#if STANDALONE_TESTS
import Foundation
#else
import XCTest
@testable import LvLianCore
#endif

@MainActor
private final class FakeBackend: ReminderBackend {
    var allowed = true
    var fail = false
    var authorizationCalls = 0
    var pending: [String: ReminderPlan] = [:]
    func authorize() async throws -> Bool { authorizationCalls += 1; return allowed }
    func replace(with plan: ReminderPlan) async throws {
        if fail { throw NSError(domain: "test", code: 1) }
        pending[ReminderPlan.identifier] = plan
    }
    func cancel() { pending.removeValue(forKey: ReminderPlan.identifier) }
}

final class ReminderTests: XCTestCase {
    @MainActor
    func testEnableReplaceAndCancel() async throws {
        let backend = FakeBackend()
        let scheduler = ReminderScheduler(backend: backend)
        let enabled = try await scheduler.apply(enabled: true, plan: ReminderPlan(hour: 21, minute: 0))
        XCTAssertTrue(enabled)
        _ = try await scheduler.apply(enabled: true, plan: ReminderPlan(hour: 8, minute: 30))
        XCTAssertEqual(backend.pending.count, 1)
        XCTAssertEqual(backend.pending[ReminderPlan.identifier]?.dateComponents, DateComponents(hour: 8, minute: 30))
        let disabled = try await scheduler.apply(enabled: false, plan: ReminderPlan(hour: 8, minute: 30))
        XCTAssertFalse(disabled)
        XCTAssertTrue(backend.pending.isEmpty)
        XCTAssertEqual(backend.authorizationCalls, 2)
    }

    @MainActor
    func testDeniedPermissionRemovesStaleRequest() async throws {
        let backend = FakeBackend()
        let scheduler = ReminderScheduler(backend: backend)
        _ = try await scheduler.apply(enabled: true, plan: ReminderPlan(hour: 21, minute: 0))
        backend.allowed = false
        let enabled = try await scheduler.apply(enabled: true, plan: ReminderPlan(hour: 10, minute: 0))
        XCTAssertFalse(enabled)
        XCTAssertTrue(backend.pending.isEmpty)
    }

    @MainActor
    func testSchedulingFailurePreservesPreviousPlan() async throws {
        let backend = FakeBackend()
        let scheduler = ReminderScheduler(backend: backend)
        let original = ReminderPlan(hour: 21, minute: 0)
        _ = try await scheduler.apply(enabled: true, plan: original)
        backend.fail = true
        do {
            _ = try await scheduler.apply(enabled: true, plan: ReminderPlan(hour: 9, minute: 0))
            XCTFail("Expected scheduling error")
        } catch {
            XCTAssertEqual(backend.pending[ReminderPlan.identifier], original)
        }
    }
}
