//
//  StyleSheets.swift
//  Minor Ai
//
//  Style for one idea (shape, fill, color, text), Design for the whole map (theme, palette,
//  background, saved themes, view and lines) and Map View. All apply as you tap, with the map
//  visible above the sheet.
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
    private var below: Int { node.count - 1 }

    // The shapes in the order the panel offers them; the first four fill the row, the rest scroll.
    private let shapes: [NodeShape] = [.rounded, .pill, .diamond, .underline, .square, .ellipse, .hexagon]
    private let fills: [NodeFill] = [.soft, .solid, .outline, .none]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                EditorSheetHeader(title: L("Node Style")) { dismiss() }

                if !node.children.isEmpty {
                    MinorSegments(items: [(false, "This Idea", nil), (true, "Whole Branch", nil)], selection: $wholeBranch, height: 30)
                        .padding(.top, 10)
                        .accessibilityValue(wholeBranch ? Text(L("“\(node.title)” and \(below) ideas below")) : Text(L("Only the idea “\(node.title)”")))
                }

                label("Shape").padding(.top, 7)
                GeometryReader { geo in
                    let width = (geo.size.width - 3 * 6) / 4
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(shapes) { shape in
                                tile(selected: look.shape == shape, label: shapeName(shape), width: width) {
                                    shapePreview(shape)
                                } action: {
                                    onLook(wholeBranch) { $0.shape = shape }
                                }
                            }
                        }
                    }
                }
                .frame(height: 50)
                .padding(.top, 6)

                label("Fill").padding(.top, 8)
                GeometryReader { geo in
                    let width = (geo.size.width - 2 * 6) / 3
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(fills) { fill in
                                pill(selected: look.fill == fill, label: fillName(fill), width: width) {
                                    fillMark(fill)
                                } action: {
                                    onLook(wholeBranch) { $0.fill = fill }
                                }
                            }
                            pill(selected: look.dashed, label: L("Dashed"), width: width) {
                                Circle().stroke(look.dashed ? MinorColor.accent : MinorColor.textSecondary, style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 2.5]))
                                    .frame(width: 14, height: 14)
                            } action: {
                                onLook(wholeBranch) { $0.dashed.toggle() }
                            }
                            .accessibilityLabel(Text("Dashed Border"))
                        }
                    }
                }
                .frame(height: 32)
                .padding(.top, 6)

                HStack(spacing: 12) {
                    label("Color").frame(width: 80, alignment: .leading)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 15) {
                            ForEach(BranchColor.allCases, id: \.self) { color in
                                swatchButton(color)
                            }
                            Button { onColor(nil, wholeBranch) } label: {
                                Circle()
                                    .fill(Color.white.opacity(0.12))
                                    .frame(width: 28, height: 28)
                                    .overlay(Text(verbatim: "A").font(.system(size: 11, weight: .semibold)).foregroundColor(MinorColor.textSecondary))
                                    .overlay(Circle().stroke(Color.white, lineWidth: 2).padding(-3).opacity(node.color == nil ? 1 : 0))
                                    .frame(width: 34, height: 38)
                            }
                            .accessibilityLabel(isRoot ? "Default color" : "Same color as the branch")
                            .accessibilityAddTraits(node.color == nil ? .isSelected : [])
                        }
                        .padding(.horizontal, 3)
                    }
                }
                .padding(.top, 6)

                HStack(spacing: 12) {
                    label("Text")
                    Spacer(minLength: 8)
                    HStack(spacing: 0) {
                        ForEach(NodeTextSize.allCases) { size in
                            let chosen = look.size == size
                            Button {
                                Haptics.selection()
                                onLook(wholeBranch) { $0.size = size }
                            } label: {
                                Text(sizeLetter(size))
                                    .font(.system(size: 14, weight: chosen ? .semibold : .regular))
                                    .foregroundColor(chosen ? .white : MinorColor.textSecondary)
                                    .frame(width: 46, height: 30)
                                    .background(RoundedRectangle(cornerRadius: 7).fill(chosen ? MinorColor.fillThumb : Color.clear).padding(2))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(sizeName(size))
                            .accessibilityAddTraits(chosen ? .isSelected : [])
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 9).fill(MinorColor.track))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(0.1), lineWidth: 1))
                    Button {
                        Haptics.selection()
                        onLook(wholeBranch) { $0.bold.toggle() }
                    } label: {
                        Text("B")
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundColor(look.bold ? .black : MinorColor.textPrimary)
                            .frame(width: 50, height: 30)
                            .background(RoundedRectangle(cornerRadius: 9).fill(look.bold ? Color.white : Color.white.opacity(0.08)))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(look.bold ? 0 : 0.1), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Bold text")
                    .accessibilityAddTraits(look.bold ? .isSelected : [])
                }
                .padding(.top, 4)

                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1).padding(.top, 10)

                HStack(spacing: 8) {
                    actionButton("Copy Style", "square.on.square") {
                        StyleClipboard.copied = (node.look, node.color)
                        copied = true
                        Haptics.success()
                    }
                    if copied {
                        actionButton("Paste Style", "doc.on.clipboard") { onPaste(wholeBranch) }
                    }
                    actionButton("Reset", "arrow.counterclockwise") { onReset(wholeBranch) }
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 22)
        }
        // The last row sits over the home indicator's area, as on the other editors' panels.
        .ignoresSafeArea(.container, edges: .bottom)
        .foregroundColor(MinorColor.textPrimary)
        .background(MinorColor.editorSheet.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    // MARK: - Pieces

    private func label(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .minorFont(14, .semibold, style: .subheadline, maxScale: 1.3)
            .foregroundColor(MinorColor.textPrimary)
    }

    private func swatchButton(_ color: BranchColor) -> some View {
        let chosen = node.color == color
        return Button {
            Haptics.selection()
            onColor(color, wholeBranch)
        } label: {
            Circle()
                .fill(color.color)
                .frame(width: 28, height: 28)
                .overlay(Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundColor(.white).opacity(chosen ? 1 : 0))
                .overlay(Circle().stroke(Color.white, lineWidth: 2).padding(-3).opacity(chosen ? 1 : 0))
                .frame(width: 34, height: 38)
        }
        .accessibilityLabel(color.name)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private func tile<Preview: View>(selected: Bool, label: String, width: CGFloat, @ViewBuilder preview: () -> Preview, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            VStack(spacing: 6) {
                preview()
                    .frame(width: 32, height: 16)
                Text(label)
                    .font(.system(size: 11, weight: selected ? .semibold : .regular))
                    .foregroundColor(selected ? MinorColor.textPrimary : MinorColor.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 4)
            }
            .frame(width: width, height: 48)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(selected ? MinorColor.accent : Color.white.opacity(0.1), lineWidth: selected ? 1.5 : 1))
            .padding(.vertical, 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func pill<Mark: View>(selected: Bool, label: String, width: CGFloat, @ViewBuilder mark: () -> Mark, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: 10) {
                mark()
                Text(label)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .foregroundColor(selected ? MinorColor.textPrimary : MinorColor.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.horizontal, 6)
            .frame(width: width, height: 30)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? MinorColor.accent : Color.white.opacity(0.1), lineWidth: selected ? 1.5 : 1))
            .padding(.vertical, 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func shapePreview(_ shape: NodeShape) -> some View {
        let color = look.shape == shape ? swatch : Color.white
        switch shape {
        case .auto:
            Image(systemName: "wand.and.stars").font(.system(size: 15)).foregroundColor(MinorColor.textSecondary)
        case .underline:
            Rectangle().fill(color).frame(height: 1.5)
        default:
            NodeOutline(kind: shape, radius: 5).stroke(color, lineWidth: 1.8)
        }
    }

    // The fill as a small round mark, like the concept's radio-style pills.
    @ViewBuilder
    private func fillMark(_ fill: NodeFill) -> some View {
        let chosen = look.fill == fill
        switch fill {
        case .solid: Circle().fill(chosen ? swatch : MinorColor.textSecondary).frame(width: 14, height: 14)
        case .soft: Circle().fill((chosen ? swatch : Color.white).opacity(0.18)).overlay(Circle().stroke(chosen ? swatch : MinorColor.textSecondary, lineWidth: 1.5)).frame(width: 14, height: 14)
        case .outline: Circle().stroke(chosen ? MinorColor.accent : MinorColor.textSecondary, lineWidth: 1.8).frame(width: 14, height: 14)
        case .none, .auto: Image(systemName: "circle.slash").font(.system(size: 13)).foregroundColor(chosen ? MinorColor.textPrimary : MinorColor.textSecondary)
        }
    }

    private func actionButton(_ title: LocalizedStringKey, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(0.1), lineWidth: 1))
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
        case .none: return L("No Fill")
        }
    }

    private func sizeLetter(_ size: NodeTextSize) -> String {
        switch size {
        case .small: return "S"
        case .regular: return "M"
        case .large: return "L"
        case .huge: return "XL"
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

// A map look saved by the person ("Save as Theme"): style, palette, lines and background,
// kept on this iPhone and offered for every map.
struct SavedMapTheme: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var style: String?
    var palette: String?
    var lines: String?
    var lineWeight: String?
    var canvas: String?

    init(name: String, map: MindMap) {
        self.name = name
        style = map.style
        palette = map.palette
        lines = map.lines
        lineWeight = map.lineWeight
        canvas = map.canvas
    }

    func matches(_ map: MindMap) -> Bool {
        style == map.style && palette == map.palette && lines == map.lines && lineWeight == map.lineWeight && canvas == map.canvas
    }

    func apply(to map: inout MindMap) {
        map.style = style
        map.palette = palette
        map.lines = lines
        map.lineWeight = lineWeight
        map.canvas = canvas
    }
}

@MainActor
final class MapThemeStore: ObservableObject {
    static let shared = MapThemeStore()
    static let limit = 12
    private static let key = "savedMapThemes"

    @Published private(set) var themes: [SavedMapTheme]

    private init() {
        let data = UserDefaults.standard.data(forKey: Self.key)
        themes = data.flatMap { try? JSONDecoder().decode([SavedMapTheme].self, from: $0) } ?? []
    }

    var isFull: Bool { themes.count >= Self.limit }

    @discardableResult
    func save(_ name: String, from map: MindMap) -> SavedMapTheme? {
        let clean = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30))
        guard !clean.isEmpty, !isFull else { return nil }
        let theme = SavedMapTheme(name: clean, map: map)
        themes.append(theme)
        persist()
        return theme
    }

    func delete(_ id: UUID) {
        themes.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(try? JSONEncoder().encode(themes), forKey: Self.key)
    }
}

// The whole map: Theme (style, palette, background, saved themes), View (layout) and Lines.
struct MapDesignSheet: View {
    enum Tab: Hashable { case theme, view, lines }

    let map: MindMap
    let mode: MapEditorView.Mode
    let theme: AppTheme
    @State var tab: Tab = .theme
    var onStyle: (MapStyle) -> Void
    var onPalette: (MapPalette) -> Void
    var onLines: (LineStyle) -> Void
    var onWeight: (LineWeight) -> Void
    var onBackground: (CanvasBackground) -> Void
    var onMode: (MapEditorView.Mode) -> Void
    var onSavedTheme: (SavedMapTheme) -> Void
    var onResetIdeas: () -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var saved = MapThemeStore.shared
    @State private var confirmReset = false
    @State private var naming = false
    @State private var themeName = ""
    @State private var deleting: SavedMapTheme?

    private var styledIdeas: Int {
        func count(_ node: MindNode) -> Int { (node.look != nil || node.color != nil ? 1 : 0) + node.children.reduce(0) { $0 + count($1) } }
        return count(map.root)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                EditorSheetHeader(title: L("Map Design"), subtitle: L("Whole map")) { dismiss() }
                MinorSegments(items: [(Tab.theme, "Theme", nil), (Tab.view, "View", nil), (Tab.lines, "Lines", nil)], selection: $tab, height: 30)
                    .padding(.top, 10)
                    .padding(.bottom, 10)
                switch tab {
                case .theme: themeTab
                case .view:
                    VStack(spacing: 10) {
                        MapLayoutCards(mode: mode, theme: theme, onMode: onMode)
                        footnote(L("Only the arrangement changes; ideas and connections stay."))
                    }
                case .lines:
                    MapLinesPicker(map: map, theme: theme, onLines: onLines, onWeight: onWeight)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 22)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .foregroundColor(MinorColor.textPrimary)
        .background(MinorColor.editorSheet.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .confirmationDialog("Reset the shape, fill, text and color of every idea?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset Styles", role: .destructive) { onResetIdeas() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Save as Theme", isPresented: $naming) {
            TextField("Theme name", text: $themeName)
            Button("Save") {
                if saved.save(themeName, from: map) != nil { Haptics.success() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Style, palette, lines and background, to use on any map on this iPhone.")
        }
        .confirmationDialog(deleting.map { L("Delete the theme “\($0.name)”?") } ?? "", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible, presenting: deleting) { item in
            Button("Delete Theme", role: .destructive) { saved.delete(item.id) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Maps that use it keep their look.")
        }
    }

    @ViewBuilder
    private var themeTab: some View {
        GeometryReader { geo in
            let width = (geo.size.width - 2 * 9) / 3
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 9) {
                    ForEach(MapStyle.allCases) { style in
                        card(selected: map.mapStyle == style && !saved.themes.contains { $0.matches(map) }, title: styleName(style), width: width) {
                            MapThemePreview(style: style, palette: map.mapPalette, lines: map.lineStyle, background: map.canvasBackground)
                        } action: { onStyle(style) }
                    }
                    ForEach(saved.themes) { item in
                        card(selected: item.matches(map), title: item.name, width: width) {
                            MapThemePreview(
                                style: MapStyle(rawValue: item.style ?? "") ?? .classic,
                                palette: MapPalette(rawValue: item.palette ?? "") ?? .vivid,
                                lines: LineStyle(rawValue: item.lines ?? "") ?? .curved,
                                background: CanvasBackground(rawValue: item.canvas ?? "") ?? .dots
                            )
                        } action: { onSavedTheme(item) }
                        .contextMenu {
                            Button(role: .destructive) { deleting = item } label: { Label("Delete Theme", systemImage: "trash") }
                        }
                        .accessibilityAction(named: Text("Delete Theme")) { deleting = item }
                    }
                }
                .padding(.vertical, 1)
            }
        }
        .frame(height: 112)

        divider.padding(.top, 8)

        // The map's colors; the palettes open from here.
        Menu {
            Picker("Palette", selection: Binding(get: { map.mapPalette }, set: { value in
                Haptics.selection()
                onPalette(value)
            })) {
                ForEach(MapPalette.allCases) { palette in Text(palette.name).tag(palette) }
            }
        } label: {
            HStack(spacing: 0) {
                Text("Palette").minorFont(15, .semibold, maxScale: 1.3).foregroundColor(MinorColor.textPrimary)
                Spacer(minLength: 12)
                HStack(spacing: 18) {
                    ForEach(Array(map.mapPalette.colors.prefix(5).enumerated()), id: \.offset) { _, color in
                        Circle().fill(color.color).frame(width: 24, height: 24)
                    }
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(MinorColor.textPrimary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.white.opacity(0.05)))
                        .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 1))
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(Text("Palette"))
        .accessibilityValue(Text(map.mapPalette.name))

        divider

        HStack(spacing: 12) {
            Text("Background").minorFont(15, .semibold, maxScale: 1.3)
            Spacer(minLength: 8)
            MinorSegments(
                items: CanvasBackground.allCases.map { ($0, LocalizedStringKey(backgroundName($0)), nil) },
                selection: Binding(get: { map.canvasBackground }, set: { onBackground($0) }),
                height: 30
            )
            .frame(maxWidth: 255)
        }
        .frame(minHeight: 44)

        if styledIdeas > 0 {
            divider
            Button { confirmReset = true } label: {
                HStack {
                    Text("Reset Styles of \(styledIdeas) Ideas").minorFont(15, maxScale: 1.3)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundColor(MinorColor.textTertiary)
                }
                .frame(minHeight: 42)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }

        Button {
            themeName = ""
            naming = true
        } label: {
            Label("Save as Theme", systemImage: "square.and.arrow.up")
                .minorFont(15, .medium, maxScale: 1.3)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.1), lineWidth: 1))
        }
        .buttonStyle(PressScale())
        .disabled(saved.isFull)
        .opacity(saved.isFull ? 0.5 : 1)
        .padding(.top, 6)
        if saved.isFull {
            footnote(L("Up to \(MapThemeStore.limit) saved themes. Touch and hold one to delete it.")).padding(.top, 8)
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
    }

    private func card<Preview: View>(selected: Bool, title: String, width: CGFloat, @ViewBuilder preview: () -> Preview, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            VStack(spacing: 6) {
                preview()
                    .frame(width: width, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? MinorColor.accent : Color.white.opacity(0.1), lineWidth: selected ? 2 : 1))
                Text(title)
                    .minorFont(13, selected ? .semibold : .regular, maxScale: 1.3)
                    .foregroundColor(selected ? MinorColor.textPrimary : MinorColor.textSecondary)
                    .lineLimit(1)
                    .frame(width: width)
            }
        }
        .buttonStyle(PressScale())
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .minorFont(13, style: .footnote, maxScale: 1.4)
            .foregroundColor(MinorColor.textTertiary)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
    }

    private func styleName(_ style: MapStyle) -> String {
        switch style {
        case .classic: return L("Classic")
        case .pills: return L("Pills")
        case .outline: return L("Outlined")
        case .minimal: return L("Minimal")
        }
    }

    private func backgroundName(_ background: CanvasBackground) -> String {
        switch background {
        case .dots: return "Dots"
        case .grid: return "Grid"
        case .plain: return "Plain"
        }
    }
}

// Map View (from the map's More menu): Tree, Around the Center or List, and the lines.
struct MapViewSheet: View {
    let map: MindMap
    let mode: MapEditorView.Mode
    let theme: AppTheme
    var onMode: (MapEditorView.Mode) -> Void
    var onLines: (LineStyle) -> Void
    var onWeight: (LineWeight) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    EditorSheetHeader(title: L("Map View"), subtitle: L("Whole map")) { dismiss() }
                        .padding(.bottom, 4)
                    MapLayoutCards(mode: mode, theme: theme, onMode: onMode)
                    NavigationLink {
                        ScrollView {
                            MapLinesPicker(map: map, theme: theme, onLines: onLines, onWeight: onWeight)
                                .padding(16)
                        }
                        .foregroundColor(MinorColor.textPrimary)
                        .background(MinorColor.editorSheet.ignoresSafeArea())
                        .navigationTitle(Text("Lines"))
                        .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        HStack(spacing: 14) {
                            LinePreview(style: map.lineStyle)
                                .stroke(MinorColor.textPrimary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                .frame(width: 34, height: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Lines").minorFont(15, .semibold, maxScale: 1.3)
                                Text(MapLinesPicker.lineName(map.lineStyle)).minorFont(13, maxScale: 1.3).foregroundColor(MinorColor.textTertiary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundColor(MinorColor.textTertiary)
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 58)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Text("Only the arrangement changes; ideas and connections stay.")
                        .minorFont(12, style: .caption1, maxScale: 1.4)
                        .foregroundColor(MinorColor.textTertiary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 22)
            }
            .ignoresSafeArea(.container, edges: .bottom)
            .foregroundColor(MinorColor.textPrimary)
            .background(MinorColor.editorSheet.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }
}

// The three arrangements with a small picture of each.
struct MapLayoutCards: View {
    let mode: MapEditorView.Mode
    let theme: AppTheme
    var onMode: (MapEditorView.Mode) -> Void

    var body: some View {
        VStack(spacing: 8) {
            card(.tree, L("Tree"), L("Branches to one side"))
            card(.balanced, L("Around the Center"), L("Balanced left and right"))
            card(.list, L("List"), L("Focus on the structure"))
        }
    }

    private func card(_ value: MapEditorView.Mode, _ title: String, _ detail: String) -> some View {
        let selected = mode == value
        return Button {
            guard !selected else { return }
            Haptics.selection()
            onMode(value)
        } label: {
            HStack(spacing: 16) {
                MapViewPreview(mode: value)
                    .frame(width: 112, height: 62)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.black.opacity(0.4)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).minorFont(16, .semibold, maxScale: 1.3)
                    Text(detail).minorFont(13, maxScale: 1.3).foregroundColor(MinorColor.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ZStack {
                    Circle().stroke(selected ? Color.clear : MinorColor.textTertiary, lineWidth: 1.5)
                    if selected {
                        Circle().fill(MinorColor.accent)
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundColor(.black)
                    }
                }
                .frame(width: 22, height: 22)
            }
            .padding(7)
            .padding(.trailing, 10)
            .background(RoundedRectangle(cornerRadius: 14).fill(selected ? MinorColor.accent.opacity(0.08) : Color.white.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? MinorColor.accent : Color.white.opacity(0.08), lineWidth: selected ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(detail)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

// Line shape and thickness for the whole map.
struct MapLinesPicker: View {
    let map: MindMap
    let theme: AppTheme
    var onLines: (LineStyle) -> Void
    var onWeight: (LineWeight) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            EditorSection(title: "Shape") {
                HStack(spacing: 8) {
                    ForEach(LineStyle.allCases) { style in
                        let selected = map.lineStyle == style
                        Button {
                            Haptics.selection()
                            onLines(style)
                        } label: {
                            VStack(spacing: 8) {
                                LinePreview(style: style).stroke(selected ? MinorColor.accent : MinorColor.textSecondary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                    .frame(width: 44, height: 22)
                                Text(Self.lineName(style)).minorFont(12, selected ? .semibold : .regular, maxScale: 1.3).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 64)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? MinorColor.accent : Color.white.opacity(0.1), lineWidth: selected ? 1.5 : 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Self.lineName(style))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
            EditorSection(title: "Thickness") {
                MinorSegments(
                    items: LineWeight.allCases.map { ($0, LocalizedStringKey(Self.weightKey($0)), nil) },
                    selection: Binding(get: { map.lineWeightValue }, set: { onWeight($0) }),
                    height: 30
                )
            }
        }
    }

    static func lineName(_ style: LineStyle) -> String {
        switch style {
        case .curved: return L("Curved")
        case .straight: return L("Straight")
        case .elbow: return L("Elbow")
        }
    }

    static func weightKey(_ weight: LineWeight) -> String {
        switch weight {
        case .thin: return "Thin"
        case .regular: return "Regular"
        case .bold: return "Bold"
        }
    }
}

// A tiny map in one of the three arrangements.
struct MapViewPreview: View {
    let mode: MapEditorView.Mode

    var body: some View {
        Canvas { context, size in
            let colors = [BranchColor.mint, .sky, .lilac, .sun]
            func pill(_ rect: CGRect, _ color: Color) {
                context.fill(Path(roundedRect: rect, cornerRadius: rect.height / 2), with: .color(color))
            }
            func curve(_ a: CGPoint, _ b: CGPoint, _ color: Color) {
                var path = Path()
                path.move(to: a)
                path.addCurve(to: b, control1: CGPoint(x: (a.x + b.x) / 2, y: a.y), control2: CGPoint(x: (a.x + b.x) / 2, y: b.y))
                context.stroke(path, with: .color(color), lineWidth: 1.5)
            }
            let w = size.width, h = size.height
            switch mode {
            case .tree:
                let root = CGRect(x: w * 0.1, y: h / 2 - 6, width: w * 0.28, height: 12)
                for i in 0..<4 {
                    let y = h * 0.17 + CGFloat(i) * h * 0.22
                    let node = CGRect(x: w * 0.6, y: y - 5, width: w * 0.28, height: 10)
                    curve(CGPoint(x: root.maxX, y: root.midY), CGPoint(x: node.minX, y: node.midY), colors[i].color)
                    pill(node, colors[i].color)
                }
                pill(root, .white)
            case .balanced:
                let root = CGRect(x: w / 2 - w * 0.13, y: h / 2 - 6, width: w * 0.26, height: 12)
                for i in 0..<4 {
                    let left = i < 2
                    let y = i % 2 == 0 ? h * 0.25 : h * 0.75
                    let node = CGRect(x: left ? w * 0.05 : w * 0.73, y: y - 5, width: w * 0.22, height: 10)
                    curve(CGPoint(x: left ? root.minX : root.maxX, y: root.midY), CGPoint(x: left ? node.maxX : node.minX, y: node.midY), colors[i].color)
                    pill(node, colors[i].color)
                }
                pill(root, .white)
            case .list:
                let root = CGRect(x: w * 0.12, y: h * 0.14, width: w * 0.24, height: 10)
                pill(root, .white)
                var spine = Path()
                spine.move(to: CGPoint(x: w * 0.18, y: root.maxY))
                spine.addLine(to: CGPoint(x: w * 0.18, y: h * 0.84))
                context.stroke(spine, with: .color(.white.opacity(0.3)), lineWidth: 1)
                for i in 0..<3 {
                    let y = h * 0.4 + CGFloat(i) * h * 0.22
                    context.fill(Path(ellipseIn: CGRect(x: w * 0.18 - 3.5, y: y - 3.5, width: 7, height: 7)), with: .color(colors[i].color))
                    pill(CGRect(x: w * 0.3, y: y - 2.5, width: w * (0.55 - CGFloat(i) * 0.08), height: 5), .white.opacity(0.35))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// A tiny map drawn in a style, palette, line shape and background, for the theme cards.
struct MapThemePreview: View {
    let style: MapStyle
    let palette: MapPalette
    let lines: LineStyle
    let background: CanvasBackground

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: "#111111")))
            switch background {
            case .dots:
                for x in stride(from: 6.0, to: w, by: 10) {
                    for y in stride(from: 6.0, to: h, by: 10) {
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.2, height: 1.2)), with: .color(.white.opacity(0.12)))
                    }
                }
            case .grid:
                var grid = Path()
                for x in stride(from: 0.0, to: w, by: 12) { grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: h)) }
                for y in stride(from: 0.0, to: h, by: 12) { grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: w, y: y)) }
                context.stroke(grid, with: .color(.white.opacity(0.06)), lineWidth: 0.5)
            case .plain:
                break
            }
            let colors = palette.colors.count >= 4 ? Array(palette.colors.prefix(4)) : Array(repeating: palette.colors.first ?? .gray, count: 4)
            let root = CGRect(x: w * 0.08, y: h / 2 - 8, width: w * 0.28, height: 16)
            for i in 0..<4 {
                let color = colors[i].color
                let y = h * 0.16 + CGFloat(i) * h * 0.23
                let node = CGRect(x: w * 0.55, y: y - 6, width: w * 0.36, height: 12)
                var path = Path()
                let a = CGPoint(x: root.maxX, y: root.midY), b = CGPoint(x: node.minX, y: node.midY)
                path.move(to: a)
                switch lines {
                case .curved: path.addCurve(to: b, control1: CGPoint(x: (a.x + b.x) / 2, y: a.y), control2: CGPoint(x: (a.x + b.x) / 2, y: b.y))
                case .straight: path.addLine(to: b)
                case .elbow:
                    path.addLine(to: CGPoint(x: (a.x + b.x) / 2, y: a.y))
                    path.addLine(to: CGPoint(x: (a.x + b.x) / 2, y: b.y))
                    path.addLine(to: b)
                }
                context.stroke(path, with: .color(color.opacity(0.8)), lineWidth: 1.5)
                switch style {
                case .classic:
                    let shape = Path(roundedRect: node, cornerRadius: 4)
                    context.fill(shape, with: .color(color.opacity(0.25)))
                    context.stroke(shape, with: .color(color), lineWidth: 1)
                case .pills:
                    context.fill(Path(roundedRect: node, cornerRadius: node.height / 2), with: .color(color))
                case .outline:
                    context.stroke(Path(roundedRect: node, cornerRadius: node.height / 2), with: .color(color), lineWidth: 1.2)
                case .minimal:
                    var line = Path()
                    line.move(to: CGPoint(x: node.minX, y: node.maxY))
                    line.addLine(to: CGPoint(x: node.maxX, y: node.maxY))
                    context.stroke(line, with: .color(color), lineWidth: 1.2)
                    context.fill(Path(roundedRect: CGRect(x: node.minX + 2, y: node.midY - 1.5, width: node.width * 0.6, height: 3), cornerRadius: 1.5), with: .color(.white.opacity(0.5)))
                }
            }
            context.fill(Path(roundedRect: root, cornerRadius: 5), with: .color(.white))
        }
        .accessibilityHidden(true)
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
