import Foundation

public struct Course: Identifiable, Codable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let contraction: TimeInterval
    public let relaxation: TimeInterval
    public let repetitions: Int

    public var duration: TimeInterval { (contraction + relaxation) * Double(repetitions) }

    // A separate identifier keeps the personal rhythm out of stage progression.
    public static let personal = Course(id: 100, name: "5 秒收缩 · 5 秒放松", contraction: 5, relaxation: 5, repetitions: 10)
    public var isPersonal: Bool { id == Self.personal.id }

    public static let stages: [Course] = [
        Course(id: 0, name: "感知", contraction: 3, relaxation: 6, repetitions: 8),
        Course(id: 1, name: "熟悉", contraction: 3, relaxation: 6, repetitions: 10),
        Course(id: 2, name: "控制", contraction: 4, relaxation: 8, repetitions: 10),
        Course(id: 3, name: "巩固", contraction: 5, relaxation: 10, repetitions: 10)
    ]

    public static func stage(_ index: Int) -> Course {
        stages[min(max(index, 0), stages.count - 1)]
    }
}

public struct TrainingDay: Sendable {
    public let dayKey: String
    public let stage: Int
    public let completed: Bool

    public init(dayKey: String, stage: Int, completed: Bool) {
        self.dayKey = dayKey
        self.stage = stage
        self.completed = completed
    }
}

public enum ProgressCalculator {
    // Store the local date when the session starts, so travel cannot move old check-ins.
    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public static func completedDays(_ records: [TrainingDay], stage: Int? = nil) -> Set<String> {
        Set(records.filter { $0.completed && (stage == nil || $0.stage == stage) }.map(\.dayKey))
    }

    public static func personalGroups(_ records: [TrainingDay], dayKey: String) -> Int {
        records.filter { $0.completed && $0.stage == Course.personal.id && $0.dayKey == dayKey }.count
    }

    public static func canAdvance(_ records: [TrainingDay], stage: Int) -> Bool {
        stage < Course.stages.count - 1 && completedDays(records, stage: stage).count >= 7
    }
}
