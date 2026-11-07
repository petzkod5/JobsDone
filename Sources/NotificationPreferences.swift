import Foundation

enum NotificationEvent: String, CaseIterable {
    case opened, merged, committed
}

/// Installation-wide preferences; account checkpoints remain in StateStore.
final class NotificationPreferences {
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func isEnabled(_ event: NotificationEvent) -> Bool {
        defaults.object(forKey: "notify." + event.rawValue) as? Bool ?? true
    }
    func setEnabled(_ enabled: Bool, for event: NotificationEvent) {
        defaults.set(enabled, forKey: "notify." + event.rawValue)
    }
    var soundEnabled: Bool {
        get { !defaults.bool(forKey: "muted") }
        set { defaults.set(!newValue, forKey: "muted") }
    }
    var nativeNotifications: Bool {
        get { defaults.bool(forKey: "nativeNotifications") }
        set { defaults.set(newValue, forKey: "nativeNotifications") }
    }
    var ignoredRepositories: [String] {
        Array(Set((defaults.stringArray(forKey: "ignoredRepositories") ?? []).compactMap(Self.canonicalRepository))).sorted()
    }
    static func canonicalRepository(_ input: String) -> String? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let owner = String(parts[0]), repo = String(parts[1])
        guard owner.count <= 39, repo.count <= 100, repo != ".", repo != "..",
              owner.range(of: "^[a-z0-9]+(-[a-z0-9]+)*$", options: .regularExpression) != nil,
              repo.range(of: "^[a-z0-9_.-]+$", options: .regularExpression) != nil else { return nil }
        return value
    }
    @discardableResult func addRepository(_ input: String) -> String? {
        guard let repo = Self.canonicalRepository(input) else {
            return "Enter owner/repository (no URL or wildcard). Owner: up to 39 letters, numbers or internal hyphens. Repository: up to 100 letters, numbers, dots, underscores or hyphens."
        }
        guard !ignoredRepositories.contains(repo) else { return "\(repo) is already ignored." }
        defaults.set((ignoredRepositories + [repo]).sorted(), forKey: "ignoredRepositories")
        return nil
    }
    func removeRepository(_ repo: String) {
        defaults.set(ignoredRepositories.filter { $0 != repo }, forKey: "ignoredRepositories")
    }
    func allows(_ event: NotificationEvent, repository: String) -> Bool {
        isEnabled(event) && !ignoredRepositories.contains(repository.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}
