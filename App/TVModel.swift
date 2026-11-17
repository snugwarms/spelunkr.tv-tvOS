import AVFoundation
import Combine
import MediaPlayer
import OSLog
import SpelunkrCore
import SwiftUI

@MainActor
final class TVModel: ObservableObject {
    private let logger = Logger(subsystem: "tv.spelunkr.community", category: "playback")
    let player = AVPlayer()
    let community = CommunityPlayback()
    let captions = LiveCaptions()
    private let audioPlayer = AVPlayer()
    private let service = BroadcastService()
    @Published private(set) var channels: [Channel] = []
    @Published private(set) var guide: [String: GuideEntry] = [:]
    @Published private(set) var channelErrors: [String: String] = [:]
    @Published private(set) var channel: Channel?
    @Published private(set) var playback: ResolvedPlayback?
    @Published private(set) var isLoading = true
    @Published private(set) var isTuning = false
    @Published private(set) var isBuffering = false
    @Published private(set) var isPaused = false
    @Published private(set) var error: String?
    @Published private(set) var guideError: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var favoriteIDs: Set<String>
    @Published var showsSidebar = true
    @Published var showsSchedule = false
    @Published var showsNativeControls = false {
        didSet { logger.notice("Native controls requested: \(self.showsNativeControls)") }
    }
    @Published private(set) var videoAspectRatio: CGFloat = 4 / 3
    @Published private(set) var schedule: [String: [Program]] = [:]
    @Published private(set) var scheduleStart = Date()
    @Published private(set) var isLoadingSchedule = false
    private var scheduleRequest = UUID()
    @Published var showsAbout = false
    @Published private(set) var isUsingSavedGuide = false

    private var previousChannelID: String?
    private var tuneTask: Task<Void, Never>?
    private var transitionTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    private var statusObservation: NSKeyValueObservation?
    private var controlObservation: NSKeyValueObservation?
    private var endedObservation: NSObjectProtocol?
    private var failedObservation: NSObjectProtocol?
    private var generation = UUID()
    private var foreground = true
    private var usedFallback = false
    private var internalPlayerChange = true
    private var liveBoundaryObserver: Any?
    private var retryCount = 0
    private var started = false

    init() {
        favoriteIDs = Set(UserDefaults.standard.stringArray(forKey: "favoriteChannels") ?? [])
        player.automaticallyWaitsToMinimizeStalling = true
        liveBoundaryObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 1000), queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.enforceLiveBoundary() }
        }
        controlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let waiting = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
            Task { @MainActor [weak self] in self?.bufferingChanged(waiting) }
        }
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in Task { @MainActor [weak self] in self?.resumePlayback() }; return .success }
        commands.pauseCommand.addTarget { [weak self] _ in Task { @MainActor [weak self] in self?.pause(source: "system remote command") }; return .success }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor [weak self] in self?.togglePause() }; return .success }
        commands.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor [weak self] in self?.surf(1) }; return .success }
        commands.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor [weak self] in self?.surf(-1) }; return .success }
        commands.changePlaybackPositionCommand.isEnabled = false
    }

    var orderedChannels: [Channel] {
        channels.sorted {
            let a = favoriteIDs.contains($0.id), b = favoriteIDs.contains($1.id)
            return a == b ? ($0.dial ?? 0) < ($1.dial ?? 0) : a
        }
    }
    var canFlipBack: Bool { previousChannelID != nil }

    func start() async {
        guard !started else { return }
        started = true
        configureAudio()
        await refresh()
        if channel == nil, let first = channels.first(where: { $0.id == UserDefaults.standard.string(forKey: "lastChannel") }) ?? channels.first {
            tune(first)
        }
        startRefreshLoop()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false; isLoading = false }
        do {
            let lineup = try await service.lineup(force: true)
            channels = lineup.availableChannels
            isUsingSavedGuide = await service.usingCachedLineup
            guideError = nil
            let at = Date(), service = service
            // A failed channel keeps its row and retries at the next refresh.
            await withTaskGroup(of: (String, GuideEntry?, String?).self) { group in
                for entry in channels {
                    group.addTask {
                        do { return (entry.id, try await service.guide(channel: entry, at: at), nil) }
                        catch { return (entry.id, nil, error.localizedDescription) }
                    }
                }
                for await (id, result, message) in group {
                    if let result { guide[id] = result; channelErrors[id] = nil }
                    else { channelErrors[id] = message }
                }
            }
            if let current = channel {
                if let updated = channels.first(where: { $0.id == current.id }) {
                    let changed = updated.versions != current.versions
                    channel = updated
                    if changed, foreground { tune(updated) }
                } else if let first = channels.first { tune(first) }
            }
            if showsSchedule { await loadSchedule(start: scheduleStart) }
        } catch { guideError = error.localizedDescription }
    }

    func tune(_ selected: Channel, resetRetry: Bool = true) {
        logger.debug("Tune \(selected.id, privacy: .public)")
        tuneTask?.cancel(); transitionTask?.cancel(); recoveryTask?.cancel(); watchdogTask?.cancel()
        let token = UUID()
        generation = token
        internalPlayerChange = true
        if channel?.id != selected.id {
            previousChannelID = channel?.id
            channel = selected
            UserDefaults.standard.set(selected.id, forKey: "lastChannel")
        }
        if resetRetry { retryCount = 0 }
        player.pause(); audioPlayer.pause()
        captions.bind(nil)
        player.replaceCurrentItem(with: nil); audioPlayer.replaceCurrentItem(with: nil)
        clearObservers()
        playback = nil; error = nil; isTuning = true; usedFallback = false
        tuneTask = Task { [weak self] in
            guard let self else { return }
            do {
                let resolved = try await service.tune(channel: selected)
                try Task.checkCancellation()
                guard generation == token, foreground else { return }
                // Metadata or a slow network can cross a station-break boundary.
                guard resolved.plan.program.end > Date() else { tune(selected); return }
                playback = resolved
                community.watch(videoID: resolved.plan.program.type == "video" ? resolved.plan.archiveID : nil,
                                sessionKey: "\(selected.id):\(resolved.plan.program.key)") { [weak self] in
                    guard let self, !isPaused, player.timeControlStatus == .playing else { return nil }
                    let time = player.currentTime().seconds
                    return time.isFinite ? time : nil
                }
                isTuning = false
                setNowPlaying()
                scheduleTransition(resolved.plan, token: token)
                if let url = resolved.mediaURL { installVideo(url, token: token) }
                else if let url = resolved.audioURL { installAudio(url, token: token) }
            } catch is CancellationError { }
            catch {
                guard generation == token, foreground else { return }
                isTuning = false
                self.error = error.localizedDescription
                scheduleRecovery(token: token)
            }
        }
    }

    private func installVideo(_ url: URL, token: UUID) {
        clearObservers()
        let item = AVPlayerItem(url: url)
        if let plan = playback?.plan {
            let title = AVMutableMetadataItem()
            title.identifier = .commonIdentifierTitle
            title.value = plan.program.title as NSString
            let subtitle = AVMutableMetadataItem()
            subtitle.identifier = .iTunesMetadataTrackSubTitle
            subtitle.value = (channel?.name ?? "Spelunkr") as NSString
            item.externalMetadata = [title, subtitle]
        }
        item.preferredForwardBufferDuration = 8
        player.replaceCurrentItem(with: item)
        captions.bind(item)
        isBuffering = true
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self, generation == token, player.currentItem === item else { return }
                switch item.status {
                case .readyToPlay:
                    let size = item.presentationSize
                    if size.height > 0 { videoAspectRatio = size.width / size.height }
                    guard let plan = playback?.plan else { return }
                    guard plan.program.end > Date() else { if let channel { tune(channel) }; return }
                    let target = plan.inPoint + plan.offset(at: Date())
                    player.seek(to: CMTime(seconds: target, preferredTimescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] completed in
                        Task { @MainActor [weak self] in
                            guard let self, generation == token, completed, foreground else { return }
                            isBuffering = false; error = nil; watchdogTask?.cancel()
                            internalPlayerChange = false
                            if !isPaused { player.play() }
                        }
                    }
                case .failed: videoFailed(token: token)
                default: break
                }
            }
        }
        failedObservation = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.videoFailed(token: token) }
        }
        endedObservation = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, generation == token else { return }
                if let plan = playback?.plan, plan.program.end.timeIntervalSinceNow > 2 {
                    isBuffering = false
                    error = "This tape ended early. The next program will tune automatically."
                } else if let channel { tune(channel) }
            }
        }
        watchdogTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(25))
            guard !Task.isCancelled, let self, generation == token, isBuffering else { return }
            videoFailed(token: token)
        }
    }

    private func videoFailed(token: UUID) {
        guard generation == token, foreground else { return }
        watchdogTask?.cancel()
        if !usedFallback, let url = playback?.fallbackURL {
            usedFallback = true
            installVideo(url, token: token)
        } else {
            isBuffering = false
            error = "The tape could not be played. Retrying shortly…"
            scheduleRecovery(token: token)
        }
    }

    private func bufferingChanged(_ waiting: Bool) {
        isBuffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        if player.timeControlStatus == .playing { isPaused = false }
        else if player.timeControlStatus == .paused, foreground, !internalPlayerChange, !isTuning, playback?.plan.isVideo == true {
            isPaused = true
        }
        guard waiting, !isPaused, foreground, playback?.plan.isVideo == true else { return }
        let token = generation
        watchdogTask?.cancel()
        watchdogTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(25))
            guard !Task.isCancelled, let self, generation == token, isBuffering else { return }
            videoFailed(token: token)
        }
    }

    private func installAudio(_ url: URL, token: UUID) {
        let item = AVPlayerItem(url: url)
        audioPlayer.replaceCurrentItem(with: item)
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self, generation == token, item.status == .readyToPlay, let plan = playback?.plan else { return }
                audioPlayer.seek(to: CMTime(seconds: plan.audioInPoint + plan.offset(at: Date()), preferredTimescale: 1000)) { [weak self] done in
                    Task { @MainActor [weak self] in
                        guard let self, generation == token, done, !isPaused, foreground else { return }
                        audioPlayer.play()
                    }
                }
            }
        }
    }

    private func scheduleTransition(_ plan: PlaybackPlan, token: UUID) {
        transitionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0.05, plan.program.end.timeIntervalSinceNow)))
            guard !Task.isCancelled, let self, generation == token, foreground, let channel else { return }
            tune(channel)
        }
    }

    private func scheduleRecovery(token: UUID) {
        recoveryTask?.cancel()
        retryCount += 1
        let delay = min(30, 5 * retryCount)
        recoveryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, generation == token, foreground, let channel else { return }
            tune(channel, resetRetry: false)
        }
    }

    func togglePause() { isPaused ? resumePlayback() : pause() }
    func resumePlayback() {
        isPaused = false
        if playback?.plan.isVideo == true { player.play() }
        else { audioPlayer.play() }
        MPNowPlayingInfoCenter.default().playbackState = .playing
    }
    func pause(source: String = "app control") {
        logger.debug("Pause from \(source, privacy: .public)")
        isPaused = true
        player.pause(); audioPlayer.pause()
        MPNowPlayingInfoCenter.default().playbackState = .paused
    }
    func resumeLive() {
        logger.debug("Resume live")
        isPaused = false
        if let channel { tune(channel) }
    }
    func retry() {
        if let channel { tune(channel) }
        else { Task { await refresh(); if let first = channels.first { tune(first) } } }
    }
    func surf(_ direction: Int) {
        guard !channels.isEmpty else { return }
        let index = channels.firstIndex(where: { $0.id == channel?.id }) ?? 0
        tune(channels[(index + direction + channels.count) % channels.count])
    }
    func flipBack() {
        if let previous = channels.first(where: { $0.id == previousChannelID }) { tune(previous) }
    }
    func toggleFavorite(_ id: String) {
        if favoriteIDs.contains(id) { favoriteIDs.remove(id) } else { favoriteIDs.insert(id) }
        UserDefaults.standard.set(favoriteIDs.sorted(), forKey: "favoriteChannels")
    }
    func setActive(_ active: Bool) {
        logger.debug("App active: \(active)")
        foreground = active
        if active {
            configureAudio()
            if let channel { tune(channel) }
            startRefreshLoop()
        } else {
            generation = UUID()
            tuneTask?.cancel(); transitionTask?.cancel(); recoveryTask?.cancel(); watchdogTask?.cancel(); refreshTask?.cancel()
            player.pause(); audioPlayer.pause()
            community.watch(videoID: nil, clock: { nil })
        }
    }
    private func startRefreshLoop() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled, let self, foreground else { return }
                await refresh()
            }
        }
    }
    private func configureAudio() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
    }
    private func setNowPlaying() {
        guard let playback, let channel else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: playback.plan.program.title,
            MPMediaItemPropertyArtist: channel.name,
            MPNowPlayingInfoPropertyIsLiveStream: true
        ]
        MPNowPlayingInfoCenter.default().playbackState = isPaused ? .paused : .playing
    }
    private func clearObservers() {
        statusObservation = nil
        if let endedObservation { NotificationCenter.default.removeObserver(endedObservation) }
        if let failedObservation { NotificationCenter.default.removeObserver(failedObservation) }
        endedObservation = nil; failedObservation = nil
    }

    private func enforceLiveBoundary() {
        guard foreground, !isTuning, !internalPlayerChange, let plan = playback?.plan,
              plan.isVideo, player.currentItem?.status == .readyToPlay else { return }
        let position = player.currentTime().seconds
        let ceiling = plan.livePosition(at: Date())
        guard position.isFinite, position > ceiling + 0.08 else { return }
        let shouldPlay = !isPaused
        let token = generation
        internalPlayerChange = true
        player.rate = 0
        player.seek(to: CMTime(seconds: ceiling, preferredTimescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, generation == token else { return }
                internalPlayerChange = false
                if shouldPlay { player.play() }
            }
        }
    }

    var guideVisible: Bool { showsSidebar || showsSchedule }
    func openMiniGuide() { showsSchedule = false; showsSidebar = true; showsNativeControls = false }
    func openFullGuide() {
        showsSidebar = false; showsSchedule = true
        showsNativeControls = false
        Task { await loadSchedule() }
    }
    func closeGuides() { showsSidebar = false; showsSchedule = false; showsNativeControls = false }
    func backFromGuide() {
        if showsSchedule { openMiniGuide() }
        else { closeGuides() }
    }

    func loadSchedule(start: Date? = nil) async {
        let token = UUID()
        scheduleRequest = token
        let at = start ?? Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970 / 1800) * 1800)
        scheduleStart = at
        isLoadingSchedule = true
        var rows: [String: [Program]] = [:]
        let service = service
        await withTaskGroup(of: (String, [Program]).self) { group in
            for channel in channels {
                group.addTask {
                    let programs = (try? await service.timeline(channel: channel, start: at, end: at.addingTimeInterval(7200))) ?? []
                    return (channel.id, programs)
                }
            }
            for await (id, programs) in group { rows[id] = programs }
        }
        guard scheduleRequest == token else { return }
        schedule = rows
        isLoadingSchedule = false
    }
}
