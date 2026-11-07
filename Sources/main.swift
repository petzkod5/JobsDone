import AppKit
import UserNotifications
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, NSMenuDelegate, NSUserInterfaceValidations {
    private var item: NSStatusItem!
    private let menu = NSMenu()
    private var timer: Timer?
    private var busy = false
    private var testing = false
    private var menuOpen = false
    private var paused = UserDefaults.standard.bool(forKey: "paused")
    private var soundEnabled: Bool { !UserDefaults.standard.bool(forKey: "muted") }
    private var monitorError: String?
    private var startupError: String?
    private var deliveryWarning: String?
    private var soundWarning: String?
    private var soundEndsAt = Date.distantPast
    private var lastCheck: Date?
    private var notificationState = NotificationReadiness.checking
    private var systemSoundAllowed = true
    private var toastPreviewsEnabled = true
    private var nativeSoundTypes = Set<String>()
    private var login = ""
    private var recent: [MergedPR] = []
    private var recentOpened: [OpenedPR] = []
    private var recentCommits: [CommitNotice] = []
    private let store = StateStore()
    private var sound: NSSound?
    private var statusRow: NSMenuItem?
    private var permissionRow: NSMenuItem?
    private var checkRow: NSMenuItem?
    private var testRow: NSMenuItem?
    private var workTestRow: NSMenuItem?
    private var commitTestRow: NSMenuItem?
    private var soundRow: NSMenuItem?
    private var pollTask: Task<Void, Never>?
    private var helpWindow: NSWindow?
    private var helpTestButton: NSButton?
    private var helpMenuButton: NSButton?
    private let peonToasts = PeonToastPresenter()
    private var usesPeonToasts: Bool { !UserDefaults.standard.bool(forKey: "nativeNotifications") }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "local.JobsDone").count > 1 {
            NSApp.terminate(nil); return
        }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        menu.autoenablesItems = false
        menu.delegate = self
        item.menu = menu
        installApplicationMenu()
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.removeDeliveredNotifications(withIdentifiers: ["jobsdone-test", "jobsdone-test-current"])
        let action = UNNotificationAction(identifier: "OPEN_PR", title: "Open Pull Request", options: .foreground)
        center.setNotificationCategories([UNNotificationCategory(identifier: "COMMIT_PR", actions: [action], intentIdentifiers: []), UNNotificationCategory(identifier: "MERGED_PR", actions: [action], intentIdentifiers: []), UNNotificationCategory(identifier: "OPENED_PR", actions: [action], intentIdentifiers: [])])
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
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
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
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            Task { @MainActor in self?.apply(settings) }
        }
    }

    private func apply(_ settings: UNNotificationSettings) {
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

    private var testTitle: String {
        testing ? "Testing…" : (soundEnabled && systemSoundAllowed ? "Test Sound + Notification" : "Test Notification (Sound Off)")
    }

    private var workTestTitle: String {
        testing ? "Testing…" : (soundEnabled && systemSoundAllowed ? "Test Work Work + Notification" : "Test Opened PR Notification (Sound Off)")
    }

    private var commitTestTitle: String {
        testing ? "Testing…" : (soundEnabled && systemSoundAllowed ? "Test Hmmm? + Notification" : "Test Commit Notification (Sound Off)")
    }

    private var soundTitle: String {
        systemSoundAllowed ? "Play Celebration Sound" : "Play Sound — Disabled in System Settings…"
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

    private func refreshMenu() {
        guard item != nil else { return }
        if SMAppService.mainApp.status == .enabled { startupError = nil }
        updateIcon()
        helpTestButton?.title = testTitle
        helpTestButton?.isEnabled = !busy && !testing
        // Preserve the active native menu and its keyboard selection during background updates.
        if menuOpen {
            statusRow?.title = status
            statusRow?.isEnabled = !busy && monitorError != nil
            statusRow?.toolTip = monitorError
            permissionRow?.title = notificationState.actionTitle
            checkRow?.isEnabled = !busy && !paused && !testing
            checkRow?.title = busy ? "Checking…" : "Check Now"
            testRow?.title = testTitle
            testRow?.isEnabled = !busy && !testing
            workTestRow?.title = workTestTitle
            workTestRow?.isEnabled = !busy && !testing
            commitTestRow?.title = commitTestTitle
            commitTestRow?.isEnabled = !busy && !testing
            soundRow?.title = soundTitle
            soundRow?.state = soundEnabled && systemSoundAllowed ? .on : .off
            return
        }
        menu.removeAllItems()
        @discardableResult func row(_ title: String, _ action: Selector? = nil, key: String = "") -> NSMenuItem {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
            entry.target = self
            menu.addItem(entry)
            return entry
        }
        row("Job’s Done").isEnabled = false
        row(login.isEmpty ? "Your authored GitHub PRs · every minute" : "@\(login) · authored PRs · every minute").isEnabled = false
        statusRow = row(status, #selector(showMonitorError))
        statusRow?.isEnabled = !busy && monitorError != nil
        statusRow?.toolTip = monitorError
        permissionRow = row(notificationState.actionTitle, #selector(notificationSettings))
        if deliveryWarning != nil { row("Notification issue — View Details…", #selector(showDeliveryWarning)) }
        if soundWarning != nil { row("Sound issue — View Details…", #selector(showSoundWarning)) }
        menu.addItem(.separator())
        checkRow = row(busy ? "Checking…" : "Check Now", #selector(checkNow), key: "r")
        checkRow?.isEnabled = !busy && !paused && !testing
        testRow = row(testTitle, #selector(test))
        testRow?.isEnabled = !busy && !testing
        workTestRow = row(workTestTitle, #selector(testWorkWork))
        workTestRow?.isEnabled = !busy && !testing
        commitTestRow = row(commitTestTitle, #selector(testCommit))
        commitTestRow?.isEnabled = !busy && !testing
        soundRow = row(soundTitle, #selector(toggleSound))
        soundRow?.state = soundEnabled && systemSoundAllowed ? .on : .off
        soundRow?.toolTip = "One sound per event type per check, even when several PRs open or merge. macOS notification Sound settings also apply."
        let styles = NSMenu()
        styles.autoenablesItems = false
        for (title, tag) in [("Peon Toast (Real Portrait)", 1), ("macOS Notification", 0)] {
            let choice = NSMenuItem(title: title, action: #selector(chooseNotificationStyle(_:)), keyEquivalent: "")
            choice.target = self
            choice.tag = tag
            choice.state = (tag == 1) == usesPeonToasts ? .on : .off
            styles.addItem(choice)
        }
        row("Notification Style").submenu = styles
        row(paused ? "Resume Monitoring" : "Pause Monitoring", #selector(togglePause))
        let startup = row(startupTitle, #selector(toggleStartup))
        startup.state = SMAppService.mainApp.status == .enabled ? .on : (SMAppService.mainApp.status == .requiresApproval ? .mixed : .off)
        if startupError != nil { row("Login setup needs attention — View Details…", #selector(showStartupError)) }
        menu.addItem(.separator())
        row("Recently Opened").isEnabled = false
        if recentOpened.isEmpty { row("New PRs you create will appear here").isEnabled = false }
        for pr in recentOpened {
            let title = "\(pr.repository.nameWithOwner) #\(pr.number) · \(pr.title)"
            let entry = row(MenuCopy.truncated(title, limit: 68), #selector(openPR(_:)))
            entry.representedObject = pr.url
            entry.toolTip = "\(title)\nOpened \(DateFormatter.localizedString(from: pr.createdAt, dateStyle: .medium, timeStyle: .short))"
        }
        menu.addItem(.separator())
        row("Recent Merges").isEnabled = false
        if recent.isEmpty { row("New merges of your PRs will appear here").isEnabled = false }
        for pr in recent {
            let title = "\(pr.repository.nameWithOwner) #\(pr.number) · \(pr.title)"
            let entry = row(MenuCopy.truncated(title, limit: 68), #selector(openPR(_:)))
            entry.representedObject = pr.url
            entry.toolTip = "\(title)\nMerged \(DateFormatter.localizedString(from: pr.mergedAt, dateStyle: .medium, timeStyle: .short))"
        }
        menu.addItem(.separator())
        row("Recent Commits by Others").isEnabled = false
        if recentCommits.isEmpty { row("New commits by others on your PRs will appear here").isEnabled = false }
        for notice in recentCommits {
            let author = notice.commit.author.user?.login ?? "Unknown author"
            let title = "\(notice.pr.repository.nameWithOwner) #\(notice.pr.number) · @\(author): \(notice.commit.messageHeadline)"
            let entry = row(MenuCopy.truncated(title, limit: 68), #selector(openPR(_:)))
            entry.representedObject = notice.pr.url
            entry.toolTip = "\(title)\n\(notice.commit.oid)"
        }
        menu.addItem(.separator())
        row("About / Setup Help…", #selector(showHelp))
        row("Quit Job’s Done", #selector(quit), key: "q")
    }

    private var startupTitle: String {
        SMAppService.mainApp.status == .requiresApproval ? "Open at Login — Approve in Settings…" : "Open at Login"
    }

    @objc private func checkNow() { check() }
    @objc private func woke() {
        updatePermission()
        timer?.fireDate = Date().addingTimeInterval(12)
    }
    @objc private func activated() { updatePermission(); refreshMenu() }
    @objc private func togglePause() {
        paused.toggle()
        UserDefaults.standard.set(paused, forKey: "paused")
        if paused { sound?.stop(); soundEndsAt = .distantPast; peonToasts.dismissAll() }
        refreshMenu()
        if !paused { check() }
    }
    @objc private func toggleSound() {
        if !systemSoundAllowed { notificationSettings(); return }
        UserDefaults.standard.set(soundEnabled, forKey: "muted")
        if !soundEnabled { sound?.stop(); soundEndsAt = .distantPast }
        refreshMenu()
    }
    @objc private func chooseNotificationStyle(_ sender: NSMenuItem) {
        UserDefaults.standard.set(sender.tag == 0, forKey: "nativeNotifications")
        peonToasts.dismissAll()
        sound?.stop()
        soundEndsAt = .distantPast
        refreshMenu()
    }
    @objc private func quit() { pollTask?.cancel(); sound?.stop(); peonToasts.dismissAll(); NSApp.terminate(nil) }
    @objc private func notificationSettings() {
        if notificationState == .notDetermined {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in
                Task { @MainActor in self?.updatePermission() }
            }
        } else {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
        }
    }
    @objc private func toggleStartup() {
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
    @objc private func showMonitorError() { if let monitorError { alert("Monitoring needs attention", monitorError + "\n\nChecks retry every minute. Use Check Now after correcting the issue. Setup Help explains GitHub sign-in.") } }
    @objc private func showStartupError() { if let startupError { alert("Open at Login needs attention", startupError + "\n\nUse System Settings → General → Login Items to review Job’s Done.") } }
    @objc private func showDeliveryWarning() { if let deliveryWarning { alert("Celebration needs attention", deliveryWarning + "\n\nYour PR events are saved in Recently Opened, Recent Merges, and Recent Commits by Others. They will not replay their sound because a banner failed.") } }
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
        let about = NSMenuItem(title: "About / Setup Help…", action: #selector(showHelp), keyEquivalent: "")
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
        let watching = section("WHAT GETS CELEBRATED", "Your authored PRs: “Work Work” when opened, “Job’s done” when merged, “Hmmm?” for commits by other GitHub authors on your PRs. Checks run every minute and catch up after sleep. Earlier PR events stay silent.")
        let controlsHelp = section("CONTROLS", "Turn off Play Celebration Sound to mute without stopping checks. Pause holds new alerts until you resume. Manage Open at Login in the Peon menu. Keyboard: ⌘⇧M opens the menu from Help; use arrow keys and Return on Recently Opened, Recent Merges, or Recent Commits by Others.")
        let notices = section("NOTIFICATIONS", "Peon toasts show the real portrait and may appear during Focus. Choose macOS Notification in Notification Style for system banners and Focus handling. PR links stay in the menu after a toast closes.")
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
        controls.addArrangedSubview(NSButton(title: "Notification Settings…", target: self, action: #selector(notificationSettings)))
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
        guard !busy, !paused, !testing else { return }
        busy = true
        nativeSoundTypes.removeAll()
        refreshMenu()
        pollTask = Task {
            defer { busy = false; refreshMenu(); updatePermission() }
            do {
                let started = Date()
                let account = try await Task.detached { try GitHub.login() }.value
                if login != account { recent = []; recentOpened = []; recentCommits = [] }
                login = account
                var state = try store.load(login: account, now: started)
                try store.save(state, login: account)
                recent = state.recent
                recentOpened = state.opened?.recent ?? []
                recentCommits = state.commits?.recent ?? []
                let since = max(state.startedAt, state.lastCheck.addingTimeInterval(-172800))
                let mergeResult = await Task.detached { Result { try GitHub.merged(login: account, since: since) } }.value
                var openedState = state.opened!
                let openedSince = max(openedState.startedAt, openedState.lastCheck.addingTimeInterval(-172800))
                let openedResult = await Task.detached { Result { try GitHub.opened(login: account, since: openedSince) } }.value
                var failures: [String] = []
                let prs: [MergedPR]
                switch mergeResult {
                case .success(let values): prs = values
                case .failure(let error): prs = []; failures.append("Merge alerts: " + error.localizedDescription)
                }
                let openedPRs: [OpenedPR]
                switch openedResult {
                case .success(let values): openedPRs = values
                case .failure(let error): openedPRs = []; failures.append("Opening alerts: " + error.localizedDescription)
                }
                let pendingOpened = openedState.pending(openedPRs)
                let pending = state.pending(prs)
                guard !paused, !Task.isCancelled else { return }
                apply(await UNUserNotificationCenter.current().notificationSettings())
                if !pendingOpened.isEmpty { await playSound(resource: "WorkWork") }
                for pr in pendingOpened {
                    guard !paused, !Task.isCancelled else { return }
                    await post(id: "opened-" + pr.id, subtitle: "Opened · \(pr.repository.nameWithOwner) #\(pr.number)", body: pr.title, url: pr.url, opened: true)
                    openedState.record(pr)
                    state.opened = openedState
                    try store.save(state, login: account)
                    recentOpened = openedState.recent
                }
                if case .success = openedResult { openedState.lastCheck = started }
                state.opened = openedState
                try store.save(state, login: account)
                guard !paused, !Task.isCancelled else { return }
                if !pending.isEmpty { await playSound() }
                for pr in pending {
                    guard !paused, !Task.isCancelled else { return }
                    await post(id: pr.id, subtitle: "Merged · \(pr.repository.nameWithOwner) #\(pr.number)", body: pr.title, url: pr.url)
                    state.record(pr)
                    try store.save(state, login: account)
                    recent = state.recent
                }
                if case .success = mergeResult { state.lastCheck = started }
                try store.save(state, login: account)
                do {
                    var commitsState = state.commits!
                    let commitSince = commitsState.initialized ? commitsState.lastCheck.addingTimeInterval(-172800) : nil
                    let baselineSince = commitsState.startedAt
                    let candidates = try await Task.detached { try GitHub.commitCandidates(login: account, since: commitSince, baselineSince: baselineSince) }.value
                    var playedCommitSound = false
                    var commitFailures = 0
                    for pr in candidates where commitsState.needsSnapshot(pr) {
                        guard !paused, !Task.isCancelled else { return }
                        let commits: [PRCommit]
                        do { commits = try await Task.detached { try GitHub.commits(on: pr) }.value }
                        catch { commitFailures += 1; continue }
                        let notices = commitsState.prepare(commits, on: pr, login: account)
                        state.commits = commitsState
                        try store.save(state, login: account)
                        for notice in notices {
                            guard !paused, !Task.isCancelled else { return }
                            if !playedCommitSound { await playSound(resource: "Hmmm"); playedCommitSound = true }
                            guard !paused, !Task.isCancelled else { return }
                            let author = notice.commit.author.user!.login
                            await post(id: "commit-" + notice.id, subtitle: "New commit · \(pr.repository.nameWithOwner) #\(pr.number)", body: "@\(author): \(notice.commit.messageHeadline)", url: pr.url, committed: true)
                            commitsState.record(notice)
                            state.commits = commitsState
                            try store.save(state, login: account)
                            recentCommits = commitsState.recent
                        }
                        commitsState.snapshot(commits, on: pr)
                        state.commits = commitsState
                        try store.save(state, login: account)
                    }
                    guard !paused, !Task.isCancelled else { return }
                    if commitFailures == 0 {
                        commitsState.initialized = true
                        commitsState.lastCheck = started
                    } else {
                        failures.append("Commit alerts: \(commitFailures) PR checks failed; other PRs were checked. Failed PRs retry next minute.")
                    }
                    state.commits = commitsState
                    try store.save(state, login: account)
                } catch { failures.append("Commit alerts: " + error.localizedDescription) }
                lastCheck = Date()
                monitorError = failures.isEmpty ? nil : failures.joined(separator: "\n\n")
            } catch { monitorError = error.localizedDescription }
        }
    }

    private func playSound(resource: String = "JobsDone") async {
        guard usesPeonToasts, notificationState == .ready, soundEnabled, systemSoundAllowed, !paused || testing else { return }
        let remaining = soundEndsAt.timeIntervalSinceNow
        if remaining > 0 { try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }
        guard !Task.isCancelled, usesPeonToasts, notificationState == .ready, soundEnabled, systemSoundAllowed, !paused || testing else { return }
        guard let path = Bundle.main.path(forResource: resource, ofType: "wav"), let clip = NSSound(contentsOfFile: path, byReference: false) else {
            soundWarning = "The celebration sound is missing. Reinstall the app to restore it."
            return
        }
        sound = clip
        if clip.play() {
            soundWarning = nil
            soundEndsAt = Date().addingTimeInterval(clip.duration)
        } else {
            soundWarning = "The celebration sound could not start. Check your audio output device, then try the sound test again."
        }
    }

    private func post(id: String, subtitle: String, body: String, url: String, opened: Bool = false, committed: Bool = false) async {
        guard notificationState.canPost else { return }
        let content = UNMutableNotificationContent()
        content.title = committed ? "Hmmm?" : opened ? "Work Work! ⚒" : "Job’s done! ⚒"
        content.subtitle = subtitle
        content.body = body
        content.categoryIdentifier = committed ? "COMMIT_PR" : opened ? "OPENED_PR" : "MERGED_PR"
        content.userInfo = ["url": url]
        if usesPeonToasts {
            content.interruptionLevel = .passive
            if notificationState == .ready {
                let preview = ToastPreview(subtitle: subtitle, body: body, previewsEnabled: toastPreviewsEnabled)
                peonToasts.show(id: id, title: content.title, subtitle: preview.subtitle, body: preview.body) { [weak self] in self?.open(url) }
            }
        }
        if !usesPeonToasts && soundEnabled && systemSoundAllowed && nativeSoundTypes.insert(committed ? "committed" : opened ? "opened" : "merged").inserted {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: committed ? "Hmmm.wav" : opened ? "WorkWork.wav" : "JobsDone.wav"))
        }
        let portrait = try? NotificationPortrait.attachment()
        if let portrait { content.attachments = [portrait.0] }
        defer { if let portrait { try? FileManager.default.removeItem(at: portrait.1) } }
        do {
            try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
            deliveryWarning = nil
        } catch { deliveryWarning = "macOS could not accept the notification. Review Notification Settings and try the test again." }
    }

    @objc private func test() { runTest(opened: false) }
    @objc private func testWorkWork() { runTest(opened: true) }

    @objc private func testCommit() { runTest(opened: false, committed: true) }

    private func runTest(opened: Bool, committed: Bool = false) {
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
            apply(await UNUserNotificationCenter.current().notificationSettings())
            await playSound(resource: committed ? "Hmmm" : opened ? "WorkWork" : "JobsDone")
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
            await post(id: "jobsdone-test-current", subtitle: committed ? "Sample commit by another author" : opened ? "Sample opened PR notification" : "Sample merge notification", body: "Job’s Done \(version) test — click to open your GitHub pull requests.", url: "https://github.com/pulls", opened: opened, committed: committed)
            if notificationState != .ready {
                let history = committed ? "Recent Commits by Others" : opened ? "Recently Opened" : "Recent Merges"
                let focusNote = usesPeonToasts ? "" : " Focus may also suppress macOS banners."
                alert("Test completed — notifications need setup", "\(notificationState.explanation)\n\nYour PR events will still appear in \(history). Select “\(notificationState.actionTitle)” in the Peon menu to enable notifications.\(focusNote)")
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
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let value = response.notification.request.content.userInfo["url"] as? String
        Task { @MainActor in
            if response.actionIdentifier != UNNotificationDismissActionIdentifier, let value { self.open(value) }
            completionHandler()
        }
    }
}

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

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
