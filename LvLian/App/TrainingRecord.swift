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

@MainActor
@Observable
final class AppSettings {
    private let defaults: UserDefaults
    var personalRhythm: Bool { didSet { defaults.set(personalRhythm, forKey: "personalRhythm") } }
    var pelvicDailySets: Int { didSet { defaults.set(pelvicDailySets, forKey: "pelvicDailySets") } }
    var strongHaptics: Bool { didSet { defaults.set(strongHaptics, forKey: "strongHaptics") } }
    var watchHaptics: Bool { didSet { defaults.set(watchHaptics, forKey: "watchHaptics") } }
    var selectedCourse: Course { personalRhythm ? .personal : .stage(currentStage) }
    var currentStage: Int { didSet { defaults.set(currentStage, forKey: "currentStage") } }
    var hapticsEnabled: Bool { didSet { defaults.set(hapticsEnabled, forKey: "hapticsEnabled") } }
    var squatVoiceEnabled: Bool { didSet { defaults.set(squatVoiceEnabled, forKey: "squatVoiceEnabled") } }
    var squatHapticsEnabled: Bool { didSet { defaults.set(squatHapticsEnabled, forKey: "squatHapticsEnabled") } }
    var squatDown: Double { didSet { defaults.set(squatDown, forKey: "squatDown") } }
    var squatUp: Double { didSet { defaults.set(squatUp, forKey: "squatUp") } }
    var squatRest: Double { didSet { defaults.set(squatRest, forKey: "squatRest") } }
    var onboardingComplete: Bool { didSet { defaults.set(onboardingComplete, forKey: "onboardingComplete") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        personalRhythm = defaults.object(forKey: "personalRhythm") as? Bool ?? true
        pelvicDailySets = min(8, max(1, defaults.object(forKey: "pelvicDailySets") as? Int ?? 5))
        strongHaptics = defaults.object(forKey: "strongHaptics") as? Bool ?? true
        watchHaptics = defaults.object(forKey: "watchHaptics") as? Bool ?? true
        squatVoiceEnabled = defaults.object(forKey: "squatVoiceEnabled") as? Bool ?? true
        squatHapticsEnabled = defaults.bool(forKey: "squatHapticsEnabled")
        squatDown = min(5, max(1, defaults.object(forKey: "squatDown") as? Double ?? 2))
        squatUp = min(5, max(1, defaults.object(forKey: "squatUp") as? Double ?? 2))
        squatRest = min(120, max(15, defaults.object(forKey: "squatRest") as? Double ?? 30))
        currentStage = min(max(defaults.integer(forKey: "currentStage"), 0), 3)
        hapticsEnabled = defaults.object(forKey: "hapticsEnabled") as? Bool ?? true
        onboardingComplete = defaults.bool(forKey: "onboardingComplete")
    }
}
