//
//  MinorIntents.swift
//  Minor Ai
//
//  Siri, Shortcuts and Spotlight: add an idea to a map, hear today's tasks, create a map about
//  a topic, open a map. They run in the app (maps live on the phone).
//

import AppIntents
import Foundation

struct MapEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Mind Map"
    static var defaultQuery = MapQuery()

    var id: UUID
    var title: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct MapQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [MapEntity] {
        MapStore.shared.maps.filter { identifiers.contains($0.id) }.map { MapEntity(id: $0.id, title: $0.title) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [MapEntity] {
        let wanted = string.lowercased()
        return MapStore.shared.maps
            .filter { $0.title.lowercased().contains(wanted) }
            .map { MapEntity(id: $0.id, title: $0.title) }
    }

    @MainActor
    func suggestedEntities() async throws -> [MapEntity] {
        let maps = MapStore.shared.maps
        return (maps.filter(\.isPinned) + maps.filter { !$0.isPinned }).prefix(20).map { MapEntity(id: $0.id, title: $0.title) }
    }
}

struct AddIdeaIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Idea to Map"
    static var description = IntentDescription("Adds an idea to one of your mind maps, as a main branch or under a branch you name.")

    @Parameter(title: "Map")
    var map: MapEntity

    @Parameter(title: "Idea")
    var idea: String

    @Parameter(title: "Under Branch")
    var branch: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$idea) to \(\.$map)") {
            \.$branch
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = String(idea.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !text.isEmpty else { throw $idea.needsValueError("What idea should I add?") }
        guard let stored = MapStore.shared.map(map.id) else { throw $map.needsValueError("Which map?") }
        var parent = stored.root.id
        if let branch, !branch.trimmingCharacters(in: .whitespaces).isEmpty,
           let match = stored.root.ids(titled: [branch]).first {
            parent = match
        }
        MapStore.shared.update(map.id) { map in
            map.root.update(parent) { node in
                node.isCollapsed = false
                node.children.append(MindNode(title: text))
            }
        }
        return .result(dialog: "Added “\(text)” to \(map.title).")
    }
}

struct TodayTasksIntent: AppIntent {
    static var title: LocalizedStringResource = "Today’s Tasks"
    static var description = IntentDescription("Tells you which tasks in your maps are due today or overdue.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        let due = TaskAgenda.tasks(in: MapStore.shared.maps)
            .filter { !$0.isDone && ($0.due.map { $0 < tomorrow } ?? false) }
            .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
        guard !due.isEmpty else { return .result(dialog: "Nothing is due today.") }
        let list = due.prefix(5).map(\.title).joined(separator: "; ")
        return .result(dialog: "Due today: \(due.count). \(list)")
    }
}

struct NewMapIntent: AppIntent {
    static var title: LocalizedStringResource = "Create Mind Map"
    static var description = IntentDescription("Opens Minor and builds a mind map about a topic with AI.")
    static var openAppWhenRun = true

    @Parameter(title: "Topic")
    var topic: String

    @MainActor
    func perform() async throws -> some IntentResult {
        let text = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw $topic.needsValueError("What should the map be about?") }
        GenerationCenter.shared.topicRequest = text
        return .result()
    }
}

struct OpenMapIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Map"
    static var description = IntentDescription("Opens one of your mind maps.")
    static var openAppWhenRun = true

    @Parameter(title: "Map")
    var map: MapEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        GenerationCenter.shared.openRequest = map.id
        return .result()
    }
}

struct MinorShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddIdeaIntent(), phrases: [
            "Add an idea to \(.applicationName)",
            "Add to my \(.applicationName) map",
        ])
        AppShortcut(intent: TodayTasksIntent(), phrases: [
            "What’s due today in \(.applicationName)",
            "My tasks in \(.applicationName)",
        ])
        AppShortcut(intent: NewMapIntent(), phrases: [
            "Create a map in \(.applicationName)",
            "New mind map in \(.applicationName)",
        ])
        AppShortcut(intent: OpenMapIntent(), phrases: [
            "Open a map in \(.applicationName)",
        ])
    }
}
