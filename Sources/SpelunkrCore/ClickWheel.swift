import Foundation

/// Converts an absolute touch surface trace into circular scroll steps.
public struct ClickWheel: Sendable {
    private var lastAngle: Double?
    private var accumulated: Double = 0
    public init() {}
    public mutating func reset() { lastAngle = nil; accumulated = 0 }
    public mutating func update(x: Double, y: Double) -> Int {
        guard hypot(x, y) >= 0.55 else { reset(); return 0 }
        let angle = atan2(y, x)
        defer { lastAngle = angle }
        guard let previous = lastAngle else { return 0 }
        var delta = angle - previous
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }
        // A fresh touch on another edge is not a circular motion.
        guard abs(delta) < 0.9 else { accumulated = 0; return 0 }
        accumulated -= delta
        let threshold = Double.pi / 8
        let steps = Int(accumulated / threshold)
        accumulated -= Double(steps) * threshold
        return steps
    }
}
