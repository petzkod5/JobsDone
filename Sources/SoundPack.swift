import Foundation

/// Code-registered packs use one WAV file per event in a bundled folder.
struct SoundPack: Identifiable {
    let id: String
    let name: String
    let directory: URL

    func fileURL(for event: NotificationEvent) -> URL {
        directory.appendingPathComponent(event.rawValue).appendingPathExtension("wav")
    }

    // macOS notification sounds use unique filenames at the bundle resource root.
    func notificationSoundName(for event: NotificationEvent) -> String {
        "\(id)-\(event.rawValue).wav"
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
            .appendingPathComponent("Contents/Resources/SoundPacks/peon", isDirectory: true))
    ], defaultID: "peon")
}
