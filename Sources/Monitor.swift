import Foundation

struct MergedPR: Codable, Equatable {
    let id: String
    let title: String
    let url: String
    let number: Int
    let mergedAt: Date
    let repository: Repository
    struct Repository: Codable, Equatable { let nameWithOwner: String }
}

struct OpenedPR: Codable, Equatable {
    let id: String
    let title: String
    let url: String
    let number: Int
    let createdAt: Date
    let repository: MergedPR.Repository
}

struct OpenedIssue: Codable, Equatable {
    let id: String
    let title: String
    let url: String
    let number: Int
    let createdAt: Date
    let repository: MergedPR.Repository
}

struct CommitPR: Codable, Equatable {
    let id: String
    let title: String
    let url: String
    let number: Int
    let createdAt: Date
    let headRefOid: String?
    let repository: MergedPR.Repository
}

struct PRCommit: Codable, Equatable {
    let oid: String
    let messageHeadline: String
    let committedDate: Date
    let author: Author
    struct Author: Codable, Equatable {
        let user: User?
        struct User: Codable, Equatable { let login: String }
    }
}

struct CommitNotice: Codable, Equatable {
    let pr: CommitPR
    let commit: PRCommit
    var id: String { pr.id + "-" + commit.oid }
}

struct CommitState: Codable {
    var startedAt: Date
    var lastCheck: Date
    var initialized = false
    var heads: [String: String] = [:]
    var baselined: Set<String>?
    var seen: [String: Set<String>] = [:]
    var recent: [CommitNotice] = []

    func needsSnapshot(_ pr: CommitPR) -> Bool {
        !hasBaseline(pr) || seen[pr.id] == nil || pr.headRefOid == nil || heads[pr.id] != pr.headRefOid
    }

    private func hasBaseline(_ pr: CommitPR) -> Bool {
        baselined?.contains(pr.id) ?? (heads[pr.id] != nil)
    }

    func pending(_ commits: [PRCommit], on pr: CommitPR, login: String) -> [CommitNotice] {
        guard initialized || hasBaseline(pr) else { return [] }
        var known = seen[pr.id] ?? []
        return commits.filter { commit in
            guard known.insert(commit.oid).inserted,
                  let author = commit.author.user?.login,
                  author.caseInsensitiveCompare(login) != .orderedSame else { return false }
            // A newly discovered PR must not celebrate commits made before it existed.
            return seen[pr.id] != nil || commit.committedDate > max(startedAt, pr.createdAt)
        }.map { CommitNotice(pr: pr, commit: $0) }
    }

    mutating func prepare(_ commits: [PRCommit], on pr: CommitPR, login: String) -> [CommitNotice] {
        let notices = pending(commits, on: pr, login: login)
        let waiting = Set(notices.map { $0.commit.oid })
        seen[pr.id, default: []].formUnion(commits.map(\.oid).filter { !waiting.contains($0) })
        return notices
    }

    mutating func record(_ notice: CommitNotice) {
        seen[notice.pr.id, default: []].insert(notice.commit.oid)
        recent.removeAll { $0.id == notice.id }
        recent.insert(notice, at: 0)
        recent = Array(recent.prefix(10))
    }

    mutating func snapshot(_ commits: [PRCommit], on pr: CommitPR) {
        if baselined == nil { baselined = Set(heads.keys) }
        baselined!.insert(pr.id)
        seen[pr.id, default: []].formUnion(commits.map(\.oid))
        heads[pr.id] = pr.headRefOid
    }
}

struct OpenedState: Codable {
    var startedAt: Date
    var lastCheck: Date
    var delivered: Set<String> = []
    var recent: [OpenedPR] = []

    func pending(_ prs: [OpenedPR]) -> [OpenedPR] {
        var seen = delivered
        return prs.sorted { $0.createdAt < $1.createdAt }.filter {
            $0.createdAt >= startedAt && seen.insert($0.id).inserted
        }
    }

    mutating func record(_ pr: OpenedPR) {
        delivered.insert(pr.id)
        recent.removeAll { $0.id == pr.id }
        recent.insert(pr, at: 0)
        recent = Array(recent.prefix(10))
    }
}

struct IssueState: Codable {
    var startedAt: Date
    var lastCheck: Date
    var delivered: Set<String> = []
    var recent: [OpenedIssue] = []

    func pending(_ issues: [OpenedIssue]) -> [OpenedIssue] {
        var seen = delivered
        return issues.sorted { $0.createdAt < $1.createdAt }.filter {
            $0.createdAt >= startedAt && seen.insert($0.id).inserted
        }
    }

    mutating func record(_ issue: OpenedIssue) {
        delivered.insert(issue.id)
        recent.removeAll { $0.id == issue.id }
        recent.insert(issue, at: 0)
        recent = Array(recent.prefix(10))
    }
}

struct AccountState: Codable {
    var startedAt: Date
    var lastCheck: Date
    var delivered: Set<String> = []
    var recent: [MergedPR] = []
    var issues: IssueState?
    var opened: OpenedState?
    var commits: CommitState?
    var comments: CommentState?

    func pending(_ prs: [MergedPR]) -> [MergedPR] {
        var seen = delivered
        return prs.sorted { $0.mergedAt < $1.mergedAt }.filter {
            $0.mergedAt >= startedAt && seen.insert($0.id).inserted
        }
    }

    mutating func record(_ pr: MergedPR) {
        delivered.insert(pr.id)
        recent.removeAll { $0.id == pr.id }
        recent.insert(pr, at: 0)
        recent = Array(recent.prefix(10))
    }
}

struct MonitorError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum GitHub {
    static let query = """
    query($q: String!, $cursor: String) {
      search(query: $q, type: ISSUE, first: 100, after: $cursor) {
        issueCount pageInfo { hasNextPage endCursor }
        nodes { ... on PullRequest { id title url number mergedAt repository { nameWithOwner } } }
      }
    }
    """

    static func run(_ arguments: [String]) throws -> Data {
        let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw MonitorError(message: "Install GitHub CLI, then run gh auth login in Terminal.")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["GH_PROMPT_DISABLED"] = "1"
        environment["GH_HOST"] = "github.com"
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        // stderr can contain private repository details; do not persist it.
        process.standardError = FileHandle.nullDevice
        try process.run()
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 40, execute: timeout)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeout.cancel()
        guard process.terminationStatus == 0 else {
            throw MonitorError(message: "GitHub check failed. Check network, gh auth status, repository access, or API rate limits. Will retry.")
        }
        return data
    }

    static func login() throws -> String {
        let data: Data
        do {
            data = try run(["api", "--hostname", "github.com", "user", "--jq", ".login"])
        } catch {
            if (try? run(["auth", "status", "--hostname", "github.com"])) == nil {
                throw MonitorError(message: "GitHub CLI is missing or not signed in. Install GitHub CLI, then run gh auth login --hostname github.com in Terminal. If already signed in, check your network and run gh auth status.")
            }
            throw error
        }
        let login = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !login.isEmpty else { throw MonitorError(message: "No GitHub account found. Run gh auth login.") }
        return login
    }

    static func merged(login: String, since: Date) throws -> [MergedPR] {
        try search(query: query, search: searchText(login: login, since: since, opened: false))
    }

    static func opened(login: String, since: Date) throws -> [OpenedPR] {
        try search(query: query.replacingOccurrences(of: "mergedAt", with: "createdAt"), search: searchText(login: login, since: since, opened: true))
    }

    static func issues(login: String, since: Date, request: ([String]) throws -> Data = GitHub.run) throws -> [OpenedIssue] {
        let issueQuery = query.replacingOccurrences(of: "PullRequest", with: "Issue")
            .replacingOccurrences(of: "mergedAt", with: "createdAt")
        let date = ISO8601DateFormatter().string(from: since)
        return try search(query: issueQuery, search: "is:issue user:\(login) created:>=\(date) sort:created-asc", request: request)
    }

    static func commitCandidates(login: String, since: Date?, baselineSince: Date? = nil) throws -> [CommitPR] {
        let fields = "id title url number createdAt headRefOid repository { nameWithOwner }"
        let candidateQuery = query.replacingOccurrences(of: "id title url number mergedAt repository { nameWithOwner }", with: fields)
        let scope = since.map { "updated:>=\(ISO8601DateFormatter().string(from: $0))" } ?? "is:open"
        var candidates: [CommitPR] = try search(query: candidateQuery, search: "is:pr author:\(login) \(scope) sort:updated-asc")
        if since == nil, let baselineSince {
            let updated: [CommitPR] = try search(query: candidateQuery, search: "is:pr author:\(login) updated:>=\(ISO8601DateFormatter().string(from: baselineSince)) sort:updated-asc")
            let updatedIDs = Set(updated.map(\.id))
            candidates.removeAll { updatedIDs.contains($0.id) }
            candidates += updated
        }
        return candidates
    }

    static func commits(on pr: CommitPR, request: ([String]) throws -> Data = GitHub.run) throws -> [PRCommit] {
        let query = """
        query($id: ID!, $cursor: String) {
          node(id: $id) { ... on PullRequest {
            headRefOid baseRefOid headRepository { nameWithOwner }
            commits(first: 100, after: $cursor) {
              totalCount pageInfo { hasNextPage endCursor }
              nodes { commit { oid messageHeadline committedDate author { user { login } } } }
            }
          } }
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var cursor: String?
        var visited = Set<String>()
        var result: [PRCommit] = []
        var total: Int?
        repeat {
            var args = ["api", "--hostname", "github.com", "graphql", "-f", "query=\(query)", "-f", "id=\(pr.id)"]
            if let cursor { args += ["-f", "cursor=\(cursor)"] }
            let response = try decoder.decode(CommitResponse.self, from: request(args))
            guard response.errors == nil, let node = response.data?.node,
                  node.headRefOid == pr.headRefOid else {
                throw MonitorError(message: "PR commits changed during the check or GitHub returned an incomplete result. Will retry.")
            }
            guard total == nil || total == node.commits.totalCount else {
                throw MonitorError(message: "PR commit count changed during pagination. Will retry.")
            }
            total = node.commits.totalCount
            result += node.commits.nodes.map(\.commit)
            if node.commits.totalCount > 250 || (!node.commits.pageInfo.hasNextPage && Set(result.map(\.oid)).count != node.commits.totalCount) {
                guard let base = node.baseRefOid, let head = pr.headRefOid, let headRepo = node.headRepository else {
                    throw MonitorError(message: "GitHub returned incomplete PR commits and the full comparison is unavailable. Will retry.")
                }
                let owner = headRepo.nameWithOwner.split(separator: "/")[0]
                let comparison = "repos/\(pr.repository.nameWithOwner)/compare/\(base)...\(owner):\(head)"
                var complete: [PRCommit] = []
                var page = 1
                repeat {
                    let data = try request(["api", "--hostname", "github.com", "\(comparison)?per_page=100&page=\(page)"])
                    let value = try decoder.decode(CompareResponse.self, from: data)
                    guard value.total_commits == node.commits.totalCount, !value.commits.isEmpty else {
                        throw MonitorError(message: "GitHub returned an incomplete commit comparison. Will retry.")
                    }
                    complete += value.commits.map { $0.value }
                    guard Set(complete.map(\.oid)).count == complete.count, complete.count <= value.total_commits else {
                        throw MonitorError(message: "GitHub returned duplicate or inconsistent comparison pages. Will retry.")
                    }
                    if complete.count == value.total_commits { break }
                    page += 1
                } while true
                let verified = try decoder.decode(CommitResponse.self, from: request(["api", "--hostname", "github.com", "graphql", "-f", "query=\(query)", "-f", "id=\(pr.id)"]))
                guard verified.errors == nil, let current = verified.data?.node,
                      current.headRefOid == head, current.baseRefOid == base,
                      current.commits.totalCount == complete.count else {
                    throw MonitorError(message: "PR changed during its full commit comparison. Will retry.")
                }
                return complete
            }
            if !node.commits.pageInfo.hasNextPage { return result }
            guard let next = node.commits.pageInfo.endCursor, visited.insert(next).inserted else {
                throw MonitorError(message: "GitHub commit pagination failed. Will retry.")
            }
            cursor = next
        } while true
    }

    static func searchText(login: String, since: Date, opened: Bool) -> String {
        let date = ISO8601DateFormatter().string(from: since)
        return opened
            ? "is:pr author:\(login) created:>=\(date) sort:created-asc"
            : "is:pr is:merged author:\(login) merged:>=\(date) sort:updated-asc"
    }

    static func search<PR: Decodable>(query: String, search: String, request: ([String]) throws -> Data = GitHub.run) throws -> [PR] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var cursor: String?
        var visitedCursors = Set<String>()
        var prs: [PR] = []
        repeat {
            var args = ["api", "--hostname", "github.com", "graphql", "-f", "query=\(query)", "-f", "q=\(search)"]
            if let cursor { args += ["-f", "cursor=\(cursor)"] }
            let response = try decoder.decode(SearchResponse<PR>.self, from: request(args))
            guard response.errors == nil, let page = response.data?.search else {
                throw MonitorError(message: "GitHub returned an incomplete result. Will retry without advancing the checkpoint.")
            }
            guard page.issueCount <= 1000 else {
                throw MonitorError(message: "Over 1,000 GitHub events since the checkpoint; narrow the catch-up window before continuing.")
            }
            prs += page.nodes
            if !page.pageInfo.hasNextPage { return prs }
            guard let next = page.pageInfo.endCursor, visitedCursors.insert(next).inserted else {
                throw MonitorError(message: "GitHub pagination failed. Will retry.")
            }
            cursor = next
        } while true
    }

}

private struct SearchResponse<PR: Decodable>: Decodable {
    let data: Payload?
    let errors: [APIError]?
    struct APIError: Decodable { let message: String }
    struct Payload: Decodable { let search: Search }
    struct Search: Decodable {
        let issueCount: Int
        let nodes: [PR]
        let pageInfo: PageInfo
    }
    struct PageInfo: Decodable { let hasNextPage: Bool; let endCursor: String? }
}

private struct CommitResponse: Decodable {
    let data: Payload?
    let errors: [APIError]?
    struct APIError: Decodable { let message: String }
    struct Payload: Decodable { let node: Node? }
    struct Node: Decodable {
        let headRefOid: String?
        let baseRefOid: String?
        let headRepository: MergedPR.Repository?
        let commits: Connection
    }
    struct Connection: Decodable { let totalCount: Int; let nodes: [Entry]; let pageInfo: PageInfo }
    struct Entry: Decodable { let commit: PRCommit }
    struct PageInfo: Decodable { let hasNextPage: Bool; let endCursor: String? }
}

private struct CompareResponse: Decodable {
    let total_commits: Int
    let commits: [Commit]
    struct Commit: Decodable {
        let sha: String
        let author: PRCommit.Author.User?
        let commit: Details
        struct Details: Decodable {
            let message: String
            let committer: Timestamp
            struct Timestamp: Decodable { let date: Date }
        }
        var value: PRCommit {
            PRCommit(oid: sha, messageHeadline: String(commit.message.prefix { $0 != "\n" }), committedDate: commit.committer.date, author: .init(user: author))
        }
    }
}

struct StateStore {
    let directory: URL
    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("JobsDone")) {
        self.directory = directory
    }
    func load(login: String, now: Date) throws -> AccountState {
        let file = directory.appendingPathComponent("\(login).json")
        guard FileManager.default.fileExists(atPath: file.path) else {
            return AccountState(startedAt: now, lastCheck: now, issues: IssueState(startedAt: now, lastCheck: now), opened: OpenedState(startedAt: now, lastCheck: now), commits: CommitState(startedAt: now, lastCheck: now), comments: CommentState(startedAt: now, lastCheck: now))
        }
        do {
            var state = try JSONDecoder().decode(AccountState.self, from: Data(contentsOf: file))
            // Opening alerts begin at upgrade; existing merge checkpoints stay intact.
            if state.issues == nil { state.issues = IssueState(startedAt: now, lastCheck: now) }
            if state.opened == nil { state.opened = OpenedState(startedAt: now, lastCheck: now) }
            if state.comments == nil { state.comments = CommentState(startedAt: now, lastCheck: now) }
            if state.commits == nil { state.commits = CommitState(startedAt: now, lastCheck: now) }
            return state
        } catch {
            throw MonitorError(message: "Saved PR history could not be read at \(file.path). Quit the app and restore a backup of this file, or move it aside to start watching from a new setup boundary. Moving it aside clears the app’s prior delivery history; old PR events will remain silent. Your existing file has not been changed.")
        }
    }
    func save(_ state: AccountState, login: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let file = directory.appendingPathComponent("\(login).json")
        try JSONEncoder().encode(state).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
