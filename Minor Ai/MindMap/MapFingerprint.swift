//
//  MapFingerprint.swift
//  Minor Ai
//
//  A fingerprint of what a map (or a branch) says: titles, notes, tasks, dates, priorities, links,
//  icons, pictures and the order of ideas. Collapsing, zoom, pins, focus and styling don't change
//  it, and neither do suggestions waiting for a decision. A presentation keeps the fingerprint of
//  the content it was made from, so the app can tell when the map has really changed since.
//

import CryptoKit
import Foundation

extension MindNode {
    var contentFingerprint: String {
        var text = ""
        func walk(_ node: MindNode, depth: Int) {
            guard !node.isSuggestion else { return }
            text += "\(depth)|\(node.title)|\(node.note)|\(node.isTask ? 1 : 0)\(node.isDone ? 1 : 0)|\(node.priority ?? 0)|"
            text += "\(node.due.map { Int($0.timeIntervalSince1970) } ?? 0)|\(node.link ?? "")|\(node.icon ?? "")|\(node.image?.id.uuidString ?? "")|\(node.isCallout ? 1 : 0)\n"
            for child in node.children { walk(child, depth: depth + 1) }
        }
        walk(self, depth: 0)
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}

extension MindMap {
    var contentFingerprint: String { root.contentFingerprint }

    // The branch as a map of its own (for slides made from one branch), keeping the map's design.
    func branch(_ id: UUID) -> MindMap? {
        guard let node = root.node(id) else { return nil }
        var copy = self
        copy.root = node
        copy.links = links.filter { node.node($0.from) != nil && node.node($0.to) != nil }
        return copy
    }
}

extension Deck {
    // What the deck was made from, as it is now: the map, or the branch (nil when it is gone).
    @MainActor var sourceContent: MindMap? {
        guard let mapID = sourceMapID, let map = MapStore.shared.map(mapID) else { return nil }
        if let nodeID = sourceNodeID { return map.branch(nodeID) }
        return map
    }

    // The source changed since the slides were made (or last updated from it). Unknown for decks
    // made before fingerprints existed.
    @MainActor var sourceChanged: Bool {
        guard let revision = sourceRevision, let content = sourceContent else { return false }
        return content.contentFingerprint != revision
    }
}
