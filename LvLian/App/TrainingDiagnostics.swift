import Foundation

/// Explicit developer launch arguments use a separate store and preferences.
/// Never selected during an ordinary launch and never included in Release builds.
enum TrainingDiagnostics {
    static var mode: String? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--diagnostic-pelvic") { return "pelvic" }
        if ProcessInfo.processInfo.arguments.contains("--diagnostic-squat") { return "squat" }
        #endif
        return nil
    }
}
