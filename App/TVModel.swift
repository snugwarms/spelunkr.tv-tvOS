import AVFoundation
import Combine
import MediaPlayer
import OSLog
import SpelunkrCore
import SwiftUI

// Concrete result metadata avoids a reproduced Release-only task completion abort with tuples.
private struct GuideLoadResult: Sendable {
    let id: String
    let entry: GuideEntry?
    let error: String?
}

private struct ScheduleLoadResult: Sendable {
    let id: String
    let programs: [Program]
}

@MainActor
final class TVModel: ObservableObject {
    private let logger = Logger(subsystem: "tv.spelunkr.community", category: "playback")
    let player = AVPlayer()
    let community = CommunityPlayback()
    let captions = LiveCaptions()
    @Published private(set) var normalizesVolume = UserDefaults.standard.object(forKey: "normalizesVolume") as? Bool ?? true
    private var playbackAudioTap: PlaybackAudioTap?
    private let audioPlayer = AVPlayer()
    private let service: BroadcastService
    private let mediaURLTransform: (URL) -> URL
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
    @Published private(set) var playbackFailure: PlaybackFailureInfo?
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
    @Published private var tapeSynopses: [String: String] = [:]
    private var synopsisAttempts: [String: Date] = [:]
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
    private var watchdogID = UUID()
    private var videoStartupTask: Task<Void, Never>?
    private var videoAttempt = UUID()
    private var preparedVideoAttempt: UUID?
    private var remainingMediaURLs: [URL] = []
    private var videoHasStarted = false
    private var needsStartupLiveSync = false
    private var statusObservation: NSKeyValueObservation?
    private var controlObservation: NSKeyValueObservation?
    private var audioRouteObservation: NSObjectProtocol?
    private var endedObservation: NSObjectProtocol?
    private var failedObservation: NSObjectProtocol?
    private var generation = UUID()
    private var foreground = true
    private var internalPlayerChange = true
    private var liveBoundaryObserver: Any?
    private var retryCount = 0
    private var started = false

    init(service: BroadcastService = BroadcastService(session: NetworkAudit.session), mediaURLTransform: @escaping (URL) -> URL = { $0 }) {
        self.service = service
        self.mediaURLTransform = mediaURLTransform
        favoriteIDs = Set(UserDefaults.standard.stringArray(forKey: "favoriteChannels") ?? [])
        player.automaticallyWaitsToMinimizeStalling = true
        liveBoundaryObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 1000), queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.enforceLiveBoundary() }
        }
        controlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in self?.bufferingChanged() }
        }
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in Task { @MainActor [weak self] in self?.resumePlayback() }; return .success }
        commands.pauseCommand.addTarget { [weak self] _ in Task { @MainActor [weak self] in self?.pause(source: "system remote command") }; return .success }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor [weak self] in self?.togglePause() }; return .success }
        commands.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor [weak self] in self?.surf(1) }; return .success }
        commands.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor [weak self] in self?.surf(-1) }; return .success }
        commands.changePlaybackPositionCommand.isEnabled = false
        audioRouteObservation = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.configureStereoOutput() }
        }
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
            await withTaskGroup(of: GuideLoadResult.self) { group in
                var pending = channels.makeIterator()
                func enqueue(_ entry: Channel) {
                    group.addTask {
                        do { return GuideLoadResult(id: entry.id, entry: try await service.guide(channel: entry, at: at), error: nil) }
                        catch { return GuideLoadResult(id: entry.id, entry: nil, error: error.localizedDescription) }
                    }
                }
                for _ in 0..<NetworkPolicy.concurrentGuideLoads {
                    if let entry = pending.next() { enqueue(entry) }
                }
                for await result in group {
                    if let entry = result.entry { guide[result.id] = entry; channelErrors[result.id] = nil }
                    else { channelErrors[result.id] = result.error }
                    if let entry = pending.next() { enqueue(entry) }
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
        videoStartupTask?.cancel()
        videoAttempt = UUID()
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
        playbackAudioTap?.stop(); playbackAudioTap = nil
        player.replaceCurrentItem(with: nil); audioPlayer.replaceCurrentItem(with: nil)
        clearObservers()
        playback = nil; error = nil; playbackFailure = nil; isTuning = true; remainingMediaURLs = []
        tuneTask = Task { [weak self] in
            guard let self else { return }
            do {
                let resolved = try await service.tune(channel: selected)
                try Task.checkCancellation()
                guard generation == token, foreground else { return }
                // Metadata or a slow network can cross a station-break boundary.
                guard resolved.plan.program.end > Date() else { tune(selected); return }
                playback = resolved
                remainingMediaURLs = resolved.alternateMediaURLs
                if let synopsis = resolved.synopsis { tapeSynopses[resolved.plan.program.id] = synopsis }
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
        videoAttempt = UUID()
        let attempt = videoAttempt
        videoStartupTask?.cancel()
        stopVideoWatchdog()
        clearObservers()
        internalPlayerChange = true
        videoHasStarted = false
        needsStartupLiveSync = true
        captions.bind(nil)
        playbackAudioTap?.stop(); playbackAudioTap = nil
        player.pause()
        let item = AVPlayerItem(url: mediaURLTransform(url))
        item.allowedAudioSpatializationFormats = []
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
                guard let self, generation == token, videoAttempt == attempt, player.currentItem === item else { return }
                switch item.status {
                case .readyToPlay:
                    guard preparedVideoAttempt != attempt else { return }
                    preparedVideoAttempt = attempt
                    videoStartupTask?.cancel()
                    videoStartupTask = Task { [weak self] in
                        guard let self else { return }
                        await prepareAudioProcessing(item, token: token)
                        guard !Task.isCancelled, generation == token, videoAttempt == attempt,
                              player.currentItem === item, foreground else { return }
                        let size = item.presentationSize
                        if size.height > 0 { videoAspectRatio = size.width / size.height }
                        guard let plan = playback?.plan else { return }
                        guard plan.program.end > Date() else { if let channel { tune(channel) }; return }
                        seekVideoToLive(item: item, token: token, attempt: attempt)
                    }
                case .failed: videoFailed(token: token, attempt: attempt, reason: "Player rejected the tape")
                default: break
                }
            }
        }
        failedObservation = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.videoFailed(token: token, attempt: attempt, reason: "Playback stopped") }
        }
        endedObservation = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, generation == token, videoAttempt == attempt, player.currentItem === item else { return }
                if let plan = playback?.plan, plan.program.end.timeIntervalSinceNow > 2 {
                    isBuffering = false
                    error = "This tape ended early. The next program will tune automatically."
                } else if let channel { tune(channel) }
            }
        }
        armVideoWatchdog(item: item, token: token, attempt: attempt)
    }

    private func seekVideoToLive(item: AVPlayerItem, token: UUID, attempt: UUID, catchingUp: Bool = false) {
        guard let plan = playback?.plan else { return }
        let target = plan.livePosition(at: Date())
        // Allow an earlier decodable frame without ever seeking ahead of live.
        player.seek(to: CMTime(seconds: target, preferredTimescale: 1000),
                    toleranceBefore: CMTime(seconds: 2, preferredTimescale: 1000), toleranceAfter: .zero) { [weak self] completed in
            Task { @MainActor [weak self] in
                guard let self, generation == token, videoAttempt == attempt,
                      player.currentItem === item, foreground else { return }
                guard completed else { return } // AVKit may cancel this seek when the user scrubs.
                guard needsStartupLiveSync else { return } // A manual seek now owns the playhead.
                // A slow range request can finish well after its original live target.
                if !catchingUp, plan.livePosition(at: Date()) - player.currentTime().seconds > 8 {
                    seekVideoToLive(item: item, token: token, attempt: attempt, catchingUp: true)
                    return
                }
                error = nil
                internalPlayerChange = false
                if !isPaused { player.playImmediately(atRate: 1); captions.playbackReady() }
            }
        }
    }

    private func videoFailed(token: UUID, attempt: UUID, reason: String) {
        guard generation == token, videoAttempt == attempt, foreground else { return }
        stopVideoWatchdog()
        let item = player.currentItem
        let lastEvent = item?.errorLog()?.events.last
        let host = (item?.asset as? AVURLAsset)?.url.host ?? "Archive"
        let info = PlaybackFailureInfo.make(error: item?.error, logDomain: lastEvent?.errorDomain,
                                            logStatus: lastEvent?.errorStatusCode, logComment: lastEvent?.errorComment, reason: reason, host: host,
                                            retryAfter: min(30, 5 * (retryCount + 1)))
        logger.error("Video recovery: \(info.details, privacy: .public), channel=\(self.channel?.id ?? "", privacy: .public)")
        if !remainingMediaURLs.isEmpty {
            installVideo(remainingMediaURLs.removeFirst(), token: token)
        } else {
            isBuffering = false
            playbackFailure = info
            error = info.message
            if info.shouldRetry { scheduleRecovery(token: token) }
        }
    }

    private func bufferingChanged() {
        isBuffering = !isPaused && (internalPlayerChange && playback?.plan.isVideo == true || player.timeControlStatus == .waitingToPlayAtSpecifiedRate)
        if player.timeControlStatus == .playing {
            isPaused = false
            videoHasStarted = true
            isBuffering = false
            captions.playbackReady()
            stopVideoWatchdog()
        }
        else if player.timeControlStatus == .paused, foreground, !internalPlayerChange, !isTuning, playback?.plan.isVideo == true {
            isPaused = true
            stopVideoWatchdog()
        }
        guard isBuffering, !isPaused, foreground, playback?.plan.isVideo == true, let item = player.currentItem else { return }
        armVideoWatchdog(item: item, token: generation, attempt: videoAttempt)
    }

    private func stopVideoWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = nil
        watchdogID = UUID()
    }

    private func armVideoWatchdog(item: AVPlayerItem, token: UUID, attempt: UUID) {
        guard watchdogTask == nil, !isPaused else { return }
        let identifier = UUID()
        watchdogID = identifier
        watchdogTask = Task { [weak self] in
            var monitor = PlaybackProgressWatchdog(at: ProcessInfo.processInfo.systemUptime)
            let beganAt = ProcessInfo.processInfo.systemUptime
            var nudged = false
            defer { if self?.watchdogID == identifier { self?.watchdogTask = nil } }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self, generation == token, videoAttempt == attempt,
                      player.currentItem === item, foreground, !isPaused else { return }
                if player.timeControlStatus == .playing { videoHasStarted = true; return }
                let now = ProcessInfo.processInfo.systemUptime
                let ranges = item.loadedTimeRanges.map(\.timeRangeValue)
                let end = ranges.map { CMTimeRangeGetEnd($0).seconds }.filter(\.isFinite).max() ?? 0
                let bytes = item.accessLog()?.events.reduce(Int64(0)) { $0 + $1.numberOfBytesTransferred } ?? 0
                if !nudged, !internalPlayerChange, item.status == .readyToPlay, now - beganAt >= 5 {
                    nudged = true
                    player.playImmediately(atRate: 1)
                }
                if monitor.shouldRetry(at: now, bytes: bytes, bufferedThrough: end,
                                       position: player.currentTime().seconds, isStarting: !videoHasStarted) {
                    videoFailed(token: token, attempt: attempt, reason: "Loading stalled")
                    return
                }
            }
        }
    }

    private func installAudio(_ url: URL, token: UUID) {
        let item = AVPlayerItem(url: url)
        item.allowedAudioSpatializationFormats = []
        audioPlayer.replaceCurrentItem(with: item)
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self, generation == token, item.status == .readyToPlay, let plan = playback?.plan else { return }
                await prepareAudioProcessing(item, token: token)
                guard generation == token, foreground else { return }
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
    func toggleNormalization() {
        normalizesVolume.toggle()
        UserDefaults.standard.set(normalizesVolume, forKey: "normalizesVolume")
        playbackAudioTap?.setNormalization(normalizesVolume)
    }
    private func prepareAudioProcessing(_ item: AVPlayerItem, token: UUID) async {
        do {
            let tap = try await PlaybackAudioTap.shared(for: item)
            guard generation == token, player.currentItem === item || audioPlayer.currentItem === item else { tap.stop(); return }
            playbackAudioTap = tap
            tap.setNormalization(normalizesVolume)
        } catch { logger.error("Could not start audio processing: \(error.localizedDescription, privacy: .public)") }
    }
    func resumePlayback() {
        isPaused = false
        if playback?.plan.isVideo == true { player.play(); captions.playbackReady() }
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
        guard foreground != active else { return }
        logger.notice("App active: \(active)")
        foreground = active
        if active {
            isPaused = false
            configureAudio()
            if let channel { tune(channel) }
            startRefreshLoop()
        } else {
            generation = UUID()
            videoAttempt = UUID()
            videoStartupTask?.cancel()
            tuneTask?.cancel(); transitionTask?.cancel(); recoveryTask?.cancel(); watchdogTask?.cancel(); refreshTask?.cancel()
            player.pause(); audioPlayer.pause()
            captions.bind(nil)
            community.watch(videoID: nil, clock: { nil })
        }
    }
    private func startRefreshLoop() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(NetworkPolicy.lineupRefreshInterval))
                guard !Task.isCancelled, let self, foreground else { return }
                await refresh()
            }
        }
    }
    private func configureAudio() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        configureStereoOutput()
    }
    private func configureStereoOutput() {
        let session = AVAudioSession.sharedInstance()
        if session.supportsMultichannelContent { try? session.setSupportsMultichannelContent(false) }
        if session.maximumOutputNumberOfChannels >= 2, session.preferredOutputNumberOfChannels != 2 {
            try? session.setPreferredOutputNumberOfChannels(2)
        }
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
        NetworkAudit.shared.recordMedia(player.currentItem ?? audioPlayer.currentItem, audio: NetworkAudit.shared.enabled ? playbackAudioTap?.statistics : nil)
        guard foreground, !isTuning, !internalPlayerChange, let plan = playback?.plan,
              plan.isVideo, player.currentItem?.status == .readyToPlay else { return }
        let position = player.currentTime().seconds
        let ceiling = plan.livePosition(at: Date())
        if needsStartupLiveSync, !isPaused, player.timeControlStatus == .playing, position.isFinite {
            let hasBufferedVideo = player.currentItem?.loadedTimeRanges.contains {
                let range = $0.timeRangeValue
                return range.start.seconds <= position && CMTimeRangeGetEnd(range).seconds >= position + 0.25
            } == true
            if hasBufferedVideo {
                if ceiling - position > 8, let item = player.currentItem {
                    internalPlayerChange = true
                    player.pause()
                    seekVideoToLive(item: item, token: generation, attempt: videoAttempt, catchingUp: true)
                    return
                }
                needsStartupLiveSync = false
            }
        }
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

    func userDidNavigatePlayback() {
        needsStartupLiveSync = false
        internalPlayerChange = false
        videoStartupTask?.cancel()
    }

    var guideVisible: Bool { showsSidebar || showsSchedule }
    func synopsis(for program: Program) -> String? { program.synopsis ?? tapeSynopses[program.id] }
    func loadSynopsis(for program: Program) async {
        guard program.type == "video", synopsis(for: program) == nil,
              Date().timeIntervalSince(synopsisAttempts[program.id] ?? .distantPast) >= 300 else { return }
        synopsisAttempts[program.id] = Date()
        if let value = try? await service.tapeSynopsis(id: program.id) { tapeSynopses[program.id] = value }
    }
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
        await withTaskGroup(of: ScheduleLoadResult.self) { group in
            var pending = channels.makeIterator()
            func enqueue(_ channel: Channel) {
                group.addTask {
                    let programs = (try? await service.timeline(channel: channel, start: at, end: at.addingTimeInterval(7200))) ?? []
                    return ScheduleLoadResult(id: channel.id, programs: programs)
                }
            }
            for _ in 0..<NetworkPolicy.concurrentGuideLoads {
                if let channel = pending.next() { enqueue(channel) }
            }
            for await result in group {
                rows[result.id] = result.programs
                if let channel = pending.next() { enqueue(channel) }
            }
        }
        guard scheduleRequest == token else { return }
        schedule = rows
        isLoadingSchedule = false
    }
}
