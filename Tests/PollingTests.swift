import Foundation

@testable import JobsDone
import Testing

@MainActor
private final class PollFixture {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var output: [String] = []
    var paused = false
    var account = "alice"
    var app: AppDelegate!
    var session: PollingSession!
    var mergeFailure = false
    var openedFailure = false
    var issueFailure = false
    var includeIssues = false
    var commitFailure = false
    var boundary: ((String) -> Void)?
    var merge: MergedPR { MergedPR(id: "m", title: "Merge", url: "https://github.com/o/r/pull/1", number: 1, mergedAt: start, repository: .init(nameWithOwner: "o/r")) }
    var opened: OpenedPR { OpenedPR(id: "o", title: "Open", url: merge.url, number: 1, createdAt: start, repository: merge.repository) }
    var issue: OpenedIssue { OpenedIssue(id: "i", title: "Something broken", url: "https://github.com/alice/r/issues/4", number: 4, createdAt: start, repository: .init(nameWithOwner: "alice/r")) }
    var pr: CommitPR { CommitPR(id: "c", title: "Commit", url: merge.url, number: 1, createdAt: start, headRefOid: "new", repository: merge.repository) }
    var commit: PRCommit { PRCommit(oid: "new", messageHeadline: "Change", committedDate: start.addingTimeInterval(1), author: .init(user: .init(login: "bob"))) }
    init() throws {
        app = AppDelegate(configuration: .isolated(directory: directory, output: { [weak self] in self?.output.append($0) }))
        app.notificationState = .ready
        let github = GitHubResponses(login: { self.boundary?("login"); return self.account }, merged: { login, since in
            expectEqual(login, self.account); expectEqual(since, self.account == "alice" ? self.start : self.start.addingTimeInterval(10))
            self.boundary?("merged"); if self.mergeFailure { throw MonitorError(message: "merge failed") }; return [self.merge]
        }, opened: { login, since in
            expectEqual(login, self.account); expectEqual(since, self.account == "alice" ? self.start : self.start.addingTimeInterval(10))
            self.boundary?("opened"); if self.openedFailure { throw MonitorError(message: "opened failed") }; return [self.opened]
        }, candidates: { login, since, baseline in
            expectEqual(login, self.account)
            expectEqual(baseline, self.account == "alice" ? self.start : self.start.addingTimeInterval(10))
            expectEqual(since == nil, self.account != "alice")
            self.boundary?("candidates"); return [self.pr] }, commits: { pr in
            expectEqual(pr, self.pr)
            self.boundary?("commits"); if self.commitFailure { throw MonitorError(message: "commits failed") }; return [self.commit]
        }, issues: { login, since in
            expectEqual(login, self.account)
            expectEqual(since, self.account == "alice" ? self.start : self.start.addingTimeInterval(10))
            self.boundary?("issues")
            if self.issueFailure { throw MonitorError(message: "issues failed") }
            return self.includeIssues ? [self.issue, self.issue] : []
        })
        session = PollingSession(github: github, store: StateStore(directory: directory), now: { self.start.addingTimeInterval(10) }, paused: { self.paused }, prepareDelivery: {}, playSound: { _, _, _ in self.boundary?("sound"); return false }, post: { [weak self] event in
            guard let self else { return }
            await self.app.post(event: event.event, repository: event.repository, id: event.id, subtitle: event.subtitle, body: event.body, url: event.url, issueOpened: event.issueOpened, opened: event.opened, committed: event.committed)
        })
        var state = try StateStore(directory: directory).load(login: "alice", now: start)
        state.commits!.initialized = true
        try StateStore(directory: directory).save(state, login: "alice")
    }
    func state(_ account: String = "alice") throws -> AccountState { try StateStore(directory: directory).load(login: account, now: start) }
    func clean() { try? FileManager.default.removeItem(at: directory) }
}

final class PollingTests {
    @Test @MainActor func testIssueDeliveryHistoryDeduplicationAndAccountIsolation() async throws {
        let f = try PollFixture(); defer { f.clean() }
        f.includeIssues = true
        var sounds: [String] = []
        f.session.playSound = { resource, event, repo in
            if event == .issueOpened { sounds.append(resource); expectEqual(repo, "alice/r") }
            return true
        }
        await f.session.run()
        expectEqual(f.output.filter { $0 == "issue-i" }, ["issue-i"])
        expectEqual(sounds, ["SomethingNeedDoing"])
        expectEqual(try f.state().issues!.recent, [f.issue])
        await f.session.run()
        expectEqual(f.output.filter { $0 == "issue-i" }.count, 1)
        f.account = "bob"
        await f.session.run()
        expectEqual(f.session.recentIssues, [])
        expectEqual(try f.state("bob").issues!.delivered, [])
    }

    @Test @MainActor func testIssueFailureRetriesWithoutBlockingPRs() async throws {
        let f = try PollFixture(); defer { f.clean() }
        f.includeIssues = true; f.issueFailure = true
        await f.session.run()
        expectEqual(try f.state().issues!.lastCheck, f.start)
        expectEqual(f.output.count, 3)
        #expect(f.session.monitorError?.contains("Issue alerts") == true)
        f.issueFailure = false
        await f.session.run()
        expectEqual(f.output.count, 4)
        expectEqual(try f.state().issues!.lastCheck, f.start.addingTimeInterval(10))
    }

    @Test @MainActor func testIssueFiltersRecordWithoutReplay() async throws {
        for ignored in [true, false] {
            let f = try PollFixture(); defer { f.clean() }
            f.includeIssues = true
            if ignored { f.app.preferences.addRepository("ALICE/R") }
            else { f.app.preferences.setEnabled(false, for: .issueOpened) }
            await f.session.run()
            #expect(!f.output.contains("issue-i"))
            expectEqual(try f.state().issues!.recent, [f.issue])
            f.app.preferences.removeRepository("alice/r")
            f.app.preferences.setEnabled(true, for: .issueOpened)
            await f.session.run()
            #expect(!f.output.contains("issue-i"))
        }
    }

    @Test @MainActor func testPauseDuringIssueFetchPreservesPending() async throws {
        let f = try PollFixture(); defer { f.clean() }
        f.includeIssues = true
        f.boundary = { if $0 == "issues" { f.paused = true } }
        await f.session.run()
        expectEqual(f.output, [])
        expectEqual(try f.state().issues!.lastCheck, f.start)
        f.paused = false; f.boundary = nil
        await f.session.run()
        #expect(f.output.contains("issue-i"))
    }

    @Test @MainActor func testProductionPostHonorsNotificationReadiness() async throws {
        let f = try PollFixture(); defer { f.clean() }
        for state in [NotificationReadiness.checking, .notDetermined, .denied] {
            f.app.notificationState = state
            await f.app.post(event: .merged, repository: "o/r", id: "blocked", subtitle: "", body: "", url: "")
        }
        expectEqual(f.output, [])
        for state in [NotificationReadiness.quiet, .ready] {
            f.app.notificationState = state
            await f.app.post(event: .merged, repository: "o/r", id: "allowed", subtitle: "", body: "", url: "")
        }
        expectEqual(f.output, ["allowed", "allowed"])
    }
    @Test @MainActor func testSuppressedEventsAreSilentAndRecordedWithoutReplayAfterReload() async throws {
        let f = try PollFixture(); defer { f.clean() }
        for event in NotificationEvent.allCases { f.app.preferences.setEnabled(false, for: event) }
        await f.session.run()
        expectEqual(f.output, [])
        let saved = try f.state()
        expectEqual(saved.recent.map(\.id), ["m"])
        expectEqual(saved.opened!.recent.map(\.id), ["o"])
        expectEqual(saved.commits!.recent.map(\.id), ["c-new"])
        expectEqual(saved.lastCheck, f.start.addingTimeInterval(10))
        for event in NotificationEvent.allCases { f.app.preferences.setEnabled(true, for: event) }
        await f.session.run()
        expectEqual(f.output, [])
    }
    @Test @MainActor func testProductionPostFiltersIgnoredRepositoriesAndDisabledEvents() async throws {
        let f = try PollFixture(); defer { f.clean() }
        f.app.preferences.addRepository("O/R")
        await f.session.run()
        expectEqual(f.output, [])
        expectEqual(try f.state().recent.count, 1)
        f.app.preferences.removeRepository("o/r")
        await f.app.post(event: .merged, repository: "o/r", id: "allowed", subtitle: "", body: "", url: "")
        expectEqual(f.output, ["allowed"])
        f.app.preferences.setEnabled(false, for: .merged)
        await f.app.post(event: .merged, repository: "o/r", id: "disabled", subtitle: "", body: "", url: "")
        expectEqual(f.output, ["allowed"])
    }
    @Test @MainActor func testIndependentFetchFailuresKeepOnlyFailedCheckpoints() async throws {
        for failure in ["merged", "opened", "commits"] {
            let f = try PollFixture(); defer { f.clean() }
            f.mergeFailure = failure == "merged"; f.openedFailure = failure == "opened"; f.commitFailure = failure == "commits"
            await f.session.run()
            let state = try f.state(), advanced = f.start.addingTimeInterval(10)
            expectEqual(state.lastCheck, failure == "merged" ? f.start : advanced)
            expectEqual(state.opened!.lastCheck, failure == "opened" ? f.start : advanced)
            expectEqual(state.commits!.lastCheck, failure == "commits" ? f.start : advanced)
            #expect(f.session.monitorError != nil)
            f.mergeFailure = false; f.openedFailure = false; f.commitFailure = false
            await f.session.run()
            expectEqual(Set(f.output), Set(["m", "opened-o", "commit-c-new"]))
            expectEqual(f.output.count, 3)
        }
    }
    @Test @MainActor func testAccountSwitchLoadsSeparateHistory() async throws {
        let f = try PollFixture(); defer { f.clean() }
        await f.session.run()
        f.account = "bob"
        await f.session.run()
        expectEqual(f.session.login, "bob")
        expectEqual(f.session.recent, []) // bob's setup boundary excludes alice's older event
        expectEqual(try f.state().recent.map(\.id), ["m"])
        expectEqual(try f.state("bob").recent, [])
    }
    @Test @MainActor func testPauseAcrossFetchAndSoundAwaitsDoesNotConsumePendingEvents() async throws {
        for boundary in ["login", "merged", "opened", "candidates", "commits", "sound"] {
            let f = try PollFixture(); defer { f.clean() }
            f.boundary = { if $0 == boundary { f.paused = true } }
            await f.session.run()
            let state = try f.state()
            if ["login", "merged", "opened", "sound"].contains(boundary) {
                expectEqual(f.output, [], boundary)
                expectEqual(state.delivered, [], boundary)
                expectEqual(state.opened!.delivered, [], boundary)
            }
            expectEqual(state.commits!.lastCheck, f.start, boundary)
            f.paused = false; f.boundary = nil
            await f.session.run()
            expectEqual(f.output.count, 3, boundary)
        }
    }
    @Test @MainActor func testPreferenceEditsAcrossSoundAwaitUseLatestPolicyAndStillRecord() async throws {
        let f = try PollFixture(); defer { f.clean() }
        f.boundary = { if $0 == "sound" { f.app.preferences.addRepository("o/r") } }
        await f.session.run()
        expectEqual(f.output, [])
        expectEqual(try f.state().recent.count, 1)
        expectEqual(try f.state().opened!.recent.count, 1)
        expectEqual(try f.state().commits!.recent.count, 1)
    }
    @Test @MainActor func testCancellationAcrossFetchAwaitLeavesCheckpointForRetry() async throws {
        let f = try PollFixture(); defer { f.clean() }
        f.boundary = { if $0 == "opened" { withUnsafeCurrentTask { $0?.cancel() } } }
        await Task { await f.session.run() }.value
        expectEqual(f.output, [])
        expectEqual(try f.state().lastCheck, f.start)
    }
    @Test @MainActor func testDeniedNotificationsStillRecordHistory() async throws {
        let f = try PollFixture(); defer { f.clean() }
        f.app.notificationState = .denied
        await f.session.run()
        expectEqual(f.output, [])
        expectEqual(try f.state().recent.count, 1)
    }
}

final class DeliveryTests {
    @Test @MainActor func testSoundRechecksPreferencesAfterInjectedWait() async {
        for edit in ["disabled", "ignored", "muted", "style", "none"] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            var config = AppConfiguration.isolated(directory: directory)
            let now = Date(timeIntervalSince1970: 1000)
            config.now = { now }
            let prefs = NotificationPreferences(defaults: config.defaults)
            var waits: [Double] = [], output: [String] = []
            config.wait = { seconds in
                waits.append(seconds)
                switch edit {
                case "disabled": prefs.setEnabled(false, for: .merged)
                case "ignored": prefs.addRepository("o/r")
                case "muted": prefs.soundEnabled = false
                case "style": prefs.nativeNotifications = true
                default: break
                }
            }
            config.soundOutput = { output.append($0); return true }
            let app = AppDelegate(configuration: config)
            app.notificationState = .ready
            app.soundEndsAt = now.addingTimeInterval(5)
            let played = await app.playSound(event: .merged, repository: "o/r")
            expectEqual(waits, [5])
            expectEqual(output, edit == "none" ? ["JobsDone"] : [])
            expectEqual(played, edit == "none")
        }
    }
    @Test @MainActor func testCancellationDuringSoundWaitNeverPlays() async {
        var config = AppConfiguration.isolated(directory: FileManager.default.temporaryDirectory)
        var output: [String] = []
        config.wait = { _ in withUnsafeCurrentTask { $0?.cancel() } }
        config.soundOutput = { output.append($0); return true }
        let app = AppDelegate(configuration: config)
        app.notificationState = .ready
        app.soundEndsAt = Date().addingTimeInterval(5)
        let played = await Task { await app.playSound(event: .merged, repository: "o/r") }.value
        expectEqual(output, [])
        expectEqual(played, false)
    }
}
