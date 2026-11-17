import AVFoundation
import XCTest

/// Opt-in network checks for recordings reported on 17 November 2026.
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

    func testSonsOfPitchesPausedStartup() async throws {
        try await checkPlayback("https://dn711306.ca.archive.org/0/items/retnsap2002sonsofpitches/RETN-SAP-2002-SonsofPitches.mp4", seek: 1237, primeBeforeSeeking: false)
    }

    func testBadInfluenceEpisode10PausedStartup() async throws {
        try await checkPlayback("https://dn711102.ca.archive.org/0/items/bad_influence_se1ep10/Bad.Influence.se1ep10.mp4", seek: 748, primeBeforeSeeking: false)
    }

    func testMandatoryViewingBlockbusterPausedStartup() async throws {
        try await checkPlayback("https://dn600208.us.archive.org/0/items/blockbuster-video-training-video/blockbuster%20video%20training%20video.ia.mp4", seek: 60, primeBeforeSeeking: false)
    }

    func testLateNiteLocalHolidaySpecialPausedStartup() async throws {
        try await checkPlayback("https://dn600203.us.archive.org/0/items/ptvpny-PTV_Presents_-_The_2019_Holiday_Special/PTV_Presents_-_The_2019_Holiday_Special.mp4", seek: 720, primeBeforeSeeking: false)
    }

    func testUnpaidProgrammingCountryCollectionPausedStartup() async throws {
        try await checkPlayback("https://ia601607.us.archive.org/21/items/time-life-60s-and-70s-country-infomercials/TIME%20LIFE-%2060%27S%20COUNTRY.mp4", seek: 1200, primeBeforeSeeking: false)
    }

    private func checkPlayback(_ url: String, seek: Double, primeBeforeSeeking: Bool = true) async throws {
        guard ProcessInfo.processInfo.environment["SPELUNKR_LIVE_PLAYBACK_TESTS"] == "1" else {
            throw XCTSkip("Opt-in Archive playback check")
        }
        let sourceURL: URL
        if let proxy = ProcessInfo.processInfo.environment["SPELUNKR_MEDIA_PROXY"] {
            let name = url.contains("Holiday_Special") ? "late-nite-local" : url.contains("COUNTRY") ? "unpaid-programming" : url.contains("blockbuster") ? "mandatory" : url.contains("RETN-SAP") ? "sons" : url.contains("se1ep10") ? "bad10" : url.contains("Jam_session") ? "open-mic" : url.contains("Influence") ? "warp-zone" : "control"
            sourceURL = URL(string: proxy)!.appendingPathComponent("\(name).mp4")
        } else { sourceURL = URL(string: url)! }
        let item = AVPlayerItem(url: sourceURL)
        item.allowedAudioSpatializationFormats = []
        item.preferredForwardBufferDuration = 8
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        let surface = AVPlayerLayer(player: player)
        if primeBeforeSeeking { player.play() }
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
