//
//  MapMergeSheet.swift
//  Minor Ai
//
//  Update from Map: what the map changed, slide by slide, before anything changes. Changes the
//  person didn't touch are ticked; a text both sides changed is a conflict that keeps the person's
//  words unless they take the map's or write their own. The button counts what will really change.
//  Before applying, the map and the presentation are checked again; a stale comparison is never
//  applied. Applying is one change Undo takes back. Design, notes, pictures and order stay.
//
//  Presentations made before links existed say so and can be linked to the map's branches by hand
//  (nothing is matched by guesswork), or the whole update can be saved as a separate copy.
//

import SwiftUI

struct MapMergeSheet: View {
    @State var update: MapUpdate
    let deck: Deck
    let theme: AppTheme
    var onApply: (MapUpdate) -> String?       // nil when applied, otherwise what went wrong
    var onRefresh: () -> MapUpdate?           // a new comparison (the map or the slides changed)
    var onCopy: (MapUpdate) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var problem: String?
    @State private var stale = false
    @State private var editing: String?       // the conflict being written by hand
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    previewCard
                    if stale { staleNotice }
                    if let problem {
                        Label(problem, systemImage: "exclamationmark.triangle")
                            .minorFont(14, maxScale: 1.3)
                            .foregroundColor(MinorColor.dangerText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !update.offers.isEmpty {
                        sectionTitle(L("Changes without conflicts"))
                        VStack(spacing: 8) {
                            ForEach(update.offers) { change in offerRow(change) }
                        }
                    }
                    if !update.conflicts.isEmpty {
                        sectionTitle(L("Text conflicts"))
                        ForEach(update.conflicts) { change in conflictCard(change) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            footer
        }
        .foregroundColor(MinorColor.textPrimary)
        .background(theme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    // MARK: Pieces

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.white.opacity(0.1)))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close")
            VStack(spacing: 3) {
                Text("Update from Map")
                    .minorFont(24, .bold, maxScale: 1.3)
                    .accessibilityAddTraits(.isHeader)
                Text(summary)
                    .minorFont(15, maxScale: 1.3)
                    .foregroundColor(MinorColor.textSecondary)
            }
            .frame(maxWidth: .infinity)
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    private var summary: String {
        let offers = L("\(update.offers.count) suggestions")
        return update.conflicts.isEmpty ? offers : "\(offers) · \(L("\(update.conflicts.count) conflicts"))"
    }

    // The first slide that changes, and the promise that design and notes stay.
    private var previewCard: some View {
        let id = update.visible.compactMap(\.slideID).first
        let slide = id.flatMap { id in deck.slides.first { $0.id == id } } ?? deck.slides.first
        let index = slide.flatMap { s in deck.slides.firstIndex { $0.id == s.id } } ?? 0
        return HStack(spacing: 16) {
            if let slide {
                SlideCanvas(slide: slide, deck: deck, index: index)
                    .frame(width: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            Text("Your design and notes stay as they are.")
                .minorFont(15, maxScale: 1.3)
                .foregroundColor(MinorColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }

    private var staleNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("The document changed. Refresh the comparison.", systemImage: "arrow.triangle.2.circlepath")
                .minorFont(15, .semibold, maxScale: 1.3)
                .foregroundColor(BranchColor.sun.color)
            Button {
                guard let fresh = onRefresh() else { return dismiss() }
                update = fresh.carrying(update)
                stale = false
                problem = nil
            } label: {
                Text("Refresh Comparison")
                    .minorFont(15, .semibold, maxScale: 1.3)
                    .foregroundColor(.black)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 40)
                    .background(Capsule().fill(BranchColor.sun.color))
            }
            .buttonStyle(PressScale())
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(BranchColor.sun.color.opacity(0.1)))
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .minorFont(20, .bold, maxScale: 1.3)
            .padding(.top, 8)
            .accessibilityAddTraits(.isHeader)
    }

    private func place(_ change: MapUpdate.Change) -> String {
        change.kind == .newSlide
            ? L("Slide \(change.slideNumber) · new")
            : L("Slide \(change.slideNumber) · \(change.slideTitle)")
    }

    private func describe(_ change: MapUpdate.Change) -> String {
        switch change.kind {
        case .change: return L("“\(change.current)” → “\(change.proposal)”")
        case .addition: return L("Add the point “\(change.proposal)”")
        case .newSlide: return L("New slide “\(change.proposal)” with its ideas")
        case .removal: return change.include ? L("Remove “\(change.current)”: its idea is gone from the map") : L("Keep “\(change.current)” as your own text")
        case .slideRemoval: return change.include ? L("Remove the slide: its branch is gone from the map") : L("Keep the slide as your own")
        default: return ""
        }
    }

    private func offerRow(_ change: MapUpdate.Change) -> some View {
        Button {
            toggle(change.id)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(change.include ? MinorColor.accent : Color.clear)
                    Circle().stroke(change.include ? Color.clear : MinorColor.textTertiary, lineWidth: 1.5)
                    if change.include { Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundColor(.black) }
                }
                .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(place(change)).minorFont(16, .semibold, maxScale: 1.3).lineLimit(1)
                    Text(describe(change))
                        .minorFont(14, maxScale: 1.3)
                        .foregroundColor(MinorColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if change.overflows {
                        Label("Won’t all fit: you can split the slide after.", systemImage: "rectangle.split.2x1")
                            .minorFont(12, maxScale: 1.3)
                            .foregroundColor(BranchColor.sun.color)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(change.include ? .isSelected : [])
        .accessibilityHint("Turns this change on or off")
    }

    private func conflictCard(_ change: MapUpdate.Change) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(place(change)).minorFont(17, .bold, maxScale: 1.3).lineLimit(1)
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    Circle().fill(MinorColor.accent).frame(width: 8, height: 8)
                    Text(choiceName(change.choice)).minorFont(14, maxScale: 1.3).foregroundColor(MinorColor.accent)
                }
            }
            option(change, .mine, L("Keep my text"), change.current)
            option(change, .map, L("Take from the map"), change.proposal)
            if editing == change.id {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("", text: $draft, axis: .vertical)
                        .minorFont(15, maxScale: 1.3)
                        .lineLimit(1...4)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
                    HStack {
                        Button("Cancel") { editing = nil }
                            .foregroundColor(MinorColor.textSecondary)
                        Spacer()
                        Button("Use This Text") {
                            let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !text.isEmpty else { return }
                            set(change.id) { $0.choice = .custom(text) }
                            editing = nil
                        }
                        .foregroundColor(MinorColor.accent)
                    }
                    .minorFont(15, .medium, maxScale: 1.3)
                }
            } else {
                Button {
                    if case .custom(let text) = change.choice { draft = text } else { draft = change.current }
                    editing = change.id
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "pencil").font(.system(size: 18))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Edit by Hand").minorFont(16, maxScale: 1.3)
                            if case .custom(let text) = change.choice {
                                Text(text).minorFont(13, maxScale: 1.3).foregroundColor(MinorColor.textSecondary).lineLimit(2)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundColor(MinorColor.textTertiary)
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(isCustom(change.choice) ? MinorColor.accent : Color.clear, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }

    private func isCustom(_ choice: MapUpdate.Choice) -> Bool {
        if case .custom = choice { return true }
        return false
    }

    private func choiceName(_ choice: MapUpdate.Choice) -> String {
        switch choice {
        case .mine: return L("Keep mine")
        case .map: return L("From the map")
        case .custom: return L("By hand")
        }
    }

    private func option(_ change: MapUpdate.Change, _ choice: MapUpdate.Choice, _ title: String, _ text: String) -> some View {
        let chosen = change.choice == choice
        return Button {
            set(change.id) { $0.choice = choice }
        } label: {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle().stroke(chosen ? MinorColor.accent : MinorColor.textTertiary, lineWidth: 2)
                    if chosen { Circle().fill(MinorColor.accent).padding(6) }
                }
                .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).minorFont(16, .semibold, maxScale: 1.3)
                    Text(text)
                        .minorFont(15, maxScale: 1.3)
                        .foregroundColor(MinorColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(chosen ? MinorColor.accent : Color.clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Button {
                problem = onApply(update)
                if problem == nil { dismiss() } else if problem == MapMergeSheet.staleMessage { stale = true; problem = nil }
            } label: {
                Text(update.changeCount > 0 ? L("Apply Selected (\(update.changeCount))") : L("Apply Selected"))
                    .minorFont(17, .semibold, maxScale: 1.3)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white))
            }
            .buttonStyle(PressScale())
            .disabled(stale)
            .opacity(stale ? 0.5 : 1)
            HStack(spacing: 6) {
                Text("You can undo this.")
                Text("·")
                Button("Save as a Copy") {
                    onCopy(update)
                    dismiss()
                }
                .foregroundColor(MinorColor.textSecondary)
            }
            .minorFont(13, maxScale: 1.3)
            .foregroundColor(MinorColor.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(theme.background.opacity(0.96).ignoresSafeArea())
    }

    static let staleMessage = "stale"

    private func toggle(_ id: String) {
        Haptics.selection()
        set(id) { $0.include.toggle() }
    }

    private func set(_ id: String, _ change: (inout MapUpdate.Change) -> Void) {
        guard let i = update.changes.firstIndex(where: { $0.id == id }) else { return }
        change(&update.changes[i])
    }
}

// MARK: - Presentations without links

struct MapLinkSheet: View {
    let deck: Deck
    let map: MindMap
    let theme: AppTheme
    var onLink: (DeckLineage) -> Void
    var onCopy: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var chosen: [UUID: UUID] = [:]     // slide → branch
    @State private var confirming = false

    private var slides: [Slide] { deck.slides.filter { $0.layout != .cover && $0.layout != .closing } }
    private var branches: [MindNode] { map.root.children.filter { !$0.isSuggestion } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("This presentation has no exact link to the map’s ideas yet.")
                        .minorFont(18, .semibold, maxScale: 1.3)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Link slides to the branches they are about: their titles and new ideas will be offered when the map changes. Nothing is matched by guesswork, and the text of the slides doesn’t change now.")
                        .minorFont(14, maxScale: 1.3)
                        .foregroundColor(MinorColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(slides) { slide in
                        let index = (deck.slides.firstIndex { $0.id == slide.id } ?? 0) + 1
                        HStack(spacing: 12) {
                            Text("\(index)").minorFont(14, .semibold, maxScale: 1.2).monospacedDigit()
                                .frame(width: 28, height: 28).background(Circle().fill(Color.white.opacity(0.08)))
                            Text(slide.title.isEmpty ? L("Untitled slide") : slide.title)
                                .minorFont(15, maxScale: 1.3).lineLimit(2)
                            Spacer(minLength: 8)
                            Menu {
                                Button(L("Not linked")) { chosen[slide.id] = nil }
                                ForEach(branches) { branch in
                                    Button(branch.title) { chosen[slide.id] = branch.id }
                                }
                            } label: {
                                Text(chosen[slide.id].flatMap { id in branches.first { $0.id == id }?.title } ?? L("Not linked"))
                                    .minorFont(14, maxScale: 1.3)
                                    .lineLimit(1)
                                    .padding(.horizontal, 12)
                                    .frame(minHeight: 36)
                                    .background(Capsule().fill(chosen[slide.id] == nil ? Color.white.opacity(0.08) : MinorColor.accent.opacity(0.25)))
                            }
                            .accessibilityLabel(Text(L("Branch for slide \(index)")))
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
                    }
                    Button {
                        confirming = true
                    } label: {
                        Text(chosen.isEmpty ? L("Link Slides") : L("Link Slides (\(chosen.count))"))
                            .minorFont(16, .semibold, maxScale: 1.3)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white))
                    }
                    .buttonStyle(PressScale())
                    .disabled(chosen.isEmpty)
                    .opacity(chosen.isEmpty ? 0.5 : 1)
                    Button {
                        dismiss()
                        onCopy()
                    } label: {
                        Text("Make a New Copy from the Map")
                            .minorFont(15, .medium, maxScale: 1.3)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(PressScale())
                }
                .padding(16)
            }
            .foregroundColor(MinorColor.textPrimary)
            .background(theme.background.ignoresSafeArea())
            .navigationTitle(Text("Update from Map"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.foregroundColor(.white) }
            }
            .confirmationDialog(L("Link \(chosen.count) slides to these branches?"), isPresented: $confirming, titleVisibility: .visible) {
                Button("Link Slides") {
                    let pairs = slides.compactMap { slide in chosen[slide.id].flatMap { id in branches.first { $0.id == id } }.map { (slide: slide, node: $0) } }
                    onLink(DeckLineage.manual(pairs, map: map))
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("From now on, when these branches change, their new titles and ideas are offered for the slides.")
            }
        }
        .preferredColorScheme(.dark)
    }
}
