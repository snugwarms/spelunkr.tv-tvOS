import AVFoundation
import Combine
import Speech
import SwiftUI

@MainActor
final class LiveCaptions: ObservableObject {
    @Published private(set) var isEnabled = UserDefaults.standard.bool(forKey: "automaticCaptions")
    @Published private(set) var text = ""
    @Published private(set) var status: String?
    @Published private(set) var lastTextAt = Date.distantPast
    private weak var item: AVPlayerItem?
    private var startTask: Task<Void, Never>?
    private var seekTask: Task<Void, Never>?
    private var recognition: AnyObject?
    private var jumpObserver: NSObjectProtocol?
    private var generation = UUID()

    var supportedOS: Bool {
        if #available(tvOS 26.0, *) { return true }
        return false
    }

    func toggle() {
        isEnabled.toggle()
        UserDefaults.standard.set(isEnabled, forKey: "automaticCaptions")
        restart()
    }

    func bind(_ item: AVPlayerItem?) {
        guard self.item !== item else { return }
        stop()
        self.item = item
        restart()
    }

    private func stop() {
        generation = UUID()
        startTask?.cancel(); seekTask?.cancel()
        if let jumpObserver { NotificationCenter.default.removeObserver(jumpObserver) }
        jumpObserver = nil
        if #available(tvOS 26.0, *), let session = recognition as? CaptionRecognitionSession { session.stop() }
        recognition = nil
        item?.audioMix = nil
        text = ""; status = nil
    }

    private func restart() {
        stop()
        guard isEnabled, let item else { return }
        guard #available(tvOS 26.0, *) else {
            status = "Automatic captions require tvOS 26 or later."
            return
        }
        let token = generation
        status = "Preparing automatic captions…"
        startTask = Task { [weak self] in
            guard let self else { return }
            do {
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
        audioTap?.stop()
        audioTap = nil
        let analyzer = analyzer
        Task { await analyzer.cancelAndFinishNow() }
    }
}

struct CaptionOverlay: View {
    @ObservedObject var captions: LiveCaptions
    @ObservedObject var community: CommunityPlayback
    var body: some View {
        GeometryReader { geometry in
            let scale = max(0.35, min(1, geometry.size.width / 1440))
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let recentText = context.date.timeIntervalSince(captions.lastTextAt) < 6 ? captions.text : ""
                let value = !recentText.isEmpty ? recentText : captions.status ?? ""
                if captions.isEnabled, !value.isEmpty {
                    VStack {
                        Spacer()
                        Text(value)
                            .accessibilityIdentifier("captionText")
                            .font(.system(size: 29 * scale, weight: .semibold))
                            .foregroundStyle(.white).multilineTextAlignment(.center).lineLimit(3)
                            .padding(.horizontal, 18 * scale).padding(.vertical, 10 * scale)
                            .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 7 * scale))
                            .frame(maxWidth: geometry.size.width * 0.82)
                            .padding(.bottom, (community.comments.isEmpty ? 50 : 230) * scale)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityLabel("Automatic captions")
    }
}
