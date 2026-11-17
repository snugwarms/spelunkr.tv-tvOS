import Foundation

/// Keeps slow, progressing downloads alive while bounding genuinely stuck startup/rebuffering.
public struct PlaybackProgressWatchdog: Sendable {
    private let beganAt: TimeInterval
    private var lastProgressAt: TimeInterval
    private var bytes: Int64 = 0
    private var bufferedThrough: Double = 0
    private var position: Double = 0

    public init(at time: TimeInterval) { beganAt = time; lastProgressAt = time }

    public mutating func shouldRetry(at time: TimeInterval, bytes: Int64, bufferedThrough: Double,
                                     position: Double, isStarting: Bool) -> Bool {
        if bytes > self.bytes || bufferedThrough.isFinite && bufferedThrough > self.bufferedThrough + 0.05 ||
            position.isFinite && position > self.position + 0.1 { lastProgressAt = time }
        self.bytes = max(self.bytes, bytes)
        if bufferedThrough.isFinite { self.bufferedThrough = max(self.bufferedThrough, bufferedThrough) }
        if position.isFinite { self.position = position }
        return time - lastProgressAt >= (isStarting ? 60 : 25) || isStarting && time - beganAt >= 120
    }
}
