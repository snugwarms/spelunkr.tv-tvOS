import Foundation

/// Converts an absolute touch surface trace into circular scroll steps.
public struct ClickWheel: Sendable {
    private var lastAngle: Double?
    private var accumulated: Double = 0
    private var lastTime: TimeInterval?
    private var lastStepAt: TimeInterval = -.infinity
    private var speed: Double = 0
    public init() {}
    public mutating func reset() { lastAngle = nil; lastTime = nil; accumulated = 0; speed = 0; lastStepAt = -.infinity }
    public mutating func update(x: Double, y: Double, timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Int {
        guard hypot(x, y) >= 0.55 else { reset(); return 0 }
        let angle = atan2(y, x)
        defer { lastAngle = angle; lastTime = timestamp }
        guard let previous = lastAngle, let previousTime = lastTime else { return 0 }
        let elapsed = timestamp - previousTime
        guard elapsed > 0, elapsed < 0.25 else { accumulated = 0; speed = 0; return 0 }
        var delta = angle - previous
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }
        // A fresh touch on another edge is not a circular motion.
        guard abs(delta) < 0.9 else { accumulated = 0; return 0 }
        speed = speed * 0.75 + abs(delta) / elapsed * 0.25
        let acceleration = min(1, max(0, (speed - 2) / 10))
        accumulated -= delta * (1 + 0.5 * acceleration * acceleration)
        let threshold = Double.pi / 3 // Six rows per slow turn; gentle gain is capped at 1.5x.
        guard timestamp - lastStepAt >= 0.11 else {
            accumulated = max(-threshold, min(threshold, accumulated))
            return 0
        }
        let steps = max(-1, min(1, Int(accumulated / threshold)))
        accumulated -= Double(steps) * threshold
        if steps != 0 { lastStepAt = timestamp }
        return steps
    }
}
