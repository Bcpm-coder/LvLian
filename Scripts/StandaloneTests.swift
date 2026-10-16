// Run the same test cases when Command Line Tools do not include XCTest.
#if STANDALONE_TESTS
import Foundation
class XCTestCase {}
func XCTAssertTrue(_ value: Bool, file: StaticString = #file, line: UInt = #line) {
    precondition(value, "Expected true", file: file, line: line)
}
func XCTAssertFalse(_ value: Bool, file: StaticString = #file, line: UInt = #line) {
    precondition(!value, "Expected false", file: file, line: line)
}
func XCTAssertEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #file, line: UInt = #line) {
    precondition(actual == expected, "Expected \(expected), got \(actual)", file: file, line: line)
}
func XCTAssertEqual(_ actual: Double, _ expected: Double, accuracy: Double, file: StaticString = #file, line: UInt = #line) {
    precondition(abs(actual - expected) <= accuracy, "Expected \(expected), got \(actual)", file: file, line: line)
}
func XCTFail(_ message: String, file: StaticString = #file, line: UInt = #line) {
    fatalError(message, file: file, line: line)
}

@main
struct StandaloneTests {
    @MainActor
    static func main() async throws {
        let training = TrainingTests()
        let progress = ProgressTests()
        let reminders = ReminderTests()
        let squats = SquatTests()
        let personal = PersonalWatchTests()
        let syncCases: [(String, () -> Void)] = [
            ("testPersonalFiveFiveTenCompleteCycles", personal.testPersonalFiveFiveTenCompleteCycles),
            ("testPersonalResumeUsesFiveSecondsFullRelaxation", personal.testPersonalResumeUsesFiveSecondsFullRelaxation),
            ("testPersonalGroupsDoNotAdvanceStagesAndRecompute", personal.testPersonalGroupsDoNotAdvanceStagesAndRecompute),
            ("testWatchRejectsDuplicateOutOfOrderAndExpiredCues", personal.testWatchRejectsDuplicateOutOfOrderAndExpiredCues),
            ("testWatchAcceptsNewPhoneStreamButRejectsOlderSession", personal.testWatchAcceptsNewPhoneStreamButRejectsOlderSession),
            ("testWatchAcceptsRecentDisplaySnapshotButNotDelayedHaptic", personal.testWatchAcceptsRecentDisplaySnapshotButNotDelayedHaptic),

            ("testRemainingPlanAndBounds", squats.testRemainingPlanAndBounds),
            ("testGuidanceDoesNotAutomaticallyConfirm", squats.testGuidanceDoesNotAutomaticallyConfirm),
            ("testFullSessionAndActualCounts", squats.testFullSessionAndActualCounts),
            ("testPauseMovementRestartsUnfinishedRep", squats.testPauseMovementRestartsUnfinishedRep),
            ("testPauseRestPreservesRemaining", squats.testPauseRestPreservesRemaining),
            ("testEarlyEndAndDuplicateConfirmation", squats.testEarlyEndAndDuplicateConfirmation),
            ("testEarlyEndWithoutConfirmationDiscardsCurrentSet", squats.testEarlyEndWithoutConfirmationDiscardsCurrentSet),
            ("testEndDuringRestNeverCreditsNextSet", squats.testEndDuringRestNeverCreditsNextSet),
            ("testDelayedTickDoesNotInventReps", squats.testDelayedTickDoesNotInventReps),
            ("testDailyTotalsDeduplicateAndRecomputeAfterDeletion", squats.testDailyTotalsDeduplicateAndRecomputeAfterDeletion),
            ("testPauseDuringPreparationDoesNotCountWork", squats.testPauseDuringPreparationDoesNotCountWork),
            ("testRenderClockIsContinuousFrozenAndClamped", squats.testRenderClockIsContinuousFrozenAndClamped),
            ("All courses complete after final relaxation", training.testAllCoursesCompleteOnlyAfterFinalRelaxation),
            ("Pause during contraction", training.testPauseDuringContractionRestartsWithFullUncreditedRelaxation),
            ("Pause during relaxation", training.testPauseDuringRelaxationKeepsEarnedContraction),
            ("Pause during preparation", training.testPauseDuringPreparationDoesNotInventRepetition),
            ("Early end is idempotent", training.testEarlyEndIsIdempotentAndNeverCreditsBackgroundTime),
            ("Delayed tick cannot invent work", training.testDelayedTickDoesNotSkipCuesOrInventWork),
            ("Fractional elapsed time", training.testFractionalTicksUseElapsedTimeRatherThanTickCount),
            ("Deduplication, interruption, deletion, seven-day threshold", progress.testDuplicateAndInterruptedSessionsDoNotAdvanceCourse),
            ("Final stage and global day count", progress.testFinalStageNeverAdvancesAndGlobalDaysAreDeduplicated),
            ("Midnight and stored start day", progress.testLocalMidnightAndSessionStartDayAreStable)
        ]
        for (name, test) in syncCases { test(); print("PASS: \(name)") }
        try personal.testStandaloneSquatResultRoundTripsForDeferredPhoneImport()
        print("PASS: Standalone watch squat result round trip")
        try personal.testStandalonePelvicResultRoundTripsForDeferredPhoneImport()
        print("PASS: Standalone watch pelvic result round trip")
        try await reminders.testEnableReplaceAndCancel()
        print("PASS: Enable, replace, cancel reminder")
        try await reminders.testDeniedPermissionRemovesStaleRequest()
        print("PASS: Denied notification permission")
        try await reminders.testSchedulingFailurePreservesPreviousPlan()
        print("PASS: Scheduling failure preserves previous plan")
        print("33 test cases passed.")
    }
}
#endif
