import AppKit
import Foundation
@testable import JobsDone
import Testing
import UserNotifications

struct SoundPackTests {
    @Test @MainActor func selectedPackRoutesBothDeliveryPaths() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let peon = SoundPack(id: "peon", name: "Peon", directory: root.appendingPathComponent("peon"),
                             sounds: ["Default.wav"], eventSounds: Dictionary(uniqueKeysWithValues: NotificationEvent.allCases.map { ($0, "Default.wav") }))
        let other = SoundPack(id: "other", name: "Other", directory: root.appendingPathComponent("other"),
                              sounds: ["Hello.wav", "Done.wav", "Unused.wav"],
                              eventSounds: [.opened: "Hello.wav", .merged: "Done.wav", .committed: "Hello.wav", .issueOpened: "Done.wav", .commented: "Hello.wav"])
        let registry = SoundPackRegistry(packs: [peon, other], defaultID: "peon")
        var config = AppConfiguration.isolated(directory: root)
        let suite = config.defaults
        defer { for key in suite.dictionaryRepresentation().keys { suite.removeObject(forKey: key) } }
        config.soundPacks = registry
        var files: [URL] = []
        var requests: [UNNotificationRequest] = []
        config.soundOutput = { files.append($0); return true }
        config.notificationOutput = { requests.append($0) }
        let app = AppDelegate(configuration: config)
        app.notificationState = .ready
        #expect(app.preferences.soundPack.id == "peon")
        app.preferences.soundPack = other
        #expect(NotificationPreferences(defaults: suite, soundPacks: registry).soundPack.id == "other")
        for event in NotificationEvent.allCases {
            #expect(await app.playSound(event: event, repository: "o/r"))
        }
        #expect(files == ["Hello.wav", "Done.wav", "Hello.wav", "Done.wav", "Hello.wav"].map { root.appendingPathComponent("other/" + $0) })
        app.preferences.nativeNotifications = true
        for event in NotificationEvent.allCases {
            await app.post(event: event, repository: "o/r", id: event.rawValue, subtitle: "Fixture", body: "Fixture",
                           url: "https://github.com/o/r/pull/1", issueOpened: event == .issueOpened, opened: event == .opened, committed: event == .committed)
        }
        #expect(requests.count == NotificationEvent.allCases.count)
        let nativeNames = ["other-Hello.wav", "other-Done.wav", "other-Hello.wav", "other-Done.wav", "other-Hello.wav"]
        for (request, name) in zip(requests, nativeNames) {
            let sound = try #require(request.content.sound)
            let data = try NSKeyedArchiver.archivedData(withRootObject: sound, requiringSecureCoding: true)
            let archive = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            let objects = archive?["$objects"] as? [Any] ?? []
            #expect(objects.compactMap { $0 as? String }.contains(name))
        }
        app.preferences.soundEnabled = false
        let mutedApp = AppDelegate(configuration: config)
        mutedApp.notificationState = .ready
        await mutedApp.post(id: "muted", subtitle: "Fixture", body: "Fixture", url: "https://github.com/o/r/pull/1")
        #expect(requests.last?.content.sound == nil)
        suite.set("removed", forKey: "soundPackID")
        #expect(app.preferences.soundPack.id == "peon")
        suite.set(42, forKey: "soundPackID")
        #expect(app.preferences.soundPack.id == "peon")
        suite.removeObject(forKey: "soundPackID")
    }

    @Test func bundledFilesArePlayableAndShort() throws {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/SoundPacks/peon")
        let pack = SoundPackRegistry.bundled.defaultPack
        #expect(NotificationEvent.allCases.map { pack.fileURL(for: $0).lastPathComponent }
                == ["WorkWork.wav", "JobsDone.wav", "Hmmm.wav", "SomethingNeedDoing.wav", "GetEm.wav"])
        for event in NotificationEvent.allCases {
            let clip = try #require(NSSound(contentsOf: folder.appendingPathComponent(pack.fileURL(for: event).lastPathComponent), byReference: false))
            #expect(clip.duration > 0 && clip.duration < 30)
        }
    }
}
