import Foundation
import Observation
import SwiftData
import os

/// Owns a dedicated serial executor; neither a caller's actor nor SwiftData's
/// default executor can redirect checkpoint work onto the UI thread.
private final class BackgroundModelExecutor: SerialModelExecutor, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.personal.lvlian.persistence", qos: .utility)
    private let container: ModelContainer
    private var context: ModelContext?
    init(container: ModelContainer) { self.container = container }
    var modelContext: ModelContext {
        dispatchPrecondition(condition: .onQueue(queue))
        if let context { return context }
        let created = ModelContext(container)
        created.autosaveEnabled = false
        context = created
        return created
    }
    func enqueue(_ job: consuming ExecutorJob) {
        let unownedJob = UnownedJob(job)
        let executor = asUnownedSerialExecutor()
        queue.async { unownedJob.runSynchronously(on: executor) }
    }
    func asUnownedSerialExecutor() -> UnownedSerialExecutor { UnownedSerialExecutor(ordinary: self) }
}

actor TrainingWriter: ModelActor {
    nonisolated let modelContainer: ModelContainer
    nonisolated let modelExecutor: any ModelExecutor
    nonisolated private let executor: BackgroundModelExecutor
    nonisolated var unownedExecutor: UnownedSerialExecutor { executor.asUnownedSerialExecutor() }
    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        let executor = BackgroundModelExecutor(container: modelContainer)
        self.executor = executor
        modelExecutor = executor
    }
    private var revisions: [UUID: Int] = [:]
    private var tombstones: Set<UUID> = []
    private let log = OSLog(subsystem: "com.personal.lvlian", category: "TrainingPersistence")

    func save(_ snapshot: PelvicSnapshot) throws {
        assert(!Thread.isMainThread, "Checkpoints must not write on the UI thread")
        guard !tombstones.contains(snapshot.id), snapshot.revision > (revisions[snapshot.id] ?? -1) else { return }
        let id = snapshot.id
        let existing = try modelContext.fetch(pelvicDescriptor(id: id)).first
        guard existing?.status == nil || existing?.status == "active" || snapshot.isTerminal else { return }
        os_signpost(.begin, log: log, name: "Save checkpoint")
        defer { os_signpost(.end, log: log, name: "Save checkpoint") }
        do {
            let record = existing ?? TrainingRecord(course: snapshot.course, now: snapshot.startedAt)
            if existing == nil { record.id = id; modelContext.insert(record) }
            record.dayKey = snapshot.dayKey; record.endedAt = snapshot.endedAt
            record.completedRepetitions = snapshot.completedRepetitions
            record.activeDuration = snapshot.activeDuration
            record.status = snapshot.status; record.feedback = snapshot.feedback
            try modelContext.save()
            revisions[id] = snapshot.revision
        } catch { modelContext.rollback(); throw error }
    }

    func save(_ snapshot: SquatSnapshot) throws {
        assert(!Thread.isMainThread, "Checkpoints must not write on the UI thread")
        guard !tombstones.contains(snapshot.id), snapshot.revision > (revisions[snapshot.id] ?? -1) else { return }
        let id = snapshot.id
        let existing = try modelContext.fetch(squatDescriptor(id: id)).first
        guard existing?.status == nil || existing?.status == "active" || snapshot.isTerminal else { return }
        os_signpost(.begin, log: log, name: "Save checkpoint")
        defer { os_signpost(.end, log: log, name: "Save checkpoint") }
        do {
            let record = existing ?? SquatRecord(plan: snapshot.plan, now: snapshot.startedAt)
            if existing == nil { record.id = id; modelContext.insert(record) }
            record.dayKey = snapshot.dayKey; record.endedAt = snapshot.endedAt
            record.confirmedSets = snapshot.confirmedSets; record.guidedRepetitions = snapshot.guidedRepetitions
            record.activeDuration = snapshot.activeDuration; record.status = snapshot.status
            try modelContext.save()
            revisions[id] = snapshot.revision
        } catch { modelContext.rollback(); throw error }
    }

    func load(recover: Bool = false) throws -> LibrarySnapshot {
        let pelvic = try modelContext.fetch(pelvicByDate())
        let squats = try modelContext.fetch(squatsByDate())
        if recover {
            do {
                for record in pelvic where record.status == "active" { record.status = "interrupted" }
                for record in squats where record.status == "active" { record.status = "interrupted" }
                try modelContext.save()
            } catch { modelContext.rollback(); throw error }
        }
        return LibrarySnapshot(pelvic: pelvic.map(PelvicSnapshot.init), squats: squats.map(SquatSnapshot.init))
    }

    func delete(id: UUID, squat: Bool) throws {
        do {
            if squat {
                for record in try modelContext.fetch(squatDescriptor(id: id)) { modelContext.delete(record) }
            } else {
                for record in try modelContext.fetch(pelvicDescriptor(id: id)) { modelContext.delete(record) }
            }
            try modelContext.save()
            tombstones.insert(id)
        } catch { modelContext.rollback(); throw error }
    }

    func clear() throws {
        do {
            let pelvic = try modelContext.fetch(FetchDescriptor<TrainingRecord>())
            let squats = try modelContext.fetch(FetchDescriptor<SquatRecord>())
            let ids = pelvic.map(\.id) + squats.map(\.id)
            pelvic.forEach { modelContext.delete($0) }
            squats.forEach { modelContext.delete($0) }
            try modelContext.save()
            tombstones.formUnion(ids)
        } catch { modelContext.rollback(); throw error }
    }
}

struct LibrarySnapshot: Sendable {
    var pelvic: [PelvicSnapshot]
    var squats: [SquatSnapshot]
}

@MainActor
@Observable
final class TrainingLibrary {
    private(set) var records: [PelvicSnapshot] = []
    private(set) var squats: [SquatSnapshot] = []
    private(set) var ready = false
    @ObservationIgnored private let writerTask: Task<TrainingWriter, Never>

    init(container: ModelContainer) {
        writerTask = Task.detached { TrainingWriter(modelContainer: container) }
    }
    func load() async throws {
        let writer = await writerTask.value
        let snapshot = try await writer.load(recover: !ready)
        records = snapshot.pelvic; squats = snapshot.squats; ready = true
    }
    func save(_ snapshot: PelvicSnapshot) async throws {
        try await writerTask.value.save(snapshot)
        if snapshot.isTerminal { try await load() }
    }
    func save(_ snapshot: SquatSnapshot) async throws {
        try await writerTask.value.save(snapshot)
        if snapshot.isTerminal { try await load() }
    }
    func delete(id: UUID, squat: Bool) async throws {
        try await writerTask.value.delete(id: id, squat: squat)
        try await load()
    }
    func clear() async throws {
        try await writerTask.value.clear()
        try await load()
    }
}

// Build Foundation predicate/sort values outside actor isolation. The descriptors
// are consumed synchronously on the writer's executor, never shared between tasks.
private func pelvicDescriptor(id: UUID) -> FetchDescriptor<TrainingRecord> {
    FetchDescriptor(predicate: #Predicate<TrainingRecord> { $0.id == id })
}
private func squatDescriptor(id: UUID) -> FetchDescriptor<SquatRecord> {
    FetchDescriptor(predicate: #Predicate<SquatRecord> { $0.id == id })
}
private func pelvicByDate() -> FetchDescriptor<TrainingRecord> {
    FetchDescriptor(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
}
private func squatsByDate() -> FetchDescriptor<SquatRecord> {
    FetchDescriptor(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
}
