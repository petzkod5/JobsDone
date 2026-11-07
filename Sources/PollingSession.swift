import Foundation

@MainActor
struct GitHubResponses {
    var login: @MainActor () async throws -> String
    var merged: @MainActor (String, Date) async throws -> [MergedPR]
    var opened: @MainActor (String, Date) async throws -> [OpenedPR]
    var candidates: @MainActor (String, Date?, Date) async throws -> [CommitPR]
    var commits: @MainActor (CommitPR) async throws -> [PRCommit]

    static let live = GitHubResponses(
        login: { try await Task.detached { try GitHub.login() }.value },
        merged: { login, since in try await Task.detached { try GitHub.merged(login: login, since: since) }.value },
        opened: { login, since in try await Task.detached { try GitHub.opened(login: login, since: since) }.value },
        candidates: { login, since, baseline in try await Task.detached { try GitHub.commitCandidates(login: login, since: since, baselineSince: baseline) }.value },
        commits: { pr in try await Task.detached { try GitHub.commits(on: pr) }.value })
}

struct Delivery {
    var event: NotificationEvent
    var repository: String
    var id: String
    var subtitle: String
    var body: String
    var url: String
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
    var recentOpened: [OpenedPR] = []
    var recentCommits: [CommitNotice] = []
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
            if login != account { recent = []; recentOpened = []; recentCommits = [] }
            login = account
            var state = try store.load(login: account, now: started)
            try store.save(state, login: account)
            recent = state.recent
            recentOpened = state.opened?.recent ?? []
            recentCommits = state.commits?.recent ?? []
            let since = max(state.startedAt, state.lastCheck.addingTimeInterval(-172800))
            let mergeResult = await result { try await self.github.merged(account, since) }
            var openedState = state.opened!
            let openedSince = max(openedState.startedAt, openedState.lastCheck.addingTimeInterval(-172800))
            guard !paused(), !Task.isCancelled else { return }
            let openedResult = await result { try await self.github.opened(account, openedSince) }
            guard !paused(), !Task.isCancelled else { return }
            var failures: [String] = []
            let prs: [MergedPR]
            switch mergeResult {
            case .success(let values): prs = values
            case .failure(let error): prs = []; failures.append("Merge alerts: " + error.localizedDescription)
            }
            let openedPRs: [OpenedPR]
            switch openedResult {
            case .success(let values): openedPRs = values
            case .failure(let error): openedPRs = []; failures.append("Opening alerts: " + error.localizedDescription)
            }
            let pendingOpened = openedState.pending(openedPRs)
            let pending = state.pending(prs)
            guard !paused(), !Task.isCancelled else { return }
            await prepareDelivery()
            guard !paused(), !Task.isCancelled else { return }
            guard try await deliverOpened(pendingOpened, result: openedResult, state: &state,
                                          openedState: &openedState, account: account, started: started) else { return }
            guard try await deliverMerged(pending, result: mergeResult, state: &state,
                                          account: account, started: started) else { return }
            guard try await checkCommits(state: &state, account: account, started: started,
                                         failures: &failures) else { return }
            lastCheck = now()
            monitorError = failures.isEmpty ? nil : failures.joined(separator: "\n\n")
        } catch { monitorError = error.localizedDescription }
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
