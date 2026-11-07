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
    private let repositoryCount = NSTextField(labelWithString: "")
    private let emptyState = NSView()
    private var systemSoundAllowed = true
    private var displayedRepositories: [String]?

    init(preferences: NotificationPreferences) {
        self.preferences = preferences
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 760), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
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
        label.font = .systemFont(ofSize: heading ? 13 : 12, weight: heading ? .semibold : .regular)
        label.textColor = heading ? .labelColor : .secondaryLabelColor
        return label
    }
    private func build() {
        guard let content = window?.contentView else { return }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24)
        ])
        func add(_ view: NSView) {
            stack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        func vertical(_ views: [NSView], spacing: CGFloat) -> NSStackView {
            let group = NSStackView(views: views)
            group.orientation = .vertical
            group.alignment = .leading
            group.spacing = spacing
            return group
        }
        func surface(_ group: NSStackView) -> NSView {
            let box = SettingsSurface()
            let interior = box
            group.translatesAutoresizingMaskIntoConstraints = false
            interior.addSubview(group)
            NSLayoutConstraint.activate([
                group.leadingAnchor.constraint(equalTo: interior.leadingAnchor, constant: 16),
                group.trailingAnchor.constraint(equalTo: interior.trailingAnchor, constant: -16),
                group.topAnchor.constraint(equalTo: interior.topAnchor, constant: 14),
                group.bottomAnchor.constraint(equalTo: interior.bottomAnchor, constant: -14)
            ])
            return box
        }
        func separator() -> NSBox {
            let line = NSBox()
            line.boxType = .separator
            return line
        }
        let title = label("Notifications", heading: true)
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        add(vertical([title, label("For all GitHub accounts on this Mac")], spacing: 4))
        stack.setCustomSpacing(24, after: stack.arrangedSubviews.last!)
        add(label("Your authored PRs", heading: true))
        var eventRows: [NSView] = []
        for (event, title, detail) in [
            (NotificationEvent.opened, "PR opened", "“Work Work” when you open a PR, including drafts."),
            (.merged, "PR merged", "“Job’s done” when your PR merges."),
            (.committed, "Commits by others on your PRs", "“Hmmm?” for other linked GitHub authors, including bots.")
        ] {
            let button = NSButton(checkboxWithTitle: title, target: self, action: #selector(eventChanged(_:)))
            button.font = .systemFont(ofSize: 13)
            button.identifier = NSUserInterfaceItemIdentifier(event.rawValue)
            button.setAccessibilityHelp(detail)
            eventButtons[event] = button
            let detailLabel = label(detail)
            let row = vertical([button, detailLabel], spacing: 3)
            detailLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 20).isActive = true
            eventRows.append(row)
        }
        add(surface(vertical(eventRows, spacing: 12)))
        stack.setCustomSpacing(20, after: stack.arrangedSubviews.last!)
        add(label("Delivery", heading: true))
        style.addItems(withTitles: ["Peon Toast", "macOS Notification"])
        style.setAccessibilityLabel("Notification style")
        style.target = self
        style.action = #selector(styleChanged)
        let styleLabel = label("Notification style")
        styleLabel.font = .systemFont(ofSize: 13)
        styleLabel.textColor = .labelColor
        let styleRow = NSStackView(views: [styleLabel, NSView(), style])
        styleRow.spacing = 12
        style.widthAnchor.constraint(equalToConstant: 210).isActive = true
        soundButton.target = self
        soundButton.action = #selector(soundChanged)
        soundButton.font = .systemFont(ofSize: 13)
        soundStatus.font = .systemFont(ofSize: 12)
        soundStatus.textColor = .secondaryLabelColor
        soundStatus.maximumNumberOfLines = 1
        soundStatus.heightAnchor.constraint(equalToConstant: 16).isActive = true
        let soundRow = vertical([soundButton, soundStatus], spacing: 3)
        soundStatus.leadingAnchor.constraint(equalTo: soundRow.leadingAnchor, constant: 20).isActive = true
        let systemButton = NSButton(title: "macOS Notification Settings…", target: self, action: #selector(systemSettings))
        systemButton.controlSize = .small
        let systemRow = NSStackView(views: [NSView(), systemButton])
        let delivery = vertical([styleRow, separator(), soundRow, systemRow], spacing: 8)
        add(surface(delivery))
        for row in [styleRow, soundRow, systemRow] {
            row.widthAnchor.constraint(equalTo: delivery.widthAnchor).isActive = true
        }
        stack.setCustomSpacing(20, after: stack.arrangedSubviews.last!)
        repositoryCount.font = .systemFont(ofSize: 12)
        repositoryCount.textColor = .secondaryLabelColor
        let repoHeading = NSStackView(views: [label("Ignored repositories", heading: true), NSView(), repositoryCount])
        add(repoHeading)
        add(label("Skip all three events for exact owner/repository matches."))
        repositoryField.placeholderString = "owner/repository"
        repositoryField.setAccessibilityLabel("Repository to ignore, owner slash repository")
        repositoryField.setAccessibilityHelp("Enter an exact owner/repository. No URLs or wildcards. Press Return or Add.")
        repositoryField.target = self
        repositoryField.action = #selector(addRepository)
        let addButton = NSButton(title: "Add", target: self, action: #selector(addRepository))
        addButton.widthAnchor.constraint(equalToConstant: 72).isActive = true
        let input = NSStackView(views: [repositoryField, addButton])
        input.spacing = 8
        repositoryField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        add(input)
        errorLabel.textColor = .systemRed
        errorLabel.font = .systemFont(ofSize: 12)
        errorLabel.maximumNumberOfLines = 1
        errorLabel.setAccessibilityLabel("Repository validation")
        errorLabel.heightAnchor.constraint(equalToConstant: 16).isActive = true
        add(errorLabel)
        stack.setCustomSpacing(6, after: input)
        stack.setCustomSpacing(6, after: errorLabel)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        entries.orientation = .vertical
        entries.alignment = .leading
        entries.spacing = 0
        entries.edgeInsets = NSEdgeInsets(top: 4, left: 12, bottom: 4, right: 12)
        entries.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = entries
        entries.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        let list = SettingsSurface()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let listInterior = list
        listInterior.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: listInterior.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: listInterior.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: listInterior.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: listInterior.bottomAnchor)
        ])
        list.heightAnchor.constraint(equalToConstant: 104).isActive = true
        add(list)
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        list.addSubview(emptyState)
        let emptyTitle = label("No repositories ignored", heading: true)
        let emptyDetail = label("Events from all repositories are included.")
        let emptyCopy = vertical([emptyTitle, emptyDetail], spacing: 5)
        emptyCopy.alignment = .centerX
        emptyCopy.translatesAutoresizingMaskIntoConstraints = false
        emptyState.addSubview(emptyCopy)
        NSLayoutConstraint.activate([
            emptyState.leadingAnchor.constraint(equalTo: list.leadingAnchor),
            emptyState.trailingAnchor.constraint(equalTo: list.trailingAnchor),
            emptyState.topAnchor.constraint(equalTo: list.topAnchor),
            emptyState.bottomAnchor.constraint(equalTo: list.bottomAnchor),
            emptyCopy.centerXAnchor.constraint(equalTo: emptyState.centerXAnchor),
            emptyCopy.centerYAnchor.constraint(equalTo: emptyState.centerYAnchor)
        ])
        stack.setCustomSpacing(18, after: list)
        add(separator())
        add(label("Filtered events stay in history and won’t notify later.\nPaused events catch up when you resume."))
        let saved = label("Changes save immediately.")
        let help = NSButton(title: "About notification tests…", target: self, action: #selector(aboutTests))
        help.bezelStyle = .rounded
        help.controlSize = .small
        add(NSStackView(views: [saved, NSView(), help]))
        content.layoutSubtreeIfNeeded()
        window?.setContentSize(NSSize(width: 600, height: stack.fittingSize.height + 48))
        window?.initialFirstResponder = repositoryField
    }
    @objc private func aboutTests() {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "About notification tests"
        alert.informativeText = "Manual test notifications bypass event filters, ignored repositories and pause. They honor mute and macOS permission."
        alert.addButton(withTitle: "Done")
        alert.beginSheetModal(for: window)
    }
    func refresh(systemSoundAllowed: Bool? = nil) {
        if let systemSoundAllowed { self.systemSoundAllowed = systemSoundAllowed }
        for (event, button) in eventButtons { button.state = preferences.isEnabled(event) ? .on : .off }
        soundButton.state = preferences.soundEnabled ? .on : .off
        soundStatus.stringValue = self.systemSoundAllowed ? "macOS permission and Focus settings also apply." : "Sound is disabled in macOS. Enable it in Notification Settings."
        style.selectItem(at: preferences.nativeNotifications ? 1 : 0)
        let repositories = preferences.ignoredRepositories
        guard displayedRepositories != repositories else { return }
        displayedRepositories = repositories
        for view in entries.arrangedSubviews { entries.removeArrangedSubview(view); view.removeFromSuperview() }
        repositoryCount.stringValue = "\(repositories.count) ignored"
        emptyState.isHidden = !repositories.isEmpty
        for repo in repositories {
            let name = NSTextField(labelWithString: repo)
            name.font = .systemFont(ofSize: 13)
            name.lineBreakMode = .byTruncatingMiddle
            name.toolTip = repo
            name.setAccessibilityLabel(repo)
            name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let remove = NSButton(title: "Remove", target: self, action: #selector(removeRepository(_:)))
            remove.controlSize = .small
            remove.widthAnchor.constraint(equalToConstant: 68).isActive = true
            remove.identifier = NSUserInterfaceItemIdentifier(repo)
            remove.setAccessibilityLabel("Remove \(repo)")
            let row = NSStackView(views: [name, NSView(), remove])
            row.spacing = 8
            row.distribution = .fill
            row.heightAnchor.constraint(equalToConstant: 32).isActive = true
            entries.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: entries.widthAnchor, constant: -24).isActive = true
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
        errorLabel.stringValue = error.map { $0.contains("already ignored") ? "This repository is already ignored." : "Enter owner/repository without a URL or wildcard." } ?? ""
        errorLabel.toolTip = error
        errorLabel.setAccessibilityHelp(error)
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
        errorLabel.toolTip = nil
        errorLabel.setAccessibilityHelp(nil)
        repositoryField.setAccessibilityHelp("Enter an exact owner/repository, then press Return or Add.")
        changed()
        window?.makeFirstResponder(repositoryField)
    }
}

private final class RepositoryEntriesView: NSStackView {
    override var isFlipped: Bool { true }
}

private final class SettingsSurface: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }
}
