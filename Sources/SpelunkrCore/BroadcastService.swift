import Foundation

public actor BroadcastService {
    private static let requestLimiter = BroadcastRequestLimiter()
    public static let roots = [URL(string: "https://data.spelunkr.tv/")!, URL(string: "https://spelunkr.tv/broadcast/")!]
    private let session: URLSession
    private let roots: [URL]
    private var preferredRoot: URL
    private var lineupData: Lineup?
    private var lineupAt = Date.distantPast
    private var assets: [String: Data] = [:]
    private var pendingAssets: [String: Task<Data, Error>] = [:]
    private var signatures: [String: [VersionPointer]] = [:]
    private var metadata: [String: ArchiveMetadata] = [:]
    private var scheduler: ScheduleEngine?
    public private(set) var usingCachedLineup = false

    public init(session: URLSession = .shared, roots: [URL] = BroadcastService.roots) {
        self.session = session
        self.roots = roots
        self.preferredRoot = roots.first ?? BroadcastService.roots[0]
    }

    public func lineup(force: Bool = false) async throws -> Lineup {
        if !force, let lineupData, Date().timeIntervalSince(lineupAt) < NetworkPolicy.lineupRefreshInterval { return lineupData }
        var lastError: Error = BroadcastError.invalidData("The broadcast guide is unavailable.")
        // Retry the live host on each refresh even when the previous refresh used a snapshot.
        for root in roots {
            do {
                let data = try await Self.fetch(root.appendingPathComponent("lineup.json"), session: session, policy: .reloadRevalidatingCacheData)
                let lineup = try JSONDecoder().decode(Lineup.self, from: data)
                guard lineup.engine <= 5 else { throw BroadcastError.unsupportedEngine(lineup.engine) }
                guard !lineup.availableChannels.isEmpty else { throw BroadcastError.invalidData("The broadcast guide is empty.") }
                lineupData = lineup
                lineupAt = Date()
                preferredRoot = root
                usingCachedLineup = false
                return lineup
            } catch let error as BroadcastError {
                if case .unsupportedEngine = error { throw error }
                lastError = error
            } catch { lastError = error }
        }
        if let lineupData {
            usingCachedLineup = true
            lineupAt = Date()
            return lineupData
        }
        throw lastError
    }

    public func guide(channel: Channel, at: Date = Date()) async throws -> GuideEntry {
        try await ensureLoaded(channel)
        return try engine().guide(id: channel.id, at: at)
    }

    public func timeline(channel: Channel, start: Date, end: Date) async throws -> [Program] {
        try await ensureLoaded(channel)
        return try engine().timeline(id: channel.id, start: start, end: end)
    }

    public func tune(channel: Channel, at: Date = Date()) async throws -> ResolvedPlayback {
        try await ensureLoaded(channel)
        let plan = try engine().tune(id: channel.id, at: at)
        var mediaURL: URL?, alternateMediaURLs: [URL] = [], audioURL: URL?
        if plan.isVideo, let id = plan.archiveID {
            let result = try await resolveMedia(id: id, file: plan.file)
            mediaURL = result.primary
            alternateMediaURLs = result.alternates
        }
        if let filename = plan.audioFile {
            // The metadata's audio attribution URL is not a stream URL.
            if let base = URL(string: lineupData?.audioBase ?? "https://audio.spelunkr.tv/bumps/"), base.scheme == "https" {
                audioURL = base.appendingPathComponent(filename)
            }
        }
        return ResolvedPlayback(plan: plan, mediaURL: mediaURL, alternateMediaURLs: alternateMediaURLs, audioURL: audioURL,
                                synopsis: plan.program.synopsis ?? plan.archiveID.flatMap { metadata[$0]?.synopsis })
    }

    private func engine() throws -> ScheduleEngine {
        if let scheduler { return scheduler }
        let value = try ScheduleEngine()
        scheduler = value
        return value
    }

    private func ensureLoaded(_ channel: Channel) async throws {
        if signatures[channel.id] == channel.versions { return }
        var versions: [[String: Any]] = []
        for pointer in channel.versions {
            let manifestData = try await asset(pointer.manifest)
            guard let manifest = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any] else {
                throw BroadcastError.invalidData("Invalid manifest for \(channel.name).")
            }
            let version = manifest["engine"] as? Int ?? 0
            guard version <= 5 else { throw BroadcastError.unsupportedEngine(version) }
            var platform: Any = NSNull()
            if let path = manifest["platform"] as? String {
                platform = try JSONSerialization.jsonObject(with: await asset(path))
            }
            let pointerData = try JSONEncoder().encode(pointer)
            versions.append(["manifest": manifest, "platform": platform, "pointer": try JSONSerialization.jsonObject(with: pointerData)])
        }
        try engine().load(channel: channel, versions: versions)
        signatures[channel.id] = channel.versions
    }

    private func orderedRoots() -> [URL] { [preferredRoot] + roots.filter { $0 != preferredRoot } }

    private func asset(_ path: String) async throws -> Data {
        if let data = assets[path] { return data }
        if let task = pendingAssets[path] { return try await task.value }
        let roots = orderedRoots(), session = session
        let task = Task<Data, Error> {
            var lastError: Error = BroadcastError.invalidData("Invalid broadcast asset path.")
            for root in roots {
                guard let url = MediaURL.asset(path: path, base: root) else { throw lastError }
                do { return try await Self.fetch(url, session: session) }
                catch { lastError = error }
            }
            throw lastError
        }
        pendingAssets[path] = task
        defer { pendingAssets[path] = nil }
        let data = try await task.value
        if assets.count > 200 { assets.removeAll(keepingCapacity: true) }
        assets[path] = data
        return data
    }

    private func request(_ url: URL) async throws -> Data { try await Self.fetch(url, session: session) }

    private static func fetch(_ url: URL, session: URLSession, policy: URLRequest.CachePolicy = .useProtocolCachePolicy) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: policy, timeoutInterval: 12)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // The public broadcast hosts require the site's origin, just as their browser client sends it.
        // Do not forward these headers to Archive metadata or other hosts.
        if ["data.spelunkr.tv", "spelunkr.tv"].contains(url.host?.lowercased() ?? "") {
            request.setValue("https://spelunkr.tv", forHTTPHeaderField: "Origin")
            request.setValue("https://spelunkr.tv/", forHTTPHeaderField: "Referer")
        }
        await requestLimiter.acquire()
        let data: Data, response: URLResponse
        do {
            try Task.checkCancellation()
            (data, response) = try await session.data(for: request)
            await requestLimiter.release()
        } catch {
            await requestLimiter.release()
            throw error
        }
        guard let response = response as? HTTPURLResponse else { throw BroadcastError.invalidData("Invalid server response.") }
        guard (200..<300).contains(response.statusCode) else { throw BroadcastError.http(response.statusCode) }
        return data
    }

    private func resolveMedia(id: String, file: String?) async throws -> (primary: URL, alternates: [URL]) {
        var info = metadata[id]
        if info == nil {
            let url = URL(string: "https://archive.org/metadata/")!.appendingPathComponent(id)
            // Known filenames can still play through Archive's normal redirect if metadata is unavailable.
            if let data = try? await request(url), let decoded = try? JSONDecoder().decode(ArchiveMetadata.self, from: data) {
                info = decoded
                if metadata.count > 80 { metadata.removeAll(keepingCapacity: true) }
                metadata[id] = decoded
            }
        }
        let filename = info?.playbackFilename(requested: file) ?? file.flatMap { ["mp4", "m4v", "mov"].contains(($0 as NSString).pathExtension.lowercased()) ? $0 : nil }
        guard let filename, let redirect = MediaURL.archive(id: id, file: filename) else { throw BroadcastError.noVideo }
        var candidates = info?.directURLs(file: filename) ?? []
        if !candidates.contains(redirect) { candidates.append(redirect) }
        return (candidates[0], Array(candidates.dropFirst()))
    }

    public func tapeSynopsis(id: String) async throws -> String? {
        if let saved = metadata[id] { return saved.synopsis }
        let url = URL(string: "https://archive.org/metadata/")!.appendingPathComponent(id)
        let value = try JSONDecoder().decode(ArchiveMetadata.self, from: await request(url))
        if metadata.count > 80 { metadata.removeAll(keepingCapacity: true) }
        metadata[id] = value
        return value.synopsis
    }
}

struct ArchiveMetadata: Decodable {
    struct DescriptiveMetadata: Decodable {
        let description: String?
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            description = (try? values.decode(String.self, forKey: .description)) ?? (try? values.decode([String].self, forKey: .description).joined(separator: " "))
        }
        private enum CodingKeys: String, CodingKey { case description }
    }
    struct File: Decodable { let name: String; let format: String?; let original: String? }
    struct Location: Decodable { let server: String?; let dir: String? }
    struct Alternate: Decodable { let servers: [Location]?; let workable: [Location]? }
    let server: String?
    let d1: String?
    let d2: String?
    let dir: String?
    let files: [File]?
    let alternate_locations: Alternate?
    let metadata: DescriptiveMetadata?
    var synopsis: String? {
        guard let raw = metadata?.description else { return nil }
        let text = raw.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return text.isEmpty ? nil : text
    }

    func playbackFilename(requested: String?) -> String? {
        let videos = files?.filter { ["mp4", "m4v", "mov"].contains(($0.name as NSString).pathExtension.lowercased()) } ?? []
        let h264 = videos.filter { $0.format?.lowercased().hasPrefix("h.264") == true }
            .sorted { ($0.format?.lowercased() == "h.264 ia" ? 0 : 1) < ($1.format?.lowercased() == "h.264 ia" ? 0 : 1) }
        guard let requested else { return (h264.first ?? videos.first)?.name }
        let source = files?.first { $0.name == requested }
        if source?.format?.lowercased().hasPrefix("h.264") == true { return requested }
        // Archive often already has an H.264 conversion of an unsupported original.
        // Match its provenance so multi-episode items never switch to an unrelated recording.
        if let converted = h264.first(where: {
            $0.original == requested || (source?.original != nil && $0.original == source?.original)
        }) { return converted.name }
        if ["mp4", "m4v", "mov"].contains((requested as NSString).pathExtension.lowercased()) { return requested }
        return h264.count == 1 ? h264[0].name : nil
    }

    func directURL(file: String) -> URL? { directURLs(file: file).first }

    func directURLs(file: String) -> [URL] {
        let locations = [Location(server: server, dir: dir), Location(server: d1, dir: dir), Location(server: d2, dir: dir)] +
            (alternate_locations?.workable ?? []) +
            (alternate_locations?.servers ?? [])
        var result: [URL] = []
        for location in locations {
            guard let host = location.server?.lowercased(),
                  host == "archive.org" || host.hasSuffix(".archive.org"),
                  !host.contains("/"), !host.contains(":"), !host.contains("@"),
                  let directory = location.dir ?? dir,
                  !directory.contains(".."), !file.split(separator: "/").contains(".."),
                  let base = URL(string: "https://\(host)") else { continue }
            let url = base.appendingPathComponent(directory).appendingPathComponent(file)
            if !result.contains(url) { result.append(url) }
        }
        return Array(result.prefix(5))
    }
}
