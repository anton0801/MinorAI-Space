//
//  StyleSheets.swift
//  Minor Ai
//
//  Style for one idea (shape, fill, color, text) and Design for the whole map (style, palette,
//  lines, background). Both apply as you tap, with the map visible above the sheet.
//

import SwiftUI

// The style copied with "Copy Style", for "Paste Style" on any idea in any map.
@MainActor
enum StyleClipboard {
    static var copied: (look: NodeLook?, color: BranchColor?)?
}

struct NodeStyleSheet: View {
    let node: MindNode
    let isRoot: Bool
    let effectiveColor: BranchColor?
    let theme: AppTheme
    var onLook: (_ wholeBranch: Bool, _ change: @escaping (inout NodeLook) -> Void) -> Void
    var onColor: (_ color: BranchColor?, _ wholeBranch: Bool) -> Void
    var onPaste: (_ wholeBranch: Bool) -> Void
    var onReset: (_ wholeBranch: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var wholeBranch = false
    @State private var copied = StyleClipboard.copied != nil

    private var look: NodeLook { node.look ?? NodeLook() }
    private var swatch: Color { (effectiveColor ?? .mint).color }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("Shape") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(NodeShape.allCases) { shape in
                                    tile(selected: look.shape == shape, label: shapeName(shape)) {
                                        shapePreview(shape)
                                    } action: {
                                        onLook(wholeBranch) { $0.shape = shape }
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        .padding(.horizontal, -20)
                    }

                    section("Fill") {
                        HStack(spacing: 8) {
                            ForEach(NodeFill.allCases) { fill in
                                tile(selected: look.fill == fill, label: fillName(fill)) {
                                    fillPreview(fill)
                                } action: {
                                    onLook(wholeBranch) { $0.fill = fill }
                                }
                            }
                        }
                        Toggle(isOn: Binding(get: { look.dashed }, set: { value in onLook(wholeBranch) { $0.dashed = value } })) {
                            Label("Dashed Border", systemImage: "square.dashed")
                        }
                        .tint(MinorColor.accent)
                        .padding(.top, 4)
                    }

                    section("Color") {
                        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)
                        LazyVGrid(columns: columns, spacing: 10) {
                            Button { onColor(nil, wholeBranch) } label: {
                                Circle()
                                    .stroke(MinorColor.textTertiary, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                                    .overlay(Text("A").font(.system(size: 13, weight: .semibold)).foregroundColor(MinorColor.textSecondary))
                                    .frame(width: 34, height: 34)
                                    .overlay(Circle().stroke(Color.white, lineWidth: 2).padding(-4).opacity(node.color == nil ? 1 : 0))
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel(isRoot ? "Default color" : "Same color as the branch")
                            .accessibilityAddTraits(node.color == nil ? .isSelected : [])
                            ForEach(BranchColor.allCases, id: \.self) { color in
                                Button {
                                    Haptics.selection()
                                    onColor(color, wholeBranch)
                                } label: {
                                    Circle()
                                        .fill(color.color)
                                        .frame(width: 34, height: 34)
                                        .overlay(Circle().stroke(Color.white, lineWidth: 2).padding(-4).opacity(node.color == color ? 1 : 0))
                                        .frame(width: 44, height: 44)
                                }
                                .accessibilityLabel(color.name)
                                .accessibilityAddTraits(node.color == color ? .isSelected : [])
                            }
                        }
                    }

                    section("Text") {
                        HStack(spacing: 8) {
                            ForEach(NodeTextSize.allCases) { size in
                                Button {
                                    Haptics.selection()
                                    onLook(wholeBranch) { $0.size = size }
                                } label: {
                                    Text("Aa")
                                        .font(.system(size: 15 + size.delta, weight: look.bold ? .bold : .regular))
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 44)
                                        .background(RoundedRectangle(cornerRadius: 10).fill(look.size == size ? MinorColor.accent.opacity(0.18) : theme.chatRectangle))
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(look.size == size ? MinorColor.accent : theme.chatStroke, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(sizeName(size))
                                .accessibilityAddTraits(look.size == size ? .isSelected : [])
                            }
                            Button {
                                Haptics.selection()
                                onLook(wholeBranch) { $0.bold.toggle() }
                            } label: {
                                Image(systemName: "bold")
                                    .font(.system(size: 16, weight: .bold))
                                    .frame(width: 52, height: 44)
                                    .foregroundColor(look.bold ? .black : MinorColor.textPrimary)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(look.bold ? MinorColor.accent : theme.chatRectangle))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(look.bold ? .clear : theme.chatStroke, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Bold")
                            .accessibilityAddTraits(look.bold ? .isSelected : [])
                        }
                    }

                    if !node.children.isEmpty {
                        Toggle(isOn: $wholeBranch) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Apply to the Whole Branch")
                                Text("Changes also go to the \(node.count - 1) ideas below.")
                                    .font(.system(size: 13))
                                    .foregroundColor(MinorColor.textTertiary)
                            }
                        }
                        .tint(MinorColor.accent)
                    }

                    HStack(spacing: 8) {
                        actionButton("Copy Style", "doc.on.doc") {
                            StyleClipboard.copied = (node.look, node.color)
                            copied = true
                            Haptics.success()
                        }
                        actionButton("Paste Style", "doc.on.clipboard") { onPaste(wholeBranch) }
                            .disabled(!copied)
                            .opacity(copied ? 1 : 0.4)
                        actionButton("Reset", "arrow.counterclockwise") { onReset(wholeBranch) }
                    }
                }
                .padding(20)
            }
            .foregroundColor(MinorColor.textPrimary)
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("Style")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundColor(MinorColor.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Pieces

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .textCase(.uppercase)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(MinorColor.textTertiary)
            content()
        }
    }

    private func tile<Preview: View>(selected: Bool, label: String, @ViewBuilder preview: () -> Preview, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            VStack(spacing: 6) {
                preview()
                    .frame(width: 46, height: 30)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(selected ? MinorColor.textPrimary : MinorColor.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 64, height: 68)
            .background(RoundedRectangle(cornerRadius: 12).fill(selected ? MinorColor.accent.opacity(0.14) : theme.chatRectangle))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? MinorColor.accent : theme.chatStroke, lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func shapePreview(_ shape: NodeShape) -> some View {
        switch shape {
        case .auto:
            Image(systemName: "wand.and.stars").font(.system(size: 17)).foregroundColor(MinorColor.textSecondary)
        case .underline:
            VStack { Spacer(); Rectangle().fill(swatch).frame(height: 2) }.padding(.horizontal, 4)
        default:
            NodeOutline(kind: shape, radius: 8).fill(swatch.opacity(0.25))
                .overlay(NodeOutline(kind: shape, radius: 8).stroke(swatch, lineWidth: 1.5))
        }
    }

    @ViewBuilder
    private func fillPreview(_ fill: NodeFill) -> some View {
        let shape = NodeOutline(kind: look.shape == .auto || look.shape == .underline ? .rounded : look.shape, radius: 8)
        switch fill {
        case .auto: Image(systemName: "wand.and.stars").font(.system(size: 17)).foregroundColor(MinorColor.textSecondary)
        case .soft: shape.fill(swatch.opacity(0.22)).overlay(shape.stroke(swatch.opacity(0.6), lineWidth: 1))
        case .solid: shape.fill(swatch)
        case .outline: shape.stroke(swatch, lineWidth: 1.5)
        case .none: Text("Aa").font(.system(size: 15, weight: .medium)).foregroundColor(MinorColor.textPrimary)
        }
    }

    private func actionButton(_ title: LocalizedStringKey, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 12).fill(theme.chatRectangle))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.chatStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func shapeName(_ shape: NodeShape) -> String {
        switch shape {
        case .auto: return L("Auto")
        case .rounded: return L("Rounded")
        case .pill: return L("Pill")
        case .square: return L("Square")
        case .ellipse: return L("Oval")
        case .hexagon: return L("Hexagon")
        case .diamond: return L("Diamond")
        case .underline: return L("Underline")
        }
    }

    private func fillName(_ fill: NodeFill) -> String {
        switch fill {
        case .auto: return L("Auto")
        case .soft: return L("Soft")
        case .solid: return L("Solid")
        case .outline: return L("Outlined")
        case .none: return L("None")
        }
    }

    private func sizeName(_ size: NodeTextSize) -> String {
        switch size {
        case .small: return L("Small text")
        case .regular: return L("Regular text")
        case .large: return L("Large text")
        case .huge: return L("Huge text")
        }
    }
}

// The whole map: style preset, palette, connector lines and canvas background.
struct MapDesignSheet: View {
    let map: MindMap
    let theme: AppTheme
    var onStyle: (MapStyle) -> Void
    var onPalette: (MapPalette) -> Void
    var onLines: (LineStyle) -> Void
    var onWeight: (LineWeight) -> Void
    var onBackground: (CanvasBackground) -> Void
    var onResetIdeas: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false

    private var styledIdeas: Int {
        func count(_ node: MindNode) -> Int { (node.look != nil || node.color != nil ? 1 : 0) + node.children.reduce(0) { $0 + count($1) } }
        return count(map.root)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("Style") {
                        HStack(spacing: 8) {
                            ForEach(MapStyle.allCases) { style in
                                option(map.mapStyle == style, styleName(style), icon: styleIcon(style)) { onStyle(style) }
                            }
                        }
                    }
                    section("Palette") {
                        VStack(spacing: 8) {
                            ForEach(MapPalette.allCases) { palette in
                                Button {
                                    Haptics.selection()
                                    onPalette(palette)
                                } label: {
                                    HStack(spacing: 12) {
                                        HStack(spacing: -6) {
                                            ForEach(Array(palette.colors.prefix(6).enumerated()), id: \.offset) { _, color in
                                                Circle().fill(color.color).frame(width: 24, height: 24)
                                                    .overlay(Circle().stroke(theme.background, lineWidth: 2))
                                            }
                                        }
                                        Text(palette.name).font(.system(size: 16))
                                        Spacer()
                                        if map.mapPalette == palette {
                                            Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)).foregroundColor(MinorColor.accent)
                                        }
                                    }
                                    .padding(.horizontal, 14)
                                    .frame(height: 50)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(theme.chatRectangle))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(map.mapPalette == palette ? MinorColor.accent : theme.chatStroke, lineWidth: map.mapPalette == palette ? 1.5 : 1))
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(map.mapPalette == palette ? .isSelected : [])
                            }
                        }
                    }
                    section("Lines") {
                        HStack(spacing: 8) {
                            ForEach(LineStyle.allCases) { style in
                                Button {
                                    Haptics.selection()
                                    onLines(style)
                                } label: {
                                    VStack(spacing: 6) {
                                        LinePreview(style: style).stroke(MinorColor.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                            .frame(width: 54, height: 28)
                                        Text(lineName(style)).font(.system(size: 12))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 72)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(map.lineStyle == style ? MinorColor.accent.opacity(0.14) : theme.chatRectangle))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(map.lineStyle == style ? MinorColor.accent : theme.chatStroke, lineWidth: map.lineStyle == style ? 1.5 : 1))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(lineName(style))
                                .accessibilityAddTraits(map.lineStyle == style ? .isSelected : [])
                            }
                        }
                        HStack(spacing: 8) {
                            ForEach(LineWeight.allCases) { weight in
                                option(map.lineWeightValue == weight, weightName(weight), icon: nil, lineWidth: 1.2 * weight.scale + 0.4) { onWeight(weight) }
                            }
                        }
                    }
                    section("Background") {
                        HStack(spacing: 8) {
                            ForEach(CanvasBackground.allCases) { background in
                                option(map.canvasBackground == background, backgroundName(background), icon: backgroundIcon(background)) { onBackground(background) }
                            }
                        }
                    }
                    if styledIdeas > 0 {
                        Button(role: .destructive) { confirmReset = true } label: {
                            Label("Reset Styles of \(styledIdeas) Ideas", systemImage: "arrow.counterclockwise")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(MinorColor.dangerText)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                        }
                    }
                }
                .padding(20)
            }
            .foregroundColor(MinorColor.textPrimary)
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("Map Design")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundColor(MinorColor.accent)
                }
            }
            .confirmationDialog("Reset the shape, fill, text and color of every idea?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset Styles", role: .destructive) { onResetIdeas() }
                Button("Cancel", role: .cancel) {}
            }
        }
        .preferredColorScheme(.dark)
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .textCase(.uppercase)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(MinorColor.textTertiary)
            content()
        }
    }

    private func option(_ selected: Bool, _ title: String, icon: String?, lineWidth: CGFloat? = nil, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            VStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 18))
                } else if let lineWidth {
                    Capsule().fill(MinorColor.accent).frame(width: 40, height: lineWidth)
                        .frame(height: 20)
                }
                Text(title).font(.system(size: 12)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(RoundedRectangle(cornerRadius: 12).fill(selected ? MinorColor.accent.opacity(0.14) : theme.chatRectangle))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? MinorColor.accent : theme.chatStroke, lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func styleName(_ style: MapStyle) -> String {
        switch style {
        case .classic: return L("Classic")
        case .pills: return L("Pills")
        case .outline: return L("Outlined")
        case .minimal: return L("Minimal")
        }
    }

    private func styleIcon(_ style: MapStyle) -> String {
        switch style {
        case .classic: return "rectangle.roundedtop"
        case .pills: return "capsule"
        case .outline: return "square.dashed"
        case .minimal: return "textformat"
        }
    }

    private func lineName(_ style: LineStyle) -> String {
        switch style {
        case .curved: return L("Curved")
        case .straight: return L("Straight")
        case .elbow: return L("Elbow")
        }
    }

    private func weightName(_ weight: LineWeight) -> String {
        switch weight {
        case .thin: return L("Thin")
        case .regular: return L("Regular")
        case .bold: return L("Bold")
        }
    }

    private func backgroundName(_ background: CanvasBackground) -> String {
        switch background {
        case .dots: return L("Dots")
        case .grid: return L("Grid")
        case .plain: return L("Plain")
        }
    }

    private func backgroundIcon(_ background: CanvasBackground) -> String {
        switch background {
        case .dots: return "circle.grid.3x3"
        case .grid: return "squareshape.split.3x3"
        case .plain: return "square"
        }
    }
}

// A small connector from the left middle to the right bottom, in each line style.
private struct LinePreview: Shape {
    let style: LineStyle

    func path(in rect: CGRect) -> Path {
        let start = CGPoint(x: rect.minX, y: rect.minY + 4)
        let end = CGPoint(x: rect.maxX, y: rect.maxY - 4)
        let midX = rect.midX
        var path = Path()
        path.move(to: start)
        switch style {
        case .curved: path.addCurve(to: end, control1: CGPoint(x: midX, y: start.y), control2: CGPoint(x: midX, y: end.y))
        case .straight: path.addLine(to: end)
        case .elbow:
            path.addLine(to: CGPoint(x: midX, y: start.y))
            path.addLine(to: CGPoint(x: midX, y: end.y))
            path.addLine(to: end)
        }
        return path
    }
}

extension View {
    // The map stays usable above a half-height sheet where iOS allows it (16.4 and later).
    @ViewBuilder
    func mapVisibleBehindSheet() -> some View {
        if #available(iOS 16.4, *) {
            self.presentationBackgroundInteraction(.enabled(upThrough: .medium))
        } else {
            self
        }
    }
}
