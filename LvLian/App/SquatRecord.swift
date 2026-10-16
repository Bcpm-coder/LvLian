import Foundation
import SwiftData

@Model
final class SquatRecord {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var dayKey: String
    var targetRepetitions: Int
    var downSeconds: Double
    var upSeconds: Double
    var restSeconds: Double
    var plannedSets: [Int]
    var confirmedSets: [Int]
    var guidedRepetitions: Int
    var activeDuration: Double
    var status: String

    init(plan: SquatPlan, now: Date = .now) {
        id = UUID(); startedAt = now; dayKey = ProgressCalculator.dayKey(for: now)
        targetRepetitions = plan.target
        downSeconds = plan.down; upSeconds = plan.up; restSeconds = plan.rest
        plannedSets = plan.sets; confirmedSets = []; guidedRepetitions = 0
        activeDuration = 0; status = "active"
    }
}

struct PelvicSnapshot: Identifiable, Sendable {
    var id = UUID()
    var startedAt: Date
    var endedAt: Date?
    var dayKey: String
    var course: Course
    var completedRepetitions = 0
    var activeDuration = 0.0
    var status = "active"
    var feedback: String?
    var revision = 0
    var isCompleted: Bool { status == "completed" }
    var isTerminal: Bool { status != "active" }
    var stageIndex: Int { course.id }
    var stageName: String { course.name }
    var contraction: Double { course.contraction }
    var relaxation: Double { course.relaxation }
    var targetRepetitions: Int { course.repetitions }
    var trainingDay: TrainingDay { .init(dayKey: dayKey, stage: course.id, completed: isCompleted) }
    var statusTitle: String { isCompleted ? "已完成" : status == "active" ? "训练中" : "已中断" }
    init(course: Course, now: Date = .now) {
        self.course = course; startedAt = now; dayKey = ProgressCalculator.dayKey(for: now)
    }
    init(_ record: TrainingRecord) {
        id = record.id; startedAt = record.startedAt; endedAt = record.endedAt; dayKey = record.dayKey
        course = Course(id: record.stageIndex, name: record.stageName, contraction: record.contraction,
                        relaxation: record.relaxation, repetitions: record.targetRepetitions)
        completedRepetitions = record.completedRepetitions; activeDuration = record.activeDuration
        status = record.status; feedback = record.feedback
    }
}

struct SquatSnapshot: Identifiable, Sendable {
    var id = UUID()
    var startedAt: Date
    var endedAt: Date?
    var dayKey: String
    var plan: SquatPlan
    var confirmedSets: [Int] = []
    var guidedRepetitions = 0
    var activeDuration = 0.0
    var status = "active"
    var revision = 0
    var confirmed: Int { confirmedSets.reduce(0, +) }
    var isTerminal: Bool { status != "active" }
    var day: SquatDay { .init(id: id, dayKey: dayKey, confirmed: confirmed) }
    var statusTitle: String { status == "completed" ? "带练结束" : status == "active" ? "训练中" : "提前结束" }
    init(plan: SquatPlan, now: Date = .now) {
        self.plan = plan; startedAt = now; dayKey = ProgressCalculator.dayKey(for: now)
    }
    init(_ record: SquatRecord) {
        id = record.id; startedAt = record.startedAt; endedAt = record.endedAt; dayKey = record.dayKey
        plan = SquatPlan(target: record.targetRepetitions, down: record.downSeconds, up: record.upSeconds, rest: record.restSeconds)
        confirmedSets = record.confirmedSets; guidedRepetitions = record.guidedRepetitions
        activeDuration = record.activeDuration; status = record.status
    }
}
