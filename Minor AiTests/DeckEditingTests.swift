//
//  DeckEditingTests.swift
//  Minor AiTests
//
//  The slides editor's new parts: hidden slides, a slide's own style and text style (stored
//  compatibly, used by presenting and export), layouts that keep every point and never make up a
//  number, splitting what doesn't fit, and finding the text under a tap.
//

import Foundation
import Testing
import UIKit
@testable import Minor_Ai

@MainActor
struct DeckEditingTests {
    private func roundTrip(_ slide: Slide) throws -> Slide {
        try JSONDecoder().decode(Slide.self, from: JSONEncoder().encode(slide))
    }

    @Test func oldSlidesLoadAndNewFieldsRoundTrip() throws {
        let old = #"{"id":"\#(UUID().uuidString)","layout":"bullets","title":"Plan","bullets":["A"]}"#
        let slide = try JSONDecoder().decode(Slide.self, from: Data(old.utf8))
        #expect(!slide.isHidden && slide.look == nil && slide.theme == nil && slide.text == nil)
        let json = String(decoding: try JSONEncoder().encode(slide), as: UTF8.self)
        #expect(!json.contains("hidden") && !json.contains("\"text\""), "Nothing new is written for a plain slide")

        var styled = slide
        styled.isHidden = true
        styled.theme = DeckTheme.paper.rawValue
        var text = SlideTextStyle()
        text.title.scale = 1.3
        text.title.align = .center
        text.body.color = "#E8553F"
        styled.text = text
        let decoded = try roundTrip(styled)
        #expect(decoded.isHidden && decoded.theme == "paper" && decoded.text == text)

        // Unknown or empty values from elsewhere are dropped instead of breaking the slide.
        let odd = #"{"id":"\#(UUID().uuidString)","layout":"bullets","title":"X","hidden":false,"theme":"neon-pink","text":{"title":{"scale":9}}}"#
        let tolerant = try JSONDecoder().decode(Slide.self, from: Data(odd.utf8))
        #expect(!tolerant.isHidden && tolerant.theme == nil)
        #expect(tolerant.text?.title.scale == SlideTextStyle.Part.scales.upperBound, "Sizes stay within the allowed range")
    }

    @Test func changingTheLayoutKeepsEveryPointAndInventsNoNumbers() {
        let points = ["Idea", "Plan", "Draft", "Review", "Launch", "Learn", "Grow", "Share", "Repeat"]
        let slide = Slide(layout: .bullets, title: "Roadmap", bullets: points)
        let timeline = slide.converted(to: .timeline)
        #expect(timeline.items.map(\.title) == points, "Nothing is dropped")
        #expect(timeline.bullets == points, "The original points stay with the slide")
        #expect(slide.converted(to: .diagram).diagram?.nodes == points)
        #expect(slide.converted(to: .table).table.count == points.count + 1)

        let noNumber = slide.converted(to: .bigNumber)
        #expect(noNumber.stat?.value == "", "No made-up 100%")
        let withNumber = Slide(layout: .bullets, title: "Growth", bullets: ["Users came back", "41% return every week"]).converted(to: .bigNumber)
        #expect(withNumber.stat?.value == "41%")
        #expect(Slide.firstNumber(in: "Plus costs $12.99 a month") == "$12.99")
        #expect(Slide.firstNumber(in: "1 000 users") == "1 000")
        #expect(Slide.firstNumber(in: "no digits here") == nil)
    }

    @Test func whatDoesNotFitIsSplitIntoNewSlides() {
        var slide = Slide(layout: .timeline, title: "Roadmap")
        slide.items = (1...9).map { SlideItem(title: "Step \($0)", detail: "") }
        slide.notes = "Say this"
        slide.elements = [SlideElement.new(.text)]
        #expect(slide.overflow?.shown == Slide.capacity(.timeline) && slide.overflow?.total == 9)
        let parts = slide.split()
        #expect(parts.count == 2)
        #expect(parts[0].id == slide.id && parts[0].items.count == 6 && parts[0].notes == "Say this" && parts[0].elements.count == 1)
        #expect(parts[1].id != slide.id && parts[1].items.map(\.title) == ["Step 7", "Step 8", "Step 9"])
        #expect(parts[1].notes.isEmpty && parts[1].elements.isEmpty, "Notes and free elements stay on the first slide")
        #expect(parts.allSatisfy { $0.overflow == nil })

        var table = Slide(layout: .table, title: "Plans")
        table.table = [["Plan", "Price"]] + (1...7).map { ["P\($0)", "$\($0)"] }
        let tables = table.split()
        #expect(tables.count == 2 && tables.allSatisfy { $0.table.first == ["Plan", "Price"] }, "Each part keeps the header")
        #expect(Slide(layout: .bullets, title: "Short", bullets: ["A", "B"]).split().count == 1)
    }

    @Test func hiddenSlidesAreSkippedWhenPresenting() {
        var deck = Deck(title: "Talk", slides: (1...5).map { Slide(layout: .bullets, title: "Slide \($0)") })
        deck.slides[1].isHidden = true
        deck.slides[2].isHidden = true
        #expect(deck.withoutHidden().slides.map(\.title) == ["Slide 1", "Slide 4", "Slide 5"])
        #expect(deck.shownIndex(for: 0) == 0)
        #expect(deck.shownIndex(for: 1) == 1, "A hidden slide on screen starts the show at the next shown one")
        #expect(deck.shownIndex(for: 3) == 1 && deck.shownIndex(for: 4) == 2)
    }

    @Test func aSlidesOwnStyleWinsOverThePresentations() {
        var deck = Deck(title: "Talk", slides: [Slide(layout: .cover, title: "A"), Slide(layout: .bullets, title: "B")], theme: .midnight)
        #expect(!deck.style(for: deck.slides[1]).isLight)
        deck.slides[1].theme = DeckTheme.paper.rawValue
        #expect(deck.style(for: deck.slides[1]).isLight, "This slide's ready-made theme")
        #expect(!deck.style(for: deck.slides[0]).isLight, "Other slides keep the presentation's style")
        var look = DeckLook(theme: .ocean)
        look.accent = "#FF0000"
        deck.slides[1].look = look
        #expect(UIColor(deck.style(for: deck.slides[1]).accent).hexString.uppercased() == "#FF0000", "Its own style comes before a ready-made theme")
    }

    @Test func tapsFindTheTextUnderTheFinger() {
        let frames: [String: CGRect] = [
            "title": CGRect(x: 80, y: 70, width: 900, height: 70),
            "bar": CGRect(x: 80, y: 40, width: 96, height: 10),
            "col.0": CGRect(x: 80, y: 200, width: 500, height: 400),
            "col.0.title": CGRect(x: 110, y: 230, width: 300, height: 50),
            "col.0.text.1": CGRect(x: 140, y: 340, width: 400, height: 40),
        ]
        #expect(SlidePart.hit(CGPoint(x: 200, y: 100), in: frames) == "title")
        #expect(SlidePart.hit(CGPoint(x: 200, y: 360), in: frames) == "col.0.text.1", "The smallest text around the point")
        #expect(SlidePart.hit(CGPoint(x: 120, y: 45), in: frames) == nil, "Bars and cards aren't text")
        #expect(SlidePart.hit(CGPoint(x: 1200, y: 700), in: frames) == nil)
        #expect(SlidePart.role("title") == .title && SlidePart.role("b.text.2") == .body)
        #expect(SlidePart.isText("t.3.detail") && SlidePart.isText("row.2") && !SlidePart.isText("t.3.dot") && !SlidePart.isText("table"))
    }

    @Test func powerPointUsesTheSlidesTextStyleAndLeavesHiddenSlidesOut() throws {
        var deck = Deck(title: "Talk", slides: [Slide(layout: .bullets, title: "Shown", bullets: ["One"]), Slide(layout: .bullets, title: "Hidden one", bullets: ["Two"])])
        var text = SlideTextStyle()
        text.title.color = "#E8553F"
        text.title.align = .center
        deck.slides[0].text = text
        deck.slides[1].isHidden = true
        let url = try DeckExport.pptx(deck.withoutHidden())
        let file = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        #expect(file.components(separatedBy: "<p:sld ").count - 1 == 1, "Only the shown slide")
        #expect(!file.contains("Hidden one"))
        #expect(file.contains("E8553F"), "The title's own color")
        #expect(file.contains("algn=\"ctr\""), "The title's own alignment")
    }
}
