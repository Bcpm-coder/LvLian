import SwiftUI
import UserNotifications

@MainActor
@Observable
final class ReminderService {
    private(set) var enabled: Bool
    private(set) var hour: Int
    private(set) var minute: Int
    private(set) var denied = false
    private(set) var busy = false
    var errorMessage: String?
    private let defaults = UserDefaults.standard
    private let center = UNUserNotificationCenter.current()

    init() {
        enabled = UserDefaults.standard.bool(forKey: "reminderEnabled")
        hour = UserDefaults.standard.object(forKey: "reminderHour") as? Int ?? 21
        minute = UserDefaults.standard.integer(forKey: "reminderMinute")
    }

    var date: Date {
        Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? .now
    }

    func update(enabled requested: Bool, date: Date? = nil) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        errorMessage = nil
        let components = date.map { Calendar.current.dateComponents([.hour, .minute], from: $0) }
        let plan = ReminderPlan(hour: components?.hour ?? hour, minute: components?.minute ?? minute)
        do {
            enabled = try await ReminderScheduler(backend: NotificationBackend(center: center))
                .apply(enabled: requested, plan: plan)
            denied = await center.notificationSettings().authorizationStatus == .denied
            save(plan)
        } catch {
            errorMessage = "提醒设置未能更新，请重试。\n\(error.localizedDescription)"
        }
    }

    func refresh() async {
        guard !busy else { return }
        let status = await center.notificationSettings().authorizationStatus
        denied = status == .denied
        if denied {
            await update(enabled: false)
        } else if enabled {
            await update(enabled: true)
        }
    }

    private func save(_ plan: ReminderPlan) {
        hour = plan.hour
        minute = plan.minute
        defaults.set(enabled, forKey: "reminderEnabled")
        defaults.set(hour, forKey: "reminderHour")
        defaults.set(minute, forKey: "reminderMinute")
    }
}

@MainActor
private struct NotificationBackend: ReminderBackend {
    let center: UNUserNotificationCenter

    func authorize() async throws -> Bool {
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
            status = await center.notificationSettings().authorizationStatus
        }
        return status == .authorized || status == .provisional || status == .ephemeral
    }

    func replace(with plan: ReminderPlan) async throws {
        let content = UNMutableNotificationContent()
        content.title = plan.title
        content.body = plan.body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: ReminderPlan.identifier, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: plan.dateComponents, repeats: true)
        )
        try await center.add(request)
    }

    func cancel() {
        center.removePendingNotificationRequests(withIdentifiers: [ReminderPlan.identifier])
    }
}
