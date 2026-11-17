import Foundation

public struct Lineup: Decodable, Sendable {
    public let engine: Int
    public let generatedAt: String
    public let audioBase: String?
    public let channels: [Channel]

    public var availableChannels: [Channel] {
        channels.filter { $0.dial != nil && $0.debugOnly != true && $0.comingSoon != true && !$0.versions.isEmpty }
            .sorted { $0.dial! < $1.dial! }
    }
}

public struct Channel: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let emoji: String?
    public let color: String?
    public let logomark: ChannelMark?
    public let description: String?
    public let dial: Int?
    public let debugOnly: Bool?
    public let comingSoon: Bool?
    public let versions: [VersionPointer]

    public var number: String { String(format: "%02d", dial ?? 0) }
}

public struct ChannelMark: Codable, Hashable, Sendable {
    public let type: String?
    public let rows: [String]?
    private enum CodingKeys: String, CodingKey { case type, rows }
    public init(from decoder: Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else { type = nil; rows = nil; return }
        type = try? container.decode(String.self, forKey: .type)
        rows = try? container.decode([String].self, forKey: .rows)
    }
}

public struct VersionPointer: Codable, Hashable, Sendable {
    public let v: Int
    public let manifest: String
    public let epochMs: Double
    public let effectiveAtMs: Double?
    public let startIndex: Int?
}

public struct Program: Codable, Hashable, Sendable {
    public let key: String
    public let type: String
    public let id: String
    public let title: String
    public let year: String
    public let synopsis: String?
    public let startMs: Double
    public let endMs: Double
    public var start: Date { Date(timeIntervalSince1970: startMs / 1000) }
    public var end: Date { Date(timeIntervalSince1970: endMs / 1000) }
    public func progress(at date: Date) -> Double {
        min(1, max(0, (date.timeIntervalSince1970 * 1000 - startMs) / max(1, endMs - startMs)))
    }
}

public struct GuideEntry: Decodable, Sendable {
    public let current: Program
    public let next: Program?
}

public struct StationCard: Codable, Sendable {
    public let text: String
    public let start: Double
    public let end: Double
}

public struct PlaybackPlan: Decodable, Sendable {
    public let program: Program
    public let archiveID: String?
    public let file: String?
    public let inPoint: Double
    public let cards: [StationCard]
    public let audioFile: String?
    public let audioInPoint: Double
    public let audioTitle: String?
    public let audioArtist: String?

    public var isVideo: Bool { program.type == "video" || program.type == "ad" }
    public func offset(at date: Date) -> Double { max(0, date.timeIntervalSince1970 - program.startMs / 1000) }
    public func livePosition(at date: Date) -> Double {
        inPoint + min(max(0, (program.endMs - program.startMs) / 1000), offset(at: date))
    }
    public func clampedSeek(_ requested: Double, at date: Date) -> Double {
        min(livePosition(at: date), max(inPoint, requested.isFinite ? requested : inPoint))
    }
    public func card(at date: Date) -> String {
        let ms = offset(at: date) * 1000
        return cards.first { ms >= $0.start && ms < $0.end }?.text ?? "SPELUNKR"
    }
}

public struct ResolvedPlayback: Sendable {
    public let plan: PlaybackPlan
    public let mediaURL: URL?
    public let alternateMediaURLs: [URL]
    public var fallbackURL: URL? { alternateMediaURLs.first }
    public let audioURL: URL?
    public let synopsis: String?
}

public enum BroadcastError: LocalizedError {
    case invalidData(String)
    case unsupportedEngine(Int)
    case missingChannel
    case http(Int)
    case noVideo

    public var errorDescription: String? {
        switch self {
        case .invalidData(let message): return message
        case .unsupportedEngine(let version): return "Spelunkr now uses schedule engine \(version). This app needs an update."
        case .missingChannel: return "This channel is no longer in the guide."
        case .http(let status): return "The broadcast service returned \(status). Try again shortly."
        case .noVideo: return "This tape has no Apple TV compatible video. The next program will tune automatically."
        }
    }
}
