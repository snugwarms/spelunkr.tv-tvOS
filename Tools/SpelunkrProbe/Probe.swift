import Foundation
import SpelunkrCore

@main
struct Probe {
    static func main() async throws {
        let service = BroadcastService()
        let lineup = try await service.lineup()
        let date = Date()
        let arguments = CommandLine.arguments
        let requested = Set(arguments.indices.compactMap { index -> String? in
            guard arguments[index] == "--media", index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        })
        let channels = requested.isEmpty ? lineup.availableChannels : lineup.availableChannels.filter { requested.contains($0.id) }
        print("CHECKED AT \(date.ISO8601Format())")
        var failures = 0
        for channel in channels {
            do {
                let row = try await service.guide(channel: channel, at: date)
                print("\(channel.number) \(channel.name): \(row.current.title) [\(row.current.key)]")
                if requested.contains(channel.id) {
                    let resolved = try await service.tune(channel: channel, at: date)
                    print("MEDIA \(resolved.plan.program.title)")
                    print("ARCHIVE \(resolved.plan.archiveID ?? "none"), FILE \(resolved.plan.file ?? "automatic")")
                    print("START \(resolved.plan.program.startMs), END \(resolved.plan.program.endMs), SEEK \(resolved.plan.livePosition(at: date))")
                    print("URL \(resolved.mediaURL?.absoluteString ?? resolved.audioURL?.absoluteString ?? "station card")")
                    print("FALLBACK \(resolved.fallbackURL?.absoluteString ?? "none")")
                }
            } catch {
                failures += 1
                print("ERROR \(channel.id): \(error.localizedDescription)")
            }
        }
        print("\(channels.count) channels, \(failures) errors, engine \(lineup.engine), lineup \(lineup.generatedAt)")
        if failures > 0 { throw BroadcastError.invalidData("\(failures) channels could not be resolved.") }
    }
}
