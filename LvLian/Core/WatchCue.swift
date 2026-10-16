import Foundation

/// Only live, expiring messages travel to the watch. No background delivery queue.
public struct WatchCuePacket: Codable, Sendable {
    public enum Cue: String, Codable, Sendable { case none, single, double }
    public enum WorkoutKind: String, Codable, Sendable { case pelvic, squat }
    public var stream: UUID
    public var sequence: Int
    public var sentAt: Date
    public var workout: UUID
    public var kind: WorkoutKind
    public var title: String
    public var detail: String
    public var remaining: Double
    public var running: Bool
    public var enabled: Bool
    public var cue: Cue
}

/// A completed watch-only squat session. Unlike live cues, this value uses
/// WatchConnectivity's background transfer queue so it can reach the phone later.
public struct WatchSquatResult: Codable, Sendable {
    public var id: UUID
    public var startedAt: Date
    public var endedAt: Date
    public var target: Int
    public var down: Double
    public var up: Double
    public var rest: Double
    public var confirmedSets: [Int]
    public var guidedRepetitions: Int
    public var activeDuration: Double
    public var status: String
    public var revision: Int

    public init(id: UUID, startedAt: Date, endedAt: Date, target: Int,
                down: Double, up: Double, rest: Double, confirmedSets: [Int],
                guidedRepetitions: Int, activeDuration: Double, status: String,
                revision: Int = 1) {
        self.id = id; self.startedAt = startedAt; self.endedAt = endedAt
        self.target = target; self.down = down; self.up = up; self.rest = rest
        self.confirmedSets = confirmedSets; self.guidedRepetitions = guidedRepetitions
        self.activeDuration = activeDuration; self.status = status; self.revision = revision
    }
}

/// One 10-cycle pelvic-floor set completed entirely on Apple Watch.
public struct WatchPelvicResult: Codable, Sendable {
    public var id: UUID
    public var startedAt: Date
    public var endedAt: Date
    public var completedRepetitions: Int
    public var activeDuration: Double
    public var status: String
    public var revision: Int

    public init(id: UUID, startedAt: Date, endedAt: Date,
                completedRepetitions: Int, activeDuration: Double,
                status: String, revision: Int = 1) {
        self.id = id; self.startedAt = startedAt; self.endedAt = endedAt
        self.completedRepetitions = completedRepetitions
        self.activeDuration = activeDuration; self.status = status; self.revision = revision
    }
}

public struct WatchCueGate: Sendable {
    private var stream: UUID?
    private var sequence = -1
    private var newestDate = Date.distantPast
    public init() {}
    public mutating func accept(_ packet: WatchCuePacket, now: Date) -> Bool {
        let age = now.timeIntervalSince(packet.sentAt)
        // Display-only snapshots may arrive through applicationContext after the
        // real-time channel reconnects. Haptic cues keep a strict two-second TTL.
        let maximumAge: TimeInterval = packet.cue == .none ? 15 : 2
        guard age >= -1, age <= maximumAge, packet.sentAt >= newestDate,
              packet.remaining.isFinite, packet.remaining >= 0 else { return false }
        if stream == packet.stream, packet.sequence <= sequence { return false }
        stream = packet.stream; sequence = packet.sequence; newestDate = packet.sentAt
        return true
    }
}
