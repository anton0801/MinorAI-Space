//
//  DiagramView.swift
//  Minor Ai
//
//  A diagram drawn from its geometry (DiagramLayout): boxes with an icon and a label, connections
//  with arrowheads and labels, a matrix's grid, quadrants and axes. The slide, the editor, PDF
//  export and presenting all draw it this way; PowerPoint gets the same geometry as shapes.
//

import SwiftUI

struct DiagramView: View {
    let geometry: DiagramGeometry
    let diagram: SlideDiagram
    let style: SlideStyle
    let font: (CGFloat, Font.Weight) -> Font
    let textColor: Color?
    var selectedPart: String?
    var probe: SlideLayoutProbe?
    var reveal: (Int) -> Reveal

    static func key(_ id: UUID) -> String { "dn.\(id.uuidString)" }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let axes = geometry.axes { axesView(axes) }
            ForEach(geometry.connectors) { connector in
                connectorView(connector)
            }
            ForEach(Array(geometry.boxes.enumerated()), id: \.element.id) { i, box in
                boxView(box)
                    .frame(width: box.frame.width, height: box.frame.height)
                    .overlay { if selectedPart == Self.key(box.id) { selection(box) } }
                    .probed(Self.key(box.id), probe)
                    .modifier(reveal(i))
                    .position(x: box.frame.midX, y: box.frame.midY)
            }
            if geometry.empty {
                Text("Add the first step")
                    .font(font(28, .medium))
                    .foregroundColor(style.secondary)
                    .frame(width: DiagramLayout.area.width, height: DiagramLayout.area.height)
                    .position(x: DiagramLayout.area.midX, y: DiagramLayout.area.midY)
            }
        }
        .frame(width: SlideView.size.width, height: SlideView.size.height, alignment: .topLeading)
    }

    private func color(_ index: Int) -> Color { style.palette[index % max(style.palette.count, 1)] }

    @ViewBuilder
    private func boxView(_ box: DiagramGeometry.Box) -> some View {
        let tint = color(box.color)
        switch box.shape {
        case .circle:
            Circle()
                .fill(LinearGradient(colors: [style.accent, style.palette.dropFirst().first ?? style.accent], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(
                    Text(box.label)
                        .font(font(box.fontSize, .bold))
                        .foregroundColor(textColor ?? style.onAccent)
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .minimumScaleFactor(0.85)
                        .padding(22)
                )
        case .chip:
            Text(box.label)
                .font(font(box.fontSize, .semibold))
                .foregroundColor(textColor ?? style.text)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Capsule().fill(style.isLight ? Color.white : Color(hex: "#1D1A20")))
                .overlay(Capsule().stroke(tint, lineWidth: 3))
        case .roundRect:
            let filled = diagram.filled != false
            VStack(spacing: 8) {
                if let icon = box.icon {
                    Image(systemName: icon)
                        .font(.system(size: box.fontSize * 0.9, weight: .semibold))
                        .foregroundColor(filled ? (style.isLight ? .white : .black) : tint)
                        .frame(width: box.fontSize * 1.6, height: box.fontSize * 1.6)
                        .background(Circle().fill(filled ? tint : tint.opacity(0.18)))
                }
                Text(box.label)
                    .font(font(box.fontSize, .semibold))
                    .foregroundColor(textColor ?? style.text)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 22).fill(filled ? tint.opacity(style.isLight ? 0.2 : 0.24) : style.card))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(filled ? tint.opacity(0.0) : tint, lineWidth: 3))
        }
    }

    // The editor's selection: a frame with a handle at each corner.
    private func selection(_ box: DiagramGeometry.Box) -> some View {
        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size).insetBy(dx: -8, dy: -8)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 26)
                    .stroke(MinorColor.accent, lineWidth: 5)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(MinorColor.accent)
                        .frame(width: 24, height: 24)
                        .offset(x: (i % 2 == 0 ? rect.minX : rect.maxX) - 12, y: (i < 2 ? rect.minY : rect.maxY) - 12)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func connectorView(_ connector: DiagramGeometry.Connector) -> some View {
        let points = connector.points
        let color = connector.dashed || !connector.directed ? style.secondary.opacity(0.7) : style.accent
        return ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: points[0])
                for point in points.dropFirst() { path.addLine(to: point) }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round, dash: connector.dashed ? [2, 10] : []))
            if connector.directed, points.count >= 2 {
                Self.arrowhead(at: points[points.count - 1], from: points[points.count - 2]).fill(color)
            }
            if !connector.label.isEmpty {
                let middle = CGPoint(x: (points[0].x + points[points.count - 1].x) / 2, y: (points[0].y + points[points.count - 1].y) / 2)
                Text(connector.label)
                    .font(font(18, .medium))
                    .foregroundColor(style.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(style.isLight ? Color.white.opacity(0.9) : Color.black.opacity(0.55)))
                    .position(middle)
            }
        }
    }

    // A filled triangle ending at `tip`, pointing away from `from`.
    static func arrowhead(at tip: CGPoint, from: CGPoint, size: CGFloat = 18) -> Path {
        let angle = atan2(tip.y - from.y, tip.x - from.x)
        var path = Path()
        path.move(to: tip)
        path.addLine(to: CGPoint(x: tip.x - size * cos(angle - 0.45), y: tip.y - size * sin(angle - 0.45)))
        path.addLine(to: CGPoint(x: tip.x - size * cos(angle + 0.45), y: tip.y - size * sin(angle + 0.45)))
        path.closeSubpath()
        return path
    }

    private func axesView(_ axes: DiagramGeometry.Axes) -> some View {
        let grid = axes.grid
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 18)
                .fill(style.card.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(style.line, lineWidth: 2))
                .frame(width: grid.width, height: grid.height)
                .offset(x: grid.minX, y: grid.minY)
            Path { path in
                path.move(to: CGPoint(x: grid.midX, y: grid.minY))
                path.addLine(to: CGPoint(x: grid.midX, y: grid.maxY))
                path.move(to: CGPoint(x: grid.minX, y: grid.midY))
                path.addLine(to: CGPoint(x: grid.maxX, y: grid.midY))
            }
            .stroke(style.line, style: StrokeStyle(lineWidth: 2, dash: axes.showsQuadrants ? [] : [6, 8]))
            if axes.showsQuadrants {
                ForEach(Array(axes.quadrantLabels.enumerated()), id: \.offset) { _, item in
                    Text(item.1)
                        .font(font(20, .bold))
                        .foregroundColor(style.secondary)
                        .lineLimit(1)
                        .frame(width: item.0.width, height: item.0.height, alignment: .leading)
                        .offset(x: item.0.minX, y: item.0.minY)
                }
            }
            Text(axisText(axes.xLow, axes.xTitle, axes.xHigh))
                .font(font(18, .semibold))
                .foregroundColor(style.secondary)
                .frame(width: grid.width, height: 30)
                .offset(x: grid.minX, y: grid.maxY + 10)
            Text(Self.verticalAxisText(axes))
                .font(font(18, .semibold))
                .foregroundColor(style.secondary)
                .lineLimit(1)
                .frame(width: grid.width, height: 30, alignment: .leading)
                .offset(x: grid.minX, y: grid.minY - 36)
        }
    }

    private func axisText(_ low: String, _ title: String, _ high: String) -> String {
        Self.horizontalAxisText(low, title, high)
    }

    // "low ← Effort → high" under the grid; "↑ Impact · low → high" above it.
    static func horizontalAxisText(_ low: String, _ title: String, _ high: String) -> String {
        [low.isEmpty ? nil : low + " ←", title.isEmpty ? nil : title, high.isEmpty ? nil : "→ " + high].compactMap { $0 }.joined(separator: "  ")
    }

    static func verticalAxisText(_ axes: DiagramGeometry.Axes) -> String {
        guard !axes.yTitle.isEmpty || !axes.yLow.isEmpty || !axes.yHigh.isEmpty else { return "" }
        let range = axes.yLow.isEmpty && axes.yHigh.isEmpty ? "" : " · \(axes.yLow) → \(axes.yHigh)"
        return "↑ \(axes.yTitle)\(range)"
    }
}
