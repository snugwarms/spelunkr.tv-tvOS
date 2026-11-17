import Foundation

public struct VideoComment: Decodable, Identifiable, Sendable {
    public struct Author: Decodable, Sendable { public let display_name: String? }
    public let id: String
    public let video_id: String?
    public let timestamp_s: Double
    public let text: String
    public let users: Author?
    public var author: String { users?.display_name ?? "Spelunker" }
}

public struct VideoReaction: Decodable, Identifiable, Sendable {
    public let id: String
    public let video_id: String
    public let timestamp_s: Double
    public let emoji: String
    public var symbol: String {
        ["laugh": "😂", "skull": "💀", "shocked": "😮", "fire": "🔥", "question": "❓", "sad": "😢", "heart": "❤️"][emoji] ?? "❤️"
    }
}

public struct CommunitySnapshot: Sendable {
    public let comments: [VideoComment]
    public let reactions: [VideoReaction]
}

/// Reads the same public, moderated comments and timestamped reactions as the website.
/// This client never signs in or posts on the viewer's behalf.
public actor CommunityService {
    private struct Configuration: Decodable { let url: URL; let publicKey: String }
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public func snapshot(videoID: String) async throws -> CommunitySnapshot {
        guard !videoID.isEmpty else { return CommunitySnapshot(comments: [], reactions: []) }
        let configURL = Bundle.module.url(forResource: "community", withExtension: "json")!
        let config = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: configURL))
        async let comments: [VideoComment] = pages(table: "comments", config: config, query: [
            "select": "id,video_id,timestamp_s,text,users:user_cards!comments_user_id_fkey(display_name)",
            "video_id": "eq.\(videoID)", "status": "eq.active", "order": "timestamp_s.asc,id.asc"
        ])
        async let reactions: [VideoReaction] = pages(table: "reactions", config: config, query: [
            "select": "id,video_id,timestamp_s,emoji", "video_id": "eq.\(videoID)", "order": "id.asc"
        ])
        let result = try await CommunitySnapshot(comments: comments, reactions: reactions)
        return CommunitySnapshot(
            comments: result.comments.filter { $0.timestamp_s.isFinite && !$0.text.isEmpty },
            reactions: result.reactions.filter { $0.timestamp_s.isFinite && ["laugh", "skull", "shocked", "fire", "question", "sad", "heart"].contains($0.emoji) }
        )
    }

    private func pages<T: Decodable>(table: String, config: Configuration, query: [String: String]) async throws -> [T] {
        var rows: [T] = []
        for page in 0..<20 {
            var parts = URLComponents(url: config.url.appendingPathComponent(table), resolvingAgainstBaseURL: false)!
            parts.queryItems = (query.merging(["limit": "1000", "offset": String(page * 1000)]) { a, _ in a })
                .sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            var request = URLRequest(url: parts.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
            request.setValue(config.publicKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(config.publicKey)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw BroadcastError.invalidData("Comments and reactions are temporarily unavailable.")
            }
            let batch = try JSONDecoder().decode([T].self, from: data)
            rows.append(contentsOf: batch)
            if batch.count < 1000 { break }
        }
        return rows
    }
}
