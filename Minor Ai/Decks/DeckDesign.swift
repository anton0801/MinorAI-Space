//
//  DeckDesign.swift
//  Minor Ai
//
//  How a presentation can look beyond the ready-made themes: a deck's own look (background,
//  colors, fonts), a brand (logo and footer), a background per slide, transitions, things that
//  appear one by one, and free elements placed anywhere on a slide.
//

import SwiftUI
import UIKit

// MARK: - Fonts

enum DeckFont: String, Codable, CaseIterable, Identifiable {
    case system, rounded, serif, mono, avenir, futura, georgia, didot
    var id: String { rawValue }

    var name: String {
        switch self {
        case .system: return "SF Pro"
        case .rounded: return "SF Rounded"
        case .serif: return "New York"
        case .mono: return "SF Mono"
        case .avenir: return "Avenir Next"
        case .futura: return "Futura"
        case .georgia: return "Georgia"
        case .didot: return "Didot"
        }
    }

    func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        switch self {
        case .system: return .system(size: size, weight: weight)
        case .rounded: return .system(size: size, weight: weight, design: .rounded)
        case .serif: return .system(size: size, weight: weight, design: .serif)
        case .mono: return .system(size: size, weight: weight, design: .monospaced)
        case .avenir: return .custom("Avenir Next", size: size).weight(weight)
        case .futura: return .custom("Futura", size: size).weight(weight)
        case .georgia: return .custom("Georgia", size: size).weight(weight)
        case .didot: return .custom("Didot", size: size).weight(weight)
        }
    }

    // The closest font PowerPoint and Keynote have.
    var officeName: String {
        switch self {
        case .system: return "Helvetica Neue"
        case .rounded: return "Arial Rounded MT Bold"
        case .serif, .georgia: return "Georgia"
        case .mono: return "Courier New"
        case .avenir: return "Avenir Next"
        case .futura: return "Futura"
        case .didot: return "Didot"
        }
    }
}

// MARK: - Backgrounds

struct SlideBackground: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable { case solid, gradient, image }
    var kind: Kind = .gradient
    var colors: [String] = ["#121014", "#19151C"]   // hex, first is used for solid
    var angle: Double = 135                          // degrees, for gradients
    var image: UUID?
    var dim: Double = 0.35                           // darkening over a photo, 0…0.8

    var first: Color { Color(hex: colors.first ?? "#121014") }
    var last: Color { Color(hex: colors.last ?? colors.first ?? "#121014") }

    // Light or dark, to choose readable text.
    var isLight: Bool {
        // Photos get darkened, so text on them is light.
        kind == .image ? false : Self.luminance(colors.first ?? "#000000") > 0.6
    }

    static func luminance(_ hex: String) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(Color(hex: hex)).getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)
    }

    // Start and end of a gradient at `angle` (0° = left to right, 90° = top to bottom).
    var points: (UnitPoint, UnitPoint) {
        let radians = angle * .pi / 180
        let dx = cos(radians) / 2, dy = sin(radians) / 2
        return (UnitPoint(x: 0.5 - dx, y: 0.5 - dy), UnitPoint(x: 0.5 + dx, y: 0.5 + dy))
    }
}

// MARK: - A deck's own look

struct DeckLook: Codable, Equatable, Identifiable {
    var id = UUID()
    var name = ""
    var background = SlideBackground()
    var accent = "#2FFF9E"
    var palette: [String] = ["#2FFF9E", "#C9A2FF", "#7CC4FF", "#FC86C3", "#FFD66B", "#FC9886"]
    var titleFont: DeckFont = .system
    var bodyFont: DeckFont = .system
    var glow = true
    var textColor: String?              // nil: chosen from the background

    private enum CodingKeys: String, CodingKey { case id, name, background, accent, palette, titleFont, bodyFont, glow, textColor }

    init(name: String = "", background: SlideBackground = SlideBackground(), accent: String = "#2FFF9E",
         palette: [String]? = nil, titleFont: DeckFont = .system, bodyFont: DeckFont = .system, glow: Bool = true) {
        self.name = name
        self.background = background
        self.accent = accent
        self.palette = palette ?? DeckLook.palette(from: accent)
        self.titleFont = titleFont
        self.bodyFont = bodyFont
        self.glow = glow
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        background = (try? c.decodeIfPresent(SlideBackground.self, forKey: .background)) ?? SlideBackground()
        accent = (try? c.decodeIfPresent(String.self, forKey: .accent)) ?? "#2FFF9E"
        palette = (try? c.decodeIfPresent([String].self, forKey: .palette)) ?? DeckLook.palette(from: accent)
        if palette.isEmpty { palette = DeckLook.palette(from: accent) }
        titleFont = (try? c.decodeIfPresent(DeckFont.self, forKey: .titleFont)) ?? .system
        bodyFont = (try? c.decodeIfPresent(DeckFont.self, forKey: .bodyFont)) ?? .system
        glow = (try? c.decodeIfPresent(Bool.self, forKey: .glow)) ?? true
        textColor = try? c.decodeIfPresent(String.self, forKey: .textColor)
    }

    // Six colors that go with an accent: the accent and its neighbours around the color wheel.
    static func palette(from accent: String) -> [String] {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(Color(hex: accent)).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return [accent.uppercased()] + [0.12, 0.5, 0.62, 0.8, 0.3].map { shift in
            UIColor(hue: (h + shift).truncatingRemainder(dividingBy: 1), saturation: max(s, 0.45), brightness: max(b, 0.75), alpha: 1).hexString
        }
    }

    // Starting from a ready-made theme.
    init(theme: DeckTheme) {
        self.init(
            name: theme.name,
            background: SlideBackground(kind: .gradient, colors: theme.background.map { UIColor($0).hexString }, angle: 45),
            accent: UIColor(theme.accent).hexString,
            palette: theme.palette.map { UIColor($0).hexString }
        )
        textColor = nil
    }
}

// MARK: - Brand

struct DeckBrand: Codable, Equatable {
    enum Corner: String, Codable, CaseIterable { case topLeft, topRight, bottomLeft, bottomRight }
    var logo: UUID?
    var corner: Corner = .topRight
    var size: Double = 64                 // logo height on the 1280×720 slide
    var onCover = true
    var footer = ""                       // instead of the deck title in the footer
    var showNumbers = true
}

// MARK: - Motion

enum SlideTransition: String, Codable, CaseIterable, Identifiable {
    case none, fade, push, zoom, wipe
    var id: String { rawValue }

    var name: String {
        switch self {
        case .none: return L("None")
        case .fade: return L("Fade")
        case .push: return L("Push")
        case .zoom: return L("Zoom")
        case .wipe: return L("Wipe")
        }
    }

    var swiftUI: AnyTransition {
        switch self {
        case .none: return .identity
        case .fade: return .opacity
        case .push: return .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
        case .zoom: return .scale(scale: 0.85).combined(with: .opacity)
        case .wipe: return .asymmetric(insertion: .push(from: .trailing), removal: .opacity)
        }
    }
}

// How a bullet or an element comes in when it is its turn.
enum BuildEffect: String, Codable, CaseIterable, Identifiable {
    case none, fade, rise, fly, zoom
    var id: String { rawValue }

    var name: String {
        switch self {
        case .none: return L("Always Shown")
        case .fade: return L("Fade In")
        case .rise: return L("Rise")
        case .fly: return L("Fly In")
        case .zoom: return L("Zoom In")
        }
    }

    var icon: String {
        switch self {
        case .none: return "eye"
        case .fade: return "circle.lefthalf.filled"
        case .rise: return "arrow.up.circle"
        case .fly: return "arrow.up.right.circle"
        case .zoom: return "plus.magnifyingglass"
        }
    }
}

// Hides a bullet or an element until its turn, then brings it in with its effect.
struct Reveal: ViewModifier {
    let effect: BuildEffect
    let shown: Bool

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : (effect == .rise ? 40 : (effect == .fly ? 260 : 0)))
            .scaleEffect(shown || effect != .zoom ? 1 : 0.6)
            .animation(.spring(response: 0.55, dampingFraction: 0.85), value: shown)
    }
}

// MARK: - Free elements

struct ChartSpec: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable { case bar, line, pie, donut }
    var kind: Kind = .bar
    var title = ""
    var labels: [String] = []
    var values: [Double] = []
    var showValues = true

    init(kind: Kind = .bar, title: String = "", labels: [String] = [], values: [Double] = [], showValues: Bool = true) {
        self.kind = kind
        self.title = title
        self.labels = labels
        self.values = values
        self.showValues = showValues
    }

    private enum CodingKeys: String, CodingKey { case kind, title, labels, values, showValues }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = (try? c.decodeIfPresent(Kind.self, forKey: .kind)) ?? .bar
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        labels = (try? c.decodeIfPresent([String].self, forKey: .labels)) ?? []
        values = (try? c.decodeIfPresent([Double].self, forKey: .values)) ?? []
        showValues = (try? c.decodeIfPresent(Bool.self, forKey: .showValues)) ?? true
    }
}

struct SlideElement: Codable, Equatable, Identifiable {
    enum Kind: String, Codable, CaseIterable { case text, shape, icon, image, table, chart, qr }
    enum Shape: String, Codable, CaseIterable { case rect, roundRect, ellipse, triangle, diamond, arrow, star, line, hexagon }
    enum Align: String, Codable { case leading, center, trailing }

    var id = UUID()
    var kind: Kind
    // Position on the 1280×720 slide.
    var x: Double = 440
    var y: Double = 260
    var w: Double = 400
    var h: Double = 200
    var rotation: Double = 0
    var opacity: Double = 1

    // Text (text, and text inside shapes).
    var text = ""
    var fontSize: Double = 40
    var bold = false
    var italic = false
    var align: Align = .leading
    var titleFont = false                 // use the deck's title font
    var color: String?                    // nil: the theme's text color

    // Shapes and icons.
    var shape: Shape = .roundRect
    var fill: String?                     // nil: the theme's accent
    var fillOpacity: Double = 1
    var stroke: String?
    var strokeWidth: Double = 0
    var symbol = "star.fill"

    // Content.
    var image: UUID?
    var rows: [[String]] = []
    var chart: ChartSpec?
    var link = ""                         // QR codes

    var build: BuildEffect = .none

    init(kind: Kind) { self.kind = kind }

    private enum CodingKeys: String, CodingKey {
        case id, kind, x, y, w, h, rotation, opacity, text, fontSize, bold, italic, align, titleFont, color
        case shape, fill, fillOpacity, stroke, strokeWidth, symbol, image, rows, chart, link, build
    }

    // Tolerant like slides: unknown or missing fields never make a deck unreadable.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T { ((try? c.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback }
        id = v(.id, UUID())
        kind = v(.kind, .text)
        x = v(.x, 440); y = v(.y, 260); w = v(.w, 400); h = v(.h, 200)
        rotation = v(.rotation, 0); opacity = v(.opacity, 1)
        text = v(.text, ""); fontSize = v(.fontSize, 40); bold = v(.bold, false); italic = v(.italic, false)
        align = v(.align, .leading); titleFont = v(.titleFont, false)
        color = try? c.decodeIfPresent(String.self, forKey: .color)
        shape = v(.shape, .roundRect)
        fill = try? c.decodeIfPresent(String.self, forKey: .fill)
        fillOpacity = v(.fillOpacity, 1)
        stroke = try? c.decodeIfPresent(String.self, forKey: .stroke)
        strokeWidth = v(.strokeWidth, 0); symbol = v(.symbol, "star.fill")
        image = try? c.decodeIfPresent(UUID.self, forKey: .image)
        rows = v(.rows, []); chart = try? c.decodeIfPresent(ChartSpec.self, forKey: .chart)
        link = v(.link, ""); build = v(.build, .none)
    }

    var frame: CGRect { CGRect(x: x, y: y, width: w, height: h) }

    // Kinds that keep their proportions when resized.
    var keepsAspect: Bool { kind == .icon || kind == .qr }

    var plainText: [String] {
        switch kind {
        case .text, .shape: return [text]
        case .table: return rows.map { $0.joined(separator: " | ") }
        case .chart: return [chart?.title ?? ""] + zip(chart?.labels ?? [], chart?.values ?? []).map { "\($0): \(ChartView.format($1))" }
        case .qr: return [link]
        default: return []
        }
    }

    // A new element of a kind, sized and filled sensibly, in the middle of the slide.
    static func new(_ kind: Kind) -> SlideElement {
        var e = SlideElement(kind: kind)
        switch kind {
        case .text:
            e.text = L("Your text"); e.w = 560; e.h = 90; e.fontSize = 44; e.bold = true
        case .shape:
            e.w = 360; e.h = 220; e.shape = .roundRect
        case .icon:
            e.w = 160; e.h = 160; e.symbol = "sparkles"
        case .image:
            e.w = 480; e.h = 320
        case .table:
            e.w = 760; e.h = 300
            e.rows = [[L("Item"), L("Value")], ["A", "10"], ["B", "20"]]
        case .chart:
            e.w = 720; e.h = 420
            e.chart = ChartSpec(kind: .bar, title: L("Chart"), labels: ["Q1", "Q2", "Q3", "Q4"], values: [12, 18, 15, 26])
        case .qr:
            e.w = 220; e.h = 220; e.link = "https://minorai.site"
        }
        e.x = (1280 - e.w) / 2
        e.y = (720 - e.h) / 2
        return e
    }
}

// MARK: - The look a slide is drawn with

struct SlideStyle {
    var background: SlideBackground
    var text: Color
    var secondary: Color
    var card: Color
    var line: Color
    var accent: Color
    var palette: [Color]
    var isLight: Bool
    var titleFont: DeckFont
    var bodyFont: DeckFont
    var glow: Bool
    var onAccent: Color                   // text on an accent-filled shape

    init(look: DeckLook) {
        background = look.background
        let light = look.textColor.map { SlideBackground.luminance($0) < 0.5 } ?? look.background.isLight
        isLight = light
        text = look.textColor.map { Color(hex: $0) } ?? (light ? Color(hex: "#18171B") : .white)
        secondary = light ? Color(hex: "#5E5963") : Color.white.opacity(0.72)
        card = light ? Color.black.opacity(0.05) : Color.white.opacity(0.07)
        line = light ? Color.black.opacity(0.12) : Color.white.opacity(0.14)
        accent = Color(hex: look.accent)
        palette = (look.palette.isEmpty ? DeckLook.palette(from: look.accent) : look.palette).map { Color(hex: $0) }
        titleFont = look.titleFont
        bodyFont = look.bodyFont
        glow = look.glow
        onAccent = SlideBackground.luminance(look.accent) > 0.55 ? .black : .white
    }

    init(theme: DeckTheme) {
        var look = DeckLook(theme: theme)
        look.background.angle = 45
        self.init(look: look)
        // The ready-made themes keep their exact colors.
        text = theme.text
        secondary = theme.secondary
        card = theme.card
        line = theme.line
        accent = theme.accent
        palette = theme.palette
        isLight = theme.isLight
        onAccent = theme.isLight && theme != .mono ? .white : .black
    }

    func title(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font { titleFont.font(size, weight) }
    func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { bodyFont.font(size, weight) }

    func with(background override: SlideBackground?) -> SlideStyle {
        guard let override else { return self }
        var copy = self
        copy.background = override
        // A photo or a background of the other brightness changes which text reads well.
        let light = override.kind != .image && override.isLight
        if light != isLight {
            copy.isLight = light
            copy.text = light ? Color(hex: "#18171B") : .white
            copy.secondary = light ? Color(hex: "#5E5963") : Color.white.opacity(0.72)
            copy.card = light ? Color.black.opacity(0.05) : Color.white.opacity(0.07)
            copy.line = light ? Color.black.opacity(0.12) : Color.white.opacity(0.14)
        }
        return copy
    }
}

extension Deck {
    // The look slides are drawn with: the deck's own, or its ready-made theme.
    var style: SlideStyle { look.map(SlideStyle.init(look:)) ?? SlideStyle(theme: deckTheme) }

    func style(for slide: Slide) -> SlideStyle { style.with(background: slide.background) }

    // How many taps a slide takes before the next one: bullets and elements that come in one by one.
    static func buildSteps(_ slide: Slide) -> Int {
        slide.buildUnits + slide.elements.filter { $0.build != .none }.count
    }
}

extension Slide {
    // The parts of the layout that can come in one by one.
    var buildUnits: Int {
        guard buildBullets != .none else { return 0 }
        switch layout {
        case .bullets, .imageText: return bullets.count
        case .twoColumns: return min(columns.count, 3)
        case .timeline: return min(items.count, 6)
        case .diagram: return min(diagram?.nodes.count ?? 0, 6)
        case .table: return max(min(table.count, 6) - 1, 0)
        default: return 0
        }
    }
}

extension UIColor {
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(max(0, min(1, r)) * 255), Int(max(0, min(1, g)) * 255), Int(max(0, min(1, b)) * 255))
    }
}
