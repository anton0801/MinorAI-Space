//
//  TodayView.swift
//  Minor Ai
//
//  Tasks from every map in one place: overdue, today, this week, later, and important tasks
//  without a date. A tap opens the map at the task; the circle marks it done.
//

import SwiftUI

struct TaskEntry: Identifiable, Equatable {
    var id: UUID { nodeID }
    let mapID: UUID
    let mapTitle: String
    let nodeID: UUID
    let title: String
    let place: String        // "Map › Branch"
    let due: Date?
    let priority: Int?
    let isDone: Bool
    let icon: String?
}

enum TaskAgenda {
    struct Section: Identifiable, Equatable {
        enum Kind: String { case overdue, today, week, later, important }
        let kind: Kind
        let tasks: [TaskEntry]
        var id: String { kind.rawValue }
    }

    // Every task in the maps (suggestions left out).
    static func tasks(in maps: [MindMap]) -> [TaskEntry] {
        var result: [TaskEntry] = []
        for map in maps {
            func walk(_ node: MindNode, path: [String]) {
                for child in node.children where !child.isSuggestion {
                    if child.isTask {
                        result.append(TaskEntry(
                            mapID: map.id, mapTitle: map.title, nodeID: child.id, title: child.title,
                            place: ([map.title] + path).joined(separator: " › "), due: child.due,
                            priority: child.priority, isDone: child.isDone, icon: child.icon
                        ))
                    }
                    walk(child, path: path + [child.title])
                }
            }
            walk(map.root, path: [])
        }
        return result
    }

    // Open tasks grouped by when they are due. Done tasks show only on the day they were due.
    static func sections(_ tasks: [TaskEntry], now: Date = Date(), calendar: Calendar = .current) -> [Section] {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        let week = calendar.date(byAdding: .day, value: 8, to: today) ?? now
        func sorted(_ list: [TaskEntry]) -> [TaskEntry] {
            list.sorted { a, b in
                if a.isDone != b.isDone { return !a.isDone }
                if let x = a.due, let y = b.due, x != y { return x < y }
                return (a.priority ?? 4) < (b.priority ?? 4)
            }
        }
        let dated = tasks.filter { $0.due != nil }
        let overdue = dated.filter { !$0.isDone && $0.due! < today }
        let dueToday = dated.filter { $0.due! >= today && $0.due! < tomorrow }
        let thisWeek = dated.filter { !$0.isDone && $0.due! >= tomorrow && $0.due! < week }
        let later = dated.filter { !$0.isDone && $0.due! >= week }
        let important = tasks.filter { $0.due == nil && !$0.isDone && ($0.priority ?? 4) <= 2 }
        return [
            Section(kind: .overdue, tasks: sorted(overdue)),
            Section(kind: .today, tasks: sorted(dueToday)),
            Section(kind: .week, tasks: sorted(thisWeek)),
            Section(kind: .important, tasks: sorted(important)),
            Section(kind: .later, tasks: sorted(later)),
        ].filter { !$0.tasks.isEmpty }
    }

    // The number on the Today button: open tasks due today or earlier.
    static func dueCount(in maps: [MindMap], now: Date = Date()) -> Int {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now
        return tasks(in: maps).filter { !$0.isDone && ($0.due.map { $0 < tomorrow } ?? false) }.count
    }
}

struct TodayView: View {
    let theme: AppTheme
    var onOpen: (_ map: UUID, _ node: UUID) -> Void
    var onAsk: () -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = MapStore.shared

    private var tasks: [TaskEntry] { TaskAgenda.tasks(in: store.maps) }
    private var sections: [TaskAgenda.Section] { TaskAgenda.sections(tasks) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    summary
                    if sections.isEmpty {
                        empty
                    }
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(title(section.kind))
                                    .textCase(.uppercase)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(section.kind == .overdue ? MinorColor.dangerText : MinorColor.textTertiary)
                                Spacer()
                                Text("\(section.tasks.filter { !$0.isDone }.count)")
                                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                                    .foregroundColor(MinorColor.textTertiary)
                            }
                            VStack(spacing: 0) {
                                ForEach(section.tasks) { task in
                                    row(task, last: task.id == section.tasks.last?.id)
                                }
                            }
                            .background(RoundedRectangle(cornerRadius: 14).fill(theme.chatRectangle))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.chatStroke, lineWidth: 1))
                        }
                    }
                }
                .padding(20)
            }
            .foregroundColor(MinorColor.textPrimary)
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundColor(MinorColor.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var summary: some View {
        let open = tasks.filter { !$0.isDone }
        let doneToday = tasks.filter { $0.isDone && $0.due.map(Calendar.current.isDateInToday) == true }.count
        let dueToday = tasks.filter { $0.due.map(Calendar.current.isDateInToday) == true }.count
        return VStack(alignment: .leading, spacing: 14) {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.12), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: dueToday == 0 ? 0 : CGFloat(doneToday) / CGFloat(dueToday))
                    .stroke(MinorColor.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(dueToday == 0 ? "—" : "\(doneToday)/\(dueToday)")
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
            }
            .frame(width: 58, height: 58)
            .accessibilityLabel(L("\(doneToday) of \(dueToday) tasks for today done"))
            VStack(alignment: .leading, spacing: 4) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(AppLanguage.current.locale)))
                    .font(.system(size: 20, weight: .bold))
                Text(L("\(open.count) open tasks in \(Set(open.map(\.mapID)).count) maps"))
                    .font(.system(size: 14))
                    .foregroundColor(MinorColor.textSecondary)
            }
            Spacer(minLength: 0)
        }
            Button(action: onAsk) {
                Label("Plan My Day with AI", systemImage: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Capsule().fill(MinorColor.accent))
            }
            .buttonStyle(.plain)
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No tasks yet")
                .font(.system(size: 17, weight: .semibold))
            Text("Make an idea a task in its menu and give it a due date — it shows up here, with a reminder on that day.")
                .font(.system(size: 15))
                .foregroundColor(MinorColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(theme.chatRectangle))
    }

    private func row(_ task: TaskEntry, last: Bool) -> some View {
        HStack(spacing: 12) {
            Button { toggle(task) } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(task.isDone ? MinorColor.accent : MinorColor.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isDone ? "Mark as Not Done" : "Mark as Done")
            Button {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onOpen(task.mapID, task.nodeID) }
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            if let priority = task.priority {
                                Text("\(priority)")
                                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                                    .foregroundColor(.black)
                                    .frame(width: 15, height: 15)
                                    .background(Circle().fill(priority == 1 ? Color(hex: "#FF6B6B") : priority == 2 ? Color(hex: "#FFD66B") : Color(hex: "#7CC4FF")))
                            }
                            Text((task.icon.map { "\($0) " } ?? "") + task.title)
                                .font(.system(size: 16))
                                .strikethrough(task.isDone)
                                .foregroundColor(task.isDone ? MinorColor.textTertiary : MinorColor.textPrimary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        Text(task.place)
                            .font(.system(size: 12))
                            .foregroundColor(MinorColor.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    if let due = task.due {
                        VStack(alignment: .trailing, spacing: 2) {
                            DueLabel(date: due)
                            Text(due.formatted(date: .omitted, time: .shortened))
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundColor(MinorColor.textTertiary)
                        }
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(MinorColor.textChevron)
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.trailing, 14)
        .overlay(alignment: .bottom) {
            if !last { Rectangle().fill(theme.chatStroke).frame(height: 1).padding(.leading, 56) }
        }
    }

    private func toggle(_ task: TaskEntry) {
        Haptics.selection()
        store.update(task.mapID) { $0.root.update(task.nodeID) { $0.isDone.toggle() } }
    }

    private func title(_ kind: TaskAgenda.Section.Kind) -> String {
        switch kind {
        case .overdue: return L("Overdue")
        case .today: return L("Today")
        case .week: return L("Next 7 Days")
        case .later: return L("Later")
        case .important: return L("Important, No Date")
        }
    }
}
