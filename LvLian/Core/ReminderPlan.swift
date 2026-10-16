import Foundation

public struct ReminderPlan: Equatable, Sendable {
    public static let identifier = "daily-training"
    public let hour: Int
    public let minute: Int
    public init(hour: Int, minute: Int) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }
    public var dateComponents: DateComponents { DateComponents(hour: hour, minute: minute) }
    public let title = "律练"
    public let body = "该进行今天的练习了"
}

@MainActor
public protocol ReminderBackend {
    func authorize() async throws -> Bool
    func replace(with plan: ReminderPlan) async throws
    func cancel()
}

/// Shared orchestration is testable without the iOS notification framework.
@MainActor
public struct ReminderScheduler {
    private let backend: any ReminderBackend
    public init(backend: any ReminderBackend) { self.backend = backend }

    public func apply(enabled: Bool, plan: ReminderPlan) async throws -> Bool {
        guard enabled else { backend.cancel(); return false }
        guard try await backend.authorize() else { backend.cancel(); return false }
        try await backend.replace(with: plan)
        return true
    }
}
