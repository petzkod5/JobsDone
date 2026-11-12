import Foundation

enum NotificationEvent: String, CaseIterable {
    case opened, merged, committed, issueOpened, commented
}

/// Installation-wide preferences; account checkpoints remain in StateStore.
final class NotificationPreferences {
    let soundPacks: SoundPackRegistry
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard, soundPacks: SoundPackRegistry = .bundled) {
        self.defaults = defaults
        self.soundPacks = soundPacks
    }
    var soundPack: SoundPack {
        get { soundPacks.pack(id: defaults.string(forKey: "soundPackID")) }
        set { defaults.set(soundPacks.pack(id: newValue.id).id, forKey: "soundPackID") }
    }

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
    static let pollingIntervals: [TimeInterval] = [30, 60, 120, 300, 600, 900]
    static let notificationDurations: [TimeInterval] = [5, 8, 10, 15, 20, 30, 60]
    var pollingInterval: TimeInterval {
        get { supportedTime("pollingInterval", choices: Self.pollingIntervals, fallback: 60) }
        set { defaults.set(Self.pollingIntervals.contains(newValue) ? newValue : 60, forKey: "pollingInterval") }
    }
    var notificationDuration: TimeInterval {
        get { supportedTime("notificationDuration", choices: Self.notificationDurations, fallback: 8) }
        set { defaults.set(Self.notificationDurations.contains(newValue) ? newValue : 8, forKey: "notificationDuration") }
    }
    private func supportedTime(_ key: String, choices: [TimeInterval], fallback: TimeInterval) -> TimeInterval {
        guard let number = defaults.object(forKey: key) as? NSNumber,
              choices.contains(number.doubleValue) else { return fallback }
        return number.doubleValue
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
