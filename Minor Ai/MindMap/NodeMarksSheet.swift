//
//  NodeMarksSheet.swift
//  Minor Ai
//
//  Marks & Task for one idea: checkbox, due date, priority, emoji and the person's own labels.
//  Changes apply as you tap (each one can be undone on the map); color and shape live in Style.
//

import SwiftUI

struct NodeMarksSheet: View {
    let node: MindNode
    let isRoot: Bool
    // Labels used elsewhere in this map, offered with one tap.
    let mapLabels: [String]
    let theme: AppTheme
    var onChange: (_ change: @escaping (inout MindNode) -> Void) -> Void
    var onDue: (Date?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showDue = false
    @State private var showIcons = false
    @State private var adding = false
    @State private var newLabel = ""
    @FocusState private var labelFocused: Bool

    static let quickIcons = ["⭐️", "💡", "🎯", "🎙️", "📌", "✅"]

    private var suggestions: [String] {
        mapLabels.filter { !node.hasLabel($0) }.prefix(8).map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                EditorSheetHeader(title: L("Marks & Task"), subtitle: L("Only the idea “\(node.title)”")) { dismiss() }
                    .padding(.bottom, 12)
                divider
                if !isRoot {
                    row("checkmark.square", height: 38) {
                        Text("Task").minorFont(14, maxScale: 1.3)
                        Spacer(minLength: 8)
                        Toggle("Task", isOn: Binding(get: { node.isTask }, set: { value in
                            Haptics.selection()
                            onChange { node in
                                node.isTask = value
                                if !value { node.isDone = false }
                            }
                        }))
                        .labelsHidden()
                        .tint(MinorColor.accent)
                        .scaleEffect(0.86, anchor: .trailing)
                    }
                    .accessibilityElement(children: .contain)
                    divider
                    Button { showDue = true } label: {
                        row("calendar", height: 38) {
                            Text("Due").minorFont(14, maxScale: 1.3)
                            Spacer(minLength: 8)
                            Text(node.due.map(Self.dueText) ?? L("None"))
                                .minorFont(13, maxScale: 1.3)
                                .foregroundColor(MinorColor.textSecondary)
                                .lineLimit(1)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(MinorColor.textTertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Due, \(node.due.map(Self.dueText) ?? L("None"))"))
                    divider
                }
                // Priority, badge and labels keep their choices on the same line where they fit.
                ViewThatFits(in: .horizontal) {
                    row("flag", height: 46) {
                        HStack(spacing: 0) {
                            Text("Priority").minorFont(14, maxScale: 1.3).fixedSize()
                            Spacer(minLength: 6)
                            priorities.fixedSize()
                        }
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        row("flag", height: 38) { Text("Priority").minorFont(14, maxScale: 1.3) }
                        priorities.padding(.bottom, 8)
                    }
                }
                divider
                ViewThatFits(in: .horizontal) {
                    row("face.smiling", height: 48) {
                        HStack(spacing: 0) {
                            Text("Badge").minorFont(14, maxScale: 1.3).fixedSize()
                            Spacer(minLength: 6)
                            badges.fixedSize()
                        }
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        row("face.smiling", height: 38) { Text("Badge").minorFont(14, maxScale: 1.3) }
                        ScrollView(.horizontal, showsIndicators: false) { badges }.padding(.bottom, 8)
                    }
                }
                divider
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "tag")
                        .font(.system(size: 17))
                        .foregroundColor(MinorColor.textSecondary)
                        .frame(width: 24, height: 42)
                    Text("Labels").minorFont(14, maxScale: 1.3).frame(minHeight: 42).fixedSize()
                    labels
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle").font(.system(size: 12))
                    Text("Color and shape are in the Style tab.")
                        .minorFont(12, style: .caption1, maxScale: 1.4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundColor(MinorColor.textTertiary)
                .padding(.top, 4)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 22)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .foregroundColor(MinorColor.textPrimary)
        .background(MinorColor.editorSheet.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showDue) {
            DueDateSheet(title: node.title, current: node.due, theme: theme, onSave: { onDue($0) }, onRemove: { onDue(nil) })
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showIcons) {
            IconPickerView(current: node.icon) { icon in
                onChange { $0.icon = icon }
                showIcons = false
            }
        }
    }

    private var priorities: some View {
        HStack(spacing: 5) {
            priority(1, L("High"))
            priority(2, L("Medium"))
            priority(3, L("Low"))
        }
    }

    // The quick emoji (the idea's own one first when it isn't among them) and More.
    private var badges: some View {
        HStack(spacing: 5) {
            ForEach(icons.prefix(6), id: \.self) { icon in
                Button {
                    Haptics.selection()
                    onChange { $0.icon = $0.icon == icon ? nil : icon }
                } label: {
                    Text(icon)
                        .font(.system(size: 16))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.white.opacity(0.07)))
                        .overlay(Circle().stroke(BranchColor.lilac.color, lineWidth: 2).opacity(node.icon == icon ? 1 : 0))
                        .frame(height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(icon)
                .accessibilityAddTraits(node.icon == icon ? .isSelected : [])
            }
            Button { showIcons = true } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MinorColor.textPrimary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white.opacity(0.07)))
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More Icons")
        }
    }

    // The quick emoji, with the idea's own one first when it isn't among them.
    private var icons: [String] {
        guard let icon = node.icon, !Self.quickIcons.contains(icon) else { return Self.quickIcons }
        return [icon] + Self.quickIcons
    }

    @ViewBuilder
    private var labels: some View {
        FlowLayout(spacing: 7, lineSpacing: 7) {
            ForEach(node.labels, id: \.self) { label in
                LabelChip(label: label) {
                    Haptics.impact(.light)
                    onChange { $0.labels.removeAll { $0.caseInsensitiveCompare(label) == .orderedSame } }
                }
            }
            if adding {
                TextField("", text: $newLabel)
                    .placeholder(when: newLabel.isEmpty) { Text("New label").foregroundColor(theme.placeholderText) }
                    .minorFont(13, maxScale: 1.3)
                    .focused($labelFocused)
                    .submitLabel(.done)
                    .onSubmit(commitLabel)
                    .onChange(of: newLabel) { text in
                        if text.count > MindNode.maxLabelLength { newLabel = String(text.prefix(MindNode.maxLabelLength)) }
                    }
                    .padding(.horizontal, 10)
                    .frame(width: 140, height: 31)
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(MinorColor.accent, lineWidth: 1))
            } else if node.labels.count < MindNode.maxLabels {
                Button {
                    adding = true
                    labelFocused = true
                } label: {
                    Label("Add", systemImage: "plus")
                        .minorFont(13, maxScale: 1.3)
                        .foregroundColor(MinorColor.textPrimary)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 31)
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(MinorColor.textTertiary, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add Label")
            }
        }
        .onChange(of: labelFocused) { focused in
            if !focused { commitLabel(); adding = false }
        }
        // Labels already used in this map, offered while a new one is typed.
        if adding && !suggestions.isEmpty {
            FlowLayout(spacing: 7, lineSpacing: 7) {
                ForEach(suggestions, id: \.self) { label in
                    Button {
                        Haptics.selection()
                        onChange { $0.labels = MindNode.cleanLabels($0.labels + [label]) }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                            Text(label).minorFont(13, maxScale: 1.3).lineLimit(1)
                        }
                        .foregroundColor(MinorColor.textSecondary)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 29)
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(BranchColor.forLabel(label).color.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("Add label \(label)"))
                }
            }
            .padding(.top, 7)
        }
    }

    private func commitLabel() {
        guard let label = MindNode.cleanLabel(newLabel) else { return }
        newLabel = ""
        guard !node.hasLabel(label), node.labels.count < MindNode.maxLabels else { return }
        Haptics.selection()
        onChange { $0.labels = MindNode.cleanLabels($0.labels + [label]) }
    }

    private func priority(_ value: Int, _ title: String) -> some View {
        let selected = node.priority == value
        let color = Self.priorityColor(value)
        return Button {
            Haptics.selection()
            onChange { $0.priority = $0.priority == value ? nil : value }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: selected ? "flag.fill" : "flag").font(.system(size: 10))
                    .foregroundColor(selected ? color : MinorColor.textPrimary)
                Text(title).minorFont(12, selected ? .semibold : .regular, maxScale: 1.3).lineLimit(1)
                    .foregroundColor(selected ? color : MinorColor.textPrimary)
            }
            .padding(.horizontal, 7)
            .frame(minHeight: 31)
            .background(RoundedRectangle(cornerRadius: 9).fill(selected ? color.opacity(0.12) : Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(selected ? color : Color.white.opacity(0.12), lineWidth: selected ? 1.5 : 1))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("Priority: \(title)"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func row<Content: View>(_ icon: String, height: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundColor(MinorColor.textSecondary)
                .frame(width: 24)
            content()
        }
        .frame(minHeight: height)
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
    }

    static func priorityColor(_ priority: Int) -> Color {
        switch priority {
        case 1: return Color(hex: "#FF6B6B")
        case 2: return Color(hex: "#FFD66B")
        default: return Color(hex: "#7CC4FF")
        }
    }

    // "Today, 18:00", "Tomorrow, 9:00" or "Oct 20, 9:00".
    static func dueText(_ date: Date) -> String {
        let time = DateFormatter()
        time.locale = AppLanguage.current.locale
        time.setLocalizedDateFormatFromTemplate("jmm")
        return "\(DueLabel.text(for: date)), \(time.string(from: date))"
    }
}
