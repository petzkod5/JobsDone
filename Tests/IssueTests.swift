import Foundation
@testable import JobsDone
import Testing
import UserNotifications

final class IssueTests {
    @Test @MainActor func testNativeIssueNotificationAndMute() async {
        var config = AppConfiguration.isolated(directory: FileManager.default.temporaryDirectory)
        var requests: [UNNotificationRequest] = []
        config.notificationOutput = { requests.append($0) }
        let app = AppDelegate(configuration: config)
        app.notificationState = .ready
        app.preferences.nativeNotifications = true
        await app.post(event: .issueOpened, repository: "alice/r", id: "issue-1", subtitle: "Issue opened", body: "Bug", url: "https://github.com/alice/r/issues/1", issueOpened: true)
        expectEqual(requests.count, 1)
        expectEqual(requests[0].content.title, "Something need doing?")
        expectEqual(requests[0].content.categoryIdentifier, "OPENED_ISSUE")
        expectEqual(requests[0].content.userInfo["url"] as? String, "https://github.com/alice/r/issues/1")
        #expect(requests[0].content.sound != nil)
        app.preferences.soundEnabled = false
        await app.post(event: .issueOpened, repository: "alice/r", id: "issue-2", subtitle: "", body: "", url: "", issueOpened: true)
        expectEqual(requests.count, 2)
        #expect(requests[1].content.sound == nil)
    }

    @Test func testOwnedIssueQueryAndPagination() throws {
        var requests: [[String]] = []
        let values = try GitHub.issues(login: "alice", since: Date(timeIntervalSince1970: 0)) { args in
            requests.append(args)
            let second = requests.count == 2
            let node: [String: Any] = ["id": second ? "i2" : "i1", "title": "Issue", "number": 4,
                "url": "https://github.com/alice/repo/issues/4", "createdAt": "2026-11-07T00:00:00Z",
                "repository": ["nameWithOwner": "alice/repo"]]
            return try JSONSerialization.data(withJSONObject: ["data": ["search": ["issueCount": 2,
                "nodes": [node], "pageInfo": ["hasNextPage": !second, "endCursor": "next"]]]])
        }
        expectEqual(values.map(\.id), ["i1", "i2"])
        expectEqual(requests.count, 2)
        #expect(requests[0].contains("q=is:issue user:alice created:>=1970-01-01T00:00:00Z sort:created-asc"))
        let query = requests[0].first { $0.hasPrefix("query=") }!
        #expect(query.contains("... on Issue"))
        #expect(!query.contains("PullRequest"))
        #expect(!query.contains("author:"))
        #expect(requests[1].contains("cursor=next"))
    }

    @Test func testIssueSearchRejectsPartialResultsOverflowAndStuckPagination() {
        for mode in ["errors", "overflow", "cursor"] {
            var requests = 0
            #expect(throws: (any Error).self) {
                _ = try GitHub.issues(login: "alice", since: .distantPast) { _ in
                    requests += 1
                    if mode == "errors" { return Data(#"{"errors":[{"message":"failed"}]}"#.utf8) }
                    return try JSONSerialization.data(withJSONObject: ["data": ["search": [
                        "issueCount": mode == "overflow" ? 1001 : 1, "nodes": [],
                        "pageInfo": ["hasNextPage": true, "endCursor": "same"]]]])
                }
            }
            expectEqual(requests, mode == "cursor" ? 2 : 1)
        }
    }

    @Test func testUpgradeStartsIssueBoundaryWithoutChangingPRHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StateStore(directory: directory), old = Date(timeIntervalSince1970: 100)
        var state = AccountState(startedAt: old, lastCheck: old)
        state.delivered = ["merge"]
        try store.save(state, login: "alice")
        let now = old.addingTimeInterval(100)
        let loaded = try store.load(login: "alice", now: now)
        expectEqual(loaded.delivered, ["merge"])
        expectEqual(loaded.lastCheck, old)
        expectEqual(loaded.issues!.startedAt, now)
        let issue = OpenedIssue(id: "old", title: "Old", url: "", number: 1, createdAt: old, repository: .init(nameWithOwner: "alice/r"))
        expectEqual(loaded.issues!.pending([issue]), [])
        try store.save(loaded, login: "alice")
        expectEqual(try store.load(login: "alice", now: now.addingTimeInterval(100)).issues!.startedAt, now)
    }
}
