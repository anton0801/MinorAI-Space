//
//  ConversationStore.swift
//  Minor Ai
//
//  Persists conversations as a JSON file in Application Support. Conversations used to live in
//  UserDefaults; they move to the file on first launch (photos would bloat UserDefaults).
//

import Foundation

final class ConversationStore {
    static let shared = ConversationStore()

    private let file: URL
    private let legacyKey = "SavedConversations"
    // Writes happen in order off the main thread (photos make the file large).
    private let io = DispatchQueue(label: "com.minorailifegroup.MinorAI.conversations", qos: .utility)

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        file = base.appendingPathComponent("Conversations.json")
        migrateFromUserDefaults()
    }

    // Reads every conversation that can be read. One broken entry doesn't hide the others, and a
    // file that can't be read at all is kept aside, so the next save never overwrites it.
    func loadAll() -> [Conversation] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        let decoder = JSONDecoder()
        if let list = try? decoder.decode([Lossy<Conversation>].self, from: data) {
            return list.compactMap(\.value).sorted { $0.updatedAt > $1.updatedAt }
        }
        let backup = file.deletingPathExtension().appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.copyItem(at: file, to: backup)
        return []
    }

    func saveAll(_ conversations: [Conversation]) {
        let file = file
        io.async {
            guard let data = try? JSONEncoder().encode(conversations) else { return }
            // Readable after the first unlock, so a reply that arrives while the phone is locked is still saved.
            try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    // Copies of unreadable files set aside by loadAll (removed when the account is deleted).
    func deleteBackups() {
        let folder = file.deletingLastPathComponent()
        io.async {
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for url in files where url.lastPathComponent.hasPrefix("Conversations.unreadable") {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    // Waits until queued writes reach the disk.
    func flush() {
        io.sync {}
    }

    private func migrateFromUserDefaults() {
        let defaults = UserDefaults.standard
        guard !FileManager.default.fileExists(atPath: file.path), let data = defaults.data(forKey: legacyKey) else { return }
        do {
            try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            defaults.removeObject(forKey: legacyKey)
        } catch {
            // Keep the old copy; the move is tried again on the next launch.
        }
    }
}

// Decodes an element if it can, nil otherwise, so one bad entry doesn't fail a whole list.
struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}
