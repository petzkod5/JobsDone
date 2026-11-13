import AppKit

/// The kinds of GitHub events saved in menu history, in the order the app announces them.
enum ActivityKind: CaseIterable {
    case opened, merged, issue, commit, comment

    var label: String {
        switch self {
        case .opened: return "Opened"
        case .merged: return "Merged"
        case .issue: return "New issue"
        case .commit: return "Commit"
        case .comment: return "Comment"
        }
    }

    var sectionTitle: String {
        switch self {
        case .opened: return "Opened PRs"
        case .merged: return "Merged PRs"
        case .issue: return "New Issues"
        case .commit: return "Commits by Others"
        case .comment: return "Comments by Others"
        }
    }

    var testTitle: String {
        switch self {
        case .opened: return "Opened PR — “Work Work!”"
        case .merged: return "Merged PR — “Job’s done!”"
        case .issue: return "New Issue — “Something need doing?”"
        case .commit: return "Commit by Others — “Hmmm?”"
        case .comment: return "Comment by Others — “Get ’em!”"
        }
    }

    /// Spoken type for VoiceOver, which reads the row instead of seeing the icon color.
    var spokenLabel: String {
        switch self {
        case .opened: return "Opened pull request"
        case .merged: return "Merged pull request"
        case .issue: return "New issue"
        case .commit: return "Commit"
        case .comment: return "Comment"
        }
    }

    var symbol: String {
        switch self {
        case .opened: return "arrow.triangle.pull"
        case .merged: return "arrow.triangle.merge"
        case .issue: return "smallcircle.filled.circle"
        case .commit: return "chevron.left.forwardslash.chevron.right"
        case .comment: return "text.bubble"
        }
    }

    var tint: NSColor {
        switch self {
        case .opened: return .systemGreen
        case .merged: return .systemPurple
        case .issue: return .systemOrange
        case .commit: return .systemTeal
        case .comment: return .systemBlue
        }
    }
}

struct ActivityEntry: Equatable {
    let kind: ActivityKind
    let id: String
    let title: String
    let actor: String?
    let repository: String
    let number: Int
    let url: String
    let date: Date

    var reference: String { "\(repository) #\(number)" }
}

/// Saved per-account event history shown in the menu.
struct ActivityHistory: Equatable {
    var opened: [OpenedPR] = []
    var merged: [MergedPR] = []
    var issues: [OpenedIssue] = []
    var commits: [CommitNotice] = []
    var comments: [CommentNotice] = []

    var isEmpty: Bool { ActivityKind.allCases.allSatisfy { entries($0).isEmpty } }

    func entries(_ kind: ActivityKind) -> [ActivityEntry] {
        switch kind {
        case .opened:
            return opened.map { ActivityEntry(kind: kind, id: $0.id, title: $0.title, actor: nil,
                                              repository: $0.repository.nameWithOwner, number: $0.number, url: $0.url, date: $0.createdAt) }
        case .merged:
            return merged.map { ActivityEntry(kind: kind, id: $0.id, title: $0.title, actor: nil,
                                              repository: $0.repository.nameWithOwner, number: $0.number, url: $0.url, date: $0.mergedAt) }
        case .issue:
            return issues.map { ActivityEntry(kind: kind, id: $0.id, title: $0.title, actor: nil,
                                              repository: $0.repository.nameWithOwner, number: $0.number, url: $0.url, date: $0.createdAt) }
        case .commit:
            return commits.map { ActivityEntry(kind: kind, id: $0.id, title: $0.commit.messageHeadline,
                                               actor: $0.commit.author.user?.login ?? "unknown author",
                                               repository: $0.pr.repository.nameWithOwner, number: $0.pr.number, url: $0.pr.url,
                                               date: $0.commit.committedDate) }
        case .comment:
            return comments.map { ActivityEntry(kind: kind, id: $0.id, title: $0.body, actor: $0.author,
                                                repository: $0.pr.repository.nameWithOwner, number: $0.pr.number, url: $0.url,
                                                date: $0.createdAt) }
        }
    }

    /// Every saved event, newest first. Ties keep announcement order.
    var timeline: [ActivityEntry] {
        ActivityKind.allCases.flatMap(entries).enumerated()
            .sorted { $0.element.date != $1.element.date ? $0.element.date > $1.element.date : $0.offset < $1.offset }
            .map(\.element)
    }
}

enum ActivityFormat {
    /// Compact age such as “now”, “5m”, “3h”, “2d”, or a short date after a week.
    static func age(of date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(Int(seconds / 60))m"
        case ..<86400: return "\(Int(seconds / 3600))h"
        case ..<604_800: return "\(Int(seconds / 86400))d"
        default:
            let formatter = DateFormatter()
            formatter.setLocalizedDateFormatFromTemplate("MMMd")
            return formatter.string(from: date)
        }
    }

    /// Spoken age for VoiceOver, such as “12 minutes ago”.
    static func spokenAge(of date: Date, now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: min(date, now), relativeTo: now)
    }

    static func interval(_ seconds: TimeInterval) -> String {
        seconds < 60 ? "\(Int(seconds)) sec" : "\(Int(seconds / 60)) min"
    }

    /// Single-line text for the menu; comments and commit messages can contain line breaks.
    static func singleLine(_ value: String) -> String {
        value.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// “Commit by @octocat · owner/repo #12”. Category lists omit the kind they already name.
    /// With `compact`, long actors and repositories shorten so the number and age stay visible.
    static func context(for entry: ActivityEntry, includeKind: Bool = true, compact: Bool = false) -> String {
        let actor = entry.actor.map { compact ? MenuCopy.truncated($0, limit: 16) : $0 }
        let action: String? = switch (actor, includeKind) {
        case let (actor?, true): "\(entry.kind.label) by @\(actor)"
        case let (actor?, false): "@\(actor)"
        case (nil, true): entry.kind.label
        case (nil, false): nil
        }
        let repository = compact ? MenuCopy.truncated(entry.repository, limit: 28) : entry.repository
        return [action, "\(repository) #\(entry.number)"].compactMap { $0 }.joined(separator: " · ")
    }

    static func detail(for entry: ActivityEntry, now: Date, includeKind: Bool = true) -> String {
        "\(context(for: entry, includeKind: includeKind, compact: true)) · \(age(of: entry.date, now: now))"
    }
}

@MainActor
enum MenuStyle {
    static let titleLimit = 48

    static func symbol(_ name: String, tint: NSColor, description: String, size: CGFloat = 13) -> NSImage? {
        let base = NSImage(systemSymbolName: name, accessibilityDescription: description)
        // Two palette colors keep the glyph inside filled circles (check, pause) legible.
        let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: name.hasSuffix(".fill") ? [.white, tint] : [tint]))
        return base?.withSymbolConfiguration(configuration)
    }

    /// The system’s multicolor warning triangle, matching macOS alerts in both appearances.
    static func warning(size: CGFloat = 13) -> NSImage? {
        NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Needs attention")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
                .applying(.preferringMulticolor()))
    }

    /// Monochrome control icon, so every top-level row shares one icon column and one text column.
    static func control(_ name: String, _ description: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: description)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular))
    }

    /// Two lines: a primary title over smaller secondary context.
    static func twoLine(_ primary: String, _ secondary: String) -> NSAttributedString {
        let text = NSMutableAttributedString(string: primary, attributes: [
            .font: NSFont.menuFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor
        ])
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacingBefore = 1
        text.append(NSAttributedString(string: "\n" + secondary, attributes: [
            .font: NSFont.menuFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph
        ]))
        return text
    }

    static func activityItem(_ entry: ActivityEntry, now: Date, includeKind: Bool = true,
                             target: AnyObject, action: Selector) -> NSMenuItem {
        let title = ActivityFormat.singleLine(entry.title)
        let detail = ActivityFormat.detail(for: entry, now: now, includeKind: includeKind)
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        item.attributedTitle = twoLine(MenuCopy.truncated(title, limit: titleLimit), detail)
        item.image = symbol(entry.kind.symbol, tint: entry.kind.tint, description: entry.kind.label)
        item.representedObject = entry.url
        let when = DateFormatter.localizedString(from: entry.date, dateStyle: .medium, timeStyle: .short)
        item.toolTip = "\(title)\n\(ActivityFormat.context(for: entry)) · \(when)"
        let actor = entry.actor.map { " by \($0)" } ?? ""
        item.setAccessibilityLabel("\(entry.kind.spokenLabel)\(actor): \(title). \(entry.repository) number \(entry.number), "
                                   + ActivityFormat.spokenAge(of: entry.date, now: now))
        return item
    }

    static func sectionHeader(_ title: String) -> NSMenuItem {
        if #available(macOS 14.0, *) { return NSMenuItem.sectionHeader(title: title) }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.menuFont(ofSize: 11).bold, .foregroundColor: NSColor.secondaryLabelColor
        ])
        item.isEnabled = false
        return item
    }

    static func setCount(_ count: Int, on item: NSMenuItem, title: String) {
        if #available(macOS 14.0, *) {
            item.title = title
            item.badge = count > 0 ? NSMenuItemBadge(count: count) : nil
        } else {
            item.title = count > 0 ? "\(title) (\(count))" : title
        }
    }
}

/// Non-interactive status header. A view keeps full-contrast text that a disabled menu item would dim.
@MainActor
final class MenuStatusView: NSView {
    private let icon = NSImageView()
    private let headline = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private var iconCenter: NSLayoutConstraint!
    private var textLeading: NSLayoutConstraint!
    /// Native rows sit 8pt further right when any row shows a checkmark; the header follows them.
    private var inset: CGFloat { hasStateColumn ? 48 : 40 }
    var hasStateColumn = true {
        didSet {
            iconCenter.constant = inset - 15
            textLeading.constant = inset
        }
    }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 44))
        autoresizingMask = .width
        headline.font = .menuFont(ofSize: 13).bold
        headline.textColor = .labelColor
        detail.font = .menuFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        let text = NSStackView(views: [headline, detail])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1
        for view in [icon, text] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        iconCenter = icon.centerXAnchor.constraint(equalTo: leadingAnchor, constant: inset - 15)
        textLeading = text.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset)
        NSLayoutConstraint.activate([
            iconCenter,
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            textLeading,
            text.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
            text.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func update(headline: String, detail: String, image: NSImage?) {
        self.headline.stringValue = headline
        self.detail.stringValue = detail
        icon.image = image
        setAccessibilityLabel("\(headline). \(detail)")
        let width = max(self.headline.intrinsicContentSize.width, self.detail.intrinsicContentSize.width) + inset + 14
        setFrameSize(NSSize(width: max(240, width), height: 44))
    }
}

private extension NSFont {
    var bold: NSFont { NSFontManager.shared.convert(self, toHaveTrait: .boldFontMask) }
}
