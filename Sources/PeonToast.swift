import AppKit
import UserNotifications

@MainActor
final class PeonToastPresenter {
    private final class Entry {
        let id: String
        let window: NSPanel
        let duration: TimeInterval
        var timer: Timer?
        init(id: String, window: NSPanel, duration: TimeInterval) {
            self.id = id; self.window = window; self.duration = duration
        }
    }
    private var entries: [Entry] = []
    private var overflowCount = 0
    private let scheduleTimer: (TimeInterval, @escaping () -> Void) -> Timer

    init(scheduleTimer: @escaping (TimeInterval, @escaping () -> Void) -> Timer = { interval, action in
        let timer = Timer(timeInterval: interval, repeats: false) { _ in action() }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }) {
        self.scheduleTimer = scheduleTimer
    }

    func show(id: String, title: String, subtitle: String, body: String, duration: TimeInterval = 8, open: @escaping () -> Void) {
        dismiss(id)
        let panel = ToastPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 136), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Job’s Done — \(subtitle)"
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.setAccessibilityLabel("\(title) \(subtitle). \(body)")
        let card = ToastCard(title: title, subtitle: subtitle, body: body)
        card.onOpen = { [weak self] in open(); self?.dismiss(id) }
        card.onDismiss = { [weak self] in self?.dismiss(id) }
        card.onHover = { [weak self] _ in self?.refreshDismissTimers() }
        panel.contentView = card
        let entry = Entry(id: id, window: panel, duration: duration)
        entries.insert(entry, at: 0)
        while entries.count > 3 { dismiss(entries.last!.id); overflowCount += 1 }
        reposition()
        panel.orderFrontRegardless()
        refreshDismissTimers()
        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested, userInfo: [.announcement: "Job’s Done: a pull request update is ready.", .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }

    func dismissAll() { for id in entries.map(\.id) { dismiss(id) } }

    func dismissKeyToast() -> Bool {
        guard let entry = entries.first(where: { $0.window.isKeyWindow }) else { return false }
        dismiss(entry.id)
        return true
    }

    private var pointerOverToasts: Bool {
        entries.contains { $0.window.frame.contains(NSEvent.mouseLocation) }
    }

    private func refreshDismissTimers() {
        for entry in entries { scheduleDismiss(entry) }
    }

    private func scheduleDismiss(_ entry: Entry) {
        entry.timer?.invalidate()
        guard !pointerOverToasts, !NSWorkspace.shared.isVoiceOverEnabled, !NSWorkspace.shared.isSwitchControlEnabled else { return }
        let id = entry.id
        let timer = scheduleTimer(entry.duration) { [weak self] in
            Task { @MainActor in
                guard !NSWorkspace.shared.isVoiceOverEnabled, !NSWorkspace.shared.isSwitchControlEnabled else { return }
                guard self?.pointerOverToasts != true else { self?.refreshDismissTimers(); return }
                self?.dismiss(id)
            }
        }
        entry.timer = timer
    }

    private func dismiss(_ id: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let entry = entries.remove(at: index)
        entry.timer?.invalidate()
        entry.window.close()
        if entries.isEmpty { overflowCount = 0 }
        reposition()
    }

    private func reposition() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let area = screen.visibleFrame
        for (index, entry) in entries.enumerated() {
            (entry.window.contentView as? ToastCard)?.setOverflowCount(index == entries.count - 1 ? overflowCount : 0)
            entry.window.setFrameOrigin(NSPoint(x: area.maxX - 396, y: area.maxY - 152 - CGFloat(index) * 146))
        }
        refreshDismissTimers()
    }
}

@MainActor
private final class ToastPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class ToastCard: NSVisualEffectView {
    var onOpen: (() -> Void)?
    var onDismiss: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    private var hoverArea: NSTrackingArea?
    private let overflowLabel = ToastLabel(labelWithString: "")

    init(title: String, subtitle: String, body: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 380, height: 136))
        material = .popover
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.masksToBounds = true

        let portrait = ToastPortrait()
        if let path = Bundle.main.path(forResource: "PeonPortrait", ofType: "png") {
            portrait.image = NSImage(contentsOfFile: path)
        }
        portrait.imageScaling = .scaleProportionallyUpOrDown
        portrait.setAccessibilityLabel("Warcraft III Peon")
        portrait.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([portrait.widthAnchor.constraint(equalToConstant: 42), portrait.heightAnchor.constraint(equalToConstant: 42)])
        func label(_ text: String, font: NSFont, color: NSColor = .labelColor, lines: Int = 1) -> NSTextField {
            let field = ToastLabel(wrappingLabelWithString: text)
            field.font = font
            field.textColor = color
            field.maximumNumberOfLines = lines
            field.lineBreakMode = lines > 1 ? .byWordWrapping : .byTruncatingTail
            field.cell?.wraps = lines > 1
            field.cell?.isScrollable = false
            field.preferredMaxLayoutWidth = 266
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            return field
        }
        let labels = NSStackView(views: [label(title, font: .systemFont(ofSize: 13, weight: .semibold)), label(subtitle, font: .systemFont(ofSize: 12, weight: .medium)), label(body, font: .systemFont(ofSize: 12), color: .secondaryLabelColor, lines: 2)])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 3
        labels.translatesAutoresizingMaskIntoConstraints = false
        labels.widthAnchor.constraint(equalToConstant: 266).isActive = true
        let close = ToastButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Dismiss notification")!, target: self, action: #selector(dismissToast))
        close.keyEquivalent = "\u{1b}"
        close.keyEquivalentModifierMask = []
        close.isBordered = false
        close.toolTip = "Dismiss notification"
        close.setAccessibilityLabel("Dismiss notification")
        close.translatesAutoresizingMaskIntoConstraints = false
        close.widthAnchor.constraint(equalToConstant: 24).isActive = true
        close.heightAnchor.constraint(equalToConstant: 24).isActive = true
        let top = NSStackView(views: [portrait, labels, close])
        top.alignment = .top
        top.spacing = 10
        let link = ToastButton(title: "Open Pull Request", target: self, action: #selector(openPR))
        link.keyEquivalent = "\r"
        link.keyEquivalentModifierMask = []
        link.bezelStyle = .rounded
        link.font = .systemFont(ofSize: 12, weight: .medium)
        overflowLabel.font = .systemFont(ofSize: 10)
        overflowLabel.textColor = .secondaryLabelColor
        overflowLabel.isHidden = true
        overflowLabel.setContentHuggingPriority(.required, for: .horizontal)
        let footer = NSStackView(views: [overflowLabel, NSView(), link])
        footer.distribution = .fill
        let stack = NSStackView(views: [top, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14), stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14), stack.topAnchor.constraint(equalTo: topAnchor, constant: 14), stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14), footer.widthAnchor.constraint(equalTo: stack.widthAnchor)])
    }

    func setOverflowCount(_ count: Int) {
        overflowLabel.stringValue = count == 1 ? "+1 more PR update" : "+\(count) more PR updates"
        overflowLabel.toolTip = "Recent links are in the Peon menu; Notification Center keeps the notification history."
        overflowLabel.isHidden = count == 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        return hit is NSButton ? hit : self
    }
    override func mouseDown(with event: NSEvent) { }
    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onOpen?()
    }
    @objc private func openPR() { onOpen?() }
    @objc private func dismissToast() { onDismiss?() }
}

// UserNotifications takes ownership of attachment files; always hand it a disposable copy.
enum NotificationPortrait {
    static func attachment() throws -> (UNNotificationAttachment, URL)? {
        guard let image = Bundle.main.url(forResource: "PeonPortrait", withExtension: "png") else { return nil }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("JobsDone-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let copy = directory.appendingPathComponent("Peon.png")
            try FileManager.default.copyItem(at: image, to: copy)
            let attachment = try UNNotificationAttachment(identifier: "peon", url: copy)
            return (attachment, directory)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}

@MainActor
private final class ToastLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
private final class ToastPortrait: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
private final class ToastButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
