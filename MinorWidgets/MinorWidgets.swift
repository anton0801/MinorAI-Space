//
//  MinorWidgets.swift
//  MinorWidgets
//
//  Today: tasks from your maps due today or overdue, on the Home Screen and the Lock Screen.
//  The app writes the data (WidgetSnapshot) whenever maps change; a tap opens the task's map.
//

import SwiftUI
import WidgetKit

struct TodayEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        let snapshot = context.isPreview ? WidgetSnapshot.sample : (WidgetSnapshot.read() ?? .empty)
        completion(TodayEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let entry = TodayEntry(date: Date(), snapshot: WidgetSnapshot.read() ?? .empty)
        // "Today" changes at midnight; the app reloads the widget whenever tasks change.
        let midnight = Calendar.current.startOfDay(for: Date().addingTimeInterval(86_400))
        completion(Timeline(entries: [entry], policy: .after(midnight)))
    }
}

// The widget's few words, in the app's language.
struct WidgetText {
    let ru: Bool
    init(_ snapshot: WidgetSnapshot) { ru = snapshot.language == "ru" }

    var today: String { ru ? "Сегодня" : "Today" }
    var allClear: String { ru ? "Всё сделано" : "All clear" }
    var nothingDue: String { ru ? "На сегодня задач нет" : "Nothing due today" }
    var overdue: String { ru ? "Просрочено" : "Overdue" }
    func due(_ n: Int) -> String { ru ? "К сроку: \(n)" : "\(n) due" }
    func more(_ n: Int) -> String { ru ? "и ещё \(n)" : "and \(n) more" }
}

struct TodayWidgetView: View {
    let entry: TodayEntry
    @Environment(\.widgetFamily) private var family

    private var snapshot: WidgetSnapshot { entry.snapshot }
    private var text: WidgetText { WidgetText(snapshot) }
    private let accent = Color(red: 47 / 255, green: 1, blue: 158 / 255)

    var body: some View {
        content
            .widgetURL(URL(string: "\(SharedContainer.scheme)://today"))
            .modifier(WidgetBackground())
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: snapshot.dueCount == 0 ? "checkmark" : "calendar")
                        .font(.system(size: 12, weight: .semibold))
                    Text(snapshot.dueCount == 0 ? "✓" : "\(snapshot.dueCount)")
                        .font(.system(size: 18, weight: .bold))
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("Minor · \(snapshot.dueCount == 0 ? text.allClear : text.due(snapshot.dueCount))")
                    .font(.headline)
                    .widgetAccentable()
                ForEach(snapshot.tasks.prefix(2)) { task in
                    Text("○ \(task.title)").font(.caption).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .systemSmall:
            small
        default:
            medium
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(accent)
            Text(text.today)
                .font(.system(size: 14, weight: .semibold))
            Spacer(minLength: 0)
            Text(snapshot.dueCount == 0 ? "✓" : "\(snapshot.dueCount)")
                .font(.system(size: 14, weight: .bold).monospacedDigit())
                .foregroundColor(snapshot.dueCount == 0 ? accent : .white)
        }
        .foregroundColor(.white)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            Spacer(minLength: 0)
            if let task = snapshot.tasks.first {
                Text(task.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(3)
                Text(task.map)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
                if snapshot.tasks.count > 1 {
                    Text(text.more(snapshot.dueCount - 1))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(accent)
                }
            } else {
                Text(text.nothingDue)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if snapshot.tasks.isEmpty {
                Spacer(minLength: 0)
                Text(text.nothingDue)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                Spacer(minLength: 0)
            } else {
                ForEach(snapshot.tasks.prefix(3)) { task in
                    Link(destination: URL(string: "\(SharedContainer.scheme)://task/\(task.mapID.uuidString)/\(task.id.uuidString)")!) {
                        row(task)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ task: WidgetSnapshot.Task) -> some View {
        let overdue = task.due.map { $0 < Calendar.current.startOfDay(for: entry.date) } ?? false
        return HStack(spacing: 8) {
            Image(systemName: "circle")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.6))
            VStack(alignment: .leading, spacing: 1) {
                Text(task.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(overdue ? "\(text.overdue) · \(task.map)" : task.map)
                    .font(.system(size: 10))
                    .foregroundColor(overdue ? Color(red: 1, green: 0.41, blue: 0.38) : .white.opacity(0.5))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let due = task.due, !overdue {
                Text(due, style: .time)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }
}

// The dark Minor background; iOS 17 asks widgets to declare it.
struct WidgetBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            content.containerBackground(for: .widget) { Color(red: 0.09, green: 0.09, blue: 0.1) }
        } else {
            content.padding().background(Color(red: 0.09, green: 0.09, blue: 0.1))
        }
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MinorToday", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("Minor · Today")
        .description("Tasks from your maps due today.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}

@main
struct MinorWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
    }
}

extension WidgetSnapshot {
    static let sample = WidgetSnapshot(
        updated: Date(),
        tasks: [
            Task(id: UUID(), mapID: UUID(), title: "Finish the pitch deck", map: "Launch plan", due: Date(), priority: 1),
            Task(id: UUID(), mapID: UUID(), title: "Book tickets", map: "Trip to Lisbon", due: Date(), priority: nil),
            Task(id: UUID(), mapID: UUID(), title: "Review chapter 3", map: "Biology", due: nil, priority: 2),
        ],
        dueCount: 3, doneToday: 1, openCount: 9, language: Locale.current.language.languageCode?.identifier == "ru" ? "ru" : "en"
    )
}
