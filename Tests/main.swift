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
    // PR A completed its baseline before PR B failed. A must keep watching across restart.
    var partialBaseline = CommitState(startedAt: now, lastCheck: now)
    partialBaseline.snapshot([old], on: pr)
    partialBaseline = try JSONDecoder().decode(CommitState.self, from: JSONEncoder().encode(partialBaseline))
    expect(!partialBaseline.initialized)
    expect(!partialBaseline.needsSnapshot(pr))
    let advancedPR = CommitPR(id: pr.id, title: pr.title, url: pr.url, number: pr.number, createdAt: pr.createdAt, headRefOid: incoming.oid, repository: pr.repository)
    var legacyObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(partialBaseline)) as! [String: Any]
    legacyObject.removeValue(forKey: "baselined")
    let legacyBaseline = try JSONDecoder().decode(CommitState.self, from: JSONSerialization.data(withJSONObject: legacyObject))
    expectEqual(legacyBaseline.pending([old, incoming], on: advancedPR, login: "alice").map { $0.commit.oid }, ["new"])
    expect(partialBaseline.needsSnapshot(advancedPR))
    expectEqual(partialBaseline.prepare([old, incoming], on: advancedPR, login: "alice").map { $0.commit.oid }, ["new"])
    partialBaseline.record(CommitNotice(pr: advancedPR, commit: incoming))
    expect(partialBaseline.pending([old, incoming], on: advancedPR, login: "alice").isEmpty)
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

func testCompleteCommitPagination() throws {
    let pr = CommitPR(id: "PR", title: "Many commits", url: "https://github.com/o/r/pull/1", number: 1, createdAt: Date(), headRefOid: "head", repository: .init(nameWithOwner: "o/r"))
    func graph(_ total: Int, head: String = "head", next: Bool = false, cursor: String? = nil, ids: [String] = ["first"]) throws -> Data {
        let nodes: [[String: Any]] = ids.map { ["commit": ["oid": $0, "messageHeadline": "Change", "committedDate": "2026-01-01T00:00:00Z", "author": ["user": ["login": "bob"]]]] }
        return try JSONSerialization.data(withJSONObject: ["data": ["node": ["headRefOid": head, "baseRefOid": "base", "headRepository": ["nameWithOwner": "fork/r"], "commits": ["totalCount": total, "nodes": nodes, "pageInfo": ["hasNextPage": next, "endCursor": cursor as Any? ?? NSNull()]]]]])
    }
    func comparison(_ total: Int, ids: [String]) throws -> Data {
        let commits: [[String: Any]] = ids.map { ["sha": $0, "author": ["login": "bob"], "commit": ["message": "Change\nBody", "committer": ["date": "2026-01-01T00:00:00Z"]]] }
        return try JSONSerialization.data(withJSONObject: ["total_commits": total, "commits": commits])
    }
    var pages: [Int] = []
    var queries = 0
    let complete = try GitHub.commits(on: pr) { args in
        if args.contains("graphql") { queries += 1; return try graph(301) }
        let page = Int(args.last!.components(separatedBy: "page=").last!)!
        pages.append(page)
        let low = (page - 1) * 100
        return try comparison(301, ids: (low..<min(low + 100, 301)).map { "sha-\($0)" })
    }
    expectEqual(complete.count, 301)
    expectEqual(complete.last?.oid, "sha-300")
    expectEqual(complete.last?.messageHeadline, "Change")
    expectEqual(pages, [1, 2, 3, 4])
    expectEqual(queries, 2)
    // A misleading hasNextPage=false still requires the full comparison.
    var fallbackCalled = false
    let short = try GitHub.commits(on: pr) { args in
        if args.contains("graphql") { return try graph(3) }
        fallbackCalled = true
        return try comparison(3, ids: ["a", "b", "c"])
    }
    expect(fallbackCalled)
    expectEqual(short.count, 3)
    func rejected(_ request: ([String]) throws -> Data) {
        do { _ = try GitHub.commits(on: pr, request: request); fatalError("Incomplete snapshot accepted") }
        catch { }
    }
    rejected { args in args.contains("graphql") ? try graph(301) : try comparison(301, ids: []) }
    rejected { args in args.contains("graphql") ? try graph(301) : try comparison(300, ids: ["a"]) }
    rejected { args in args.contains("graphql") ? try graph(3) : try comparison(3, ids: ["a", "a", "b"]) }
    var changedQueries = 0
    rejected { args in
        if args.contains("graphql") { changedQueries += 1; return try graph(3, head: changedQueries == 1 ? "head" : "moved") }
        return try comparison(3, ids: ["a", "b", "c"])
    }
    var normalPages = 0
    let normal = try GitHub.commits(on: pr) { args in
        expect(args.contains("graphql"))
        normalPages += 1
        return normalPages == 1 ? try graph(3, next: true, cursor: "next", ids: ["a", "b"]) : try graph(3, ids: ["c"])
    }
    expectEqual(normal.map(\.oid), ["a", "b", "c"])
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
try testCompleteCommitPagination()
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
print("Passed 7 monitor scenarios plus commit baseline/author/deduplication/force-push/migration, complete-history pagination, notification-readiness, Unicode truncation, and preview-privacy assertions.")
