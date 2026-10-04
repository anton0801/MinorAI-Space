//
//  DeckStore.swift
//  Minor Ai
//
//  Presentations as JSON files in Application Support/Decks. Pictures share the maps' image
//  folder (MapStore), so a picture can move between a map and a deck.
//

import Foundation
import UIKit

@MainActor
final class DeckStore: ObservableObject {
    static let shared = DeckStore()

    @Published private(set) var decks: [Deck] = []

    private let folder: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let io = DispatchQueue(label: "com.minorailifegroup.MinorAI.decks", qos: .utility)

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        folder = base.appendingPathComponent("Decks", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        load()
    }

    func deck(_ id: UUID) -> Deck? { decks.first { $0.id == id } }

    var imageIDs: Set<UUID> { Set(decks.flatMap(\.imageIDs)) }

    func save(_ deck: Deck) {
        var deck = deck
        deck.updatedAt = Date()
        if let index = decks.firstIndex(where: { $0.id == deck.id }) {
            decks[index] = deck
        } else {
            decks.append(deck)
        }
        sort()
        write(deck)
    }

    @discardableResult
    func update(_ id: UUID, _ change: (inout Deck) -> Void) -> Deck? {
        guard let index = decks.firstIndex(where: { $0.id == id }) else { return nil }
        var deck = decks[index]
        change(&deck)
        deck.updatedAt = Date()
        decks[index] = deck
        sort()
        write(deck)
        return deck
    }

    func delete(_ id: UUID) {
        guard decks.contains(where: { $0.id == id }) else { return }
        MapSync.shared.noteDeleted(id)
        decks.removeAll { $0.id == id }
        let url = file(for: id)
        io.async { try? FileManager.default.removeItem(at: url) }
    }

    func deleteAll() {
        decks = []
        let folder = folder
        io.async {
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for file in files { try? FileManager.default.removeItem(at: file) }
        }
    }

    // MARK: - Sync

    func applySynced(_ deck: Deck) {
        if let index = decks.firstIndex(where: { $0.id == deck.id }) {
            decks[index] = deck
        } else {
            decks.append(deck)
        }
        sort()
        write(deck)
    }

    func removeSynced(_ id: UUID) {
        guard decks.contains(where: { $0.id == id }) else { return }
        decks.removeAll { $0.id == id }
        let url = file(for: id)
        io.async { try? FileManager.default.removeItem(at: url) }
    }

    nonisolated func flush() { io.sync {} }

    private func write(_ deck: Deck) {
        guard let data = try? encoder.encode(deck) else { return }
        let url = file(for: deck.id)
        io.async { try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
    }

    private func load() {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        decks = files.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            if let deck = try? decoder.decode(Deck.self, from: data) { return deck }
            // Set aside, not skipped: the next launch's picture cleanup would otherwise delete its
            // pictures, and a later version of the app may read it.
            try? FileManager.default.moveItem(at: url, to: url.deletingPathExtension().appendingPathExtension("unreadable"))
            return nil
        }
        sort()
    }

    private func sort() { decks.sort { $0.updatedAt > $1.updatedAt } }

    private func file(for id: UUID) -> URL { folder.appendingPathComponent("\(id.uuidString).json") }
}

// AI work on presentations, served by the `ai` edge function.
final class DeckService {
    static let shared = DeckService()

    enum Source {
        case map(MindMap)
        case topic(String)
        case text(String)
    }

    struct Generated {
        let title: String
        let slides: [Slide]
    }

    // `layouts`: a template's slides in order, for the AI to fill instead of choosing its own.
    func generate(_ source: Source, slides: Int, audience: String = "", quality: String? = nil, layouts: [SlideLayout]? = nil) async throws -> Generated {
        struct SourceBody: Encodable { let kind: String; let value: String?; let map: APINode? }
        struct Body: Encodable { let action = "deck"; let source: SourceBody; let slides: Int; let audience: String?; let quality: String?; let layouts: [String]? }
        struct Reply: Decodable { let deck: APIDeck }
        let sourceBody: SourceBody
        switch source {
        case .map(let map): sourceBody = SourceBody(kind: "map", value: nil, map: APINode(map.root))
        case .topic(let topic): sourceBody = SourceBody(kind: "topic", value: topic, map: nil)
        case .text(let text): sourceBody = SourceBody(kind: "text", value: String(text.suffix(200_000)), map: nil)
        }
        let body = Body(source: sourceBody, slides: layouts?.count ?? slides, audience: audience.isEmpty ? nil : audience, quality: quality,
                        layouts: layouts?.map(\.rawValue))
        let reply: Reply = try await BackendClient.shared.invoke("ai", body: body)
        return Generated(title: reply.deck.title, slides: reply.deck.toSlides())
    }

    // One slide again, following an instruction; pictures and the slide's id stay.
    func rewrite(_ slide: Slide, in deck: Deck, instruction: String, layout: SlideLayout? = nil) async throws -> Slide {
        struct Body: Encodable { let action = "slide"; let deckTitle: String; let slide: APISlide; let neighbors: [String]; let instruction: String; let layout: String? }
        struct Reply: Decodable { let slide: APISlide }
        let index = deck.slides.firstIndex { $0.id == slide.id } ?? 0
        let neighbors = deck.slides.indices.filter { abs($0 - index) <= 2 && $0 != index }.map { deck.slides[$0].title }.filter { !$0.isEmpty }
        let body = Body(deckTitle: deck.title, slide: APISlide(slide), neighbors: neighbors, instruction: instruction, layout: layout?.rawValue)
        let reply: Reply = try await BackendClient.shared.invoke("ai", body: body)
        var result = reply.slide.toSlide(keeping: slide)
        if result.imagePrompt == nil { result.imagePrompt = slide.imagePrompt }
        return result
    }

    // The whole deck changed by a command; slides that stay keep their pictures.
    func edit(_ deck: Deck, command: String) async throws -> Deck {
        struct Body: Encodable { let action = "deckEdit"; let deck: APIDeck; let command: String }
        struct Reply: Decodable { let deck: APIDeck }
        // Only slides with words go to the AI (the server drops the others); slides of just a
        // picture or elements are put back where they were.
        let sent = deck.slides.filter(Self.hasWords)
        guard !sent.isEmpty else { throw BackendError.server(code: "bad_request") }
        var request = deck
        request.slides = sent
        let reply: Reply = try await BackendClient.shared.invoke("ai", body: Body(deck: APIDeck(request), command: command))
        var slides = reply.deck.toSlides(keeping: sent).map { slide in
            // Text the server shortened or flattened (line breaks, long notes) but didn't change stays as it was.
            guard let old = sent.first(where: { $0.id == slide.id }) else { return slide }
            var kept = slide
            kept.title = Self.unlessOnlyShortened(old.title, slide.title)
            kept.subtitle = Self.unlessOnlyShortened(old.subtitle, slide.subtitle)
            kept.notes = Self.unlessOnlyShortened(old.notes, slide.notes)
            if slide.bullets.count == old.bullets.count {
                kept.bullets = zip(old.bullets, slide.bullets).map { Self.unlessOnlyShortened($0, $1) }
            }
            return kept
        }
        for (index, slide) in deck.slides.enumerated() where !Self.hasWords(slide) {
            slides.insert(slide, at: min(index, slides.count))
        }
        var edited = deck
        edited.title = reply.deck.title.isEmpty ? deck.title : reply.deck.title
        edited.slides = slides
        return edited
    }

    static func hasWords(_ slide: Slide) -> Bool {
        !slide.title.isEmpty || !slide.bullets.isEmpty || slide.quote != nil || slide.stat != nil
    }

    // The old text when the new one is only the old one shortened ("…") or with its line breaks
    // and spaces flattened; otherwise the new text.
    static func unlessOnlyShortened(_ old: String, _ new: String) -> String {
        func flat(_ text: String) -> String { text.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        let a = flat(old), b = flat(new)
        if a == b { return old }
        if b.hasSuffix("…"), a.hasPrefix(String(b.dropLast()).trimmingCharacters(in: .whitespaces)), b.count > 1 { return old }
        return new
    }

    // MARK: - AI designer (Minor Plus and PRO)

    // A look from a description: "calm, navy and gold", "like a tech keynote".
    func style(_ prompt: String, for deck: Deck) async throws -> DeckLook {
        struct Body: Encodable { let action = "deckStyle"; let prompt: String; let deckTitle: String; let outline: String }
        struct Reply: Decodable { let look: APILook }
        let reply: Reply = try await BackendClient.shared.invoke("ai", body: Body(prompt: prompt, deckTitle: deck.title, outline: String(deck.outline.prefix(3_000))))
        return reply.look.toLook()
    }

    // Elements for a slide from a description: a badge, a timeline, a chart from numbers…
    func elements(_ prompt: String, slide: Slide, deck: Deck) async throws -> [SlideElement] {
        struct Body: Encodable { let action = "slideElements"; let prompt: String; let deckTitle: String; let slide: APISlide; let occupied: [[Double]] }
        struct Reply: Decodable { let elements: [APIElement] }
        // Where the layout's own text sits, so new elements go around it.
        let occupied = slide.elements.map { [$0.x, $0.y, $0.w, $0.h] }
        let reply: Reply = try await BackendClient.shared.invoke("ai", body: Body(prompt: prompt, deckTitle: deck.title, slide: APISlide(slide), occupied: occupied))
        return reply.elements.compactMap { $0.toElement() }
    }
}

// What the server returns for a look (see `deckStyle` in the ai function).
struct APILook: Decodable {
    struct Background: Decodable { var kind: String?; var colors: [String]?; var angle: Double? }
    var name: String?
    var background: Background?
    var accent: String?
    var palette: [String]?
    var titleFont: String?
    var bodyFont: String?
    var glow: Bool?

    static func validHex(_ value: String?) -> String? {
        guard let value, value.range(of: #"^#[0-9A-Fa-f]{6}$"#, options: .regularExpression) != nil else { return nil }
        return value.uppercased()
    }

    func toLook() -> DeckLook {
        let colors = (background?.colors ?? []).compactMap(Self.validHex)
        let kind: SlideBackground.Kind = background?.kind == "solid" ? .solid : .gradient
        var look = DeckLook(
            name: String((name ?? "").prefix(40)),
            background: SlideBackground(kind: kind, colors: colors.isEmpty ? ["#121014", "#19151C"] : Array(colors.prefix(2)), angle: background?.angle ?? 135),
            accent: Self.validHex(accent) ?? "#2FFF9E",
            palette: (palette ?? []).compactMap(Self.validHex).nilIfEmpty,
            titleFont: titleFont.flatMap(DeckFont.init(rawValue:)) ?? .system,
            bodyFont: bodyFont.flatMap(DeckFont.init(rawValue:)) ?? .system,
            glow: glow ?? true
        )
        if look.background.colors.count == 1 && kind == .gradient { look.background.colors.append(look.background.colors[0]) }
        return look
    }
}

struct APIElement: Decodable {
    var kind: String
    var x: Double?, y: Double?, w: Double?, h: Double?
    var rotation: Double?
    var text: String?
    var fontSize: Double?
    var bold: Bool?
    var italic: Bool?
    var align: String?
    var titleFont: Bool?
    var color: String?
    var shape: String?
    var fill: String?
    var fillOpacity: Double?
    var stroke: String?
    var strokeWidth: Double?
    var symbol: String?
    var rows: [[String]]?
    var chart: ChartSpec?
    var link: String?
    var build: String?

    func toElement() -> SlideElement? {
        guard let kind = SlideElement.Kind(rawValue: kind), kind != .image else { return nil }
        var e = SlideElement.new(kind)
        // Inside the slide, at a size that can be seen.
        e.w = min(max(w ?? e.w, 40), 1280)
        e.h = min(max(h ?? e.h, 24), 720)
        e.x = min(max(x ?? e.x, 0), 1280 - e.w)
        e.y = min(max(y ?? e.y, 0), 720 - e.h)
        e.rotation = rotation ?? 0
        if let text { e.text = String(text.prefix(300)) }
        if let fontSize { e.fontSize = min(max(fontSize, 12), 180) }
        if let bold { e.bold = bold }
        if let italic { e.italic = italic }
        if let align { e.align = SlideElement.Align(rawValue: align) ?? .leading }
        if let titleFont { e.titleFont = titleFont }
        e.color = APILook.validHex(color)
        if let shape { e.shape = SlideElement.Shape(rawValue: shape) ?? .roundRect }
        e.fill = APILook.validHex(fill)
        if let fillOpacity { e.fillOpacity = min(max(fillOpacity, 0), 1) }
        e.stroke = APILook.validHex(stroke)
        if let strokeWidth { e.strokeWidth = min(max(strokeWidth, 0), 16) }
        if let symbol, UIImage(systemName: symbol) != nil { e.symbol = symbol }
        if let rows { e.rows = Array(rows.prefix(8).map { Array($0.prefix(5).map { String($0.prefix(80)) }) }) }
        if var chart {
            chart.labels = Array(chart.labels.prefix(12))
            chart.values = Array(chart.values.prefix(chart.labels.count))
            e.chart = chart
        }
        if let link { e.link = String(link.prefix(500)) }
        if let build { e.build = BuildEffect(rawValue: build) ?? .none }
        return e
    }
}

private extension Array {
    var nilIfEmpty: Self? { isEmpty ? nil : self }
}
