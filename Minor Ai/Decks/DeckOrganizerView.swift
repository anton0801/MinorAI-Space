//
//  DeckOrganizerView.swift
//  Minor Ai
//
//  All Slides: every slide in a grid. Drag to change the order (or use Move Earlier / Later),
//  duplicate, hide (skipped when presenting and left out of exports) and delete with Undo. A
//  presentation always keeps one slide, and one slide stays visible.
//

import SwiftUI

struct DeckOrganizerView: View {
    let deckID: UUID
    let theme: AppTheme
    @Binding var current: Int
    // The editor's changes, so Undo there and here is one history.
    var onChange: (_ undoable: Bool, _ change: (inout Deck) -> Void) -> Void
    var canUndo: Bool
    var onUndo: () -> Void
    var onAddSlide: () -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = DeckStore.shared
    @State private var selected: UUID?
    @State private var dragging: UUID?
    @State private var movedThisDrag = false
    @State private var notice: Notice?

    struct Notice: Equatable {
        let id = UUID()
        let text: String
        let canUndo: Bool
    }

    private var deck: Deck? { store.deck(deckID) }
    private var selectedIndex: Int? { deck?.slides.firstIndex { $0.id == selected } }
    private var visibleCount: Int { deck?.slides.filter { !$0.isHidden }.count ?? 0 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                if let deck {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Image(systemName: "line.3.horizontal").font(.system(size: 15)).accessibilityHidden(true)
                                Text("Drag a slide to change the order").minorFont(14, maxScale: 1.3).lineLimit(1).minimumScaleFactor(0.8)
                            }
                            .foregroundColor(MinorColor.textTertiary)
                            .padding(.horizontal, 14)
                            .frame(maxWidth: .infinity, minHeight: 35, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 1))
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)], spacing: 12) {
                                ForEach(Array(deck.slides.enumerated()), id: \.element.id) { i, slide in
                                    cell(slide, index: i, deck: deck)
                                }
                            }
                        }
                        .padding(.horizontal, 9)
                        .padding(.top, 4)
                        .padding(.bottom, 12)
                    }
                    .onDrop(of: [.text], isTargeted: nil) { _ in
                        dragging = nil
                        return true
                    }
                    bottomBar
                } else {
                    Spacer()
                    Text("This presentation was deleted.").foregroundColor(MinorColor.textSecondary)
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .foregroundColor(MinorColor.textPrimary)
        .preferredColorScheme(.dark)
        .onAppear {
            if selected == nil, let deck, deck.slides.indices.contains(current) { selected = deck.slides[current].id }
        }
        .onChange(of: deck == nil) { gone in if gone { dismiss() } }
    }

    // Back, the title with the presentation under it, Undo and Done.
    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: 36, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            VStack(alignment: .leading, spacing: 1) {
                Text("All Slides")
                    .minorFont(21, .bold, maxScale: 1.2)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                if let deck {
                    Text("\(deck.title) · \(L("\(deck.slides.count) slides"))")
                        .minorFont(14, maxScale: 1.2)
                        .foregroundColor(MinorColor.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if canUndo {
                Button(action: undo) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 40, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Undo")
            }
            Button("Done") { dismiss() }
                .minorFont(17, .semibold, maxScale: 1.2)
                .foregroundColor(MinorColor.accent)
                .frame(minHeight: 44)
        }
        .padding(.leading, 6)
        .padding(.trailing, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    // MARK: - Cells

    private func cell(_ slide: Slide, index i: Int, deck: Deck) -> some View {
        let isSelected = selected == slide.id
        return VStack(alignment: .leading, spacing: 6) {
            SlideCanvas(slide: slide, deck: deck, index: i)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .opacity(slide.isHidden ? 0.4 : 1)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSelected ? MinorColor.accent : theme.chatStroke, lineWidth: isSelected ? 2.5 : 1))
                .overlay(alignment: .topTrailing) {
                    if slide.isHidden {
                        Image(systemName: "eye.slash.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Circle().fill(Color.black.opacity(0.65)))
                            .padding(6)
                            .accessibilityHidden(true)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    // The chosen slide's actions, also in its context menu.
                    if isSelected && !slide.isHidden {
                        Menu { actions(slide, index: i, deck: deck) } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(Color.black.opacity(0.55)))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("More")
                    }
                }
                .opacity(dragging == slide.id ? 0.5 : 1)
            HStack(spacing: 14) {
                Text("\(i + 1)").minorFont(14, maxScale: 1.3).monospacedDigit()
                Text(slide.plainText.first ?? slide.layout.name)
                    .minorFont(14, maxScale: 1.3)
                    .foregroundColor(MinorColor.textSecondary)
                    .lineLimit(1)
            }
            .padding(.leading, 6)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.selection()
            selected = slide.id
        }
        .onTapGesture(count: 2) { open(i) }
        .onDrag {
            dragging = slide.id
            movedThisDrag = false
            return NSItemProvider(object: slide.id.uuidString as NSString)
        }
        .onDrop(of: [.text], delegate: SlideDropDelegate(target: slide.id, dragging: $dragging) { dragged, target in
            guard let slides = self.deck?.slides,
                  let from = slides.firstIndex(where: { $0.id == dragged }),
                  let to = slides.firstIndex(where: { $0.id == target }) else { return }
            move(from: from, to: to)
        })
        .contextMenu { actions(slide, index: i, deck: deck) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Slide \(i + 1): \(slide.plainText.first ?? slide.layout.name)") + (slide.isHidden ? L(", hidden") : ""))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { selected = slide.id }
        .accessibilityAction(named: Text("Open")) { open(i) }
        .accessibilityAction(named: Text("Move Earlier")) { if i > 0 { move(from: i, to: i - 1, undoable: true) } }
        .accessibilityAction(named: Text("Move Later")) { if i < deck.slides.count - 1 { move(from: i, to: i + 1, undoable: true) } }
    }

    @ViewBuilder
    private func actions(_ slide: Slide, index i: Int, deck: Deck) -> some View {
        Button { open(i) } label: { Label("Open", systemImage: "rectangle.portrait.and.arrow.right") }
        if i > 0 { Button { move(from: i, to: i - 1, undoable: true) } label: { Label("Move Earlier", systemImage: "arrow.left") } }
        if i < deck.slides.count - 1 { Button { move(from: i, to: i + 1, undoable: true) } label: { Label("Move Later", systemImage: "arrow.right") } }
        Button { duplicate(slide.id) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
        Button { toggleHidden(slide.id) } label: {
            Label(slide.isHidden ? "Show Slide" : "Hide Slide", systemImage: slide.isHidden ? "eye" : "eye.slash")
        }
        .disabled(!slide.isHidden && visibleCount <= 1)
        if deck.slides.count > 1 {
            Button(role: .destructive) { delete(slide.id) } label: { Label("Delete Slide", systemImage: "trash") }
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if let notice {
                HStack(spacing: 12) {
                    Text(notice.text).minorFont(15, maxScale: 1.3)
                    if notice.canUndo && canUndo {
                        Button("Undo", action: undo).minorFont(15, .semibold, maxScale: 1.3).foregroundColor(MinorColor.accent)
                    }
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 40)
                .background(Capsule().fill(theme.chatRectangle))
                .overlay(Capsule().stroke(theme.chatStroke, lineWidth: 1))
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            if let deck, let i = selectedIndex {
                let slide = deck.slides[i]
                HStack(spacing: 0) {
                    barButton(L("Duplicate"), "plus.square.on.square") { duplicate(slide.id) }
                    Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1, height: 28)
                    barButton(slide.isHidden ? L("Show") : L("Hide"), slide.isHidden ? "eye" : "eye.slash") { toggleHidden(slide.id) }
                        .disabled(!slide.isHidden && visibleCount <= 1)
                    Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1, height: 28)
                    barButton(L("Delete"), "trash", destructive: true) { delete(slide.id) }
                        .disabled(deck.slides.count <= 1)
                }
                .frame(minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
                if deck.slides.count <= 1 {
                    footnote(L("A presentation keeps at least one slide."))
                } else if !slide.isHidden && visibleCount <= 1 {
                    footnote(L("One slide stays visible, so there is something to present."))
                }
            }
            Button {
                dismiss()
                onAddSlide()
            } label: {
                Label("Add Slide", systemImage: "plus")
                    .minorFont(16, .semibold, maxScale: 1.3)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white))
            }
            .buttonStyle(PressScale())
        }
        .padding(.horizontal, 9)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(theme.background)
        .animation(.minorMenu, value: notice)
    }

    private func barButton(_ title: String, _ icon: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .minorFont(14, maxScale: 1.25)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundColor(destructive ? MinorColor.dangerText : MinorColor.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .minorFont(13, style: .footnote, maxScale: 1.3)
            .foregroundColor(MinorColor.textTertiary)
            .multilineTextAlignment(.center)
    }

    // MARK: - Changes

    private func open(_ i: Int) {
        current = i
        dismiss()
    }

    // One drag is one step to undo, however many places the slide passes on the way.
    private func move(from: Int, to: Int, undoable: Bool? = nil) {
        guard let deck, deck.slides.indices.contains(from), deck.slides.indices.contains(to), from != to else { return }
        let onScreen = deck.slides.indices.contains(current) ? deck.slides[current].id : nil
        let record = undoable ?? !movedThisDrag
        movedThisDrag = true
        withAnimation(.minorMenu) {
            onChange(record) { deck in
                let slide = deck.slides.remove(at: from)
                deck.slides.insert(slide, at: to)
            }
        }
        // The slide on screen in the editor stays the same slide.
        if let onScreen, let i = store.deck(deckID)?.slides.firstIndex(where: { $0.id == onScreen }) { current = i }
        Haptics.selection()
    }

    private func duplicate(_ id: UUID) {
        guard let i = deck?.slides.firstIndex(where: { $0.id == id }) else { return }
        var copy = deck!.slides[i]
        copy.id = UUID()
        copy.elements = copy.elements.map { var e = $0; e.id = UUID(); return e }
        onChange(true) { $0.slides.insert(copy, at: i + 1) }
        if i < current { current += 1 }
        selected = copy.id
        show(L("Slide duplicated"), canUndo: true)
    }

    private func toggleHidden(_ id: UUID) {
        guard let slide = deck?.slides.first(where: { $0.id == id }) else { return }
        guard slide.isHidden || visibleCount > 1 else { return }
        onChange(true) { deck in
            guard let i = deck.slides.firstIndex(where: { $0.id == id }) else { return }
            deck.slides[i].isHidden.toggle()
        }
        show(slide.isHidden ? L("Slide shown") : L("Slide hidden: skipped when presenting"), canUndo: true)
    }

    private func delete(_ id: UUID) {
        guard let deck, deck.slides.count > 1, let i = deck.slides.firstIndex(where: { $0.id == id }) else { return }
        // A deleted slide that was the only visible one: the next one becomes visible.
        let wasLastVisible = !deck.slides[i].isHidden && visibleCount <= 1
        onChange(true) { deck in
            deck.slides.remove(at: i)
            if wasLastVisible, let first = deck.slides.indices.first { deck.slides[first].isHidden = false }
        }
        if i < current || current >= deck.slides.count - 1 { current = max(current - 1, 0) }
        selected = store.deck(deckID)?.slides[min(i, (store.deck(deckID)?.slides.count ?? 1) - 1)].id
        show(L("Slide deleted"), canUndo: true)
        Haptics.impact(.light)
    }

    private func undo() {
        onUndo()
        notice = nil
        if let deck, !deck.slides.contains(where: { $0.id == selected }) { selected = deck.slides.first?.id }
    }

    private func show(_ text: String, canUndo: Bool) {
        let new = Notice(text: text, canUndo: canUndo)
        notice = new
        UIAccessibility.post(notification: .announcement, argument: text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { if notice == new { notice = nil } }
    }
}

// Moving a dragged slide to where it is over another one, as it moves.
private struct SlideDropDelegate: DropDelegate {
    let target: UUID
    @Binding var dragging: UUID?
    var move: (_ dragged: UUID, _ target: UUID) -> Void

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target else { return }
        move(dragging, target)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}
