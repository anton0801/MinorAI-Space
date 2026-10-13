//
//  DiagramLayout.swift
//  Minor Ai
//
//  Where a diagram's boxes, connections and axes go on the slide (1280 × 720). The same geometry
//  draws the slide on screen and in PDF and becomes PowerPoint shapes and connectors, so the three
//  agree. Connections leave and enter boxes at the middle of a side (the sides PowerPoint attaches
//  connectors to), never inside the text. Long labels wrap and make boxes taller before the text
//  gets smaller, and never below a readable size; what still doesn't fit is reported, not cut.
//

import UIKit

struct DiagramGeometry: Equatable {
    struct Box: Equatable, Identifiable {
        let id: UUID
        var frame: CGRect
        let label: String
        let icon: String?
        let color: Int              // index in the slide's palette
        let fontSize: CGFloat
        var shape: Shape = .roundRect

        enum Shape: Equatable { case roundRect, circle, chip }
    }

    // A side of a box: PowerPoint's connection site index for rectangles (top, left, bottom, right).
    enum Side: Int { case top = 0, left = 1, bottom = 2, right = 3 }

    struct Connector: Equatable, Identifiable {
        let id: UUID
        let from: UUID
        let to: UUID
        let start: CGPoint
        let end: CGPoint
        let startSide: Side
        let endSide: Side
        let elbow: Bool             // vertical, across, vertical (a tree)
        let directed: Bool
        let dashed: Bool
        let label: String

        // The drawn path: straight, or down–across–down for an elbow.
        var points: [CGPoint] {
            guard elbow, start.x != end.x else { return [start, end] }
            let middle = (start.y + end.y) / 2
            return [start, CGPoint(x: start.x, y: middle), CGPoint(x: end.x, y: middle), end]
        }
    }

    struct Axes: Equatable {
        var grid: CGRect
        var xTitle: String
        var yTitle: String
        var xLow: String
        var xHigh: String
        var yLow: String
        var yHigh: String
        var quadrantLabels: [(CGRect, String)]
        var showsQuadrants: Bool

        static func == (a: Axes, b: Axes) -> Bool {
            a.grid == b.grid && a.xTitle == b.xTitle && a.yTitle == b.yTitle && a.quadrantLabels.map(\.1) == b.quadrantLabels.map(\.1)
        }
    }

    var boxes: [Box] = []
    var connectors: [Connector] = []
    var axes: Axes?
    var overflow = false            // something doesn't fit at a readable size
    var empty = false
}

enum DiagramLayout {
    static let area = CGRect(x: 80, y: 190, width: 1120, height: 460)
    static let minFont: CGFloat = 18

    // The geometry of a slide's diagram. `scale`: the slide's body text size.
    static func geometry(_ diagram: SlideDiagram, slideID: UUID, title: String, scale: CGFloat = 1, area: CGRect = area) -> DiagramGeometry {
        let d = diagram.structured(slideID: slideID)
        var geometry: DiagramGeometry
        guard !d.allItems.isEmpty else {
            geometry = DiagramGeometry()
            geometry.empty = true
            return geometry
        }
        switch d.kindValue {
        case .process: geometry = process(d, scale: scale, area: area, closed: false)
        case .cycle: geometry = cycle(d, scale: scale, area: area)
        case .hierarchy: geometry = d.radial == true ? radial(d, title: title, scale: scale, area: area) : tree(d, scale: scale, area: area)
        case .matrix: geometry = matrix(d, scale: scale, area: area)
        }
        if d.arrangement == .manual, d.kindValue != .matrix {
            geometry = manual(geometry, d, area: area)
        }
        geometry.connectors += extraConnectors(d, boxes: geometry.boxes, drawn: geometry.connectors)
        return geometry
    }

    // MARK: Text

    static func font(_ size: CGFloat) -> UIFont { .systemFont(ofSize: size, weight: .semibold) }

    // The height a label takes at `size` in `width`.
    static func textHeight(_ text: String, size: CGFloat, width: CGFloat) -> CGFloat {
        let rect = (text.isEmpty ? " " : text as NSString).boundingRect(with: CGSize(width: max(width, 10), height: .greatestFiniteMagnitude),
                                                                       options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font(size)], context: nil)
        return ceil(rect.height)
    }

    static func widestWord(_ text: String, size: CGFloat) -> CGFloat {
        text.split(whereSeparator: \.isWhitespace).map { (String($0) as NSString).size(withAttributes: [.font: font(size)]).width }.max() ?? 0
    }

    // The largest size, from `size` down to the readable minimum, at which every label fits its
    // box width (no word broken) and the box height; nil when even the minimum doesn't fit.
    static func fit(_ labels: [String], size: CGFloat, width: CGFloat, height: CGFloat, icon: Bool) -> CGFloat? {
        var s = size
        let room = width - 32
        while s >= minFont {
            let iconSpace: CGFloat = icon ? s * 1.6 + 8 : 0
            if labels.allSatisfy({ widestWord($0, size: s) <= room && textHeight($0, size: s, width: room) + 28 + iconSpace <= height }) { return s }
            s -= 1
        }
        return nil
    }

    // The height boxes need for their labels at `size`.
    static func neededHeight(_ labels: [String], size: CGFloat, width: CGFloat, icon: Bool) -> CGFloat {
        let iconSpace: CGFloat = icon ? size * 1.6 + 8 : 0
        return (labels.map { textHeight($0, size: size, width: width - 32) }.max() ?? size) + 28 + iconSpace
    }

    // MARK: Sides

    // The sides two boxes face each other with, and the middles of those sides.
    static func facing(_ a: CGRect, _ b: CGRect) -> (DiagramGeometry.Side, CGPoint, DiagramGeometry.Side, CGPoint) {
        let dx = b.midX - a.midX, dy = b.midY - a.midY
        if abs(dx) * a.height >= abs(dy) * a.width {
            return dx >= 0
                ? (.right, CGPoint(x: a.maxX, y: a.midY), .left, CGPoint(x: b.minX, y: b.midY))
                : (.left, CGPoint(x: a.minX, y: a.midY), .right, CGPoint(x: b.maxX, y: b.midY))
        }
        return dy >= 0
            ? (.bottom, CGPoint(x: a.midX, y: a.maxY), .top, CGPoint(x: b.midX, y: b.minY))
            : (.top, CGPoint(x: a.midX, y: a.minY), .bottom, CGPoint(x: b.midX, y: b.maxY))
    }

    static func straight(_ edge: DiagramEdge, _ a: CGRect, _ b: CGRect, dashed: Bool = false) -> DiagramGeometry.Connector {
        let (s1, p1, s2, p2) = facing(a, b)
        return .init(id: edge.id, from: edge.from, to: edge.to, start: p1, end: p2, startSide: s1, endSide: s2, elbow: false,
                     directed: edge.directed, dashed: dashed, label: edge.label)
    }

    // MARK: Process and cycle

    static func process(_ d: SlideDiagram, scale: CGFloat, area: CGRect, closed: Bool) -> DiagramGeometry {
        let items = d.allItems
        let n = items.count
        // One row up to three steps; four as two by two; then rows of three or four, as a snake.
        let columns = n <= 3 ? n : n == 4 ? 2 : n <= 6 ? 3 : 4
        let rows = Int((Double(n) / Double(columns)).rounded(.up))
        let gapX: CGFloat = columns > 3 ? 64 : 110, gapY: CGFloat = rows > 2 ? 48 : 70
        let width = min(columns <= 2 ? 400 : 320, (area.width - gapX * CGFloat(columns - 1)) / CGFloat(columns))
        let icons = d.showIcons != false && items.contains { $0.icon != nil }
        let maxHeight = (area.height - gapY * CGFloat(rows - 1)) / CGFloat(rows)
        let labels = items.map(\.label)
        // Few steps get big boxes and type; many get smaller ones, never below the readable minimum.
        let fitted = fit(labels, size: (n <= 4 ? 34 : 28) * scale, width: width, height: maxHeight, icon: icons)
        let size = fitted ?? minFont
        let height = min(maxHeight, max(neededHeight(labels, size: size, width: width, icon: icons), rows <= 2 ? min(maxHeight, 170) : 96))
        let total = CGSize(width: CGFloat(columns) * width + CGFloat(columns - 1) * gapX, height: CGFloat(rows) * height + CGFloat(rows - 1) * gapY)
        let origin = CGPoint(x: area.midX - total.width / 2, y: area.midY - total.height / 2)
        var geometry = DiagramGeometry()
        for (i, item) in items.enumerated() {
            let row = i / columns
            let column = row % 2 == 0 ? i % columns : columns - 1 - i % columns   // a snake: every other row runs back
            let frame = CGRect(x: origin.x + CGFloat(column) * (width + gapX), y: origin.y + CGFloat(row) * (height + gapY), width: width, height: height)
            geometry.boxes.append(.init(id: item.id, frame: frame, label: item.label, icon: d.showIcons == false ? nil : item.icon, color: i, fontSize: size))
        }
        geometry.overflow = fitted == nil || n > 12
        geometry.connectors = sequenceConnectors(d, boxes: geometry.boxes)
        return geometry
    }

    static func cycle(_ d: SlideDiagram, scale: CGFloat, area: CGRect) -> DiagramGeometry {
        let items = d.allItems
        let n = items.count
        guard n > 2 else { return process(d, scale: scale, area: area, closed: true) }
        let width = min(260, max(170, 900 / CGFloat(n) + 60))
        let icons = d.showIcons != false && items.contains { $0.icon != nil }
        let labels = items.map(\.label)
        let fitted = fit(labels, size: 28 * scale, width: width, height: 150, icon: icons)
        let size = fitted ?? minFont
        let height = min(150, max(neededHeight(labels, size: size, width: width, icon: icons), icons ? 130 : 96))
        let rx = area.width / 2 - width / 2, ry = area.height / 2 - height / 2
        var geometry = DiagramGeometry()
        for (i, item) in items.enumerated() {
            let angle = -Double.pi / 2 + Double(i) * 2 * .pi / Double(n)
            let center = CGPoint(x: area.midX + CGFloat(cos(angle)) * rx, y: area.midY + CGFloat(sin(angle)) * ry)
            let frame = CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
            geometry.boxes.append(.init(id: item.id, frame: frame, label: item.label, icon: d.showIcons == false ? nil : item.icon, color: i, fontSize: size))
        }
        // Neighbouring boxes on a small ellipse may touch: then it doesn't fit.
        let frames = geometry.boxes.map(\.frame)
        let touching = frames.indices.contains { i in frames.indices.contains { j in j > i && frames[i].insetBy(dx: -8, dy: -8).intersects(frames[j]) } }
        geometry.overflow = fitted == nil || touching || n > 10
        geometry.connectors = sequenceConnectors(d, boxes: geometry.boxes)
        return geometry
    }

    static func sequenceConnectors(_ d: SlideDiagram, boxes: [DiagramGeometry.Box]) -> [DiagramGeometry.Connector] {
        let frames = Dictionary(uniqueKeysWithValues: boxes.map { ($0.id, $0.frame) })
        return d.allEdges.filter(\.sequence).compactMap { edge in
            guard let a = frames[edge.from], let b = frames[edge.to] else { return nil }
            return straight(edge, a, b)
        }
    }

    // MARK: Hierarchy

    static func tree(_ d: SlideDiagram, scale: CGFloat, area: CGRect) -> DiagramGeometry {
        let items = d.allItems
        let ids = Set(items.map(\.id))
        let roots = items.filter { $0.parent == nil || !ids.contains($0.parent!) }
        func children(_ id: UUID) -> [DiagramNode] { items.filter { $0.parent == id } }
        // Depth of each node and the leaves under it (the room it needs across).
        var depth: [UUID: Int] = [:]
        var leaves: [UUID: Int] = [:]
        func walk(_ node: DiagramNode, _ level: Int, _ seen: Set<UUID>) -> Int {
            guard !seen.contains(node.id) else { return 0 }
            depth[node.id] = level
            let kids = children(node.id)
            let count = kids.isEmpty ? 1 : kids.reduce(0) { $0 + walk($1, level + 1, seen.union([node.id])) }
            leaves[node.id] = max(count, 1)
            return max(count, 1)
        }
        let totalLeaves = roots.reduce(0) { $0 + walk($1, 0, []) }
        let levels = (depth.values.max() ?? 0) + 1
        let gapX: CGFloat = 24, gapY: CGFloat = 56
        let slot = area.width / CGFloat(max(totalLeaves, 1))
        let width = min(260, slot - gapX)
        let icons = d.showIcons != false && items.contains { $0.icon != nil }
        let maxHeight = (area.height - gapY * CGFloat(levels - 1)) / CGFloat(levels)
        let labels = items.map(\.label)
        let fitted = width >= 110 ? fit(labels, size: 24 * scale, width: width, height: maxHeight, icon: icons) : nil
        let size = fitted ?? minFont
        let height = min(maxHeight, max(neededHeight(labels, size: size, width: max(width, 110), icon: icons), 76))
        let totalHeight = CGFloat(levels) * height + CGFloat(levels - 1) * gapY
        let top = area.midY - totalHeight / 2
        var geometry = DiagramGeometry()
        var x = area.minX
        var placed: [UUID: CGRect] = [:]
        func place(_ node: DiagramNode, _ seen: Set<UUID>) {
            guard !seen.contains(node.id), let level = depth[node.id], placed[node.id] == nil else { return }
            let span = CGFloat(leaves[node.id] ?? 1) * slot
            let start = x
            let kids = children(node.id)
            if kids.isEmpty { x += slot } else { kids.forEach { place($0, seen.union([node.id])) } }
            let centerX = kids.isEmpty ? start + slot / 2 : start + span / 2
            placed[node.id] = CGRect(x: centerX - width / 2, y: top + CGFloat(level) * (height + gapY), width: width, height: height)
        }
        roots.forEach { place($0, []) }
        // Each main branch has its color; the top has the first.
        var branch: [UUID: Int] = [:]
        for root in roots {
            branch[root.id] = 0
            for (i, child) in children(root.id).enumerated() {
                branch[child.id] = i + 1
                for id in descendants(of: child.id, in: items) { branch[id] = i + 1 }
            }
        }
        for item in items {
            guard let frame = placed[item.id] else { continue }
            geometry.boxes.append(.init(id: item.id, frame: frame, label: item.label, icon: d.showIcons == false ? nil : item.icon, color: branch[item.id] ?? 0, fontSize: size))
        }
        geometry.overflow = fitted == nil || levels > 4
        for item in items {
            guard let parent = item.parent, let a = placed[parent], let b = placed[item.id] else { continue }
            let start = CGPoint(x: a.midX, y: a.maxY), end = CGPoint(x: b.midX, y: b.minY)
            geometry.connectors.append(.init(id: SlideDiagram.stableID(item.id, "parent"), from: parent, to: item.id, start: start, end: end,
                                             startSide: .bottom, endSide: .top, elbow: true, directed: false, dashed: false, label: ""))
        }
        return geometry
    }

    static func descendants(of id: UUID, in items: [DiagramNode]) -> Set<UUID> {
        var found: Set<UUID> = []
        var queue = [id]
        while let next = queue.popLast() {
            for child in items where child.parent == next && !found.contains(child.id) {
                found.insert(child.id)
                queue.append(child.id)
            }
        }
        return found
    }

    // Around the center: the root in a circle, its children around it (the diagrams made before 2.1).
    static func radial(_ d: SlideDiagram, title: String, scale: CGFloat, area: CGRect) -> DiagramGeometry {
        let items = d.allItems
        guard let root = items.first(where: { $0.parent == nil }) else { return tree(d, scale: scale, area: area) }
        let around = items.filter { $0.parent == root.id }
        var geometry = DiagramGeometry()
        let center = CGPoint(x: 640, y: 420)
        let circle = CGRect(x: center.x - 115, y: center.y - 115, width: 230, height: 230)
        let rootLabel = root.label.isEmpty ? title : root.label
        let rootSize = fit([rootLabel], size: 30 * scale, width: 210, height: 200, icon: false) ?? minFont
        geometry.boxes.append(.init(id: root.id, frame: circle, label: rootLabel, icon: nil, color: 0, fontSize: rootSize, shape: .circle))
        let labels = around.map(\.label)
        let size = fit(labels, size: 25 * scale, width: 300, height: 96, icon: false)
        for (i, item) in around.enumerated() {
            let angle = -Double.pi / 2 + Double(i) * 2 * .pi / Double(max(around.count, 1))
            let point = CGPoint(x: center.x + CGFloat(cos(angle)) * 420, y: center.y + CGFloat(sin(angle)) * 210)
            let height = max(72, neededHeight([item.label], size: size ?? minFont, width: 300, icon: false) - 8)
            let frame = CGRect(x: point.x - 150, y: point.y - height / 2, width: 300, height: height)
            geometry.boxes.append(.init(id: item.id, frame: frame, label: item.label, icon: nil, color: i, fontSize: size ?? minFont, shape: .chip))
            let (s1, p1, s2, p2) = facing(circle, frame)
            geometry.connectors.append(.init(id: SlideDiagram.stableID(item.id, "parent"), from: root.id, to: item.id, start: p1, end: p2,
                                             startSide: s1, endSide: s2, elbow: false, directed: false, dashed: true, label: ""))
        }
        geometry.overflow = size == nil || around.count > 8 || items.count > around.count + 1
        return geometry
    }

    // MARK: Matrix

    static func matrix(_ d: SlideDiagram, scale: CGFloat, area: CGRect) -> DiagramGeometry {
        let axes = d.axesValue
        // The vertical axis is named above the grid, the horizontal one under it (no turned text,
        // which some viewers lay out wrongly).
        let grid = CGRect(x: area.minX, y: area.minY + 36, width: area.width, height: area.height - 80)
        var geometry = DiagramGeometry()
        let half = CGSize(width: grid.width / 2, height: grid.height / 2)
        let quadrants = (0..<4).map { q in
            CGRect(x: grid.minX + (q % 2 == 0 ? 0 : half.width), y: grid.minY + (q < 2 ? 0 : half.height), width: half.width, height: half.height)
        }
        geometry.axes = .init(grid: grid, xTitle: axes.x.title, yTitle: axes.y.title, xLow: axes.x.low, xHigh: axes.x.high, yLow: axes.y.low, yHigh: axes.y.high,
                              quadrantLabels: quadrants.enumerated().map { q, rect in (CGRect(x: rect.minX + 16, y: rect.minY + 12, width: rect.width - 32, height: 30), axes.quadrants.indices.contains(q) ? axes.quadrants[q] : "") },
                              showsQuadrants: d.matrix != .values)
        let size = max(minFont, 22 * scale)
        if d.matrix == .values {
            // Each item where its values put it, as a chip; chips that would cover each other move down.
            var taken: [CGRect] = []
            for (i, item) in d.allItems.enumerated() {
                let value = item.value ?? d.value(inQuadrant: item.quadrant ?? i % 4)
                let fx = (value[0] - axes.x.min) / max(axes.x.max - axes.x.min, 0.0001)
                let fy = (value[1] - axes.y.min) / max(axes.y.max - axes.y.min, 0.0001)
                let point = CGPoint(x: grid.minX + CGFloat(min(max(fx, 0), 1)) * grid.width, y: grid.maxY - CGFloat(min(max(fy, 0), 1)) * grid.height)
                let width = min(240, ceil((item.label as NSString).size(withAttributes: [.font: font(size)]).width) + 40)
                let height = textHeight(item.label, size: size, width: width - 32) + 22
                var frame = CGRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height)
                frame.origin.x = min(max(frame.minX, grid.minX), grid.maxX - width)
                frame.origin.y = min(max(frame.minY, grid.minY), grid.maxY - height)
                var tries = 0
                while taken.contains(where: { $0.intersects(frame) }) && tries < 12 {
                    frame.origin.y = min(frame.origin.y + height + 6, grid.maxY - height)
                    tries += 1
                }
                if taken.contains(where: { $0.intersects(frame) }) { geometry.overflow = true }
                taken.append(frame)
                geometry.boxes.append(.init(id: item.id, frame: frame, label: item.label, icon: nil, color: i, fontSize: size, shape: .chip))
            }
        } else {
            // Items flow inside their quadrant, under its label.
            for q in 0..<4 {
                let members = d.allItems.enumerated().filter { ($0.element.quadrant ?? $0.offset % 4) == q }
                let rect = quadrants[q].insetBy(dx: 16, dy: 0)
                var x = rect.minX, y = rect.minY + 54, rowHeight: CGFloat = 0
                for (i, item) in members {
                    let width = min(rect.width, ceil((item.label as NSString).size(withAttributes: [.font: font(size)]).width) + 40)
                    let height = textHeight(item.label, size: size, width: width - 32) + 22
                    if x + width > rect.maxX + 0.5 {
                        x = rect.minX
                        y += rowHeight + 10
                        rowHeight = 0
                    }
                    let frame = CGRect(x: x, y: y, width: width, height: height)
                    if frame.maxY > quadrants[q].maxY - 8 { geometry.overflow = true }
                    geometry.boxes.append(.init(id: item.id, frame: frame, label: item.label, icon: nil, color: i, fontSize: size, shape: .chip))
                    x += width + 10
                    rowHeight = max(rowHeight, height)
                }
            }
        }
        geometry.overflow = geometry.overflow || d.allItems.count > 16
        return geometry
    }

    // MARK: Manual positions and extra connections

    // Boxes where the person put them; connections follow the boxes.
    static func manual(_ geometry: DiagramGeometry, _ d: SlideDiagram, area: CGRect) -> DiagramGeometry {
        var copy = geometry
        let positions = Dictionary(uniqueKeysWithValues: d.allItems.compactMap { item in item.position.flatMap { $0.count == 2 ? (item.id, CGPoint(x: $0[0], y: $0[1])) : nil } })
        copy.boxes = geometry.boxes.map { box in
            guard let center = positions[box.id] else { return box }
            var moved = box
            moved.frame.origin = CGPoint(x: min(max(center.x - box.frame.width / 2, 20), 1260 - box.frame.width),
                                         y: min(max(center.y - box.frame.height / 2, 150), 700 - box.frame.height))
            return moved
        }
        let frames = Dictionary(uniqueKeysWithValues: copy.boxes.map { ($0.id, $0.frame) })
        copy.connectors = geometry.connectors.compactMap { connector in
            guard let a = frames[connector.from], let b = frames[connector.to] else { return nil }
            if connector.elbow {
                return .init(id: connector.id, from: connector.from, to: connector.to, start: CGPoint(x: a.midX, y: a.maxY), end: CGPoint(x: b.midX, y: b.minY),
                             startSide: .bottom, endSide: .top, elbow: true, directed: connector.directed, dashed: connector.dashed, label: connector.label)
            }
            let (s1, p1, s2, p2) = facing(a, b)
            return .init(id: connector.id, from: connector.from, to: connector.to, start: p1, end: p2, startSide: s1, endSide: s2,
                         elbow: false, directed: connector.directed, dashed: connector.dashed, label: connector.label)
        }
        let all = copy.boxes.map(\.frame)
        copy.overflow = copy.overflow || all.indices.contains { i in all.indices.contains { j in j > i && all[i].intersects(all[j]) } }
        return copy
    }

    // Connections added by hand (not the sequence, not a parent): straight, between facing sides.
    // A matrix keeps them in its data without drawing them.
    static func extraConnectors(_ d: SlideDiagram, boxes: [DiagramGeometry.Box], drawn: [DiagramGeometry.Connector]) -> [DiagramGeometry.Connector] {
        guard d.kindValue != .matrix else { return [] }
        let frames = Dictionary(uniqueKeysWithValues: boxes.map { ($0.id, $0.frame) })
        let done = Set(drawn.map(\.id))
        return d.allEdges.filter { !$0.sequence && !done.contains($0.id) }.compactMap { edge in
            guard let a = frames[edge.from], let b = frames[edge.to] else { return nil }
            return straight(edge, a, b, dashed: true)
        }
    }
}
