//
//  DesignTokens.swift
//  Minor Ai
//
//  Theme-independent tokens from the Minor design system (DesignSystem/DESIGN.md).
//  Theme-dependent colors stay in AppTheme.
//

import SwiftUI

extension AppTheme {
    // glow-solid: the sphere glow at full strength, for AI states on the map.
    var glowSolid: Color {
        switch sphere {
        case 2: return Color(hex: "#E1BEFF")
        case 3: return Color(hex: "#BEFFF7")
        case 4, 5: return Color(hex: "#FC86C3")
        case 6: return Color(hex: "#FC9886")
        default: return Color(hex: "#BBFFDF")
        }
    }
}

enum MinorColor {
    static let textPrimary = Color.white
    static let textSecondary = Color(hex: "#A3A3A3")
    static let textTertiary = Color(hex: "#969696")
    static let textChevron = Color(hex: "#AAAAAA")
    static let textSignature = Color(hex: "#BBBBBB")
    static let sheet = Color(hex: "#232323")
    static let row = Color(hex: "#323232")
    static let track = Color(hex: "#1C1C1C")
    static let divider = Color(hex: "#6A6A6A")
    static let closeFill = Color(hex: "#505050")
    static let fillRow = Color.white.opacity(0.08)
    static let fillThumb = Color.white.opacity(0.2)
    static let sendFill = Color.white.opacity(0.9)
    static let sweep = Color.white.opacity(0.3)
    static let haze = Color.white.opacity(0.2)
    static let accent = Color(hex: "#2FFF9E")
    static let premium = Color(hex: "#3B7161")
    static let pro = Color(hex: "#FFD60A")
    static let danger = Color(hex: "#FF453A")
    // Red text on the dark sheets with enough contrast (4.5:1) for small sizes.
    static let dangerText = Color(hex: "#FF6961")
    static let canvasDot = Color.white.opacity(0.06)
}

enum BranchColor: Int, CaseIterable, Codable {
    case mint, sky, lilac, pink, sun, coral
    case teal, blue, orange, red, lime, gray

    var color: Color {
        switch self {
        case .mint: return Color(hex: "#5EF0B0")
        case .sky: return Color(hex: "#7CC4FF")
        case .lilac: return Color(hex: "#C9A2FF")
        case .pink: return Color(hex: "#FC86C3")
        case .sun: return Color(hex: "#FFD66B")
        case .coral: return Color(hex: "#FC9886")
        case .teal: return Color(hex: "#4FD8D0")
        case .blue: return Color(hex: "#7F96FF")
        case .orange: return Color(hex: "#FFAD5C")
        case .red: return Color(hex: "#FF7070")
        case .lime: return Color(hex: "#B8F35E")
        case .gray: return Color(hex: "#C3C7D1")
        }
    }

    var tint: Color { color.opacity(0.18) }   // branch-*-tint
    var line: Color { color.opacity(0.6) }    // branch-*-line

    var name: String {
        switch self {
        case .mint: return L("Mint")
        case .sky: return L("Sky")
        case .lilac: return L("Lilac")
        case .pink: return L("Pink")
        case .sun: return L("Sun")
        case .coral: return L("Coral")
        case .teal: return L("Teal")
        case .blue: return L("Blue")
        case .orange: return L("Orange")
        case .red: return L("Red")
        case .lime: return L("Lime")
        case .gray: return L("Gray")
        }
    }

    // Branches take the palette's colors in order and wrap around.
    static func forBranch(at index: Int, palette: MapPalette = .vivid) -> BranchColor {
        let colors = palette.colors
        return colors[((index % colors.count) + colors.count) % colors.count]
    }
}

// The colors a map's branches take in order (Map Design → Palette).
enum MapPalette: String, CaseIterable, Identifiable {
    case vivid, ocean, sunset, forest, neon, mono
    var id: String { rawValue }

    var colors: [BranchColor] {
        switch self {
        case .vivid: return [.mint, .sky, .lilac, .pink, .sun, .coral]
        case .ocean: return [.sky, .teal, .blue, .mint, .lilac, .gray]
        case .sunset: return [.coral, .orange, .sun, .pink, .red, .lilac]
        case .forest: return [.lime, .mint, .teal, .sun, .orange, .sky]
        case .neon: return [.lime, .pink, .sky, .orange, .lilac, .sun]
        case .mono: return [.gray]
        }
    }

    var name: String {
        switch self {
        case .vivid: return L("Vivid")
        case .ocean: return L("Ocean")
        case .sunset: return L("Sunset")
        case .forest: return L("Forest")
        case .neon: return L("Neon")
        case .mono: return L("Mono")
        }
    }
}

enum MapMetrics {
    static let gridPitch: CGFloat = 24
    static let levelGap: CGFloat = 56
    static let siblingGap: CGFloat = 12
    static let subtreeGap: CGFloat = 24
    static let connector1: CGFloat = 2
    static let connector2: CGFloat = 1.5
    static let nodeMaxWidth: CGFloat = 240
    static let rootMaxWidth: CGFloat = 280
    static let nodeMinHeight: CGFloat = 40
    static let leafMinHeight: CGFloat = 30
    static let zoomRange: ClosedRange<CGFloat> = 0.25...3
    static let lodThreshold: CGFloat = 0.5
}

extension Animation {
    // Springs named in the design system's motion section.
    static let minorStandard = Animation.spring(response: 0.6, dampingFraction: 0.7)
    static let minorSheet = Animation.spring(response: 0.6, dampingFraction: 0.8)
    static let minorMenu = Animation.spring(response: 0.4, dampingFraction: 0.8)
    static let minorNode = Animation.spring(response: 0.5, dampingFraction: 0.7)
    static let minorFit = Animation.spring(response: 0.6, dampingFraction: 0.9)
}

// Rounded surface with the 1pt theme stroke used everywhere in Minor.
struct MinorSurface: ViewModifier {
    let fill: Color
    let stroke: Color
    var radius: CGFloat = 16

    func body(content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: radius)
                .fill(fill)
                .overlay(RoundedRectangle(cornerRadius: radius).stroke(stroke, lineWidth: 1))
        )
    }
}

extension View {
    func minorSurface(_ theme: AppTheme, radius: CGFloat = 16) -> some View {
        modifier(MinorSurface(fill: theme.chatRectangle, stroke: theme.chatStroke, radius: radius))
    }
}

enum Haptics {
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) { UIImpactFeedbackGenerator(style: style).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}

// Design-system sizes that still follow Dynamic Type: 17 pt at the default setting, larger when the
// person asks for larger text, capped so fixed layouts don't break.
struct MinorFont: ViewModifier {
    let size: CGFloat
    var weight: Font.Weight = .regular
    var style: UIFont.TextStyle = .body
    var maxScale: CGFloat = 1.5

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        let traits = UITraitCollection(preferredContentSizeCategory: Self.category(dynamicTypeSize))
        let scaled = UIFontMetrics(forTextStyle: style).scaledValue(for: size, compatibleWith: traits)
        return content.font(.system(size: min(scaled, size * maxScale), weight: weight))
    }

    static func category(_ size: DynamicTypeSize) -> UIContentSizeCategory {
        switch size {
        case .xSmall: return .extraSmall
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .xLarge: return .extraLarge
        case .xxLarge: return .extraExtraLarge
        case .xxxLarge: return .extraExtraExtraLarge
        case .accessibility1: return .accessibilityMedium
        case .accessibility2: return .accessibilityLarge
        case .accessibility3: return .accessibilityExtraLarge
        case .accessibility4: return .accessibilityExtraExtraLarge
        case .accessibility5: return .accessibilityExtraExtraExtraLarge
        @unknown default: return .large
        }
    }
}

extension View {
    func minorFont(_ size: CGFloat, _ weight: Font.Weight = .regular, style: UIFont.TextStyle = .body, maxScale: CGFloat = 1.5) -> some View {
        modifier(MinorFont(size: size, weight: weight, style: style, maxScale: maxScale))
    }
}
