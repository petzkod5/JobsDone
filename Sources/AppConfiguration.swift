import Foundation

struct AppConfiguration {
    var defaults: UserDefaults
    var historyDirectory: URL
    var isolated = false
    var now: () -> Date = Date.init
    var wait: (TimeInterval) async -> Void = { seconds in
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
    var soundOutput: ((String) -> Bool)?
    var output: ((String) -> Void)?

    static var production: AppConfiguration {
        AppConfiguration(defaults: .standard, historyDirectory: StateStore().directory)
    }
    static func isolated(directory: URL, output: ((String) -> Void)? = nil) -> AppConfiguration {
        // A dedicated suite never reads or writes the installed app's domain.
        let defaults = UserDefaults(suiteName: "JobsDone.Dev." + UUID().uuidString)!
        return AppConfiguration(defaults: defaults, historyDirectory: directory, isolated: true, output: output)
    }
}
