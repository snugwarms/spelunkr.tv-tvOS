import XCTest
@testable import SpelunkrCore

final class ClickWheelTests: XCTestCase {
    func testClockwiseAndCounterclockwiseScroll() {
        var wheel = ClickWheel()
        var clockwise = 0
        for index in 0...100 {
            let angle = -Double(index) * 2 * .pi / 100
            clockwise += wheel.update(x: cos(angle), y: sin(angle))
        }
        XCTAssertTrue((15...16).contains(clockwise))
        wheel.reset()
        var counterclockwise = 0
        for index in 0...100 {
            let angle = Double(index) * 2 * .pi / 100
            counterclockwise += wheel.update(x: cos(angle), y: sin(angle))
        }
        XCTAssertTrue((-16 ... -15).contains(counterclockwise))
    }

    func testStraightSwipesAndFingerLiftDoNotSpin() {
        var wheel = ClickWheel()
        for x in stride(from: -1.0, through: 1.0, by: 0.05) { XCTAssertEqual(wheel.update(x: x, y: 0), 0) }
        XCTAssertEqual(wheel.update(x: 0, y: 0), 0)
        XCTAssertEqual(wheel.update(x: 0, y: 1), 0)
        XCTAssertEqual(wheel.update(x: 0, y: -1), 0)
    }
}
