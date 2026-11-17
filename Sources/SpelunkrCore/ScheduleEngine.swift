import Foundation
import JavaScriptCore

/// Owned exclusively by BroadcastService. No website bootstrap or downloaded code executes here.
final class ScheduleEngine {
    private let context: JSContext

    init() throws {
        guard let context = JSContext() else { throw BroadcastError.invalidData("Could not start the broadcast scheduler.") }
        self.context = context
        for name in ["schedule-engine", "tv-bridge"] {
            guard let url = Bundle.module.url(forResource: name, withExtension: "js") else {
                throw BroadcastError.invalidData("The bundled scheduler is missing.")
            }
            context.evaluateScript(try String(contentsOf: url, encoding: .utf8), withSourceURL: url)
            try checkException()
        }
    }

    private func checkException() throws {
        if let exception = context.exception {
            let message = exception.toString() ?? "Unknown scheduler error"
            context.exception = nil
            throw BroadcastError.invalidData(message)
        }
    }

    func load(channel: Channel, versions: [[String: Any]]) throws {
        let payload: [String: Any] = ["id": channel.id, "versions": versions]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        _ = try call("load", arguments: [String(decoding: data, as: UTF8.self)])
    }

    func guide(id: String, at: Date) throws -> GuideEntry {
        try decode("guide", arguments: [id, at.timeIntervalSince1970 * 1000])
    }

    func tune(id: String, at: Date) throws -> PlaybackPlan {
        try decode("tune", arguments: [id, at.timeIntervalSince1970 * 1000])
    }

    func timeline(id: String, start: Date, end: Date) throws -> [Program] {
        try decode("timeline", arguments: [id, start.timeIntervalSince1970 * 1000, end.timeIntervalSince1970 * 1000])
    }

    private func call(_ name: String, arguments: [Any]) throws -> String {
        let result = context.objectForKeyedSubscript("SpelunkrTV")?.invokeMethod(name, withArguments: arguments)
        try checkException()
        guard let text = result?.toString(), text != "undefined" else {
            throw BroadcastError.invalidData("The scheduler did not return a program.")
        }
        return text
    }

    private func decode<T: Decodable>(_ name: String, arguments: [Any]) throws -> T {
        let text = try call(name, arguments: arguments)
        return try JSONDecoder().decode(T.self, from: Data(text.utf8))
    }
}
