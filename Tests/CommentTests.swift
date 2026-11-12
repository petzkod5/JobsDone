import Foundation
@testable import JobsDone
import Testing
import UserNotifications

@MainActor
private final class CommentPollControl {
    var account = "alice"
    var fail = true
}

struct CommentTests {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    var pr: CommitPR { CommitPR(id: "pr", title: "Change", url: "https://github.com/alice/r/pull/1", number: 1,
                               createdAt: start, headRefOid: "head", repository: .init(nameWithOwner: "alice/r")) }
    func notice(_ id: String = "1", author: String = "bob", offset: Double = 1) -> CommentNotice {
        CommentNotice(pr: pr, id: id, author: author, body: "Looks good", url: pr.url + "#issuecomment-1", createdAt: start.addingTimeInterval(offset))
    }

    @Test func stateFiltersAndMigrates() throws {
        var state = CommentState(startedAt: start, lastCheck: start)
        #expect(state.pending([notice(), notice(), notice("own", author: "ALICE"), notice("old", offset: -1)], login: "alice") == [notice()])
        state.record(notice())
        #expect(state.pending([notice()], login: "alice").isEmpty)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StateStore(directory: root)
        try store.save(AccountState(startedAt: start, lastCheck: start), login: "alice")
        let upgraded = try store.load(login: "alice", now: start.addingTimeInterval(10))
        #expect(upgraded.startedAt == start)
        #expect(upgraded.comments?.startedAt == start.addingTimeInterval(10))
        #expect(upgraded.comments?.pending([notice()], login: "alice").isEmpty == true)
    }

    @Test func productionFetchCoversAllCommentKindsAndPagination() throws {
        var endpoints: [String] = []
        let result = try GitHub.comments(login: "alice", since: start) { args in
            if args.contains("graphql") {
                #expect(args.contains { $0.contains("author:alice updated:>=") })
                return Data("""
                {"data":{"search":{"issueCount":1,"pageInfo":{"hasNextPage":false},"nodes":[{"id":"pr","title":"Change","url":"https://github.com/alice/r/pull/1","number":1,"createdAt":"2023-11-14T22:13:20Z","headRefOid":"head","repository":{"nameWithOwner":"alice/r"}}]}}}
                """.utf8)
            }
            let endpoint = args.last!
            endpoints.append(endpoint)
            let review = endpoint.contains("/reviews?")
            let count = endpoint.contains("/issues/") && endpoint.hasSuffix("page=1") ? 100 : 1
            let entries: [[String: Any]] = (0..<count).map { index in
                ["id": endpoint.hasSuffix("page=2") ? 100 : index, "user": ["login": "bob"], "body": "Comment",
                 "html_url": "https://github.com/alice/r/pull/1#comment-\(index)",
                 review ? "submitted_at" : "created_at": "2023-11-14T22:13:21Z"]
            }
            return try JSONSerialization.data(withJSONObject: entries)
        }
        #expect(result.count == 103)
        #expect(Set(result.map(\.id)).count == 103)
        #expect(endpoints.count == 4)
        #expect(result.contains { $0.id.contains("inline") })
        #expect(result.contains { $0.id.contains("review") })
        #expect(throws: (any Error).self) {
            _ = try GitHub.comments(login: "alice", since: start) { _ in Data("{\"errors\":[{\"message\":\"unavailable\"}]}".utf8) }
        }
    }

    @Test @MainActor func pollingRetriesDeduplicatesPausesAndIsolatesAccounts() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StateStore(directory: root)
        try store.save(try store.load(login: "alice", now: start), login: "alice")
        let control = CommentPollControl()
        var paused = false
        var deliveries: [Delivery] = []
        var sounds: [NotificationEvent] = []
        let github = GitHubResponses(login: { control.account }, merged: { _, _ in [] }, opened: { _, _ in [] },
                                     candidates: { _, _, _ in [] }, commits: { _ in [] }, comments: { _, _ in
            if control.fail { throw MonitorError(message: "offline") }
            return [notice(), notice(), notice("own", author: "ALICE"), notice("old", offset: -1)]
        }, issues: { _, _ in [] })
        let session = PollingSession(github: github, store: store, now: { start.addingTimeInterval(10) },
                                     paused: { paused }, prepareDelivery: {}, playSound: { event, _ in
            sounds.append(event); return true
        }, post: { deliveries.append($0) })
        await session.run()
        #expect(session.monitorError?.contains("Comment alerts") == true)
        #expect(try store.load(login: "alice", now: start).comments?.lastCheck == start)
        control.fail = false
        paused = true
        await session.run()
        #expect(deliveries.isEmpty)
        paused = false
        await session.run()
        await session.run()
        #expect(deliveries.map(\.id) == ["comment-1"])
        #expect(deliveries.first?.url == notice().url)
        #expect(sounds == [.commented])
        #expect(try store.load(login: "alice", now: start).comments?.recent == [notice()])
        control.account = "other"
        await session.run()
        #expect(session.recentComments.isEmpty)
        #expect(deliveries.count == 1)
    }

    @Test @MainActor func preferencesMuteAndNativeContentUseCommentEvent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var config = AppConfiguration.isolated(directory: root)
        defer { for key in config.defaults.dictionaryRepresentation().keys { config.defaults.removeObject(forKey: key) } }
        var requests: [UNNotificationRequest] = []
        config.notificationOutput = { requests.append($0) }
        let app = AppDelegate(configuration: config)
        app.notificationState = .ready
        app.preferences.nativeNotifications = true
        app.preferences.setEnabled(false, for: .commented)
        await app.post(event: .commented, repository: "alice/r", id: "disabled", subtitle: "", body: "", url: "")
        #expect(requests.isEmpty)
        app.preferences.setEnabled(true, for: .commented)
        app.preferences.soundEnabled = false
        await app.post(event: .commented, repository: "alice/r", id: "muted", subtitle: "", body: "", url: notice().url)
        #expect(requests.last?.content.title == "Get ’em!")
        #expect(requests.last?.content.categoryIdentifier == "COMMENT_PR")
        #expect(requests.last?.content.sound == nil)
        _ = app.preferences.addRepository("alice/r")
        await app.post(event: .commented, repository: "alice/r", id: "ignored", subtitle: "", body: "", url: "")
        #expect(requests.count == 1)
    }
}
