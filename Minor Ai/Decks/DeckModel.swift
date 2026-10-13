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

struct SlideItem: Codable, Equatable, Hashable, Identifiable {
    var id = UUID()            // stable, so an item can be linked to the idea it comes from
    var title = ""
    var detail = ""

    init(id: UUID = UUID(), title: String = "", detail: String = "") {
        self.id = id
        self.title = title
        self.detail = detail
    }

    private enum CodingKeys: String, CodingKey { case id, title, detail }
    static let legacyNamespace = UUID(uuidString: "5E1D17E0-0000-4000-8000-000000000000")!

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        detail = (try? c.decodeIfPresent(String.self, forKey: .detail)) ?? ""
        // Items saved before ids get one from their words, the same every time they are read.
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? SlideDiagram.stableID(SlideItem.legacyNamespace, "item/\(title)/\(detail)")
    }
}

struct SlideStat: Codable, Equatable {
    var value = ""
    var label = ""
}

struct SlideQuote: Codable, Equatable {
    var text = ""
    var author = ""
}

struct Slide: Identifiable, Codable, Equatable {
    var id = UUID()
    var layout: SlideLayout = .bullets
    var title = ""
    var subtitle = ""
    var bullets: [String] = []
    var bulletIDs: [UUID]?                // stable ids of the bullets, in step with them (see DeckLineage)
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
    var hidden: Bool?                     // skipped when presenting and left out of exports unless asked
    var look: DeckLook?                   // "This slide": its own style instead of the presentation's
    var theme: String?                    // "This slide": a ready-made theme (DeckTheme) instead
    var text: SlideTextStyle?             // this slide's title and text: size, weight, color, alignment

    var isHidden: Bool {
        get { hidden == true }
        set { hidden = newValue ? true : nil }
    }

    init(layout: SlideLayout = .bullets, title: String = "", subtitle: String = "", bullets: [String] = []) {
        self.layout = layout
        self.title = title
        self.subtitle = subtitle
        self.bullets = bullets
    }

    private enum CodingKeys: String, CodingKey {
        case id, layout, title, subtitle, bullets, bulletIDs, columns, items, stat, quote, table, diagram, image, imagePrompt, notes
        case background, transition, buildBullets, elements, hidden, look, theme, text
    }

    // Tolerant: a field added later or an unknown layout never makes a deck unreadable.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        layout = (try? c.decodeIfPresent(SlideLayout.self, forKey: .layout)) ?? .bullets
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        subtitle = (try? c.decodeIfPresent(String.self, forKey: .subtitle)) ?? ""
        bullets = (try? c.decodeIfPresent([String].self, forKey: .bullets)) ?? []
        bulletIDs = try? c.decodeIfPresent([UUID].self, forKey: .bulletIDs)
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
        hidden = (try? c.decodeIfPresent(Bool.self, forKey: .hidden)).flatMap { $0 == true ? true : nil }
        look = try? c.decodeIfPresent(DeckLook.self, forKey: .look)
        theme = (try? c.decodeIfPresent(String.self, forKey: .theme)).flatMap { DeckTheme(rawValue: $0) == nil ? nil : $0 }
        text = (try? c.decodeIfPresent(SlideTextStyle.self, forKey: .text)).flatMap { $0.isDefault ? nil : $0 }
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
        if let diagram {
            // Diagrams of 2.1 by their items; earlier ones by center and nodes.
            if diagram.isStructured {
                lines.append(diagram.allItems.map(\.label).joined(separator: ", "))
            } else {
                lines.append("\(diagram.center): \(diagram.nodes.joined(separator: ", "))")
            }
        }
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
            if slide.bullets.isEmpty { slide.bullets = points }
        case .twoColumns:
            if slide.columns.count < 2 {
                let half = (points.count + 1) / 2
                slide.columns = [
                    SlideColumn(title: L("First"), bullets: Array(points.prefix(half))),
                    SlideColumn(title: L("Second"), bullets: Array(points.dropFirst(half))),
                ]
            }
        case .timeline:
            if slide.items.isEmpty { slide.items = points.map { SlideItem(title: $0, detail: "") } }
        case .diagram:
            if slide.diagram == nil { slide.diagram = SlideDiagram(center: title, nodes: points) }
        case .bigNumber:
            // Only a number the slide already says; never a made-up one.
            if slide.stat == nil {
                let words = [subtitle] + points + [title]
                let found = words.lazy.compactMap { Slide.firstNumber(in: $0) }.first
                slide.stat = SlideStat(value: found ?? "", label: subtitle.isEmpty ? (points.first ?? "") : subtitle)
            }
        case .quote:
            if slide.quote == nil { slide.quote = SlideQuote(text: points.first ?? title, author: "") }
        case .table:
            if slide.table.isEmpty {
                slide.table = [[title.isEmpty ? L("Item") : title, L("Detail")]] + points.map { [$0, ""] }
            }
        case .cover, .section, .closing:
            if slide.subtitle.isEmpty { slide.subtitle = points.first ?? "" }
        }
        return slide
    }

    // A number as written in the text ("42", "27%", "$12.99", "1 000"), or nil.
    static func firstNumber(in text: String) -> String? {
        let pattern = #"[$€£₽]?\d[\d\s.,]*\d%?|[$€£₽]?\d%?"#
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        return String(text[range]).trimmingCharacters(in: .whitespaces)
    }

    // How many of the slide's points its layout can show, and how many it has (nil: all fit).
    var overflow: (shown: Int, total: Int)? {
        let (shown, total): (Int, Int)
        switch layout {
        case .bullets: (shown, total) = (Self.capacity(.bullets), bullets.count)
        case .imageText: (shown, total) = (Self.capacity(.imageText), bullets.count)
        case .timeline: (shown, total) = (Self.capacity(.timeline), items.count)
        case .table: (shown, total) = (Self.capacity(.table), max(table.count - 1, 0))
        case .twoColumns: (shown, total) = (Self.capacity(.twoColumns), columns.count)
        default: return nil
        }
        return total > shown ? (shown, total) : nil
    }

    // Points a layout draws (table: rows under the header; two columns: columns).
    static func capacity(_ layout: SlideLayout) -> Int {
        switch layout {
        case .bullets, .imageText: return 6
        case .timeline, .diagram: return 6
        case .table: return 5
        case .twoColumns: return 3
        default: return .max
        }
    }

    // The slide with what fits, and the rest on as many new slides of the same layout as needed.
    func split() -> [Slide] {
        guard let overflow else { return [self] }
        let size = overflow.shown
        func copy(_ index: Int) -> Slide {
            var slide = self
            if index > 0 {
                slide.id = UUID()
                slide.elements = []
                slide.notes = ""
                slide.image = nil
            }
            return slide
        }
        var result: [Slide] = []
        switch layout {
        case .bullets, .imageText:
            let keys = bulletKeys.chunked(size)
            for (i, chunk) in bullets.chunked(size).enumerated() { var s = copy(i); s.bullets = chunk; s.bulletIDs = keys[i]; result.append(s) }
        case .timeline:
            for (i, chunk) in items.chunked(size).enumerated() { var s = copy(i); s.items = chunk; result.append(s) }
        case .table:
            let header = table.first ?? []
            for (i, chunk) in Array(table.dropFirst()).chunked(size).enumerated() { var s = copy(i); s.table = [header] + chunk; result.append(s) }
        case .twoColumns:
            for (i, chunk) in columns.chunked(size).enumerated() { var s = copy(i); s.columns = chunk; result.append(s) }
        default:
            return [self]
        }
        return result
    }
}

extension Array {
    // Consecutive pieces of at most `size` elements.
    func chunked(_ size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

// How a slide's own title and other text are drawn, on top of the style: bigger or smaller, bold
// or not, italic, another color, and where the title sits. Kept by role (the title, everything
// else), so the text stays the slide's title and points for AI and export.
struct SlideTextStyle: Codable, Equatable {
    enum Align: String, Codable, CaseIterable { case leading, center, trailing }

    struct Part: Codable, Equatable {
        var scale: Double = 1     // 0.6…1.6 of the layout's size
        var bold: Bool?           // nil: the layout's own weight
        var italic = false
        var color: String?        // hex; nil: the style's color
        var align: Align?         // titles only; nil: where the layout puts it

        var isDefault: Bool { self == Part() }
        static let scales: ClosedRange<Double> = 0.6...1.6

        private enum CodingKeys: String, CodingKey { case scale, bold, italic, color, align }

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            scale = min(max((try? c.decodeIfPresent(Double.self, forKey: .scale)) ?? 1, Self.scales.lowerBound), Self.scales.upperBound)
            bold = try? c.decodeIfPresent(Bool.self, forKey: .bold)
            italic = (try? c.decodeIfPresent(Bool.self, forKey: .italic)) ?? false
            color = try? c.decodeIfPresent(String.self, forKey: .color)
            align = try? c.decodeIfPresent(Align.self, forKey: .align)
        }
    }

    var title = Part()
    var body = Part()

    var isDefault: Bool { title.isDefault && body.isDefault }

    private enum CodingKeys: String, CodingKey { case title, body }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = (try? c.decodeIfPresent(Part.self, forKey: .title)) ?? Part()
        body = (try? c.decodeIfPresent(Part.self, forKey: .body)) ?? Part()
    }
}

struct Deck: Identifiable, Codable, Equatable {
    var id = UUID()
    var lineage: DeckLineage?       // which slides, titles and bullets come from which ideas of the map
    var title: String
    var slides: [Slide]
    var theme: String?              // DeckTheme raw value
    var sourceMapID: UUID?          // the map it was made from
    var sourceNodeID: UUID?         // the branch it was made from (nil: the whole map)
    var sourceRevision: String?     // the map's content fingerprint when made or last updated from it
    var look: DeckLook?             // its own look instead of a ready-made theme
    var brand: DeckBrand?
    var transition: SlideTransition = .fade
    var isPinned = false            // kept on top of the Library's Slides
    var createdAt = Date()
    var updatedAt = Date()

    init(title: String, slides: [Slide], theme: DeckTheme = .midnight, sourceMapID: UUID? = nil) {
        self.title = title
        self.slides = slides
        self.theme = theme.rawValue
        self.sourceMapID = sourceMapID
    }

    private enum CodingKeys: String, CodingKey { case id, title, slides, theme, sourceMapID, sourceNodeID, sourceRevision, look, brand, transition, isPinned, createdAt, updatedAt, lineage }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        slides = (try? c.decodeIfPresent([Slide].self, forKey: .slides)) ?? []
        theme = try? c.decodeIfPresent(String.self, forKey: .theme)
        sourceMapID = try? c.decodeIfPresent(UUID.self, forKey: .sourceMapID)
        sourceNodeID = try? c.decodeIfPresent(UUID.self, forKey: .sourceNodeID)
        sourceRevision = try? c.decodeIfPresent(String.self, forKey: .sourceRevision)
        look = try? c.decodeIfPresent(DeckLook.self, forKey: .look)
        brand = try? c.decodeIfPresent(DeckBrand.self, forKey: .brand)
        transition = (try? c.decodeIfPresent(SlideTransition.self, forKey: .transition)) ?? .fade
        isPinned = (try? c.decodeIfPresent(Bool.self, forKey: .isPinned)) ?? false
        lineage = try? c.decodeIfPresent(DeckLineage.self, forKey: .lineage)
        createdAt = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? Date()
        updatedAt = (try? c.decodeIfPresent(Date.self, forKey: .updatedAt)) ?? createdAt
    }

    var deckTheme: DeckTheme { DeckTheme(rawValue: theme ?? "") ?? .midnight }

    // Presenting and exporting leave hidden slides out (export can include them when asked).
    func withoutHidden() -> Deck {
        var copy = self
        copy.slides = slides.filter { !$0.isHidden }
        return copy
    }

    // Where slide `index` lands among the shown slides: itself, or the next shown one after a hidden one.
    func shownIndex(for index: Int) -> Int {
        let shown = slides.indices.filter { !slides[$0].isHidden }
        guard !shown.isEmpty else { return 0 }
        return shown.firstIndex { $0 >= index } ?? shown.count - 1
    }
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
    var src: String?            // in replies: the map idea the slide is about
    var bulletSrc: [String]?    // the idea each bullet comes from ("" for none)

    struct APIItem: Codable { var title: String; var detail: String?; var src: String? }
    struct APIQuote: Codable { var text: String; var author: String? }

    init(_ slide: Slide) {
        layout = slide.layout.rawValue
        title = slide.title.isEmpty ? nil : slide.title
        subtitle = slide.subtitle.isEmpty ? nil : slide.subtitle
        bullets = slide.bullets.isEmpty ? nil : slide.bullets
        columns = slide.columns.isEmpty ? nil : slide.columns
        items = slide.items.isEmpty ? nil : slide.items.map { APIItem(title: $0.title, detail: $0.detail.isEmpty ? nil : $0.detail, src: nil) }
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
        // A diagram edited as data keeps its steps and connections; the AI rewrites words, not them.
        if old?.diagram?.isStructured != true { slide.diagram = diagram }
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
