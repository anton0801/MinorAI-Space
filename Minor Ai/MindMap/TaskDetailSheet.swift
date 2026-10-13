//
//  TaskDetailSheet.swift
//  Minor Ai
//
//  One task: its status, its due date as a draft (Today / Tomorrow / No Date, date and time) that
//  counts only with "Save Date", the way to its idea on the map, and what will happen with the
//  reminder — said by the real state: permission not asked yet, refused in Settings, reminders off
//  in the app, scheduled (checked after saving), or a scheduling error with a retry. The task's
//  status is changed apart from the date; "No Date" removes the date and its reminder, not the
//  task. Used from Today and from the selected idea on a map.
//

import SwiftUI
import UserNotifications

struct TaskDetailSheet: View {
    let mapID: UUID
    let nodeID: UUID
    let theme: AppTheme
    var onOpenNode: (() -> Void)?       // nil when the map is already open at this idea

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @ObservedObject private var store = MapStore.shared
    @State private var draft: Date?
    @State private var started = false
    @State private var editingDate = false
    @State private var editingTime = false
    @State private var permission: UNAuthorizationStatus = .notDetermined
    @State private var scheduled: Bool?           // checked after saving
    @State private var leaving = false

    private var map: MindMap? { store.map(mapID) }
    private var node: MindNode? { map?.root.node(nodeID) }
    private var canEdit: Bool { map?.collab?.canEdit != false }
    private var saved: Date? { node?.due }
    private var changed: Bool { draft != saved }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let node {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(node.title.isEmpty ? L("Untitled") : node.title)
                            .minorFont(30, .bold, maxScale: 1.3)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.bottom, 6)
                        statusRow(node)
                        dateRows
                        if canEdit { quickChoices }
                        reminderCard
                        if let onOpenNode {
                            row(icon: "point.3.connected.trianglepath.dotted", title: L("Open Idea in the Map"), value: nil) {
                                if changed { leaving = true } else { open(onOpenNode) }
                            }
                        }
                        if !canEdit {
                            Label("This map is shared with you to view, so the task can’t be changed here.", systemImage: "eye")
                                .minorFont(13, maxScale: 1.3)
                                .foregroundColor(MinorColor.textTertiary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                } else {
                    Text("This task isn’t on the map any more.")
                        .minorFont(16, maxScale: 1.3)
                        .foregroundColor(MinorColor.textSecondary)
                        .padding(24)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if node != nil, canEdit {
                    Button(action: save) {
                        Text("Save Date")
                            .minorFont(17, .semibold, maxScale: 1.3)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white))
                    }
                    .buttonStyle(PressScale())
                    .disabled(!changed)
                    .opacity(changed ? 1 : 0.45)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(theme.background.opacity(0.96).ignoresSafeArea())
                }
            }
            .foregroundColor(MinorColor.textPrimary)
            .background(theme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // As the design: "Task" and where it is, at the left.
                ToolbarItem(placement: .navigationBarLeading) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Task").minorFont(19, .semibold, maxScale: 1.2)
                        Text(place).minorFont(12, maxScale: 1.2).foregroundColor(MinorColor.textSecondary).lineLimit(1)
                    }
                    .padding(.leading, 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.white.opacity(0.1)))
                    }
                    .accessibilityLabel("Close")
                }
            }
            .confirmationDialog("Save the new date?", isPresented: $leaving, titleVisibility: .visible) {
                Button("Save and Open") { save(); if let onOpenNode { open(onOpenNode) } }
                Button("Open Without Saving", role: .destructive) { if let onOpenNode { open(onOpenNode) } }
                Button("Stay", role: .cancel) {}
            }
        }
        .tint(.white)
        .preferredColorScheme(.dark)
        .onAppear {
            guard !started else { return }
            started = true
            draft = saved
            readPermission()
        }
        // Back from Settings: the permission may have changed.
        .onChange(of: scenePhase) { phase in if phase == .active { readPermission() } }
    }

    // MARK: Pieces

    private var place: String {
        let path = map?.root.path(to: nodeID)?.dropLast().map(\.title) ?? []
        return path.suffix(2).joined(separator: " › ")
    }

    private func statusRow(_ node: MindNode) -> some View {
        Button {
            guard canEdit else { return }
            Haptics.selection()
            store.update(mapID) { $0.root.update(nodeID) { $0.isDone.toggle() } }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: node.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 26))
                    .foregroundColor(node.isDone ? MinorColor.accent : MinorColor.textSecondary)
                Text(node.isDone ? L("Done") : L("Not done"))
                    .minorFont(18, .semibold, maxScale: 1.3)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundColor(MinorColor.textTertiary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 60)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(node.isDone ? "Marks the task as not done" : "Marks the task as done")
        .disabled(!canEdit)
    }

    @ViewBuilder
    private var dateRows: some View {
        let locale = AppLanguage.current.locale
        row(icon: "calendar", title: L("Date"), value: draft.map { $0.formatted(.dateTime.day().month(.wide).locale(locale)) } ?? L("No date")) {
            guard canEdit else { return }
            if draft == nil { draft = DueDateSheet.morning(daysFromNow: 1) }
            withAnimation(.minorMenu) { editingDate.toggle(); editingTime = false }
        }
        if editingDate, let date = draft {
            DatePicker("Date", selection: Binding(get: { date }, set: { draft = $0 }), displayedComponents: [.date])
                .datePickerStyle(.graphical)
                .tint(MinorColor.accent)
                .labelsHidden()
                .environment(\.locale, locale)
        }
        if let date = draft {
            row(icon: "clock", title: L("Time"), value: date.formatted(.dateTime.hour().minute().locale(locale))) {
                guard canEdit else { return }
                withAnimation(.minorMenu) { editingTime.toggle(); editingDate = false }
            }
            if editingTime {
                DatePicker("Time", selection: Binding(get: { date }, set: { draft = $0 }), displayedComponents: [.hourAndMinute])
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .environment(\.locale, locale)
            }
        }
    }

    private var quickChoices: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { chips }
            VStack(spacing: 8) { chips }
        }
    }

    @ViewBuilder
    private var chips: some View {
        chip(L("Today"), DueDateSheet.later(today: true))
        chip(L("Tomorrow"), DueDateSheet.morning(daysFromNow: 1))
        chip(L("No Date"), nil)
    }

    private func chip(_ title: String, _ date: Date?) -> some View {
        let chosen = date.map { d in draft.map { Calendar.current.isDate($0, inSameDayAs: d) } ?? false } ?? (draft == nil)
        return Button {
            Haptics.selection()
            draft = date
            editingDate = false
            editingTime = false
        } label: {
            Text(title)
                .minorFont(15, .medium, maxScale: 1.3)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 12).fill(chosen ? MinorColor.accent.opacity(0.18) : Color.white.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(chosen ? MinorColor.accent : Color.white.opacity(0.08), lineWidth: chosen ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    // What happens with the reminder, by the real state of things.
    @ViewBuilder
    private var reminderCard: some View {
        if draft != nil || saved != nil {
            let state = reminderState
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: state.icon)
                    .font(.system(size: 22))
                    .foregroundColor(state.problem ? MinorColor.textSecondary : MinorColor.accent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.title).minorFont(16, .semibold, maxScale: 1.3)
                    if let detail = state.detail {
                        Text(detail)
                            .minorFont(14, maxScale: 1.3)
                            .foregroundColor(MinorColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let action = state.action {
                        Button(action.0, action: action.1)
                            .minorFont(15, .semibold, maxScale: 1.3)
                            .foregroundColor(MinorColor.accent)
                            .frame(minHeight: 36)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
            .accessibilityElement(children: .combine)
        }
    }

    private struct ReminderState {
        var icon: String
        var title: String
        var detail: String?
        var action: (String, () -> Void)?
        var problem: Bool
    }

    private var reminderState: ReminderState {
        switch permission {
        case .denied:
            return ReminderState(icon: "bell.slash", title: L("Notifications are off"), detail: L("The date is kept. The reminder won’t come."),
                                 action: (L("Open Settings"), { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }), problem: true)
        case .notDetermined:
            return ReminderState(icon: "bell", title: L("Reminders aren’t allowed yet"), detail: L("The date is kept either way."),
                                 action: (L("Allow Reminders"), requestPermission), problem: true)
        default:
            if !Reminders.isEnabled {
                return ReminderState(icon: "bell.slash", title: L("Task reminders are off in Minor"), detail: L("The date is kept. Turn them on to get a reminder."),
                                     action: (L("Turn On Reminders"), { Reminders.isEnabled = true; Reminders.shared.sync(store.maps); checkScheduled() }), problem: true)
            }
            if changed || draft == nil {
                return ReminderState(icon: "bell", title: draft == nil ? L("No reminder without a date") : L("A reminder comes at this time after you save"), detail: nil, action: nil, problem: false)
            }
            if let date = saved, date < Date() {
                return ReminderState(icon: "bell", title: L("The time has passed"), detail: L("Choose a later time for a reminder."), action: nil, problem: true)
            }
            switch scheduled {
            case true?:
                return ReminderState(icon: "bell.badge", title: L("The reminder is set"), detail: nil, action: nil, problem: false)
            case false?:
                return ReminderState(icon: "exclamationmark.triangle", title: L("Couldn’t set the reminder"), detail: L("The date is saved."),
                                     action: (L("Try Again"), { Reminders.shared.sync(store.maps); checkScheduled() }), problem: true)
            case nil:
                return ReminderState(icon: "bell", title: L("Checking the reminder…"), detail: nil, action: nil, problem: false)
            }
        }
    }

    private func row(icon: String, title: String, value: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 20)).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    if let value {
                        Text(title).minorFont(13, maxScale: 1.3).foregroundColor(MinorColor.textSecondary)
                        Text(value).minorFont(18, .medium, maxScale: 1.3)
                    } else {
                        Text(title).minorFont(17, .medium, maxScale: 1.3)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundColor(MinorColor.textTertiary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 60)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    // MARK: Actions

    // The date counts only now; the task stays a task, its reminder follows the new date.
    private func save() {
        guard canEdit, changed else { return }
        let date = draft
        store.update(mapID) { map in
            map.root.update(nodeID) { node in
                node.isTask = true
                node.due = date
                if date != nil { node.isDone = false }
            }
        }
        Haptics.success()
        scheduled = nil
        Reminders.shared.sync(store.maps)
        if date != nil { checkScheduled() }
    }

    private func open(_ action: @escaping () -> Void) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: action)
    }

    private func readPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                permission = settings.authorizationStatus
                if saved != nil { checkScheduled() }
            }
        }
    }

    // Asked only by this explicit action.
    private func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
            DispatchQueue.main.async {
                readPermission()
                Reminders.shared.sync(store.maps)
            }
        }
    }

    // Whether the reminder for this task is really waiting in the system.
    private func checkScheduled() {
        let id = Reminders.prefix + nodeID.uuidString
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                let found = requests.contains { $0.identifier == id }
                DispatchQueue.main.async { scheduled = found }
            }
        }
    }
}
