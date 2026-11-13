import AppKit

@MainActor
final class NotificationSettingsController: NSWindowController {
    let preferences: NotificationPreferences
    var onPollingIntervalChange: (() -> Void)?
    var onChange: (() -> Void)?
    var openSystemSettings: (() -> Void)?
    private var eventSwitches: [NotificationEvent: NSSwitch] = [:]
    private let soundSwitch = NSSwitch()
    private let soundPack = NSPopUpButton()
    private let style = NSPopUpButton()
    private let pollingInterval = NSPopUpButton()
    private let notificationDuration = NSPopUpButton()
    private let durationHelp = FormText.detail("")
    private let soundStatus = FormText.detail("")
    private let repositoryField = NSTextField()
    private let errorLabel = FormText.detail("")
    private let repositoryCount = FormText.detail("")
    private let repositoryGroup = FormGroup()
    private let emptyRepositories = FormRow()
    private lazy var durationRow = FormRow(title: "Duration", detail: durationHelp, control: notificationDuration)
    private lazy var soundPackRow = FormRow(title: "Sound pack", control: soundPack)
    private var repositoryRows: [FormRow] = []
    private let formView = SettingsBackground()
    private var systemSoundAllowed = true
    private var displayedRepositories: [String]?

    init(preferences: NotificationPreferences) {
        self.preferences = preferences
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: Form.width, height: 720), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Job’s Done Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        build()
        refresh()
        fitWindowToContent()
        window.center()
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present() {
        refresh()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Layout

    private func build() {
        guard let window else { return }
        let viewport = NSScrollView(frame: NSRect(x: 0, y: 0, width: Form.width, height: 720))
        viewport.hasVerticalScroller = true
        viewport.autohidesScrollers = true
        viewport.drawsBackground = false
        viewport.documentView = formView
        window.contentView = viewport
        formView.translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        formView.addSubview(stack)
        NSLayoutConstraint.activate([
            formView.widthAnchor.constraint(equalTo: viewport.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: formView.leadingAnchor, constant: Form.margin),
            stack.trailingAnchor.constraint(equalTo: formView.trailingAnchor, constant: -Form.margin),
            stack.topAnchor.constraint(equalTo: formView.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: formView.bottomAnchor, constant: -20)
        ])
        for view in [header(), eventsSection(), alertsSection(), githubSection(), repositoriesSection()] {
            stack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    private func header() -> NSView {
        let subtitle = FormText.detail("These settings apply to every GitHub account on this Mac.")
        subtitle.font = .systemFont(ofSize: 12)
        let row = NSStackView(views: [subtitle])
        row.spacing = 10
        row.alignment = .centerY
        if let path = Bundle.main.path(forResource: "PeonPortrait", ofType: "png"), let image = NSImage(contentsOfFile: path) {
            let portrait = PortraitView(image: image)
            portrait.widthAnchor.constraint(equalToConstant: 28).isActive = true
            portrait.heightAnchor.constraint(equalToConstant: 28).isActive = true
            row.insertArrangedSubview(portrait, at: 0)
        }
        return row
    }

    private func eventsSection() -> NSView {
        let group = FormGroup()
        for (event, title, detail) in [
            (NotificationEvent.opened, "PR opened", "“Work Work” when you open a PR, including drafts."),
            (.merged, "PR merged", "“Job’s done” when your PR merges."),
            (.committed, "Commits by others on your PRs", "“Hmmm?” for commits by other authors, including bots."),
            (.commented, "Comments by others on your PRs", "“Get ’em!” for conversation, inline, and review comments."),
            (.issueOpened, "Issues in your repositories", "“Something need doing?” when anyone opens an issue.")
        ] {
            let toggle = NSSwitch()
            toggle.controlSize = .mini
            toggle.target = self
            toggle.action = #selector(eventChanged(_:))
            toggle.identifier = NSUserInterfaceItemIdentifier(event.rawValue)
            toggle.setAccessibilityLabel(title)
            toggle.setAccessibilityHelp(detail)
            eventSwitches[event] = toggle
            group.add(FormRow(title: title, detail: FormText.detail(detail), control: toggle))
        }
        let note = FormText.footnote("Turned-off events stay in history and won’t notify later.")
        let footer = NSStackView(views: [note, link("About test notifications…", action: #selector(aboutTests))])
        footer.alignment = .firstBaseline
        footer.spacing = 4
        return FormSection(title: "Notify me about", group: group, footer: footer)
    }

    private func alertsSection() -> NSView {
        configure(style, label: "Notification style", titles: ["Peon Toast", "macOS Notification"], action: #selector(styleChanged))
        configure(notificationDuration, label: "Notification duration",
                  titles: NotificationPreferences.notificationDurations.map(Form.duration), action: #selector(durationChanged))
        configure(soundPack, label: "Sound pack", titles: preferences.soundPacks.packs.map(\.name), action: #selector(soundPackChanged))
        soundSwitch.controlSize = .mini
        soundSwitch.target = self
        soundSwitch.action = #selector(soundChanged)
        soundSwitch.identifier = NSUserInterfaceItemIdentifier("sound")
        soundSwitch.setAccessibilityLabel("Play celebration sounds")
        soundStatus.textColor = .systemOrange
        let group = FormGroup()
        group.add(FormRow(title: "Style", control: style))
        group.add(durationRow)
        group.add(FormRow(title: "Play celebration sounds", detail: soundStatus, control: soundSwitch))
        group.add(soundPackRow)
        let note = FormText.footnote("macOS permission and Focus settings also apply.")
        let footer = NSStackView(views: [note, link("macOS Notification Settings…", action: #selector(systemSettings))])
        footer.alignment = .firstBaseline
        footer.spacing = 4
        return FormSection(title: "Alerts", group: group, footer: footer)
    }

    private func githubSection() -> NSView {
        configure(pollingInterval, label: "GitHub polling interval",
                  titles: NotificationPreferences.pollingIntervals.map(Form.duration), action: #selector(pollingChanged))
        let group = FormGroup()
        group.add(FormRow(title: "Check for activity every", control: pollingInterval))
        return FormSection(title: "GitHub", group: group,
                           footer: FormText.footnote("Checks catch up after sleep. Paused events catch up when you resume."))
    }

    private func repositoriesSection() -> NSView {
        repositoryField.placeholderString = "owner/repository"
        repositoryField.bezelStyle = .roundedBezel
        repositoryField.setAccessibilityLabel("Repository to ignore, owner slash repository")
        repositoryField.setAccessibilityHelp("Enter an exact owner/repository. No URLs or wildcards. Press Return or Add.")
        repositoryField.target = self
        repositoryField.action = #selector(addRepository)
        repositoryField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let addButton = NSButton(title: "Add", target: self, action: #selector(addRepository))
        addButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 64).isActive = true
        errorLabel.textColor = .systemRed
        errorLabel.setAccessibilityLabel("Repository validation")
        errorLabel.isHidden = true
        let input = NSStackView(views: [repositoryField, addButton])
        input.spacing = 8
        let entry = NSStackView(views: [input, errorLabel])
        entry.orientation = .vertical
        entry.alignment = .leading
        entry.spacing = 4
        input.widthAnchor.constraint(equalTo: entry.widthAnchor).isActive = true
        repositoryGroup.add(FormRow(content: entry))
        let empty = FormText.detail("No repositories ignored. Events from every repository can notify.")
        emptyRepositories.setContent(empty)
        repositoryGroup.add(emptyRepositories)
        return FormSection(title: "Ignored repositories", accessory: repositoryCount, group: repositoryGroup,
                           footer: FormText.footnote("Events from these repositories stay in history and never notify."))
    }

    private func link(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.isBordered = false
        button.attributedTitle = NSAttributedString(string: title, attributes: [.foregroundColor: NSColor.linkColor, .font: NSFont.systemFont(ofSize: 11)])
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }

    private func configure(_ popup: NSPopUpButton, label: String, titles: [String], action: Selector) {
        popup.addItems(withTitles: titles)
        popup.setAccessibilityLabel(label)
        popup.target = self
        popup.action = action
        popup.controlSize = .regular
        popup.widthAnchor.constraint(equalToConstant: Form.popupWidth).isActive = true
    }

    private func fitWindowToContent() {
        guard let window else { return }
        formView.layoutSubtreeIfNeeded()
        let height = formView.fittingSize.height
        let available = ((window.screen ?? NSScreen.main)?.visibleFrame.height ?? 800) - 60
        let size = NSSize(width: Form.width, height: min(height, available))
        guard window.contentView?.frame.size != size else { return }
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        window.setFrame(frame, display: window.isVisible)
    }

    // MARK: - State

    @objc private func aboutTests() {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "About test notifications"
        alert.informativeText = "Manual test notifications bypass event filters, ignored repositories and pause. They honor mute and macOS permission."
        alert.addButton(withTitle: "Done")
        alert.beginSheetModal(for: window)
    }
    func refresh(systemSoundAllowed: Bool? = nil) {
        if let systemSoundAllowed { self.systemSoundAllowed = systemSoundAllowed }
        for (event, toggle) in eventSwitches { toggle.state = preferences.isEnabled(event) ? .on : .off }
        soundPack.selectItem(at: preferences.soundPacks.packs.firstIndex { $0.id == preferences.soundPack.id } ?? 0)
        soundSwitch.state = preferences.soundEnabled ? .on : .off
        soundStatus.stringValue = "macOS has turned off sound for Job’s Done. Turn it on with the link below."
        soundStatus.isHidden = self.systemSoundAllowed || !preferences.soundEnabled
        soundSwitch.setAccessibilityHelp(soundStatus.isHidden ? "macOS permission and Focus settings also apply." : soundStatus.stringValue)
        soundPack.isEnabled = preferences.soundEnabled
        soundPackRow.isDimmed = !preferences.soundEnabled
        style.selectItem(at: preferences.nativeNotifications ? 1 : 0)
        pollingInterval.selectItem(at: NotificationPreferences.pollingIntervals.firstIndex(of: preferences.pollingInterval)!)
        notificationDuration.selectItem(at: NotificationPreferences.notificationDurations.firstIndex(of: preferences.notificationDuration)!)
        notificationDuration.isEnabled = !preferences.nativeNotifications
        durationRow.isDimmed = preferences.nativeNotifications
        durationHelp.stringValue = preferences.nativeNotifications
            ? "macOS sets the duration of its notifications."
            : "Hover pauses dismissal. Applies to tests too."
        notificationDuration.setAccessibilityHelp(durationHelp.stringValue)
        refreshRepositories()
    }
    private func refreshRepositories() {
        let repositories = preferences.ignoredRepositories
        guard displayedRepositories != repositories else { return }
        displayedRepositories = repositories
        repositoryRows.forEach(repositoryGroup.remove)
        repositoryRows = repositories.map { repo in
            let icon = NSImageView(image: NSImage(systemSymbolName: "eye.slash", accessibilityDescription: nil) ?? NSImage())
            icon.contentTintColor = .secondaryLabelColor
            icon.setAccessibilityElement(false)
            let name = FormText.label(repo, size: 13, weight: .regular)
            name.lineBreakMode = .byTruncatingMiddle
            name.toolTip = repo
            name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let remove = NSButton(title: "Remove", target: self, action: #selector(removeRepository(_:)))
            remove.controlSize = .small
            remove.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            remove.identifier = NSUserInterfaceItemIdentifier(repo)
            remove.setAccessibilityLabel("Remove \(repo)")
            let line = NSStackView(views: [icon, name, NSView(), remove])
            line.alignment = .centerY
            line.spacing = 8
            return FormRow(content: line)
        }
        repositoryRows.forEach(repositoryGroup.add)
        emptyRepositories.isHidden = !repositories.isEmpty
        repositoryCount.stringValue = repositories.isEmpty ? "" : "\(repositories.count) ignored"
        fitWindowToContent()
    }
    private func showRepositoryError(_ message: String?) {
        errorLabel.stringValue = message.map { $0.contains("already ignored") ? "This repository is already ignored." : "Use owner/repository, like acme/app. No URLs or wildcards." } ?? ""
        errorLabel.isHidden = message == nil
        errorLabel.toolTip = message
        errorLabel.setAccessibilityHelp(message)
        repositoryField.setAccessibilityHelp(message ?? "Enter an exact owner/repository, then press Return or Add.")
        fitWindowToContent()
    }
    private func changed() { refresh(); onChange?() }
    @objc private func eventChanged(_ sender: NSSwitch) {
        guard let value = sender.identifier?.rawValue, let event = NotificationEvent(rawValue: value) else { return }
        preferences.setEnabled(sender.state == .on, for: event)
        changed()
    }
    @objc private func pollingChanged() {
        preferences.pollingInterval = NotificationPreferences.pollingIntervals[pollingInterval.indexOfSelectedItem]
        refresh()
        onPollingIntervalChange?()
    }
    @objc private func durationChanged() {
        preferences.notificationDuration = NotificationPreferences.notificationDurations[notificationDuration.indexOfSelectedItem]
        refresh()
    }
    @objc private func soundPackChanged() {
        guard preferences.soundPacks.packs.indices.contains(soundPack.indexOfSelectedItem) else { return }
        preferences.soundPack = preferences.soundPacks.packs[soundPack.indexOfSelectedItem]
        changed()
    }
    @objc private func soundChanged() { preferences.soundEnabled = soundSwitch.state == .on; changed() }
    @objc private func styleChanged() { preferences.nativeNotifications = style.indexOfSelectedItem == 1; changed() }
    @objc private func systemSettings() { openSystemSettings?() }
    @objc private func addRepository() {
        let error = preferences.addRepository(repositoryField.stringValue)
        showRepositoryError(error)
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
        showRepositoryError(nil)
        changed()
        window?.makeFirstResponder(repositoryField)
    }
}

// MARK: - Form building blocks

private enum Form {
    static let width: CGFloat = 560
    static let margin: CGFloat = 24
    static let inset: CGFloat = 14
    static let radius: CGFloat = 10
    static let popupWidth: CGFloat = 180

    static func duration(_ seconds: TimeInterval) -> String {
        let value = Int(seconds)
        guard value >= 60, value % 60 == 0 else { return "\(value) seconds" }
        return value == 60 ? "1 minute" : "\(value / 60) minutes"
    }
}

@MainActor
private enum FormText {
    static func label(_ text: String, size: CGFloat, weight: NSFont.Weight) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = .labelColor
        return label
    }
    static func detail(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }
    static func footnote(_ text: String) -> NSTextField {
        detail(text)
    }
}

/// A titled group: heading, rounded rows, and an optional note underneath.
private final class FormSection: NSStackView {
    init(title: String, accessory: NSView? = nil, group: FormGroup, footer: NSView? = nil) {
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 6
        let heading = FormText.label(title, size: 13, weight: .semibold)
        heading.setAccessibilityRole(.staticText)
        let headingRow = NSStackView(views: [heading, NSView()] + (accessory.map { [$0] } ?? []))
        headingRow.alignment = .firstBaseline
        headingRow.edgeInsets = NSEdgeInsets(top: 0, left: 2, bottom: 0, right: 2)
        var views: [NSView] = [headingRow, group]
        if let footer {
            let padded = NSStackView(views: [footer])
            padded.edgeInsets = NSEdgeInsets(top: 0, left: 2, bottom: 0, right: 2)
            views.append(padded)
        }
        for view in views {
            addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        }
        setCustomSpacing(8, after: group)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(title)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Rounded inset surface that separates visible rows with hairlines.
private final class FormGroup: NSView {
    private let rows = NSStackView()
    init() {
        super.init(frame: .zero)
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 0
        rows.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rows)
        NSLayoutConstraint.activate([
            rows.leadingAnchor.constraint(equalTo: leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: trailingAnchor),
            rows.topAnchor.constraint(equalTo: topAnchor),
            rows.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func add(_ row: FormRow) {
        rows.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        needsLayout = true
    }
    func remove(_ row: FormRow) {
        rows.removeArrangedSubview(row)
        row.removeFromSuperview()
        needsLayout = true
    }
    override func layout() {
        super.layout()
        var first = true
        for case let row as FormRow in rows.arrangedSubviews where !row.isHidden {
            row.showsSeparator = !first
            first = false
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: Form.radius, yRadius: Form.radius)
        NSColor.formSurface.setFill()
        path.fill()
        NSColor.formBorder.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

/// One row: a title with optional detail on the left and a control on the right.
private final class FormRow: NSView {
    var showsSeparator = false { didSet { if oldValue != showsSeparator { needsDisplay = true } } }
    var isDimmed = false { didSet { titleLabel?.textColor = isDimmed ? .tertiaryLabelColor : .labelColor } }
    private var content: NSView?
    private var titleLabel: NSTextField?

    init() { super.init(frame: .zero) }
    convenience init(content: NSView) {
        self.init()
        setContent(content)
    }
    convenience init(title: String, detail: NSTextField? = nil, control: NSView) {
        self.init()
        let titleLabel = FormText.label(title, size: 13, weight: .regular)
        self.titleLabel = titleLabel
        let text = NSStackView(views: [titleLabel] + (detail.map { [$0] } ?? []))
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        text.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        let line = NSStackView(views: [text, control])
        line.alignment = .centerY
        line.distribution = .fill
        line.spacing = 16
        line.heightAnchor.constraint(greaterThanOrEqualToConstant: 24).isActive = true
        setContent(line)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setContent(_ view: NSView) {
        content?.removeFromSuperview()
        content = view
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Form.inset),
            view.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Form.inset),
            view.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            view.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7)
        ])
    }
    override func draw(_ dirtyRect: NSRect) {
        guard showsSeparator else { return }
        let scale = window?.backingScaleFactor ?? 2
        NSColor.separatorColor.setFill()
        let y = isFlipped ? 0 : bounds.maxY - 1 / scale
        NSRect(x: Form.inset, y: y, width: bounds.width - Form.inset * 2, height: 1 / scale).fill()
    }
}

/// Rounded portrait matching the toast artwork.
private final class PortraitView: NSImageView {
    convenience init(image: NSImage) {
        self.init(frame: .zero)
        self.image = image
        imageScaling = .scaleProportionallyUpOrDown
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        setAccessibilityElement(false)
    }
}

private final class SettingsBackground: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
    }
}

private extension NSColor {
    static var formSurface: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 1, alpha: 0.05)
                : NSColor(white: 0, alpha: 0.035)
        }
    }
    static var formBorder: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 1, alpha: 0.08)
                : NSColor(white: 0, alpha: 0.06)
        }
    }
}
