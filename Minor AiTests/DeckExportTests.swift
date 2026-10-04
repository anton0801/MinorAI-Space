//
//  DeckExportTests.swift
//  Minor AiTests
//
//  The PowerPoint export puts text where the slide itself draws it: a long cover title stays
//  under its accent bar. Both files are also copied to Documents to look at.
//

import Foundation
import Testing
@testable import Minor_Ai

@MainActor
struct DeckExportTests {
    static func carDeck() -> Deck {
        let cover = Slide(layout: .cover, title: "BMW M5 F90 2022: покупаем с холодной головой", subtitle: "План для нас и друзей: от поиска до безопасной сделки")
        var diagram = Slide(layout: .diagram, title: "Бюджет — не только цена машины")
        diagram.diagram = SlideDiagram(center: "Полная стоимость покупки",
                                       nodes: ["Цена автомобиля", "Проверки и диагностика", "Оформление и страховка", "Первое обслуживание", "Резерв на ремонт"])
        let image = Slide(layout: .imageText, title: "Отбираем объявления до поездки",
                          bullets: ["Запрашиваем VIN, документы и историю обслуживания", "Уточняем год выпуска, комплектацию и происхождение",
                                    "Спрашиваем про ДТП, тюнинг и причины продажи", "Сравниваем похожие машины, а не только минимальные цены"])
        return Deck(title: "Как купить BMW M5 F90 2022 года", slides: [cover, diagram, image])
    }

    // Frames (EMU) of the shapes on the first slide, in order.
    private static func firstSlideFrames(_ pptx: URL) throws -> (xml: String, frames: [(y: Int, height: Int)]) {
        // The file is stored without compression, so its XML can be read straight from the bytes.
        let text = String(decoding: try Data(contentsOf: pptx), as: UTF8.self)
        let start = try #require(text.range(of: "<p:sld "))
        let end = try #require(text.range(of: "</p:sld>", range: start.upperBound..<text.endIndex))
        let xml = String(text[start.lowerBound..<end.upperBound])
        let pattern = try NSRegularExpression(pattern: #"<a:off x="\d+" y="(\d+)"/><a:ext cx="\d+" cy="(\d+)"/>"#)
        let frames = pattern.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)).map { match -> (Int, Int) in
            (Int((xml as NSString).substring(with: match.range(at: 1)))!, Int((xml as NSString).substring(with: match.range(at: 2)))!)
        }
        return (xml, frames)
    }

    @Test func longCoverTitleStaysUnderItsBar() throws {
        let deck = Self.carDeck()
        let pptx = try DeckExport.pptx(deck)
        let pdf = try DeckExport.pdf(deck)
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        for (url, name) in [(pptx, "export-test.pptx"), (pdf, "export-test.pdf")] {
            let target = documents.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.copyItem(at: url, to: target)
        }
        let (xml, frames) = try Self.firstSlideFrames(pptx)
        #expect(xml.contains("покупаем с холодной головой"))
        // Bar, title, subtitle: the title starts below the bar and the subtitle below the title.
        try #require(frames.count >= 3)
        #expect(frames[1].y >= frames[0].y + frames[0].height)
        #expect(frames[2].y >= frames[1].y + frames[1].height - 9525 * 10)
    }
}
