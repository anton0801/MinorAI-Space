//
//  DeckTemplates.swift
//  Minor Ai
//
//  Ready-made templates (a look, motion and a slide plan the AI fills from a map or a topic)
//  and templates people save from their own presentations.
//

import Foundation

struct DeckTemplate: Identifiable {
    let id: String
    let name: String
    let icon: String
    let deck: Deck

    var layouts: [SlideLayout] { deck.slides.map(\.layout) }

    // A fresh copy to edit: new ids everywhere.
    func instantiate(title: String? = nil) -> Deck {
        var copy = deck
        copy.id = UUID()
        copy.createdAt = Date()
        copy.updatedAt = Date()
        if let title, !title.isEmpty { copy.title = title }
        copy.slides = copy.slides.map { slide in
            var slide = slide
            slide.id = UUID()
            slide.elements = slide.elements.map { var e = $0; e.id = UUID(); return e }
            return slide
        }
        return copy
    }

    // The AI's slides in the template's design: content from the AI, look and motion from the template.
    func fill(with generated: [Slide], title: String) -> Deck {
        var deck = instantiate(title: title)
        deck.slides = generated.enumerated().map { i, content in
            guard deck.slides.indices.contains(i) else { return content }
            var slide = content
            let design = deck.slides[i]
            slide.background = design.background
            slide.transition = design.transition
            slide.buildBullets = design.buildBullets
            slide.elements = design.elements
            return slide
        }
        return deck
    }
}

enum DeckTemplates {
    private static func s(_ layout: SlideLayout, _ title: String, _ points: [String] = [], subtitle: String = "", build: BuildEffect = .none) -> Slide {
        var slide = Slide(layout: .bullets, title: title, subtitle: subtitle, bullets: points).converted(to: layout)
        if layout != .bullets && layout != .imageText { slide.bullets = [] }
        slide.subtitle = subtitle
        slide.buildBullets = layout.buildable ? build : .none
        return slide
    }

    private static func look(_ name: String, _ from: String, _ to: String, accent: String, title: DeckFont, body: DeckFont, angle: Double = 135, glow: Bool = true) -> DeckLook {
        DeckLook(name: name, background: SlideBackground(kind: .gradient, colors: [from, to], angle: angle), accent: accent, titleFont: title, bodyFont: body, glow: glow)
    }

    private static func icon(_ symbol: String, x: Double, y: Double, size: Double = 120, fill: String? = nil) -> SlideElement {
        var e = SlideElement.new(.icon)
        e.symbol = symbol
        e.x = x; e.y = y; e.w = size; e.h = size
        e.fill = fill
        e.fillOpacity = 0.9
        return e
    }

    private static func make(_ id: String, _ name: String, _ icon: String, look: DeckLook, transition: SlideTransition, slides: [Slide]) -> DeckTemplate {
        var deck = Deck(title: name, slides: slides)
        deck.look = look
        deck.transition = transition
        return DeckTemplate(id: id, name: name, icon: icon, deck: deck)
    }

    static var all: [DeckTemplate] {
        [
            make("pitch", L("Pitch Deck"), "chart.line.uptrend.xyaxis",
                 look: look(L("Pitch Deck"), "#0B1026", "#1B2A5C", accent: "#F5C451", title: .avenir, body: .system),
                 transition: .push,
                 slides: [
                    s(.cover, L("Company name"), subtitle: L("One line about what you do")),
                    {
                        var slide = s(.bullets, L("The problem"), [L("Who has it"), L("What it costs them"), L("Why now")], build: .fade)
                        slide.elements = [icon("exclamationmark.triangle.fill", x: 1080, y: 70)]
                        return slide
                    }(),
                    s(.bullets, L("Our solution"), [L("What we built"), L("How it works"), L("Why it is better")], build: .fade),
                    s(.bigNumber, L("Market"), [L("people who need it")]),
                    s(.twoColumns, L("Business model"), [L("Who pays"), L("How much"), L("Why they stay"), L("How we grow")], build: .rise),
                    s(.timeline, L("Roadmap"), [L("Today"), L("Next quarter"), L("This year"), L("Next year")], build: .rise),
                    s(.table, L("Competition"), [L("Them"), L("Us")]),
                    s(.closing, L("Thank you"), subtitle: L("What we are asking for")),
                 ]),
            make("lecture", L("Lecture"), "graduationcap.fill",
                 look: look(L("Lecture"), "#F7F4EE", "#EDE6DA", accent: "#E8553F", title: .serif, body: .georgia, glow: false),
                 transition: .fade,
                 slides: [
                    s(.cover, L("Lecture topic"), subtitle: L("Course · date")),
                    s(.section, L("Introduction")),
                    s(.bullets, L("Key ideas"), [L("First idea"), L("Second idea"), L("Third idea")], build: .fade),
                    s(.imageText, L("An example"), [L("What we see"), L("Why it matters")]),
                    s(.diagram, L("How it connects"), [L("Cause"), L("Effect"), L("Context"), L("Evidence")], build: .zoom),
                    s(.quote, L("A thought to remember")),
                    s(.bullets, L("Summary"), [L("What to remember"), L("What to read"), L("What to try")], build: .fade),
                    s(.closing, L("Questions?")),
                 ]),
            make("project", L("Project Plan"), "flag.checkered",
                 look: look(L("Project Plan"), "#0C1A13", "#15301F", accent: "#B8F35E", title: .rounded, body: .rounded),
                 transition: .fade,
                 slides: [
                    s(.cover, L("Project name"), subtitle: L("Goal in one line")),
                    s(.bullets, L("Goals"), [L("What success looks like"), L("How we measure it"), L("By when")], build: .fade),
                    s(.timeline, L("Milestones"), [L("Start"), L("First result"), L("Test"), L("Launch")], build: .rise),
                    s(.table, L("Who does what"), [L("Task"), L("Owner"), L("Date")]),
                    s(.twoColumns, L("Risks"), [L("Risk"), L("What could go wrong"), L("Plan"), L("What we will do")], build: .fade),
                    s(.bigNumber, L("Budget"), [L("for the whole project")]),
                    s(.closing, L("Next steps")),
                 ]),
            make("report", L("Weekly Report"), "chart.bar.fill",
                 look: look(L("Weekly Report"), "#FFFFFF", "#F2F4F8", accent: "#3B82F6", title: .system, body: .system, glow: false),
                 transition: .fade,
                 slides: [
                    s(.cover, L("Weekly report"), subtitle: L("Team · week")),
                    s(.bigNumber, L("Key result"), [L("the number that matters most")]),
                    s(.bullets, L("Done"), [L("What we finished"), L("What we learned")], build: .fade),
                    s(.bullets, L("Blockers"), [L("What slows us down"), L("What we need")], build: .fade),
                    s(.table, L("Metrics"), [L("Metric"), L("Value")]),
                    s(.bullets, L("Next week"), [L("Top priority"), L("Also planned")], build: .fade),
                    s(.closing, L("Thanks")),
                 ]),
            make("launch", L("Product Launch"), "rocket.fill",
                 look: look(L("Product Launch"), "#2A0E1F", "#56202A", accent: "#FFAD5C", title: .futura, body: .system),
                 transition: .zoom,
                 slides: [
                    s(.cover, L("Product name"), subtitle: L("Coming soon")),
                    s(.bigNumber, L("Why it matters"), [L("people waiting for this")]),
                    s(.imageText, L("Meet the product"), [L("What it does"), L("Who it is for"), L("What makes it special")], build: .rise),
                    s(.twoColumns, L("Before and after"), [L("Before"), L("The old way"), L("After"), L("With us")], build: .fade),
                    s(.timeline, L("Launch plan"), [L("Preview"), L("Launch day"), L("First month")], build: .rise),
                    s(.quote, L("What early users say")),
                    s(.closing, L("Try it today")),
                 ]),
            make("study", L("Study Notes"), "books.vertical.fill",
                 look: look(L("Study Notes"), "#1B1035", "#0E2A47", accent: "#FC86C3", title: .rounded, body: .rounded),
                 transition: .push,
                 slides: [
                    s(.cover, L("Subject"), subtitle: L("Topic of the exam")),
                    s(.section, L("Basics")),
                    s(.bullets, L("Key ideas"), [L("Idea one"), L("Idea two"), L("Idea three")], build: .fade),
                    s(.diagram, L("Concept map"), [L("Term"), L("Rule"), L("Example"), L("Exception")], build: .zoom),
                    s(.table, L("Terms"), [L("Term"), L("Meaning")]),
                    s(.quote, L("Remember this")),
                    s(.bullets, L("Check yourself"), [L("Question one"), L("Question two"), L("Question three")], build: .fade),
                    s(.closing, L("Good luck!")),
                 ]),
        ]
    }
}

// Templates people save from their own presentations.
@MainActor
final class TemplateStore: ObservableObject {
    static let shared = TemplateStore()
    @Published private(set) var decks: [Deck] = []
    private let url: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        url = base.appendingPathComponent("Templates.json")
        if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder.iso.decode([Deck].self, from: data) {
            decks = saved
        }
    }

    var templates: [DeckTemplate] {
        decks.map { DeckTemplate(id: $0.id.uuidString, name: $0.title, icon: "square.on.square", deck: $0) }
    }

    var imageIDs: [UUID] { decks.flatMap(\.imageIDs) }

    func save(_ deck: Deck, name: String) {
        var copy = deck
        copy.id = UUID()
        copy.title = name
        copy.sourceMapID = nil
        decks.insert(copy, at: 0)
        decks = Array(decks.prefix(30))
        persist()
    }

    func delete(_ id: UUID) {
        decks.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder.iso.encode(decks) { try? data.write(to: url, options: .atomic) }
    }
}
