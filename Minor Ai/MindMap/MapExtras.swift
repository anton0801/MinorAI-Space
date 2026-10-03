//
//  MapExtras.swift
//  Minor Ai
//
//  Frames around branches and connections between any two ideas, drawn on the canvas and in
//  exported images.
//

import SwiftUI

extension MapLayout {
    // The arrow for a connection: from the edge of one idea to the edge of the other, bowed a
    // little so it doesn't run along the tree's own connectors. Nil when either idea is hidden.
    func linkGeometry(_ link: MapLink) -> (path: Path, head: Path, mid: CGPoint)? {
        guard let a = node(link.from)?.frame, let b = node(link.to)?.frame else { return nil }
        let ca = CGPoint(x: a.midX, y: a.midY)
        let cb = CGPoint(x: b.midX, y: b.midY)
        func edge(of rect: CGRect, toward point: CGPoint) -> CGPoint {
            let dx = point.x - rect.midX, dy = point.y - rect.midY
            guard dx != 0 || dy != 0 else { return CGPoint(x: rect.midX, y: rect.midY) }
            let scale = min(dx == 0 ? .infinity : (rect.width / 2 + 4) / abs(dx), dy == 0 ? .infinity : (rect.height / 2 + 4) / abs(dy))
            return CGPoint(x: rect.midX + dx * scale, y: rect.midY + dy * scale)
        }
        let start = edge(of: a, toward: cb)
        let end = edge(of: b, toward: ca)
        let dx = end.x - start.x, dy = end.y - start.y
        let length = max(sqrt(dx * dx + dy * dy), 1)
        let bow = min(length * 0.22, 80)
        let control = CGPoint(x: (start.x + end.x) / 2 - dy / length * bow, y: (start.y + end.y) / 2 + dx / length * bow)
        var path = Path()
        path.move(to: start)
        path.addQuadCurve(to: end, control: control)
        // Arrowhead along the curve's last direction.
        let ux = end.x - control.x, uy = end.y - control.y
        let ul = max(sqrt(ux * ux + uy * uy), 0.001)
        let (nx, ny) = (ux / ul, uy / ul)
        let size: CGFloat = 9
        var head = Path()
        head.move(to: CGPoint(x: end.x - nx * size - ny * size * 0.55, y: end.y - ny * size + nx * size * 0.55))
        head.addLine(to: end)
        head.addLine(to: CGPoint(x: end.x - nx * size + ny * size * 0.55, y: end.y - ny * size - nx * size * 0.55))
        let mid = CGPoint(x: 0.25 * start.x + 0.5 * control.x + 0.25 * end.x, y: 0.25 * start.y + 0.5 * control.y + 0.25 * end.y)
        return (path, head, mid)
    }
}

// Frames around branches, behind everything else.
struct MapGroupsLayer: View {
    let layout: MapLayout

    var body: some View {
        Canvas { context, _ in
            for group in layout.groups {
                let color = group.color ?? .mint
                let shape = Path(roundedRect: group.rect, cornerRadius: 16)
                context.fill(shape, with: .color(color.color.opacity(0.06)))
                context.stroke(shape, with: .color(color.line), style: StrokeStyle(lineWidth: 1.2, dash: [6, 4]))
                if !group.label.isEmpty {
                    let text = Text(group.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(color.color)
                    context.draw(text, at: CGPoint(x: group.rect.minX + 12, y: group.rect.minY + MapLayout.frameLabelHeight / 2 + 4), anchor: .leading)
                }
            }
        }
        .frame(width: layout.size.width, height: layout.size.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// Connections between ideas: dashed arrows with their labels.
struct MapLinksLayer: View {
    let layout: MapLayout
    let links: [MapLink]
    var showLabels = true

    var body: some View {
        Canvas { context, _ in
            for link in links {
                guard let geometry = layout.linkGeometry(link) else { continue }
                let color = Color.white.opacity(0.55)
                context.stroke(geometry.path, with: .color(color), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [5, 5]))
                context.stroke(geometry.head, with: .color(color), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                if showLabels, !link.label.isEmpty {
                    let text = context.resolve(Text(link.label).font(.system(size: 12, weight: .medium)).foregroundColor(MinorColor.textPrimary))
                    let size = text.measure(in: CGSize(width: 180, height: 40))
                    let box = CGRect(x: geometry.mid.x - size.width / 2 - 8, y: geometry.mid.y - size.height / 2 - 4, width: size.width + 16, height: size.height + 8)
                    context.fill(Path(roundedRect: box, cornerRadius: box.height / 2), with: .color(Color(white: 0.16)))
                    context.stroke(Path(roundedRect: box, cornerRadius: box.height / 2), with: .color(Color.white.opacity(0.25)), lineWidth: 1)
                    context.draw(text, in: box.insetBy(dx: 8, dy: 4))
                }
            }
        }
        .frame(width: layout.size.width, height: layout.size.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
