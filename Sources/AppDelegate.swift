import AppKit
import ServiceManagement
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, NSMenuDelegate, NSUserInterfaceValidations {
    private var item: NSStatusItem!
    let menu = NSMenu()
    private(set) var timer: Timer?
    private var busy = false
    private var testing = false
    private var menuOpen = false
    private var paused: Bool
    let preferences: NotificationPreferences
    private let configuration: AppConfiguration
    private(set) var settingsController: NotificationSettingsController?
    private var soundEnabled: Bool { preferences.soundEnabled }
    private var monitorError: String?
    private var startupError: String?
    private var deliveryWarning: String?
    private var soundWarning: String?
    var soundEndsAt = Date.distantPast
    var lastCheck: Date?
    var notificationState = NotificationReadiness.checking
    private var systemSoundAllowed = true
    private var toastPreviewsEnabled = true
    private var nativeSoundTypes = Set<String>()
    var login = ""
    var history = ActivityHistory()
    private let store: StateStore
    private var sound: NSSound?
    let statusView = MenuStatusView()
    private var statusRow: NSMenuItem?
    private var monitorErrorRow: NSMenuItem?
    private var permissionRow: NSMenuItem?
    private var checkRow: NSMenuItem?
    private var testRow: NSMenuItem?
    private var soundRow: NSMenuItem?
    private var pollTask: Task<Void, Never>?
    private var helpWindow: NSWindow?
    private var helpTestButton: NSButton?
    private var helpMenuButton: NSButton?
    private let peonToasts: PeonToastPresenter
    private var usesPeonToasts: Bool { !preferences.nativeNotifications }

    init(configuration: AppConfiguration = .production, peonToasts: PeonToastPresenter? = nil) {
        self.peonToasts = peonToasts ?? PeonToastPresenter()
        self.configuration = configuration
        preferences = NotificationPreferences(defaults: configuration.defaults, soundPacks: configuration.soundPacks)
        store = StateStore(directory: configuration.historyDirectory)
        paused = configuration.defaults.bool(forKey: "paused")
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "local.JobsDone").count > 1 {
            NSApp.terminate(nil); return
        }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        menu.autoenablesItems = false
        menu.delegate = self
        item.menu = menu
        installApplicationMenu()
        if configuration.isolated {
            notificationState = .ready
            refreshMenu()
            showSettings()
            settingsController?.window?.title = "JobsDone Dev / Test Settings"
            return
        }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.removeDeliveredNotifications(withIdentifiers: ["jobsdone-test", "jobsdone-test-current"])
        let action = UNNotificationAction(identifier: "OPEN_PR", title: "Open Pull Request", options: .foreground)
        let issueAction = UNNotificationAction(identifier: "OPEN_ISSUE", title: "Open Issue", options: .foreground)
        center.setNotificationCategories([UNNotificationCategory(identifier: "COMMENT_PR", actions: [action], intentIdentifiers: []), UNNotificationCategory(identifier: "OPENED_ISSUE", actions: [issueAction], intentIdentifiers: []), UNNotificationCategory(identifier: "COMMIT_PR", actions: [action], intentIdentifiers: []), UNNotificationCategory(identifier: "MERGED_PR", actions: [action], intentIdentifiers: []), UNNotificationCategory(identifier: "OPENED_PR", actions: [action], intentIdentifiers: [])])
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in
            Task { @MainActor in self?.updatePermission() }
        }
        updatePermission()
        if !UserDefaults.standard.bool(forKey: "startupConfigured") {
            do {
                try SMAppService.mainApp.register()
                UserDefaults.standard.set(true, forKey: "startupConfigured")
            } catch { startupError = error.localizedDescription }
        }
        refreshMenu()
        reschedulePolling()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(activated), name: NSApplication.didBecomeActiveNotification, object: nil)
        check()
        if !UserDefaults.standard.bool(forKey: "setupHelpShown") {
            UserDefaults.standard.set(true, forKey: "setupHelpShown")
            DispatchQueue.main.async { self.showHelp() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showHelp() }
        return false
    }

    func menuNeedsUpdate(_ menu: NSMenu) { refreshMenu(); updatePermission() }
    func menuWillOpen(_ menu: NSMenu) { menuOpen = true }
    func menuDidClose(_ menu: NSMenu) { menuOpen = false }

    private func updatePermission() {
        guard !configuration.isolated else { return }
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let snapshot = NotificationSettingsSnapshot(settings)
            Task { @MainActor in self?.apply(snapshot) }
        }
    }

    private func apply(_ settings: NotificationSettingsSnapshot) {
        switch settings.authorizationStatus {
        case .notDetermined: notificationState = .notDetermined
        case .denied: notificationState = .denied
        case .provisional: notificationState = .quiet
        case .authorized:
            notificationState = settings.alertSetting == .enabled && settings.alertStyle != .none ? .ready : .quiet
        @unknown default: notificationState = .quiet
        }
        systemSoundAllowed = settings.soundSetting != .disabled
        toastPreviewsEnabled = settings.showPreviewsSetting != .never
        refreshMenu()
    }

    private var status: String {
        if paused { return busy ? "Pausing — finishing current check…" : "Paused — resume to catch up" }
        if busy { return "Checking GitHub…" }
        if monitorError != nil { return "Monitoring needs attention — View Details…" }
        if let lastCheck {
            return "Watching · checked \(DateFormatter.localizedString(from: lastCheck, dateStyle: .none, timeStyle: .short))"
        }
        return "Connecting to GitHub…"
    }

    /// Problems that get their own row under the status header.
    private var setupProblems: Int {
        let permission = notificationState == .ready || notificationState == .checking ? 0 : 1
        return permission + [deliveryWarning, soundWarning, startupError].compactMap { $0 }.count
    }

    /// Headline, detail, and icon for the status header. Warning rows below turn the header orange; while
    /// paused or checking, the header keeps its state icon and shows the problem count instead.
    private var statusSummary: (String, String, NSImage?) {
        let every = "every \(ActivityFormat.interval(preferences.pollingInterval))"
        let account = login.isEmpty ? "" : " @\(login)"
        func icon(_ name: String, _ tint: NSColor) -> NSImage? { MenuStyle.symbol(name, tint: tint, description: name, size: 15) }
        let problems = setupProblems + (monitorError == nil ? 0 : 1)
        let below = problems == 0 ? nil : problems == 1 ? "1 problem below" : "\(problems) problems below"
        if paused {
            let detail = busy ? "Finishing the current check…" : below ?? "Resume to catch up on missed events"
            return ("Paused", detail, icon("pause.circle.fill", .systemGray))
        }
        if busy { return ("Checking GitHub…", below ?? "Watching\(account) · \(every)", icon("arrow.triangle.2.circlepath.circle.fill", .systemBlue)) }
        if let monitorError {
            let reason = monitorError.split(whereSeparator: \.isNewline).first.map(String.init) ?? monitorError
            return ("Monitoring needs attention", MenuCopy.truncated(reason, limit: 48), MenuStyle.warning(size: 15))
        }
        let checked = lastCheck.map { "Checked \(DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .short))" }
        let headline = checked == nil ? "Connecting to GitHub…" : "Watching\(account)"
        if let below { return (headline, [checked, below].compactMap { $0 }.joined(separator: " · "), MenuStyle.warning(size: 15)) }
        guard let checked else { return (headline, "Checks \(every)", icon("circle.dotted", .systemGray)) }
        return (headline, "\(checked) · \(every)", icon("checkmark.circle.fill", .systemGreen))
    }

    private var testTitle: String {
        testing ? "Testing…" : (soundEnabled && systemSoundAllowed ? "Test Sound + Notification" : "Test Notification (Sound Off)")
    }

    private var soundTitle: String {
        systemSoundAllowed ? "Play Celebration Sound" : "Sound Off in macOS — Notification Settings…"
    }

    private func updateIcon() {
        let description = "Job’s Done — \(paused ? "paused" : monitorError == nil ? "monitoring" : "needs attention"), sound \(soundEnabled && systemSoundAllowed ? "on" : "off")"
        let icon: NSImage?
        if !paused && monitorError != nil {
            icon = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: description)
        } else if let path = Bundle.main.path(forResource: "MenuBarPeon", ofType: "png") {
            icon = NSImage(contentsOfFile: path)
            icon?.size = NSSize(width: 18, height: 18)
            icon?.accessibilityDescription = description
        } else {
            icon = NSImage(systemSymbolName: "person.crop.circle", accessibilityDescription: description)
        }
        icon?.isTemplate = true
        item.button?.image = icon
        item.button?.appearsDisabled = paused
        item.button?.setAccessibilityLabel(description)
        item.button?.toolTip = status
    }

    /// Number of newest events listed directly in the menu; the rest stay one level down in All Activity.
    static let recentActivityLimit = 5

    func refreshMenu() {
        guard item != nil else { return }
        if SMAppService.mainApp.status == .enabled { startupError = nil }
        settingsController?.refresh(systemSoundAllowed: systemSoundAllowed)
        updateIcon()
        helpTestButton?.title = testTitle
        helpTestButton?.isEnabled = !busy && !testing
        // Preserve the active native menu and its keyboard selection during background updates.
        if menuOpen { updateLiveRows(); return }
        menu.removeAllItems()
        addStatusRows()
        menu.addItem(.separator())
        addActivityRows()
        menu.addItem(.separator())
        addControlRows()
        menu.addItem(.separator())
        let startup = row(startupTitle, #selector(toggleStartup))
        startup.state = SMAppService.mainApp.status == .enabled ? .on : (SMAppService.mainApp.status == .requiresApproval ? .mixed : .off)
        startup.image = MenuStyle.control("power.circle", "Open at Login")
        row("Settings…", #selector(showSettings), key: ",").image = MenuStyle.control("gearshape", "Settings")
        row("Setup Help…", #selector(showHelp)).image = MenuStyle.control("questionmark.circle", "Setup Help")
        row("Quit Job’s Done", #selector(quit), key: "q").image = MenuStyle.control("xmark.circle", "Quit")
        updateLiveRows()
    }

    @discardableResult
    private func row(_ title: String, _ action: Selector? = nil, key: String = "", in parent: NSMenu? = nil) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = self
        (parent ?? menu).addItem(entry)
        return entry
    }

    private func warningRow(_ title: String, _ action: Selector) -> NSMenuItem {
        let entry = row(title, action)
        entry.image = MenuStyle.warning()
        return entry
    }

    private func addStatusRows() {
        statusRow = row(status)
        statusRow?.view = statusView
        // Disabled so arrow keys skip it; the view draws its own full-contrast text.
        statusRow?.isEnabled = false
        // Only problems get their own rows; healthy settings live in Settings….
        monitorErrorRow = warningRow("Show Error Details…", #selector(showMonitorError))
        permissionRow = warningRow(notificationState.actionTitle, #selector(notificationSettings))
        if deliveryWarning != nil { _ = warningRow("Notification issue — View Details…", #selector(showDeliveryWarning)) }
        if soundWarning != nil { _ = warningRow("Sound issue — View Details…", #selector(showSoundWarning)) }
        if startupError != nil { _ = warningRow("Open at Login needs attention — View Details…", #selector(showStartupError)) }
    }

    private func addActivityRows() {
        menu.addItem(MenuStyle.sectionHeader("Recent Activity"))
        let now = configuration.now()
        let timeline = history.timeline
        guard !timeline.isEmpty else {
            let empty = row("No activity yet")
            empty.attributedTitle = MenuStyle.twoLine("No activity yet", "New events from GitHub appear here")
            empty.image = MenuStyle.symbol("tray", tint: .tertiaryLabelColor, description: "No activity")
            empty.isEnabled = false
            return
        }
        for entry in timeline.prefix(Self.recentActivityLimit) {
            menu.addItem(MenuStyle.activityItem(entry, now: now, target: self, action: #selector(openPR(_:))))
        }
        // Everything is already listed above, so a grouped view would only repeat it.
        guard timeline.count > Self.recentActivityLimit else { return }
        let all = NSMenu()
        all.autoenablesItems = false
        for kind in ActivityKind.allCases {
            let entries = history.entries(kind)
            guard !entries.isEmpty else { continue }
            let category = row(kind.sectionTitle, in: all)
            category.image = MenuStyle.symbol(kind.symbol, tint: kind.tint, description: kind.label)
            MenuStyle.setCount(entries.count, on: category, title: kind.sectionTitle)
            let list = NSMenu()
            list.autoenablesItems = false
            for entry in entries {
                list.addItem(MenuStyle.activityItem(entry, now: now, includeKind: false, target: self, action: #selector(openPR(_:))))
            }
            category.submenu = list
        }
        let allRow = row("All Activity")
        allRow.submenu = all
        allRow.image = MenuStyle.control("tray.full", "All Activity")
        MenuStyle.setCount(timeline.count, on: allRow, title: "All Activity")
    }

    private func addControlRows() {
        checkRow = row("Check Now", #selector(checkNow), key: "r")
        checkRow?.image = MenuStyle.control("arrow.clockwise", "Check Now")
        row(paused ? "Resume Monitoring" : "Pause Monitoring", #selector(togglePause)).image =
            MenuStyle.control(paused ? "play.circle" : "pause.circle", paused ? "Resume" : "Pause")
        soundRow = row(soundTitle, #selector(toggleSound))
        soundRow?.toolTip = "One sound per event type per check, even when several events arrive. macOS notification Sound settings also apply."
        let tests = NSMenu()
        tests.autoenablesItems = false
        tests.addItem(MenuStyle.sectionHeader(soundEnabled && systemSoundAllowed ? "Plays the sound and shows a notification" : "Sound is off — shows a notification only"))
        for kind in ActivityKind.allCases {
            let entry = row(kind.testTitle, #selector(runTest(_:)), in: tests)
            entry.representedObject = kind
            entry.image = MenuStyle.symbol(kind.symbol, tint: kind.tint, description: kind.label)
        }
        testRow = row("Test Notifications")
        testRow?.submenu = tests
        testRow?.image = MenuStyle.control("bell.badge", "Test Notifications")
    }

    private func updateLiveRows() {
        let (headline, detail, image) = statusSummary
        statusRow?.title = "\(headline) — \(detail)"
        statusView.update(headline: headline, detail: detail, image: image)
        statusView.toolTip = status
        // Disabled rather than hidden during a check, so rows don't shift under the pointer.
        monitorErrorRow?.isHidden = monitorError == nil
        monitorErrorRow?.isEnabled = !busy
        monitorErrorRow?.toolTip = monitorError
        permissionRow?.title = notificationState.actionTitle
        permissionRow?.isHidden = notificationState == .ready || notificationState == .checking
        checkRow?.isEnabled = !busy && !paused && !testing
        checkRow?.title = busy ? "Checking…" : "Check Now"
        testRow?.title = testing ? "Testing…" : "Test Notifications"
        for entry in testRow?.submenu?.items ?? [] where entry.action != nil { entry.isEnabled = !busy && !testing }
        soundRow?.title = soundTitle
        // A checkmark would claim sound plays while macOS blocks it; the row opens macOS settings instead.
        soundRow?.state = soundEnabled && systemSoundAllowed ? .on : .off
        soundRow?.image = MenuStyle.control(soundEnabled && systemSoundAllowed ? "speaker.wave.2" : "speaker.slash", "Sound")
        statusView.hasStateColumn = menu.items.contains { !$0.isHidden && $0.state != .off }
        soundRow?.action = systemSoundAllowed ? #selector(toggleSound) : #selector(notificationSettings)
    }

    private var startupTitle: String {
        SMAppService.mainApp.status == .requiresApproval ? "Open at Login — Approve in Settings…" : "Open at Login"
    }

    func reschedulePolling() {
        guard !configuration.isolated else { return }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: preferences.pollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
    }

    @objc func showSettings() {
        if settingsController == nil {
            let controller = NotificationSettingsController(preferences: preferences)
            controller.onPollingIntervalChange = { [weak self] in
                self?.reschedulePolling()
                self?.refreshMenu()
            }
            controller.onChange = { [weak self] in
                guard let self else { return }
                self.peonToasts.dismissAll()
                self.sound?.stop()
                self.soundEndsAt = .distantPast
                self.refreshMenu()
            }
            controller.openSystemSettings = { [weak self] in self?.openSystemNotificationSettings() }
            settingsController = controller
        }
        settingsController?.refresh(systemSoundAllowed: systemSoundAllowed)
        settingsController?.present()
    }

    @objc private func checkNow() { check() }
    @objc private func woke() {
        updatePermission()
        timer?.fireDate = Date().addingTimeInterval(12)
    }
    @objc private func activated() { updatePermission(); refreshMenu() }
    @objc private func togglePause() {
        paused.toggle()
        configuration.defaults.set(paused, forKey: "paused")
        if paused { sound?.stop(); soundEndsAt = .distantPast; peonToasts.dismissAll() }
        refreshMenu()
        if !paused { check() }
    }
    @objc private func toggleSound() {
        preferences.soundEnabled.toggle()
        if !soundEnabled { sound?.stop(); soundEndsAt = .distantPast }
        refreshMenu()
    }
    @objc private func quit() { pollTask?.cancel(); sound?.stop(); peonToasts.dismissAll(); NSApp.terminate(nil) }
    @objc private func openSystemNotificationSettings() {
        guard !configuration.isolated else { return }
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
    }
    @objc private func notificationSettings() {
        guard !configuration.isolated else { return }
        if notificationState == .notDetermined {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in
                Task { @MainActor in self?.updatePermission() }
            }
        } else { openSystemNotificationSettings() }
    }
    @objc private func toggleStartup() {
        guard !configuration.isolated else { return }
        if SMAppService.mainApp.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
            return
        }
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
            startupError = nil
        } catch { startupError = error.localizedDescription }
        refreshMenu()
    }
    @objc private func openPR(_ sender: NSMenuItem) {
        if let value = sender.representedObject as? String { open(value) }
    }
    private func open(_ value: String) {
        guard let url = URL(string: value), url.scheme == "https", url.host == "github.com" else { return }
        NSWorkspace.shared.open(url)
    }
    private func alert(_ title: String, _ detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
    @objc private func showMonitorError() { if let monitorError { alert("Monitoring needs attention", monitorError + "\n\nChecks retry every \(Int(preferences.pollingInterval)) seconds. Use Check Now after correcting the issue. Setup Help explains GitHub sign-in.") } }
    @objc private func showStartupError() { if let startupError { alert("Open at Login needs attention", startupError + "\n\nUse System Settings → General → Login Items to review Job’s Done.") } }
    @objc private func showDeliveryWarning() { if let deliveryWarning { alert("Celebration needs attention", deliveryWarning + "\n\nYour GitHub events are saved in Recent Activity. They will not replay their sound because a banner failed.") } }
    @objc private func showSoundWarning() {
        if let soundWarning { alert("Celebration sound needs attention", soundWarning) }
    }

    private func installApplicationMenu() {
        let main = NSMenu()
        func submenu(_ title: String) -> NSMenu {
            let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let child = NSMenu(title: title)
            entry.submenu = child
            main.addItem(entry)
            return child
        }
        let application = submenu("Job’s Done")
        let about = NSMenuItem(title: "Setup Help…", action: #selector(showHelp), keyEquivalent: "")
        about.target = self
        application.addItem(about)
        let openMenu = NSMenuItem(title: "Open Peon Menu", action: #selector(openPeonMenu), keyEquivalent: "M")
        openMenu.keyEquivalentModifierMask = [.command, .shift]
        openMenu.target = self
        application.addItem(openMenu)
        application.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Job’s Done", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        application.addItem(quit)
        let file = submenu("File")
        let close = NSMenuItem(title: "Close", action: #selector(closeActiveWindow), keyEquivalent: "w")
        close.target = self
        file.addItem(close)
        let edit = submenu("Edit")
        edit.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        edit.addItem(.separator())
        edit.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        edit.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.addItem(NSMenuItem(title: "Undo", action: NSSelectorFromString("undo:"), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "Redo", action: NSSelectorFromString("redo:"), keyEquivalent: "Z")
        edit.addItem(redo)
        if let appMenu = main.items.first?.submenu {
            let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
            settings.target = self
            appMenu.insertItem(settings, at: 0)
            appMenu.insertItem(.separator(), at: 1)
        }
        NSApp.mainMenu = main
    }

    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        item.action != #selector(closeActiveWindow) || NSApp.keyWindow != nil
    }

    @objc private func closeActiveWindow() {
        if !peonToasts.dismissKeyToast() { NSApp.keyWindow?.performClose(nil) }
    }

    @objc private func openPeonMenu() {
        if helpWindow?.isVisible == true, let helpMenuButton { showHelpMenu(helpMenuButton) }
        else { item.button?.performClick(nil) }
    }

    @objc private func showHelp() {
        if let helpWindow, helpWindow.isVisible {
            helpWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 580), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Job’s Done — Setup Help"
        window.isReleasedWhenClosed = false
        let content = window.contentView!
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: 44), icon.heightAnchor.constraint(equalToConstant: 44)])
        let title = NSTextField(labelWithString: "Job’s Done \(version)")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        let header = NSStackView(views: [icon, title])
        header.spacing = 12
        func section(_ title: String, _ text: String, command: String? = nil) -> NSStackView {
            let heading = NSTextField(labelWithString: title)
            heading.font = .systemFont(ofSize: 12, weight: .semibold)
            heading.textColor = .secondaryLabelColor
            let body = NSTextField(wrappingLabelWithString: text)
            body.font = .systemFont(ofSize: 13)
            body.isSelectable = true
            body.preferredMaxLayoutWidth = 552
            if let command, let range = text.range(of: command) {
                let attributed = NSMutableAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor])
                attributed.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), range: NSRange(range, in: text))
                body.attributedStringValue = attributed
            }
            let section = NSStackView(views: [heading, body])
            section.orientation = .vertical
            section.alignment = .leading
            section.spacing = 4
            return section
        }
        let setup = section("SIGN IN", "Install GitHub CLI, then run in Terminal:\ngh auth login --hostname github.com", command: "gh auth login --hostname github.com")
        let watching = section("WHAT GETS CELEBRATED", "Your authored PRs: “Work Work” when opened, “Job’s done” when merged, “Hmmm?” for commits by other GitHub authors on your PRs, and “Get ’em!” for their comments. “Something need doing?” when anyone opens an issue in a repository you own. Set the GitHub polling interval in Settings. Checks catch up after sleep. Earlier events stay silent.")
        let controlsHelp = section("CONTROLS", "Turn off Play Celebration Sound to mute without stopping checks. Pause holds new alerts until you resume. Test Notifications and Open at Login are in the Peon menu. Keyboard: ⌘⇧M opens the menu from Help; use arrow keys and Return on Recent Activity.")
        let notices = section("NOTIFICATIONS", "Peon toasts show the real portrait and may appear during Focus. Choose macOS Notification as the Notification style in Settings for system banners and Focus handling. PR and issue links stay in Recent Activity after a toast closes.")
        let controls = NSStackView()
        controls.spacing = 12
        let menuButton = NSButton(title: "Open Peon Menu", target: self, action: #selector(showHelpMenu(_:)))
        helpMenuButton = menuButton
        menuButton.toolTip = "Open Peon Menu (⌘⇧M)"
        controls.addArrangedSubview(menuButton)
        let testButton = NSButton(title: testTitle, target: self, action: #selector(test))
        testButton.isEnabled = !busy && !testing
        helpTestButton = testButton
        controls.addArrangedSubview(testButton)
        controls.addArrangedSubview(NSButton(title: "macOS Notification Settings…", target: self, action: #selector(openSystemNotificationSettings)))
        let stack = NSStackView(views: [header, setup, watching, controlsHelp, notices, controls])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24), stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24), stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24)])
        content.layoutSubtreeIfNeeded()
        window.setContentSize(NSSize(width: 600, height: stack.fittingSize.height + 48))
        window.center()
        helpWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showHelpMenu(_ sender: NSButton) {
        refreshMenu()
        let belowButton = sender.isFlipped ? sender.bounds.maxY + 4 : sender.bounds.minY - 4
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: belowButton), in: sender)
    }

    private func check() {
        guard !configuration.isolated else { return }
        guard !busy, !paused, !testing else { return }
        busy = true
        nativeSoundTypes.removeAll()
        refreshMenu()
        pollTask = Task {
            defer { busy = false; refreshMenu(); updatePermission() }
            let session = PollingSession(store: store, paused: { self.paused }, prepareDelivery: {
                self.apply(await NotificationSettingsSnapshot.current())
            }, playSound: { await self.playSound(event: $0, repository: $1) }, post: {
                await self.post(event: $0.event, repository: $0.repository, id: $0.id, subtitle: $0.subtitle,
                                body: $0.body, url: $0.url, issueOpened: $0.issueOpened, opened: $0.opened, committed: $0.committed)
            })
            session.login = login
            session.recentIssues = history.issues
            session.recent = history.merged; session.recentOpened = history.opened; session.recentCommits = history.commits
            session.recentComments = history.comments
            session.lastCheck = lastCheck
            await session.run()
            login = session.login
            history = ActivityHistory(opened: session.recentOpened, merged: session.recent, issues: session.recentIssues,
                                      commits: session.recentCommits, comments: session.recentComments)
            lastCheck = session.lastCheck; monitorError = session.monitorError
        }
    }

    @discardableResult
    func playSound(event: NotificationEvent? = nil, repository: String = "", soundEvent: NotificationEvent = .merged) async -> Bool {
        func eligible() -> Bool {
            event.map { preferences.allows($0, repository: repository) } ?? true
        }
        guard eligible(), usesPeonToasts, notificationState == .ready, soundEnabled, systemSoundAllowed, !paused || testing else { return false }
        let remaining = soundEndsAt.timeIntervalSince(configuration.now())
        if remaining > 0 { await configuration.wait(remaining) }
        guard eligible(), !Task.isCancelled, usesPeonToasts, notificationState == .ready, soundEnabled, systemSoundAllowed, !paused || testing else { return false }
        let file = preferences.soundPack.fileURL(for: event ?? soundEvent)
        if let output = configuration.soundOutput { return output(file) }
        guard let clip = NSSound(contentsOf: file, byReference: false) else {
            soundWarning = "The celebration sound is missing. Reinstall the app to restore it."
            return false
        }
        sound = clip
        if clip.play() {
            soundWarning = nil
            soundEndsAt = Date().addingTimeInterval(clip.duration)
            return true
        } else {
            soundWarning = "The celebration sound could not start. Check your audio output device, then try the sound test again."
            return false
        }
    }

    func post(event: NotificationEvent? = nil, repository: String = "", id: String, subtitle: String, body: String, url: String, issueOpened: Bool = false, opened: Bool = false, committed: Bool = false, commented: Bool = false) async {
        guard !Task.isCancelled, notificationState.canPost else { return }
        if let event {
            guard !paused, preferences.allows(event, repository: repository) else { return }
        }
        if let output = configuration.output { output(id); return }
        let soundEvent: NotificationEvent = event ?? (commented ? .commented : issueOpened ? .issueOpened : committed ? .committed : opened ? .opened : .merged)
        let content = UNMutableNotificationContent()
        content.title = soundEvent == .commented ? "Get ’em!" : issueOpened ? "Something need doing?" : committed ? "Hmmm?" : opened ? "Work Work! ⚒" : "Job’s done! ⚒"
        content.subtitle = subtitle
        content.body = body
        content.categoryIdentifier = soundEvent == .commented ? "COMMENT_PR" : issueOpened ? "OPENED_ISSUE" : committed ? "COMMIT_PR" : opened ? "OPENED_PR" : "MERGED_PR"
        content.userInfo = ["url": url]
        if usesPeonToasts {
            content.interruptionLevel = .passive
            if notificationState == .ready {
                let preview = ToastPreview(subtitle: subtitle, body: body, previewsEnabled: toastPreviewsEnabled)
                peonToasts.show(id: id, title: content.title, subtitle: preview.subtitle, body: preview.body, duration: preferences.notificationDuration, issueOpened: issueOpened) { [weak self] in self?.open(url) }
            }
        }
        if !usesPeonToasts && soundEnabled && systemSoundAllowed && nativeSoundTypes.insert(soundEvent.rawValue).inserted {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: preferences.soundPack.notificationSoundName(for: soundEvent)))
        }
        let portrait = try? NotificationPortrait.attachment()
        if let portrait { content.attachments = [portrait.0] }
        defer { if let portrait { try? FileManager.default.removeItem(at: portrait.1) } }
        do {
            let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
            if let output = configuration.notificationOutput { try await output(request) }
            else { try await UNUserNotificationCenter.current().add(request) }
            deliveryWarning = nil
        } catch { deliveryWarning = "macOS could not accept the notification. Review Notification Settings and try the test again." }
    }

    @objc private func test() { runTest(opened: false) }

    @objc private func runTest(_ sender: NSMenuItem) {
        switch sender.representedObject as? ActivityKind {
        case .opened: runTest(opened: true)
        case .issue: runTest(opened: false, issueOpened: true)
        case .commit: runTest(opened: false, committed: true)
        case .comment: runTest(opened: false, commented: true)
        case .merged, nil: runTest(opened: false)
        }
    }

    private func runTest(opened: Bool, committed: Bool = false, issueOpened: Bool = false, commented: Bool = false) {
        guard !configuration.isolated else { return }
        guard !testing else { return }
        guard !busy else {
            alert("GitHub check in progress", "Please use the test again after the current check finishes.")
            return
        }
        testing = true
        nativeSoundTypes.removeAll()
        refreshMenu()
        Task {
            defer { testing = false; refreshMenu() }
            apply(await NotificationSettingsSnapshot.current())
            await playSound(soundEvent: commented ? .commented : issueOpened ? .issueOpened : committed ? .committed : opened ? .opened : .merged)
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
            await post(id: "jobsdone-test-current", subtitle: commented ? "Sample comment by another author" : issueOpened ? "Sample opened issue notification" : committed ? "Sample commit by another author" : opened ? "Sample opened PR notification" : "Sample merge notification", body: "Job’s Done \(version) test — click to open GitHub.", url: issueOpened ? "https://github.com/issues" : "https://github.com/pulls", issueOpened: issueOpened, opened: opened, committed: committed, commented: commented)
            if notificationState != .ready {
                let focusNote = usesPeonToasts ? "" : " Focus may also suppress macOS banners."
                alert("Test completed — notifications need setup", "\(notificationState.explanation)\n\nYour GitHub events will still appear in Recent Activity. Select “\(notificationState.actionTitle)” in the Peon menu to enable notifications.\(focusNote)")
            }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let content = notification.request.content
        guard content.interruptionLevel != .passive else { completionHandler([.list]); return }
        var options: UNNotificationPresentationOptions = [.banner, .list]
        if content.sound != nil { options.insert(.sound) }
        completionHandler(options)
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let value = response.notification.request.content.userInfo["url"] as? String
        let dismissed = response.actionIdentifier == UNNotificationDismissActionIdentifier
        if !dismissed, let value { await MainActor.run { self.open(value) } }
    }
}
