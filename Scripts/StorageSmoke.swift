import Foundation
import SwiftData

@main
struct StorageSmoke {
    static func main() async throws {
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let config = ModelConfiguration(url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: TrainingRecord.self, SquatRecord.self, configurations: config)
        let writer = await Task.detached { TrainingWriter(modelContainer: container) }.value
        var data = try await writer.load()
        precondition(data.pelvic.count == 1 && data.squats.isEmpty)
        let legacy = data.pelvic[0]
        precondition(legacy.id.uuidString == "00000000-0000-0000-0000-000000000001")
        precondition(legacy.stageIndex == 2 && legacy.dayKey == "2026-09-12")
        precondition(legacy.isCompleted && legacy.activeDuration == 120 && legacy.feedback == "适中")
        print("PASS: v1 disk store migrates without losing pelvic records")

        var squat = SquatSnapshot(plan: SquatPlan(target: 27))
        squat.confirmedSets = [10, 8]; squat.guidedRepetitions = 20; squat.activeDuration = 80; squat.revision = 1
        try await writer.save(squat)
        var final = squat
        final.confirmedSets = [10, 8, 7]; final.status = "completed"; final.endedAt = .now; final.revision = 3
        try await writer.save(final)
        try await writer.save(squat) // Late checkpoint must not replace the final result.
        try await writer.save(final) // Retries must not create another row.
        data = try await writer.load()
        precondition(data.squats.count == 1 && data.squats[0].confirmed == 25 && data.squats[0].status == "completed")
        precondition(data.pelvic[0].id == legacy.id && data.pelvic[0].feedback == "适中")
        print("PASS: immutable snapshots, idempotence, terminal precedence and independent statistics")

        var interrupted = SquatSnapshot(plan: SquatPlan())
        interrupted.confirmedSets = [7]; interrupted.guidedRepetitions = 15; interrupted.revision = 1
        try await writer.save(interrupted)
        data = try await writer.load(recover: true)
        let recovered = data.squats.first { $0.id == interrupted.id }!
        precondition(recovered.status == "interrupted" && recovered.confirmed == 7)
        precondition(recovered.endedAt == nil)
        print("PASS: crash recovery keeps confirmed counts only")

        var pc = PelvicSnapshot(course: .stage(0)); pc.revision = 1
        try await writer.save(pc)
        pc.status = "completed"; pc.completedRepetitions = 8; pc.activeDuration = 72; pc.revision = 3
        try await writer.save(pc)
        var stale = pc; stale.status = "active"; stale.revision = 2; stale.completedRepetitions = 0
        try await writer.save(stale)
        data = try await writer.load()
        precondition(data.pelvic.first { $0.id == pc.id }?.completedRepetitions == 8)
        print("PASS: pelvic terminal checkpoint cannot be overwritten")

        try await writer.delete(id: final.id, squat: true)
        try await writer.save(final)
        data = try await writer.load()
        precondition(data.squats.count == 1 && data.squats[0].confirmed == 7)
        precondition(data.pelvic.count == 2)
        print("PASS: deletion recomputes squat progress and stale writes cannot resurrect data")

        let reopened = try ModelContainer(for: TrainingRecord.self, SquatRecord.self, configurations: config)
        let reader = await Task.detached { TrainingWriter(modelContainer: reopened) }.value
        let disk = try await reader.load()
        precondition(disk.squats.count == 1 && disk.pelvic.count == 2)
        precondition(disk.squats[0].confirmedSets == [7])
        print("PASS: disk reopen preserves both models")
        try await writer.clear()
        data = try await writer.load()
        precondition(data.pelvic.isEmpty && data.squats.isEmpty)
        print("PASS: clear removes both training types")
    }
}
