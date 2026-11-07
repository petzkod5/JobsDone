import Foundation
import Testing
@testable import JobsDone

struct TimingTests {
    @Test func preferencesPersistAndRejectUnsupportedValues() {
        let suite = "JobsDone.TimingTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = NotificationPreferences(defaults: defaults)
        #expect(preferences.pollingInterval == 60)
        #expect(preferences.notificationDuration == 8)
        for interval in NotificationPreferences.pollingIntervals {
            preferences.pollingInterval = interval
            #expect(NotificationPreferences(defaults: defaults).pollingInterval == interval)
        }
        for duration in NotificationPreferences.notificationDurations {
            preferences.notificationDuration = duration
            #expect(NotificationPreferences(defaults: defaults).notificationDuration == duration)
        }
        for invalid in [-1.0, 0, 1, 1e100, Double.infinity, Double.nan] {
            preferences.pollingInterval = invalid
            preferences.notificationDuration = invalid
            #expect(preferences.pollingInterval == 60)
            #expect(preferences.notificationDuration == 8)
            defaults.set(invalid, forKey: "pollingInterval")
            defaults.set(invalid, forKey: "notificationDuration")
            #expect(preferences.pollingInterval == 60)
            #expect(preferences.notificationDuration == 8)
        }
        defaults.set("bad", forKey: "pollingInterval")
        defaults.set(true, forKey: "notificationDuration")
        #expect(preferences.pollingInterval == 60)
        #expect(preferences.notificationDuration == 8)
    }

    @Test @MainActor func reschedulingReplacesTheProductionTimer() {
        let suite = "JobsDone.TimerTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let delegate = AppDelegate(configuration: AppConfiguration(defaults: defaults,
            historyDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        delegate.preferences.pollingInterval = 120
        delegate.reschedulePolling()
        let first = delegate.timer!
        #expect(first.timeInterval == 120)
        delegate.preferences.pollingInterval = 30
        delegate.reschedulePolling()
        defer { delegate.timer?.invalidate() }
        #expect(!first.isValid)
        #expect(delegate.timer!.isValid)
        #expect(delegate.timer!.timeInterval == 30)
        #expect(delegate.timer!.fireDate.timeIntervalSinceNow > 29)
    }
}
