import AVFoundation
import XCTest

final class PlaybackFailureInfoTests: XCTestCase {
    func testAStallExplainsTheCauseAndRetryTiming() {
        let info = PlaybackFailureInfo.make(error: nil, logDomain: nil, logStatus: nil, reason: "Loading stalled", host: "archive.org", retryAfter: 10)
        XCTAssertEqual(info.title, "VIDEO LOAD STALLED")
        XCTAssertTrue(info.message.contains("Retrying in 10 seconds"))
        XCTAssertTrue(info.shouldRetry)
    }

    func testUnderlyingNetworkErrorsAreNotReportedAsAnUnsupportedCodec() {
        let error = NSError(domain: AVFoundationErrorDomain, code: AVError.Code.unknown.rawValue,
                            userInfo: [NSUnderlyingErrorKey: NSError(domain: NSURLErrorDomain, code: URLError.timedOut.rawValue)])
        let info = PlaybackFailureInfo.make(error: error, logDomain: nil, logStatus: nil, reason: "Player rejected the tape", host: "server.archive.org", retryAfter: 5)
        XCTAssertEqual(info.title, "VIDEO LOAD TIMED OUT")
        XCTAssertTrue(info.details.contains("-1001"))
        XCTAssertTrue(info.shouldRetry)
    }

    func testMissingAndDeniedFilesHaveDifferentMessages() {
        let missing = PlaybackFailureInfo.make(error: nil, logDomain: "HTTP", logStatus: 404, reason: "Playback stopped", host: "archive.org", retryAfter: 5)
        let denied = PlaybackFailureInfo.make(error: nil, logDomain: "HTTP", logStatus: 403, reason: "Playback stopped", host: "archive.org", retryAfter: 5)
        XCTAssertEqual(missing.title, "RECORDING NOT FOUND")
        XCTAssertEqual(denied.title, "VIDEO ACCESS REFUSED")
    }

    func testUnsupportedCodecsDoNotRepeatedlyRequestTheSameFile() {
        let error = NSError(domain: AVFoundationErrorDomain, code: AVError.Code.decoderNotFound.rawValue)
        let info = PlaybackFailureInfo.make(error: error, logDomain: nil, logStatus: nil, reason: "Player rejected the tape", host: "archive.org", retryAfter: 5)
        XCTAssertEqual(info.title, "FORMAT NOT SUPPORTED")
        XCTAssertFalse(info.shouldRetry)
        XCTAssertTrue(info.message.contains("next program"))
    }

    func testAnUnreadableHttpResponseIsNotMistakenForAnUnsupportedCodec() {
        let error = NSError(domain: AVFoundationErrorDomain, code: AVError.Code.fileFormatNotRecognized.rawValue)
        let info = PlaybackFailureInfo.make(error: error, logDomain: "CoreMediaErrorDomain", logStatus: -12938,
                                             logComment: "HTTP 404: File Not Found", reason: "Playback stopped", host: "archive.org", retryAfter: 5)
        XCTAssertEqual(info.title, "RECORDING NOT FOUND")
        XCTAssertTrue(info.shouldRetry)
    }
}
