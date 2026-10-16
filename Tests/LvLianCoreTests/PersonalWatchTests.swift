#if STANDALONE_TESTS
import Foundation
#else
import XCTest
@testable import LvLianCore
#endif

final class PersonalWatchTests: XCTestCase {
    func testPersonalFiveFiveTenCompleteCycles() {
        let course = Course.personal
        XCTAssertEqual(course.contraction, 5)
        XCTAssertEqual(course.relaxation, 5)
        XCTAssertEqual(course.repetitions, 10)
        var machine = TrainingMachine(course: course)
        machine.start(at: 0); machine.tick(at: 5)
        for repetition in 0..<10 {
            machine.tick(at: Double(10 + repetition * 10))
            XCTAssertEqual(machine.phase, .relax)
            XCTAssertEqual(machine.completedRepetitions, repetition)
            machine.tick(at: Double(15 + repetition * 10))
            XCTAssertEqual(machine.completedRepetitions, repetition + 1)
        }
        XCTAssertEqual(machine.phase, .completed)
        XCTAssertEqual(machine.activeDuration, 100)
    }
    func testPersonalResumeUsesFiveSecondsFullRelaxation() {
        var machine = TrainingMachine(course: .personal)
        machine.start(at: 0); machine.tick(at: 5); machine.pause(at: 7)
        machine.resume(at: 100)
        XCTAssertEqual(machine.phase, .relax)
        XCTAssertEqual(machine.remaining, 5)
        machine.tick(at: 105)
        XCTAssertEqual(machine.completedRepetitions, 0)
        XCTAssertEqual(machine.phase, .contract)
        XCTAssertEqual(machine.activeDuration, 7)
    }
    func testPersonalGroupsDoNotAdvanceStagesAndRecompute() {
        var days = (0..<7).map { TrainingDay(dayKey: "day\($0)", stage: Course.personal.id, completed: true) }
        for stage in 0..<4 { XCTAssertFalse(ProgressCalculator.canAdvance(days, stage: stage)) }
        days += (0..<5).map { _ in TrainingDay(dayKey: "today", stage: Course.personal.id, completed: true) }
        days.append(.init(dayKey: "today", stage: Course.personal.id, completed: false))
        days.append(.init(dayKey: "today", stage: 0, completed: true))
        XCTAssertEqual(ProgressCalculator.personalGroups(days, dayKey: "today"), 5)
        days.remove(at: 7)
        XCTAssertEqual(ProgressCalculator.personalGroups(days, dayKey: "today"), 4)
        XCTAssertEqual(ProgressCalculator.personalGroups(days, dayKey: "tomorrow"), 0)
    }
    private func packet(_ sequence: Int, at time: Double = 100, stream: UUID) -> WatchCuePacket {
        .init(stream: stream, sequence: sequence, sentAt: Date(timeIntervalSince1970: time), workout: stream, kind: .pelvic,
              title: "收缩", detail: "0 / 10", remaining: 5, running: true, enabled: true, cue: .single)
    }
    func testWatchRejectsDuplicateOutOfOrderAndExpiredCues() {
        let stream = UUID(), now = Date(timeIntervalSince1970: 101)
        var gate = WatchCueGate()
        XCTAssertTrue(gate.accept(packet(2, stream: stream), now: now))
        XCTAssertFalse(gate.accept(packet(2, stream: stream), now: now))
        XCTAssertFalse(gate.accept(packet(1, stream: stream), now: now))
        XCTAssertFalse(gate.accept(packet(3, at: 98, stream: stream), now: now))
        XCTAssertFalse(gate.accept(packet(4, at: 105, stream: stream), now: now))
        var paused = packet(5, at: 101, stream: stream)
        paused.running = false; paused.cue = .none
        XCTAssertTrue(gate.accept(paused, now: now))
        XCTAssertFalse(gate.accept(packet(4, at: 100.5, stream: stream), now: now))
    }
    func testWatchAcceptsNewPhoneStreamButRejectsOlderSession() {
        var gate = WatchCueGate()
        let first = UUID(), second = UUID()
        XCTAssertTrue(gate.accept(packet(50, stream: first), now: Date(timeIntervalSince1970: 100)))
        XCTAssertTrue(gate.accept(packet(1, at: 101, stream: second), now: Date(timeIntervalSince1970: 101)))
        XCTAssertFalse(gate.accept(packet(51, at: 100.5, stream: first), now: Date(timeIntervalSince1970: 101)))
        var invalid = packet(2, at: 102, stream: second)
        invalid.remaining = .infinity
        XCTAssertFalse(gate.accept(invalid, now: Date(timeIntervalSince1970: 102)))
    }
    func testWatchAcceptsRecentDisplaySnapshotButNotDelayedHaptic() {
        let stream = UUID(), now = Date(timeIntervalSince1970: 110)
        var gate = WatchCueGate()
        var display = packet(2, at: 100, stream: stream)
        display.cue = .none
        XCTAssertTrue(gate.accept(display, now: now))
        XCTAssertFalse(gate.accept(packet(3, at: 100, stream: stream), now: now))
    }
    func testStandaloneSquatResultRoundTripsForDeferredPhoneImport() throws {
        let id = UUID()
        let value = WatchSquatResult(id: id, startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200), target: 50, down: 2, up: 2, rest: 30,
            confirmedSets: [10, 9], guidedRepetitions: 20, activeDuration: 80,
            status: "interrupted")
        let decoded = try JSONDecoder().decode(WatchSquatResult.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.confirmedSets, [10, 9])
        XCTAssertEqual(decoded.guidedRepetitions, 20)
        XCTAssertEqual(decoded.status, "interrupted")
    }
    func testStandalonePelvicResultRoundTripsForDeferredPhoneImport() throws {
        let id = UUID()
        let value = WatchPelvicResult(id: id, startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 205), completedRepetitions: 10,
            activeDuration: 100, status: "completed")
        let decoded = try JSONDecoder().decode(WatchPelvicResult.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.completedRepetitions, 10)
        XCTAssertEqual(decoded.activeDuration, 100)
        XCTAssertEqual(decoded.status, "completed")
    }
}
