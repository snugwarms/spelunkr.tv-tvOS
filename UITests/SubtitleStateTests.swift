import AVFoundation
import XCTest

@MainActor
final class SubtitleStateTests: XCTestCase {
    private struct PreparedPlayer {
        let player: AVPlayer
        let item: AVPlayerItem
        let group: AVMediaSelectionGroup
    }

    private func preparedPlayer(_ captions: LiveCaptions, allowsAudioProcessing: Bool = true) async throws -> PreparedPlayer {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "subtitles", withExtension: "mp4"))
        let item = AVPlayerItem(url: url)
        let loadedGroup = try await item.asset.loadMediaSelectionGroup(for: .legible)
        let group = try XCTUnwrap(loadedGroup)
        let player = AVPlayer(playerItem: item)
        captions.bind(item, allowsAudioProcessing: allowsAudioProcessing)
        for _ in 0..<250 {
            if item.status != .unknown { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(item.status, .readyToPlay)
        captions.playbackReady()
        for _ in 0..<250 {
            if captions.usesNativeSubtitles { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(captions.usesNativeSubtitles, "Native tracks must suppress the extra app subtitle control, including when Off")
        return PreparedPlayer(player: player, item: item, group: group)
    }

    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "SubtitleTests-\(UUID().uuidString)")!
    }

    func testNativeSubtitlesUseOneControlAndRestoreLanguage() async throws {
        let defaults = isolatedDefaults()
        let captions = LiveCaptions(defaults: defaults)
        let original = try await preparedPlayer(captions)
        let spanish = try XCTUnwrap(original.group.options.first { $0.extendedLanguageTag?.hasPrefix("es") == true })
        original.item.select(spanish, in: original.group)
        captions.userSelected(spanish, in: original.group)
        XCTAssertTrue(captions.isEnabled)
        captions.bind(nil)

        let restored = LiveCaptions(defaults: defaults)
        XCTAssertTrue(restored.isEnabled)
        let next = try await preparedPlayer(restored)
        let selection = try XCTUnwrap(next.item.currentMediaSelection.selectedMediaOption(in: next.group))
        XCTAssertTrue(selection.extendedLanguageTag?.hasPrefix("es") == true)
        XCTAssertEqual(selection.displayName, spanish.displayName)
        XCTAssertFalse(defaults.bool(forKey: "subtitleGenerated"))
        restored.bind(nil)
        withExtendedLifetime((original.player, next.player)) {}
    }

    func testNativeOffSurvivesNewPlayerItem() async throws {
        let defaults = isolatedDefaults()
        defaults.set(true, forKey: "automaticCaptions")
        let captions = LiveCaptions(defaults: defaults)
        let original = try await preparedPlayer(captions)
        XCTAssertNotNil(original.item.currentMediaSelection.selectedMediaOption(in: original.group))
        original.item.select(nil, in: original.group)
        captions.userSelected(nil, in: original.group)
        captions.bind(nil)

        let restored = LiveCaptions(defaults: defaults)
        XCTAssertFalse(restored.isEnabled)
        let next = try await preparedPlayer(restored)
        XCTAssertNil(next.item.currentMediaSelection.selectedMediaOption(in: next.group))
        restored.bind(nil)
        withExtendedLifetime((original.player, next.player)) {}
    }

    func testAudioSelectionDoesNotEnableSubtitles() async throws {
        let defaults = isolatedDefaults()
        let captions = LiveCaptions(defaults: defaults)
        let source = try await preparedPlayer(captions)
        let loadedAudio = try await source.item.asset.loadMediaSelectionGroup(for: .audible)
        let audio = try XCTUnwrap(loadedAudio)
        captions.userSelected(try XCTUnwrap(audio.options.first), in: audio)
        XCTAssertFalse(captions.isEnabled)
        XCTAssertFalse(defaults.bool(forKey: "automaticCaptions"))
        captions.bind(nil)
        withExtendedLifetime(source.player) {}
    }

    func testCompatibilityPlaybackKeepsNativeSubtitlesWithoutAnAudioTap() async throws {
        let defaults = isolatedDefaults()
        defaults.set(true, forKey: "automaticCaptions")
        let captions = LiveCaptions(defaults: defaults)
        let source = try await preparedPlayer(captions, allowsAudioProcessing: false)
        XCTAssertNotNil(source.item.currentMediaSelection.selectedMediaOption(in: source.group))
        XCTAssertNil(source.item.audioMix)
        XCTAssertTrue(captions.isEnabled)
        XCTAssertTrue(defaults.bool(forKey: "automaticCaptions"))
        captions.bind(nil)
        withExtendedLifetime(source.player) {}
    }

    func testCompatibilityPlaybackDoesNotRecreateTheSpeechAudioTap() async throws {
        let defaults = isolatedDefaults()
        defaults.set(true, forKey: "automaticCaptions")
        let captions = LiveCaptions(defaults: defaults)
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "no-subtitles", withExtension: "mp4"))
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        captions.bind(item, allowsAudioProcessing: false)
        for _ in 0..<250 {
            if item.status != .unknown { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(item.status, .readyToPlay)
        captions.playbackReady()
        for _ in 0..<250 {
            if captions.status?.contains("compatibility") == true { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(captions.status?.contains("compatibility") == true)
        XCTAssertNil(item.audioMix)
        XCTAssertTrue(captions.isEnabled, "Keep the preference for later recordings")
        captions.toggle()
        XCTAssertFalse(captions.isEnabled, "The viewer can still turn captions off")
        captions.bind(nil)
        withExtendedLifetime(player) {}
    }
}
