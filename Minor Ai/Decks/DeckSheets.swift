//
//  DeckSheets.swift
//  Minor Ai
//
//  The presentation editor's sheets: edit a slide (with a live preview), pick a layout or a
//  theme, rewrite a slide with AI, and speaker notes.
//

import SwiftUI

struct SlideInspector: View {
    let deck: Deck
    let theme: AppTheme
    var onSave: (Slide) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: Slide

    init(slide: Slide, deck: Deck, theme: AppTheme, onSave: @escaping (Slide) -> Void) {
        self.deck = deck
        self.theme = theme
        self.onSave = onSave
        _draft = State(initialValue: slide)
    }

    private var index: Int { deck.slides.firstIndex { $0.id == draft.id } ?? 0 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SlideCanvas(slide: draft, deck: deck, index: index)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.chatStroke, lineWidth: 1))
                    fields
                    field(L("Speaker notes"), text: $draft.notes, lines: 3...8)
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(theme.background.ignoresSafeArea())
            .foregroundColor(MinorColor.textPrimary)
            .navigationTitle(draft.layout.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(MinorColor.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(draft)
                        dismiss()
                    }
                    .foregroundColor(MinorColor.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var fields: some View {
        switch draft.layout {
        case .cover, .section, .closing:
            field(L("Title"), text: $draft.title)
            field(L("Subtitle"), text: $draft.subtitle, lines: 1...4)
        case .bullets, .imageText:
            field(L("Title"), text: $draft.title)
            listEditor(L("Points"), items: $draft.bullets, max: 6)
        case .twoColumns:
            field(L("Title"), text: $draft.title)
            ForEach(draft.columns.indices, id: \.self) { i in
                VStack(alignment: .leading, spacing: 10) {
                    field(L("Column \(i + 1)"), text: safe(\.columns, i, \.title, empty: SlideColumn(title: "", bullets: [])))
                    listEditor(L("Points"), items: safe(\.columns, i, \.bullets, empty: SlideColumn(title: "", bullets: [])), max: 5)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(theme.chatRectangle.opacity(0.5)))
            }
            if draft.columns.count < 3 {
                addButton(L("Add Column")) { draft.columns.append(SlideColumn(title: L("New column"), bullets: [])) }
            }
        case .timeline:
            field(L("Title"), text: $draft.title)
            ForEach(draft.items.indices, id: \.self) { i in
                HStack(alignment: .top, spacing: 8) {
                    VStack(spacing: 8) {
                        input(L("Step"), text: safe(\.items, i, \.title, empty: SlideItem(title: "", detail: "")))
                        input(L("Detail"), text: safe(\.items, i, \.detail, empty: SlideItem(title: "", detail: "")))
                    }
                    removeButton { if draft.items.indices.contains(i) { draft.items.remove(at: i) } }
                }
            }
            if draft.items.count < 6 {
                addButton(L("Add Step")) { draft.items.append(SlideItem(title: L("New step"), detail: "")) }
            }
        case .bigNumber:
            field(L("Title"), text: $draft.title)
            field(L("Number"), text: Binding(get: { draft.stat?.value ?? "" }, set: { draft.stat = SlideStat(value: $0, label: draft.stat?.label ?? "") }))
            field(L("What it means"), text: Binding(get: { draft.stat?.label ?? "" }, set: { draft.stat = SlideStat(value: draft.stat?.value ?? "", label: $0) }), lines: 1...3)
        case .quote:
            field(L("Quote"), text: Binding(get: { draft.quote?.text ?? "" }, set: { draft.quote = SlideQuote(text: $0, author: draft.quote?.author ?? "") }), lines: 2...6)
            field(L("Author"), text: Binding(get: { draft.quote?.author ?? "" }, set: { draft.quote = SlideQuote(text: draft.quote?.text ?? "", author: $0) }))
        case .table:
            field(L("Title"), text: $draft.title)
            tableEditor
        case .diagram:
            field(L("Title"), text: $draft.title)
            field(L("Center"), text: Binding(get: { draft.diagram?.center ?? "" }, set: { draft.diagram = SlideDiagram(center: $0, nodes: draft.diagram?.nodes ?? []) }))
            listEditor(L("Around it"), items: Binding(get: { draft.diagram?.nodes ?? [] }, set: { draft.diagram = SlideDiagram(center: draft.diagram?.center ?? "", nodes: $0) }), max: 6)
        }
    }

    private var tableEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Table").font(.system(size: 13, weight: .medium)).foregroundColor(MinorColor.textTertiary).textCase(.uppercase)
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(draft.table.indices, id: \.self) { r in
                        HStack(spacing: 6) {
                            ForEach(draft.table[r].indices, id: \.self) { c in
                                TextField("", text: cell(r, c))
                                    .font(.system(size: 15, weight: r == 0 ? .semibold : .regular))
                                    .padding(10)
                                    .frame(width: 130)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(r == 0 ? MinorColor.accent.opacity(0.14) : theme.chatRectangle))
                            }
                            if r > 0 { removeButton { if draft.table.indices.contains(r) { draft.table.remove(at: r) } } }
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                if draft.table.count < 6 {
                    addButton(L("Add Row")) { draft.table.append(Array(repeating: "", count: max(draft.table.first?.count ?? 2, 2))) }
                }
                if (draft.table.first?.count ?? 0) < 4 {
                    addButton(L("Add Column")) {
                        if draft.table.isEmpty { draft.table = [["", ""]] }
                        for r in draft.table.indices { draft.table[r].append("") }
                    }
                }
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, lines: ClosedRange<Int> = 1...3) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 13, weight: .medium)).foregroundColor(MinorColor.textTertiary).textCase(.uppercase)
            TextField("", text: text, axis: .vertical)
                .lineLimit(lines)
                .font(.system(size: 17))
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(theme.chatRectangle))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.chatStroke, lineWidth: 1))
        }
    }

    private func input(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text, axis: .vertical)
            .lineLimit(1...3)
            .font(.system(size: 16))
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(theme.chatRectangle))
    }

    // Bindings into rows that may be removed while a field still holds focus: reading or writing a
    // row that is gone does nothing instead of crashing.
    private func safe<Row, Value>(_ list: WritableKeyPath<Slide, [Row]>, _ i: Int, _ field: WritableKeyPath<Row, Value>, empty: Row) -> Binding<Value> {
        Binding(
            get: { draft[keyPath: list].indices.contains(i) ? draft[keyPath: list][i][keyPath: field] : empty[keyPath: field] },
            set: { if draft[keyPath: list].indices.contains(i) { draft[keyPath: list][i][keyPath: field] = $0 } }
        )
    }

    private func cell(_ r: Int, _ c: Int) -> Binding<String> {
        Binding(
            get: { draft.table.indices.contains(r) && draft.table[r].indices.contains(c) ? draft.table[r][c] : "" },
            set: { if draft.table.indices.contains(r) && draft.table[r].indices.contains(c) { draft.table[r][c] = $0 } }
        )
    }

    private func listEditor(_ label: String, items: Binding<[String]>, max: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.system(size: 13, weight: .medium)).foregroundColor(MinorColor.textTertiary).textCase(.uppercase)
            ForEach(items.wrappedValue.indices, id: \.self) { i in
                HStack(spacing: 8) {
                    input(L("Point"), text: Binding(get: { items.wrappedValue.indices.contains(i) ? items.wrappedValue[i] : "" }, set: { value in
                        if items.wrappedValue.indices.contains(i) { items.wrappedValue[i] = value }
                    }))
                    removeButton { if items.wrappedValue.indices.contains(i) { items.wrappedValue.remove(at: i) } }
                }
            }
            if items.wrappedValue.count < max {
                addButton(L("Add Point")) { items.wrappedValue.append("") }
            }
        }
    }

    private func addButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: "plus")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(MinorColor.accent)
                .frame(minHeight: 40)
        }
        .buttonStyle(.plain)
    }

    private func removeButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(MinorColor.textTertiary)
                .frame(width: 36, height: 40)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove")
    }
}

// Layouts with the slide's own content in each, so the choice is easy to see.
struct LayoutPicker: View {
    let slide: Slide?
    let deck: Deck
    let theme: AppTheme
    var onPick: (SlideLayout) -> Void

    @Environment(\.dismiss) private var dismiss

    private var sample: Slide {
        slide ?? Slide(layout: .bullets, title: L("New slide"), bullets: [L("First point"), L("Second point"), L("Third point")])
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
                    ForEach(SlideLayout.allCases) { layout in
                        Button {
                            Haptics.selection()
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onPick(layout) }
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                SlideCanvas(slide: sample.converted(to: layout), deck: deck)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(slide?.layout == layout ? MinorColor.accent : theme.chatStroke, lineWidth: slide?.layout == layout ? 2 : 1))
                                Label(layout.name, systemImage: layout.icon)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(MinorColor.textPrimary)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(layout.name)
                    }
                }
                .padding(16)
            }
            .background(theme.background.ignoresSafeArea())
            .navigationTitle(slide == nil ? "Add Slide" : "Layout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(MinorColor.textSecondary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct RewriteSheet: View {
    let theme: AppTheme
    var onRewrite: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var custom = ""

    private var presets: [(String, String)] {
        [
            ("text.badge.minus", L("Shorter")),
            ("eye", L("More visual")),
            ("textformat.size.smaller", L("Simpler words")),
            ("text.badge.plus", L("More detail")),
            ("lightbulb", L("Add an example")),
            ("megaphone", L("More persuasive")),
            ("briefcase", L("More formal")),
            ("checkmark.seal", L("Fix the wording")),
        ]
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(presets, id: \.1) { icon, title in
                        Button { apply(title) } label: {
                            Label(title, systemImage: icon)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(MinorColor.textPrimary)
                                .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                                .padding(.horizontal, 12)
                                .background(RoundedRectangle(cornerRadius: 12).fill(theme.chatRectangle))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.chatStroke, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack(spacing: 8) {
                    TextField("", text: $custom, axis: .vertical)
                        .placeholder(when: custom.isEmpty) { Text("Or say how to change it").foregroundColor(theme.placeholderText) }
                        .lineLimit(1...3)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(theme.chatRectangle))
                    DictationButton(text: $custom, stroke: theme.chatStroke)
                    Button { apply(custom) } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.black)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(MinorColor.accent))
                    }
                    .disabled(custom.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel("Rewrite")
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .foregroundColor(MinorColor.textPrimary)
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("Rewrite with AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(MinorColor.textSecondary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func apply(_ instruction: String) {
        let text = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        dismiss()
        onRewrite(text)
    }
}

struct NotesSheet: View {
    let theme: AppTheme
    var onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var notes: String

    init(notes: String, theme: AppTheme, onSave: @escaping (String) -> Void) {
        self.theme = theme
        self.onSave = onSave
        _notes = State(initialValue: notes)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                Text("What you say on this slide. Only you see it while presenting.")
                    .font(.system(size: 14))
                    .foregroundColor(MinorColor.textSecondary)
                TextEditor(text: $notes)
                    .font(.system(size: 17))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(theme.chatRectangle))
            }
            .padding(20)
            .foregroundColor(MinorColor.textPrimary)
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("Speaker Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(notes)
                        dismiss()
                    }
                    .foregroundColor(MinorColor.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
