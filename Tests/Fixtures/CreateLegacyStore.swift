import Foundation
import SwiftData

@main
struct CreateLegacyStore {
    @MainActor static func main() throws {
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let configuration = ModelConfiguration(url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: TrainingRecord.self, configurations: configuration)
        let context = ModelContext(container)
        let record = TrainingRecord(course: .stage(2), now: Date(timeIntervalSince1970: 1_789_200_000))
        record.id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        record.dayKey = "2026-09-12"
        record.status = "completed"; record.activeDuration = 120
        record.completedRepetitions = 10; record.feedback = "适中"
        context.insert(record); try context.save()
        print("PASS: created disk fixture with frozen v1 schema")
    }
}
