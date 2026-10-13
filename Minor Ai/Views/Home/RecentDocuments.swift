//
//  RecentDocuments.swift
//  Minor Ai
//
//  Maps and presentations in the order they were last opened, for Continue in the menu and
//  "Recently opened" in the Library. Only ids and dates are kept; titles and previews come
//  from the stores, so a deleted document simply drops out.
//

import Foundation

@MainActor
final class RecentDocuments: ObservableObject {
    static let shared = RecentDocuments()

    enum Kind: String, Codable { case map, deck }

    struct Entry: Codable, Equatable, Identifiable {
        let kind: Kind
        let id: UUID
        var openedAt: Date
    }

    @Published private(set) var entries: [Entry] = []

    private let key = "recentDocuments"
    private let limit = 40

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = saved
        }
    }

    func opened(_ kind: Kind, _ id: UUID, at date: Date = Date()) {
        entries.removeAll { $0.id == id }
        entries.insert(Entry(kind: kind, id: id, openedAt: date), at: 0)
        if entries.count > limit { entries.removeLast(entries.count - limit) }
        save()
    }

    func forget(_ id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func clear() {
        entries = []
        UserDefaults.standard.removeObject(forKey: key)
    }

    // When a document was last opened here, or nil if never.
    func openedAt(_ id: UUID) -> Date? { entries.first { $0.id == id }?.openedAt }

    // The latest documents that still exist: opened ones first, then ones only edited (synced
    // from another device or made by the assistant), newest first.
    func latest(_ count: Int, maps: [MindMap], decks: [Deck]) -> [Entry] {
        let mapIDs = Set(maps.map(\.id))
        let deckIDs = Set(decks.map(\.id))
        var result = entries.filter { $0.kind == .map ? mapIDs.contains($0.id) : deckIDs.contains($0.id) }
        let known = Set(result.map(\.id))
        let edited = maps.filter { !known.contains($0.id) }.map { Entry(kind: .map, id: $0.id, openedAt: $0.updatedAt) }
            + decks.filter { !known.contains($0.id) }.map { Entry(kind: .deck, id: $0.id, openedAt: $0.updatedAt) }
        result += edited
        result.sort { $0.openedAt > $1.openedAt }
        return Array(result.prefix(count))
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) { UserDefaults.standard.set(data, forKey: key) }
    }
}
