//
//  BranchPulse.swift
//  Minor Ai
//
//  When an idea is selected, light runs from it along the connectors to every idea below it,
//  three times, then fades — so a whole branch stands out even in a large, tangled map.
//  With Reduce Motion the branch just glows once and fades.
//

import SwiftUI

struct BranchPulse: View {
    let layout: MapLayout
    let focus: UUID
    let start: Date
    var lineStyle: LineStyle = .curved
    var lineScale: CGFloat = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Timing (seconds): one wave every `period`, each level a little later than its parent.
    static let waves = 3
    static let period: TimeInterval = 0.85
    static let levelDelay: TimeInterval = 0.14
    static let travel: TimeInterval = 0.3
    static let fade: TimeInterval = 0.6

    static func duration(depth: Int) -> TimeInterval {
        Double(waves) * period + Double(min(depth, 8)) * levelDelay + fade
    }

    private struct Member {
        let node: LayoutNode
        let depth: Int
        let path: Path?    // connector from the parent (nil for the root)
        let color: Color
    }

    private let members: [Member]
    private let maxDepth: Int

    init(layout: MapLayout, focus: UUID, start: Date, lineStyle: LineStyle = .curved, lineScale: CGFloat = 1) {
        self.layout = layout
        self.focus = focus
        self.start = start
        self.lineStyle = lineStyle
        self.lineScale = lineScale
        // Large branches pulse their first few hundred ideas; the rest still glow with the fade.
        let branch = layout.branch(of: focus).prefix(400)
        members = branch.map { item in
            Member(
                node: item.node,
                depth: item.depth,
                path: layout.connector(to: item.node, style: lineStyle),
                color: item.node.color?.color ?? MinorColor.accent
            )
        }
        maxDepth = members.map(\.depth).max() ?? 0
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, _ in
                let t = timeline.date.timeIntervalSince(start)
                draw(&context, at: t)
            }
        }
        .frame(width: layout.size.width, height: layout.size.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(_ context: inout GraphicsContext, at t: TimeInterval) {
        let total = Self.duration(depth: maxDepth)
        guard t >= 0, t < total else { return }
        // The whole branch glows while the waves run, then fades out.
        let envelope = t < total - Self.fade ? min(1, t / 0.15) : max(0, (total - t) / Self.fade)
        let glow = members.count <= 150

        for member in members {
            let width = (member.depth <= 1 && member.node.level == 1 ? MapMetrics.connector1 : MapMetrics.connector2) * lineScale
            // Lines into the branch: brighter and a little thicker than usual.
            if let path = member.path, member.depth > 0 {
                context.stroke(path, with: .color(member.color.opacity(0.55 * envelope)), style: StrokeStyle(lineWidth: width + 1.5, lineCap: .round))
                if !reduceMotion {
                    for wave in 0..<Self.waves {
                        let begin = Double(wave) * Self.period + Double(member.depth - 1) * Self.levelDelay
                        let local = (t - begin) / Self.travel
                        guard local > 0, local < 1.6 else { continue }
                        // A short comet travels from the parent to the child.
                        let head = min(1, local)
                        let tail = max(0, head - 0.4)
                        let fadeOut = local > 1 ? max(0, 1 - (local - 1) / 0.6) : 1
                        let comet = path.trimmedPath(from: tail, to: head)
                        context.drawLayer { layer in
                            if glow { layer.addFilter(.shadow(color: member.color, radius: 5)) }
                            layer.stroke(comet, with: .color(Color.white.opacity(0.95 * fadeOut)), style: StrokeStyle(lineWidth: width + 1.5, lineCap: .round))
                        }
                    }
                }
            }
            // A ring around the idea that lights up as the wave arrives.
            let ring = NodeOutline(kind: member.node.decor.look.shape == .auto || member.node.decor.look.shape == .underline ? .rounded : member.node.decor.look.shape,
                                   radius: member.node.level == 0 ? 19 : 14)
                .path(in: member.node.frame.insetBy(dx: -4, dy: -4))
            var intensity = 0.0
            if reduceMotion {
                intensity = 0.6
            } else {
                for wave in 0..<Self.waves {
                    let arrival = Double(wave) * Self.period + Double(member.depth) * Self.levelDelay + (member.depth > 0 ? Self.travel * 0.6 : 0)
                    let x = (t - arrival) / 0.22
                    intensity = max(intensity, exp(-x * x))
                }
                intensity = max(intensity, 0.25)
            }
            intensity *= envelope
            guard intensity > 0.02 else { continue }
            context.drawLayer { layer in
                if glow { layer.addFilter(.shadow(color: member.color.opacity(intensity), radius: 8 * intensity)) }
                layer.stroke(ring, with: .color(member.color.opacity(intensity)), lineWidth: 1.5 + 1.5 * intensity)
            }
        }
    }
}
