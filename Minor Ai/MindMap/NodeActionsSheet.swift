//
//  NodeActionsSheet.swift
//  Minor Ai
//
//  "More Actions" for one selected idea, as the design lists them: structure (move, connect), look
//  (appearance, marks), sources, the rest (duplicate, focus), and deleting at the bottom; groups
//  that open in place hold the content (photo, link, callout, frame), Minor's actions and the
//  order (add beside, up, down, collapse). The root has no move, sibling or delete; a map the
//  person only views shows what can be read, not what would change it.
//

import SwiftUI

enum NodeAction: Hashable {
    case move, connect, addSibling, moveUp, moveDown, toggleCollapse
    case style, marks, sources
    case photo, removePhoto, link, callout, frame, removeFrame
    case expand, examples, questions, nextSteps, aiImage
    case duplicate, focus, note
    case delete
}

struct NodeActionsSheet: View {
    let node: MindNode
    let isRoot: Bool
    let canEdit: Bool
    let siblingIndex: Int
    let siblingCount: Int
    let busy: Bool                       // Minor is already working on this idea
    var onAction: (NodeAction) -> Void

    @Environment(\.dismiss) private var dismiss
    // The nested groups opened in place (order, content, Minor's actions).
    @State private var open: Set<String> = []

    // As the design's list: structure, look, sources, the rest, and deleting at the bottom; what
    // didn't fit there sits in groups that open in place.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                EditorSheetHeader(title: L("More Actions"), subtitle: L("Idea “\(node.title)”"), closeButton: true) { dismiss() }
                if canEdit {
                    group {
                        if !isRoot { row("arrow.up.and.down.and.arrow.left.and.right", L("Move"), .move) }
                        row("link", L("Connect to an Idea"), .connect)
                    }
                    group {
                        row("paintbrush", L("Appearance"), .style)
                        row("tag", L("Marks & Labels"), .marks)
                        row("doc.text.magnifyingglass", L("Sources"), .sources)
                    }
                    if !isRoot {
                        group {
                            row("plus.rectangle.on.rectangle", L("Duplicate"), .duplicate)
                            row("scope", L("Focus on Branch"), .focus)
                        }
                    }
                    group {
                        nested("content", "square.on.square", L("Contents")) {
                            row("photo", node.image == nil ? L("Add Photo") : L("Replace Photo"), .photo)
                            if node.image != nil { row("photo.badge.minus", L("Remove Photo"), .removePhoto, destructive: true) }
                            row("globe", node.link == nil ? L("Add Web Link") : L("Edit Web Link"), .link)
                            if !isRoot {
                                row("quote.opening", node.isCallout ? L("Show as Idea") : L("Show as Callout"), .callout)
                                row("rectangle.dashed", node.frame == nil ? L("Add Frame") : L("Edit Frame"), .frame)
                                if node.frame != nil { row("rectangle.slash", L("Remove Frame"), .removeFrame, destructive: true) }
                            }
                        }
                        nested("ai", "sparkles", L("Minor’s Actions")) {
                            row("sparkles", isRoot ? L("Expand All") : L("Expand with AI"), .expand)
                            row("lightbulb", L("Find Examples"), .examples)
                            row("questionmark.bubble", L("Questions"), .questions)
                            row("checklist", L("Next Steps"), .nextSteps)
                            row("wand.and.stars", node.image == nil ? L("Create Image with AI") : L("New AI Image"), .aiImage)
                        }
                        .disabled(busy)
                        if hasOrder {
                            nested("order", "arrow.up.arrow.down", L("Order")) {
                                if !isRoot { row("plus.square.on.square", L("Add at the Same Level"), .addSibling) }
                                if !isRoot && siblingIndex > 0 { row("arrow.up", L("Move Up"), .moveUp) }
                                if !isRoot && siblingIndex < siblingCount - 1 { row("arrow.down", L("Move Down"), .moveDown) }
                                if !node.children.isEmpty {
                                    row(node.isCollapsed ? "plus.circle" : "minus.circle", node.isCollapsed ? L("Expand Branch") : L("Collapse Branch"), .toggleCollapse)
                                }
                            }
                        }
                    }
                    if !isRoot {
                        group { row("trash", L("Delete Branch"), .delete, destructive: true) }
                    }
                } else {
                    group {
                        row("text.alignleft", L("Note"), .note)
                        row("doc.text.magnifyingglass", L("Sources"), .sources)
                        if !isRoot { row("scope", L("Focus on Branch"), .focus) }
                    }
                    Label("This map is shared with you to view.", systemImage: "eye")
                        .minorFont(13, maxScale: 1.3)
                        .foregroundColor(MinorColor.textTertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            // Clear of the home indicator, so Delete is never at the very edge.
            .padding(.bottom, 28)
        }
        .foregroundColor(MinorColor.textPrimary)
        .background(MinorColor.editorSheet.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private var hasOrder: Bool { !isRoot || !node.children.isEmpty }

    // A row that opens its own rows below it.
    @ViewBuilder
    private func nested<Content: View>(_ id: String, _ icon: String, _ title: String, @ViewBuilder content: () -> Content) -> some View {
        let expanded = open.contains(id)
        Button {
            withAnimation(.minorMenu) {
                if expanded { open.remove(id) } else { open.insert(id) }
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 16)).frame(width: 26)
                Text(title).minorFont(15, maxScale: 1.3)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MinorColor.textTertiary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
            }
            .foregroundColor(MinorColor.textPrimary)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1).padding(.leading, 54) }
        .accessibilityValue(expanded ? Text("Expanded") : Text("Collapsed"))
        if expanded {
            VStack(spacing: 0) { content() }
                .padding(.leading, 16)
                .background(Color.white.opacity(0.025))
        }
    }

    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func row(_ icon: String, _ title: String, _ action: NodeAction, destructive: Bool = false) -> some View {
        Button {
            dismiss()
            // After the sheet has gone, so the next sheet or the move mode can open.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onAction(action) }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 16)).frame(width: 26)
                Text(title).minorFont(15, maxScale: 1.3)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundColor(MinorColor.textTertiary)
            }
            .foregroundColor(destructive ? MinorColor.dangerText : MinorColor.textPrimary)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1).padding(.leading, 54) }
    }
}

// Choosing an idea from a list, with search and the path to each: where a branch goes (the branch
// itself and its own ideas aren't offered, nor where it already is), or what an idea connects to
// (any other idea; one already connected says so).
struct MoveTargetPicker: View {
    enum Purpose { case move, connect }

    let map: MindMap
    let moving: UUID
    var purpose: Purpose = .move
    var onPick: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var connected: Set<UUID> {
        Set(map.links.compactMap { $0.from == moving ? $0.to : $0.to == moving ? $0.from : nil })
    }

    private var excluded: Set<UUID> {
        if purpose == .connect { return [moving] }
        guard let node = map.root.node(moving) else { return [] }
        var ids: Set<UUID> = []
        func walk(_ n: MindNode) { ids.insert(n.id); n.children.forEach(walk) }
        walk(node)
        if let parent = map.root.parent(of: moving) { ids.insert(parent.id) }
        return ids
    }

    private var entries: [(node: MindNode, depth: Int, path: String)] {
        var out: [(MindNode, Int, String)] = []
        func walk(_ node: MindNode, _ depth: Int, _ path: [String]) {
            guard node.id != moving || purpose == .connect else { return }
            out.append((node, depth, path.joined(separator: " › ")))
            for child in node.children where !child.isSuggestion { walk(child, depth + 1, path + [node.title]) }
        }
        walk(map.root, 0, [])
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return q.isEmpty ? out : out.filter { $0.0.title.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(entries, id: \.node.id) { entry in
                    let blocked = excluded.contains(entry.node.id)
                    Button {
                        guard !blocked else { return }
                        onPick(entry.node.id)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.node.title.isEmpty ? L("Untitled") : entry.node.title)
                                .minorFont(16, maxScale: 1.3)
                                .foregroundColor(blocked ? MinorColor.textTertiary : MinorColor.textPrimary)
                            if !entry.path.isEmpty, !query.isEmpty {
                                Text(entry.path).minorFont(12, maxScale: 1.3).foregroundColor(MinorColor.textTertiary).lineLimit(1)
                            }
                            if purpose == .move, blocked, entry.node.id == map.root.parent(of: moving)?.id {
                                Text("It is already here").minorFont(12, maxScale: 1.3).foregroundColor(MinorColor.textTertiary)
                            }
                            if purpose == .connect, connected.contains(entry.node.id) {
                                Text("Already connected").minorFont(12, maxScale: 1.3).foregroundColor(MinorColor.textTertiary)
                            }
                        }
                        .padding(.leading, query.isEmpty ? CGFloat(entry.depth) * 16 : 0)
                    }
                    .disabled(blocked)
                    .listRowBackground(Color.white.opacity(0.04))
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .searchable(text: $query, prompt: Text("Search ideas"))
            .background(MinorColor.editorSheet.ignoresSafeArea())
            .navigationTitle(purpose == .move ? Text("New Parent") : Text("Connect To"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .tint(.white)
        .preferredColorScheme(.dark)
    }
}
