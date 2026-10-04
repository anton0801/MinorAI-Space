//
//  DueDateSheet.swift
//  Minor Ai
//
//  When a task should be done. A reminder comes at that time (Settings → Task Reminders).
//

import SwiftUI

struct DueDateSheet: View {
    let title: String
    let current: Date?
    let theme: AppTheme
    var onSave: (Date) -> Void
    var onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var date: Date

    init(title: String, current: Date?, theme: AppTheme, onSave: @escaping (Date) -> Void, onRemove: @escaping () -> Void) {
        self.title = title
        self.current = current
        self.theme = theme
        self.onSave = onSave
        self.onRemove = onRemove
        _date = State(initialValue: current ?? Self.morning(daysFromNow: 1))
    }

    // 9:00 on a day from today.
    static func morning(daysFromNow days: Int) -> Date {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: Date())) ?? Date()
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        quick(L("Today"), Self.later(today: true))
                        quick(L("Tomorrow"), Self.morning(daysFromNow: 1))
                        quick(L("Next Week"), Self.morning(daysFromNow: 7))
                    }
                    DatePicker("Due", selection: $date, in: Date().addingTimeInterval(-86_400 * 365)..., displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.graphical)
                        .tint(MinorColor.accent)
                        .labelsHidden()
                    Text("You’ll get a reminder at this time.")
                        .font(.system(size: 13))
                        .foregroundColor(MinorColor.textTertiary)
                    if current != nil {
                        Button(role: .destructive) {
                            onRemove()
                            dismiss()
                        } label: {
                            Label("Remove Date", systemImage: "calendar.badge.minus")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(MinorColor.dangerText)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                        }
                    }
                }
                .padding(20)
            }
            .foregroundColor(MinorColor.textPrimary)
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("Due Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(MinorColor.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(date)
                        dismiss()
                    }
                    .foregroundColor(MinorColor.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // Today: the next full hour, or 18:00 when it is still earlier.
    static func later(today: Bool) -> Date {
        let calendar = Calendar.current
        let now = Date()
        let evening = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now) ?? now
        if now < evening { return evening }
        // The start of the next hour (19:35 → 20:00). `date(bySetting:)` searches forward and
        // gave 21:00, or 1:00 tomorrow late at night.
        let hour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        return calendar.date(byAdding: .hour, value: 1, to: hour) ?? now
    }

    private func quick(_ title: String, _ value: Date) -> some View {
        let selected = Calendar.current.isDate(date, inSameDayAs: value)
        return Button {
            Haptics.selection()
            date = value
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(selected ? .black : MinorColor.textPrimary)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(Capsule().fill(selected ? MinorColor.accent : theme.chatRectangle))
                .overlay(Capsule().stroke(selected ? .clear : theme.chatStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
