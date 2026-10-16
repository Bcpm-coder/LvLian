#if STANDALONE_TESTS
import Foundation
#else
import XCTest
@testable import LvLianCore
#endif

final class SquatTests: XCTestCase {
    func testRemainingPlanAndBounds() {
        XCTAssertEqual(SquatPlan().sets, [10, 10, 10, 10, 10])
        XCTAssertEqual(SquatPlan(target: 27).sets, [10, 10, 7])
        let plan = SquatPlan(target: 100, down: 0, up: 10, rest: 200)
        XCTAssertEqual(plan.target, 50); XCTAssertEqual(plan.down, 1)
        XCTAssertEqual(plan.up, 5); XCTAssertEqual(plan.rest, 120)
    }
    func testGuidanceDoesNotAutomaticallyConfirm() {
        var m = SquatMachine(plan: SquatPlan(target: 1))
        m.start(at: 0); m.tick(at: 5); m.tick(at: 7); m.tick(at: 9)
        XCTAssertEqual(m.phase, .confirm)
        XCTAssertEqual(m.guidedTotal, 1); XCTAssertEqual(m.confirmedTotal, 0)
        m.tick(at: 100)
        XCTAssertEqual(m.phase, .confirm)
        m.confirmSet(actual: 1, at: 100)
        XCTAssertEqual(m.phase, .completed) // No rest after final set.
        XCTAssertEqual(m.confirmedTotal, 1); XCTAssertEqual(m.activeDuration, 4)
    }
    func testFullSessionAndActualCounts() {
        var m = SquatMachine(plan: SquatPlan())
        var time = 5.0
        m.start(at: 0); m.tick(at: time)
        for group in 0..<5 {
            for _ in 0..<10 {
                time += 2; m.tick(at: time)
                time += 2; m.tick(at: time)
            }
            XCTAssertEqual(m.phase, .confirm)
            m.confirmSet(actual: 9, at: time)
            if group < 4 {
                XCTAssertEqual(m.phase, .rest)
                time += 30; m.tick(at: time)
            }
        }
        XCTAssertEqual(m.phase, .completed)
        XCTAssertEqual(m.confirmedSets, [9, 9, 9, 9, 9])
        XCTAssertEqual(m.confirmedTotal, 45); XCTAssertEqual(m.guidedTotal, 50)
        XCTAssertEqual(m.activeDuration, 200)
    }
    func testPauseMovementRestartsUnfinishedRep() {
        for pauseTime in [6.0, 8.0] {
            var m = SquatMachine(plan: SquatPlan(target: 2))
            m.start(at: 0); m.tick(at: 5)
            if pauseTime > 7 { m.tick(at: 7) }
            m.pause(at: pauseTime)
            let duration = m.activeDuration
            m.tick(at: 900)
            XCTAssertEqual(m.activeDuration, duration)
            m.resume(at: 900)
            XCTAssertEqual(m.phase, .resuming); XCTAssertEqual(m.remaining, 3)
            m.tick(at: 903)
            XCTAssertEqual(m.phase, .down); XCTAssertEqual(m.guidedInSet, 0)
            m.tick(at: 905); m.tick(at: 907)
            XCTAssertEqual(m.guidedInSet, 1)
        }
    }
    func testPauseRestPreservesRemaining() {
        var m = SquatMachine(plan: SquatPlan(target: 11))
        var t = 5.0
        m.start(at: 0); m.tick(at: t)
        for _ in 0..<10 { t += 2; m.tick(at: t); t += 2; m.tick(at: t) }
        m.confirmSet(actual: 10, at: t)
        m.pause(at: t + 2.5)
        XCTAssertEqual(m.remaining, 27.5)
        m.resume(at: 1000)
        XCTAssertEqual(m.phase, .rest); XCTAssertEqual(m.remaining, 27.5)
        m.tick(at: 1027.5)
        XCTAssertEqual(m.phase, .down)
        XCTAssertEqual(m.setTarget, 1)
    }
    func testEarlyEndAndDuplicateConfirmation() {
        var m = SquatMachine(plan: SquatPlan())
        m.start(at: 0); m.tick(at: 5); m.tick(at: 7); m.tick(at: 9)
        m.end(actualInCurrentSet: 1, at: 10)
        m.end(actualInCurrentSet: 10, at: 11)
        m.confirmSet(actual: 10, at: 12)
        XCTAssertEqual(m.phase, .interrupted); XCTAssertEqual(m.confirmedTotal, 1)
        XCTAssertEqual(m.guidedTotal, 1)
    }
    func testEarlyEndWithoutConfirmationDiscardsCurrentSet() {
        var m = SquatMachine(plan: SquatPlan())
        m.start(at: 0); m.tick(at: 5); m.tick(at: 7); m.tick(at: 9)
        m.end(at: 10)
        XCTAssertEqual(m.phase, .interrupted)
        XCTAssertEqual(m.guidedTotal, 1)
        XCTAssertEqual(m.confirmedSets, [])
        XCTAssertEqual(m.confirmedTotal, 0)
    }
    func testEndDuringRestNeverCreditsNextSet() {
        var m = SquatMachine(plan: SquatPlan(target: 11))
        var t = 5.0
        m.start(at: 0); m.tick(at: t)
        for _ in 0..<10 { t += 2; m.tick(at: t); t += 2; m.tick(at: t) }
        m.confirmSet(actual: 7, at: t)
        m.confirmSet(actual: 10, at: t) // Duplicate UI event is ignored.
        m.end(actualInCurrentSet: 1, at: t + 1)
        XCTAssertEqual(m.confirmedSets, [7]); XCTAssertEqual(m.confirmedTotal, 7)
    }
    func testDelayedTickDoesNotInventReps() {
        var m = SquatMachine(plan: SquatPlan())
        m.start(at: 0); m.tick(at: 50)
        XCTAssertEqual(m.phase, .down); XCTAssertEqual(m.activeDuration, 0)
        m.tick(at: 100)
        XCTAssertEqual(m.phase, .up); XCTAssertEqual(m.guidedTotal, 0)
        m.tick(at: 200)
        XCTAssertEqual(m.guidedTotal, 1); XCTAssertEqual(m.confirmedTotal, 0)
        XCTAssertEqual(m.activeDuration, 4)
    }
    func testDailyTotalsDeduplicateAndRecomputeAfterDeletion() {
        let id = UUID()
        let a = SquatDay(id: id, dayKey: "2026-09-12", confirmed: 10)
        let b = SquatDay(id: id, dayKey: "2026-09-12", confirmed: 23)
        let c = SquatDay(id: UUID(), dayKey: "2026-09-12", confirmed: 27)
        let next = SquatDay(id: UUID(), dayKey: "2026-09-13", confirmed: 5)
        XCTAssertEqual(SquatProgress.totals([a, b, c, next])["2026-09-12"], 50)
        XCTAssertEqual(SquatProgress.remaining([a, b, c, next], dayKey: "2026-09-12"), 0)
        XCTAssertEqual(SquatProgress.remaining([a, b, next], dayKey: "2026-09-12"), 27)
        XCTAssertEqual(SquatProgress.remaining([next], dayKey: "2026-09-13"), 45)
    }
    func testPauseDuringPreparationDoesNotCountWork() {
        var m = SquatMachine(plan: SquatPlan())
        m.start(at: 0); m.pause(at: 1); m.resume(at: 100)
        m.tick(at: 103)
        XCTAssertEqual(m.phase, .down); XCTAssertEqual(m.guidedTotal, 0)
        XCTAssertEqual(m.activeDuration, 0)
    }
    func testRenderClockIsContinuousFrozenAndClamped() {
        let moving = CountdownState(duration: 3, remaining: 3, anchoredAt: 100, running: true)
        XCTAssertEqual(moving.progress(at: 101.5), 0.5, accuracy: 0.0001)
        XCTAssertEqual(moving.progress(at: 110), 1)
        let paused = CountdownState(duration: 3, remaining: 1.5, anchoredAt: 101.5, running: false)
        XCTAssertEqual(paused.progress(at: 999), 0.5)
        let next = CountdownState(duration: 6, remaining: 6, anchoredAt: 103, running: true)
        XCTAssertEqual(next.progress(at: 103), 0)
        XCTAssertEqual(next.progress(at: 104), 1.0 / 6, accuracy: 0.0001)
    }
}
