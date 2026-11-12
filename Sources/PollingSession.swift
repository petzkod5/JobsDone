import Foundation

@MainActor
struct GitHubResponses {
    var login: @MainActor () async throws -> String
    var merged: @MainActor (String, Date) async throws -> [MergedPR]
    var opened: @MainActor (String, Date) async throws -> [OpenedPR]
    var candidates: @MainActor (String, Date?, Date) async throws -> [CommitPR]
    var commits: @MainActor (CommitPR) async throws -> [PRCommit]

    var commentCandidates: @MainActor (String, Date) async throws -> [CommentCandidate] = { _, _ in [] }
    var comments: @MainActor (CommentCandidate, Date) async throws -> [CommentNotice] = { _, _ in [] }
    var issues: @MainActor (String, Date) async throws -> [OpenedIssue]

    static let live = GitHubResponses(
        login: { try await Task.detached { try GitHub.login() }.value },
        merged: { login, since in try await Task.detached { try GitHub.merged(login: login, since: since) }.value },
        opened: { login, since in try await Task.detached { try GitHub.opened(login: login, since: since) }.value },
        candidates: { login, since, baseline in try await Task.detached { try GitHub.commitCandidates(login: login, since: since, baselineSince: baseline) }.value },
        commits: { pr in try await Task.detached { try GitHub.commits(on: pr) }.value },
        commentCandidates: { login, since in try await Task.detached { try GitHub.commentCandidates(login: login, since: since) }.value },
        comments: { candidate, since in try await Task.detached { try GitHub.comments(on: candidate, since: since) }.value },
        issues: { login, since in try await Task.detached { try GitHub.issues(login: login, since: since) }.value })
}

struct Delivery {
    var event: NotificationEvent
    var repository: String
    var id: String
    var subtitle: String
    var body: String
    var url: String
    var issueOpened = false
    var opened = false
    var committed = false
}

@MainActor
final class PollingSession {
    let github: GitHubResponses
    let store: StateStore
    var now: () -> Date
    var paused: () -> Bool
    var prepareDelivery: () async -> Void
    var playSound: (NotificationEvent, String) async -> Bool
    var post: (Delivery) async -> Void
    var login = ""
    var recent: [MergedPR] = []
    var recentIssues: [OpenedIssue] = []
    var recentOpened: [OpenedPR] = []
    var recentCommits: [CommitNotice] = []
    var recentComments: [CommentNotice] = []
    var lastCheck: Date?
    var monitorError: String?

    init(github: GitHubResponses = .live, store: StateStore, now: @escaping () -> Date = Date.init,
         paused: @escaping () -> Bool, prepareDelivery: @escaping () async -> Void,
         playSound: @escaping (NotificationEvent, String) async -> Bool,
         post: @escaping (Delivery) async -> Void) {
        self.github = github; self.store = store; self.now = now; self.paused = paused
        self.prepareDelivery = prepareDelivery; self.playSound = playSound; self.post = post
    }
    private func result<T>(_ operation: () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await operation()) } catch { return .failure(error) }
    }
    func run() async {
        do {
            let started = now()
            let account = try await github.login()
            guard !paused(), !Task.isCancelled else { return }
            if login != account { recent = []; recentIssues = []; recentOpened = []; recentCommits = []; recentComments = [] }
            login = account
            var state = try store.load(login: account, now: started)
            try store.save(state, login: account)
            recentIssues = state.issues?.recent ?? []
            recent = state.recent
            recentOpened = state.opened?.recent ?? []
            recentCommits = state.commits?.recent ?? []
            recentComments = state.comments?.recent ?? []
            let since = max(state.startedAt, state.lastCheck.addingTimeInterval(-172800))
            let mergeResult = await result { try await self.github.merged(account, since) }
            var openedState = state.opened!
            let openedSince = max(openedState.startedAt, openedState.lastCheck.addingTimeInterval(-172800))
            guard !paused(), !Task.isCancelled else { return }
            let openedResult = await result { try await self.github.opened(account, openedSince) }
            guard !paused(), !Task.isCancelled else { return }
            var issueState = state.issues!
            let issueSince = max(issueState.startedAt, issueState.lastCheck.addingTimeInterval(-172800))
            let issueResult = await result { try await self.github.issues(account, issueSince) }
            guard !paused(), !Task.isCancelled else { return }
            var failures: [String] = []
            let issues = fetched(issueResult, label: "Issue alerts", failures: &failures)
            let prs = fetched(mergeResult, label: "Merge alerts", failures: &failures)
            let openedPRs = fetched(openedResult, label: "Opening alerts", failures: &failures)
            let pendingOpened = openedState.pending(openedPRs)
            let pending = state.pending(prs)
            guard !paused(), !Task.isCancelled else { return }
            await prepareDelivery()
            guard !paused(), !Task.isCancelled else { return }
            guard try await deliverOpened(pendingOpened, result: openedResult, state: &state,
                                          openedState: &openedState, account: account, started: started) else { return }
            guard try await deliverIssues(issueState.pending(issues), result: issueResult, state: &state,
                                          issueState: &issueState, account: account, started: started) else { return }
            guard try await deliverMerged(pending, result: mergeResult, state: &state,
                                          account: account, started: started) else { return }
            guard try await checkCommits(state: &state, account: account, started: started,
                                         failures: &failures) else { return }
            guard try await checkComments(state: &state, account: account, started: started, failures: &failures) else { return }
            lastCheck = now()
            monitorError = failures.isEmpty ? nil : failures.joined(separator: "\n\n")
        } catch { monitorError = error.localizedDescription }
    }

    private func fetched<Value>(_ result: Result<[Value], Error>, label: String, failures: inout [String]) -> [Value] {
        switch result {
        case .success(let values): return values
        case .failure(let error):
            failures.append(label + ": " + error.localizedDescription)
            return []
        }
    }

    private func deliverOpened(_ pending: [OpenedPR], result: Result<[OpenedPR], Error>, state: inout AccountState, openedState: inout OpenedState, account: String, started: Date) async throws -> Bool {
        var playedOpenedSound = false
        for pr in pending {
            guard !paused(), !Task.isCancelled else { return false }
            if !playedOpenedSound { playedOpenedSound = await playSound(.opened, pr.repository.nameWithOwner) }
            guard !paused(), !Task.isCancelled else { return false }
            await post(Delivery(event: .opened, repository: pr.repository.nameWithOwner, id: "opened-" + pr.id, subtitle: "Opened · \(pr.repository.nameWithOwner) #\(pr.number)", body: pr.title, url: pr.url, opened: true))
            openedState.record(pr)
            state.opened = openedState
            try store.save(state, login: account)
            recentOpened = openedState.recent
        }
        if case .success = result { openedState.lastCheck = started }
        state.opened = openedState
        try store.save(state, login: account)
        return true
    }

    private func deliverIssues(_ pending: [OpenedIssue], result: Result<[OpenedIssue], Error>, state: inout AccountState, issueState: inout IssueState, account: String, started: Date) async throws -> Bool {
        var playedSound = false
        for issue in pending {
            guard !paused(), !Task.isCancelled else { return false }
            if !playedSound { playedSound = await playSound(.issueOpened, issue.repository.nameWithOwner) }
            guard !paused(), !Task.isCancelled else { return false }
            await post(Delivery(event: .issueOpened, repository: issue.repository.nameWithOwner, id: "issue-" + issue.id, subtitle: "Issue opened · \(issue.repository.nameWithOwner) #\(issue.number)", body: issue.title, url: issue.url, issueOpened: true))
            issueState.record(issue)
            state.issues = issueState
            try store.save(state, login: account)
            recentIssues = issueState.recent
        }
        if case .success = result { issueState.lastCheck = started }
        state.issues = issueState
        try store.save(state, login: account)
        return true
    }

    private func deliverMerged(_ pending: [MergedPR], result: Result<[MergedPR], Error>, state: inout AccountState, account: String, started: Date) async throws -> Bool {
        guard !paused(), !Task.isCancelled else { return false }
        var playedMergeSound = false
        for pr in pending {
            guard !paused(), !Task.isCancelled else { return false }
            if !playedMergeSound { playedMergeSound = await playSound(.merged, pr.repository.nameWithOwner) }
            guard !paused(), !Task.isCancelled else { return false }
            await post(Delivery(event: .merged, repository: pr.repository.nameWithOwner, id: pr.id, subtitle: "Merged · \(pr.repository.nameWithOwner) #\(pr.number)", body: pr.title, url: pr.url))
            state.record(pr)
            try store.save(state, login: account)
            recent = state.recent
        }
        if case .success = result { state.lastCheck = started }
        try store.save(state, login: account)
        return true
    }

    private func checkComments(state: inout AccountState, account: String, started: Date, failures: inout [String]) async throws -> Bool {
        guard !paused(), !Task.isCancelled else { return false }
        var commentsState = state.comments!
        let since = max(commentsState.startedAt, commentsState.lastCheck.addingTimeInterval(-172800))
        let candidates: [CommentCandidate]
        do { candidates = try await github.commentCandidates(account, since) }
        catch {
            if Task.isCancelled { return false }
            failures.append("Comment alerts: " + error.localizedDescription)
            return true
        }
        guard !paused(), !Task.isCancelled else { return false }
        var playedSound = false
        var failedPRs = 0
        for candidate in candidates where commentsState.needsCheck(candidate) {
            guard !paused(), !Task.isCancelled else { return false }
            let comments: [CommentNotice]
            do { comments = try await github.comments(candidate, since) }
            catch {
                if Task.isCancelled { return false }
                failedPRs += 1
                continue
            }
            guard !paused(), !Task.isCancelled else { return false }
            for notice in commentsState.pending(comments, login: account) {
                guard !paused(), !Task.isCancelled else { return false }
                let repository = notice.pr.repository.nameWithOwner
                if !playedSound { playedSound = await playSound(.commented, repository) }
                guard !paused(), !Task.isCancelled else { return false }
                await post(Delivery(event: .commented, repository: repository, id: "comment-" + notice.id,
                                    subtitle: "New comment · \(repository) #\(notice.pr.number)",
                                    body: "@\(notice.author): \(notice.body)", url: notice.url))
                commentsState.record(notice)
                state.comments = commentsState
                try store.save(state, login: account)
                recentComments = commentsState.recent
            }
            commentsState.snapshot(candidate, at: started)
            state.comments = commentsState
            try store.save(state, login: account)
        }
        guard !paused(), !Task.isCancelled else { return false }
        if failedPRs == 0 { commentsState.lastCheck = started }
        else { failures.append("Comment alerts: \(failedPRs) PR checks failed; other PRs were checked. Failed PRs retry on the next check.") }
        state.comments = commentsState
        try store.save(state, login: account)
        return true
    }

    private func checkCommits(state: inout AccountState, account: String, started: Date, failures: inout [String]) async throws -> Bool {
        do {
            var commitsState = state.commits!
            let commitSince = commitsState.initialized ? commitsState.lastCheck.addingTimeInterval(-172800) : nil
            let baselineSince = commitsState.startedAt
            let candidates = try await github.candidates(account, commitSince, baselineSince)
            guard !paused(), !Task.isCancelled else { return false }
            var playedCommitSound = false
            var commitFailures = 0
            for pr in candidates where commitsState.needsSnapshot(pr) {
                guard !paused(), !Task.isCancelled else { return false }
                let commits: [PRCommit]
                do { commits = try await github.commits(pr) }
                catch { commitFailures += 1; continue }
                guard !paused(), !Task.isCancelled else { return false }
                let notices = commitsState.prepare(commits, on: pr, login: account)
                state.commits = commitsState
                try store.save(state, login: account)
                for notice in notices {
                    guard !paused(), !Task.isCancelled else { return false }
                    if !playedCommitSound { playedCommitSound = await playSound(.committed, pr.repository.nameWithOwner) }
                    guard !paused(), !Task.isCancelled else { return false }
                    let author = notice.commit.author.user!.login
                    await post(Delivery(event: .committed, repository: pr.repository.nameWithOwner, id: "commit-" + notice.id, subtitle: "New commit · \(pr.repository.nameWithOwner) #\(pr.number)", body: "@\(author): \(notice.commit.messageHeadline)", url: pr.url, committed: true))
                    commitsState.record(notice)
                    state.commits = commitsState
                    try store.save(state, login: account)
                    recentCommits = commitsState.recent
                }
                commitsState.snapshot(commits, on: pr)
                state.commits = commitsState
                try store.save(state, login: account)
            }
            guard !paused(), !Task.isCancelled else { return false }
            if commitFailures == 0 {
                commitsState.initialized = true
                commitsState.lastCheck = started
            } else {
                failures.append("Commit alerts: \(commitFailures) PR checks failed; other PRs were checked. Failed PRs retry on the next check.")
            }
            state.commits = commitsState
            try store.save(state, login: account)
        } catch { failures.append("Commit alerts: " + error.localizedDescription) }
        return true
    }
}
