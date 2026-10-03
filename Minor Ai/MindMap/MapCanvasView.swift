//
//  MapCanvasView.swift
//  Minor Ai
//
//  Pannable, zoomable canvas: dot grid, connectors and nodes. Below 50% zoom leaves turn
//  into colored bars and the grid disappears (DesignSystem → Mind Map → Canvas).
//

import SwiftUI

struct CanvasViewport: Equatable {
    var scale: CGFloat = 1
    var offset: CGSize = .zero

    // Fits the whole map between the top and bottom chrome, never larger than 100%.
    static func fit(_ content: CGSize, in size: CGSize, insets: EdgeInsets) -> CanvasViewport {
        let width = max(size.width - insets.leading - insets.trailing, 1)
        let height = max(size.height - insets.top - insets.bottom, 1)
        let scale = min(1, width / max(content.width, 1), height / max(content.height, 1))
            .clamped(to: MapMetrics.zoomRange)
        let x = insets.leading + (width - content.width * scale) / 2
        let y = insets.top + (height - content.height * scale) / 2
        return CanvasViewport(scale: scale, offset: CGSize(width: x, height: y))
    }
}

extension CanvasViewport {
    // Fits one part of the map (a branch) on screen, up to `maxScale`.
    static func fit(rect: CGRect, in size: CGSize, insets: EdgeInsets, maxScale: CGFloat = 1) -> CanvasViewport {
        let width = max(size.width - insets.leading - insets.trailing, 1)
        let height = max(size.height - insets.top - insets.bottom, 1)
        let scale = min(maxScale, width / max(rect.width, 1), height / max(rect.height, 1)).clamped(to: MapMetrics.zoomRange)
        return CanvasViewport(
            scale: scale,
            offset: CGSize(
                width: insets.leading + (width - rect.width * scale) / 2 - rect.minX * scale,
                height: insets.top + (height - rect.height * scale) / 2 - rect.minY * scale
            )
        )
    }

    // First view of a map: fit it, but never so small that ideas turn into bars;
    // a wide map then opens centered on the root and can be panned.
    static func opening(_ layout: MapLayout, in size: CGSize, insets: EdgeInsets) -> CanvasViewport {
        let target = fit(layout.size, in: size, insets: insets)
        let minimum = MapMetrics.lodThreshold + 0.15
        guard target.scale < minimum, let root = layout.nodes.first(where: { $0.level == 0 }) else { return target }
        let visibleHeight = size.height - insets.top - insets.bottom
        return CanvasViewport(
            scale: minimum,
            offset: CGSize(
                width: size.width / 2 - root.frame.midX * minimum,
                height: insets.top + visibleHeight / 2 - root.frame.midY * minimum
            )
        )
    }
}

struct MapCanvasView: View {
    let layout: MapLayout
    let theme: AppTheme
    @Binding var viewport: CanvasViewport
    @Binding var selection: UUID?
    var generating: Set<UUID> = []
    var dimmed: Set<UUID> = []
    var highlighted: Set<UUID> = []
    var chromeInsets = EdgeInsets(top: 110, leading: 16, bottom: 170, trailing: 16)
    var onDoubleTapNode: (UUID) -> Void = { _ in }
    var onToggleCollapse: (UUID) -> Void = { _ in }
    var onExpand: (UUID) -> Void = { _ in }
    var onMove: (_ node: UUID, _ newParent: UUID) -> Void = { _, _ in }
    var mapStyle: MapStyle = .classic
    var onToggleDone: (UUID) -> Void = { _ in }
    var lineStyle: LineStyle = .curved
    var lineWeight: LineWeight = .regular
    var background: CanvasBackground = .dots
    var links: [MapLink] = []
    var onLinkTap: (MapLink) -> Void = { _ in }

    // A lifted node. Gesture state resets by itself if the drag is cancelled (a call, a sheet,
    // the node disappearing), so a node can never stay stuck half-transparent.
    struct DragState: Equatable {
        let id: UUID
        var point: CGPoint
        var target: UUID?
    }

    @GestureState private var pan: CGSize = .zero
    @GestureState(resetTransaction: Transaction(animation: .spring(response: 0.4, dampingFraction: 0.8)))
    private var drag: DragState? = nil
    @GestureState private var pinch: CGFloat = 1
    @State private var size: CGSize = .zero
    // The light that runs through a newly selected branch (see BranchPulse).
    @State private var pulse: (id: UUID, start: Date)?

    private var scale: CGFloat { (viewport.scale * pinch).clamped(to: MapMetrics.zoomRange) }

    private var offset: CGSize {
        // Pinch zooms around the middle of the visible area.
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let ratio = scale / viewport.scale
        return CGSize(
            width: center.x - (center.x - viewport.offset.width) * ratio + pan.width,
            height: center.y - (center.y - viewport.offset.height) * ratio + pan.height
        )
    }

    private var isLOD: Bool { scale < MapMetrics.lodThreshold }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                grid
                content
                    .scaleEffect(scale, anchor: .topLeading)
                    .offset(offset)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .clipped()
            .contentShape(Rectangle())
            // A double tap on empty canvas fits the map; on a node it renames instead (the node's
            // own gestures win, so the two never fire together).
            .onTapGesture(count: 2) { fit(animated: true) }
            .onTapGesture { withAnimation(.minorMenu) { selection = nil } }
            .gesture(panGesture)
            .simultaneousGesture(pinchGesture)
            .onAppear {
                size = geo.size
                if viewport == CanvasViewport() { openingFit() }
            }
            .onChange(of: geo.size) { size = $0 }
            .onChange(of: selection) { id in startPulse(id) }
        }
        .background(theme.background)
        .accessibilityAction(named: "Fit map") { fit(animated: true) }
        .accessibilityAction(named: "Zoom in") { zoom(by: 1.5) }
        .accessibilityAction(named: "Zoom out") { zoom(by: 1 / 1.5) }
    }

    // MARK: - Layers

    private var grid: some View {
        Canvas { context, canvasSize in
            guard !isLOD, background != .plain else { return }
            let step = MapMetrics.gridPitch * scale
            guard step > 6 else { return }
            let startX = offset.width.truncatingRemainder(dividingBy: step) - step
            let startY = offset.height.truncatingRemainder(dividingBy: step) - step
            var marks = Path()
            if background == .grid {
                var x = startX
                while x < canvasSize.width + step {
                    marks.move(to: CGPoint(x: x, y: 0))
                    marks.addLine(to: CGPoint(x: x, y: canvasSize.height))
                    x += step
                }
                var y = startY
                while y < canvasSize.height + step {
                    marks.move(to: CGPoint(x: 0, y: y))
                    marks.addLine(to: CGPoint(x: canvasSize.width, y: y))
                    y += step
                }
                context.stroke(marks, with: .color(MinorColor.canvasDot.opacity(0.7)), lineWidth: 0.5)
                return
            }
            var y = startY
            while y < canvasSize.height + step {
                var x = startX
                while x < canvasSize.width + step {
                    marks.addEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
                    x += step
                }
                y += step
            }
            context.fill(marks, with: .color(MinorColor.canvasDot))
        }
        .allowsHitTesting(false)
    }

    private func startPulse(_ id: UUID?) {
        guard let id, layout.node(id) != nil else {
            pulse = nil
            return
        }
        let start = Date()
        pulse = (id, start)
        let depth = layout.branch(of: id).map(\.depth).max() ?? 0
        DispatchQueue.main.asyncAfter(deadline: .now() + BranchPulse.duration(depth: depth) + 0.1) {
            if pulse?.start == start { pulse = nil }
        }
    }

    private var content: some View {
        ZStack(alignment: .topLeading) {
            if !layout.groups.isEmpty { MapGroupsLayer(layout: layout) }
            connectors
            if !links.isEmpty { MapLinksLayer(layout: layout, links: links, showLabels: !isLOD) }
            if let pulse, layout.node(pulse.id) != nil {
                BranchPulse(layout: layout, focus: pulse.id, start: pulse.start, lineStyle: lineStyle, lineScale: lineWeight.scale)
                    .id(pulse.start)
            }
            ForEach(layout.nodes) { node in
                if isLOD && node.level >= 2 {
                    EmptyView()
                } else {
                    MindNodeView(
                        node: node,
                        theme: theme,
                        isSelected: selection == node.id,
                        isGenerating: generating.contains(node.id),
                        isDimmed: dimmed.contains(node.id),
                        isHighlighted: highlighted.contains(node.id) || drag?.target == node.id,
                        mapStyle: mapStyle,
                        onToggleCollapse: { onToggleCollapse(node.id) },
                        onToggleDone: { onToggleDone(node.id) }
                    )
                    .opacity(drag?.id == node.id ? 0.3 : 1)
                    .position(x: node.frame.midX, y: node.frame.midY)
                    .onTapGesture {
                        Haptics.selection()
                        withAnimation(.minorMenu) { selection = node.id }
                    }
                    .simultaneousGesture(TapGesture(count: 2).onEnded { onDoubleTapNode(node.id) })
                    // The root can't be moved, but its collapse button must keep working.
                    .gesture(dragGesture(for: node), including: node.level == 0 ? .subviews : .all)
                    .accessibilityAction { selectForAccessibility(node.id) }
                    .accessibilityActions {
                        Button("Expand with AI") { onExpand(node.id) }
                        Button("Rename") { onDoubleTapNode(node.id) }
                        if node.decor.isTask {
                            Button(node.decor.isDone ? "Mark as Not Done" : "Mark as Done") { onToggleDone(node.id) }
                        }
                        if node.hiddenCount > 0 {
                            Button("Show hidden ideas") { onToggleCollapse(node.id) }
                        } else if node.hasChildren {
                            Button("Collapse") { onToggleCollapse(node.id) }
                        }
                    }
                }
            }
            if let drag, let node = layout.node(drag.id) {
                MindNodeView(node: node, theme: theme, isHighlighted: true, mapStyle: mapStyle)
                    .scaleEffect(1.04)
                    .opacity(0.92)
                    .position(drag.point)
                    .allowsHitTesting(false)
            }
            ForEach(layout.nodes.filter { generating.contains($0.id) }) { node in
                ghosts(for: node)
            }
            // A tap on a connection's middle (its label) edits or removes it.
            ForEach(links) { link in
                if let mid = layout.linkGeometry(link)?.mid {
                    Button { onLinkTap(link) } label: {
                        Group {
                            if link.label.isEmpty || isLOD {
                                Circle().fill(Color(white: 0.16)).overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 1)).frame(width: 10, height: 10)
                            } else {
                                Color.clear
                            }
                        }
                        .frame(width: 36, height: 30)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .position(mid)
                    .accessibilityLabel(link.label.isEmpty ? L("Connection") : L("Connection: \(link.label)"))
                }
            }
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
        .coordinateSpace(name: "mapContent")
    }

    // Long press lifts a node; dropping it on another node makes it that node's child.
    private func dragGesture(for node: LayoutNode) -> some Gesture {
        let layout = layout
        // Worked out only while this node is being dragged: building it for every node on every
        // frame of a pan made large maps stutter.
        func excluded() -> Set<UUID> { layout.subtree(node.id).union(node.parentID.map { [$0] } ?? []) }
        return LongPressGesture(minimumDuration: 0.4)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("mapContent")))
            .updating($drag) { value, state, _ in
                guard case .second(true, let moved) = value else { return }
                if state == nil { Haptics.impact(.medium) }
                let point = moved?.location ?? CGPoint(x: node.frame.midX, y: node.frame.midY)
                let target = moved.flatMap { layout.node(at: $0.location, excluding: excluded())?.id }
                if let target, target != state?.target { Haptics.selection() }
                state = DragState(id: node.id, point: point, target: target)
            }
            .onEnded { value in
                guard case .second(true, let moved?) = value,
                      let target = layout.node(at: moved.location, excluding: excluded())?.id
                else { return }
                Haptics.impact(.rigid)
                onMove(node.id, target)
            }
    }

    // VoiceOver's double tap selects the idea, like a tap.
    private func selectForAccessibility(_ id: UUID) {
        withAnimation(.minorMenu) { selection = id }
    }

    private var connectors: some View {
        Canvas { context, _ in
            for node in layout.nodes {
                guard let path = layout.connector(to: node, style: lineStyle) else { continue }
                let color = node.color ?? .mint
                let width = (node.level == 1 ? MapMetrics.connector1 : MapMetrics.connector2) * lineWeight.scale
                let shading = node.level == 1 ? color.color : color.line
                context.opacity = dimmed.contains(node.id) ? 0.35 : 1
                context.stroke(path, with: .color(shading), style: StrokeStyle(lineWidth: width, lineCap: .round))
                if isLOD && node.level >= 2 {
                    let bar = CGRect(x: node.frame.minX, y: node.frame.midY - 3, width: min(node.frame.width, 120), height: 6)
                    context.fill(Path(roundedRect: bar, cornerRadius: 3), with: .color(color.line))
                }
            }
            context.opacity = 1
            for node in layout.nodes where generating.contains(node.id) {
                for (i, y) in ghostOffsets(for: node).enumerated() {
                    var path = Path()
                    let start = CGPoint(x: node.side < 0 ? node.frame.minX : node.frame.maxX, y: node.frame.midY)
                    let end = CGPoint(x: start.x + MapMetrics.levelGap * node.side, y: node.frame.midY + y)
                    let midX = (start.x + end.x) / 2
                    path.move(to: start)
                    path.addCurve(to: end, control1: CGPoint(x: midX, y: start.y), control2: CGPoint(x: midX, y: end.y))
                    context.stroke(path, with: .color(theme.glowSolid.opacity(0.7)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [4, 5], dashPhase: CGFloat(i) * 3))
                }
            }
        }
        .frame(width: layout.size.width, height: layout.size.height)
        .allowsHitTesting(false)
    }

    private func ghostOffsets(for node: LayoutNode) -> [CGFloat] { [-36, 0, 36] }

    private func ghosts(for node: LayoutNode) -> some View {
        ForEach(Array(ghostOffsets(for: node).enumerated()), id: \.offset) { i, y in
            let width = CGFloat([96, 72, 110][i % 3])
            let edge = node.side < 0 ? node.frame.minX - MapMetrics.levelGap - width / 2 : node.frame.maxX + MapMetrics.levelGap + width / 2
            GhostNode(width: width)
                .position(x: edge, y: node.frame.midY + y)
        }
    }

    // MARK: - Gestures

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .updating($pan) { value, state, _ in state = value.translation }
            .onEnded { value in
                viewport.offset.width += value.translation.width
                viewport.offset.height += value.translation.height
            }
    }

    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .updating($pinch) { value, state, _ in state = value }
            .onEnded { value in
                let newScale = (viewport.scale * value).clamped(to: MapMetrics.zoomRange)
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let ratio = newScale / viewport.scale
                viewport = CanvasViewport(
                    scale: newScale,
                    offset: CGSize(
                        width: center.x - (center.x - viewport.offset.width) * ratio,
                        height: center.y - (center.y - viewport.offset.height) * ratio
                    )
                )
            }
    }

    private func zoom(by factor: CGFloat) {
        let newScale = (viewport.scale * factor).clamped(to: MapMetrics.zoomRange)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let ratio = newScale / viewport.scale
        withAnimation(.minorFit) {
            viewport = CanvasViewport(
                scale: newScale,
                offset: CGSize(
                    width: center.x - (center.x - viewport.offset.width) * ratio,
                    height: center.y - (center.y - viewport.offset.height) * ratio
                )
            )
        }
        UIAccessibility.post(notification: .announcement, argument: "\(Int((newScale * 100).rounded()))%")
    }

    private func openingFit() {
        viewport = .opening(layout, in: size, insets: chromeInsets)
    }

    private func fit(animated: Bool) {
        let target = CanvasViewport.fit(layout.size, in: size, insets: chromeInsets)
        if animated {
            withAnimation(.minorFit) { viewport = target }
        } else {
            viewport = target
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
