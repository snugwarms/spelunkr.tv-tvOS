import AVFoundation
import SpelunkrCore
import XCTest

/// Exercises TVModel itself; the local relay only substitutes the remote transport.
@MainActor
final class PlayerRecoveryTests: XCTestCase {
    private final class SeekStatus { var completed: Bool? }
    private func makeModel(primaryPath: String, allCopiesFail: Bool = false) throws -> (TVModel, () -> [String]) {
        guard ProcessInfo.processInfo.environment["SPELUNKR_LIVE_PLAYBACK_TESTS"] == "1",
              let proxy = ProcessInfo.processInfo.environment["SPELUNKR_MEDIA_PROXY"], let base = URL(string: proxy) else {
            throw XCTSkip("Opt-in local-relay recovery check")
        }
        let epoch = floor((Date().timeIntervalSince1970 - 1237) * 1000)
        PlayerRecoveryProtocol.handler = { request in
            if request.url?.host == "archive.org" {
                return Data("""
                {"server":"ia-primary.us.archive.org","d1":"ia-backup.us.archive.org","dir":"/0/items/tape"}
                """.utf8)
            }
            if request.url?.lastPathComponent == "lineup.json" {
                return Data("""
                {"engine":5,"generatedAt":"test","channels":[{"id":"test","name":"TEST","dial":2,
                "versions":[{"v":1,"manifest":"manifests/test/v1.json","epochMs":\(epoch)}]}]}
                """.utf8)
            }
            return Data("""
            {"engine":5,"items":[{"id":"tape","title":"Recovery fixture","duration":2867,"mp4":"tape.mp4"}]}
            """.utf8)
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PlayerRecoveryProtocol.self]
        let service = BroadcastService(session: URLSession(configuration: config), roots: [URL(string: "https://feed.example/")!])
        var attempts: [String] = []
        let run = UUID().uuidString
        let model = TVModel(service: service, mediaURLTransform: { url in
            attempts.append(url.host ?? "")
            let path = allCopiesFail ? "fail.mp4" : url.host == "ia-primary.us.archive.org" ? primaryPath : "sons.mp4"
            var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "run", value: run)]
            return components.url!
        })
        model.community.showsComments = false
        model.community.showsReactions = false
        model.player.isMuted = true
        if model.captions.isEnabled { model.captions.toggle() }
        return (model, { attempts })
    }

    private func waitForPlayback(_ model: TVModel, timeout: Int) async throws {
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: nil)
        var outputItem: AVPlayerItem?
        var lastFrame = -Double.infinity
        var movingFrames = 0
        for _ in 0..<(timeout * 10) {
            if let item = model.player.currentItem, item !== outputItem {
                outputItem?.remove(output)
                item.add(output)
                outputItem = item
            }
            let time = model.player.currentTime()
            if output.hasNewPixelBuffer(forItemTime: time) {
                var displayed = CMTime.invalid
                if output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: &displayed) != nil,
                   displayed.seconds > 1237, displayed.seconds > lastFrame {
                    movingFrames += 1
                    lastFrame = displayed.seconds
                }
            }
            let lag = model.playback?.plan.livePosition(at: Date()) ?? .infinity
            if model.player.timeControlStatus == .playing, movingFrames >= 2,
               abs(lastFrame - time.seconds) < 1, lag - time.seconds < 8 { break }
            if model.error != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(model.player.timeControlStatus, .playing, model.error ?? "Playback did not start")
        XCTAssertGreaterThanOrEqual(movingFrames, 2, "The recording must produce advancing video frames, not just an audio clock")
        XCTAssertNil(model.error)
        outputItem?.remove(output)
        if let plan = model.playback?.plan {
            XCTAssertLessThan(plan.livePosition(at: Date()) - model.player.currentTime().seconds, 8, "Catch up after slow startup")
        }
    }

    func testProductionModelSwitchesToADistinctMirror() async throws {
        let (model, attempts) = try makeModel(primaryPath: "fail.mp4")
        let surface = AVPlayerLayer(player: model.player)
        await model.start()
        try await waitForPlayback(model, timeout: 25)
        XCTAssertEqual(attempts(), ["ia-primary.us.archive.org", "ia-backup.us.archive.org"])
        model.setActive(false)
        withExtendedLifetime(surface) {}
    }

    func testProductionModelKeepsTheSourceDuringA30SecondLiveSeek() async throws {
        let (model, attempts) = try makeModel(primaryPath: "sons-slow.mp4")
        let surface = AVPlayerLayer(player: model.player)
        let beganAt = ProcessInfo.processInfo.systemUptime
        await model.start()
        try await waitForPlayback(model, timeout: 65)
        XCTAssertGreaterThanOrEqual(ProcessInfo.processInfo.systemUptime - beganAt, 28, "The relay must actually delay every live-range request")
        XCTAssertEqual(attempts(), ["ia-primary.us.archive.org"], "The old 25-second watchdog would discard this healthy source")
        model.setActive(false)
        withExtendedLifetime(surface) {}
    }

    func testExhaustedCopiesShowClearRetryInformation() async throws {
        let (model, attempts) = try makeModel(primaryPath: "fail.mp4", allCopiesFail: true)
        let surface = AVPlayerLayer(player: model.player)
        await model.start()
        for _ in 0..<200 {
            if model.error != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertNotNil(model.playbackFailure)
        XCTAssertNotEqual(model.playbackFailure?.title, "FORMAT NOT SUPPORTED", "HTTP errors are not decoder errors")
        XCTAssertTrue(model.error?.contains("Retrying in 5 seconds") == true)
        XCTAssertEqual(attempts().count, 3)
        model.setActive(false)
        withExtendedLifetime(surface) {}
    }

    func testManualRewindIsNotForcedBackToLive() async throws {
        let (model, _) = try makeModel(primaryPath: "sons.mp4")
        let surface = AVPlayerLayer(player: model.player)
        defer { model.setActive(false) }
        await model.start()
        try await waitForPlayback(model, timeout: 25)
        model.pause()
        model.userDidNavigatePlayback()
        let result = SeekStatus()
        model.player.seek(to: CMTime(seconds: 900, preferredTimescale: 1000)) { completed in
            Task { @MainActor in result.completed = completed }
        }
        for _ in 0..<200 {
            if result.completed != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(result.completed, true)
        model.resumePlayback()
        for _ in 0..<100 {
            if model.player.currentTime().seconds > 901 { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertGreaterThan(model.player.currentTime().seconds, 901)
        XCTAssertLessThan(model.player.currentTime().seconds, 910)
        withExtendedLifetime(surface) {}
    }
}

private final class PlayerRecoveryProtocol: URLProtocol {
    static var handler: ((URLRequest) -> Data)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let data = Self.handler!(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
