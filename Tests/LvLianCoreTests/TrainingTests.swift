#if STANDALONE_TESTS
import Foundation
#else
import XCTest
@testable import LvLianCore
#endif

final class TrainingTests: XCTestCase {
    func testAllCoursesCompleteOnlyAfterFinalRelaxation() {
        for course in Course.stages {
            var machine = TrainingMachine(course: course)
            var now = 100.0
            machine.start(at: now)
            now += 5
            machine.tick(at: now)
            XCTAssertEqual(machine.phase, .contract)
            XCTAssertEqual(machine.activeDuration, 0)
            for index in 0..<course.repetitions {
                now += course.contraction
                machine.tick(at: now)
                XCTAssertEqual(machine.phase, .relax)
                XCTAssertEqual(machine.completedRepetitions, index)
                now += course.relaxation
                machine.tick(at: now)
                XCTAssertEqual(machine.completedRepetitions, index + 1)
            }
            XCTAssertEqual(machine.phase, .completed)
            XCTAssertEqual(machine.activeDuration, course.duration, accuracy: 0.001)
            machine.end(at: now + 10)
            XCTAssertEqual(machine.phase, .completed)
        }
    }

    func testPauseDuringContractionRestartsWithFullUncreditedRelaxation() {
        var machine = TrainingMachine(course: .stage(0))
        machine.start(at: 0)
        machine.tick(at: 5)
        machine.pause(at: 6)
        XCTAssertEqual(machine.activeDuration, 1)
        machine.tick(at: 1000)
        XCTAssertEqual(machine.activeDuration, 1)
        machine.resume(at: 1000)
        XCTAssertEqual(machine.phase, .relax)
        XCTAssertEqual(machine.remaining, 6)
        machine.tick(at: 1006)
        XCTAssertEqual(machine.completedRepetitions, 0)
        XCTAssertEqual(machine.phase, .contract)
        XCTAssertEqual(machine.activeDuration, 7)
    }

    func testPauseDuringRelaxationKeepsEarnedContraction() {
        var machine = TrainingMachine(course: .stage(0))
        machine.start(at: 0)
        machine.tick(at: 5)
        machine.tick(at: 8)
        machine.pause(at: 10)
        machine.resume(at: 80)
        XCTAssertEqual(machine.remaining, 6)
        machine.tick(at: 86)
        XCTAssertEqual(machine.completedRepetitions, 1)
        XCTAssertEqual(machine.activeDuration, 11)
    }

    func testPauseDuringPreparationDoesNotInventRepetition() {
        var machine = TrainingMachine(course: .stage(0))
        machine.start(at: 0)
        machine.pause(at: 2)
        machine.resume(at: 50)
        machine.tick(at: 56)
        XCTAssertEqual(machine.completedRepetitions, 0)
        XCTAssertEqual(machine.phase, .contract)
    }

    func testEarlyEndIsIdempotentAndNeverCreditsBackgroundTime() {
        var machine = TrainingMachine(course: .stage(0))
        machine.start(at: 0)
        machine.tick(at: 5)
        machine.end(at: 6.5)
        machine.end(at: 200)
        machine.resume(at: 300)
        machine.tick(at: 400)
        XCTAssertEqual(machine.phase, .interrupted)
        XCTAssertEqual(machine.activeDuration, 1.5)
        XCTAssertEqual(machine.completedRepetitions, 0)
    }

    func testDelayedTickDoesNotSkipCuesOrInventWork() {
        var machine = TrainingMachine(course: .stage(0))
        machine.start(at: 0)
        machine.tick(at: 100)
        XCTAssertEqual(machine.phase, .contract)
        XCTAssertEqual(machine.activeDuration, 0)
        machine.tick(at: 200)
        XCTAssertEqual(machine.phase, .relax)
        XCTAssertEqual(machine.activeDuration, 3)
        XCTAssertEqual(machine.completedRepetitions, 0)
    }

    func testFractionalTicksUseElapsedTimeRatherThanTickCount() {
        var machine = TrainingMachine(course: .stage(0))
        machine.start(at: 10)
        machine.tick(at: 10.125)
        machine.tick(at: 12.75)
        XCTAssertEqual(machine.remaining, 2.25, accuracy: 0.0001)
    }
}
