//
//  TodayView.swift
//  Minor Ai
//
//  Tasks from every map in one place: overdue, today, the next seven days, important ones without a
//  date, later, and the rest without a date (folded). A tap on a task opens its details (status,
//  date, reminder, the way to its idea); the box beside it marks it done, with Undo, and the row
//  moves to the done ones only after a moment. With nothing for today it says so and shows what
//  comes next; with no tasks at all it explains how to make one.
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
        enum Kind: String { case overdue, today, week, later, important, undated }
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
    // Tasks in `keep` were just ticked: they stay where they were for a moment.
    static func sections(_ tasks: [TaskEntry], now: Date = Date(), calendar: Calendar = .current, keep: Set<UUID> = []) -> [Section] {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        let week = calendar.date(byAdding: .day, value: 8, to: today) ?? now
        func open(_ task: TaskEntry) -> Bool { !task.isDone || keep.contains(task.id) }
        func sorted(_ list: [TaskEntry]) -> [TaskEntry] {
            list.sorted { a, b in
                if open(a) != open(b) { return open(a) }
                if let x = a.due, let y = b.due, x != y { return x < y }
                return (a.priority ?? 4) < (b.priority ?? 4)
            }
        }
        let dated = tasks.filter { $0.due != nil }
        let overdue = dated.filter { open($0) && $0.due! < today }
        let dueToday = dated.filter { $0.due! >= today && $0.due! < tomorrow }
        let thisWeek = dated.filter { open($0) && $0.due! >= tomorrow && $0.due! < week }
        let later = dated.filter { open($0) && $0.due! >= week }
        let important = tasks.filter { $0.due == nil && open($0) && ($0.priority ?? 4) <= 2 }
        // Never counted as today's: listed last, folded until opened.
        let undated = tasks.filter { $0.due == nil && open($0) && ($0.priority ?? 4) > 2 }
        return [
            Section(kind: .overdue, tasks: sorted(overdue)),
            Section(kind: .today, tasks: sorted(dueToday)),
            Section(kind: .week, tasks: sorted(thisWeek)),
            Section(kind: .important, tasks: sorted(important)),
            Section(kind: .later, tasks: sorted(later)),
            Section(kind: .undated, tasks: sorted(undated)),
        ].filter { !$0.tasks.isEmpty }
    }

    // The nearest open task after today, for "Coming Up" when nothing is due today.
    static func next(_ tasks: [TaskEntry], now: Date = Date(), calendar: Calendar = .current) -> TaskEntry? {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return tasks.filter { !$0.isDone && ($0.due.map { $0 >= tomorrow } ?? false) }.min { $0.due! < $1.due! }
    }

    // Done tasks that aren't today's (today's stay in Today), the latest due first.
    static func completed(_ tasks: [TaskEntry], now: Date = Date(), calendar: Calendar = .current) -> [TaskEntry] {
        tasks.filter { $0.isDone && !($0.due.map { calendar.isDate($0, inSameDayAs: now) } ?? false) }
            .sorted { ($0.due ?? .distantPast) > ($1.due ?? .distantPast) }
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
    var onStudy: (_ map: UUID) -> Void = { _ in }
    var onOpenMaps: () -> Void = {}
    // Pushed inside the menu's stack (large title, Back) instead of shown as its own sheet.
    var embedded = false

    @ObservedObject private var study = StudyStore.shared

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var store = MapStore.shared
    @State private var viewOnlyNotice = false
    @State private var showUndated = false
    @State private var showCompleted = false
    @State private var showWeek = false
    @State private var now = Date()
    @State private var settling: Set<UUID> = []
    @State private var doneToast: DoneToast?
    @State private var detail: TaskEntry?

    private struct DoneToast: Equatable {
        let task: TaskEntry
        let token = UUID()
    }

    private var tasks: [TaskEntry] { TaskAgenda.tasks(in: store.maps) }

    var body: some View {
        if embedded {
            content
                .navigationBarTitleDisplayMode(.large)
        } else {
            NavigationStack {
                content
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { dismiss() }.foregroundColor(MinorColor.accent)
                        }
                    }
            }
            .preferredColorScheme(.dark)
        }
    }

    // As a sheet it closes first; inside the menu the map opens on top and Back returns here.
    private func leave(then action: @escaping () -> Void) {
        guard !embedded else { return action() }
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: action)
    }

    private var content: some View {
        let all = tasks
        let sections = TaskAgenda.sections(all, now: now, keep: settling)
        let todays = sections.filter { $0.kind == .overdue || $0.kind == .today }
        let openToday = todays.flatMap(\.tasks).filter { !$0.isDone || settling.contains($0.id) }
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header(all, planning: !todays.isEmpty)
                    if all.isEmpty {
                        emptyHero(L("No tasks yet"), L("Select an idea on a map and tap Task to make it one. Tasks with a date show up here."), week: nil)
                    } else if todays.isEmpty {
                        emptyHero(L("No tasks for today"), L("You can go back to a project or look at the plans for the week."), week: sections.isEmpty || showWeek ? nil : {
                            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .minorMenu) { showWeek = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                withAnimation { proxy.scrollTo(sections.first?.id, anchor: .top) }
                            }
                        })
                        if let next = TaskAgenda.next(all, now: now) { comingUp(next) }
                    } else if openToday.isEmpty {
                        allDone
                    }
                    reviews
                    if !todays.isEmpty || showWeek {
                        ForEach(sections) { section in
                            sectionView(section).id(section.id)
                        }
                    }
                    if showCompleted { completed(all) }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, doneToast == nil ? 24 : 80)
            }
        }
        .foregroundColor(MinorColor.textPrimary)
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("Today")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Toggle(isOn: $showCompleted.animation(.minorMenu)) { Label("Show Completed", systemImage: "checkmark.circle") }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(MinorColor.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                .accessibilityLabel("Filter")
                .accessibilityIdentifier("today.filter")
            }
        }
        .overlay(alignment: .bottom) { toastView }
        .animation(.minorMenu, value: doneToast)
        .sheet(item: $detail) { task in
            TaskDetailSheet(mapID: task.mapID, nodeID: task.nodeID, theme: theme, onOpenNode: { open(task) })
                .presentationDetents([.large])
        }
        .alert("View only", isPresented: $viewOnlyNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This map is shared with you to view. The owner can make you an editor.")
        }
        // The day turned (midnight, a new time zone, back from the background): sections follow it.
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in now = Date() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in now = Date() }
        .onChange(of: scenePhase) { phase in if phase == .active { now = Date() } }
        .onAppear {
            now = Date()
            Telemetry.log("today_open", ["tasks": tasks.filter { !$0.isDone }.count])
        }
    }

    // The date, today's progress (only tasks due today) and planning with Minor.
    private func header(_ all: [TaskEntry], planning: Bool) -> some View {
        let calendar = Calendar.current
        let dueToday = all.filter { $0.due.map { calendar.isDate($0, inSameDayAs: now) } == true }
        let doneToday = dueToday.filter(\.isDone).count
        return VStack(alignment: .leading, spacing: 10) {
            Text(now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(AppLanguage.current.locale)).capitalizedFirst)
                .minorFont(19, maxScale: 1.4)
                .foregroundColor(MinorColor.textSecondary)
            if !dueToday.isEmpty {
                Text(L("\(doneToday) of \(dueToday.count) tasks for today done"))
                    .minorFont(15, maxScale: 1.4)
                    .foregroundColor(MinorColor.textTertiary)
            }
            if planning {
                Button(action: onAsk) {
                    Label("Plan with Minor", systemImage: "calendar")
                        .minorFont(17, .medium, maxScale: 1.3)
                        .foregroundColor(MinorColor.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.7), lineWidth: 1.2))
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressScale())
                .padding(.top, 6)
            }
        }
    }

    private func sectionView(_ section: TaskAgenda.Section) -> some View {
        let main = section.kind == .overdue || section.kind == .today
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title(section.kind))
                    .minorFont(22, .bold, maxScale: 1.3)
                    .foregroundColor(main ? MinorColor.textPrimary : MinorColor.textSecondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if section.kind == .undated {
                    Button(showUndated ? L("Hide") : L("Show \(section.tasks.count)")) {
                        withAnimation(.minorMenu) { showUndated.toggle() }
                    }
                    .minorFont(15, .semibold, maxScale: 1.3)
                    .foregroundColor(MinorColor.accent)
                    .frame(minHeight: 44)
                }
            }
            if section.kind != .undated || showUndated {
                ForEach(section.tasks) { task in
                    row(task, section.kind)
                }
            }
        }
    }

    private func row(_ task: TaskEntry, _ kind: TaskAgenda.Section.Kind) -> some View {
        let done = task.isDone
        return HStack(spacing: 6) {
            Button { toggle(task) } label: {
                ZStack {
                    if done {
                        Circle().fill(MinorColor.accent)
                        Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundColor(.black)
                    } else {
                        RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(MinorColor.textSecondary, lineWidth: 2)
                    }
                }
                .frame(width: 26, height: 26)
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(done ? L("Mark “\(task.title)” as not done") : L("Mark “\(task.title)” as done"))
            Button { detail = task } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            if let priority = task.priority {
                                Text("\(priority)")
                                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                                    .foregroundColor(.black)
                                    .frame(width: 15, height: 15)
                                    .background(Circle().fill(priority == 1 ? Color(hex: "#FF6B6B") : priority == 2 ? Color(hex: "#FFD66B") : Color(hex: "#7CC4FF")))
                                    .accessibilityLabel(L("Priority \(priority)"))
                            }
                            Text((task.icon.map { "\($0) " } ?? "") + (task.title.isEmpty ? L("Untitled") : task.title))
                                .minorFont(16, .medium, maxScale: 1.4)
                                .strikethrough(done)
                                .foregroundColor(done ? MinorColor.textTertiary : MinorColor.textPrimary)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                        }
                        Text(subtitle(task, kind))
                            .minorFont(13, maxScale: 1.4)
                            .foregroundColor(kind == .overdue && !done ? BranchColor.coral.color : MinorColor.textSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(MinorColor.textChevron)
                }
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the task’s details")
            .accessibilityAction(named: Text("Open in Map")) { open(task) }
            .contextMenu {
                Button { detail = task } label: { Label("Task Details", systemImage: "info.circle") }
                Button { open(task) } label: { Label("Open in Map", systemImage: "point.3.connected.trianglepath.dotted") }
            }
        }
        .padding(.trailing, 14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(theme.chatRectangle))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(theme.chatStroke, lineWidth: 1))
    }

    // "Yesterday · Launch plan", "14:00 · Launch plan", "Friday · Launch plan".
    private func subtitle(_ task: TaskEntry, _ kind: TaskAgenda.Section.Kind) -> String {
        let calendar = Calendar.current
        let locale = AppLanguage.current.locale
        var parts: [String] = []
        if let due = task.due {
            switch kind {
            case .overdue:
                parts.append(calendar.isDateInYesterday(due) ? L("Yesterday") : due.formatted(.dateTime.day().month(.wide).locale(locale)))
            case .today:
                parts.append(due.formatted(.dateTime.hour().minute().locale(locale)))
            case .week:
                parts.append(calendar.isDateInTomorrow(due) ? L("Tomorrow") : due.formatted(.dateTime.weekday(.wide).locale(locale)).capitalizedFirst)
            default:
                parts.append(due.formatted(.dateTime.day().month(.wide).locale(locale)))
            }
        }
        parts.append(task.mapTitle)
        return parts.joined(separator: " · ")
    }

    // Nothing for today: what to do instead, and the nearest task when there is one.
    private func emptyHero(_ title: String, _ text: String, week: (() -> Void)?) -> some View {
        VStack(spacing: 14) {
            TodayEmptyArt()
                .frame(height: 170)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            Text(title)
                .minorFont(25, .bold, maxScale: 1.3)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(text)
                .minorFont(16, maxScale: 1.4)
                .foregroundColor(MinorColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button { leave(then: onOpenMaps) } label: {
                Text("Open Maps")
                    .minorFont(17, .semibold, maxScale: 1.3)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Capsule().fill(Color.white))
            }
            .buttonStyle(PressScale())
            .padding(.top, 6)
            .padding(.horizontal, 16)
            if let week {
                Button("See the Week", action: week)
                    .minorFont(16, .medium, maxScale: 1.3)
                    .foregroundColor(MinorColor.textSecondary)
                    .frame(minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func comingUp(_ task: TaskEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Coming Up")
                .minorFont(20, .bold, maxScale: 1.3)
                .accessibilityAddTraits(.isHeader)
            Button { detail = task } label: {
                HStack(spacing: 14) {
                    Group {
                        if let icon = task.icon {
                            Text(icon).font(.system(size: 20))
                        } else {
                            Image(systemName: "calendar").font(.system(size: 18)).foregroundColor(BranchColor.lilac.color)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .overlay(Circle().stroke(BranchColor.lilac.color, lineWidth: 1.5))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.title.isEmpty ? L("Untitled") : task.title)
                            .minorFont(17, .medium, maxScale: 1.4)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(subtitle(task, .week))
                            .minorFont(14, maxScale: 1.4)
                            .foregroundColor(MinorColor.textSecondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundColor(MinorColor.textChevron)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.04)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the task’s details")
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22).fill(theme.chatRectangle))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(theme.chatStroke, lineWidth: 1))
    }

    // Everything due today is done.
    private var allDone: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 28))
                .foregroundColor(MinorColor.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text("All done for today").minorFont(18, .semibold, maxScale: 1.3)
                Text("The completed tasks stay below until tomorrow.")
                    .minorFont(14, maxScale: 1.4)
                    .foregroundColor(MinorColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(theme.chatRectangle))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func completed(_ all: [TaskEntry]) -> some View {
        let done = TaskAgenda.completed(all, now: now)
        VStack(alignment: .leading, spacing: 8) {
            Text("Completed")
                .minorFont(22, .bold, maxScale: 1.3)
                .foregroundColor(MinorColor.textSecondary)
                .accessibilityAddTraits(.isHeader)
            if done.isEmpty {
                Text("No other completed tasks.")
                    .minorFont(15, maxScale: 1.4)
                    .foregroundColor(MinorColor.textTertiary)
            }
            ForEach(done) { task in row(task, .later) }
        }
    }

    // Flashcards due for review, by map.
    @ViewBuilder
    private var reviews: some View {
        let due = study.reviews(in: store.maps)
        if !due.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Review")
                    .minorFont(22, .bold, maxScale: 1.3)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) {
                    ForEach(due, id: \.map.id) { item in
                        Button {
                            leave { onStudy(item.map.id) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "rectangle.on.rectangle.angled")
                                    .foregroundColor(Color(hex: "#7CC4FF"))
                                    .frame(width: 44, height: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.map.title).minorFont(16, maxScale: 1.4).lineLimit(2)
                                    Text(L("\(item.count) cards to review")).minorFont(13, maxScale: 1.4).foregroundColor(MinorColor.textTertiary)
                                }
                                Spacer()
                                Text("Review")
                                    .minorFont(14, .semibold, maxScale: 1.2)
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 12)
                                    .frame(minHeight: 32)
                                    .background(Capsule().fill(MinorColor.accent))
                            }
                            .padding(.trailing, 12)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 16).fill(theme.chatRectangle))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.chatStroke, lineWidth: 1))
            }
        }
    }

    // "Done · Undo" after a tick; the row moves to the done ones a moment later.
    @ViewBuilder
    private var toastView: some View {
        if let toast = doneToast {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill").foregroundColor(MinorColor.accent)
                Text("Done").minorFont(15, maxScale: 1.3)
                Button("Undo") { undo(toast.task) }
                    .minorFont(15, .semibold, maxScale: 1.3)
                    .foregroundColor(MinorColor.accent)
                    .frame(minHeight: 44)
            }
            .foregroundColor(MinorColor.textPrimary)
            .padding(.horizontal, 18)
            .background(Capsule().fill(theme.chatRectangle))
            .overlay(Capsule().stroke(theme.chatStroke, lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 14, y: 4)
            .padding(.bottom, 12)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private func open(_ task: TaskEntry) {
        leave { onOpen(task.mapID, task.nodeID) }
    }

    private func toggle(_ task: TaskEntry) {
        // A shared map the person can only view: their tick would never reach the others.
        if store.map(task.mapID)?.collab?.canEdit == false {
            Haptics.error()
            viewOnlyNotice = true
            return
        }
        let done = !task.isDone
        done ? Haptics.success() : Haptics.selection()
        // Kept where it is for a moment, so the row doesn't jump away under the finger.
        if done { settling.insert(task.id) } else { settling.remove(task.id) }
        store.update(task.mapID) { $0.root.update(task.nodeID) { $0.isDone = done } }
        guard done else { return }
        let toast = DoneToast(task: task)
        doneToast = toast
        UIAccessibility.post(notification: .announcement, argument: L("Done"))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .minorMenu) { _ = settling.remove(task.id) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if doneToast == toast { doneToast = nil }
        }
    }

    private func undo(_ task: TaskEntry) {
        doneToast = nil
        settling.remove(task.id)
        guard store.map(task.mapID)?.root.node(task.nodeID) != nil else { return }
        store.update(task.mapID) { $0.root.update(task.nodeID) { $0.isDone = false } }
    }

    private func title(_ kind: TaskAgenda.Section.Kind) -> String {
        switch kind {
        case .overdue: return L("Overdue")
        case .today: return L("Today")
        case .week: return L("This Week")
        case .later: return L("Later")
        case .important: return L("Important, No Date")
        case .undated: return L("No Due Date")
        }
    }
}

// A calendar with a tick, joined to three ideas: the picture for a day without tasks.
private struct TodayEmptyArt: View {
    var body: some View {
        Canvas { ctx, size in
            let w: CGFloat = 112, h: CGFloat = 100
            let rect = CGRect(x: size.width / 2 - w / 2, y: size.height / 2 - h / 2 + 6, width: w, height: h)
            func branch(from a: CGPoint, to b: CGPoint, _ color: Color) {
                var path = Path()
                path.move(to: a)
                let mid = (a.x + b.x) / 2
                path.addCurve(to: b, control1: CGPoint(x: mid, y: a.y), control2: CGPoint(x: mid, y: b.y))
                ctx.stroke(path, with: .color(color), lineWidth: 2)
                ctx.fill(Path(ellipseIn: CGRect(x: b.x - 6, y: b.y - 6, width: 12, height: 12)), with: .color(Color(white: 0.06)))
                ctx.stroke(Path(ellipseIn: CGRect(x: b.x - 6, y: b.y - 6, width: 12, height: 12)), with: .color(color), lineWidth: 2)
            }
            branch(from: CGPoint(x: rect.minX, y: rect.minY + 30), to: CGPoint(x: rect.minX - 62, y: rect.minY - 22), BranchColor.mint.color)
            branch(from: CGPoint(x: rect.maxX, y: rect.midY + 2), to: CGPoint(x: rect.maxX + 66, y: rect.minY + 2), BranchColor.lilac.color)
            branch(from: CGPoint(x: rect.maxX, y: rect.midY + 22), to: CGPoint(x: rect.maxX + 56, y: rect.maxY + 14), BranchColor.sky.color)
            let body = Path(roundedRect: rect, cornerRadius: 14)
            ctx.fill(body, with: .color(Color(white: 0.08)))
            ctx.stroke(body, with: .color(Color.white.opacity(0.75)), lineWidth: 2)
            var bar = Path()
            bar.move(to: CGPoint(x: rect.minX, y: rect.minY + 22))
            bar.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + 22))
            ctx.stroke(bar, with: .color(Color.white.opacity(0.75)), lineWidth: 2)
            for x in [rect.minX + 30, rect.maxX - 30] {
                let ring = Path(roundedRect: CGRect(x: x - 4, y: rect.minY - 9, width: 8, height: 18), cornerRadius: 4)
                ctx.fill(ring, with: .color(Color(white: 0.08)))
                ctx.stroke(ring, with: .color(Color.white.opacity(0.75)), lineWidth: 2)
            }
            for row in 0..<3 {
                for col in 0..<5 {
                    let cell = CGRect(x: rect.minX + 12 + CGFloat(col) * 18, y: rect.minY + 32 + CGFloat(row) * 20, width: 12, height: 12)
                    ctx.fill(Path(roundedRect: cell, cornerRadius: 2), with: .color(Color.white.opacity(0.08)))
                }
            }
            let center = CGPoint(x: rect.midX, y: rect.midY + 12)
            let circle = Path(ellipseIn: CGRect(x: center.x - 21, y: center.y - 21, width: 42, height: 42))
            ctx.fill(circle, with: .color(Color(white: 0.08)))
            ctx.stroke(circle, with: .color(BranchColor.mint.color), lineWidth: 2.5)
            var tick = Path()
            tick.move(to: CGPoint(x: center.x - 9, y: center.y))
            tick.addLine(to: CGPoint(x: center.x - 2, y: center.y + 7))
            tick.addLine(to: CGPoint(x: center.x + 10, y: center.y - 7))
            ctx.stroke(tick, with: .color(BranchColor.mint.color), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
    }
}

private extension String {
    // "вторник, 13 октября" → "Вторник, 13 октября".
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
