#if STANDALONE_TESTS
import Foundation
#else
import XCTest
@testable import LvLianCore
#endif

final class ProgressTests: XCTestCase {
    func testDuplicateAndInterruptedSessionsDoNotAdvanceCourse() {
        var records = (1...6).map { TrainingDay(dayKey: "2026-09-0\($0)", stage: 0, completed: true) }
        records.append(TrainingDay(dayKey: "2026-09-06", stage: 0, completed: true))
        records.append(TrainingDay(dayKey: "2026-09-07", stage: 0, completed: false))
        records.append(TrainingDay(dayKey: "2026-09-07", stage: 1, completed: true))
        XCTAssertEqual(ProgressCalculator.completedDays(records, stage: 0).count, 6)
        XCTAssertFalse(ProgressCalculator.canAdvance(records, stage: 0))
        records.append(TrainingDay(dayKey: "2026-09-08", stage: 0, completed: true))
        XCTAssertTrue(ProgressCalculator.canAdvance(records, stage: 0))
        records.removeLast()
        XCTAssertFalse(ProgressCalculator.canAdvance(records, stage: 0))
    }

    func testFinalStageNeverAdvancesAndGlobalDaysAreDeduplicated() {
        let records = (1...7).flatMap { day in [
            TrainingDay(dayKey: "2026-09-0\(day)", stage: 2, completed: true),
            TrainingDay(dayKey: "2026-09-0\(day)", stage: 3, completed: true)
        ] }
        XCTAssertFalse(ProgressCalculator.canAdvance(records, stage: 3))
        XCTAssertEqual(ProgressCalculator.completedDays(records).count, 7)
        XCTAssertEqual(ProgressCalculator.completedDays([], stage: 0).count, 0)
    }

    func testLocalMidnightAndSessionStartDayAreStable() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let date = ISO8601DateFormatter().date(from: "2026-09-12T15:59:59Z")!
        let savedKey = ProgressCalculator.dayKey(for: date, calendar: calendar)
        XCTAssertEqual(savedKey, "2026-09-12")
        XCTAssertEqual(ProgressCalculator.dayKey(for: date.addingTimeInterval(1), calendar: calendar), "2026-09-13")
        // The saved session day never changes when the session ends after midnight.
        let record = TrainingDay(dayKey: savedKey, stage: 0, completed: true)
        XCTAssertEqual(ProgressCalculator.completedDays([record]), ["2026-09-12"])
    }
}
