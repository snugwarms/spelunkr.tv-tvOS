import XCTest
@testable import SpelunkrCore

final class BroadcastServiceTests: XCTestCase {
    private static let lineup = Data("""
    {"engine":5,"generatedAt":"2026-11-17T00:00:00Z","channels":[
    {"id":"test","name":"TEST","dial":2,"versions":[{"v":1,"manifest":"manifests/test/v1.json","epochMs":0}]}]}
    """.utf8)

    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BroadcastMockProtocol.self]
        return URLSession(configuration: config)
    }

    func testFallsBackToWebsiteWhenDataHostIsUnavailable() async throws {
        BroadcastMockProtocol.handler = { request in
            if request.url!.host == "data.example" { return (403, Data()) }
            return (200, Self.lineup)
        }
        let service = BroadcastService(session: session(), roots: [URL(string: "https://data.example/")!, URL(string: "https://website.example/broadcast/")!])
        let lineup = try await service.lineup()
        XCTAssertEqual(lineup.availableChannels.map(\.id), ["test"])
        let cached = await service.usingCachedLineup
        XCTAssertFalse(cached)
    }

    func testKeepsLoadedLineupDuringAnOutage() async throws {
        BroadcastMockProtocol.handler = { _ in (200, Self.lineup) }
        let service = BroadcastService(session: session(), roots: [URL(string: "https://data.example/")!])
        _ = try await service.lineup()
        BroadcastMockProtocol.handler = { _ in (503, Data()) }
        let lineup = try await service.lineup(force: true)
        XCTAssertEqual(lineup.availableChannels.count, 1)
        let cached = await service.usingCachedLineup
        XCTAssertTrue(cached)
    }

    func testLiveHostIsRetriedAfterSnapshotFallback() async throws {
        var liveAvailable = false
        BroadcastMockProtocol.handler = { request in
            if request.url?.host == "live.example" {
                return liveAvailable ? (200, Data(String(decoding: Self.lineup, as: UTF8.self).replacingOccurrences(of: "2026-11-17T00:00:00Z", with: "live").utf8)) : (503, Data())
            }
            return (200, Self.lineup)
        }
        let service = BroadcastService(session: session(), roots: [URL(string: "https://live.example/")!, URL(string: "https://snapshot.example/")!])
        _ = try await service.lineup()
        liveAvailable = true
        let recovered = try await service.lineup(force: true)
        XCTAssertEqual(recovered.generatedAt, "live")
    }

    func testRejectsNewEngineInsteadOfPlayingTheWrongSchedule() async throws {
        BroadcastMockProtocol.handler = { _ in (200, Data(String(decoding: Self.lineup, as: UTF8.self).replacingOccurrences(of: "\"engine\":5", with: "\"engine\":6").utf8)) }
        let service = BroadcastService(session: session(), roots: [URL(string: "https://data.example/")!])
        do { _ = try await service.lineup(); XCTFail("Expected unsupported engine") }
        catch BroadcastError.unsupportedEngine(let version) { XCTAssertEqual(version, 6) }
    }

    func testBroadcastOriginHeadersPreventForbiddenResponsesWithoutLeakingToArchive() async throws {
        let requests = AssetRequestCounter()
        BroadcastMockProtocol.handler = { request in
            requests.increment()
            if request.url?.host == "archive.org" {
                XCTAssertNil(request.value(forHTTPHeaderField: "Origin"))
                XCTAssertNil(request.value(forHTTPHeaderField: "Referer"))
                return (200, Data("""
                {"server":"ia800100.us.archive.org","dir":"/12/items/tape","files":[{"name":"tape.mp4","format":"h.264"}]}
                """.utf8))
            }
            // Model the observed rejection when the site origin is missing.
            guard request.value(forHTTPHeaderField: "Origin") == "https://spelunkr.tv",
                  request.value(forHTTPHeaderField: "Referer") == "https://spelunkr.tv/" else { return (403, Data()) }
            if request.url?.lastPathComponent == "lineup.json" { return (200, Self.lineup) }
            return (200, Data("""
            {"engine":5,"items":[{"id":"tape","title":"Tape","duration":3600,"mp4":"tape.mp4"}]}
            """.utf8))
        }
        for host in ["data.spelunkr.tv", "spelunkr.tv"] {
            let service = BroadcastService(session: session(), roots: [URL(string: "https://\(host)/")!])
            let lineup = try await service.lineup()
            let channel = try XCTUnwrap(lineup.availableChannels.first)
            let resolved = try await service.tune(channel: channel, at: Date(timeIntervalSince1970: 1000))
            XCTAssertEqual(resolved.mediaURL?.host, "ia800100.us.archive.org")
        }
        XCTAssertEqual(requests.value, 6, "No extra probe or polling requests are needed")
    }

    func testConcurrentGuideReadersShareFetchAndRecoverAfterFailure() async throws {
        let requests = AssetRequestCounter()
        let manifest = Data("""
        {"engine":5,"items":[{"id":"tape","title":"Tape","duration":3600,"mp4":"tape.mp4"}]}
        """.utf8)
        func respond(status: Int) {
            BroadcastMockProtocol.handler = { request in
                if request.url!.lastPathComponent == "lineup.json" { return (200, Self.lineup) }
                requests.increment()
                // Keep the response pending until the other guide readers have joined it.
                Thread.sleep(forTimeInterval: 0.1)
                return (status, manifest)
            }
        }
        respond(status: 503)
        let service = BroadcastService(session: session(), roots: [URL(string: "https://data.example/")!])
        let lineup = try await service.lineup()
        let channel = try XCTUnwrap(lineup.availableChannels.first)
        func readTogether() async -> [Bool] {
            await withTaskGroup(of: Bool.self) { group in
                for _ in 0..<18 {
                    group.addTask {
                        do { return try await service.guide(channel: channel, at: Date(timeIntervalSince1970: 1000)).current.id == "tape" }
                        catch { return false }
                    }
                }
                var values: [Bool] = []
                for await value in group { values.append(value) }
                return values
            }
        }
        let failed = await readTogether()
        XCTAssertEqual(failed, Array(repeating: false, count: 18))
        XCTAssertEqual(requests.value, 1, "All readers must receive the same failed fetch")
        respond(status: 200)
        let recovered = await readTogether()
        XCTAssertEqual(recovered, Array(repeating: true, count: 18))
        XCTAssertEqual(requests.value, 2, "A failed shared fetch must clear so the next attempt can succeed")
    }
}

private final class AssetRequestCounter {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}

private final class BroadcastMockProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, data) = Self.handler!(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
