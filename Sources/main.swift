import AppKit
import UserNotifications

#if !JOBSDONE_DEV
if CommandLine.arguments.contains("--notification-diagnostics") {
    let center = UNUserNotificationCenter.current()
    Task {
        let settings = await center.notificationSettings()
        let delivered = await center.deliveredNotifications()
        let tests = delivered.filter { $0.request.identifier.hasPrefix("jobsdone-test") }
        print("App version:", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "unknown")
        print("Bundle:", Bundle.main.bundleURL.path)
        print("Notification style:", UserDefaults.standard.bool(forKey: "nativeNotifications") ? "macOS" : "Peon toast")
        print("Notification authorization:", settings.authorizationStatus.rawValue, "alert style:", settings.alertStyle.rawValue)
        for notification in tests { print("Delivered test:", notification.request.content.subtitle, "|", notification.request.content.body) }
        exit(0)
    }
    dispatchMain()
}

if CommandLine.arguments.contains("--check") {
    do {
        let login = try GitHub.login()
        let since = Date().addingTimeInterval(-172800)
        let prs = try GitHub.merged(login: login, since: since)
        let opened = try GitHub.opened(login: login, since: since)
        print("GitHub connection OK: @\(login), \(opened.count) created PRs and \(prs.count) merged PRs in the last 48 hours (read-only; no notifications or state changes).")
        exit(0)
    } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
}

#endif

MainActor.assumeIsolated {
    let app = NSApplication.shared
    #if JOBSDONE_DEV
    let configuration = AppConfiguration(defaults: UserDefaults(suiteName: "org.jobsdone.dev.preferences")!,
        historyDirectory: Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("history"), isolated: true)
    let delegate = AppDelegate(configuration: configuration)
    #else
    let delegate = AppDelegate()
    #endif
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
