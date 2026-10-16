import Foundation

/// Pure state machine. `now` is monotonic uptime, never wall-clock time.
public struct TrainingMachine: Sendable {
    public enum Phase: String, Sendable { case ready, prepare, contract, relax, paused, completed, interrupted }
    public private(set) var phase: Phase = .ready
    public private(set) var remaining: TimeInterval = 5
    public private(set) var completedRepetitions = 0
    public private(set) var activeDuration: TimeInterval = 0
    public let course: Course
    private var lastTick: TimeInterval = 0
    private var relaxationCreditsRepetition = false

    public init(course: Course) { self.course = course }
    public var isRunning: Bool { [.prepare, .contract, .relax].contains(phase) }
    public var isTerminal: Bool { phase == .completed || phase == .interrupted }
    public var phaseDuration: TimeInterval {
        switch phase {
        case .contract: course.contraction
        case .relax: course.relaxation
        case .prepare: 5
        default: 1
        }
    }

    public mutating func start(at now: TimeInterval) {
        guard phase == .ready else { return }
        phase = .prepare
        remaining = 5
        lastTick = now
    }

    public mutating func tick(at now: TimeInterval) {
        guard isRunning else { return }
        let elapsed = max(0, now - lastTick)
        lastTick = now
        let credited = min(elapsed, remaining)
        if phase != .prepare { activeDuration += credited }
        remaining = max(0, remaining - credited)
        guard remaining <= 0 else { return }
        // Never fast-forward across unseen cues after a delayed UI tick.
        switch phase {
        case .prepare:
            phase = .contract
            remaining = course.contraction
        case .contract:
            phase = .relax
            remaining = course.relaxation
            relaxationCreditsRepetition = true
        case .relax:
            if relaxationCreditsRepetition { completedRepetitions += 1 }
            relaxationCreditsRepetition = false
            if completedRepetitions >= course.repetitions {
                phase = .completed
            } else {
                phase = .contract
                remaining = course.contraction
            }
        default: break
        }
    }

    public mutating func pause(at now: TimeInterval) {
        guard isRunning else { return }
        // Account for the current phase without emitting a new phase cue.
        let credited = min(max(0, now - lastTick), remaining)
        if phase != .prepare { activeDuration += credited }
        remaining = max(0, remaining - credited)
        // An unfinished contraction is not a completed repetition.
        if phase == .contract && remaining == 0 { relaxationCreditsRepetition = true }
        phase = .paused
        lastTick = now
    }

    public mutating func resume(at now: TimeInterval) {
        guard phase == .paused else { return }
        phase = .relax
        remaining = course.relaxation
        lastTick = now
    }

    public mutating func end(at now: TimeInterval) {
        guard !isTerminal else { return }
        if isRunning { pause(at: now) }
        phase = .interrupted
    }
}
