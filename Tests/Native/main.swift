import AppKit
import CoreGraphics

let evidence = URL(fileURLWithPath: CommandLine.arguments[1])
MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let config = AppConfiguration.isolated(directory: evidence.appendingPathComponent("history"))
    let delegate = AppDelegate(configuration: config)
    app.delegate = delegate
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        func require(_ condition: Bool, _ name: String) {
            guard condition else { fputs("FAIL: \(name)\n", stderr); exit(1) }
            print("PASS: \(name)")
        }
        let controller = delegate.settingsController!
        let window = controller.window!
        require(window.isVisible, "isolated app launched and settings window is visible")
        require(Bundle.main.bundleIdentifier == "org.jobsdone.native-tests", "separate bundle identity")
        func views(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(views) }
        let controls = views(window.contentView!)
        let buttons = controls.compactMap { $0 as? NSButton }
        let event = buttons.first { $0.identifier?.rawValue == "opened" }!
        event.performClick(nil)
        require(!NotificationPreferences(defaults: config.defaults).isEnabled(.opened), "real event action saved and read back")
        let sound = buttons.first { $0.title == "Play celebration sounds" }!
        sound.performClick(nil)
        require(!delegate.preferences.soundEnabled, "real sound action saved")
        require(delegate.menu.items.first { $0.title == "Play Celebration Sound" }?.state == .off, "settings action synchronized menu")
        let menuSound = delegate.menu.items.first { $0.title == "Play Celebration Sound" }!
        app.sendAction(menuSound.action!, to: menuSound.target, from: menuSound)
        require(sound.state == .on && NotificationPreferences(defaults: config.defaults).soundEnabled, "menu action synchronized settings and defaults")
        let field = controls.compactMap { $0 as? NSTextField }.first { $0.placeholderString == "owner/repository" }!
        field.stringValue = " Owner/Repo "
        buttons.first { $0.title == "Add" }!.performClick(nil)
        require(NotificationPreferences(defaults: config.defaults).ignoredRepositories == ["owner/repo"], "real add action normalized and saved")
        let remove = views(window.contentView!).compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "owner/repo" }!
        remove.performClick(nil)
        require(NotificationPreferences(defaults: config.defaults).ignoredRepositories.isEmpty, "real remove action saved")
        let style = controls.compactMap { $0 as? NSPopUpButton }.first!
        style.selectItem(at: 1)
        app.sendAction(style.action!, to: style.target, from: style)
        require(NotificationPreferences(defaults: config.defaults).nativeNotifications, "style action saved and read back")
        delegate.showSettings()
        require(delegate.settingsController === controller, "settings singleton reused")
        require(delegate.menu.items.contains { $0.title == "Settings…" && $0.keyEquivalent == "," }, "settings menu shortcut retained")
        window.contentView!.layoutSubtreeIfNeeded()
        let view = window.contentView!
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: bitmap)
        do {
            try bitmap.representation(using: .png, properties: [:])!.write(to: evidence.appendingPathComponent("settings-content-view.png"))
        } catch {
            fputs("FAIL: capture write: \(error)\n", stderr)
            exit(1)
        }
        let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        let own = windows.filter { ($0[kCGWindowOwnerPID as String] as? Int) == Int(ProcessInfo.processInfo.processIdentifier) }
        print("On-screen window records for native harness: \(own.count); visible window number: \(window.windowNumber)")
        print("Capture is an NSView render, not a compositor screenshot.")
        window.close()
        exit(0)
    }
    withExtendedLifetime(delegate) { app.run() }
}
