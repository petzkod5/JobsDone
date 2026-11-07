import AppKit

@MainActor
final class NotificationSettingsController: NSWindowController {
    let preferences: NotificationPreferences
    var onChange: (() -> Void)?
    var openSystemSettings: (() -> Void)?
    private var eventButtons: [NotificationEvent: NSButton] = [:]
    private let soundButton = NSButton(checkboxWithTitle: "Play celebration sounds", target: nil, action: nil)
    private let style = NSPopUpButton()
    private let soundStatus = NSTextField(wrappingLabelWithString: "")
    private let repositoryField = NSTextField()
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let entries = RepositoryEntriesView()
    private var systemSoundAllowed = true
    private var displayedRepositories: [String]?

    init(preferences: NotificationPreferences) {
        self.preferences = preferences
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 740), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Job’s Done Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        build()
        refresh()
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present() {
        refresh()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(repositoryField)
        (repositoryField.currentEditor() as? NSTextView)?.allowsUndo = true
    }
    private func label(_ text: String, heading: Bool = false) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: heading ? 15 : 12, weight: heading ? .semibold : .regular)
        label.textColor = heading ? .labelColor : .secondaryLabelColor
        return label
    }
    private func build() {
        guard let content = window?.contentView else { return }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 22)
        ])
        func add(_ view: NSView) {
            stack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        add(label("Changes save immediately. Apply to all GitHub accounts on this Mac."))
        add(label("Your authored PRs", heading: true))
        for (event, title, detail) in [
            (NotificationEvent.opened, "PR opened", "“Work Work” when you create a pull request, including drafts."),
            (.merged, "PR merged", "“Job’s done” when one of your pull requests merges."),
            (.committed, "Commits by others on your PRs", "“Hmmm?” for a commit by another linked GitHub author, including bots.")
        ] {
            let button = NSButton(checkboxWithTitle: title, target: self, action: #selector(eventChanged(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(event.rawValue)
            eventButtons[event] = button
            add(button)
            add(label(detail))
        }
        add(label("Delivery", heading: true))
        soundButton.target = self
        soundButton.action = #selector(soundChanged)
        add(soundButton)
        add(soundStatus)
        style.addItems(withTitles: ["Peon Toast (Real Portrait)", "macOS Notification"])
        style.setAccessibilityLabel("Notification style")
        style.target = self
        style.action = #selector(styleChanged)
        add(style)
        add(NSButton(title: "macOS Notification Settings…", target: self, action: #selector(systemSettings)))
        add(label("Manual test notifications bypass event filters, ignored repositories and pause. They honor mute and macOS permission."))
        add(label("Ignored repositories", heading: true))
        add(label("Exact owner/repository matches for all three events. No wildcards or network lookup."))
        repositoryField.placeholderString = "owner/repository"
        repositoryField.setAccessibilityLabel("Repository to ignore, owner slash repository")
        repositoryField.target = self
        repositoryField.action = #selector(addRepository)
        let addButton = NSButton(title: "Add", target: self, action: #selector(addRepository))
        let input = NSStackView(views: [repositoryField, addButton])
        input.spacing = 8
        repositoryField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        add(input)
        errorLabel.textColor = .systemRed
        errorLabel.font = .systemFont(ofSize: 12)
        errorLabel.setAccessibilityLabel("Repository validation")
        add(errorLabel)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        entries.orientation = .vertical
        entries.alignment = .leading
        entries.spacing = 6
        entries.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        entries.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = entries
        entries.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: 135).isActive = true
        add(scroll)
        add(label("Filtered events stay in history and won’t notify later. Paused events catch up when you resume."))
        content.layoutSubtreeIfNeeded()
        window?.setContentSize(NSSize(width: 620, height: stack.fittingSize.height + 44))
        window?.initialFirstResponder = repositoryField
    }
    func refresh(systemSoundAllowed: Bool? = nil) {
        if let systemSoundAllowed { self.systemSoundAllowed = systemSoundAllowed }
        for (event, button) in eventButtons { button.state = preferences.isEnabled(event) ? .on : .off }
        soundButton.state = preferences.soundEnabled ? .on : .off
        soundStatus.stringValue = self.systemSoundAllowed ? "macOS notification permission, sound and Focus settings also apply." : "Sound is disabled in macOS. Enable it in macOS Notification Settings to hear alerts."
        style.selectItem(at: preferences.nativeNotifications ? 1 : 0)
        let repositories = preferences.ignoredRepositories
        guard displayedRepositories != repositories else { return }
        displayedRepositories = repositories
        for view in entries.arrangedSubviews { entries.removeArrangedSubview(view); view.removeFromSuperview() }
        if repositories.isEmpty {
            entries.addArrangedSubview(label("No repositories ignored."))
        }
        for repo in repositories {
            let name = NSTextField(labelWithString: repo)
            name.lineBreakMode = .byTruncatingMiddle
            name.toolTip = repo
            name.setAccessibilityLabel(repo)
            name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let remove = NSButton(title: "Remove", target: self, action: #selector(removeRepository(_:)))
            remove.identifier = NSUserInterfaceItemIdentifier(repo)
            remove.setAccessibilityLabel("Remove \(repo)")
            let row = NSStackView(views: [name, remove])
            row.spacing = 8
            entries.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: entries.widthAnchor, constant: -16).isActive = true
            name.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }
    }
    private func changed() { refresh(); onChange?() }
    @objc private func eventChanged(_ sender: NSButton) {
        guard let value = sender.identifier?.rawValue, let event = NotificationEvent(rawValue: value) else { return }
        preferences.setEnabled(sender.state == .on, for: event)
        changed()
    }
    @objc private func soundChanged() { preferences.soundEnabled = soundButton.state == .on; changed() }
    @objc private func styleChanged() { preferences.nativeNotifications = style.indexOfSelectedItem == 1; changed() }
    @objc private func systemSettings() { openSystemSettings?() }
    @objc private func addRepository() {
        let error = preferences.addRepository(repositoryField.stringValue)
        errorLabel.stringValue = error ?? ""
        repositoryField.setAccessibilityHelp(error ?? "Enter an exact owner/repository, then press Return or Add.")
        if let error {
            NSAccessibility.post(element: repositoryField, notification: .announcementRequested, userInfo: [.announcement: error, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        } else {
            repositoryField.stringValue = ""
            changed()
        }
        window?.makeFirstResponder(repositoryField)
    }
    @objc private func removeRepository(_ sender: NSButton) {
        guard let repo = sender.identifier?.rawValue else { return }
        preferences.removeRepository(repo)
        errorLabel.stringValue = ""
        repositoryField.setAccessibilityHelp("Enter an exact owner/repository, then press Return or Add.")
        changed()
        window?.makeFirstResponder(repositoryField)
    }
}

private final class RepositoryEntriesView: NSStackView {
    override var isFlipped: Bool { true }
}
