import XCTest
@testable import SpelunkrCore

final class ScheduleEngineTests: XCTestCase {
    private func fixture() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "website-schedule", withExtension: "json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func loadedEngine(_ fixture: [String: Any]) throws -> ScheduleEngine {
        let engine = try ScheduleEngine()
        let json: [String: Any] = ["id": "computer-chronicles", "name": "COMPUTER CHRONICLES", "dial": 13, "versions": [fixture["pointer"]!]]
        let channel = try JSONDecoder().decode(Channel.self, from: JSONSerialization.data(withJSONObject: json))
        try engine.load(channel: channel, versions: [["pointer": fixture["pointer"]!, "manifest": fixture["manifest"]!, "platform": fixture["platform"]!]])
        return engine
    }

    func testObservedWebsitePositionMatchesExactly() throws {
        let fixture = try fixture(), engine = try loadedEngine(fixture)
        let at = try XCTUnwrap(fixture["observedAt"] as? Double)
        let expected = try XCTUnwrap(fixture["expected"] as? [String: Any])
        let plan = try engine.tune(id: "computer-chronicles", at: Date(timeIntervalSince1970: at / 1000))
        XCTAssertEqual(plan.program.key, expected["key"] as? String)
        XCTAssertEqual(plan.program.id, expected["id"] as? String)
        XCTAssertEqual(plan.program.startMs, expected["startMs"] as? Double)
        XCTAssertEqual(plan.program.endMs, expected["endMs"] as? Double)
        XCTAssertEqual(floor(plan.offset(at: Date(timeIntervalSince1970: at / 1000))), expected["offset"] as? Double)
        XCTAssertNotNil(plan.file)
    }

    func testBoundaryTransitionsAdvanceAndGuideFindsNextVideo() throws {
        let fixture = try fixture(), engine = try loadedEngine(fixture)
        let at = try XCTUnwrap(fixture["observedAt"] as? Double)
        var date = Date(timeIntervalSince1970: at / 1000)
        var sawBreak = false
        for _ in 0..<40 {
            let current = try engine.tune(id: "computer-chronicles", at: date)
            XCTAssertGreaterThan(current.program.end, date)
            let next = try engine.tune(id: "computer-chronicles", at: current.program.end)
            XCTAssertNotEqual(next.program.key, current.program.key)
            XCTAssertEqual(next.program.startMs, current.program.endMs)
            if !next.isVideo { sawBreak = true; XCTAssertFalse(next.cards.isEmpty) }
            date = current.program.end
        }
        XCTAssertTrue(sawBreak)
        let guide = try engine.guide(id: "computer-chronicles", at: date)
        XCTAssertEqual(guide.next?.type, "video")
        XCTAssertGreaterThan(try XCTUnwrap(guide.next?.start), date)
    }

    func testBeforeEpochAndVersionCutover() throws {
        let engine = try ScheduleEngine()
        let pointer: [String: Any] = ["v": 1, "manifest": "manifests/test/v1.json", "epochMs": 1_000_000, "startIndex": 0]
        let newer: [String: Any] = ["v": 2, "manifest": "manifests/test/v2.json", "epochMs": 1_005_000, "effectiveAtMs": 1_005_000, "startIndex": 0]
        let first: [String: Any] = ["engine": 5, "items": [["id": "a", "title": "First tape", "duration": 10, "mp4": "a.mp4"]]]
        let second: [String: Any] = ["engine": 5, "items": [["id": "b", "title": "New tape", "duration": 20, "mp4": "b.mp4"]]]
        let data = try JSONSerialization.data(withJSONObject: ["id": "test", "name": "TEST", "versions": [pointer, newer]])
        let channel = try JSONDecoder().decode(Channel.self, from: data)
        try engine.load(channel: channel, versions: [
            ["manifest": first, "platform": NSNull(), "pointer": pointer],
            ["manifest": second, "platform": NSNull(), "pointer": newer]
        ])
        let before = try engine.tune(id: "test", at: Date(timeIntervalSince1970: 999))
        XCTAssertEqual(before.program.id, "a")
        let truncated = try engine.tune(id: "test", at: Date(timeIntervalSince1970: 1004))
        XCTAssertEqual(truncated.program.endMs, 1_005_000)
        let cutover = try engine.tune(id: "test", at: Date(timeIntervalSince1970: 1005))
        XCTAssertEqual(cutover.program.id, "b")
        XCTAssertEqual(cutover.program.startMs, 1_005_000)
    }

    func testTrimAndAdInPointsArePreserved() throws {
        let engine = try ScheduleEngine()
        let pointer: [String: Any] = ["v": 1, "manifest": "manifests/trim/v1.json", "epochMs": 1_000_000]
        let channelData = try JSONSerialization.data(withJSONObject: ["id": "trim", "name": "TRIM", "versions": [pointer]])
        let channel = try JSONDecoder().decode(Channel.self, from: channelData)
        let bump: [String: Any] = ["id": "break", "slides": [["text": "Station break"]]]
        let manifest: [String: Any] = [
            "engine": 5, "items": [["id": "trimmed", "title": "Trimmed tape", "duration": 1500, "inS": 120, "mp4": "tape.mp4"]],
            "bumps": [bump], "audio": [],
            "ads": ["slices": [["id": "ad", "tape": "ad-tape", "file": "ad.mp4", "inMs": 12345, "lengthMs": 30000]]]
        ]
        try engine.load(channel: channel, versions: [["pointer": pointer, "manifest": manifest, "platform": ["bumps": [bump], "audio": []]]])
        let plan = try engine.tune(id: "trim", at: Date(timeIntervalSince1970: 1005))
        XCTAssertEqual(plan.inPoint + plan.offset(at: Date(timeIntervalSince1970: 1005)), 125)
        var date = plan.program.end
        var ad: PlaybackPlan?
        for _ in 0..<6 {
            let next = try engine.tune(id: "trim", at: date)
            if next.program.type == "ad" { ad = next; break }
            date = next.program.end
        }
        XCTAssertEqual(ad?.archiveID, "ad-tape")
        XCTAssertEqual(ad?.file, "ad.mp4")
        XCTAssertEqual(ad?.inPoint, 12.345)
    }

    func testMalformedManifestThrowsInsteadOfHanging() throws {
        let engine = try ScheduleEngine()
        let channel = try JSONDecoder().decode(Channel.self, from: Data("{\"id\":\"bad\",\"name\":\"BAD\",\"versions\":[]}".utf8))
        XCTAssertThrowsError(try engine.load(channel: channel, versions: [["manifest": ["items": []], "platform": NSNull(), "pointer": ["v": 1, "epochMs": 0]]]))
        XCTAssertThrowsError(try engine.guide(id: "missing", at: Date()))
    }

    func testFullGuideCoversTwoHoursWithoutGaps() throws {
        let fixture = try fixture(), engine = try loadedEngine(fixture)
        let at = try XCTUnwrap(fixture["observedAt"] as? Double)
        let start = Date(timeIntervalSince1970: floor(at / 1_800_000) * 1800)
        let end = start.addingTimeInterval(7200)
        let programs = try engine.timeline(id: "computer-chronicles", start: start, end: end)
        XCTAssertLessThanOrEqual(try XCTUnwrap(programs.first?.start), start)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(programs.last?.end), end)
        for index in 1..<programs.count {
            XCTAssertEqual(programs[index - 1].endMs, programs[index].startMs)
            XCTAssertEqual(programs[index].type, "video")
        }
    }
}
