import XCTest
@testable import SpelunkrCore

final class PlaybackBoundaryTests: XCTestCase {
    private func plan() throws -> PlaybackPlan {
        try JSONDecoder().decode(PlaybackPlan.self, from: Data("""
        {"program":{"key":"1:0:0","type":"video","id":"tape","title":"Tape","year":"1983","startMs":1000000,"endMs":1600000},
         "archiveID":"tape","file":"tape.mp4","inPoint":120,"cards":[],"audioInPoint":0}
        """.utf8))
    }

    func testUserCannotSeekBeyondTheCurrentLivePosition() throws {
        let plan = try plan(), now = Date(timeIntervalSince1970: 1100)
        XCTAssertEqual(plan.livePosition(at: now), 220)
        XCTAssertEqual(plan.clampedSeek(10000, at: now), 220)
        XCTAssertEqual(plan.clampedSeek(180, at: now), 180)
        XCTAssertEqual(plan.clampedSeek(0, at: now), 120)
        XCTAssertEqual(plan.clampedSeek(.nan, at: now), 120)
        XCTAssertEqual(plan.livePosition(at: Date(timeIntervalSince1970: 2000)), 720)
    }

    func testArrowBurstMovesOneRowBeforeHeldKeyRepeating() {
        var gate = NavigationRepeatGate()
        XCTAssertTrue(gate.accept(direction: 1, at: 0))
        for i in 1..<50 { XCTAssertFalse(gate.accept(direction: 1, at: Double(i) / 100)) }
        XCTAssertTrue(gate.accept(direction: 1, at: 0.50))
        XCTAssertFalse(gate.accept(direction: 1, at: 0.55))
        XCTAssertTrue(gate.accept(direction: 1, at: 0.71))
        XCTAssertTrue(gate.accept(direction: 2, at: 0.73), "A direction change should respond immediately")
        XCTAssertTrue(gate.accept(direction: 2, at: 1.1), "A separate tap should respond immediately")
    }
}
