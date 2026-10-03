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

    func sync(_ maps: [MindMap]) {
        let items = Self.isEnabled ? Array(Self.upcoming(in: maps).prefix(Self.limit)) : []
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
        }
    }
}
