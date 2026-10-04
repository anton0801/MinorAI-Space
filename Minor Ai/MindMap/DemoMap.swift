//
//  DemoMap.swift
//  Minor Ai
//
//  Debug-only sample content and launch arguments for previews and screenshots:
//  -demoMap opens a sample map, -mindMode opens Start a Map, -sidebarMaps opens Your Maps.
//

#if DEBUG
import Foundation
import UIKit

enum DemoMap {
    // Screenshot fixtures follow the in-app language and never ship in Release.
    private static func demoText(_ english: String, _ russian: String) -> String {
        AppLanguage.current.resolved == .russian ? russian : english
    }

    static func make() -> MindMap {
        func node(_ title: String, _ children: [String] = []) -> MindNode {
            MindNode(title: title, children: children.map { MindNode(title: $0) })
        }
        var audience = node(demoText("Audience", "Аудитория"), [demoText("Students who use iPad", "Студенты с iPad"), demoText("Creators", "Авторы"), demoText("Small teams", "Небольшие команды"), demoText("Researchers", "Исследователи")])
        audience.isCollapsed = true
        var positioning = node(demoText("Positioning", "Позиционирование"), [demoText("AI first", "ИИ в основе"), demoText("Simple by design", "Простой дизайн"), demoText("Dark and focused", "Тёмная тема и фокус")])
        positioning.isCollapsed = true
        let pricing = node(demoText("Pricing", "Тарифы"), [demoText("Free · 3 maps", "Free · 3 карты"), "Plus · $12.99", "PRO · $24.99", demoText("Yearly · save up to 27%", "За год · до −27%")])
        var channels = node(demoText("Channels", "Каналы"), [demoText("App Store search", "Поиск в App Store"), demoText("TikTok demos", "Демо в TikTok"), "Product Hunt"])
        channels.isCollapsed = true
        var timeline = node(demoText("Timeline", "Сроки"), [demoText("Beta in November", "Бета в ноябре"), demoText("Launch in January", "Запуск в январе"), demoText("iPad in spring", "iPad весной")])
        // Tasks with progress on the branch.
        for index in timeline.children.indices { timeline.children[index].isTask = true }
        timeline.children[0].isDone = true
        var risks = node(demoText("Risks", "Риски"), [demoText("API costs", "Расходы на API")])
        risks.isCollapsed = true
        var risks2 = risks
        risks2.children.append(MindNode(title: demoText("Most users try one or two strong models a week, so the allowance covers real use.", "Обычно хватает одной-двух мощных моделей в неделю — лимит рассчитан на реальное использование."), isCallout: true))
        risks2.children[0].priority = 1
        var pricing2 = pricing
        pricing2.link = "https://minorai.site/#pricing"
        let icons = ["🎯", "💡", "💰", "📣", "📅", "⚠️"]
        var branches = [audience, positioning, pricing2, channels, timeline, risks2]
        for index in branches.indices { branches[index].icon = icons[index] }
        let root = MindNode(title: demoText("Launch plan", "План запуска"), children: branches)
        var map = MindMap(id: UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!, root: root, isPinned: true,
                          source: MapSource(kind: .document, label: demoText("Pitch deck.pdf", "Презентация.pdf")))
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-demoLayout"), args.indices.contains(i + 1) { map.layout = args[i + 1] }
        map.root.children[2].note = demoText("Three tiers keep the choice simple.", "Три тарифа упрощают выбор.")
        if let i = args.firstIndex(of: "-demoStyle"), args.indices.contains(i + 1) { map.style = args[i + 1] }
        // -demoShapes: every shape and fill, other lines, a palette and a due date.
        if args.contains("-demoShapes") || args.contains("-demoToday") {
            map.palette = "sunset"
            map.lines = "elbow"
            map.canvas = "grid"
            map.root.look = NodeLook(shape: .ellipse)
            map.root.children[2].look = NodeLook(shape: .hexagon, fill: .solid, bold: true)
            for (index, shape) in [NodeShape.pill, .diamond, .square, .underline].enumerated() {
                map.root.children[2].children[index].look = NodeLook(shape: shape, fill: index == 2 ? .outline : .auto, size: index == 0 ? .large : .regular, dashed: index == 2)
            }
            map.root.children[4].isCollapsed = false
            map.root.children[4].children[1].due = Calendar.current.date(byAdding: .day, value: 2, to: Date())
            map.root.children[4].children[2].due = Calendar.current.date(byAdding: .day, value: -1, to: Date())
            map.root.children[4].color = .blue
            map.root.children[4].frame = demoText("Q1 plan", "План на I квартал")
            map.links = [MapLink(from: map.root.children[2].id, to: map.root.children[3].id, label: demoText("drives", "привлекает")),
                         MapLink(from: map.root.children[4].children[0].id, to: map.root.children[5].id)]
            map.root.children[5].children.append(MindNode(title: demoText("Users want offline maps", "Нужны карты без сети"), isSuggestion: true))
            map.root.children[5].isCollapsed = false
        }
        return map
    }

    @MainActor
    static func install() -> MindMap {
        var map = make()
        // A generated gradient stands in for a photo on the Positioning branch.
        let size = CGSize(width: 800, height: 520)
        let picture = UIGraphicsImageRenderer(size: size).image { context in
            let colors = [UIColor(red: 0.35, green: 0.95, blue: 0.7, alpha: 1).cgColor, UIColor(red: 0.6, green: 0.45, blue: 1, alpha: 1).cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            UIColor.white.withAlphaComponent(0.9).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 320, y: 170, width: 160, height: 160))
        }
        if let data = picture.jpegData(compressionQuality: 0.9), let stored = MapStore.shared.storeImage(data, isAI: true) {
            map.root.children[1].image = stored
        }
        MapStore.shared.save(map)
        return map
    }

    // A conversation with a Markdown answer, for chat screenshots (-demoChat).
    static let chat: [ChatMessage] = [
        ChatMessage(role: .user, text: demoText("How should I price a mind map app?", "Какие тарифы выбрать для приложения с картами мыслей?")),
        ChatMessage(role: .assistant, text: demoText("""
        ## Simple pricing
        Keep **two paid tiers** and a free plan that shows the value fast:
        - **Free**: 3 maps a month
        - **Plus**: up to 300 maps a month and all sources
        - **PRO**: Xmind export and share links

        Offer a yearly plan with `2 months free`.
        """, """
        ## Простые тарифы
        Оставьте **два платных тарифа** и бесплатный, чтобы сразу показать пользу:
        - **Free**: 3 карты в месяц
        - **Plus**: до 300 карт в месяц и все источники
        - **PRO**: экспорт в Xmind и ссылки для обмена

        Добавьте годовой план с `2 месяцами в подарок`.
        """)),
    ]

    // A presentation with every layout (-demoDeck, -demoSlides).
    static func deck(theme: DeckTheme = .midnight) -> Deck {
        var cover = Slide(layout: .cover, title: demoText("Launch plan", "План запуска"), subtitle: demoText("How Minor AI reaches its first 100,000 people", "Как Minor AI найдёт первых 100 000 пользователей"))
        cover.notes = demoText("Welcome everyone. Today: who we serve, how we price, and how we launch.", "Сегодня обсудим аудиторию, тарифы и запуск.")
        let section = Slide(layout: .section, title: demoText("Who we serve", "Для кого мы работаем"), subtitle: demoText("Students, creators and small teams", "Студенты, авторы и небольшие команды"))
        let bullets = Slide(layout: .bullets, title: demoText("Why people switch to Minor", "Почему выбирают Minor"), bullets: [demoText("Maps from any source in seconds", "Карты из любого источника за секунды"), demoText("An assistant that knows your maps", "Помощник, который знает ваши карты"), demoText("Tasks, reminders and a Today screen", "Задачи, напоминания и экран «Сегодня»"), demoText("Beautiful presentations in one tap", "Красивые презентации одним касанием")])
        var two = Slide(layout: .twoColumns, title: demoText("Free and Plus", "Free и Plus"))
        two.columns = [SlideColumn(title: "Free", bullets: [demoText("3 maps a month", "3 карты в месяц"), demoText("Every chat model", "Все модели чата"), demoText("1 presentation", "1 презентация")]), SlideColumn(title: "Plus", bullets: [demoText("300 maps a month", "300 карт в месяц"), demoText("YouTube and voice", "YouTube и голос"), demoText("20 presentations", "20 презентаций")])]
        var image = Slide(layout: .imageText, title: demoText("Think in maps", "Мыслите картами"), bullets: [demoText("See the whole idea at once", "Вся идея перед глазами"), demoText("Expand any branch with AI", "Развивайте любую ветку с ИИ"), demoText("Present it in one tap", "Покажите её одним касанием")])
        image.imagePrompt = demoText("A glowing mind map floating above a desk at night", "Светящаяся карта мыслей над рабочим столом ночью")
        var big = Slide(layout: .bigNumber, title: demoText("Study time saved", "Экономия времени на учёбу"))
        big.stat = SlideStat(value: "3×", label: demoText("faster to review a lecture as a map than as notes", "быстрее повторить лекцию по карте, чем по конспекту"))
        var quote = Slide(layout: .quote)
        quote.quote = SlideQuote(text: demoText("I finally see how all the pieces of my thesis fit together.", "Наконец-то я вижу, как связаны все части моей дипломной работы."), author: demoText("A beta tester", "Участник бета-теста"))
        var timeline = Slide(layout: .timeline, title: demoText("Roadmap", "План развития"))
        timeline.items = [SlideItem(title: demoText("November", "Ноябрь"), detail: demoText("Beta with 500 students", "Бета с 500 студентами")), SlideItem(title: demoText("January", "Январь"), detail: demoText("Launch on the App Store", "Запуск в App Store")), SlideItem(title: demoText("March", "Март"), detail: demoText("Presentations and voice", "Презентации и голос")), SlideItem(title: demoText("Spring", "Весна"), detail: demoText("iPad and Mac", "iPad и Mac"))]
        var table = Slide(layout: .table, title: demoText("Plans at a glance", "Сравнение тарифов"))
        table.table = [[demoText("Plan", "Тариф"), demoText("Price", "Цена"), demoText("Maps", "Карты"), demoText("Presentations", "Презентации")], ["Free", "$0", demoText("3 / month", "3 / месяц"), demoText("1 / month", "1 / месяц")], ["Plus", "$12.99", demoText("300 / month", "300 / месяц"), demoText("20 / month", "20 / месяц")], ["PRO", "$24.99", demoText("600 / month", "600 / месяц"), demoText("60 / month", "60 / месяц")]]
        var diagram = Slide(layout: .diagram, title: demoText("Everything connects", "Всё связано"))
        diagram.diagram = SlideDiagram(center: demoText("Your map", "Ваша карта"), nodes: [demoText("Assistant", "Помощник"), demoText("Tasks", "Задачи"), demoText("Presentations", "Презентации"), demoText("Study", "Учёба"), demoText("Widgets", "Виджеты"), demoText("Sync", "Синхронизация")])
        let closing = Slide(layout: .closing, title: demoText("Let’s build it together", "Создадим это вместе"), subtitle: demoText("Questions? support@minorai.site", "Вопросы? support@minorai.site"))
        return Deck(title: demoText("Launch plan", "План запуска"), slides: [cover, section, bullets, two, image, big, quote, timeline, table, diagram, closing], theme: theme)
    }

    // A designed presentation (-demoDesign): own look, a slide background, elements of every kind,
    // transitions and points that come in one by one.
    static func designedDeck() -> Deck {
        var deck = DeckTemplates.all[0].instantiate(title: "Minor AI")
        deck.slides[0].title = "Minor AI"
        deck.slides[0].subtitle = demoText("Give your thoughts shape", "Придайте мыслям форму")
        var badge = SlideElement.new(.shape)
        badge.shape = .roundRect; badge.text = demoText("Seed round", "Первый раунд"); badge.fontSize = 28; badge.bold = true
        badge.x = 990; badge.y = 60; badge.w = 220; badge.h = 64; badge.rotation = 6
        deck.slides[0].elements.append(badge)
        var chart = SlideElement.new(.chart)
        chart.chart = ChartSpec(kind: .bar, title: demoText("Monthly users", "Пользователи за месяц"), labels: [demoText("Jun", "Июн"), demoText("Jul", "Июл"), demoText("Aug", "Авг"), demoText("Sep", "Сен")], values: [1200, 2600, 4100, 7300])
        chart.x = 640; chart.y = 200; chart.w = 560; chart.h = 400; chart.build = .rise
        deck.slides[3].layout = .bullets
        deck.slides[3].title = demoText("Traction", "Рост")
        deck.slides[3].bullets = [demoText("6× growth since June", "Рост в 6 раз с июня"), demoText("41% come back every week", "41% возвращаются каждую неделю")]
        deck.slides[3].buildBullets = .fade
        deck.slides[3].elements = [chart]
        var cardShape = SlideElement.new(.shape)
        cardShape.x = 80; cardShape.y = 230; cardShape.w = 340; cardShape.h = 380; cardShape.fill = "#FFFFFF"; cardShape.fillOpacity = 0.08
        var icon = SlideElement.new(.icon)
        icon.symbol = "brain.head.profile"; icon.x = 110; icon.y = 260; icon.w = 90; icon.h = 90; icon.build = .zoom
        var text = SlideElement.new(.text)
        text.text = demoText("Maps from anything", "Всё становится картой"); text.fontSize = 34; text.x = 110; text.y = 380; text.w = 290; text.h = 120; text.build = .fade
        var qr = SlideElement.new(.qr)
        qr.link = "https://minorai.site"; qr.x = 1000; qr.y = 420; qr.w = 200; qr.h = 200
        deck.slides[2].layout = .closing
        deck.slides[2].title = ""
        deck.slides[2].subtitle = ""
        deck.slides[2].elements = [cardShape, icon, text, qr]
        deck.slides[2].background = SlideBackground(kind: .solid, colors: ["#F5C451"], angle: 0)
        var table = SlideElement.new(.table)
        table.rows = [[demoText("Plan", "Тариф"), demoText("Price", "Цена")], ["Free", "$0"], ["Plus", "$12.99"]]
        table.x = 700; table.y = 260; table.w = 500; table.h = 240
        deck.slides[4].elements = [table]
        deck.brand = DeckBrand(logo: nil, corner: .topRight, size: 64, onCover: true, footer: "Minor AI · 2026", showNumbers: true)
        return deck
    }

    // The assistant working with a map (-demoAgent): a mention, a change card and a pictures card.
    static func agentChat(_ map: MindMap) -> [ChatMessage] {
        [
            ChatMessage(role: .user, text: demoText("@\(map.title) add a section about risks of launching too early", "@\(map.title) добавь раздел о рисках слишком раннего запуска"),
                        maps: [MapMention(id: map.id, title: map.title)], mapText: "…"),
            ChatMessage(role: .assistant, text: "", action: ChatAction(kind: .edited, mapID: map.id, mapTitle: map.title, summary: L("+4 ideas") + " · " + L("1 changed"))),
            ChatMessage(role: .user, text: demoText("Add pictures to every branch", "Добавь изображения к каждой ветке")),
            ChatMessage(role: .assistant, text: "", action: ChatAction(kind: .images, mapID: map.id, mapTitle: map.title, imageNodes: map.root.children.map(\.id))),
        ]
    }
}
#endif

#if DEBUG
import SwiftUI

// Every layout in every theme, for checking the slide designs (-demoSlides [theme]).
struct SlideGallery: View {
    var body: some View {
        let args = ProcessInfo.processInfo.arguments
        let theme = args.firstIndex(of: "-demoSlides").flatMap { args.indices.contains($0 + 1) ? DeckTheme(rawValue: args[$0 + 1]) : nil } ?? .midnight
        let deck = DemoMap.deck(theme: theme)
        let start = args.firstIndex(of: "-demoSlides").flatMap { args.indices.contains($0 + 2) ? Int(args[$0 + 2]) : nil } ?? 0
        ScrollView {
            VStack(spacing: 10) {
                ForEach(Array(deck.slides.enumerated()).filter { $0.offset >= start }, id: \.offset) { i, slide in
                    SlideCanvas(slide: slide, deck: deck, index: i)
                }
            }
            .padding(6)
        }
        .background(Color.black)
    }
}
#endif
