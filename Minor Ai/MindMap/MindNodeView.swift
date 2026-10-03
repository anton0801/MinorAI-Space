//
//  MindNodeView.swift
//  Minor Ai
//
//  One node on the canvas: root (white), branch (tinted plate) or leaf (text with a dot),
//  plus selection ring, AI sweep, collapsed counter and dimming.
//

import SwiftUI

struct MindNodeView: View {
    let node: LayoutNode
    let theme: AppTheme
    var isSelected = false
    var isGenerating = false
    var isDimmed = false
    var isHighlighted = false
    var mapStyle: MapStyle = .classic
    var onToggleCollapse: () -> Void = {}
    var onToggleDone: () -> Void = {}

    private var decor: NodeDecor { node.decor }
    private var look: NodeLook { decor.look }
    private var isCallout: Bool { decor.isCallout && node.level > 0 }
    private var isCard: Bool { decor.image != nil || isCallout }
    private var baseStyle: NodeStyle { NodeStyle(level: node.level, look: look) }
    private var style: NodeStyle { isCallout ? NodeStyle(level: 2, callout: true, look: look) : baseStyle }
    private var growsLeft: Bool { node.side < 0 }
    private var branch: BranchColor { node.color ?? .mint }
    private var radius: CGFloat {
        if mapStyle == .pills && !baseStyle.isRoot && !isCard { return node.frame.height / 2 }
        return baseStyle.isRoot ? 16 : baseStyle.isBranch || isCard ? 12 : 10
    }
    // A shape or fill picked in the Style panel replaces the map style's plate.
    private var hasCustomLook: Bool { !isCard && (look.shape != .auto || look.fill != .auto || look.dashed || (baseStyle.isRoot && node.color != nil)) }
    private var shapeKind: NodeShape {
        if isCard { return .rounded }
        if look.shape != .auto { return look.shape }
        return mapStyle == .pills && !baseStyle.isRoot ? .pill : .rounded
    }
    private var fillKind: NodeFill {
        if look.fill != .auto { return look.fill }
        if baseStyle.isRoot { return .solid }
        return shapeKind == .underline ? .none : .soft
    }
    private var outline: NodeOutline { NodeOutline(kind: shapeKind, radius: radius) }
    // Leaves without a plate are drawn as text with a colored dot.
    private var plainLeaf: Bool { baseStyle.isLeaf && !isCard && !hasCustomLook && !decor.isSuggestion && (mapStyle == .classic || mapStyle == .outline) }
    private var sideInset: CGFloat { baseStyle.shapeInset(for: decor, frame: node.frame.size) }
    private var trailingText: Bool { growsLeft && plainLeaf }
    private var rootOnDark: Bool { baseStyle.isRoot && (mapStyle == .outline || mapStyle == .minimal) }

    var body: some View {
        ZStack(alignment: .leading) {
            plate
            VStack(alignment: trailingText ? .trailing : .leading, spacing: NodeStyle.imageSpacing) {
                if let image = decor.image {
                    let inner = node.frame.width - baseStyle.insets.leading - baseStyle.insets.trailing
                    NodePicture(id: image.id)
                        .frame(width: inner, height: NodeStyle.imageHeight(inner: inner, aspect: image.aspect))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                VStack(alignment: trailingText ? .trailing : .leading, spacing: 0) {
                    titleRow
                    if decor.linkHost != nil || decor.due != nil {
                        HStack(spacing: 8) {
                            if let due = decor.due {
                                DueLabel(date: due)
                            }
                            if let host = decor.linkHost {
                                HStack(spacing: 4) {
                                    Image(systemName: "link").font(.system(size: 10, weight: .semibold))
                                    Text(host).font(.system(size: 12)).lineLimit(1)
                                }
                                .foregroundColor(MinorColor.textTertiary)
                            }
                        }
                        .frame(height: NodeStyle.linkLineHeight)
                    }
                }
            }
            .padding(trailingText
                ? EdgeInsets(top: style.insets.top, leading: style.insets.trailing, bottom: style.insets.bottom, trailing: style.insets.leading)
                : (decor.image != nil ? baseStyle.insets : style.insets))
            .padding(.horizontal, sideInset)
            .frame(maxWidth: .infinity, alignment: trailingText ? .trailing : (shapeKind == .ellipse || shapeKind == .diamond || shapeKind == .hexagon) && !isCard ? .center : .leading)
            if plainLeaf {
                Circle()
                    .fill(branch.color)
                    .frame(width: 5, height: 5)
                    .frame(maxWidth: .infinity, alignment: growsLeft ? .trailing : .leading)
                    .padding(.horizontal, 3)
            }
        }
        .frame(width: node.frame.width, height: node.frame.height, alignment: .leading)
        .overlay(alignment: .leading) {
            if isGenerating { Sweep().clipShape(outline) }
        }
        .overlay {
            if isSelected {
                NodeOutline(kind: shapeKind == .underline ? .rounded : shapeKind, radius: radius + 3)
                    .stroke(Color.white, lineWidth: 1.5)
                    .padding(-3)
            } else if isHighlighted {
                NodeOutline(kind: shapeKind == .underline ? .rounded : shapeKind, radius: radius)
                    .stroke(MinorColor.accent, lineWidth: 1.5)
            }
        }
        .overlay(alignment: growsLeft ? .leading : .trailing) {
            if node.hiddenCount > 0 {
                Button(action: onToggleCollapse) {
                    Text("+\(node.hiddenCount)")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundColor(MinorColor.textPrimary)
                        .padding(.horizontal, 7)
                        .frame(minWidth: 28, minHeight: 22)
                        .background(Capsule().fill(theme.background))
                        .overlay(Capsule().stroke(branch.line, lineWidth: 1))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .offset(x: growsLeft ? -44 : 44)
                .accessibilityLabel("Show \(node.hiddenCount) hidden ideas")
            }
        }
        .opacity(isDimmed ? 0.35 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // Glyphs, title and task progress on one line. Glyph frames are 14 pt plus 6 pt spacing (20 pt
    // each in NodeStyle); the emoji gets 18 pt.
    private var titleRow: some View {
        HStack(spacing: 6) {
            if decor.isSuggestion {
                Image(systemName: "lightbulb")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(MinorColor.accent)
                    .frame(width: 14)
            } else if node.isAIAdded && !baseStyle.isRoot {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(branch.color)
                    .frame(width: 14)
            }
            if node.hasNote && !baseStyle.isRoot {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(MinorColor.textTertiary)
                    .frame(width: 14)
                    .accessibilityHidden(true)
            }
            if let priority = decor.priority {
                Text("\(priority)")
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .foregroundColor(.black)
                    .frame(width: 14, height: 14)
                    .background(Circle().fill(priorityColor(priority)))
            }
            if decor.isTask {
                Button(action: onToggleDone) {
                    Image(systemName: decor.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(decor.isDone ? MinorColor.accent : titleColor.opacity(0.8))
                        .frame(width: 14)
                }
                .buttonStyle(.plain)
            }
            if let icon = decor.icon {
                Text(icon)
                    .font(.system(size: 14))
                    .frame(width: 18)
            }
            Text(node.title)
                .font(style.font)
                .foregroundColor(titleColor)
                .strikethrough(decor.isTask && decor.isDone, color: titleColor.opacity(0.6))
                .opacity(decor.isTask && decor.isDone ? 0.6 : 1)
                .lineLimit(style.maxLines)
                .lineSpacing(style.lineHeight - style.fontSize * 1.2)
                .fixedSize(horizontal: false, vertical: true)
            if decor.showsProgress {
                Text("\(decor.tasksDone)/\(decor.tasksTotal)")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundColor(decor.tasksDone == decor.tasksTotal ? .black : titleColor)
                    .padding(.horizontal, 6)
                    .frame(width: NodeStyle.progressWidth - 6, height: 18)
                    .background(Capsule().fill(decor.tasksDone == decor.tasksTotal ? MinorColor.accent : Color.white.opacity(0.12)))
            }
        }
    }

    private var titleColor: Color {
        if hasCustomLook { return fillKind == .solid ? .black : MinorColor.textPrimary }
        if baseStyle.isRoot { return rootOnDark ? MinorColor.textPrimary : .black }
        if mapStyle == .minimal && baseStyle.isBranch && !isCard { return branch.color }
        return MinorColor.textPrimary
    }

    private func priorityColor(_ priority: Int) -> Color {
        switch priority {
        case 1: return Color(hex: "#FF6B6B")
        case 2: return Color(hex: "#FFD66B")
        default: return Color(hex: "#7CC4FF")
        }
    }

    private var strokeStyle: StrokeStyle {
        StrokeStyle(lineWidth: fillKind == .outline ? 1.5 : 1, dash: look.dashed ? [5, 4] : [])
    }

    // The plate for a shape and fill picked in the Style panel.
    @ViewBuilder
    private var customPlate: some View {
        let solid = baseStyle.isRoot && node.color == nil ? MinorColor.sendFill : branch.color
        if shapeKind == .underline {
            VStack {
                Spacer()
                Rectangle()
                    .fill(fillKind == .solid ? solid : branch.color)
                    .frame(height: fillKind == .solid ? 3 : 2)
                    .mask(look.dashed ? AnyView(DashedBar()) : AnyView(Rectangle()))
            }
        } else {
            switch fillKind {
            case .solid, .auto:
                outline.fill(solid)
                    .overlay(outline.stroke(look.dashed ? Color.black.opacity(0.35) : .clear, style: strokeStyle))
                    .shadow(color: baseStyle.isRoot ? theme.blur : .clear, radius: 24)
            case .soft:
                outline.fill(theme.chatRectangle)
                    .overlay(outline.fill(branch.tint))
                    .overlay(outline.stroke(branch.line, style: strokeStyle))
            case .outline:
                outline.fill(theme.background)
                    .overlay(outline.stroke(branch.color, style: strokeStyle))
            case .none:
                outline.stroke(look.dashed ? branch.line : .clear, style: strokeStyle)
                    .background(outline.fill(isSelected ? theme.chatRectangle : .clear))
            }
        }
    }

    @ViewBuilder
    private var plate: some View {
        if decor.isSuggestion && !isCard {
            // A suggestion: dashed and see-through until it is accepted.
            outline.fill(MinorColor.accent.opacity(isSelected ? 0.14 : 0.06))
                .overlay(outline.stroke(MinorColor.accent.opacity(0.8), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])))
        } else if hasCustomLook {
            customPlate
        } else if baseStyle.isRoot {
            switch mapStyle {
            case .classic, .pills:
                RoundedRectangle(cornerRadius: radius)
                    .fill(MinorColor.sendFill)
                    .shadow(color: theme.blur, radius: 24)
            case .outline:
                RoundedRectangle(cornerRadius: radius)
                    .fill(theme.background)
                    .overlay(RoundedRectangle(cornerRadius: radius).stroke(Color.white, lineWidth: 2))
            case .minimal:
                Color.clear
            }
        } else if isCard {
            // Pictures and callouts: a card with a colored edge.
            RoundedRectangle(cornerRadius: radius)
                .fill(theme.chatRectangle)
                .overlay(alignment: .leading) {
                    if isCallout { Rectangle().fill(branch.color).frame(width: 3).padding(.vertical, 8).padding(.leading, 6) }
                }
                .overlay(RoundedRectangle(cornerRadius: radius).stroke(branch.line, lineWidth: 1))
        } else if baseStyle.isBranch {
            switch mapStyle {
            case .classic, .pills:
                RoundedRectangle(cornerRadius: radius)
                    .fill(theme.chatRectangle)
                    .overlay(RoundedRectangle(cornerRadius: radius).fill(branch.tint))
                    .overlay(RoundedRectangle(cornerRadius: radius).stroke(branch.line, lineWidth: 1))
            case .outline:
                RoundedRectangle(cornerRadius: radius)
                    .fill(theme.background)
                    .overlay(RoundedRectangle(cornerRadius: radius).stroke(branch.color, lineWidth: 1.5))
            case .minimal:
                RoundedRectangle(cornerRadius: radius)
                    .fill(isSelected ? theme.chatRectangle : Color.clear)
            }
        } else if mapStyle == .pills {
            RoundedRectangle(cornerRadius: radius)
                .fill(theme.chatRectangle)
                .overlay(RoundedRectangle(cornerRadius: radius).stroke(branch.line, lineWidth: 1))
        } else {
            RoundedRectangle(cornerRadius: radius)
                .fill(isSelected ? theme.chatRectangle : Color.clear)
        }
    }

    private var accessibilityText: String {
        let kind = baseStyle.isRoot ? L("topic") : baseStyle.isBranch ? L("branch") : L("idea")
        var text = "\(node.title), \(kind)"
        if let icon = decor.icon { text = "\(icon) \(text)" }
        if decor.isSuggestion { text += L(", suggestion") }
        if decor.isTask { text += decor.isDone ? L(", done") : L(", to do") }
        if let priority = decor.priority { text += L(", priority \(priority)") }
        if decor.showsProgress { text += L(", \(decor.tasksDone) of \(decor.tasksTotal) tasks done") }
        if decor.image != nil { text += L(", picture") }
        if let host = decor.linkHost { text += L(", link to \(host)") }
        if node.hiddenCount > 0 { text += L(", \(node.hiddenCount) hidden") }
        if isGenerating { text += L(", expanding") }
        return text
    }
}

// The outline of a node's plate for each shape in the Style panel.
struct NodeOutline: InsettableShape {
    var kind: NodeShape
    var radius: CGFloat
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        switch kind {
        case .auto, .rounded, .underline:
            return RoundedRectangle(cornerRadius: max(0, radius - inset)).path(in: r)
        case .pill:
            return Capsule().path(in: r)
        case .square:
            return RoundedRectangle(cornerRadius: 3).path(in: r)
        case .ellipse:
            return Ellipse().path(in: r)
        case .hexagon:
            let d = min(r.height * 0.25, r.width / 4)
            return smoothPolygon([
                CGPoint(x: r.minX, y: r.midY), CGPoint(x: r.minX + d, y: r.minY), CGPoint(x: r.maxX - d, y: r.minY),
                CGPoint(x: r.maxX, y: r.midY), CGPoint(x: r.maxX - d, y: r.maxY), CGPoint(x: r.minX + d, y: r.maxY),
            ], corner: 4)
        case .diamond:
            return smoothPolygon([
                CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.midY), CGPoint(x: r.midX, y: r.maxY), CGPoint(x: r.minX, y: r.midY),
            ], corner: 6)
        }
    }

    func inset(by amount: CGFloat) -> NodeOutline {
        var copy = self
        copy.inset += amount
        return copy
    }

    // A closed polygon with slightly rounded corners.
    private func smoothPolygon(_ points: [CGPoint], corner: CGFloat) -> Path {
        var path = Path()
        let count = points.count
        for i in 0..<count {
            let prev = points[(i + count - 1) % count]
            let point = points[i]
            let next = points[(i + 1) % count]
            func toward(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
                let dx = b.x - a.x, dy = b.y - a.y
                let length = max(sqrt(dx * dx + dy * dy), 0.001)
                let t = min(corner, length / 2) / length
                return CGPoint(x: a.x + dx * t, y: a.y + dy * t)
            }
            let start = toward(point, prev)
            let end = toward(point, next)
            if i == 0 { path.move(to: start) } else { path.addLine(to: start) }
            path.addQuadCurve(to: end, control: point)
        }
        path.closeSubpath()
        return path
    }
}

private struct DashedBar: View {
    var body: some View {
        GeometryReader { geo in
            Path { p in
                p.move(to: CGPoint(x: 0, y: geo.size.height / 2))
                p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height / 2))
            }
            .stroke(style: StrokeStyle(lineWidth: geo.size.height, dash: [5, 4]))
        }
    }
}

// "Due Fri" under a task; red once the day has passed.
struct DueLabel: View {
    let date: Date

    var body: some View {
        let calendar = Calendar.current
        let overdue = calendar.startOfDay(for: date) < calendar.startOfDay(for: Date())
        let today = calendar.isDateInToday(date)
        HStack(spacing: 4) {
            Image(systemName: "calendar").font(.system(size: 10, weight: .semibold))
            Text(Self.text(for: date)).font(.system(size: 12, weight: today || overdue ? .semibold : .regular)).lineLimit(1)
        }
        .foregroundColor(overdue ? MinorColor.dangerText : today ? MinorColor.accent : MinorColor.textTertiary)
    }

    static func text(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return L("Today") }
        if calendar.isDateInTomorrow(date) { return L("Tomorrow") }
        if calendar.isDateInYesterday(date) { return L("Yesterday") }
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.current.locale
        formatter.setLocalizedDateFormatFromTemplate(calendar.isDate(date, equalTo: Date(), toGranularity: .year) ? "MMMd" : "yMMMd")
        return formatter.string(from: date)
    }
}

// A node's picture, loaded from the map store's files (synchronously, so image export sees it).
struct NodePicture: View {
    let id: UUID

    var body: some View {
        if let image = MapStore.shared.image(id) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            Rectangle().fill(MinorColor.fillRow)
                .overlay(Image(systemName: "photo").foregroundColor(MinorColor.textTertiary))
        }
    }
}

// The moving highlight used while AI works on a node (sweep token, 50pt wide, 1.6 s).
struct Sweep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            if !reduceMotion {
                LinearGradient(colors: [.clear, MinorColor.sweep, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 50)
                    .offset(x: -60 + phase * (geo.size.width + 120))
                    .onAppear {
                        withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) { phase = 1 }
                    }
            }
        }
        .allowsHitTesting(false)
    }
}

// Grey placeholder bar for a child the AI has not returned yet.
struct GhostNode: View {
    var width: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(MinorColor.fillRow)
            .frame(width: width, height: 24)
            .overlay(Sweep().clipShape(RoundedRectangle(cornerRadius: 10)))
    }
}
