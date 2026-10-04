//
//  CollabMerge.swift
//  Minor Ai
//
//  Three-way merge of a shared map: the last version both sides had (base), this device's
//  version (local) and the server's (remote). Each idea is merged on its own, so two people
//  editing different ideas never lose each other's work. When both changed the same idea,
//  this device's change wins; a delete on either side removes the idea.
//

import Foundation

enum CollabMerge {
    private struct Entry {
        var node: MindNode          // without children
        var parent: UUID?
        var index: Int
    }

    // Ideas top-down (a parent before its children), so new branches are added whole.
    private static func order(_ root: MindNode) -> [UUID] {
        var ids: [UUID] = []
        func walk(_ node: MindNode) {
            ids.append(node.id)
            node.children.forEach(walk)
        }
        walk(root)
        return ids
    }

    private static func flatten(_ root: MindNode) -> [UUID: Entry] {
        var result: [UUID: Entry] = [:]
        func walk(_ node: MindNode, parent: UUID?, index: Int) {
            var bare = node
            bare.children = []
            result[node.id] = Entry(node: bare, parent: parent, index: index)
            for (i, child) in node.children.enumerated() { walk(child, parent: node.id, index: i) }
        }
        walk(root, parent: nil, index: 0)
        return result
    }

    // Fields compared without the person's own view state (what is folded on their screen).
    private static func same(_ a: MindNode, _ b: MindNode) -> Bool {
        var x = a, y = b
        x.isCollapsed = false
        y.isCollapsed = false
        x.isAIAdded = false
        y.isAIAdded = false
        return x == y
    }

    static func merge(base: MindMap, local: MindMap, remote: MindMap) -> MindMap {
        let b = flatten(base.root), l = flatten(local.root)
        var r = flatten(remote.root)

        // Deleted here: gone from the result too (with everything below it).
        let deletedHere = Set(b.keys).subtracting(l.keys)
        func removeSubtree(_ id: UUID) {
            r[id] = nil
            for (child, entry) in r where entry.parent == id { removeSubtree(child) }
        }
        for id in deletedHere where id != remote.root.id { removeSubtree(id) }

        // Changed or moved here, top-down so a new parent exists before its new children.
        for id in order(local.root) {
            guard let mine = l[id] else { continue }
            if let was = b[id] {
                guard r[id] != nil else { continue }                 // deleted there: stays deleted
                if !same(mine.node, was.node) {
                    var node = mine.node
                    node.isCollapsed = r[id]!.node.isCollapsed
                    r[id]!.node = node
                }
                if mine.parent != was.parent, let parent = mine.parent, r[parent] != nil {
                    r[id]!.parent = parent
                    r[id]!.index = mine.index
                }
            } else if r[id] == nil {
                // Added here.
                let parent = mine.parent.flatMap { r[$0] != nil ? $0 : nil } ?? remote.root.id
                r[id] = Entry(node: mine.node, parent: parent, index: mine.index)
            }
        }

        // Two people moving branches into each other can make a loop that no longer hangs from
        // the root; such ideas go back under the root instead of disappearing.
        reattachLoops(&r, root: remote.root.id)

        // Rebuild the tree in order: the server's order, with ideas added or moved here at
        // their place here. Folded branches stay as this person left them.
        let remoteOrder = flatten(remote.root)
        var children: [UUID: [(key: UUID, value: Entry)]] = [:]
        for (id, entry) in r { if let parent = entry.parent { children[parent, default: []].append((id, entry)) } }
        func build(_ id: UUID) -> MindNode {
            var node = r[id]!.node
            if let mine = l[id] { node.isCollapsed = mine.node.isCollapsed }
            let kids = children[id] ?? []
            let sorted = kids.sorted { a, c in
                let ia = remoteOrder[a.key]?.parent == id ? Double(remoteOrder[a.key]!.index) : Double(a.value.index) - 0.5
                let ic = remoteOrder[c.key]?.parent == id ? Double(remoteOrder[c.key]!.index) : Double(c.value.index) - 0.5
                return ia == ic ? a.key.uuidString < c.key.uuidString : ia < ic
            }
            node.children = sorted.map { build($0.key) }
            return node
        }

        var merged = remote
        merged.root = build(remote.root.id)

        // Connections: added and removed here are applied to the server's set.
        // (Duplicate ids in data from elsewhere keep the first one instead of crashing.)
        let baseLinks = Dictionary(base.links.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let localLinks = Dictionary(local.links.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var links = Dictionary(remote.links.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (id, link) in localLinks where baseLinks[id] != link { links[id] = link }
        for id in Set(baseLinks.keys).subtracting(localLinks.keys) { links[id] = nil }
        let remoteIDs = Set(remote.links.map(\.id))
        var seen = Set<UUID>()
        merged.links = (remote.links.compactMap { links[$0.id] } + local.links.filter { links[$0.id] != nil && !remoteIDs.contains($0.id) })
            .filter { seen.insert($0.id).inserted }
        merged.dropBrokenLinks()

        // Map design: a change here wins; otherwise the server's.
        if local.style != base.style { merged.style = local.style }
        if local.palette != base.palette { merged.palette = local.palette }
        if local.lines != base.lines { merged.lines = local.lines }
        if local.lineWeight != base.lineWeight { merged.lineWeight = local.lineWeight }
        if local.canvas != base.canvas { merged.canvas = local.canvas }
        // How the map is laid out and pinned is this person's own choice.
        merged.layout = local.layout
        merged.isPinned = local.isPinned
        return merged
    }

    private static func reattachLoops(_ r: inout [UUID: Entry], root: UUID) {
        func reachesRoot(_ start: UUID) -> Bool {
            var seen: Set<UUID> = []
            var current: UUID? = start
            while let id = current {
                if id == root { return true }
                guard seen.insert(id).inserted, let entry = r[id] else { return false }
                current = entry.parent
            }
            return false
        }
        for id in r.keys.sorted(by: { $0.uuidString < $1.uuidString }) where id != root && !reachesRoot(id) {
            r[id]?.parent = root
        }
    }
}
