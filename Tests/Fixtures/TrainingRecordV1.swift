// Frozen v1 model for the on-disk migration test. Do not change this schema.
import Foundation
import Observation
import SwiftData

@Model
final class TrainingRecord {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var dayKey: String
    var stageIndex: Int
    var stageName: String
    var contraction: Double
    var relaxation: Double
    var targetRepetitions: Int
    var completedRepetitions: Int
    var activeDuration: Double
    var status: String
    var feedback: String?

    init(course: Course, now: Date = .now) {
        id = UUID()
        startedAt = now
        dayKey = ProgressCalculator.dayKey(for: now)
        stageIndex = course.id
        stageName = course.name
        contraction = course.contraction
        relaxation = course.relaxation
        targetRepetitions = course.repetitions
        completedRepetitions = 0
        activeDuration = 0
        status = "active"
    }

    var isCompleted: Bool { status == "completed" }
    var trainingDay: TrainingDay { TrainingDay(dayKey: dayKey, stage: stageIndex, completed: isCompleted) }
    var statusTitle: String { isCompleted ? "已完成" : status == "active" ? "训练中" : "已中断" }
}
