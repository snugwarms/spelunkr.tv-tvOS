import Foundation

/// Ignores bursts from a held arrow before allowing a deliberate, slower repeat.
public struct NavigationRepeatGate: Sendable {
    private var direction = 0
    private var began: Double = 0
    private var lastInput: Double = -.infinity
    private var lastMove: Double = -.infinity
    public init() {}
    public mutating func accept(direction: Int, at time: Double) -> Bool {
        let fresh = direction != self.direction || time - lastInput > 0.22
        lastInput = time
        self.direction = direction
        if fresh {
            began = time
            lastMove = time
            return true
        }
        guard time - began >= 0.50, time - lastMove >= 0.20 else { return false }
        lastMove = time
        return true
    }
}
