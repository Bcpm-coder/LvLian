import Foundation

/// Immutable timing anchor for rendering. Drawing never advances training state.
public struct CountdownState: Equatable, Sendable {
    public let duration: Double
    public let remaining: Double
    public let anchoredAt: Double
    public let running: Bool
    public init(duration: Double = 5, remaining: Double = 5, anchoredAt: Double = 0, running: Bool = false) {
        self.duration = max(0.001, duration)
        self.remaining = max(0, remaining)
        self.anchoredAt = anchoredAt
        self.running = running
    }
    public func progress(at now: Double) -> Double {
        let elapsed = running ? max(0, now - anchoredAt) : 0
        return min(1, max(0, 1 - max(0, remaining - elapsed) / duration))
    }
}
