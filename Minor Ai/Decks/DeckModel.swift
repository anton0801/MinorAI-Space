//
//  DeckModel.swift
//  Minor Ai
//
//  A presentation: slides in ready-made layouts (the AI fills them, the app draws them) and a
//  theme. A deck made from a map remembers it, so it can be rebuilt when the map changes.
//

import SwiftUI

enum SlideLayout: String, Codable, CaseIterable, Identifiable {
    case cover, section, bullets, twoColumns, imageText, bigNumber, quote, timeline, table, diagram, closing
    var id: String { rawValue }

    var name: String {
        switch self {
        case .cover: return L("Cover")
        case .section: return L("Section")
        case .bullets: return L("Points")
        case .twoColumns: return L("Two Columns")
        case .imageText: return L("Picture and Text")
        case .bigNumber: return L("Big Number")
        case .quote: return L("Quote")
        case .timeline: return L("Timeline")
        case .table: return L("Table")
        case .diagram: return L("Diagram")
        case .closing: return L("Closing")
        }
    }

    var icon: String {
        switch self {
        case .cover: return "rectangle.inset.filled"
        case .section: return "rectangle.split.1x2"
        case .bullets: return "list.bullet"
        case .twoColumns: return "rectangle.split.2x1"
        case .imageText: return "photo.on.rectangle"
        case .bigNumber: return "number"
        case .quote: return "quote.opening"
        case .timeline: return "timeline.selection"
        case .table: return "tablecells"
        case .diagram: return "circle.hexagongrid"
        case .closing: return "flag.checkered"
        }
    }
}

struct SlideColumn: Codable, Equatable, Hashable {
    var title = ""
    var bullets: [String] = []
}

struct SlideItem: Codable, Equatable, Hashable {
    var title = ""
    var detail = ""
}

struct SlideStat: Codable, Equatable {
    var value = ""
    var label = ""
}

struct SlideQuote: Codable, Equatable {
    var text = ""
    var author = ""
}

struct SlideDiagram: Codable, Equatable {
    var center = ""
    var nodes: [String] = []
}

struct Slide: Identifiable, Codable, Equatable {
    var id = UUID()
    var layout: SlideLayout = .bullets
    var title = ""
    var subtitle = ""
    var bullets: [String] = []
    var columns: [SlideColumn] = []
    var items: [SlideItem] = []
    var stat: SlideStat?
    var quote: SlideQuote?
    var table: [[String]] = []
    var diagram: SlideDiagram?
    var image: NodeImage?
    var imagePrompt: String?
    var notes = ""
    // Design (see DeckDesign.swift).
    var background: SlideBackground?      // nil: the deck's background
    var transition: SlideTransition?      // nil: the deck's transition
    var buildBullets: BuildEffect = .none // the layout's points come in one by one
    var elements: [SlideElement] = []     // free text, shapes, icons, pictures, tables, charts

    init(layout: SlideLayout = .bullets, title: String = "", subtitle: String = "", bullets: [String] = []) {
        self.layout = layout
        self.title = title
        self.subtitle = subtitle
        self.bullets = bullets
    }

    private enum CodingKeys: String, CodingKey {
        case id, layout, title, subtitle, bullets, columns, items, stat, quote, table, diagram, image, imagePrompt, notes
        case background, transition, buildBullets, elements
    }

    // Tolerant: a field added later or an unknown layout never makes a deck unreadable.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        layout = (try? c.decodeIfPresent(SlideLayout.self, forKey: .layout)) ?? .bullets
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        subtitle = (try? c.decodeIfPresent(String.self, forKey: .subtitle)) ?? ""
        bullets = (try? c.decodeIfPresent([String].self, forKey: .bullets)) ?? []
        columns = (try? c.decodeIfPresent([SlideColumn].self, forKey: .columns)) ?? []
        items = (try? c.decodeIfPresent([SlideItem].self, forKey: .items)) ?? []
        stat = try? c.decodeIfPresent(SlideStat.self, forKey: .stat)
        quote = try? c.decodeIfPresent(SlideQuote.self, forKey: .quote)
        table = (try? c.decodeIfPresent([[String]].self, forKey: .table)) ?? []
        diagram = try? c.decodeIfPresent(SlideDiagram.self, forKey: .diagram)
        image = try? c.decodeIfPresent(NodeImage.self, forKey: .image)
        imagePrompt = try? c.decodeIfPresent(String.self, forKey: .imagePrompt)
        notes = (try? c.decodeIfPresent(String.self, forKey: .notes)) ?? ""
        background = try? c.decodeIfPresent(SlideBackground.self, forKey: .background)
        transition = try? c.decodeIfPresent(SlideTransition.self, forKey: .transition)
        buildBullets = (try? c.decodeIfPresent(BuildEffect.self, forKey: .buildBullets)) ?? .none
        elements = (try? c.decodeIfPresent([SlideElement].self, forKey: .elements)) ?? []
    }

    // Every text on the slide, for search, the outline and the AI.
    var plainText: [String] {
        var lines = [title, subtitle].filter { !$0.isEmpty }
        lines += bullets
        for column in columns { lines.append(column.title); lines += column.bullets }
        for item in items { lines.append(item.detail.isEmpty ? item.title : "\(item.title): \(item.detail)") }
        if let stat { lines.append("\(stat.value) — \(stat.label)") }
        if let quote { lines.append("“\(quote.text)” \(quote.author)") }
        lines += table.map { $0.joined(separator: " | ") }
        if let diagram { lines.append("\(diagram.center): \(diagram.nodes.joined(separator: ", "))") }
        lines += elements.flatMap(\.plainText)
        return lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    // The same content in another layout, carried over as well as it fits.
    func converted(to newLayout: SlideLayout) -> Slide {
        var slide = self
        slide.layout = newLayout
        let points = bullets.isEmpty
            ? (columns.flatMap(\.bullets) + items.map(\.title) + (diagram?.nodes ?? []))
            : bullets
        switch newLayout {
        case .bullets, .imageText:
            if slide.bullets.isEmpty { slide.bullets = Array(points.prefix(5)) }
        case .twoColumns:
            if slide.columns.count < 2 {
                let half = (points.count + 1) / 2
                slide.columns = [
                    SlideColumn(title: L("First"), bullets: Array(points.prefix(half))),
                    SlideColumn(title: L("Second"), bullets: Array(points.dropFirst(half))),
                ]
            }
        case .timeline:
            if slide.items.isEmpty { slide.items = points.prefix(6).map { SlideItem(title: $0, detail: "") } }
        case .diagram:
            if slide.diagram == nil { slide.diagram = SlideDiagram(center: title, nodes: Array(points.prefix(6))) }
        case .bigNumber:
            if slide.stat == nil { slide.stat = SlideStat(value: "100%", label: subtitle.isEmpty ? (points.first ?? "") : subtitle) }
        case .quote:
            if slide.quote == nil { slide.quote = SlideQuote(text: points.first ?? title, author: "") }
        case .table:
            if slide.table.isEmpty {
                slide.table = [[title.isEmpty ? L("Item") : title, L("Detail")]] + points.prefix(5).map { [$0, ""] }
            }
        case .cover, .section, .closing:
            if slide.subtitle.isEmpty { slide.subtitle = points.first ?? "" }
        }
        return slide
    }
}

struct Deck: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var slides: [Slide]
    var theme: String?              // DeckTheme raw value
    var sourceMapID: UUID?          // the map it was made from
    var look: DeckLook?             // its own look instead of a ready-made theme
    var brand: DeckBrand?
    var transition: SlideTransition = .fade
    var createdAt = Date()
    var updatedAt = Date()

    init(title: String, slides: [Slide], theme: DeckTheme = .midnight, sourceMapID: UUID? = nil) {
        self.title = title
        self.slides = slides
        self.theme = theme.rawValue
        self.sourceMapID = sourceMapID
    }

    private enum CodingKeys: String, CodingKey { case id, title, slides, theme, sourceMapID, look, brand, transition, createdAt, updatedAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        slides = (try? c.decodeIfPresent([Slide].self, forKey: .slides)) ?? []
        theme = try? c.decodeIfPresent(String.self, forKey: .theme)
        sourceMapID = try? c.decodeIfPresent(UUID.self, forKey: .sourceMapID)
        look = try? c.decodeIfPresent(DeckLook.self, forKey: .look)
        brand = try? c.decodeIfPresent(DeckBrand.self, forKey: .brand)
        transition = (try? c.decodeIfPresent(SlideTransition.self, forKey: .transition)) ?? .fade
        createdAt = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? Date()
        updatedAt = (try? c.decodeIfPresent(Date.self, forKey: .updatedAt)) ?? createdAt
    }

    var deckTheme: DeckTheme { DeckTheme(rawValue: theme ?? "") ?? .midnight }
    // Every picture the deck uses, so none is cleaned up or left out of sync.
    var imageIDs: [UUID] {
        var ids = slides.compactMap(\.image?.id)
        ids += slides.compactMap(\.background?.image)
        ids += slides.flatMap { $0.elements.compactMap(\.image) }
        if let image = look?.background.image { ids.append(image) }
        if let logo = brand?.logo { ids.append(logo) }
        return ids
    }

    // The deck as text, for the chat assistant.
    var outline: String {
        var lines = ["Presentation \"\(title)\": \(slides.count) slides"]
        for (index, slide) in slides.enumerated() {
            lines.append("\(index + 1). [\(slide.layout.rawValue)] " + (slide.plainText.first ?? ""))
            for text in slide.plainText.dropFirst().prefix(8) { lines.append("   - \(text)") }
        }
        return lines.joined(separator: "\n")
    }
}

// How a deck looks. Colors come from the map palettes, so a deck made from a map can match it.
enum DeckTheme: String, CaseIterable, Identifiable {
    case midnight, aurora, paper, ocean, sunset, forest, mono
    var id: String { rawValue }

    var name: String {
        switch self {
        case .midnight: return L("Midnight")
        case .aurora: return L("Aurora")
        case .paper: return L("Paper")
        case .ocean: return L("Ocean")
        case .sunset: return L("Sunset")
        case .forest: return L("Forest")
        case .mono: return L("Mono")
        }
    }

    var isLight: Bool { self == .paper || self == .mono }

    var background: [Color] {
        switch self {
        case .midnight: return [Color(hex: "#121014"), Color(hex: "#19151C")]
        case .aurora: return [Color(hex: "#1B1035"), Color(hex: "#0E2A47")]
        case .paper: return [Color(hex: "#F8F5EF"), Color(hex: "#EFEAE1")]
        case .ocean: return [Color(hex: "#081A2B"), Color(hex: "#0D3350")]
        case .sunset: return [Color(hex: "#2A0E1F"), Color(hex: "#56202A")]
        case .forest: return [Color(hex: "#0C1A13"), Color(hex: "#15301F")]
        case .mono: return [Color(hex: "#FFFFFF"), Color(hex: "#F4F4F5")]
        }
    }

    var text: Color { isLight ? Color(hex: "#18171B") : .white }
    var secondary: Color { isLight ? Color(hex: "#5E5963") : Color.white.opacity(0.72) }
    var card: Color { isLight ? Color.black.opacity(0.05) : Color.white.opacity(0.07) }
    var line: Color { isLight ? Color.black.opacity(0.12) : Color.white.opacity(0.14) }

    var accent: Color {
        switch self {
        case .midnight: return Color(hex: "#2FFF9E")
        case .aurora: return Color(hex: "#FC86C3")
        case .paper: return Color(hex: "#E8553F")
        case .ocean: return Color(hex: "#4FD8D0")
        case .sunset: return Color(hex: "#FFAD5C")
        case .forest: return Color(hex: "#B8F35E")
        case .mono: return Color(hex: "#18171B")
        }
    }

    // Colors for timeline steps, diagram nodes and columns.
    var palette: [Color] {
        let colors: [BranchColor]
        switch self {
        case .midnight: colors = MapPalette.vivid.colors
        case .aurora: colors = [.pink, .lilac, .sky, .teal, .blue, .mint]
        case .paper: colors = [.coral, .orange, .sun, .teal, .blue, .lilac]
        case .ocean: colors = MapPalette.ocean.colors
        case .sunset: colors = MapPalette.sunset.colors
        case .forest: colors = MapPalette.forest.colors
        case .mono: return [Color(hex: "#18171B"), Color(hex: "#55525A"), Color(hex: "#8A8790")]
        }
        return colors.map(\.color)
    }

    // A theme that matches a map's palette.
    static func matching(_ palette: MapPalette) -> DeckTheme {
        switch palette {
        case .vivid, .neon: return .midnight
        case .ocean: return .ocean
        case .sunset: return .sunset
        case .forest: return .forest
        case .mono: return .mono
        }
    }
}

// The JSON the server speaks (see _shared/deck.ts). Missing fields mean "none".
struct APISlide: Codable {
    var layout: String
    var title: String?
    var subtitle: String?
    var bullets: [String]?
    var columns: [SlideColumn]?
    var items: [APIItem]?
    var stat: SlideStat?
    var quote: APIQuote?
    var table: [[String]]?
    var diagram: SlideDiagram?
    var imagePrompt: String?
    var notes: String?

    struct APIItem: Codable { var title: String; var detail: String? }
    struct APIQuote: Codable { var text: String; var author: String? }

    init(_ slide: Slide) {
        layout = slide.layout.rawValue
        title = slide.title.isEmpty ? nil : slide.title
        subtitle = slide.subtitle.isEmpty ? nil : slide.subtitle
        bullets = slide.bullets.isEmpty ? nil : slide.bullets
        columns = slide.columns.isEmpty ? nil : slide.columns
        items = slide.items.isEmpty ? nil : slide.items.map { APIItem(title: $0.title, detail: $0.detail.isEmpty ? nil : $0.detail) }
        stat = slide.stat
        quote = slide.quote.map { APIQuote(text: $0.text, author: $0.author.isEmpty ? nil : $0.author) }
        table = slide.table.isEmpty ? nil : slide.table
        diagram = slide.diagram
        imagePrompt = slide.imagePrompt
        notes = slide.notes.isEmpty ? nil : slide.notes
    }

    func toSlide(keeping old: Slide? = nil) -> Slide {
        var slide = old ?? Slide()
        slide.layout = SlideLayout(rawValue: layout) ?? .bullets
        slide.title = title ?? ""
        slide.subtitle = subtitle ?? ""
        slide.bullets = bullets ?? []
        slide.columns = columns ?? []
        slide.items = (items ?? []).map { SlideItem(title: $0.title, detail: $0.detail ?? "") }
        slide.stat = stat
        slide.quote = quote.map { SlideQuote(text: $0.text, author: $0.author ?? "") }
        slide.table = table ?? []
        slide.diagram = diagram
        if let imagePrompt { slide.imagePrompt = imagePrompt }
        slide.notes = notes ?? ""
        return slide
    }
}

struct APIDeck: Codable {
    var title: String
    var slides: [APISlide]

    init(_ deck: Deck) {
        title = deck.title
        slides = deck.slides.map(APISlide.init)
    }

    // A new deck, or an edited one that keeps the pictures of slides that stayed (same title,
    // or same position with the same layout).
    func toSlides(keeping old: [Slide] = []) -> [Slide] {
        var unused = old
        return slides.enumerated().map { index, item in
            let key = (item.title ?? "").lowercased()
            if !key.isEmpty, let match = unused.firstIndex(where: { $0.title.lowercased() == key }) {
                return item.toSlide(keeping: unused.remove(at: match))
            }
            if old.indices.contains(index), old[index].layout.rawValue == item.layout,
               let match = unused.firstIndex(where: { $0.id == old[index].id }) {
                return item.toSlide(keeping: unused.remove(at: match))
            }
            return item.toSlide()
        }
    }
}
