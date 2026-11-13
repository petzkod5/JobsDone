import AppKit
@testable import JobsDone
import Testing

struct ActivityMenuTests {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let repository = MergedPR.Repository(nameWithOwner: "owner/repo")

    func history() -> ActivityHistory {
        let pr = CommitPR(id: "pr", title: "Change", url: "https://github.com/owner/repo/pull/7", number: 7,
                          createdAt: now, headRefOid: nil, repository: repository)
        return ActivityHistory(
            opened: [OpenedPR(id: "o", title: "Opened", url: "https://github.com/owner/repo/pull/9", number: 9,
                              createdAt: now.addingTimeInterval(-300), repository: repository)],
            merged: [MergedPR(id: "m", title: "Merged", url: "https://github.com/owner/repo/pull/8", number: 8,
                              mergedAt: now.addingTimeInterval(-60), repository: repository)],
            issues: [OpenedIssue(id: "i", title: "Issue", url: "https://github.com/owner/repo/issues/3", number: 3,
                                 createdAt: now.addingTimeInterval(-60), repository: repository)],
            commits: [CommitNotice(pr: pr, commit: PRCommit(oid: "abc", messageHeadline: "Commit", committedDate: now.addingTimeInterval(-7200),
                                                            author: .init(user: nil)))],
            comments: [CommentNotice(pr: pr, id: "c", author: "bob", body: "First line\n\n  second line",
                                     url: pr.url + "#issuecomment-1", createdAt: now.addingTimeInterval(-10))])
    }

    @Test func timelineMergesKindsNewestFirstWithStableTies() {
        let timeline = history().timeline
        // Merged and issue share a timestamp; announcement order (merged before issue) breaks the tie.
        expectEqual(timeline.map(\.id), ["c", "m", "i", "o", "pr-abc"])
        expectEqual(timeline.map(\.kind), [.comment, .merged, .issue, .opened, .commit])
        expect(ActivityHistory().isEmpty)
        expect(!history().isEmpty)
    }

    @Test func entriesKeepLinksAndAttribution() {
        let entries = history()
        expectEqual(entries.entries(.comment).first?.url, "https://github.com/owner/repo/pull/7#issuecomment-1")
        expectEqual(entries.entries(.commit).first?.url, "https://github.com/owner/repo/pull/7")
        expectEqual(entries.entries(.commit).first?.actor, "unknown author")
        expectEqual(entries.entries(.issue).first?.reference, "owner/repo #3")
    }

    @Test func compactAgesAndIntervals() {
        expectEqual(ActivityFormat.age(of: now.addingTimeInterval(-20), now: now), "now")
        expectEqual(ActivityFormat.age(of: now.addingTimeInterval(20), now: now), "now")
        expectEqual(ActivityFormat.age(of: now.addingTimeInterval(-300), now: now), "5m")
        expectEqual(ActivityFormat.age(of: now.addingTimeInterval(-7200), now: now), "2h")
        expectEqual(ActivityFormat.age(of: now.addingTimeInterval(-3 * 86400), now: now), "3d")
        expect(!ActivityFormat.age(of: now.addingTimeInterval(-30 * 86400), now: now).hasSuffix("d"))
        expectEqual(ActivityFormat.interval(30), "30 sec")
        expectEqual(ActivityFormat.interval(300), "5 min")
    }

    @Test func detailsNameKindOnlyWhenNeeded() {
        let comment = history().entries(.comment)[0]
        let merged = history().entries(.merged)[0]
        expectEqual(ActivityFormat.detail(for: comment, now: now), "Comment by @bob · owner/repo #7 · now")
        expectEqual(ActivityFormat.detail(for: comment, now: now, includeKind: false), "@bob · owner/repo #7 · now")
        expectEqual(ActivityFormat.detail(for: merged, now: now), "Merged · owner/repo #8 · 1m")
        expectEqual(ActivityFormat.detail(for: merged, now: now, includeKind: false), "owner/repo #8 · 1m")
    }

    @MainActor @Test func activityItemIsTwoLinesAndOpensItsURL() {
        let comment = history().entries(.comment)[0]
        let item = MenuStyle.activityItem(comment, now: now, target: NSObject(), action: #selector(NSObject.description))
        expectEqual(item.representedObject as? String, comment.url)
        expectEqual(item.attributedTitle?.string, "First line second line\nComment by @bob · owner/repo #7 · now")
        expect(item.image != nil)
        let long = ActivityEntry(kind: .merged, id: "x", title: String(repeating: "a", count: 200), actor: nil,
                                 repository: "owner/repo", number: 1, url: "https://github.com/owner/repo/pull/1", date: now)
        let line = MenuStyle.activityItem(long, now: now, target: NSObject(), action: #selector(NSObject.description))
            .attributedTitle!.string.components(separatedBy: "\n")[0]
        expectEqual(line.count, MenuStyle.titleLimit)
        expect(line.hasSuffix("…"))
    }

    @Test func longNamesShortenWithoutLosingNumberOrAge() {
        let entry = ActivityEntry(kind: .comment, id: "x", title: "Hi", actor: "a-very-long-github-username-bot",
                                  repository: "an-organization-name/an-extremely-long-repository-name", number: 4321,
                                  url: "https://github.com/o/r/pull/4321", date: now.addingTimeInterval(-120))
        let detail = ActivityFormat.detail(for: entry, now: now)
        expect(detail.hasSuffix(" #4321 · 2m"))
        expect(detail.contains("@a-very-long-git…"))
        expect(ActivityFormat.context(for: entry).contains(entry.repository))
    }

    @MainActor @Test func activityItemSpeaksTypeAndFullAge() {
        let comment = history().entries(.comment)[0]
        let item = MenuStyle.activityItem(comment, now: now.addingTimeInterval(600), target: NSObject(), action: #selector(NSObject.description))
        let label = item.accessibilityLabel() ?? ""
        expect(label.hasPrefix("Comment by bob: First line second line. owner/repo number 7, "))
        expect(label.contains("minutes"))
    }

    @MainActor @Test func everyKindHasASystemSymbol() {
        for kind in ActivityKind.allCases {
            expect(NSImage(systemSymbolName: kind.symbol, accessibilityDescription: nil) != nil)
        }
    }
}
