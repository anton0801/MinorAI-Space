//
//  MapEditProposal.swift
//  Minor Ai
//
//  A change Minor suggests for the map from the command field, shown before it happens: new ideas
//  dashed on the map, a short list of what changes, Apply and Cancel. Applying checks that the map
//  is still as it was when Minor read it; nothing is written over newer edits.
//

import SwiftUI

struct MapEditProposal: Equatable {
    struct Row: Identifiable, Equatable {
        enum Kind: Equatable { case added, changed, removed }
        let id = UUID()
        let kind: Kind
        let text: String
        let detail: String?
        var parent: String? = nil
    }

    let command: String
    let proposal: MindNode      // the map's tree as it would be
    let base: String            // editFingerprint of the tree Minor read
    let rows: [Row]
    let addedIDs: Set<UUID>
    let diff: MapDiff

    init(command: String, current: MindNode, proposal: MindNode) {
        self.command = command
        self.proposal = proposal.keepingCollapse(from: current)
        base = current.editFingerprint
        diff = MapDiff(old: current, new: proposal)
        var before: [UUID: MindNode] = [:]
        func collect(_ node: MindNode, into table: inout [UUID: MindNode]) {
            table[node.id] = node
            node.children.forEach { collect($0, into: &table) }
        }
        collect(current, into: &before)
        var after: [UUID: MindNode] = [:]
        collect(proposal, into: &after)

        var rows: [Row] = []
        var added: Set<UUID> = []
        // New ideas, each with the idea it goes under (a new branch counts once, with what's inside).
        func walkNew(_ node: MindNode, parent: MindNode?) {
            if before[node.id] == nil {
                added.formUnion(MindNode.allIDs(in: node))
                let inside = node.count - 1
                rows.append(Row(kind: .added, text: node.title, detail: [parent?.title, inside > 0 ? L("Ideas inside: \(inside)") : nil].compactMap { $0 }.joined(separator: " · "), parent: parent?.title))
                return
            }
            node.children.forEach { walkNew($0, parent: node) }
        }
        walkNew(proposal, parent: nil)
        // Renamed or otherwise changed ideas.
        for (id, new) in after {
            guard let old = before[id] else { continue }
            if old.title != new.title {
                rows.append(Row(kind: .changed, text: new.title, detail: L("was “\(old.title)”")))
            } else if old.note != new.note || old.isTask != new.isTask || old.priority != new.priority || old.icon != new.icon || old.link != new.link {
                rows.append(Row(kind: .changed, text: new.title, detail: L("details change")))
            }
        }
        // Removed ideas (a removed branch counts once).
        func walkOld(_ node: MindNode) {
            if after[node.id] == nil {
                let inside = node.count - 1
                rows.append(Row(kind: .removed, text: node.title, detail: inside > 0 ? L("with \(inside) ideas inside") : nil))
                return
            }
            node.children.forEach(walkOld)
        }
        walkOld(current)
        self.rows = rows
        addedIDs = added
    }

    // What the map shows meanwhile: the proposed tree, new ideas dashed and in view.
    var preview: MindNode {
        var root = proposal
        func mark(_ node: inout MindNode) -> Bool {
            var hasNew = addedIDs.contains(node.id)
            if hasNew { node.isSuggestion = true }
            for i in node.children.indices where mark(&node.children[i]) { hasNew = true }
            if hasNew && !addedIDs.contains(node.id) { node.isCollapsed = false }
            return hasNew
        }
        _ = mark(&root)
        return root
    }

    // The first new idea in map order.
    func firstNewID() -> UUID? { proposal.firstNew(in: addedIDs) }

    // "2 ideas for “Format”" when everything new goes under one idea; otherwise the counts.
    var headline: String {
        if headlineNamesParent, let parent = rows.first?.parent {
            return L("Ideas for “\(parent)”: \(rows.count)")
        }
        return diff.summary
    }

    // Everything is new and goes under the same idea, so the headline can name it.
    var headlineNamesParent: Bool {
        let added = rows.filter { $0.kind == .added }
        guard !added.isEmpty, added.count == rows.count, let parent = added.first?.parent else { return false }
        return added.allSatisfy { $0.parent == parent }
    }
}

// The bottom panel while a proposal waits: what changes, Apply and Cancel.
struct MapEditProposalPanel: View {
    // Up to four changes as they are; more scroll.
    @ViewBuilder
    private var rowsList: some View {
        if proposal.rows.count > 4 {
            ScrollView { rows }
        } else {
            rows
        }
    }

    // When the headline already names the idea everything goes under, rows don't repeat it.
    private func detail(_ row: MapEditProposal.Row) -> String? {
        guard let detail = row.detail, !detail.isEmpty else { return nil }
        if proposal.headlineNamesParent, let parent = row.parent {
            let rest = detail.replacingOccurrences(of: parent, with: "").trimmingCharacters(in: CharacterSet(charactersIn: " ·"))
            return rest.isEmpty ? nil : rest
        }
        return detail
    }

    private var rows: some View {
        VStack(spacing: 6) {
            ForEach(proposal.rows.prefix(8)) { row in
                HStack(spacing: 12) {
                    Image(systemName: row.kind == .added ? "plus" : row.kind == .changed ? "pencil" : "minus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(row.kind == .removed ? MinorColor.dangerText : .white)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(row.kind == .added ? BranchColor.lilac.color.opacity(0.85) : Color.white.opacity(0.12)))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.text)
                            .minorFont(15, maxScale: 1.3)
                            .strikethrough(row.kind == .removed)
                            .lineLimit(2)
                        if let detail = detail(row) {
                            Text(detail).minorFont(12, style: .caption1, maxScale: 1.3).foregroundColor(MinorColor.textTertiary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06), lineWidth: 1))
                .accessibilityElement(children: .combine)
            }
            if proposal.rows.count > 8 {
                Text(L("And more: \(proposal.rows.count - 8)"))
                    .minorFont(13, maxScale: 1.3)
                    .foregroundColor(MinorColor.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    let proposal: MapEditProposal
    let stale: Bool
    let theme: AppTheme
    var onApply: () -> Void
    var onCancel: () -> Void
    var onAskAgain: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Capsule()
                .fill(Color.white.opacity(0.22))
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Suggestion from Minor")
                    .minorFont(12, maxScale: 1.3)
                    .foregroundColor(MinorColor.textTertiary)
                Text(proposal.headline)
                    .minorFont(19, .bold, maxScale: 1.25)
                    .lineLimit(2)
            }
            .accessibilityElement(children: .combine)
            rowsList
                .frame(maxHeight: proposal.rows.count > 4 ? 230 : nil)
            Text(stale ? L("The map changed after Minor read it, so this can’t be applied safely.") : L("The rest of the map stays as it is."))
                .minorFont(12, style: .caption1, maxScale: 1.3)
                .foregroundColor(stale ? BranchColor.sun.color : MinorColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: stale ? onAskAgain : onApply) {
                Text(stale ? L("Ask Again") : L("Apply"))
                    .minorFont(16, .semibold, maxScale: 1.3)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white))
            }
            .buttonStyle(PressScale())
            Button(action: onCancel) {
                Text("Cancel")
                    .minorFont(15, maxScale: 1.3)
                    .foregroundColor(MinorColor.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 26)
                .fill(MinorColor.editorSheet)
                .overlay(RoundedRectangle(cornerRadius: 26).stroke(Color.white.opacity(0.08), lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 24, y: 6)
        )
        .padding(.horizontal, -8)
    }
}

extension MindNode {
    // The first idea (in map order) whose id is in `ids`.
    func firstNew(in ids: Set<UUID>) -> UUID? {
        if ids.contains(id) { return id }
        for child in children { if let found = child.firstNew(in: ids) { return found } }
        return nil
    }
}

