import AVFoundation
import Foundation

/// Local, opt-in development audit. Never transmits logs or stores headers or response bodies.
final class NetworkAudit: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = NetworkAudit()
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 8_000_000, diskCapacity: 32_000_000, diskPath: "SpelunkrHTTP")
        configuration.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: configuration, delegate: shared.enabled ? shared : nil, delegateQueue: nil)
    }()
    let enabled = UserDefaults.standard.bool(forKey: "networkAuditEnabled")
    private let lock = NSLock()
    private let startedAt = Date()
    private var requests: [[String: Any]] = []
    private var media: [String: [[String: Any]]] = [:]
    private var lastMediaAt = Date.distantPast
    private var audioProcessing: [String: Any] = [:]

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard enabled else { return }
        lock.lock(); defer { lock.unlock() }
        for transaction in metrics.transactionMetrics {
            guard let url = transaction.request.url else { continue }
            requests.append([
                "at": Date().timeIntervalSince1970,
                "host": url.host ?? "", "path": url.path,
                "query": url.query ?? "", "method": transaction.request.httpMethod ?? "GET",
                "status": (transaction.response as? HTTPURLResponse)?.statusCode ?? 0,
                "source": transaction.resourceFetchType == .localCache ? "local-cache" : "network",
                "fetchStart": transaction.fetchStartDate?.timeIntervalSince1970 ?? 0,
                "responseEnd": transaction.responseEndDate?.timeIntervalSince1970 ?? 0,
                "responseBodyBytes": transaction.countOfResponseBodyBytesReceived
            ])
        }
        write()
    }

    func recordMedia(_ item: AVPlayerItem?, audio: PlaybackAudioStatistics? = nil) {
        guard enabled, let item else { return }
        lock.lock(); defer { lock.unlock() }
        guard Date().timeIntervalSince(lastMediaAt) >= 5 else { return }
        lastMediaAt = Date()
        if let audio {
            audioProcessing = ["processedFrames": audio.frames, "gainDB": audio.gainDB,
                               "processingChannels": audio.channels,
                               "outputChannels": AVAudioSession.sharedInstance().outputNumberOfChannels,
                               "preferredOutputChannels": AVAudioSession.sharedInstance().preferredOutputNumberOfChannels,
                               "spatializationFormats": item.allowedAudioSpatializationFormats.rawValue,
                               "inputLUFS": audio.inputLUFS.isFinite ? audio.inputLUFS as Any : NSNull()]
        }
        media[String(describing: ObjectIdentifier(item))] = (item.accessLog()?.events ?? []).map {
            ["uri": $0.uri ?? "", "requests": $0.numberOfMediaRequests, "bytes": $0.numberOfBytesTransferred]
        }
        write()
    }

    private func write() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let report: [String: Any] = [
            "startedAt": startedAt.timeIntervalSince1970, "updatedAt": Date().timeIntervalSince1970,
            "apiTransactions": requests, "playerAccessLogs": media, "audioProcessing": audioProcessing
        ]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: directory.appendingPathComponent("network-audit.json"), options: .atomic)
        }
    }
}
