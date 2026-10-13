//
//  DiagramModel.swift
//  Minor Ai
//
//  Diagrams on slides as data, not pictures: nodes and connections with ids, in one of four kinds.
//  - Process: steps in order with directed connections; inserting after a step splits its
//    connection to the next one in two. Extra connections are added explicitly.
//  - Cycle: the same, and the last step leads back to the first; none for 0 or 1 step.
//  - Hierarchy: one parent each; moving a branch changes its parent, never onto itself or below
//    itself; removing asks whether the branch goes too or its children move up. "Around the center"
//    draws one level around the root (the diagrams made before 2.1).
//  - Matrix: a 2×2 with labelled quadrants, or points placed by their values on two axes. Moving an
//    item changes its data; switching between the two keeps both.
//  Diagrams saved before (`center` and `nodes`) still open: they read as a hierarchy around the
//  center with stable ids, and `center`/`nodes` stay written, so an earlier app shows the same
//  words. Changing the kind keeps connections and values the new kind doesn't draw.
//

import CryptoKit
import Foundation

enum DiagramKind: String, Codable, CaseIterable, Identifiable {
    case process, cycle, hierarchy, matrix
    var id: String { rawValue }

    var name: String {
        switch self {
        case .process: return L("Process")
        case .cycle: return L("Cycle")
        case .hierarchy: return L("Hierarchy")
        case .matrix: return L("Matrix")
        }
    }

    var icon: String {
        switch self {
        case .process: return "arrow.right"
        case .cycle: return "arrow.triangle.2.circlepath"
        case .hierarchy: return "point.3.connected.trianglepath.dotted"
        case .matrix: return "square.grid.2x2"
        }
    }
}

struct DiagramNode: Codable, Equatable, Identifiable {
    var id = UUID()
    var label: String
    var icon: String?          // an SF Symbol
    var parent: UUID?          // hierarchy
    var position: [Double]?    // manual layout: the center in slide points (1280 × 720)
    var value: [Double]?       // matrix by values: x, y on the axes
    var quadrant: Int?         // 2×2 matrix: 0 top left, 1 top right, 2 bottom left, 3 bottom right

    init(id: UUID = UUID(), label: String, icon: String? = nil, parent: UUID? = nil) {
        self.id = id
        self.label = label
        self.icon = icon
        self.parent = parent
    }
}

struct DiagramEdge: Codable, Equatable, Identifiable {
    var id = UUID()
    var from: UUID
    var to: UUID
    var label = ""
    var directed = true
    var sequence = false       // the connection that follows the order of steps (process, cycle)
}

struct DiagramAxis: Codable, Equatable {
    var title = ""
    var low = ""               // what the start of the axis means
    var high = ""
    var min = 0.0
    var max = 10.0
}

struct DiagramAxes: Codable, Equatable {
    var x = DiagramAxis()
    var y = DiagramAxis()
    var quadrants = ["", "", "", ""]
}

enum DiagramArrangement: String, Codable { case auto, manual }
enum MatrixMode: String, Codable { case quadrants, values }

struct SlideDiagram: Codable, Equatable {
    // Written by every version (earlier apps read only these).
    var center = ""
    var nodes: [String] = []
    // Since 2.1.
    var kind: DiagramKind?
    var items: [DiagramNode]?
    var edges: [DiagramEdge]?
    var arrangement: DiagramArrangement?
    var radial: Bool?                 // hierarchy drawn around its center
    var matrix: MatrixMode?
    var axes: DiagramAxes?
    var filled: Bool?                 // nodes filled with their color, or outlined
    var showIcons: Bool?

    init(center: String = "", nodes: [String] = []) {
        self.center = center
        self.nodes = nodes
    }

    private enum CodingKeys: String, CodingKey { case center, nodes, kind, items, edges, arrangement, radial, matrix, axes, filled, showIcons }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        center = (try? c.decodeIfPresent(String.self, forKey: .center)) ?? ""
        nodes = (try? c.decodeIfPresent([String].self, forKey: .nodes)) ?? []
        kind = try? c.decodeIfPresent(DiagramKind.self, forKey: .kind)
        items = try? c.decodeIfPresent([DiagramNode].self, forKey: .items)
        edges = try? c.decodeIfPresent([DiagramEdge].self, forKey: .edges)
        arrangement = try? c.decodeIfPresent(DiagramArrangement.self, forKey: .arrangement)
        radial = try? c.decodeIfPresent(Bool.self, forKey: .radial)
        matrix = try? c.decodeIfPresent(MatrixMode.self, forKey: .matrix)
        axes = try? c.decodeIfPresent(DiagramAxes.self, forKey: .axes)
        filled = try? c.decodeIfPresent(Bool.self, forKey: .filled)
        showIcons = try? c.decodeIfPresent(Bool.self, forKey: .showIcons)
    }

    var isStructured: Bool { items != nil }

    // The diagram with ids: as saved, or (made before 2.1) a hierarchy around its center whose ids
    // come from the slide, so they stay the same until it is first changed.
    func structured(slideID: UUID) -> SlideDiagram {
        guard items == nil else { return self }
        var copy = self
        // A diagram of 2.1 with nothing in it yet (only earlier ones have no kind).
        if kind != nil {
            copy.items = []
            copy.edges = []
            return copy
        }
        let root = DiagramNode(id: Self.stableID(slideID, "root"), label: center)
        let children = nodes.enumerated().map { i, label in DiagramNode(id: Self.stableID(slideID, "n\(i)"), label: label, parent: root.id) }
        copy.kind = .hierarchy
        copy.radial = true
        copy.items = [root] + children
        copy.edges = []
        return copy
    }

    static func stableID(_ slide: UUID, _ key: String) -> UUID {
        let digest = Array(SHA256.hash(data: Data("\(slide.uuidString)/\(key)".utf8)))
        let bytes = (0..<16).map { digest[$0] }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], (bytes[6] & 0x0F) | 0x50, bytes[7],
                           (bytes[8] & 0x3F) | 0x80, bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    // `center` and `nodes` as an earlier app would show them: the root (or the title) and the labels.
    mutating func syncLegacy(title: String) {
        guard let items else { return }
        switch kind ?? .hierarchy {
        case .hierarchy:
            let root = items.first { $0.parent == nil }
            center = root?.label ?? title
            nodes = items.filter { $0.id != root?.id }.map(\.label)
        default:
            center = title
            nodes = items.map(\.label)
        }
    }

    var allItems: [DiagramNode] { items ?? [] }
    var allEdges: [DiagramEdge] { edges ?? [] }
}

// MARK: - Editing

// What an edit couldn't do, said to the person.
enum DiagramProblem: Error, Equatable {
    case missingNode
    case sameNode
    case duplicate
    case wouldLoop
}

// The consequences of removing a node, shown before it happens.
struct RemovalImpact: Equatable {
    var edges: [DiagramEdge]      // connections that go with it
    var reconnects: Bool          // its neighbours in the sequence are joined
    var children: Int             // hierarchy: ideas below it
}

extension SlideDiagram {
    var kindValue: DiagramKind { kind ?? .hierarchy }

    func node(_ id: UUID) -> DiagramNode? { allItems.first { $0.id == id } }

    // Steps in order (process, cycle): the items as listed.
    var steps: [DiagramNode] { allItems }

    // MARK: Sequence (process, cycle)

    // The sequence connections for the order of steps: reused where the same pair was already
    // connected (its id and label stay), new where it wasn't; the cycle closes back to the first.
    mutating func rebuildSequence() {
        guard kindValue == .process || kindValue == .cycle else { return }
        let ids = allItems.map(\.id)
        let old = allEdges.filter(\.sequence)
        var pairs: [(UUID, UUID)] = zip(ids, ids.dropFirst()).map { ($0, $1) }
        if kindValue == .cycle, ids.count > 2, let first = ids.first, let last = ids.last { pairs.append((last, first)) }
        if kindValue == .cycle, ids.count == 2 { pairs = [(ids[0], ids[1])] }
        let sequence = pairs.map { pair in
            old.first { $0.from == pair.0 && $0.to == pair.1 } ?? DiagramEdge(from: pair.0, to: pair.1, sequence: true)
        }
        edges = sequence + allEdges.filter { !$0.sequence && ids.contains($0.from) && ids.contains($0.to) }
    }

    // A new step after `after` (or at the end): its connection to the next step is split in two.
    @discardableResult
    mutating func insertStep(after: UUID?, label: String) -> UUID {
        var list = allItems
        let node = DiagramNode(label: label)
        let at = after.flatMap { id in list.firstIndex { $0.id == id } }.map { $0 + 1 } ?? list.count
        list.insert(node, at: at)
        items = list
        rebuildSequence()
        return node.id
    }

    mutating func moveStep(_ id: UUID, by offset: Int) {
        var list = allItems
        guard let from = list.firstIndex(where: { $0.id == id }) else { return }
        let to = min(max(from + offset, 0), list.count - 1)
        guard to != from else { return }
        list.insert(list.remove(at: from), at: to)
        items = list
        rebuildSequence()
    }

    // MARK: Hierarchy

    @discardableResult
    mutating func addChild(to parent: UUID?, label: String) -> UUID {
        var node = DiagramNode(label: label)
        node.parent = parent ?? allItems.first { $0.parent == nil }?.id
        items = allItems + [node]
        // "Around the center" draws one level; a deeper idea makes it a tree.
        if radial == true, let parent = node.parent, self.node(parent)?.parent != nil { radial = false }
        return node.id
    }

    func descendants(of id: UUID) -> Set<UUID> {
        var found: Set<UUID> = []
        var queue = [id]
        while let next = queue.popLast() {
            for child in allItems where child.parent == next && !found.contains(child.id) {
                found.insert(child.id)
                queue.append(child.id)
            }
        }
        return found
    }

    // A branch moves under another parent; never under itself or its own branch.
    mutating func move(_ id: UUID, under parent: UUID) throws {
        guard node(id) != nil, node(parent) != nil else { throw DiagramProblem.missingNode }
        guard id != parent else { throw DiagramProblem.sameNode }
        guard !descendants(of: id).contains(parent) else { throw DiagramProblem.wouldLoop }
        items = allItems.map { item in
            var item = item
            if item.id == id { item.parent = parent }
            return item
        }
        if radial == true, node(parent)?.parent != nil { radial = false }
    }

    // MARK: Removing

    func impactOfRemoving(_ id: UUID) -> RemovalImpact {
        let touching = allEdges.filter { $0.from == id || $0.to == id }
        let sequential = (kindValue == .process || kindValue == .cycle) && touching.filter(\.sequence).count == 2
        return RemovalImpact(edges: touching, reconnects: sequential, children: kindValue == .hierarchy ? descendants(of: id).count : 0)
    }

    // Removes a node and its connections. In a process or cycle its neighbours are joined; in a
    // hierarchy its branch goes too, or (`liftChildren`) its children move up to its parent.
    mutating func remove(_ id: UUID, liftChildren: Bool = false) {
        guard let removed = node(id) else { return }
        var gone: Set<UUID> = [id]
        if kindValue == .hierarchy {
            if liftChildren {
                items = allItems.map { item in
                    var item = item
                    if item.parent == id { item.parent = removed.parent }
                    return item
                }
            } else {
                gone.formUnion(descendants(of: id))
            }
        }
        items = allItems.filter { !gone.contains($0.id) }
        edges = allEdges.filter { !gone.contains($0.from) && !gone.contains($0.to) }
        rebuildSequence()
    }

    // MARK: Connections

    @discardableResult
    mutating func connect(_ from: UUID, _ to: UUID, label: String = "") throws -> UUID {
        guard node(from) != nil, node(to) != nil else { throw DiagramProblem.missingNode }
        guard from != to else { throw DiagramProblem.sameNode }
        if allEdges.contains(where: { $0.from == from && $0.to == to }) || kindValue == .hierarchy && (node(to)?.parent == from) {
            throw DiagramProblem.duplicate
        }
        let edge = DiagramEdge(from: from, to: to, label: label)
        edges = allEdges + [edge]
        return edge.id
    }

    mutating func changeEdge(_ id: UUID, from: UUID? = nil, to: UUID? = nil) throws {
        guard let edge = allEdges.first(where: { $0.id == id }) else { throw DiagramProblem.missingNode }
        let start = from ?? edge.from, end = to ?? edge.to
        guard node(start) != nil, node(end) != nil else { throw DiagramProblem.missingNode }
        guard start != end else { throw DiagramProblem.sameNode }
        guard !allEdges.contains(where: { $0.id != id && $0.from == start && $0.to == end }) else { throw DiagramProblem.duplicate }
        updateEdge(id) {
            $0.from = start
            $0.to = end
            $0.sequence = false   // no longer the plain next step
        }
    }

    mutating func updateEdge(_ id: UUID, _ change: (inout DiagramEdge) -> Void) {
        edges = allEdges.map { edge in
            var edge = edge
            if edge.id == id { change(&edge) }
            return edge
        }
    }

    mutating func removeEdge(_ id: UUID) {
        edges = allEdges.filter { $0.id != id }
    }

    mutating func updateNode(_ id: UUID, _ change: (inout DiagramNode) -> Void) {
        items = allItems.map { item in
            var item = item
            if item.id == id { change(&item) }
            return item
        }
    }

    // MARK: Matrix

    var axesValue: DiagramAxes { axes ?? DiagramAxes() }

    // The quadrant of a value (by the middle of each axis), and the middle of a quadrant as a value.
    func quadrant(of value: [Double]) -> Int {
        let a = axesValue
        let right = value[0] >= (a.x.min + a.x.max) / 2
        let top = value[1] >= (a.y.min + a.y.max) / 2
        return (top ? 0 : 2) + (right ? 1 : 0)
    }

    func value(inQuadrant q: Int) -> [Double] {
        let a = axesValue
        let x = a.x.min + (q % 2 == 0 ? 0.25 : 0.75) * (a.x.max - a.x.min)
        let y = a.y.min + (q < 2 ? 0.75 : 0.25) * (a.y.max - a.y.min)
        return [x, y]
    }

    // Switching between quadrants and values keeps both: what is missing is filled from the other.
    mutating func setMatrixMode(_ mode: MatrixMode) {
        matrix = mode
        items = allItems.enumerated().map { i, item in
            var item = item
            if item.quadrant == nil { item.quadrant = item.value.map { quadrant(of: $0) } ?? i % 4 }
            if item.value == nil { item.value = value(inQuadrant: item.quadrant ?? 0) }
            return item
        }
    }

    // MARK: Changing the kind

    // What a change of kind does, before it happens.
    func conversionNotes(to target: DiagramKind) -> [String] {
        guard target != kindValue else { return [] }
        var notes: [String] = []
        let extra = allEdges.filter { !$0.sequence }.count
        switch (kindValue, target) {
        case (.process, .cycle):
            if allItems.count > 2 { notes.append(L("The last step will lead back to the first.")) }
        case (.cycle, .process):
            if allItems.count > 2 { notes.append(L("The connection from the last step back to the first goes.")) }
        case (_, .hierarchy):
            notes.append(L("The first item becomes the top; the others go under it."))
            if extra > 0 { notes.append(L("Extra connections stay: \(extra).")) }
        case (.hierarchy, .process), (.hierarchy, .cycle):
            notes.append(L("Items become steps in reading order; the branches become one sequence."))
        case (_, .matrix):
            notes.append(L("Items are placed in the quadrants; set them where they belong."))
            if !allEdges.isEmpty { notes.append(L("A matrix doesn’t draw connections. They are kept and come back with another kind.")) }
        case (.matrix, _):
            notes.append(L("Positions in the matrix are kept and come back if you switch back."))
        default:
            break
        }
        return notes
    }

    // The diagram as another kind. Nothing is dropped silently: connections a kind doesn't draw and
    // matrix values stay in the data.
    func converted(to target: DiagramKind) -> SlideDiagram {
        guard target != kindValue else { return self }
        var copy = self
        let from = kindValue
        copy.kind = target
        switch target {
        case .process, .cycle:
            if from == .hierarchy {
                // Reading order: depth first from the root.
                var ordered: [DiagramNode] = []
                func walk(_ parent: UUID?) {
                    for item in allItems where item.parent == parent {
                        ordered.append(item)
                        walk(item.id)
                    }
                }
                walk(nil)
                ordered += allItems.filter { item in !ordered.contains { $0.id == item.id } }
                copy.items = ordered.map { var item = $0; item.parent = nil; return item }
            }
            copy.radial = nil
            copy.rebuildSequence()
        case .hierarchy:
            let root = allItems.first
            copy.items = allItems.map { item in
                var item = item
                item.parent = item.id == root?.id ? nil : root?.id
                return item
            }
            copy.edges = allEdges.filter { !$0.sequence }
            copy.radial = false
        case .matrix:
            copy.setMatrixMode(matrix ?? .quadrants)
        }
        return copy
    }
}
