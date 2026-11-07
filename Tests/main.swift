import Foundation

struct MonitorTests {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    func pr(_ id: String, offset: Double) -> MergedPR {
        MergedPR(id: id, title: "Fix", url: "https://github.com/owner/repo/pull/1", number: 1, mergedAt: start.addingTimeInterval(offset), repository: .init(nameWithOwner: "owner/repo"))
    }
    func testNoHistoricalAlertsAndNoDuplicateDelivery() {
        var state = AccountState(startedAt: start, lastCheck: start)
        let old = pr("old", offset: -1)
        let fresh = pr("new", offset: 2)
        expectEqual(state.pending([old, fresh, fresh]), [fresh])
        state.record(fresh)
        expectEqual(state.pending([old, fresh]), [])
    }
    func testCatchupOrderedAcrossRestartAndAccounts() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StateStore(directory: directory)
        var state = AccountState(startedAt: start, lastCheck: start)
        let delivered = pr("done", offset: 1)
        state.record(delivered)
        try store.save(state, login: "alice")
        let restored = try store.load(login: "alice", now: Date())
        let early = pr("early", offset: 3)
        let late = pr("late", offset: 8)
        expectEqual(restored.pending([late, delivered, early]), [early, late])
        expectEqual(restored.recent, [delivered])
        expect(try store.load(login: "bob", now: Date()).delivered.isEmpty)
    }
    func testCorruptStateFailsInsteadOfResettingCheckpoint() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("broken".utf8).write(to: directory.appendingPathComponent("alice.json"))
        do {
            _ = try StateStore(directory: directory).load(login: "alice", now: Date())
            fatalError("Corrupt state must throw")
        } catch { }
    }
    func testRecentListBoundedWithoutForgettingDeliveredIDs() {
        var state = AccountState(startedAt: start, lastCheck: start)
        for number in 0..<15 { state.record(pr(String(number), offset: Double(number))) }
        expectEqual(state.recent.count, 10)
        expectEqual(state.delivered.count, 15)
        expectEqual(state.pending([pr("0", offset: 0)]), [])
    }
    func openedPR(_ id: String, offset: Double) -> OpenedPR {
        OpenedPR(id: id, title: "New work", url: "https://github.com/owner/repo/pull/1", number: 1, createdAt: start.addingTimeInterval(offset), repository: .init(nameWithOwner: "owner/repo"))
    }

    func testOpenedEventsAreIndependentAndDeduplicated() throws {
        var state = AccountState(startedAt: start, lastCheck: start, opened: OpenedState(startedAt: start, lastCheck: start))
        let first = openedPR("same-pr", offset: 1)
        let later = openedPR("later", offset: 3)
        expectEqual(state.opened!.pending([later, first, first, openedPR("old", offset: -1)]), [first, later])
        state.opened!.record(first)
        expectEqual(state.opened!.pending([first, later]), [later])
        let merge = pr("same-pr", offset: 5)
        expectEqual(state.pending([merge]), [merge])
        state.record(merge)
        expectEqual(state.opened!.recent, [first])
        expectEqual(state.recent, [merge])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StateStore(directory: directory)
        state.opened!.lastCheck = start.addingTimeInterval(10)
        try store.save(state, login: "alice")
        let restored = try store.load(login: "alice", now: start.addingTimeInterval(20))
        expectEqual(restored.opened!.pending([first, later]), [later])
        expectEqual(restored.opened!.lastCheck, start.addingTimeInterval(10))
        expectEqual(restored.opened!.recent, [first])
        expect(try store.load(login: "bob", now: start).opened!.delivered.isEmpty)
        for n in 0..<15 { state.opened!.record(openedPR(String(n), offset: Double(n))) }
        expectEqual(state.opened!.recent.count, 10)
        expectEqual(state.opened!.delivered.count, 16)
    }

    func testLegacyStateStartsOpenedBoundaryAtUpgrade() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StateStore(directory: directory)
        var old = AccountState(startedAt: start, lastCheck: start.addingTimeInterval(4))
        old.record(pr("merged-before-upgrade", offset: 2))
        try store.save(old, login: "alice")
        let upgrade = start.addingTimeInterval(100)
        let migrated = try store.load(login: "alice", now: upgrade)
        expectEqual(migrated.startedAt, old.startedAt)
        expectEqual(migrated.lastCheck, old.lastCheck)
        expectEqual(migrated.delivered, old.delivered)
        expectEqual(migrated.recent, old.recent)
        expectEqual(migrated.opened!.startedAt, upgrade)
        expectEqual(migrated.opened!.pending([openedPR("historical", offset: 99), openedPR("new", offset: 101)]), [openedPR("new", offset: 101)])
        try store.save(migrated, login: "alice")
        let restored = try store.load(login: "alice", now: start.addingTimeInterval(200))
        expectEqual(restored.opened!.startedAt, upgrade)
        let fresh = try store.load(login: "bob", now: upgrade)
        expectEqual(fresh.opened!.startedAt, upgrade)
    }

    func testOpenedSearchIncludesDraftAndSinceClosedPRs() {
        let query = GitHub.searchText(login: "alice", since: start, opened: true)
        expect(query.contains("is:pr author:alice created:>="))
        expect(!query.contains("is:open"))
        expect(!query.contains("is:merged"))
        expect(!query.contains("draft:"))
        expect(GitHub.searchText(login: "alice", since: start, opened: false).contains("is:merged"))
    }

}

func testCommitAlerts() throws {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let pr = CommitPR(id: "PR1", title: "Fix", url: "https://github.com/o/r/pull/1", number: 1, createdAt: now.addingTimeInterval(-100), headRefOid: "old", repository: .init(nameWithOwner: "o/r"))
    func commit(_ id: String, _ author: String?, _ offset: Double = 10) -> PRCommit {
        PRCommit(oid: id, messageHeadline: "Change", committedDate: now.addingTimeInterval(offset), author: .init(user: author.map { .init(login: $0) }))
    }
    let old = commit("old", "bob", -50)
    var state = CommitState(startedAt: now, lastCheck: now)
    expect(state.pending([old], on: pr, login: "alice").isEmpty)
    state.snapshot([old], on: pr)
    state.initialized = true
    expect(!state.needsSnapshot(pr))
    let incoming = commit("new", "bob")
    let cherryPick = commit("cherry", "carol", -1000)
    let batch = [old, commit("own", "ALICE"), commit("unknown", nil), incoming, incoming, cherryPick]
    expectEqual(state.pending(batch, on: pr, login: "alice").map { $0.commit.oid }, ["new", "cherry"])
    for notice in state.pending(batch, on: pr, login: "alice") { state.record(notice) }
    expect(state.pending(batch, on: pr, login: "alice").isEmpty)
    state.snapshot(batch, on: pr)
    // Removing and then restoring a commit through force-push never replays it.
    state.snapshot([old], on: pr)
    expect(state.pending([incoming], on: pr, login: "alice").isEmpty)
    let newPR = CommitPR(id: "PR2", title: pr.title, url: pr.url, number: 2, createdAt: now.addingTimeInterval(5), headRefOid: "new", repository: pr.repository)
    expectEqual(state.pending([old, incoming], on: newPR, login: "alice").map { $0.commit.oid }, ["new"])
    var interrupted = CommitState(startedAt: now, lastCheck: now, initialized: true)
    let queued = interrupted.prepare([old, incoming], on: newPR, login: "alice")
    expectEqual(queued.map { $0.commit.oid }, ["new"])
    // A pause/restart before delivery must not turn historical commits into new alerts.
    expectEqual(interrupted.pending([old, incoming], on: newPR, login: "alice").map { $0.commit.oid }, ["new"])
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = StateStore(directory: directory)
    var account = try store.load(login: "alice", now: now)
    account.commits = state
    try store.save(account, login: "alice")
    let restored = try store.load(login: "alice", now: now.addingTimeInterval(50))
    expect(restored.commits!.pending(batch, on: pr, login: "alice").isEmpty)
    expectEqual(restored.commits!.recent.count, 2)
    expect(!(try store.load(login: "bob", now: now)).commits!.initialized)
    var legacy = account
    legacy.commits = nil
    try store.save(legacy, login: "legacy")
    let upgraded = try store.load(login: "legacy", now: now.addingTimeInterval(100))
    expect(!upgraded.commits!.initialized)
    expectEqual(upgraded.commits!.startedAt, now.addingTimeInterval(100))
    expectEqual(upgraded.recent, legacy.recent)
}

func expectEqual<T: Equatable>(_ a: T, _ b: T) { precondition(a == b, "Expected \(a) to equal \(b)") }
func expect(_ condition: Bool) { precondition(condition) }
let tests = MonitorTests()
tests.testNoHistoricalAlertsAndNoDuplicateDelivery()
try tests.testCatchupOrderedAcrossRestartAndAccounts()
try tests.testCorruptStateFailsInsteadOfResettingCheckpoint()
tests.testRecentListBoundedWithoutForgettingDeliveredIDs()
try tests.testOpenedEventsAreIndependentAndDeduplicated()
try tests.testLegacyStateStartsOpenedBoundaryAtUpgrade()
tests.testOpenedSearchIncludesDraftAndSinceClosedPRs()
try testCommitAlerts()
expect(!NotificationReadiness.denied.canPost)
expect(!NotificationReadiness.notDetermined.canPost)
expect(NotificationReadiness.quiet.canPost)
expect(NotificationReadiness.ready.canPost)
expectEqual(MenuCopy.truncated("A long PR title", limit: 8), "A long …")
expectEqual(MenuCopy.truncated("👨‍👩‍👧‍👦abc", limit: 3), "👨‍👩‍👧‍👦a…")
expectEqual(MenuCopy.truncated("Short", limit: 10), "Short")
let hiddenPreview = ToastPreview(subtitle: "private-repo #123 merged", body: "Secret PR title", previewsEnabled: false)
expectEqual(hiddenPreview.subtitle, "Pull request update")
expectEqual(hiddenPreview.body, "A pull request update is ready.")
let visiblePreview = ToastPreview(subtitle: "repo #123 merged", body: "Fix bug", previewsEnabled: true)
expectEqual(visiblePreview.subtitle, "repo #123 merged")
expectEqual(visiblePreview.body, "Fix bug")
print("Passed 7 monitor scenarios plus commit baseline/author/deduplication/force-push/migration scenarios, notification-readiness, Unicode truncation, and preview-privacy assertions.")
