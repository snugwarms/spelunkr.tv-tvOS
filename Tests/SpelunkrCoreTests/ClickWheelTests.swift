import XCTest
@testable import SpelunkrCore

final class ClickWheelTests: XCTestCase {
    func testClockwiseAndCounterclockwiseScroll() {
        var wheel = ClickWheel()
        var clockwise = 0
        for index in 0...100 {
            let angle = -Double(index) * 2 * .pi / 100
            clockwise += wheel.update(x: cos(angle), y: sin(angle), timestamp: Double(index) * 0.02)
        }
        XCTAssertTrue((5...6).contains(clockwise))
        wheel.reset()
        var counterclockwise = 0
        for index in 0...100 {
            let angle = Double(index) * 2 * .pi / 100
            counterclockwise += wheel.update(x: cos(angle), y: sin(angle), timestamp: Double(index) * 0.02)
        }
        XCTAssertTrue((-6 ... -5).contains(counterclockwise))
    }

    func testAccelerationIsGentleAndFastInputCannotBurst() {
        func scroll(duration: Double) -> [(Double, Int)] {
            var wheel = ClickWheel(), steps: [(Double, Int)] = []
            for index in 0...600 {
                let time = Double(index) / 600 * duration
                let angle = -Double(index) / 600 * 6 * .pi
                let step = wheel.update(x: cos(angle), y: sin(angle), timestamp: time)
                if step != 0 { steps.append((time, step)) }
            }
            return steps
        }
        let slow = scroll(duration: 12), quick = scroll(duration: 3), veryFast = scroll(duration: 1)
        XCTAssertTrue((17...18).contains(slow.count))
        XCTAssertGreaterThanOrEqual(quick.count, slow.count)
        XCTAssertLessThanOrEqual(quick.count, slow.count + 4)
        XCTAssertTrue(veryFast.allSatisfy { abs($0.1) == 1 })
        for (previous, next) in zip(veryFast, veryFast.dropFirst()) { XCTAssertGreaterThanOrEqual(next.0 - previous.0, 0.109) }
    }

    func testStraightSwipesAndFingerLiftDoNotSpin() {
        var wheel = ClickWheel()
        for x in stride(from: -1.0, through: 1.0, by: 0.05) { XCTAssertEqual(wheel.update(x: x, y: 0), 0) }
        XCTAssertEqual(wheel.update(x: 0, y: 0), 0)
        XCTAssertEqual(wheel.update(x: 0, y: 1), 0)
        XCTAssertEqual(wheel.update(x: 0, y: -1), 0)
    }
}
