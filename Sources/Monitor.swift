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

struct AccountState: Codable {
    var startedAt: Date
    var lastCheck: Date
    var delivered: Set<String> = []
    var recent: [MergedPR] = []
    var opened: OpenedState?

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

    static func searchText(login: String, since: Date, opened: Bool) -> String {
        let date = ISO8601DateFormatter().string(from: since)
        return opened
            ? "is:pr author:\(login) created:>=\(date) sort:created-asc"
            : "is:pr is:merged author:\(login) merged:>=\(date) sort:updated-asc"
    }

    private static func search<PR: Decodable>(query: String, search: String) throws -> [PR] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var cursor: String?
        var visitedCursors = Set<String>()
        var prs: [PR] = []
        repeat {
            var args = ["api", "--hostname", "github.com", "graphql", "-f", "query=\(query)", "-f", "q=\(search)"]
            if let cursor { args += ["-f", "cursor=\(cursor)"] }
            let response = try decoder.decode(SearchResponse<PR>.self, from: run(args))
            guard response.errors == nil, let page = response.data?.search else {
                throw MonitorError(message: "GitHub returned an incomplete result. Will retry without advancing the checkpoint.")
            }
            guard page.issueCount <= 1000 else {
                throw MonitorError(message: "Over 1,000 PR events since the checkpoint; narrow the catch-up window before continuing.")
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

struct StateStore {
    let directory: URL
    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("JobsDone")) {
        self.directory = directory
    }
    func load(login: String, now: Date) throws -> AccountState {
        let file = directory.appendingPathComponent("\(login).json")
        guard FileManager.default.fileExists(atPath: file.path) else {
            return AccountState(startedAt: now, lastCheck: now, opened: OpenedState(startedAt: now, lastCheck: now))
        }
        do {
            var state = try JSONDecoder().decode(AccountState.self, from: Data(contentsOf: file))
            // Opening alerts begin at upgrade; existing merge checkpoints stay intact.
            if state.opened == nil { state.opened = OpenedState(startedAt: now, lastCheck: now) }
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
