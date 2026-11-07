import Foundation
import UserNotifications

enum NotificationReadiness: Equatable {
    case checking, notDetermined, denied, quiet, ready

    var canPost: Bool { self == .ready || self == .quiet }
    var actionTitle: String {
        switch self {
        case .checking: return "macOS Notification Settings…"
        case .notDetermined: return "Allow Notifications…"
        case .denied: return "Notifications Off — macOS Notification Settings…"
        case .quiet: return "Banners Off — macOS Notification Settings…"
        case .ready: return "macOS Notification Settings…"
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

struct ToastPreview {
    let subtitle: String
    let body: String
    init(subtitle: String, body: String, previewsEnabled: Bool) {
        self.subtitle = previewsEnabled ? subtitle : "Pull request update"
        self.body = previewsEnabled ? body : "A pull request update is ready."
    }
}

// Copy framework-owned settings before crossing to the main actor.
struct NotificationSettingsSnapshot: Sendable {
    let authorizationStatus: UNAuthorizationStatus
    let alertSetting: UNNotificationSetting
    let alertStyle: UNAlertStyle
    let soundSetting: UNNotificationSetting
    let showPreviewsSetting: UNShowPreviewsSetting

    static func current() async -> NotificationSettingsSnapshot {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: NotificationSettingsSnapshot(settings))
            }
        }
    }

    init(_ settings: UNNotificationSettings) {
        authorizationStatus = settings.authorizationStatus
        alertSetting = settings.alertSetting
        alertStyle = settings.alertStyle
        soundSetting = settings.soundSetting
        showPreviewsSetting = settings.showPreviewsSetting
    }
}
