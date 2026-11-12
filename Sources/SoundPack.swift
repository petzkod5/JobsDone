import Foundation

/// Packs bundle named sounds and select a default sound for each event.
struct SoundPack: Identifiable {
    let id: String
    let name: String
    let directory: URL

    let sounds: [String]
    let eventSounds: [NotificationEvent: String]

    init(id: String, name: String, directory: URL, sounds: [String], eventSounds: [NotificationEvent: String]) {
        precondition(!sounds.isEmpty && Set(sounds).count == sounds.count, "Sound filenames must be unique")
        precondition(sounds.allSatisfy { $0.range(of: "^[A-Za-z0-9_-]+\\.wav$", options: .regularExpression) != nil },
                     "Sounds must use filename-safe WAV names")
        precondition(NotificationEvent.allCases.allSatisfy { eventSounds[$0].map(sounds.contains) == true },
                     "Every event must select a sound in the pack")
        self.id = id
        self.name = name
        self.directory = directory
        self.sounds = sounds
        self.eventSounds = eventSounds
    }

    func fileURL(for event: NotificationEvent) -> URL {
        directory.appendingPathComponent(eventSounds[event]!)
    }

    // macOS notification sounds use unique filenames at the bundle resource root.
    func notificationSoundName(for event: NotificationEvent) -> String {
        "\(id)-\(eventSounds[event]!)"
    }
}

struct SoundPackRegistry {
    let packs: [SoundPack]
    let defaultPack: SoundPack

    init(packs: [SoundPack], defaultID: String) {
        precondition(!packs.isEmpty && Set(packs.map(\.id)).count == packs.count, "Sound pack IDs must be unique")
        precondition(packs.allSatisfy { $0.id.range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil }, "Sound pack IDs must be filename-safe")
        guard let defaultPack = packs.first(where: { $0.id == defaultID }) else {
            preconditionFailure("The default sound pack must be registered")
        }
        self.packs = packs
        self.defaultPack = defaultPack
    }

    func pack(id: String?) -> SoundPack {
        packs.first { $0.id == id } ?? defaultPack
    }

    static let bundled = SoundPackRegistry(packs: [
        SoundPack(id: "peon", name: "Peon", directory: Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/SoundPacks/peon", isDirectory: true),
                  sounds: ["WorkWork.wav", "JobsDone.wav", "Hmmm.wav", "SomethingNeedDoing.wav", "GetEm.wav"],
                  eventSounds: [.opened: "WorkWork.wav", .merged: "JobsDone.wav",
                                .committed: "Hmmm.wav", .issueOpened: "SomethingNeedDoing.wav", .commented: "GetEm.wav"])
    ], defaultID: "peon")
}
