//
//  Reminders.swift
//  Minor Ai
//
//  A notification for every unfinished task with a due date, at that date and time. They are
//  rebuilt from the maps whenever the maps change, so a task that is done, moved or deleted never
//  reminds anyone. Tapping one opens the map at that task.
//

import Combine
import Foundation
import UserNotifications

@MainActor
final class Reminders {
    static let shared = Reminders()

    // Settings → Task Reminders.
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "taskReminders") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "taskReminders")
            shared.sync(MapStore.shared.maps)
        }
    }

    static let prefix = "task-"

    // Settings → Morning Brief: at 8:30, today's tasks and cards to review.
    static var morningBrief: Bool {
        get { UserDefaults.standard.object(forKey: "morningBrief") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "morningBrief")
            shared.sync(MapStore.shared.maps)
        }
    }
    // iOS keeps at most 64 pending notifications per app; the rest wait for the next sync.
    private static let limit = 50

    private var subscription: AnyCancellable?

    func start() {
        guard subscription == nil else { return }
        subscription = MapStore.shared.$maps
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] maps in self?.sync(maps) }
    }

    // Asked when the person first gives a task a date.
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    struct Item: Equatable {
        let mapID: UUID
        let mapTitle: String
        let nodeID: UUID
        let title: String
        let due: Date
    }

    // Unfinished tasks due after `now`, soonest first.
    static func upcoming(in maps: [MindMap], after now: Date = Date()) -> [Item] {
        var items: [Item] = []
        for map in maps {
            func walk(_ node: MindNode) {
                if node.isTask, !node.isDone, !node.isSuggestion, let due = node.due, due > now {
                    items.append(Item(mapID: map.id, mapTitle: map.title, nodeID: node.id, title: node.title, due: due))
                }
                node.children.forEach(walk)
            }
            walk(map.root)
        }
        return items.sorted { $0.due < $1.due }
    }

    struct Extra {
        let id: String
        let title: String
        let body: String
        let date: Date
        let route: String
    }

    // The morning summary for the next 8:30, when there is something to do that day.
    static func brief(for maps: [MindMap], now: Date = Date()) -> Extra? {
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: now)
        var at = calendar.date(bySettingHour: 8, minute: 30, second: 0, of: day) ?? now
        if at <= now {
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? now
            at = calendar.date(bySettingHour: 8, minute: 30, second: 0, of: day) ?? now
        }
        let end = calendar.date(byAdding: .day, value: 1, to: day) ?? at
        let tasks = TaskAgenda.tasks(in: maps).filter { !$0.isDone && ($0.due.map { $0 < end } ?? false) }
            .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
        // Only cards of maps that still exist (as Today counts them).
        let cardIDs = Set(maps.flatMap { Flashcards.make(from: $0).map(\.id) })
        let cards = StudyStore.shared.states.filter { cardIDs.contains($0.key) && $0.value.due < end }.count
        guard !tasks.isEmpty || cards > 0 else { return nil }
        var parts: [String] = []
        if !tasks.isEmpty { parts.append(L("Tasks today: \(tasks.count)")) }
        if cards > 0 { parts.append(L("cards to review: \(cards)")) }
        let list = tasks.prefix(3).map(\.title).joined(separator: ", ")
        return Extra(id: prefix + "brief", title: L("Good morning! ") + parts.joined(separator: " · "), body: list.isEmpty ? L("Open Today to plan your day.") : list, date: at, route: "minorai://today")
    }

    // One reminder in the evening of the day the next flashcards are due.
    static func studyReminder(for maps: [MindMap], now: Date = Date()) -> Extra? {
        guard let next = StudyStore.shared.nextReview(in: maps) else { return nil }
        let calendar = Calendar.current
        var at = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: max(next.date, now)) ?? now
        if at < next.date || at <= now { at = calendar.date(byAdding: .day, value: 1, to: at) ?? at }
        return Extra(id: prefix + "study", title: L("Time to review"), body: L("\(next.count) cards are ready to review."), date: at, route: "minorai://today")
    }

    func sync(_ maps: [MindMap]) {
        let items = Self.isEnabled ? Array(Self.upcoming(in: maps).prefix(Self.limit)) : []
        var extras: [Extra] = []
        if Self.isEnabled {
            if Self.morningBrief, let brief = Self.brief(for: maps) { extras.append(brief) }
            if let study = Self.studyReminder(for: maps) { extras.append(study) }
        }
        let center = UNUserNotificationCenter.current()
        let prefix = Self.prefix
        let bodies = items.map { L("Due now · \($0.mapTitle)") }
        center.getPendingNotificationRequests { requests in
            let ours = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: ours)
            for (item, body) in zip(items, bodies) {
                let content = UNMutableNotificationContent()
                content.title = item.title
                content.body = body
                content.sound = .default
                content.threadIdentifier = item.mapID.uuidString
                content.userInfo = ["mapID": item.mapID.uuidString, "nodeID": item.nodeID.uuidString]
                let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: item.due)
                let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                center.add(UNNotificationRequest(identifier: prefix + item.nodeID.uuidString, content: content, trigger: trigger))
            }
            for extra in extras {
                let content = UNMutableNotificationContent()
                content.title = extra.title
                content.body = extra.body
                content.sound = .default
                content.userInfo = ["route": extra.route]
                let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: extra.date)
                center.add(UNNotificationRequest(identifier: extra.id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
            }
        }
    }
}
