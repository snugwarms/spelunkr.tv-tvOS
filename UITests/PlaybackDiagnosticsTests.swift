import AVFoundation
import XCTest

/// Opt-in network checks for the two recordings reported on 17 November 2026.
/// Ordinary test runs skip these so they do not repeatedly stream from Archive.
@MainActor
final class PlaybackDiagnosticsTests: XCTestCase {
    private final class SeekResult { var completed: Bool? }
    func testKnownGoodControlTape() async throws {
        try await checkPlayback("https://archive.org/download/CyberPri98/CyberPri98.mp4", seek: 300)
    }

    func testOpenMicReportedTape() async throws {
        try await checkPlayback("https://ia801902.us.archive.org/34/items/teli1ns-Jam_session_in_Judique1991/Jam_session_in_Judique1991.mp4", seek: 6803)
    }

    func testWarpZoneReportedTape() async throws {
        try await checkPlayback("https://dn710702.ca.archive.org/0/items/bad_influence_se1ep9/Bad.Influence.se1ep9.mp4", seek: 454)
    }

    private func checkPlayback(_ url: String, seek: Double) async throws {
        guard ProcessInfo.processInfo.environment["SPELUNKR_LIVE_PLAYBACK_TESTS"] == "1" else {
            throw XCTSkip("Opt-in Archive playback check")
        }
        let sourceURL: URL
        if let proxy = ProcessInfo.processInfo.environment["SPELUNKR_MEDIA_PROXY"] {
            let name = url.contains("Jam_session") ? "open-mic" : url.contains("Influence") ? "warp-zone" : "control"
            sourceURL = URL(string: proxy)!.appendingPathComponent("\(name).mp4")
        } else { sourceURL = URL(string: url)! }
        let item = AVPlayerItem(url: sourceURL)
        item.allowedAudioSpatializationFormats = []
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        let surface = AVPlayerLayer(player: player)
        player.play()
        defer { player.pause(); player.replaceCurrentItem(with: nil) }
        for _ in 0..<300 {
            if item.status != .unknown { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        print("PLAYBACK DIAGNOSTIC", url, "status", item.status.rawValue, "error", String(describing: item.error), "errorLog", String(describing: item.errorLog()?.events))
        guard item.status == .readyToPlay else { XCTFail("Tape failed to become ready: \(String(describing: item.error))"); return }
        player.pause()
        let tap = try await PlaybackAudioTap.shared(for: item)
        tap.setNormalization(true)
        defer { tap.stop() }
        let result = SeekResult()
        player.seek(to: CMTime(seconds: seek, preferredTimescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero) { complete in
            Task { @MainActor in result.completed = complete }
        }
        for _ in 0..<300 {
            if result.completed != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard result.completed == true else { XCTFail("Live-position seek did not complete: \(String(describing: item.error))"); return }
        player.play()
        for _ in 0..<300 {
            if player.currentTime().seconds > seek + 2 || item.status == .failed { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        print("PLAYBACK DIAGNOSTIC", "time", player.currentTime().seconds, "state", player.timeControlStatus.rawValue, "error", String(describing: item.error), "errorLog", String(describing: item.errorLog()?.events), "audioFrames", tap.statistics.frames)
        XCTAssertGreaterThan(player.currentTime().seconds, seek + 2, "Tape must advance after the live-position seek with normalization enabled")
        withExtendedLifetime(surface) {}
    }
}
