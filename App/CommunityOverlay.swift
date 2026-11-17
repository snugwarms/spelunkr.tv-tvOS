import Combine
import SpelunkrCore
import SwiftUI

struct FlyingComment: Identifiable {
    let id: String
    let author: String
    let text: String
    let born: Date
    let lane: Int
}

struct FloatingReaction: Identifiable {
    let id: String
    let symbol: String
    let kind: String
    let born: Date
    let lane: Int
}

@MainActor
final class CommunityPlayback: ObservableObject {
    @Published private(set) var comments: [FlyingComment] = []
    @Published private(set) var reactions: [FloatingReaction] = []
    @Published private(set) var error: String?
    @Published var showsComments: Bool {
        didSet { UserDefaults.standard.set(showsComments, forKey: "showVideoComments") }
    }
    @Published var showsReactions: Bool {
        didSet { UserDefaults.standard.set(showsReactions, forKey: "showVideoReactions") }
    }
    private let service = CommunityService()
    private var fetchTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var videoID: String?
    private var snapshot: CommunitySnapshot?
    private var clock: () -> Double? = { nil }
    private var lastPosition: Double?
    private var displayed: Set<String> = []
    private var knownReactions: Set<String> = []
    private var knownComments: Set<String> = []
    private var sessionKey: String?
    private var lane = 0

    init() {
        showsComments = UserDefaults.standard.object(forKey: "showVideoComments") as? Bool ?? true
        showsReactions = UserDefaults.standard.object(forKey: "showVideoReactions") as? Bool ?? true
    }

    func watch(videoID: String?, sessionKey: String? = nil, clock: @escaping () -> Double?) {
        self.clock = clock
        guard self.videoID != videoID || self.sessionKey != sessionKey else { return }
        fetchTask?.cancel(); tickTask?.cancel()
        self.videoID = videoID
        self.sessionKey = sessionKey
        snapshot = nil; lastPosition = nil; displayed = []; knownReactions = []
        comments = []; reactions = []; error = nil; knownComments = []
        guard let videoID else { return }
        fetchTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    let next = try await service.snapshot(videoID: videoID)
                    guard !Task.isCancelled, self.videoID == videoID else { return }
                    if snapshot != nil, let position = clock() {
                        // Newly arriving live reactions float immediately, as on the website.
                        for item in next.reactions.filter({ !self.knownReactions.contains($0.id) && abs($0.timestamp_s - position) <= 120 }).suffix(12) { float(item) }
                        for item in next.comments where !knownComments.contains(item.id) && item.timestamp_s <= position && position - item.timestamp_s <= 20 { show(item) }
                    } else { lastPosition = clock().map { max(0, $0 - 3) } }
                    knownReactions.formUnion(next.reactions.map(\.id))
                    knownComments.formUnion(next.comments.map(\.id))
                    snapshot = next
                    error = nil
                } catch {
                    guard !Task.isCancelled else { return }
                    self.error = "Comments and reactions are temporarily unavailable."
                }
                try? await Task.sleep(for: .seconds(15))
            }
        }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
    }

    private func tick() {
        let now = Date()
        comments.removeAll { now.timeIntervalSince($0.born) > 12 }
        reactions.removeAll { now.timeIntervalSince($0.born) > 6 }
        guard let position = clock(), position.isFinite, let snapshot else { return }
        let previous = lastPosition ?? max(0, position - 2)
        if position < previous - 1 {
            // Rewinding re-arms the tape's later comments and reactions.
            displayed.subtract(snapshot.comments.filter { $0.timestamp_s > position }.map(\.id))
            displayed.subtract(snapshot.reactions.filter { $0.timestamp_s > position }.map(\.id))
        }
        let lower = position < previous || position - previous > 5 ? position - 2 : previous
        lastPosition = position
        for comment in snapshot.comments where comment.timestamp_s > lower && comment.timestamp_s <= position && !displayed.contains(comment.id) {
            show(comment)
        }
        for reaction in snapshot.reactions where reaction.timestamp_s > lower && reaction.timestamp_s <= position { float(reaction) }
    }

    private func show(_ comment: VideoComment) {
        guard !displayed.contains(comment.id) else { return }
        displayed.insert(comment.id)
        guard showsComments else { return }
        comments.append(FlyingComment(id: comment.id, author: comment.author, text: comment.text, born: Date(), lane: lane % 3))
        lane += 1
        if comments.count > 3 { comments.removeFirst() }
    }

    private func float(_ reaction: VideoReaction) {
        guard !displayed.contains(reaction.id) else { return }
        displayed.insert(reaction.id)
        guard showsReactions else { return }
        reactions.append(FloatingReaction(id: reaction.id, symbol: reaction.symbol, kind: reaction.emoji, born: Date(), lane: reactions.count % 5))
        if reactions.count > 24 { reactions.removeFirst() }
    }
}

struct CommunityOverlay: View {
    @ObservedObject var community: CommunityPlayback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let scale = max(0.35, min(1, geometry.size.width / 1440))
            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                ZStack(alignment: .topLeading) {
                    if community.showsComments {
                        ForEach(community.comments) { comment in
                            let age = context.date.timeIntervalSince(comment.born)
                            let width = min(geometry.size.width * 0.8, 920 * scale)
                            VStack(alignment: .leading, spacing: 5 * scale) {
                                Text(comment.author).font(.system(size: 19 * scale, weight: .bold)).foregroundStyle(.cyan)
                                Text(comment.text).font(.system(size: 25 * scale, weight: .semibold)).foregroundStyle(.white).lineLimit(2)
                            }
                            .padding(.horizontal, 18 * scale).padding(.vertical, 12 * scale)
                            .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 9 * scale))
                            .frame(width: width, alignment: .leading)
                            .opacity(min(1, max(0, (12 - age) / 1.0)))
                            .position(x: 30 * scale + width / 2,
                                      y: geometry.size.height - (85 + CGFloat(comment.lane) * 125) * scale)
                        }
                    }
                    if community.showsReactions {
                        ForEach(community.reactions) { reaction in
                            let age = context.date.timeIntervalSince(reaction.born)
                            let progress = min(1, age / 6)
                            Image("Reaction-\(reaction.kind)")
                                .resizable().scaledToFit().frame(width: 48 * scale, height: 48 * scale)
                                .shadow(color: .black.opacity(0.4), radius: 4)
                                .opacity(min(1, max(0, (6 - age) / 1.5)))
                                .position(x: geometry.size.width - (70 + CGFloat(reaction.lane) * 22) * scale + (reduceMotion ? 0 : sin(age * 2 + Double(reaction.lane)) * 24 * scale),
                                          y: geometry.size.height - 45 * scale - (reduceMotion ? 0 : progress * geometry.size.height * 0.68))
                        }
                    }
                }
            }
        }
        .clipped().allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct CommunitySettings: View {
    @ObservedObject var community: CommunityPlayback
    var body: some View {
        Menu {
            Toggle("Comments over video", isOn: $community.showsComments)
            Toggle("Floating reactions", isOn: $community.showsReactions)
            if let error = community.error { Text(error) }
        } label: { Image(systemName: "text.bubble") }
        .accessibilityLabel("On-screen comments and reactions")
    }
}
