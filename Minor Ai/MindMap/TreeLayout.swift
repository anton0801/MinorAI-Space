//
//  TreeLayout.swift
//  Minor Ai
//
//  Right-growing tree layout (DesignSystem → Mind Map → Layouts). Node sizes are measured
//  from their text up front, so the canvas can place everything without a measuring pass.
//

import SwiftUI
import UIKit

struct LayoutNode: Identifiable {
    let id: UUID
    let title: String
    let level: Int
    let frame: CGRect
    let color: BranchColor?
    let hiddenCount: Int
    let isAIAdded: Bool
    let parentID: UUID?
    var hasNote = false
    var side: CGFloat = 1   // +1 grows right of the root, -1 grows left (balanced layout)
    var hasChildren = false
    var decor = NodeDecor()
}

// What a node shows besides its title: picture, emoji, checkbox, priority, link, progress.
struct NodeDecor: Equatable {
    var image: NodeImage?
    var icon: String?
    var isTask = false
    var isDone = false
    var priority: Int?
    var linkHost: String?
    var isCallout = false
    var tasksDone = 0
    var tasksTotal = 0
    var look = NodeLook()
    var due: Date?
    var isSuggestion = false
    var frameLabel: String?    // a frame drawn around this idea's branch

    init() {}

    init(_ node: MindNode) {
        isSuggestion = node.isSuggestion
        frameLabel = node.frame
        look = node.look ?? NodeLook()
        due = node.isTask && !node.isDone ? node.due : nil
        image = node.image
        icon = node.icon
        isTask = node.isTask
        isDone = node.isDone
        priority = node.priority
        linkHost = node.link.flatMap { URL(string: $0)?.host?.replacingOccurrences(of: "www.", with: "") ?? $0 }
        isCallout = node.isCallout
        if !node.isTask {
            let progress = node.taskProgress
            tasksDone = progress.done
            tasksTotal = progress.total
        }
    }

    // Small glyphs before the title, 20 pt each.
    var leadingGlyphs: Int { (icon != nil ? 1 : 0) + (isTask ? 1 : 0) + (priority != nil ? 1 : 0) }
    var showsDue: Bool { due != nil }
    var showsProgress: Bool { tasksTotal > 0 }
}

struct MapLayout {
    var nodes: [LayoutNode] = []
    var size: CGSize = .zero
    // Frames around branches, drawn behind the connectors.
    var groups: [Group] = []

    struct Group: Identifiable {
        let id: UUID          // the framed idea
        let rect: CGRect
        let label: String
        let color: BranchColor?
    }

    // Room a frame takes around its branch: padding on every side and a line for the label.
    static let framePad: CGFloat = 10
    static let frameLabelHeight: CGFloat = 20
    static var frameExtra: CGFloat { framePad * 2 + frameLabelHeight }

    private var index: [UUID: Int] = [:]

    func node(_ id: UUID) -> LayoutNode? {
        index[id].map { nodes[$0] }
    }

    static let padding: CGFloat = 40

    init() {}

    // Tree grows right; balanced spreads level-1 branches to both sides of a centered root.
    init(map: MindMap, balanced: Bool = false) {
        let measured = Self.measure(map.root, level: 0)
        var placed: [LayoutNode] = []

        // Places a subtree whose block starts at `top`; `side` is +1 (grows right) or -1 (grows left).
        func place(_ node: MindNode, level: Int, anchorX: CGFloat, top: CGFloat, side: CGFloat, parent: UUID?, color: BranchColor?) {
            let size = measured[node.id] ?? CGSize(width: 80, height: 40)
            // A framed branch keeps its content inside the frame's padding and below its label.
            let framed = node.frame != nil && level > 0
            let full = Self.subtreeHeight(node, measured: measured, level: level)
            let subtree = framed ? full - Self.frameExtra : full
            let top = framed ? top + Self.framePad + Self.frameLabelHeight : top
            let anchorX = framed ? anchorX + Self.framePad * side : anchorX
            let x = side > 0 ? anchorX : anchorX - size.width
            let frame = CGRect(x: x, y: top + (subtree - size.height) / 2, width: size.width, height: size.height)
            placed.append(LayoutNode(
                id: node.id, title: node.title, level: level, frame: frame, color: color,
                hiddenCount: node.hiddenCount, isAIAdded: node.isAIAdded, parentID: parent,
                hasNote: !node.note.isEmpty, side: side, hasChildren: !node.children.isEmpty,
                decor: NodeDecor(node)
            ))
            let children = node.visibleChildren
            guard !children.isEmpty else { return }
            let gap = Self.gap(below: level)
            let block = children.reduce(0) { $0 + Self.subtreeHeight($1, measured: measured, level: level + 1) } + gap * CGFloat(children.count - 1)
            var y = top + (subtree - block) / 2
            let childAnchor = side > 0 ? frame.maxX + MapMetrics.levelGap : frame.minX - MapMetrics.levelGap
            for child in children {
                // A color set on any idea carries on to its descendants.
                place(child, level: level + 1, anchorX: childAnchor, top: y, side: side, parent: node.id, color: child.color ?? color)
                y += Self.subtreeHeight(child, measured: measured, level: level + 1) + gap
            }
        }

        let rootSize = measured[map.root.id] ?? CGSize(width: 120, height: 53)
        let palette = map.mapPalette
        let branches = map.root.visibleChildren.enumerated().map { index, child in
            (child, child.color ?? BranchColor.forBranch(at: index, palette: palette))
        }

        // Split branches between the two sides so their heights stay close.
        var right: [(MindNode, BranchColor)] = []
        var left: [(MindNode, BranchColor)] = []
        if balanced {
            var rightHeight: CGFloat = 0
            var leftHeight: CGFloat = 0
            for branch in branches {
                let h = Self.subtreeHeight(branch.0, measured: measured, level: 1)
                if rightHeight <= leftHeight {
                    right.append(branch)
                    rightHeight += h
                } else {
                    left.append(branch)
                    leftHeight += h
                }
            }
        } else {
            right = branches
        }

        let gap = Self.gap(below: 0)
        func blockHeight(_ list: [(MindNode, BranchColor)]) -> CGFloat {
            list.isEmpty ? 0 : list.reduce(0) { $0 + Self.subtreeHeight($1.0, measured: measured, level: 1) } + gap * CGFloat(list.count - 1)
        }
        let height = max(rootSize.height, blockHeight(right), blockHeight(left))
        let rootFrame = CGRect(x: 0, y: (height - rootSize.height) / 2, width: rootSize.width, height: rootSize.height)
        placed.append(LayoutNode(
            id: map.root.id, title: map.root.title, level: 0, frame: rootFrame, color: map.root.color,
            hiddenCount: map.root.hiddenCount, isAIAdded: false, parentID: nil, hasNote: !map.root.note.isEmpty,
            hasChildren: !map.root.children.isEmpty, decor: NodeDecor(map.root)
        ))
        for (list, side) in [(right, CGFloat(1)), (left, CGFloat(-1))] {
            var y = (height - blockHeight(list)) / 2
            let anchor = side > 0 ? rootFrame.maxX + MapMetrics.levelGap : rootFrame.minX - MapMetrics.levelGap
            for (child, color) in list {
                place(child, level: 1, anchorX: anchor, top: y, side: side, parent: map.root.id, color: color)
                y += Self.subtreeHeight(child, measured: measured, level: 1) + gap
            }
        }

        // Shift everything so the map starts at the padding and leave room for collapsed counters.
        let minX = placed.map { $0.frame.minX - ($0.hiddenCount > 0 && $0.side < 0 ? 44 : 0) }.min() ?? 0
        let maxX = placed.map { $0.frame.maxX + ($0.hiddenCount > 0 && $0.side > 0 ? 44 : 0) }.max() ?? 0
        let dx = Self.padding - minX
        let dy = Self.padding
        nodes = placed.map { node in
            LayoutNode(
                id: node.id, title: node.title, level: node.level, frame: node.frame.offsetBy(dx: dx, dy: dy),
                color: node.color, hiddenCount: node.hiddenCount, isAIAdded: node.isAIAdded,
                parentID: node.parentID, hasNote: node.hasNote, side: node.side, hasChildren: node.hasChildren,
                decor: node.decor
            )
        }
        size = CGSize(width: maxX - minX + Self.padding * 2, height: height + Self.padding * 2)
        for (i, node) in nodes.enumerated() { index[node.id] = i }

        // Inner frames first, so an outer frame also encloses the frames inside it.
        var rects: [UUID: CGRect] = [:]
        for node in nodes.filter({ $0.level > 0 && $0.decor.frameLabel != nil }).sorted(by: { $0.level > $1.level }) {
            var content = node.frame
            for member in branch(of: node.id) {
                content = content.union(rects[member.node.id] ?? member.node.frame)
            }
            rects[node.id] = CGRect(
                x: content.minX - Self.framePad,
                y: content.minY - Self.framePad - Self.frameLabelHeight,
                width: content.width + Self.framePad * 2,
                height: content.height + Self.framePad * 2 + Self.frameLabelHeight
            )
        }
        groups = nodes.compactMap { node in
            guard let rect = rects[node.id], let label = node.decor.frameLabel else { return nil }
            return Group(id: node.id, rect: rect, label: label, color: node.color)
        }
        if let right = groups.map(\.rect.maxX).max(), right + Self.padding > size.width {
            size.width = right + Self.padding
        }
    }

    // A node and all of its visible descendants.
    func subtree(_ id: UUID) -> Set<UUID> {
        var result: Set<UUID> = [id]
        var changed = true
        while changed {
            changed = false
            for node in nodes where !result.contains(node.id) {
                if let parent = node.parentID, result.contains(parent) {
                    result.insert(node.id)
                    changed = true
                }
            }
        }
        return result
    }

    // Nodes whose frame contains a point, topmost level first (used for drag and drop).
    func node(at point: CGPoint, excluding: Set<UUID> = []) -> LayoutNode? {
        nodes.filter { !excluding.contains($0.id) && $0.frame.insetBy(dx: -8, dy: -8).contains(point) }
            .min { $0.level < $1.level }
    }

    // Connector from the parent's facing side to the child's near side (right or left).
    func connector(to child: LayoutNode, style: LineStyle = .curved) -> Path? {
        guard let parentID = child.parentID, let parent = node(parentID) else { return nil }
        let growsRight = child.frame.minX >= parent.frame.midX
        let start = CGPoint(x: growsRight ? parent.frame.maxX : parent.frame.minX, y: parent.frame.midY)
        let end = CGPoint(x: growsRight ? child.frame.minX : child.frame.maxX, y: child.frame.midY)
        let midX = (start.x + end.x) / 2
        var path = Path()
        path.move(to: start)
        switch style {
        case .curved:
            path.addCurve(to: end, control1: CGPoint(x: midX, y: start.y), control2: CGPoint(x: midX, y: end.y))
        case .straight:
            path.addLine(to: end)
        case .elbow:
            // Across, down and across again, with small rounded corners.
            let dy = end.y - start.y
            let r = min(8, abs(dy) / 2, abs(midX - start.x))
            guard r > 0.5 else {
                path.addLine(to: end)
                return path
            }
            let sx: CGFloat = end.x > start.x ? 1 : -1
            let sy: CGFloat = dy > 0 ? 1 : -1
            path.addLine(to: CGPoint(x: midX - r * sx, y: start.y))
            path.addQuadCurve(to: CGPoint(x: midX, y: start.y + r * sy), control: CGPoint(x: midX, y: start.y))
            path.addLine(to: CGPoint(x: midX, y: end.y - r * sy))
            path.addQuadCurve(to: CGPoint(x: midX + r * sx, y: end.y), control: CGPoint(x: midX, y: end.y))
            path.addLine(to: end)
        }
        return path
    }

    // A node's visible descendants with their depth below it (0 for the node itself), in tree order.
    func branch(of id: UUID) -> [(node: LayoutNode, depth: Int)] {
        guard let root = node(id) else { return [] }
        var children: [UUID: [LayoutNode]] = [:]
        for node in nodes { if let parent = node.parentID { children[parent, default: []].append(node) } }
        var result: [(LayoutNode, Int)] = []
        func walk(_ node: LayoutNode, depth: Int) {
            result.append((node, depth))
            for child in children[node.id] ?? [] { walk(child, depth: depth + 1) }
        }
        walk(root, depth: 0)
        return result
    }

    // MARK: - Measuring

    private static func gap(below level: Int) -> CGFloat {
        level == 0 ? MapMetrics.siblingGap + MapMetrics.subtreeGap : MapMetrics.siblingGap
    }

    private static func subtreeHeight(_ node: MindNode, measured: [UUID: CGSize], level: Int) -> CGFloat {
        let own = measured[node.id]?.height ?? 40
        let extra = node.frame != nil && level > 0 ? frameExtra : 0
        let children = node.visibleChildren
        guard !children.isEmpty else { return own + extra }
        let block = children.reduce(0) { $0 + subtreeHeight($1, measured: measured, level: level + 1) }
            + gap(below: level) * CGFloat(children.count - 1)
        return max(own, block) + extra
    }

    private static func measure(_ node: MindNode, level: Int) -> [UUID: CGSize] {
        let icons = level == 0 ? 0 : (node.isAIAdded || node.isSuggestion ? 1 : 0) + (node.note.isEmpty ? 0 : 1)
        let decor = NodeDecor(node)
        var result = [node.id: NodeStyle(level: level, look: decor.look).size(for: decor, title: node.title, icons: icons)]
        for child in node.children {
            result.merge(measure(child, level: level + 1)) { a, _ in a }
        }
        return result
    }
}

// Typography and padding per level, shared by the layout and the node views.
struct NodeStyle {
    let level: Int

    var isRoot: Bool { level == 0 }
    var isBranch: Bool { level == 1 }
    var isLeaf: Bool { level >= 2 }

    // The look's text size and weight on top of the level's.
    var look = NodeLook()

    var fontSize: CGFloat { (callout ? 14 : isRoot ? 20 : isBranch ? 16 : 15) + look.size.delta }
    var weight: UIFont.Weight {
        if look.bold { return .bold }
        return isRoot ? .semibold : isBranch && !callout ? .medium : .regular
    }
    var lineHeight: CGFloat { (callout ? 19 : isRoot ? 25 : isBranch ? 21 : 20) + look.size.delta * 1.25 }
    var maxLines: Int { callout ? 6 : isBranch ? 2 : 3 }
    var maxWidth: CGFloat { callout ? 280 : isRoot ? MapMetrics.rootMaxWidth : MapMetrics.nodeMaxWidth }
    var minHeight: CGFloat { isLeaf && !callout ? MapMetrics.leafMinHeight : MapMetrics.nodeMinHeight }

    var insets: EdgeInsets {
        if callout { return EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 12) }
        if isRoot { return EdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20) }
        if isBranch { return EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14) }
        return EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 10)
    }

    var font: Font {
        let font = Font.system(size: fontSize, weight: look.bold ? .bold : isRoot ? .semibold : isBranch && !callout ? .medium : .regular)
        return callout ? font.italic() : font
    }

    // Size with everything the node shows. Must match MindNodeView's layout.
    func size(for decor: NodeDecor, title: String, icons: Int = 0) -> CGSize {
        let callout = decor.isCallout && !isRoot
        let extra: CGFloat = decor.icon != nil ? 4 : 0   // the emoji is 18 pt wide, not 14
        var size = callout
            ? NodeStyle(level: 2, callout: true, look: look).size(for: title, icons: icons + decor.leadingGlyphs, extraWidth: extra)
            : self.size(for: title, icons: icons + decor.leadingGlyphs, extraWidth: extra)
        if decor.showsProgress { size.width += Self.progressWidth }
        if decor.linkHost != nil || decor.showsDue { size.height += Self.linkLineHeight }
        if let image = decor.image {
            let width = max(size.width, imageNodeWidth)
            let inner = width - insets.leading - insets.trailing
            size = CGSize(width: width, height: size.height + Self.imageHeight(inner: inner, aspect: image.aspect) + Self.imageSpacing)
        }
        // Shapes that are narrower at their edges need room around the text.
        if decor.image == nil && !callout {
            switch decor.look.shape {
            case .ellipse: size = CGSize(width: size.width * 1.12 + 22, height: size.height + 12)
            case .hexagon: size.width += size.height * 0.5
            case .diamond: size = CGSize(width: size.width * 1.25 + size.height, height: size.height * 1.5 + 8)
            case .pill: size.width += 8
            default: break
            }
        }
        return size
    }

    // Extra room left and right of the content of a shaped node, so text stays inside the shape.
    func shapeInset(for decor: NodeDecor, frame: CGSize) -> CGFloat {
        guard decor.image == nil, !(decor.isCallout && !isRoot) else { return 0 }
        switch decor.look.shape {
        case .ellipse: return (frame.width - (frame.width - 22) / 1.12) / 2
        case .hexagon: return frame.height * 0.25
        case .diamond:
            let height = (frame.height - 8) / 1.5
            let inner = (frame.width - height) / 1.25
            return max(0, (frame.width - inner) / 2)
        case .pill: return 4
        default: return 0
        }
    }

    static let progressWidth: CGFloat = 40
    static let linkLineHeight: CGFloat = 16
    static let imageSpacing: CGFloat = 6
    var imageNodeWidth: CGFloat { isRoot ? 240 : 190 }

    static func imageHeight(inner: CGFloat, aspect: Double) -> CGFloat {
        (inner * CGFloat(min(max(aspect, 0.5), 1.4))).rounded()
    }

    // Callouts: longer, smaller italic text in a wide block.
    static let calloutStyle = NodeStyle(level: 2, callout: true)
    var callout = false

    init(level: Int, callout: Bool = false, look: NodeLook = NodeLook()) {
        self.level = level
        self.callout = callout
        self.look = look
    }

    // `icons` counts the small glyphs before the title (AI sparkle, note, emoji, checkbox, priority).
    func size(for title: String, icons: Int = 0, extraWidth: CGFloat = 0) -> CGSize {
        var uiFont = UIFont.systemFont(ofSize: fontSize, weight: weight)
        if callout, let italic = uiFont.fontDescriptor.withSymbolicTraits(.traitItalic) {
            uiFont = UIFont(descriptor: italic, size: fontSize)
        }
        let iconWidth = CGFloat(icons) * 20 + extraWidth
        let maxText = maxWidth - insets.leading - insets.trailing - iconWidth
        let bounds = (title as NSString).boundingRect(
            with: CGSize(width: maxText, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: uiFont],
            context: nil
        )
        let lines = min(maxLines, max(1, Int(ceil(bounds.height / uiFont.lineHeight - 0.01))))
        let width = ceil(min(bounds.width, maxText)) + insets.leading + insets.trailing + iconWidth + 1
        let height = CGFloat(lines) * lineHeight + insets.top + insets.bottom
        return CGSize(width: width, height: max(minHeight, height))
    }
}
