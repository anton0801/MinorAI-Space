//
//  WidgetBridge.swift
//  Minor Ai
//
//  Writes the Today widget's data to the app group whenever maps change, and asks iOS to
//  redraw the widget.
//

import Combine
import Foundation
import WidgetKit

@MainActor
final class WidgetBridge {
    static let shared = WidgetBridge()

    private var subscription: AnyCancellable?
    private var last: WidgetSnapshot?

    func start() {
        guard subscription == nil else { return }
        subscription = MapStore.shared.$maps
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] maps in self?.write(maps) }
    }

    // Tasks ticked in the widget since the app was last open.
    func applyTicks() {
        let ticks = WidgetTicks.pending()
        guard !ticks.isEmpty else { return }
        WidgetTicks.clear()
        // Not on shared maps the person can only view.
        for tick in ticks where MapStore.shared.map(tick.mapID)?.collab?.canEdit != false {
            MapStore.shared.update(tick.mapID) { map in
                map.root.update(tick.nodeID) { $0.isDone = true }
            }
        }
    }

    // The language or the day changed: write again even if the tasks did not.
    func refresh() {
        applyTicks()
        last = nil
        write(MapStore.shared.maps)
    }

    static func snapshot(of maps: [MindMap], now: Date = Date(), language: String) -> WidgetSnapshot {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let tasks = TaskAgenda.tasks(in: maps)
        let due = tasks
            .filter { !$0.isDone && ($0.due.map { $0 < tomorrow } ?? false) }
            .sorted { ($0.due ?? .distantFuture, $0.priority ?? 4) < ($1.due ?? .distantFuture, $1.priority ?? 4) }
        return WidgetSnapshot(
            updated: now,
            tasks: due.prefix(6).map { WidgetSnapshot.Task(id: $0.nodeID, mapID: $0.mapID, title: $0.title, map: $0.mapTitle, due: $0.due, priority: $0.priority) },
            dueCount: due.count,
            doneToday: tasks.filter { $0.isDone && ($0.due.map(calendar.isDateInToday) ?? false) }.count,
            openCount: tasks.filter { !$0.isDone }.count,
            language: language
        )
    }

    private func write(_ maps: [MindMap]) {
        var snapshot = Self.snapshot(of: maps, language: AppLanguage.current.code == "ru" ? "ru" : "en")
        if var previous = last {
            previous.updated = snapshot.updated
            if previous == snapshot { return }
        }
        last = snapshot
        snapshot.updated = Date()
        guard let file = SharedContainer.widgetFile, let data = try? SharedContainer.encoder.encode(snapshot) else { return }
        try? data.write(to: file, options: .atomic)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
