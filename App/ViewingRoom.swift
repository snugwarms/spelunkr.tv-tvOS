import SwiftUI
import SpelunkrCore

private enum RoomFocus: Hashable { case channel(String), guide, picture }

struct ViewingRoom: View {
    @StateObject private var model = TVModel()
    @StateObject private var wheel = RemoteWheel()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focus: RoomFocus?

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let sidebarWidth = min(size.width * 0.45, max(440, size.width * 0.25))
            let pictureWidth = model.showsSchedule ? size.width * 0.30 : model.showsSidebar ? min(size.width, size.height * model.videoAspectRatio) : size.width
            let pictureHeight = model.showsSchedule ? size.height * 0.30 : size.height
            ZStack(alignment: .topLeading) {
                Color.black
                if model.showsSchedule {
                    FullGuideView(model: model, wheel: wheel)
                        .frame(width: size.width, height: size.height)
                }
                picture
                    .frame(width: pictureWidth, height: pictureHeight)
                    .offset(x: model.showsSchedule ? size.width - pictureWidth - 48 : 0,
                            y: model.showsSchedule ? 40 : 0)
                    .overlay {
                        if !model.guideVisible && !model.showsNativeControls {
                            Color.clear
                                .focusable().focusEffectDisabled()
                                .focused($focus, equals: .picture)
                                .onTapGesture { model.showsNativeControls = true }
                                .onExitCommand { model.openMiniGuide() }
                                .onMoveCommand { direction in
                                    if direction == .right { model.openMiniGuide() }
                                    else if direction == .down || direction == .up { model.showsNativeControls = true }
                                }
                                .accessibilityLabel("Video. Up, Down or Select opens playback controls. Right opens the mini guide.")
                        }
                    }
                if model.showsSidebar {
                    sidebar
                        .frame(width: sidebarWidth, height: size.height)
                        .offset(x: size.width - sidebarWidth)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
            .background(.black)
        }
        .ignoresSafeArea()
        .background { GuideBackCapture(isActive: model.guideVisible && !model.showsAbout, back: model.backFromGuide) }
        .onPlayPauseCommand(perform: !model.showsNativeControls ? { model.togglePause() } : nil)
        .onExitCommand(perform: model.guideVisible ? { model.backFromGuide() } : nil)
        .onChange(of: model.showsSidebar) { _, visible in
            focus = visible ? model.channel.map { .channel($0.id) } : model.showsSchedule ? nil : .picture
        }
        .onChange(of: model.showsSchedule) { _, visible in if !visible && !model.showsSidebar { focus = .picture } }
        .onChange(of: model.showsNativeControls) { _, visible in focus = visible ? nil : model.guideVisible ? nil : .picture }
        .onChange(of: model.channels.count) { old, count in
            if old == 0, count > 0, model.showsSidebar, let first = model.channels.first { focus = .channel(first.id) }
        }
        .onReceive(wheel.steps) { step in
            guard model.showsSidebar, !model.orderedChannels.isEmpty else { return }
            let rows = model.orderedChannels
            let current: String? = { if case .channel(let id) = focus { return id }; return model.channel?.id }()
            let index = rows.firstIndex(where: { $0.id == current }) ?? 0
            focus = .channel(rows[max(0, min(rows.count - 1, index + step))].id)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.setActive(false) }
            else if phase == .active { model.setActive(true) }
        }
        .task { await model.start() }
        .sheet(isPresented: $model.showsAbout) { about }
    }

    private var picture: some View {
        ZStack {
            Color.black
            PlayerSurface(model: model)
            if let playback = model.playback, !playback.plan.isVideo {
                TimelineView(.periodic(from: .now, by: 0.1)) { context in
                    StationBreak(text: playback.plan.card(at: context.date), channel: model.channel?.name ?? "SPELUNKR")
                }
            }
            if model.isLoading || model.isTuning || model.isBuffering {
                VStack(spacing: 18) {
                    ProgressView().controlSize(.large).tint(Palette.cyan)
                    Text(model.isLoading ? "FINDING THE SIGNAL" : "TUNING IN")
                        .font(.system(size: 20, weight: .bold, design: .monospaced)).tracking(4)
                        .foregroundStyle(Palette.cyan)
                }
                .padding(36)
                .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
            }
            if let error = model.error ?? (model.channel == nil && !model.isLoading ? model.guideError : nil) {
                VStack(spacing: 22) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash").font(.system(size: 48))
                    Text("NO SIGNAL").font(.system(size: 30, weight: .black, design: .monospaced)).tracking(5)
                    Text(error).font(.system(size: 23)).multilineTextAlignment(.center).frame(maxWidth: 650)
                    if !model.showsSidebar { Text("Press Back for the guide and Retry").font(.system(size: 20)).foregroundStyle(Palette.cyan) }
                }
                .foregroundStyle(.white).padding(50)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.navy)
            }
        }
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("videoRegion")
        .accessibilityValue(model.player.timeControlStatus == .playing ? "Playing" : model.player.timeControlStatus == .paused ? "Paused" : "Buffering")
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("SPELUNKR").font(.system(size: 29, weight: .black, design: .monospaced)).tracking(3)
                Spacer(minLength: 4)
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 18, weight: .medium, design: .monospaced))
                }.foregroundStyle(Palette.muted)
            }
            .foregroundStyle(Palette.yellow)
            .padding(.bottom, 22)

            nowPlaying
                .padding(.bottom, 18)

            HStack {
                Text("MINI GUIDE").tracking(3)
                Spacer()
                if model.isRefreshing { ProgressView().scaleEffect(0.65).frame(width: 20, height: 20) }
                else { Text("FULL GUIDE ›").foregroundStyle(Palette.cyan) }
            }
            .font(.system(size: 16, weight: .bold, design: .monospaced))
            .foregroundStyle(Palette.muted)
            .padding(.bottom, 12)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(model.orderedChannels) { entry in
                            ChannelButton(channel: entry, guide: model.guide[entry.id],
                                          error: model.channelErrors[entry.id],
                                          isPlaying: model.channel?.id == entry.id,
                                          isFavorite: model.favoriteIDs.contains(entry.id)) { model.tune(entry) }
                                .focused($focus, equals: .channel(entry.id))
                                .contextMenu {
                                    Button(model.favoriteIDs.contains(entry.id) ? "Remove favorite" : "Add favorite",
                                           systemImage: model.favoriteIDs.contains(entry.id) ? "star.slash" : "star") { model.toggleFavorite(entry.id) }
                                }
                                .id(entry.id)
                                .accessibilityIdentifier("channel-\(entry.id)")
                        }
                    }
                    .padding(5)
                }
                .scrollIndicators(.hidden)
                .onChange(of: focus) { _, next in
                    if case .channel(let id) = next {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) { proxy.scrollTo(id, anchor: .center) }
                    }
                }
                .task(id: model.channel?.id) {
                    guard let id = model.channel?.id else { return }
                    proxy.scrollTo(id, anchor: .center)
                    try? await Task.sleep(for: .milliseconds(60))
                    guard !Task.isCancelled, model.showsSidebar else { return }
                    focus = .channel(id)
                }
            }
            .frame(maxHeight: .infinity)

            if let guideError = model.guideError {
                Text(guideError).font(.system(size: 16)).foregroundStyle(Palette.yellow).lineLimit(2).padding(.top, 8)
            } else if model.isUsingSavedGuide {
                Text("Using saved guide · retrying automatically").font(.system(size: 16)).foregroundStyle(Palette.yellow).padding(.top, 8)
            }

            HStack(spacing: 12) {
                Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("Refresh guide")
                Button { model.showsAbout = true } label: { Image(systemName: "info.circle") }
                    .accessibilityLabel("About Spelunkr")
                CommunitySettings(community: model.community)
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("ORIGINAL: SPELUNKR.TV")
                    Text("VIDEO: INTERNET ARCHIVE")
                }
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Palette.muted)
            }
            .buttonStyle(SidebarButtonStyle(compact: true))
            .padding(.top, 14)
        }
        .padding(.horizontal, 28)
        .padding(.top, 54)
        .padding(.bottom, 40)
        .background(LinearGradient(colors: [Palette.purple, Palette.navy], startPoint: .topLeading, endPoint: .bottomTrailing))
        .overlay(alignment: .leading) { Rectangle().fill(Palette.border).frame(width: 2) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("miniGuide")
        .onMoveCommand { direction in
            if direction == .left { model.closeGuides() }
            else if direction == .right { model.openFullGuide() }
        }
    }

    private var nowPlaying: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Circle().fill(model.isPaused ? Palette.yellow : Palette.cyan).frame(width: 7, height: 7)
                Text(model.isPaused ? "PAUSED" : "ON AIR")
                    .font(.system(size: 13, weight: .bold, design: .monospaced)).tracking(2)
                Spacer()
                if let channel = model.channel {
                    Text("CH \(channel.number)").font(.system(size: 15, weight: .bold, design: .monospaced))
                        .accessibilityIdentifier("nowPlayingChannelNumber")
                }
            }.foregroundStyle(Palette.cyan)
            Text(model.channel?.name ?? "TUNING THE DIAL")
                .font(.system(size: 19, weight: .bold, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(.white)
                .accessibilityIdentifier("nowPlayingChannel")
            Text(model.playback?.plan.program.title ?? model.channel?.description ?? "Cable TV, but weirder.")
                .font(.system(size: 24, weight: .semibold)).lineLimit(2)
                .foregroundStyle(.white)
                .frame(height: 60, alignment: .topLeading)
                .accessibilityIdentifier("nowPlayingProgram")
            if let synopsis = model.playback?.synopsis, !synopsis.isEmpty {
                Text(synopsis).font(.system(size: 17)).foregroundStyle(.white.opacity(0.86)).lineLimit(4)
                    .accessibilityIdentifier("nowPlayingSynopsis")
            }
            if let description = model.channel?.description {
                Text(description).font(.system(size: 13)).foregroundStyle(Palette.muted).lineLimit(2)
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if let program = model.playback?.plan.program {
                    ProgressView(value: program.progress(at: context.date)).tint(Palette.cyan)
                    HStack {
                        Text(program.start, format: .dateTime.hour().minute())
                        Spacer()
                        Text(program.end, format: .dateTime.hour().minute())
                    }.font(.system(size: 13, design: .monospaced)).foregroundStyle(Palette.muted)
                } else { ProgressView(value: 0).tint(Palette.cyan) }
            }
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text("SPELUNKR ON APPLE TV").font(.system(size: 38, weight: .black, design: .monospaced)).foregroundStyle(Palette.yellow)
            Text("UNOFFICIAL third-party Apple TV app. Not made by, affiliated with, or endorsed by the creator of Spelunkr.tv. Programming, broadcast schedules, and the original scheduler belong to Spelunkr. Videos stream directly from the Internet Archive.")
            Text("Right opens the mini guide; Right again opens the full schedule. Back steps back through the guides to the video. Left and Right in the full guide browse earlier and later programs. Hold Select on a mini-guide channel to manage favorites.")
            Text("Up, Down or Select while watching opens the native tvOS player controls, with Rejoin Live and Last Channel. Play/Pause works on the remote. Rewinding is allowed; playing ahead of live is not.")
            Text("Comments pop up at the bottom left when their saved timestamp on the tape comes around again. The site's yellow reactions float up over the picture. The speech-bubble menu toggles either overlay.")
            Text("The picture always keeps its original proportions. A 4:3 tape fills the screen height beside the mini guide; for wider tapes, the guide overlaps the right edge of the video.")
            Text("References: buddytohelpu/spelunkr-guide, ominixisboss/Spelunkr.tv-App, Nikolay1243/spelunkr-webos, pedr/spelunkrtv-tizen-app.")
                .font(.system(size: 20)).foregroundStyle(Palette.muted)
            Button("Back to TV") { model.showsAbout = false }.buttonStyle(SidebarButtonStyle())
        }
        .font(.system(size: 26)).lineSpacing(6).padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.navy)
    }

    private func revealGuide() { model.openMiniGuide(); focus = model.channel.map { .channel($0.id) } }
}

private struct ChannelButton: View {
    let channel: Channel
    let guide: GuideEntry?
    let error: String?
    let isPlaying: Bool
    let isFavorite: Bool
    let tune: () -> Void

    var body: some View {
        Button(action: tune) {
            HStack(alignment: .top, spacing: 10) {
                VStack(spacing: 7) {
                    Text(channel.number).font(.system(size: 25, weight: .black, design: .monospaced))
                        .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    ChannelIcon(channel: channel).frame(width: 32, height: 32)
                    if isPlaying { Image(systemName: "speaker.wave.2.fill").font(.system(size: 14)) }
                    else if isFavorite { Image(systemName: "star.fill").font(.system(size: 14)) }
                }
                .foregroundStyle(isPlaying ? Palette.cyan : Palette.muted)
                .frame(width: 52)
                VStack(alignment: .leading, spacing: 7) {
                    Text(channel.name).font(.system(size: 17, weight: .bold, design: .monospaced))
                        .foregroundStyle(isPlaying ? Palette.cyan : .white).lineLimit(1).minimumScaleFactor(0.75)
                    Text(guide?.current.title ?? (error == nil ? "Loading schedule…" : "Schedule unavailable · select to retry"))
                        .font(.system(size: 20, weight: .medium)).foregroundStyle(.white).lineLimit(2)
                    if let next = guide?.next {
                        HStack(spacing: 6) {
                            Text(next.start, format: .dateTime.hour().minute())
                            Text(next.title).lineLimit(1)
                        }.font(.system(size: 14)).foregroundStyle(Palette.muted)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 4).padding(.trailing, 14).padding(.vertical, 15)
            .frame(maxWidth: .infinity, minHeight: 105, alignment: .leading)
        }
        .buttonStyle(ChannelButtonStyle(isPlaying: isPlaying))
        .accessibilityLabel("Channel \(channel.number), \(channel.name), \(guide?.current.title ?? "schedule loading")\(isPlaying ? ", playing" : "")")
    }
}

private struct ChannelButtonStyle: ButtonStyle {
    let isPlaying: Bool
    func makeBody(configuration: Configuration) -> some View {
        FocusedChannelLabel(configuration: configuration, isPlaying: isPlaying)
    }
    private struct FocusedChannelLabel: View {
        let configuration: Configuration
        let isPlaying: Bool
        @Environment(\.isFocused) private var focused
        var body: some View {
            configuration.label
                .background(focused ? Palette.focus : isPlaying ? Palette.panel : Palette.panel.opacity(0.4), in: RoundedRectangle(cornerRadius: 7))
                .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(focused ? Palette.yellow : isPlaying ? Palette.cyan.opacity(0.6) : .clear, lineWidth: focused ? 3 : 1) }
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
        }
    }
}

struct SidebarButtonStyle: ButtonStyle {
    var compact = false
    func makeBody(configuration: Configuration) -> some View { FocusedLabel(configuration: configuration, compact: compact) }
    private struct FocusedLabel: View {
        let configuration: Configuration
        let compact: Bool
        @Environment(\.isFocused) private var focused
        @Environment(\.isEnabled) private var enabled
        var body: some View {
            configuration.label
                .font(.system(size: compact ? 17 : 19, weight: .bold))
                .padding(.horizontal, compact ? 12 : 15).padding(.vertical, compact ? 12 : 16)
                .foregroundStyle(focused ? Palette.navy : .white)
                .background(focused ? Palette.yellow : Palette.panel, in: RoundedRectangle(cornerRadius: 7))
                .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.35)
        }
    }
}

private struct StationBreak: View {
    let text: String
    let channel: String
    var body: some View {
        VStack(spacing: 40) {
            Text(channel).font(.system(size: 23, weight: .bold, design: .monospaced)).tracking(5).foregroundStyle(Palette.cyan)
            Text(text).font(.system(size: 46, weight: .bold, design: .monospaced))
                .multilineTextAlignment(.center).lineSpacing(12).foregroundStyle(Palette.yellow)
        }
        .padding(90).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient(colors: [Palette.purple, Palette.navy], startPoint: .top, endPoint: .bottom))
    }
}

private enum Palette {
    static let purple = Color(red: 0.11, green: 0.04, blue: 0.34)
    static let navy = Color(red: 0.015, green: 0.035, blue: 0.12)
    static let panel = Color(red: 0.13, green: 0.16, blue: 0.35)
    static let focus = Color(red: 0.16, green: 0.20, blue: 0.43)
    static let border = Color(red: 0.15, green: 0.32, blue: 0.70)
    static let yellow = Color(red: 1, green: 1, blue: 0)
    static let cyan = Color(red: 0.56, green: 0.99, blue: 0.98)
    static let muted = Color(red: 0.63, green: 0.68, blue: 0.81)
}
