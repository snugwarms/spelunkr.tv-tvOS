import AVFoundation
import Combine
import Speech

@MainActor
final class LiveCaptions: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var usesNativeSubtitles = false
    @Published private(set) var text = ""
    @Published private(set) var status: String?
    @Published private(set) var lastTextAt = Date.distantPast
    private weak var item: AVPlayerItem?
    private var startTask: Task<Void, Never>?
    private var seekTask: Task<Void, Never>?
    private var recognition: AnyObject?
    private var jumpObserver: NSObjectProtocol?
    private var generation = UUID()
    private var isPlaybackReady = false
    private var nativeGroup: AVMediaSelectionGroup?
    private var nativeOption: AVMediaSelectionOption?
    private let defaults: UserDefaults
    private var preferredLanguage: String
    private var preferredName: String?
    private var prefersGenerated: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: "automaticCaptions")
        preferredLanguage = defaults.string(forKey: "subtitleLanguage") ?? "en"
        preferredName = defaults.string(forKey: "subtitleName")
        prefersGenerated = defaults.object(forKey: "subtitleGenerated") as? Bool ?? true
    }

    var supportedOS: Bool {
        if #available(tvOS 26.0, *) { return true }
        return false
    }

    func toggle() {
        isEnabled.toggle()
        defaults.set(isEnabled, forKey: "automaticCaptions")
        restart()
    }

    func bind(_ item: AVPlayerItem?) {
        guard self.item !== item else { return }
        stop()
        self.item = item
        isPlaybackReady = false
        nativeGroup = nil
        usesNativeSubtitles = false
    }

    func playbackReady() {
        guard !isPlaybackReady, item?.status == .readyToPlay else { return }
        isPlaybackReady = true
        restart()
    }

    /// AVKit calls this for user choices, including Off; app-driven selection does not persist a new choice.
    func userSelected(_ option: AVMediaSelectionOption?, in group: AVMediaSelectionGroup) {
        guard nativeGroup?.isEqual(group) == true || group.options.contains(where: { $0.hasMediaCharacteristic(.legible) }) else { return }
        stop(deselectNative: false)
        nativeGroup = group
        nativeOption = option
        usesNativeSubtitles = true
        isEnabled = option != nil
        defaults.set(isEnabled, forKey: "automaticCaptions")
        if let option {
            preferredLanguage = option.extendedLanguageTag ?? option.locale?.identifier ?? "en"
            preferredName = option.displayName
            prefersGenerated = isGenerated(option)
            defaults.set(preferredLanguage, forKey: "subtitleLanguage")
            defaults.set(preferredName, forKey: "subtitleName")
            defaults.set(prefersGenerated, forKey: "subtitleGenerated")
        }
    }

    private func stop(deselectNative: Bool = true) {
        generation = UUID()
        startTask?.cancel(); seekTask?.cancel()
        if let jumpObserver { NotificationCenter.default.removeObserver(jumpObserver) }
        jumpObserver = nil
        if let recognition, #available(tvOS 26.0, *), let session = recognition as? CaptionRecognitionSession { session.stop() }
        recognition = nil
        if deselectNative, let item, let nativeGroup, let nativeOption,
           item.currentMediaSelection.selectedMediaOption(in: nativeGroup) === nativeOption {
            item.select(nil, in: nativeGroup)
        }
        nativeOption = nil
        text = ""; status = nil
    }

    private func restart() {
        stop()
        guard isPlaybackReady, let item, item.status == .readyToPlay else { return }
        let token = generation
        status = isEnabled ? "Preparing subtitles…" : nil
        startTask = Task { [weak self] in
            guard let self else { return }
            do {
                // Discover native subtitles even when Off, so only one subtitle control is shown.
                let group = try? await item.asset.loadMediaSelectionGroup(for: .legible)
                try Task.checkCancellation()
                guard generation == token else { return }
                nativeGroup = group
                let available: [AVMediaSelectionOption]
                if let group, #available(tvOS 27.0, *) { available = item.selectableMediaSelectionOptions(in: group) }
                else { available = group?.options ?? [] }
                let options = available.filter { !$0.hasMediaCharacteristic(.containsOnlyForcedSubtitles) }
                usesNativeSubtitles = !options.isEmpty
                if let group, !options.isEmpty {
                    let option = isEnabled ? preferredOption(in: options) : nil
                    nativeOption = option
                    item.select(option, in: group)
                    status = nil
                    return
                }
                guard isEnabled else { status = nil; return }
                guard #available(tvOS 26.0, *) else {
                    status = "Automatic captions require tvOS 26 or later."
                    return
                }
                try Task.checkCancellation()
                guard generation == token else { return }
                let session = try await CaptionRecognitionSession(item: item,
                    onStatus: { [weak self] message in
                        guard let self, generation == token else { return }
                        status = message
                    },
                    onText: { [weak self] value in
                        guard let self, generation == token else { return }
                        text = value; lastTextAt = Date(); status = nil
                    },
                    onError: { [weak self] message in
                        guard let self, generation == token else { return }
                        text = ""; status = message
                    })
                guard !Task.isCancelled, generation == token else { session.stop(); return }
                recognition = session
                status = nil
                jumpObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemTimeJumped, object: item, queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.restartAfterSeek() }
                }
            } catch is CancellationError { }
            catch {
                guard generation == token else { return }
                status = error.localizedDescription
            }
        }
    }

    private func preferredOption(in options: [AVMediaSelectionOption]) -> AVMediaSelectionOption? {
        func matchesLanguage(_ option: AVMediaSelectionOption) -> Bool {
            let tag = option.extendedLanguageTag ?? option.locale?.identifier ?? ""
            return tag.caseInsensitiveCompare(preferredLanguage) == .orderedSame ||
                tag.split(whereSeparator: { $0 == "-" || $0 == "_" }).first?.lowercased() ==
                preferredLanguage.split(whereSeparator: { $0 == "-" || $0 == "_" }).first?.lowercased()
        }
        return options.first { matchesLanguage($0) && $0.displayName == preferredName && isGenerated($0) == prefersGenerated }
            ?? options.first { matchesLanguage($0) && isGenerated($0) == prefersGenerated }
            ?? options.first(where: matchesLanguage)
            ?? options.first
    }

    private func isGenerated(_ option: AVMediaSelectionOption) -> Bool {
        if #available(tvOS 26.0, *) { return option.hasMediaCharacteristic(.machineGenerated) }
        return false
    }

    private func restartAfterSeek() {
        seekTask?.cancel()
        seekTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.restart()
        }
    }
}

private enum CaptionError: LocalizedError {
    case unavailable, language, audio
    var errorDescription: String? {
        switch self {
        case .unavailable: return "Automatic captions are not supported on this Apple TV."
        case .language: return "The English speech model is not available on this Apple TV."
        case .audio: return "Automatic captions could not access this tape’s audio."
        }
    }
}

@available(tvOS 26.0, *)
@MainActor
private final class CaptionRecognitionSession {
    private let analyzer: SpeechAnalyzer
    private let continuation: AsyncStream<AnalyzerInput>.Continuation
    private var resultsTask: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?
    private var audioTap: PlaybackAudioTap?

    init(item: AVPlayerItem, onStatus: @escaping (String) -> Void,
         onText: @escaping (String) -> Void, onError: @escaping (String) -> Void) async throws {
        guard SpeechTranscriber.isAvailable else { throw CaptionError.unavailable }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US")) else { throw CaptionError.language }
        let transcriber = SpeechTranscriber(locale: locale, preset: .timeIndexedProgressiveTranscription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            onStatus("Downloading the on-device speech model…")
            try await request.downloadAndInstall()
        }
        try Task.checkCancellation()
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else { throw CaptionError.audio }
        analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.prepareToAnalyze(in: format)
        let stream = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingNewest(64))
        continuation = stream.continuation
        let feed = stream.continuation
        audioTap = try await PlaybackAudioTap.attach(to: item, targetFormat: format) { buffer, time in
            feed.yield(AnalyzerInput(buffer: buffer, bufferStartTime: time))
        }
        let analyzer = analyzer
        analysisTask = Task {
            do { try await analyzer.start(inputSequence: stream.stream) }
            catch { if !Task.isCancelled { onError("Automatic captions could not start. Try switching them off and on.") } }
        }
        resultsTask = Task {
            do {
                for try await result in transcriber.results {
                    guard !Task.isCancelled else { return }
                    let value = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty { onText(value) }
                }
            } catch {
                if !Task.isCancelled { onError("Automatic captions stopped. Try switching them off and on.") }
            }
        }
    }

    func stop() {
        continuation.finish()
        resultsTask?.cancel(); analysisTask?.cancel()
        audioTap?.stopCaptions()
        audioTap = nil
        let analyzer = analyzer
        Task { await analyzer.cancelAndFinishNow() }
    }
}
