//
//  SharedContainer.swift
//  Minor Ai (app, widgets and share extension)
//
//  The app group the app shares with its extensions: the widget reads a small summary of
//  today's tasks the app writes there, and the share extension leaves pages and text in an
//  inbox the app picks up when it opens.
//

import Foundation

enum SharedContainer {
    static let group = "group.com.minorailifegroup.MinorAI"
    static let scheme = "minorai"

    static var url: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) }
    static var widgetFile: URL? { url?.appendingPathComponent("widget.json") }
    static var inbox: URL? { url?.appendingPathComponent("Inbox", isDirectory: true) }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

// What the Today widget shows, written by the app whenever maps change.
struct WidgetSnapshot: Codable, Equatable {
    struct Task: Codable, Equatable, Identifiable {
        var id: UUID          // the idea
        var mapID: UUID
        var title: String
        var map: String
        var due: Date?
        var priority: Int?
    }

    var updated: Date
    var tasks: [Task]          // open tasks due today or earlier, soonest first (at most 6)
    var dueCount: Int
    var doneToday: Int
    var openCount: Int
    var language: String       // "en" or "ru": the widget speaks the app's language

    static let empty = WidgetSnapshot(updated: .distantPast, tasks: [], dueCount: 0, doneToday: 0, openCount: 0, language: "en")

    static func read() -> WidgetSnapshot? {
        guard let file = SharedContainer.widgetFile, let data = try? Data(contentsOf: file) else { return nil }
        return try? SharedContainer.decoder.decode(WidgetSnapshot.self, from: data)
    }
}

// A page or text shared to Minor from another app, waiting to become a map.
struct SharedItem: Codable, Equatable, Identifiable {
    var id = UUID()
    var date = Date()
    var title: String?
    var url: String?
    var text: String?

    static func pending() -> [SharedItem] {
        guard let inbox = SharedContainer.inbox,
              let files = try? FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "json" }
            .compactMap { try? SharedContainer.decoder.decode(SharedItem.self, from: Data(contentsOf: $0)) }
            .sorted { $0.date < $1.date }
    }

    func save() throws {
        guard let inbox = SharedContainer.inbox else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        try SharedContainer.encoder.encode(self).write(to: inbox.appendingPathComponent("\(id.uuidString).json"), options: .atomic)
    }

    func remove() {
        guard let inbox = SharedContainer.inbox else { return }
        try? FileManager.default.removeItem(at: inbox.appendingPathComponent("\(id.uuidString).json"))
    }
}
