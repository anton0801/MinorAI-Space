//
//  Workspace.swift
//  Minor Ai
//
//  What the chat assistant knows about the person's maps. Every message carries only a short
//  index (titles and progress); a map's content goes to the AI when the assistant asks to read
//  it (see _shared/intent.ts on the server). Maps stay on the phone.
//

import Foundation

@MainActor
enum Workspace {
    // Settings → "Assistant Sees My Maps".
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "assistantSeesMaps") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "assistantSeesMaps") }
    }

    // A short, stable name for a map in conversations with the AI.
    static func ref(_ id: UUID) -> String {
        "m-" + id.uuidString.replacingOccurrences(of: "-", with: "").prefix(6).lowercased()
    }

    static func map(ref: String) -> MindMap? {
        MapStore.shared.maps.first { Self.ref($0.id) == ref.lowercased() }
    }

    // Presentations are named "d-…" in conversations with the AI.
    static func deckRef(_ id: UUID) -> String {
        "d-" + id.uuidString.replacingOccurrences(of: "-", with: "").prefix(6).lowercased()
    }

    static func deck(ref: String) -> Deck? {
        DeckStore.shared.decks.first { deckRef($0.id) == ref.lowercased() }
    }

    struct Entry: Encodable, Equatable {
        let ref: String
        let title: String
        let ideas: Int
        let tasksDone: Int
        let tasksTotal: Int
        let edited: String
        let pinned: Bool
    }

    // Pinned maps first, then the most recently edited; at most 40.
    static func index() -> [Entry] {
        index(MapStore.shared.maps) + DeckStore.shared.decks.prefix(20).map { deck in
            Entry(ref: deckRef(deck.id), title: deck.title, ideas: deck.slides.count, tasksDone: 0, tasksTotal: 0, edited: day(deck.updatedAt), pinned: false)
        }
    }

    static func index(_ maps: [MindMap]) -> [Entry] {
        let ordered = maps.filter(\.isPinned) + maps.filter { !$0.isPinned }
        return ordered.prefix(40).map { map in
            let progress = map.root.taskProgress
            return Entry(
                ref: ref(map.id),
                title: map.title,
                ideas: map.nodeCount,
                tasksDone: progress.done,
                tasksTotal: progress.total,
                edited: day(map.updatedAt),
                pinned: map.isPinned
            )
        }
    }

    static var today: String { day(Date()) }

    private static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // MARK: - What the AI reads

    // A map as an indented outline with tasks, priorities and short notes, at most `limit` characters.
    static func outline(of map: MindMap, limit: Int = 6_000) -> String {
        let progress = map.root.taskProgress
        var header = "Map \(ref(map.id)) \"\(map.title)\": \(map.nodeCount) ideas"
        if progress.total > 0 { header += ", tasks \(progress.done)/\(progress.total) done" }
        header += ", edited \(day(map.updatedAt))"

        func lines(withNotes: Bool) -> [String] {
            var result: [String] = []
            func walk(_ node: MindNode, depth: Int) {
                for child in node.children {
                    var line = String(repeating: "  ", count: depth) + "- " + describe(child)
                    if withNotes, !child.note.isEmpty {
                        let note = child.note.replacingOccurrences(of: "\n", with: " ")
                        line += " — note: " + (note.count > 140 ? String(note.prefix(139)) + "…" : note)
                    }
                    result.append(line)
                    walk(child, depth: depth + 1)
                }
            }
            if !map.root.note.isEmpty { result.append("Topic note: " + String(map.root.note.prefix(300))) }
            walk(map.root, depth: 0)
            return result
        }

        var body = lines(withNotes: true)
        let connections = map.links.compactMap { link -> String? in
            guard let from = map.root.node(link.from), let to = map.root.node(link.to) else { return nil }
            return "- \(from.title) → \(to.title)" + (link.label.isEmpty ? "" : " (\(link.label))")
        }
        if !connections.isEmpty { body += ["Connections:"] + connections }
        if body.joined(separator: "\n").count + header.count > limit { body = lines(withNotes: false) }
        var text = header
        for (index, line) in body.enumerated() {
            if text.count + line.count + 1 > limit {
                text += "\n… and \(body.count - index) more ideas"
                break
            }
            text += "\n" + line
        }
        return text
    }

    static func describe(_ node: MindNode) -> String {
        var text = node.title
        if let icon = node.icon { text = "\(icon) \(text)" }
        if node.isTask { text = (node.isDone ? "[x] " : "[ ] ") + text }
        var marks: [String] = []
        if let priority = node.priority { marks.append("priority \(priority)") }
        if let due = node.due { marks.append("due \(day(due))") }
        if node.image != nil { marks.append("picture") }
        if let link = node.link { marks.append(link) }
        if node.isCallout { marks.append("callout") }
        if node.isSuggestion { marks.append("suggested, not accepted yet") }
        if let frame = node.frame { marks.append(frame.isEmpty ? "framed" : "frame: \(frame)") }
        if !marks.isEmpty { text += " (" + marks.joined(separator: ", ") + ")" }
        return text
    }

    // Unfinished tasks across all maps: overdue and due first, then by priority.
    static func openTasks() -> String { openTasks(MapStore.shared.maps) }

    static func openTasks(_ maps: [MindMap], limit: Int = 60) -> String {
        struct Item { let line: String; let due: Date?; let priority: Int; let order: Int }
        var items: [Item] = []
        var done = 0
        var order = 0
        for map in maps {
            func walk(_ node: MindNode, path: [String]) {
                for child in node.children {
                    if child.isTask {
                        if child.isDone {
                            done += 1
                        } else {
                            let place = ([map.title] + path).joined(separator: " > ")
                            items.append(Item(line: "- " + describe(child) + " — in \"\(place)\"", due: child.due, priority: child.priority ?? 4, order: order))
                            order += 1
                        }
                    }
                    walk(child, path: path + [child.title])
                }
            }
            walk(map.root, path: [])
        }
        guard !items.isEmpty else {
            return "Open tasks (today is \(today)): none. \(done) tasks are done."
        }
        let sorted = items.sorted { a, b in
            switch (a.due, b.due) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.priority != b.priority ? a.priority < b.priority : a.order < b.order
            }
        }
        var text = "Open tasks (today is \(today)), \(items.count) open and \(done) done:"
        for item in sorted.prefix(limit) { text += "\n" + item.line }
        if sorted.count > limit { text += "\n… and \(sorted.count - limit) more" }
        return text
    }
}

// What an AI command changed in a map, for the chat's action card.
struct MapDiff: Equatable {
    var added = 0
    var removed = 0
    var changed = 0

    init(old: MindNode, new: MindNode) {
        var before: [UUID: MindNode] = [:]
        func collect(_ node: MindNode, into table: inout [UUID: MindNode]) {
            table[node.id] = node
            node.children.forEach { collect($0, into: &table) }
        }
        collect(old, into: &before)
        var after: [UUID: MindNode] = [:]
        collect(new, into: &after)
        added = after.keys.filter { before[$0] == nil }.count
        removed = before.keys.filter { after[$0] == nil }.count
        changed = after.compactMap { id, node -> Bool? in
            guard var was = before[id] else { return nil }
            var now = node
            was.children = []
            now.children = []
            was.isCollapsed = false
            now.isCollapsed = false
            return was != now ? true : nil
        }.count
    }

    var isEmpty: Bool { added == 0 && removed == 0 && changed == 0 }

    var summary: String {
        var parts: [String] = []
        if added > 0 { parts.append(L("+\(added) ideas")) }
        if changed > 0 { parts.append(L("\(changed) changed")) }
        if removed > 0 { parts.append(L("\(removed) removed")) }
        return parts.joined(separator: " · ")
    }
}
