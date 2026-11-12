import Foundation

struct CommentNotice: Codable, Equatable {
    let pr: CommitPR
    let id: String
    let author: String
    let body: String
    let url: String
    let createdAt: Date
}

struct CommentState: Codable {
    var startedAt: Date
    var lastCheck: Date
    var delivered: Set<String> = []
    var recent: [CommentNotice] = []

    func pending(_ comments: [CommentNotice], login: String) -> [CommentNotice] {
        var seen = delivered
        return comments.sorted { $0.createdAt < $1.createdAt }.filter {
            $0.createdAt >= startedAt && $0.author.caseInsensitiveCompare(login) != .orderedSame
                && seen.insert($0.id).inserted
        }
    }

    mutating func record(_ comment: CommentNotice) {
        delivered.insert(comment.id)
        recent.removeAll { $0.id == comment.id }
        recent.insert(comment, at: 0)
        recent = Array(recent.prefix(10))
    }
}

extension GitHub {
    static func comments(login: String, since: Date, request: ([String]) throws -> Data = GitHub.run) throws -> [CommentNotice] {
        let fields = "id title url number createdAt headRefOid repository { nameWithOwner }"
        let candidateQuery = query.replacingOccurrences(of: "id title url number mergedAt repository { nameWithOwner }", with: fields)
        let date = ISO8601DateFormatter().string(from: since)
        let prs: [CommitPR] = try search(query: candidateQuery, search: "is:pr author:\(login) updated:>=\(date) sort:updated-asc", request: request)
        var result: [CommentNotice] = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for pr in prs {
            let repo = "repos/\(pr.repository.nameWithOwner)"
            let endpoints = [("issue", "\(repo)/issues/\(pr.number)/comments"),
                             ("inline", "\(repo)/pulls/\(pr.number)/comments"),
                             ("review", "\(repo)/pulls/\(pr.number)/reviews")]
            for (kind, endpoint) in endpoints {
                var page = 1
                var seen = Set<Int>()
                while true {
                    try Task.checkCancellation()
                    let data = try request(["api", "--hostname", "github.com", "\(endpoint)?per_page=100&page=\(page)"])
                    let entries = try decoder.decode([CommentEntry].self, from: data)
                    for entry in entries {
                        guard seen.insert(entry.id).inserted else {
                            throw MonitorError(message: "GitHub returned inconsistent comment pages. Will retry.")
                        }
                        guard let created = kind == "review" ? entry.submitted_at : entry.created_at,
                              created >= since, let author = entry.user?.login,
                              let body = entry.body, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                        result.append(CommentNotice(pr: pr, id: "\(pr.id)-\(kind)-\(entry.id)", author: author,
                                                    body: body, url: entry.html_url, createdAt: created))
                    }
                    if entries.count < 100 { break }
                    page += 1
                }
            }
        }
        return result
    }
}

private struct CommentEntry: Decodable {
    let id: Int
    let user: PRCommit.Author.User?
    let body: String?
    let html_url: String
    let created_at: Date?
    let submitted_at: Date?
}
