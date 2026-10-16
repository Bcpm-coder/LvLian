import SwiftUI
import SwiftData
import UserNotifications

@main
struct LvLianApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var settings = AppSettings()
    @State private var reminders = ReminderService()
    private let container: ModelContainer?
    private let launchError: String?
    @State private var library: TrainingLibrary?

    init() {
        do {
            let configuration: ModelConfiguration
            if TrainingDiagnostics.mode != nil {
                let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("TrainingDiagnostics.store")
                configuration = ModelConfiguration("TrainingDiagnostics", url: url, cloudKitDatabase: .none)
                let diagnostics = AppSettings(defaults: UserDefaults(suiteName: "com.personal.lvlian.diagnostics")!)
                diagnostics.onboardingComplete = true
                _settings = State(initialValue: diagnostics)
            } else {
                configuration = ModelConfiguration(cloudKitDatabase: .none)
            }
            let created = try ModelContainer(for: TrainingRecord.self, SquatRecord.self, configurations: configuration)
            container = created
            _library = State(initialValue: TrainingLibrary(container: created))
            launchError = nil
        } catch {
            container = nil
            launchError = error.localizedDescription
        }
    }

    var body: some Scene {
        WindowGroup {
            if let container, let library {
                RootView()
                    .environment(library)
                    .environment(settings)
                    .environment(reminders)
                    .modelContainer(container)
                    .tint(Theme.teal)
                    .preferredColorScheme(.light)
            } else {
                ContentUnavailableView {
                    Label("暂时无法打开记录", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text("请重新启动 App。现有数据不会被自动清除。\n\(launchError ?? "")")
                }
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
