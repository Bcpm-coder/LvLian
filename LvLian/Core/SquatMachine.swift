import Foundation

public struct SquatPlan: Codable, Equatable, Sendable {
    public let target: Int
    public let down: Double
    public let up: Double
    public let rest: Double
    public var sets: [Int] {
        stride(from: 0, to: target, by: 10).map { min(10, target - $0) }
    }
    public init(target: Int = 50, down: Double = 2, up: Double = 2, rest: Double = 30) {
        self.target = min(50, max(1, target))
        self.down = min(5, max(1, down))
        self.up = min(5, max(1, up))
        self.rest = min(120, max(15, rest))
    }
}

public struct SquatDay: Sendable {
    public let id: UUID
    public let dayKey: String
    public let confirmed: Int
    public init(id: UUID, dayKey: String, confirmed: Int) {
        self.id = id; self.dayKey = dayKey; self.confirmed = max(0, confirmed)
    }
}

public enum SquatProgress {
    public static func totals(_ records: [SquatDay]) -> [String: Int] {
        // A checkpoint replaces the same session instead of adding more repetitions.
        let unique = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        return unique.values.reduce(into: [:]) { $0[$1.dayKey, default: 0] += $1.confirmed }
    }
    public static func remaining(_ records: [SquatDay], dayKey: String) -> Int {
        max(0, 50 - (totals(records)[dayKey] ?? 0))
    }
}

public struct SquatMachine: Sendable {
    public enum Phase: String, Sendable {
        case ready, prepare, down, up, confirm, rest, resuming, paused, completed, interrupted
    }
    public let plan: SquatPlan
    public private(set) var phase: Phase = .ready
    public private(set) var remaining: Double = 5
    public private(set) var setIndex = 0
    public private(set) var guidedInSet = 0
    public private(set) var guidedTotal = 0
    public private(set) var confirmedSets: [Int] = []
    public private(set) var activeDuration: Double = 0
    public private(set) var hasBegunCurrentSet = false
    private var lastTick: Double = 0
    private var pausedFrom: Phase = .ready
    public var setTarget: Int { plan.sets[min(setIndex, plan.sets.count - 1)] }
    public var confirmedTotal: Int { confirmedSets.reduce(0, +) }
    public var isRunning: Bool { [.prepare, .down, .up, .rest, .resuming].contains(phase) }
    public var isTerminal: Bool { phase == .completed || phase == .interrupted }
    public var phaseDuration: Double {
        switch phase {
        case .prepare: 5
        case .resuming: 3
        case .down: plan.down
        case .up: plan.up
        case .rest: plan.rest
        default: 1
        }
    }
    public init(plan: SquatPlan) { self.plan = plan }
    public mutating func start(at now: Double) {
        guard phase == .ready else { return }
        phase = .prepare; remaining = 5; lastTick = now
    }
    public mutating func tick(at now: Double) {
        guard isRunning else { return }
        let elapsed = min(remaining, max(0, now - lastTick))
        lastTick = now
        if phase == .down || phase == .up { activeDuration += elapsed }
        remaining = max(0, remaining - elapsed)
        guard remaining <= 0 else { return }
        switch phase {
        case .prepare, .resuming, .rest: beginDown()
        case .down: phase = .up; remaining = plan.up
        case .up:
            guidedInSet += 1; guidedTotal += 1
            if guidedInSet == setTarget { phase = .confirm } else { beginDown() }
        default: break
        }
    }
    private mutating func beginDown() {
        hasBegunCurrentSet = true
        phase = .down; remaining = plan.down
    }
    public mutating func confirmSet(actual: Int, at now: Double) {
        guard phase == .confirm else { return }
        confirmedSets.append(min(setTarget, max(0, actual)))
        hasBegunCurrentSet = false
        if setIndex + 1 == plan.sets.count {
            phase = .completed; remaining = 0
        } else {
            setIndex += 1; guidedInSet = 0
            phase = .rest; remaining = plan.rest; lastTick = now
        }
    }
    public mutating func pause(at now: Double) {
        guard isRunning else { return }
        tick(at: now)
        guard isRunning else { return }
        pausedFrom = phase; phase = .paused
    }
    public mutating func resume(at now: Double) {
        guard phase == .paused else { return }
        if pausedFrom == .rest { phase = .rest }
        else { phase = .resuming; remaining = 3 }
        lastTick = now
    }
    public mutating func end(actualInCurrentSet: Int = 0, at now: Double) {
        guard !isTerminal else { return }
        if isRunning { pause(at: now) }
        if hasBegunCurrentSet && actualInCurrentSet > 0 {
            confirmedSets.append(min(setTarget, max(0, actualInCurrentSet)))
        }
        hasBegunCurrentSet = false
        phase = .interrupted
    }
}
