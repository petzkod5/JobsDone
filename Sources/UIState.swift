import Foundation

enum NotificationReadiness: Equatable {
    case checking, notDetermined, denied, quiet, ready

    var canPost: Bool { self == .ready || self == .quiet }
    var actionTitle: String {
        switch self {
        case .checking: return "Notification Settings…"
        case .notDetermined: return "Allow Notifications…"
        case .denied: return "Notifications Off — Open Settings…"
        case .quiet: return "Banners Off — Notification Settings…"
        case .ready: return "Notification Settings…"
        }
    }
    var explanation: String {
        switch self {
        case .checking, .notDetermined: return "Notification permission has not been granted yet."
        case .denied: return "macOS notification permission is off for Job’s Done."
        case .quiet: return "Notifications can be delivered quietly, but banners are disabled."
        case .ready: return "Notification permission and alerts are enabled."
        }
    }
}

enum MenuCopy {
    static func truncated(_ value: String, limit: Int) -> String {
        value.count > limit ? String(value.prefix(max(0, limit - 1))) + "…" : value
    }
}
