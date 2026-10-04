//
//  CalendarSync.swift
//  Minor Ai
//
//  Settings → Tasks in Calendar: tasks with a due date appear in a "Minor AI" calendar and
//  follow the maps — a new date moves the event, a done or deleted task removes it.
//

import Combine
import EventKit
import Foundation

@MainActor
final class CalendarSync {
    static let shared = CalendarSync()

    private let store = EKEventStore()
    private var subscription: AnyCancellable?
    private let calendarKey = "calendarSync.calendarID"
    private let eventsKey = "calendarSync.events"     // idea id → event id

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "calendarSync") }
        set { UserDefaults.standard.set(newValue, forKey: "calendarSync") }
    }

    func start() {
        guard subscription == nil else { return }
        subscription = MapStore.shared.$maps
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] maps in
                guard Self.isEnabled else { return }
                self?.sync(maps)
            }
    }

    // Asks for calendar access, then turns the sync on. Returns whether it is on.
    func enable() async -> Bool {
        let granted: Bool
        if #available(iOS 17.0, *) {
            granted = (try? await store.requestFullAccessToEvents()) ?? false
        } else {
            granted = await withCheckedContinuation { continuation in
                store.requestAccess(to: .event) { ok, _ in continuation.resume(returning: ok) }
            }
        }
        Self.isEnabled = granted
        if granted { sync(MapStore.shared.maps) }
        return granted
    }

    // Removes Minor's events and stops.
    func disable() {
        Self.isEnabled = false
        if let calendar = minorCalendar(create: false) {
            try? store.removeCalendar(calendar, commit: true)
        }
        UserDefaults.standard.removeObject(forKey: calendarKey)
        UserDefaults.standard.removeObject(forKey: eventsKey)
    }

    private var hasAccess: Bool {
        if #available(iOS 17.0, *) { return EKEventStore.authorizationStatus(for: .event) == .fullAccess }
        return EKEventStore.authorizationStatus(for: .event) == .authorized
    }

    private func minorCalendar(create: Bool) -> EKCalendar? {
        if let id = UserDefaults.standard.string(forKey: calendarKey), let calendar = store.calendar(withIdentifier: id) {
            return calendar
        }
        guard create else { return nil }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = "Minor AI"
        calendar.cgColor = CGColor(red: 0.18, green: 1, blue: 0.62, alpha: 1)
        // iCloud when there is one, so the events show on every device; otherwise on this iPhone.
        calendar.source = store.sources.first { $0.sourceType == .calDAV && $0.title.lowercased().contains("icloud") }
            ?? store.defaultCalendarForNewEvents?.source
            ?? store.sources.first { $0.sourceType == .local }
        guard calendar.source != nil, (try? store.saveCalendar(calendar, commit: true)) != nil else { return nil }
        UserDefaults.standard.set(calendar.calendarIdentifier, forKey: calendarKey)
        return calendar
    }

    func sync(_ maps: [MindMap]) {
        guard Self.isEnabled, hasAccess, let calendar = minorCalendar(create: true) else { return }
        var events = (UserDefaults.standard.dictionary(forKey: eventsKey) as? [String: String]) ?? [:]
        var wanted: [String: (title: String, map: String, due: Date, url: URL?)] = [:]
        for map in maps {
            func walk(_ node: MindNode) {
                if node.isTask, !node.isDone, !node.isSuggestion, let due = node.due {
                    wanted[node.id.uuidString] = (node.title, map.title, due, URL(string: "minorai://task/\(map.id.uuidString)/\(node.id.uuidString)"))
                }
                node.children.forEach(walk)
            }
            walk(map.root)
        }
        // Remove events of tasks that are done, undated or gone.
        for (node, eventID) in events where wanted[node] == nil {
            if let event = store.event(withIdentifier: eventID) { try? store.remove(event, span: .thisEvent, commit: false) }
            events[node] = nil
        }
        // Add or update the rest.
        for (node, task) in wanted {
            let event = events[node].flatMap(store.event(withIdentifier:)) ?? EKEvent(eventStore: store)
            let end = task.due.addingTimeInterval(30 * 60)
            guard event.title != task.title || event.startDate != task.due || event.calendar != calendar || event.notes != task.map else { continue }
            event.calendar = calendar
            event.title = task.title
            event.startDate = task.due
            event.endDate = end
            event.notes = task.map
            event.url = task.url
            if (try? store.save(event, span: .thisEvent, commit: false)) != nil { events[node] = event.eventIdentifier }
        }
        try? store.commit()
        UserDefaults.standard.set(events, forKey: eventsKey)
    }
}
