import Foundation
import SpelunkrCore

@main
struct Probe {
    static func main() async throws {
        let service = BroadcastService()
        let lineup = try await service.lineup()
        let date = Date()
        var failures = 0
        for channel in lineup.availableChannels {
            do {
                let row = try await service.guide(channel: channel, at: date)
                print("\(channel.number) \(channel.name): \(row.current.title) [\(row.current.key)]")
            } catch {
                failures += 1
                print("ERROR \(channel.id): \(error.localizedDescription)")
            }
        }
        print("\(lineup.availableChannels.count) channels, \(failures) errors, engine \(lineup.engine), lineup \(lineup.generatedAt)")
        if let index = CommandLine.arguments.firstIndex(of: "--media"), CommandLine.arguments.count > index + 1,
           let channel = lineup.availableChannels.first(where: { $0.id == CommandLine.arguments[index + 1] }) {
            let resolved = try await service.tune(channel: channel)
            print("MEDIA \(resolved.plan.program.title)")
            print("START \(resolved.plan.program.startMs), END \(resolved.plan.program.endMs), SEEK \(resolved.plan.inPoint + resolved.plan.offset(at: Date()))")
            print("URL \(resolved.mediaURL?.absoluteString ?? resolved.audioURL?.absoluteString ?? "station card")")
        }
        if failures > 0 { throw BroadcastError.invalidData("\(failures) channels could not be resolved.") }
    }
}
