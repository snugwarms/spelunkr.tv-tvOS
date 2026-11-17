import XCTest
@testable import SpelunkrCore

final class PlaybackProgressWatchdogTests: XCTestCase {
    func testSlowProgressingStartupSurvivesTheOld25SecondCutoff() {
        var monitor = PlaybackProgressWatchdog(at: 0)
        for time in stride(from: 5.0, through: 115, by: 5) {
            XCTAssertFalse(monitor.shouldRetry(at: time, bytes: Int64(time * 1000), bufferedThrough: 0, position: 0, isStarting: true))
        }
        XCTAssertTrue(monitor.shouldRetry(at: 120, bytes: 120_000, bufferedThrough: 0, position: 0, isStarting: true), "Bound even a trickling startup")
    }

    func testStartupWithoutProgressGets60Seconds() {
        var monitor = PlaybackProgressWatchdog(at: 0)
        XCTAssertFalse(monitor.shouldRetry(at: 25, bytes: 0, bufferedThrough: 0, position: 0, isStarting: true))
        XCTAssertFalse(monitor.shouldRetry(at: 59, bytes: 0, bufferedThrough: 0, position: 0, isStarting: true))
        XCTAssertTrue(monitor.shouldRetry(at: 60, bytes: 0, bufferedThrough: 0, position: 0, isStarting: true))
    }

    func testRebufferingRetriesAfter25SecondsWithoutProgress() {
        var monitor = PlaybackProgressWatchdog(at: 100)
        XCTAssertFalse(monitor.shouldRetry(at: 124, bytes: 0, bufferedThrough: .nan, position: .nan, isStarting: false))
        XCTAssertTrue(monitor.shouldRetry(at: 125, bytes: 0, bufferedThrough: .nan, position: .nan, isStarting: false))
    }

    func testDownloadedBytesBufferedMediaAndClockEachKeepAStallAlive() {
        var monitor = PlaybackProgressWatchdog(at: 0)
        XCTAssertFalse(monitor.shouldRetry(at: 20, bytes: 1024, bufferedThrough: 0, position: 0, isStarting: false))
        XCTAssertFalse(monitor.shouldRetry(at: 40, bytes: 1024, bufferedThrough: 10, position: 0, isStarting: false))
        XCTAssertFalse(monitor.shouldRetry(at: 60, bytes: 1024, bufferedThrough: 10, position: 2, isStarting: false))
        XCTAssertFalse(monitor.shouldRetry(at: 84, bytes: 1024, bufferedThrough: 10, position: 2, isStarting: false))
        XCTAssertTrue(monitor.shouldRetry(at: 85, bytes: 1024, bufferedThrough: 10, position: 2, isStarting: false))
    }
}
