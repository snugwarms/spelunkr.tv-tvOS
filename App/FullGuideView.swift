import SpelunkrCore
import SwiftUI

private enum GuideFocus: Hashable {
    case watch, now, earlier, later
    case program(String, String)
}

struct FullGuideView: View {
    @ObservedObject var model: TVModel
    @ObservedObject var wheel: RemoteWheel
    @FocusState private var focused: GuideFocus?
    @State private var repeatGate = NavigationRepeatGate()
    @StateObject private var arrows = GuideArrowInput()
    private let channelWidth: CGFloat = 300
    private let rowHeight: CGFloat = 94

    var body: some View {
        GeometryReader { geometry in
            let gridWidth = geometry.size.width - 96 - channelWidth
            VStack(alignment: .leading, spacing: 12) {
                details
                    .frame(width: geometry.size.width * 0.64 - 70,
                           height: geometry.size.height * 0.30, alignment: .topLeading)
                HStack(spacing: 18) {
                    Text("PROGRAM GUIDE")
                        .font(.system(size: 28, weight: .black, design: .monospaced)).tracking(3)
                        .foregroundStyle(.yellow)
                    Spacer()
                    Button("Watch TV") { model.closeGuides() }.focused($focused, equals: .watch)
                        .accessibilityIdentifier("watchTV")
                    Button("Earlier") { page(by: -7200) }.focused($focused, equals: .earlier)
                    Button("Now") { Task { await model.loadSchedule() } }.focused($focused, equals: .now)
                    Button("Later") { page(by: 7200) }.focused($focused, equals: .later)
                }
                .buttonStyle(SidebarButtonStyle(compact: true))
                .frame(height: 48)

                HStack(spacing: 0) {
                    Text(model.scheduleStart, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                        .font(.system(size: 19, weight: .bold, design: .monospaced))
                        .frame(width: channelWidth, alignment: .leading)
                    ForEach(0..<4) { index in
                        Text(model.scheduleStart.addingTimeInterval(Double(index) * 1800), format: .dateTime.hour().minute())
                            .font(.system(size: 23, weight: .bold, design: .monospaced))
                            .frame(width: gridWidth / 4, alignment: .leading)
                            .accessibilityIdentifier("guideTime-\(index)")
                    }
                }
                .foregroundStyle(Color(red: 0.60, green: 0.95, blue: 1))
                .frame(height: 36)
                .background {
                    LiveTimeRule(origin: model.scheduleStart, pointsPerSecond: gridWidth / 7200, visibleWidth: gridWidth)
                        .padding(.leading, channelWidth)
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(model.channels) { channel in
                                HStack(spacing: 0) {
                                    channelLabel(channel)
                                        .frame(width: channelWidth, height: rowHeight)
                                    programRow(channel, width: gridWidth)
                                }
                                .id(channel.id)
                            }
                        }
                        .padding(.vertical, 4)
                        .background {
                            LiveTimeRule(origin: model.scheduleStart, pointsPerSecond: gridWidth / 7200, visibleWidth: gridWidth)
                                .padding(.leading, channelWidth)
                        }
                    }
                    .scrollIndicators(.hidden)
                    .overlay(alignment: .center) {
                        if model.isLoadingSchedule { ProgressView("Loading schedule…").padding(24).background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 10)) }
                    }
                    .onChange(of: focused) { _, next in
                        if case .program(let id, _) = next { proxy.scrollTo(id, anchor: .center) }
                    }
                }
                .frame(maxHeight: .infinity)

                HStack {
                    Text("SELECT  Tune live     ◀ / ▶  Browse times     BACK  Mini guide")
                    Spacer()
                    Text("SPELUNKR.TV  /  INTERNET ARCHIVE")
                }
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.65))
                .frame(height: 30)
            }
            .padding(.horizontal, 48).padding(.top, 40).padding(.bottom, 28)
            .background(LinearGradient(colors: [Color(red: 0.025, green: 0.16, blue: 0.39), Color(red: 0.005, green: 0.045, blue: 0.18)], startPoint: .top, endPoint: .bottom))
        }
        .background(GuideArrowCapture(input: arrows, shouldCapture: {
            if case .program = focused { return true }
            return false
        }, move: handleArrow))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fullGuide")
        .onChange(of: model.isLoadingSchedule) { _, loading in
            if !loading { focusCurrentRow() }
        }
        .onReceive(wheel.steps) { steps in
            guard model.showsSchedule else { return }
            for _ in 0..<min(10, abs(steps)) { moveVertical(steps > 0 ? 1 : -1) }
        }
        .task { if !model.isLoadingSchedule { focusCurrentRow() } }
    }

    private var selection: (Channel, Program)? {
        if case .program(let channelID, let key) = focused,
           let channel = model.channels.first(where: { $0.id == channelID }),
           let program = model.schedule[channelID]?.first(where: { $0.key == key }) { return (channel, program) }
        guard let channel = model.channel ?? model.channels.first,
              let program = model.schedule[channel.id]?.first else { return nil }
        return (channel, program)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(selection.map { "CH \($0.0.number)  \($0.0.name)" } ?? "SPELUNKR")
                    .font(.system(size: 23, weight: .bold, design: .monospaced)).foregroundStyle(.cyan)
                    .accessibilityIdentifier("guideSelectedChannel")
                Spacer()
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(context.date, format: .dateTime.hour().minute()).font(.system(size: 22, design: .monospaced))
                }.foregroundStyle(.white.opacity(0.7))
            }
            Text(selection?.1.title ?? "The guide is coming in…")
                .font(.system(size: 40, weight: .bold)).foregroundStyle(.white).lineLimit(2)
                .accessibilityIdentifier("guideSelectedProgram")
            if let (_, program) = selection {
                HStack(spacing: 15) {
                    Text(program.start, format: .dateTime.hour().minute())
                    Text("–")
                    Text(program.end, format: .dateTime.hour().minute())
                    if !program.year.isEmpty { Text("·  \(program.year)") }
                    if program.start <= Date(), program.end > Date() { Text("  ON NOW").foregroundStyle(.yellow) }
                }
                .font(.system(size: 23, weight: .medium, design: .monospaced)).foregroundStyle(.cyan)
            }
            Text(selection?.0.description ?? "Browse channels and the next two hours of programming. The current channel keeps playing in the corner.")
                .font(.system(size: 24)).lineSpacing(5).foregroundStyle(.white.opacity(0.82)).lineLimit(3)
            Spacer(minLength: 0)
        }
    }

    private func channelLabel(_ channel: Channel) -> some View {
        HStack(spacing: 14) {
            Text(channel.number).font(.system(size: 29, weight: .black, design: .monospaced))
                .frame(width: 48, alignment: .leading)
            ChannelIcon(channel: channel).frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 6) {
                Text(channel.name).font(.system(size: 19, weight: .bold, design: .monospaced)).lineLimit(2)
                if channel.id == model.channel?.id { Label("WATCHING", systemImage: "speaker.wave.2.fill").font(.system(size: 12, weight: .bold)) }
            }
            Spacer(minLength: 6)
        }
        .padding(.leading, 15).padding(.trailing, 12)
        .foregroundStyle(channel.id == model.channel?.id ? .cyan : .white)
        .background(Color(red: 0.03, green: 0.12, blue: 0.29))
    }

    private func programRow(_ channel: Channel, width: CGFloat) -> some View {
        let programs = model.schedule[channel.id] ?? []
        return HStack(spacing: 2) {
            if programs.isEmpty {
                Button("Schedule unavailable · tune live") { model.tune(channel); model.closeGuides() }
                    .buttonStyle(ScheduleCellStyle()).frame(width: width, height: rowHeight)
            } else {
                ForEach(Array(programs.enumerated()), id: \.element.key) { index, program in
                    let left = max(program.start, model.scheduleStart)
                    let right = min(program.end, model.scheduleStart.addingTimeInterval(7200))
                    let cellWidth = max(1, CGFloat(right.timeIntervalSince(left) / 7200) * width - 2)
                    Button { model.tune(channel); model.closeGuides() } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(program.title).font(.system(size: 23, weight: .semibold)).lineLimit(2)
                            if cellWidth > 220 {
                                Text(program.start, format: .dateTime.hour().minute()).font(.system(size: 15, design: .monospaced)).opacity(0.65)
                            }
                        }
                        .padding(.horizontal, cellWidth > 60 ? 14 : 2)
                        .frame(width: cellWidth, height: rowHeight, alignment: .leading)
                        .background {
                            LiveTimeRule(origin: left, pointsPerSecond: width / 7200, visibleWidth: cellWidth)
                        }
                        .clipped()
                    }
                    .buttonStyle(ScheduleCellStyle(isPlaying: isPlaying(channel: channel, program: program)))
                    .focused($focused, equals: .program(channel.id, program.key))
                    .onMoveCommand { direction in
                        guard !arrows.suppressesMoveCommands else { return }
                        let key: Int = direction == .up ? 1 : direction == .down ? 2 : direction == .left ? 3 : 4
                        if repeatGate.accept(direction: key, at: ProcessInfo.processInfo.systemUptime) {
                            move(direction, channel: channel, index: index)
                        }
                    }
                    .accessibilityIdentifier("schedule-\(channel.id)-\(index)")
                    .accessibilityLabel("\(channel.name), \(program.title), \(program.start.formatted(date: .omitted, time: .shortened)). Select to tune channel live.")
                }
            }
        }
        .frame(width: width, height: rowHeight, alignment: .leading)
        .clipped()
    }

    private func focusCurrentRow() {
        if case .program(let id, let key) = focused, model.schedule[id]?.contains(where: { $0.key == key }) == true { return }
        let channel = selection?.0 ?? model.channel ?? model.channels.first
        if let channel, let program = model.schedule[channel.id]?.first { focused = .program(channel.id, program.key) }
        else { focused = .watch }
    }

    private func isPlaying(channel: Channel, program: Program) -> Bool {
        guard channel.id == model.channel?.id, let current = model.playback?.plan.program else { return false }
        if current.type == "video" { return program.key == current.key }
        return program.startMs <= current.startMs && program.endMs >= current.endMs
    }

    private func move(_ direction: MoveCommandDirection, channel: Channel, index: Int) {
        guard !model.isLoadingSchedule else { return }
        let programs = model.schedule[channel.id] ?? []
        switch direction {
        case .left:
            if index == 0 { page(by: -7200, channelID: channel.id, focusLast: true) }
            else { focused = .program(channel.id, programs[index - 1].key) }
        case .right:
            if index + 1 < programs.count { focused = .program(channel.id, programs[index + 1].key) }
            else { page(by: 7200, channelID: channel.id) }
        case .up: moveVertical(-1)
        case .down: moveVertical(1)
        default: break
        }
    }

    private func handleArrow(_ direction: MoveCommandDirection) {
        guard case .program(let id, let key) = focused,
              let channel = model.channels.first(where: { $0.id == id }),
              let index = model.schedule[id]?.firstIndex(where: { $0.key == key }) else { return }
        move(direction, channel: channel, index: index)
    }

    private func moveVertical(_ step: Int) {
        guard let selected = selection, let row = model.channels.firstIndex(where: { $0.id == selected.0.id }) else { return }
        if row == 0 && step < 0 { focused = .now; return }
        let nextRow = max(0, min(model.channels.count - 1, row + step))
        let channel = model.channels[nextRow]
        let time = max(model.scheduleStart, selected.1.start).addingTimeInterval(1)
        if let program = model.schedule[channel.id]?.first(where: { $0.start <= time && $0.end > time }) ?? model.schedule[channel.id]?.first {
            focused = .program(channel.id, program.key)
        }
    }

    private func page(by offset: TimeInterval, channelID: String? = nil, focusLast: Bool = false) {
        let channelID = channelID ?? selection?.0.id ?? model.channel?.id
        Task {
            await model.loadSchedule(start: model.scheduleStart.addingTimeInterval(offset))
            if let channelID, let programs = model.schedule[channelID], let program = focusLast ? programs.last : programs.first {
                focused = .program(channelID, program.key)
            }
        }
    }
}

private struct ScheduleCellStyle: ButtonStyle {
    var isPlaying = false
    func makeBody(configuration: Configuration) -> some View { Cell(configuration: configuration, isPlaying: isPlaying) }
    private struct Cell: View {
        let configuration: Configuration
        let isPlaying: Bool
        @Environment(\.isFocused) private var focused
        var body: some View {
            configuration.label
                .foregroundStyle(focused ? Color.black : Color.white)
                .background {
                    ZStack {
                        focused ? Color.yellow : isPlaying ? Color(red: 0.11, green: 0.28, blue: 0.52) : Color(red: 0.04, green: 0.18, blue: 0.41)
                        Rectangle().strokeBorder(focused ? Color.white : Color.white.opacity(0.10), lineWidth: focused ? 3 : 1)
                    }
                }
                .opacity(configuration.isPressed ? 0.75 : 1)
        }
    }
}

/// This is a label background: it sits above the cell's fill and below its text.
private struct LiveTimeRule: View {
    let origin: Date
    let pointsPerSecond: CGFloat
    let visibleWidth: CGFloat
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let x = CGFloat(context.date.timeIntervalSince(origin)) * pointsPerSecond
            if x >= 0 && x < visibleWidth {
                Rectangle().fill(Color.red)
                    .frame(width: 3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .offset(x: x)
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}
