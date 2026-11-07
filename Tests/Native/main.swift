import AppKit
import CoreGraphics

let evidence = URL(fileURLWithPath: CommandLine.arguments[1])
MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    var config = AppConfiguration.isolated(directory: evidence.appendingPathComponent("history"))
    var scheduled: [TimeInterval] = []
    var dismissActions: [() -> Void] = []
    var posted: [String] = []
    let presenter = PeonToastPresenter(scheduleTimer: { interval, action in
        scheduled.append(interval)
        dismissActions.append(action)
        return Timer(timeInterval: interval, repeats: false) { _ in }
    })
    config.notificationOutput = { posted.append($0.identifier) }
    let delegate = AppDelegate(configuration: config, peonToasts: presenter)
    app.delegate = delegate
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        Task { @MainActor in
        func require(_ condition: Bool, _ name: String) {
            guard condition else { fputs("FAIL: \(name)\n", stderr); exit(1) }
            print("PASS: \(name)")
        }
        let controller = delegate.settingsController!
        let window = controller.window!
        require(window.isVisible, "isolated app launched and settings window is visible")
        require(Bundle.main.bundleIdentifier == "org.jobsdone.native-tests", "separate bundle identity")
        @MainActor func views(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(views) }
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
        let popups = controls.compactMap { $0 as? NSPopUpButton }
        let pack = popups.first { $0.accessibilityLabel() == "Sound pack" }!
        require(pack.titleOfSelectedItem == "Peon", "default sound pack is visible")
        app.sendAction(pack.action!, to: pack.target, from: pack)
        require(config.defaults.string(forKey: "soundPackID") == "peon", "sound pack action persists stable ID")
        let polling = popups.first { $0.accessibilityLabel() == "GitHub polling interval" }!
        polling.selectItem(at: 3)
        app.sendAction(polling.action!, to: polling.target, from: polling)
        require(NotificationPreferences(defaults: config.defaults).pollingInterval == 300, "polling action saved and read back")
        require(delegate.menu.items.contains { $0.title.contains("every 300 seconds") }, "polling action synchronized menu")
        let duration = popups.first { $0.accessibilityLabel() == "Notification duration" }!
        duration.selectItem(at: 3)
        app.sendAction(duration.action!, to: duration.target, from: duration)
        require(NotificationPreferences(defaults: config.defaults).notificationDuration == 15, "duration action saved and read back")
        let style = popups.first { $0.accessibilityLabel() == "Notification style" }!
        style.selectItem(at: 1)
        app.sendAction(style.action!, to: style.target, from: style)
        require(NotificationPreferences(defaults: config.defaults).nativeNotifications, "style action saved and read back")
        require(!duration.isEnabled, "macOS duration is unavailable")
        style.selectItem(at: 0)
        app.sendAction(style.action!, to: style.target, from: style)
        require(duration.isEnabled && duration.titleOfSelectedItem == "15 seconds", "Peon duration restored")
        await delegate.post(id: "jobsdone-test-duration", subtitle: "Timing", body: "Fixture", url: "https://github.com/owner/repo/pull/1")
        require(posted == ["jobsdone-test-duration"], "production post reached notification boundary")
        require(!scheduled.isEmpty && scheduled.allSatisfy { $0 == 15 }, "production post forwards selected duration for tests")
        require(app.windows.contains { $0.title == "Job’s Done — Timing" && $0.isVisible }, "production post showed toast")
        dismissActions.last!()
        try? await Task.sleep(nanoseconds: 50_000_000)
        require(!app.windows.contains { $0.title == "Job’s Done — Timing" && $0.isVisible }, "scheduled callback dismissed toast")
        scheduled.removeAll()
        delegate.preferences.notificationDuration = 30
        await delegate.post(event: .merged, repository: "owner/repo", id: "real-duration", subtitle: "Event timing", body: "Fixture", url: "https://github.com/owner/repo/pull/1")
        require(!scheduled.isEmpty && scheduled.allSatisfy { $0 == 30 }, "new event toast reads changed duration")
        require(posted.last == "real-duration", "event reached notification boundary")
        presenter.dismissAll()
        delegate.preferences.notificationDuration = 15
        delegate.showSettings()
        require(delegate.settingsController === controller, "settings singleton reused")
        require(delegate.menu.items.contains { $0.title == "Settings…" && $0.keyEquivalent == "," }, "settings menu shortcut retained")
        window.contentView!.layoutSubtreeIfNeeded()
        let view = window.contentView!
        guard let viewport = view as? NSScrollView else {
            fputs("FAIL: expected scroll viewport\n", stderr); exit(1)
        }
        let document = viewport.documentView!
        print("Viewport: \(viewport.frame), document: \(document.frame), polling: \(polling.frame)")
        require(document.frame.width > 500 && document.frame.height > 700, "scroll document has full layout")
        let bitmap = document.bitmapImageRepForCachingDisplay(in: document.bounds)!
        document.displayIgnoringOpacity(document.bounds, in: NSGraphicsContext(bitmapImageRep: bitmap)!)
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
        let originalSize = window.contentView!.frame.size
        window.setContentSize(NSSize(width: 600, height: 600))
        window.contentView!.layoutSubtreeIfNeeded()
        document.scroll(NSPoint(x: 0, y: document.bounds.height - viewport.contentView.bounds.height))
        require(viewport.documentVisibleRect.maxY >= document.bounds.maxY - 1, "short window can scroll to footer")
        window.setContentSize(originalSize)
        document.scroll(.zero)
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-l", String(window.windowNumber), evidence.appendingPathComponent("settings-window.png").path]
        do { try capture.run() }
        catch { fputs("FAIL: compositor capture: \(error)\n", stderr); exit(1) }
        capture.waitUntilExit()
        print("Compositor capture exit: \(capture.terminationStatus)")
        let fixturePack = SoundPack(id: "fixture", name: "Fixture", directory: evidence)
        let registry = SoundPackRegistry(packs: [config.soundPacks.defaultPack, fixturePack], defaultID: "peon")
        let fixtureSettings = NotificationSettingsController(preferences: NotificationPreferences(defaults: config.defaults, soundPacks: registry))
        let fixturePopup = views(fixtureSettings.window!.contentView!).compactMap { $0 as? NSPopUpButton }
            .first { $0.accessibilityLabel() == "Sound pack" }!
        fixturePopup.selectItem(at: 1)
        app.sendAction(fixturePopup.action!, to: fixturePopup.target, from: fixturePopup)
        require(NotificationPreferences(defaults: config.defaults, soundPacks: registry).soundPack.id == "fixture", "second registered pack action persists selection")
        fixtureSettings.refresh()
        require(fixturePopup.titleOfSelectedItem == "Fixture", "refresh retains second pack selection")
        config.defaults.removeObject(forKey: "soundPackID")
        fixtureSettings.close()
        window.close()
        exit(0)
        }
    }
    withExtendedLifetime(delegate) { app.run() }
}
