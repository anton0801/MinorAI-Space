//
//  MindMapModel.swift
//  Minor Ai
//
//  A mind map is a tree with one root. A node's color is inherited by its descendants until
//  one of them sets its own (level-1 nodes take the palette's colors by default).
//

import Foundation

struct MindNode: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var note: String = ""
    var children: [MindNode] = []
    var isCollapsed = false
    var isAIAdded = false
    var color: BranchColor?   // inherited by descendants that don't set their own
    var look: NodeLook?       // shape, fill and text; nil follows the map style
    var image: NodeImage?     // a photo or AI picture shown above the title
    var icon: String?         // one emoji before the title
    var isTask = false        // shows a checkbox
    var isDone = false
    var priority: Int?        // 1 (highest) … 3
    var link: String?         // a web address the idea points to
    var isCallout = false     // shown as a quote-style block for longer text
    var due: Date?            // tasks: when it should be done (a reminder is set for that day)
    var isSuggestion = false  // proposed by Improve Map; shown dashed until accepted or dismissed
    var frame: String?        // a labeled frame around this idea and everything below it ("" for no label)

    var visibleChildren: [MindNode] { isCollapsed ? [] : children }

    var count: Int { 1 + children.reduce(0) { $0 + $1.count } }

    var hiddenCount: Int { isCollapsed ? children.reduce(0) { $0 + $1.count } : 0 }

    func node(_ id: UUID) -> MindNode? {
        if self.id == id { return self }
        for child in children {
            if let found = child.node(id) { return found }
        }
        return nil
    }

    // Nodes from the root down to `id`, inclusive.
    func path(to id: UUID) -> [MindNode]? {
        if self.id == id { return [self] }
        for child in children {
            if let tail = child.path(to: id) { return [self] + tail }
        }
        return nil
    }

    @discardableResult
    mutating func update(_ id: UUID, _ change: (inout MindNode) -> Void) -> Bool {
        if self.id == id {
            change(&self)
            return true
        }
        for index in children.indices where children[index].update(id, change) {
            return true
        }
        return false
    }

    @discardableResult
    mutating func remove(_ id: UUID) -> MindNode? {
        if let index = children.firstIndex(where: { $0.id == id }) {
            return children.remove(at: index)
        }
        for index in children.indices {
            if let removed = children[index].remove(id) { return removed }
        }
        return nil
    }

    func parent(of id: UUID) -> MindNode? {
        if children.contains(where: { $0.id == id }) { return self }
        for child in children {
            if let found = child.parent(of: id) { return found }
        }
        return nil
    }

    var expandedAll: MindNode {
        var copy = self
        copy.isCollapsed = false
        copy.children = children.map(\.expandedAll)
        return copy
    }

    // Tasks among the descendants (not the node itself): how many are done, of how many.
    var taskProgress: (done: Int, total: Int) {
        children.reduce((0, 0)) { sum, child in
            let own = child.isTask ? (child.isDone ? 1 : 0, 1) : (0, 0)
            let below = child.taskProgress
            return (sum.0 + own.0 + below.done, sum.1 + own.1 + below.total)
        }
    }

    // Every picture used in this subtree (kept on disk while any map uses it).
    var imageIDs: [UUID] {
        (image.map { [$0.id] } ?? []) + children.flatMap(\.imageIDs)
    }

    var allTitles: Set<String> {
        children.reduce(into: Set([title])) { $0.formUnion($1.allTitles) }
    }

    // MARK: Suggestions

    var suggestionCount: Int { (isSuggestion ? 1 : 0) + children.reduce(0) { $0 + $1.suggestionCount } }

    // Marks this idea and everything below it as a suggestion.
    var asSuggestion: MindNode {
        var copy = self
        copy.isSuggestion = true
        copy.isAIAdded = false
        copy.children = children.map(\.asSuggestion)
        return copy
    }

    // Keeps a suggestion (with its suggested children and its suggested parents, which it needs).
    mutating func accept(_ id: UUID) {
        guard let path = path(to: id) else { return }
        for ancestor in path where ancestor.isSuggestion { update(ancestor.id) { $0.isSuggestion = false } }
        update(id) { node in
            func keep(_ node: inout MindNode) {
                node.isSuggestion = false
                for index in node.children.indices { keep(&node.children[index]) }
            }
            keep(&node)
        }
    }

    mutating func acceptAll() {
        isSuggestion = false
        for index in children.indices { children[index].acceptAll() }
    }

    mutating func dismissAll() {
        children.removeAll(where: \.isSuggestion)
        for index in children.indices { children[index].dismissAll() }
    }

    // Only the new ideas of an AI result, added as suggestions where the AI put them (matched by
    // title under the same parent). Ideas that already existed stay exactly as they were, even if
    // the AI changed or dropped them.
    func grafting(additionsFrom reply: APINode) -> (root: MindNode, added: Int) {
        var result = self
        var added = 0
        func walk(_ incoming: APINode, into existing: MindNode) {
            for child in incoming.children ?? [] {
                let wanted = child.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !wanted.isEmpty else { continue }
                if let match = existing.children.first(where: { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == wanted }) {
                    walk(child, into: match)
                } else {
                    let suggestion = child.toNode(aiAdded: false, collapseBelow: .max).asSuggestion
                    added += suggestion.count
                    result.update(existing.id) { target in
                        target.isCollapsed = false
                        target.children.append(suggestion)
                    }
                }
            }
        }
        walk(reply, into: self)
        return (result, added)
    }

    static func allIDs(in node: MindNode) -> [UUID] {
        [node.id] + node.children.flatMap { allIDs(in: $0) }
    }
}

// A picture on a node. The JPEG lives in Application Support/Maps/Images/<id>.jpg.
struct NodeImage: Codable, Equatable {
    var id: UUID
    var aspect: Double      // height / width
    var isAI = false
}

// How a whole map is drawn.
enum MapStyle: String, CaseIterable, Identifiable {
    case classic, pills, outline, minimal
    var id: String { rawValue }
}

// How one idea is drawn, set in the Style panel. "auto" follows the map style.
struct NodeLook: Codable, Equatable {
    var shape: NodeShape = .auto
    var fill: NodeFill = .auto
    var size: NodeTextSize = .regular
    var bold = false
    var dashed = false

    var isDefault: Bool { self == NodeLook() }

    init(shape: NodeShape = .auto, fill: NodeFill = .auto, size: NodeTextSize = .regular, bold: Bool = false, dashed: Bool = false) {
        self.shape = shape
        self.fill = fill
        self.size = size
        self.bold = bold
        self.dashed = dashed
    }

    // Unknown values from a newer version fall back to the defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shape = (try? c.decodeIfPresent(NodeShape.self, forKey: .shape)) ?? .auto
        fill = (try? c.decodeIfPresent(NodeFill.self, forKey: .fill)) ?? .auto
        size = (try? c.decodeIfPresent(NodeTextSize.self, forKey: .size)) ?? .regular
        bold = (try? c.decodeIfPresent(Bool.self, forKey: .bold)) ?? false
        dashed = (try? c.decodeIfPresent(Bool.self, forKey: .dashed)) ?? false
    }
}

enum NodeShape: String, Codable, CaseIterable, Identifiable {
    case auto, rounded, pill, square, ellipse, hexagon, diamond, underline
    var id: String { rawValue }
}

enum NodeFill: String, Codable, CaseIterable, Identifiable {
    case auto, soft, solid, outline, none
    var id: String { rawValue }
}

enum NodeTextSize: String, Codable, CaseIterable, Identifiable {
    case small, regular, large, huge
    var id: String { rawValue }

    // Points added to the level's font size.
    var delta: CGFloat {
        switch self {
        case .small: return -2
        case .regular: return 0
        case .large: return 3
        case .huge: return 7
        }
    }
}

// How connectors are drawn.
enum LineStyle: String, CaseIterable, Identifiable {
    case curved, straight, elbow
    var id: String { rawValue }
}

enum LineWeight: String, CaseIterable, Identifiable {
    case thin, regular, bold
    var id: String { rawValue }
    var scale: CGFloat { self == .thin ? 0.6 : self == .bold ? 2 : 1 }
}

enum CanvasBackground: String, CaseIterable, Identifiable {
    case dots, grid, plain
    var id: String { rawValue }
}

// A connection between two ideas anywhere in the map, drawn as a dashed arrow with an optional label.
struct MapLink: Codable, Equatable, Identifiable {
    var id = UUID()
    var from: UUID
    var to: UUID
    var label = ""

    init(from: UUID, to: UUID, label: String = "") {
        self.from = from
        self.to = to
        self.label = label
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        from = try c.decode(UUID.self, forKey: .from)
        to = try c.decode(UUID.self, forKey: .to)
        label = (try? c.decodeIfPresent(String.self, forKey: .label)) ?? ""
    }
}

struct MapSource: Codable, Equatable {
    enum Kind: String, Codable { case topic, document, link, youtube, voice, chat }
    var kind: Kind
    var label: String
}

struct MindMap: Identifiable, Codable, Equatable {
    var id = UUID()
    var root: MindNode
    var createdAt = Date()
    var updatedAt = Date()
    var isPinned = false
    var source: MapSource?
    var layout: String?       // "tree" (default), "balanced" or "list"
    var style: String?        // MapStyle raw value; nil is classic
    var lines: String?        // LineStyle raw value; nil is curved
    var lineWeight: String?   // LineWeight raw value; nil is regular
    var canvas: String?       // CanvasBackground raw value; nil is dots
    var palette: String?      // MapPalette raw value; nil is vivid
    var links: [MapLink] = [] // connections between ideas

    var mapStyle: MapStyle { MapStyle(rawValue: style ?? "") ?? .classic }
    var lineStyle: LineStyle { LineStyle(rawValue: lines ?? "") ?? .curved }
    var lineWeightValue: LineWeight { LineWeight(rawValue: lineWeight ?? "") ?? .regular }
    var canvasBackground: CanvasBackground { CanvasBackground(rawValue: canvas ?? "") ?? .dots }
    var mapPalette: MapPalette { MapPalette(rawValue: palette ?? "") ?? .vivid }

    var title: String { root.title }
    var nodeCount: Int { root.count }

    // The same map with every branch open, for image and PDF export.
    var fullyExpanded: MindMap {
        var copy = self
        copy.root = root.expandedAll
        return copy
    }

    // The color a node is drawn with: its own, the nearest ancestor's, or its branch's palette color.
    func branchColor(for nodeID: UUID) -> BranchColor? {
        guard let path = root.path(to: nodeID) else { return nil }
        if let own = path.last?.color { return own }
        guard path.count >= 2 else { return nil }
        if let inherited = path.dropFirst().reversed().first(where: { $0.color != nil })?.color { return inherited }
        let index = root.children.firstIndex(where: { $0.id == path[1].id }) ?? 0
        return BranchColor.forBranch(at: index, palette: mapPalette)
    }

    // Markdown outline, used by Export → Outline and Copy as Text.
    var outline: String {
        var lines = ["# \(root.title)", ""]
        func walk(_ node: MindNode, depth: Int) {
            for child in node.children {
                lines.append(String(repeating: "  ", count: depth) + "- " + MindMap.outlineText(child))
                walk(child, depth: depth + 1)
            }
        }
        walk(root, depth: 0)
        return lines.joined(separator: "\n")
    }

    // Outline line for one idea: task box, icon and link included.
    static func outlineText(_ node: MindNode) -> String {
        var text = node.title
        if let icon = node.icon { text = "\(icon) \(text)" }
        if node.isTask { text = (node.isDone ? "[x] " : "[ ] ") + text }
        if let link = node.link { text += " (\(link))" }
        return text
    }
}

// The JSON tree the server speaks: {"title": "...", "children": [...]}.
// Optional fields are how the idea is shown (see NODE_FIELDS in the `ai` function). In replies,
// a missing field means "unchanged"; false, 0 or "" removes it.
struct APINode: Codable {
    var title: String
    var icon: String?
    var note: String?
    var task: Bool?
    var done: Bool?
    var priority: Int?
    var link: String?
    var callout: Bool?
    var children: [APINode]?

    init(title: String, icon: String? = nil, children: [APINode]? = nil) {
        self.title = title
        self.icon = icon
        self.children = children
    }

    // Notes longer than this go to the AI shortened; an unchanged short version keeps the full note.
    static let noteLimit = 300

    static func noteForAI(_ note: String) -> String {
        note.count > noteLimit ? String(note.prefix(noteLimit - 1)) + "…" : note
    }

    init(_ node: MindNode) {
        title = node.title
        icon = node.icon
        note = node.note.isEmpty ? nil : Self.noteForAI(node.note)
        task = node.isTask ? true : nil
        done = node.isTask && node.isDone ? true : nil
        priority = node.priority
        link = node.link
        callout = node.isCallout ? true : nil
        children = node.children.isEmpty ? nil : node.children.map(APINode.init)
    }

    // Sets the fields this reply carries on `node` (others stay as they are).
    func apply(to node: inout MindNode) {
        if let icon { node.icon = icon.isEmpty ? nil : MindNode.cleanIcon(icon) ?? node.icon }
        if let note, note != Self.noteForAI(node.note) { node.note = note }
        if let task { node.isTask = task }
        if let done { node.isDone = done && node.isTask }
        if !node.isTask { node.isDone = false }
        if let priority { node.priority = (1...3).contains(priority) ? priority : nil }
        if let link { node.link = link.isEmpty ? nil : link }
        if let callout { node.isCallout = callout }
    }

    func toNode(aiAdded: Bool, collapseBelow depth: Int = 3, level: Int = 0) -> MindNode {
        var node = MindNode(title: title, isAIAdded: aiAdded)
        apply(to: &node)
        node.children = (children ?? []).map { $0.toNode(aiAdded: aiAdded, collapseBelow: depth, level: level + 1) }
        // Deep branches open collapsed so the first view of a map stays readable.
        node.isCollapsed = level >= depth - 1 && !node.children.isEmpty
        return node
    }
}

// Tolerant decoding: a field added in a later version, or missing in an older file, never makes
// a whole map unreadable.
extension MindNode {
    private enum CodingKeys: String, CodingKey {
        case id, title, note, children, isCollapsed, isAIAdded, color, look, image, icon, isTask, isDone, priority, link, isCallout, due, isSuggestion, frame
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        note = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? ""
        children = (try? c.decodeIfPresent([MindNode].self, forKey: .children)) ?? []
        isCollapsed = (try? c.decodeIfPresent(Bool.self, forKey: .isCollapsed)) ?? false
        isAIAdded = (try? c.decodeIfPresent(Bool.self, forKey: .isAIAdded)) ?? false
        color = try? c.decodeIfPresent(BranchColor.self, forKey: .color)
        look = (try? c.decodeIfPresent(NodeLook.self, forKey: .look)).flatMap { $0.isDefault ? nil : $0 }
        image = try? c.decodeIfPresent(NodeImage.self, forKey: .image)
        icon = try? c.decodeIfPresent(String.self, forKey: .icon)
        isTask = (try? c.decodeIfPresent(Bool.self, forKey: .isTask)) ?? false
        isDone = (try? c.decodeIfPresent(Bool.self, forKey: .isDone)) ?? false
        priority = (try? c.decodeIfPresent(Int.self, forKey: .priority)).flatMap { (1...3).contains($0) ? $0 : nil }
        link = try? c.decodeIfPresent(String.self, forKey: .link)
        isCallout = (try? c.decodeIfPresent(Bool.self, forKey: .isCallout)) ?? false
        due = try? c.decodeIfPresent(Date.self, forKey: .due)
        isSuggestion = (try? c.decodeIfPresent(Bool.self, forKey: .isSuggestion)) ?? false
        frame = try? c.decodeIfPresent(String.self, forKey: .frame)
    }

    // Ideas whose titles the AI named, in its order (titles compared loosely, each idea once).
    func ids(titled titles: [String]) -> [UUID] {
        func key(_ s: String) -> String {
            s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        }
        var all: [MindNode] = []
        func walk(_ node: MindNode) { all.append(node); node.children.forEach(walk) }
        walk(self)
        var ids: [UUID] = []
        for title in titles {
            let wanted = key(title)
            if let match = all.first(where: { key($0.title) == wanted && !ids.contains($0.id) }) {
                ids.append(match.id)
            }
        }
        return ids
    }

    // One emoji, or nil (AI sometimes sends words or several symbols).
    static func cleanIcon(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count == 1, let scalar = text.unicodeScalars.first,
              scalar.properties.isEmoji, scalar.properties.isEmojiPresentation || text.unicodeScalars.count > 1
        else { return nil }
        return text
    }
}

extension MindMap {
    private enum CodingKeys: String, CodingKey { case id, root, createdAt, updatedAt, isPinned, source, layout, style, lines, lineWeight, canvas, palette, links }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        root = try c.decode(MindNode.self, forKey: .root)
        createdAt = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? Date()
        updatedAt = (try? c.decodeIfPresent(Date.self, forKey: .updatedAt)) ?? createdAt
        isPinned = (try? c.decodeIfPresent(Bool.self, forKey: .isPinned)) ?? false
        source = try? c.decodeIfPresent(MapSource.self, forKey: .source)
        layout = try? c.decodeIfPresent(String.self, forKey: .layout)
        style = try? c.decodeIfPresent(String.self, forKey: .style)
        lines = try? c.decodeIfPresent(String.self, forKey: .lines)
        lineWeight = try? c.decodeIfPresent(String.self, forKey: .lineWeight)
        canvas = try? c.decodeIfPresent(String.self, forKey: .canvas)
        palette = try? c.decodeIfPresent(String.self, forKey: .palette)
        links = (try? c.decodeIfPresent([MapLink].self, forKey: .links)) ?? []
    }

    // Connections whose ideas both still exist (after a delete, undo or AI edit).
    mutating func dropBrokenLinks() {
        let ids = Set(MindNode.allIDs(in: root))
        links.removeAll { !ids.contains($0.from) || !ids.contains($0.to) || $0.from == $0.to }
    }
}

extension MindNode {
    // Applies a tree the AI sent back after an edit command, keeping what the person already had:
    // nodes that survive (matched by title under the same parent, or by position when the
    // number of children did not change) keep their id, note, color and collapse state.
    // Only genuinely new nodes are marked as AI-added.
    func merged(with edited: APINode) -> MindNode {
        var result = self
        result.title = Self.clean(edited.title).isEmpty ? title : Self.clean(edited.title)
        edited.apply(to: &result)
        let incoming = edited.children ?? []
        var unused = children
        var matched: [MindNode?] = incoming.map { item in
            let key = Self.key(item.title)
            guard let index = unused.firstIndex(where: { Self.key($0.title) == key }) else { return nil }
            return unused.remove(at: index)
        }
        if incoming.count == children.count {
            // Renamed ideas: pair the leftovers by position.
            for index in matched.indices where matched[index] == nil {
                guard let old = unused.first(where: { candidate in
                    children.firstIndex(where: { $0.id == candidate.id }) == index
                }) else { continue }
                matched[index] = old
                unused.removeAll { $0.id == old.id }
            }
        }
        result.children = zip(incoming, matched).map { item, old in
            if let old { return old.merged(with: item) }
            return item.toNode(aiAdded: true, collapseBelow: .max)
        }
        if result.children.isEmpty { result.isCollapsed = false }
        return result
    }

    private static func clean(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func key(_ title: String) -> String {
        clean(title).lowercased()
    }
}
