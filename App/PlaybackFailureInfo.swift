import AVFoundation
import Foundation

struct PlaybackFailureInfo {
    let title: String
    let message: String
    let details: String
    let shouldRetry: Bool

    static func make(error: Error?, logDomain: String?, logStatus: Int?, logComment: String? = nil, reason: String, host: String, retryAfter: Int) -> PlaybackFailureInfo {
        var chain: [NSError] = []
        var next = error as NSError?
        while let value = next, chain.count < 6 {
            chain.append(value)
            next = value.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        let diagnostic = chain.last.map { "\($0.domain) \($0.code)" }
            ?? logStatus.map { "\(logDomain ?? "HTTP") \($0)" } ?? reason
        let details = "\(diagnostic) · \(host)"
        let retry = "Retrying in \(retryAfter) seconds. You can also select another channel."
        var httpStatus = logStatus
        if let comment = logComment,
           let expression = try? NSRegularExpression(pattern: #"(?i)\bHTTP(?:/[0-9.]+)?\D{0,20}([45]\d{2})\b"#),
           let match = expression.firstMatch(in: comment, range: NSRange(comment.startIndex..., in: comment)),
           let range = Range(match.range(at: 1), in: comment) { httpStatus = Int(comment[range]) }
        if httpStatus == 403 || httpStatus == 401 {
            return PlaybackFailureInfo(title: "VIDEO ACCESS REFUSED", message: "Archive refused access to this recording. \(retry)", details: details, shouldRetry: true)
        }
        if httpStatus == 404 || httpStatus == 410 {
            return PlaybackFailureInfo(title: "RECORDING NOT FOUND", message: "This copy of the recording is missing from Archive. \(retry)", details: details, shouldRetry: true)
        }
        if let network = chain.first(where: { $0.domain == NSURLErrorDomain }) {
            switch network.code {
            case URLError.timedOut.rawValue:
                return PlaybackFailureInfo(title: "VIDEO LOAD TIMED OUT", message: "Archive stopped sending video long enough for playback to stall. \(retry)", details: details, shouldRetry: true)
            case URLError.notConnectedToInternet.rawValue:
                return PlaybackFailureInfo(title: "CONNECTION UNAVAILABLE", message: "Apple TV couldn't reach the video server. Check its network connection. \(retry)", details: details, shouldRetry: true)
            case URLError.secureConnectionFailed.rawValue, URLError.serverCertificateUntrusted.rawValue, URLError.serverCertificateHasBadDate.rawValue:
                return PlaybackFailureInfo(title: "SECURE CONNECTION FAILED", message: "Apple TV couldn't make a secure connection to this recording's server. \(retry)", details: details, shouldRetry: true)
            default:
                return PlaybackFailureInfo(title: "VIDEO SERVER UNREACHABLE", message: "Apple TV couldn't connect to this recording's server. \(retry)", details: details, shouldRetry: true)
            }
        }
        if chain.contains(where: { $0.domain == AVFoundationErrorDomain && $0.code == AVError.Code.decoderNotFound.rawValue }) {
            return PlaybackFailureInfo(title: "FORMAT NOT SUPPORTED", message: "Apple TV couldn't decode this recording's video or audio format. Select another channel, or wait for the next program to start automatically.", details: details, shouldRetry: false)
        }
        if reason == "Loading stalled" {
            return PlaybackFailureInfo(title: "VIDEO LOAD STALLED", message: "No video or download progress arrived from the available servers. \(retry)", details: details, shouldRetry: true)
        }
        return PlaybackFailureInfo(title: "RECORDING COULD NOT PLAY", message: "Apple TV couldn't play the available copies of this recording. \(retry)", details: details, shouldRetry: true)
    }
}
