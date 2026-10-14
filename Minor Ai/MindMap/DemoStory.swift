//
//  DemoStory.swift
//  Minor Ai
//
//  A real-life sample for the App Store preview (-demoStory, DEBUG builds only): a student gets
//  ready for a biology exam on photosynthesis — the map made from that topic, its tasks for
//  today, the class presentation and the flashcards. Replaces the "Launch plan" fixtures when the
//  flag is set; in the app's language (English or Russian).
//

#if DEBUG
import Foundation

enum DemoStory {
    static var isOn: Bool { ProcessInfo.processInfo.arguments.contains("-demoStory") }

    private static func t(_ english: String, _ russian: String) -> String {
        AppLanguage.current.resolved == .russian ? russian : english
    }

    // What the person types on New Map.
    static var topic: String { t("Photosynthesis: exam prep", "Фотосинтез: подготовка к экзамену") }

    static func map() -> MindMap {
        func branch(_ icon: String, _ title: String, _ children: [String]) -> MindNode {
            var node = MindNode(title: title, children: children.map { MindNode(title: $0) })
            node.icon = icon
            return node
        }
        var light = branch("☀️", t("Light reactions", "Световая фаза"), [
            t("Take place in the thylakoids", "Идёт в тилакоидах хлоропласта"),
            t("Light splits water", "Свет расщепляет воду"),
            t("Oxygen is released", "Выделяется кислород"),
            t("Energy is stored in ATP and NADPH", "Энергия запасается в АТФ и НАДФ·H"),
        ])
        light.note = t("Chlorophyll absorbs red and blue light and reflects green — that’s why leaves look green.",
                       "Хлорофилл поглощает красный и синий свет, а зелёный отражает — поэтому листья зелёные.")
        var calvin = branch("🔄", t("Calvin cycle", "Цикл Кальвина"), [
            t("Takes place in the stroma", "Идёт в строме"),
            t("RuBisCO fixes CO₂", "Фермент RuBisCO связывает CO₂"),
            t("Powered by ATP and NADPH", "Энергию дают АТФ и НАДФ·H"),
            t("Glucose is made", "Образуется глюкоза"),
        ])
        calvin.note = t("Named after Melvin Calvin — Nobel Prize in Chemistry, 1961.",
                        "Назван в честь Мелвина Кальвина — Нобелевская премия по химии 1961 года.")
        let equation = branch("🧪", t("The overall equation", "Итоговое уравнение"), [
            "6CO₂ + 6H₂O → C₆H₁₂O₆ + 6O₂",
            t("Needs light and chlorophyll", "Нужны свет и хлорофилл"),
        ])
        let rate = branch("🌡️", t("What affects the rate", "Что влияет на скорость"), [
            t("Light intensity", "Интенсивность света"),
            t("CO₂ concentration", "Концентрация CO₂"),
            t("Temperature", "Температура"),
            t("Water", "Вода"),
        ])
        let matters = branch("🌍", t("Why it matters", "Почему это важно"), [
            t("The oxygen we breathe", "Кислород, которым мы дышим"),
            t("The start of food chains", "Начало пищевых цепей"),
            t("Takes CO₂ out of the air", "Поглощает CO₂ из атмосферы"),
        ])
        // The exam plan: done this morning, two for today, one overdue, one later this week.
        var prep = branch("📅", t("Exam prep", "Подготовка к экзамену"), [])
        let calendar = Calendar.current
        func task(_ title: String, day: Int, hour: Int, done: Bool = false) -> MindNode {
            var node = MindNode(title: title)
            node.isTask = true
            node.isDone = done
            let base = calendar.date(byAdding: .day, value: day, to: Date()) ?? Date()
            node.due = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: base)
            return node
        }
        prep.children = [
            task(t("Notes on chapter 5", "Конспект главы 5"), day: 0, hour: 10, done: true),
            task(t("Review the light reactions", "Повторить световую фазу"), day: 0, hour: 14),
            task(t("Solve 10 practice problems", "Решить 10 задач"), day: 0, hour: 17),
            task(t("Hand in the lab report", "Сдать лабораторную"), day: -1, hour: 18),
            task(t("Practice test", "Пробный тест"), day: 2, hour: 16),
        ]
        let root = MindNode(title: t("Photosynthesis", "Фотосинтез"), children: [light, calvin, equation, rate, matters, prep])
        return MindMap(id: UUID(uuidString: "F07051A7-0000-4000-8000-000000000001")!, root: root, isPinned: true,
                       source: MapSource(kind: .topic, label: topic))
    }

    static func deck() -> Deck {
        var cover = Slide(layout: .cover, title: t("Photosynthesis", "Фотосинтез"),
                          subtitle: t("How plants turn light into food", "Как растения превращают свет в пищу"))
        cover.notes = t("Open with a question: where does the oxygen we breathe come from?",
                        "Начните с вопроса классу: откуда берётся кислород, которым мы дышим?")
        var what = Slide(layout: .bullets, title: t("What photosynthesis is", "Что такое фотосинтез"), bullets: [
            t("Plants make glucose from CO₂ and water", "Растения делают глюкозу из CO₂ и воды"),
            t("Sunlight provides the energy", "Энергию даёт солнечный свет"),
            t("Oxygen is released as a by-product", "Побочный продукт — кислород"),
            t("It happens in chloroplasts", "Всё происходит в хлоропластах"),
        ])
        what.notes = t("Keep it simple: inputs, energy, outputs. The details come next.",
                       "Коротко: что на входе, откуда энергия, что на выходе. Детали — дальше.")
        var process = SlideDiagram()
        process.kind = .process
        for (label, icon) in [(t("Light", "Свет"), "sun.max"), (t("Water splits", "Вода расщепляется"), "drop"),
                              (t("ATP and NADPH", "АТФ и НАДФ·H"), "bolt"), (t("Calvin cycle", "Цикл Кальвина"), "arrow.triangle.2.circlepath"),
                              (t("Glucose", "Глюкоза"), "leaf")] {
            let id = process.insertStep(after: process.allItems.last?.id, label: label)
            process.updateNode(id) { $0.icon = icon }
        }
        var how = Slide(layout: .diagram, title: t("How it works", "Как это работает"))
        how.diagram = process
        how.notes = t("Walk through the arrows: light energy ends up stored in glucose.",
                      "Пройдитесь по стрелкам: энергия света в итоге запасается в глюкозе.")
        var stages = Slide(layout: .twoColumns, title: t("Two stages", "Две фазы"))
        stages.columns = [
            SlideColumn(title: t("Light reactions", "Световая фаза"), bullets: [t("In the thylakoids", "В тилакоидах"), t("Need light", "Нужен свет"), t("Give O₂, ATP and NADPH", "Дают O₂, АТФ и НАДФ·H")]),
            SlideColumn(title: t("Calvin cycle", "Цикл Кальвина"), bullets: [t("In the stroma", "В строме"), t("No light needed directly", "Свет напрямую не нужен"), t("Makes glucose from CO₂", "Делает глюкозу из CO₂")]),
        ]
        stages.notes = t("Common exam question: where does each stage take place?",
                         "Частый вопрос на экзамене: где идёт каждая фаза?")
        var oxygen = Slide(layout: .bigNumber, title: t("Earth’s oxygen", "Кислород Земли"))
        oxygen.stat = SlideStat(value: "50–80%", label: t("of Earth’s oxygen is produced in the ocean, mostly by phytoplankton",
                                                         "кислорода на Земле производит океан — в основном фитопланктон"))
        oxygen.notes = t("Source: NOAA. Not only forests — the ocean matters most.",
                         "Источник: NOAA. Важны не только леса — больше всего даёт океан.")
        var factors = Slide(layout: .table, title: t("What changes the rate", "Что влияет на скорость"))
        factors.table = [
            [t("Factor", "Фактор"), t("When it rises", "Если больше")],
            [t("Light", "Свет"), t("Faster, up to a limit", "Быстрее — до предела")],
            ["CO₂", t("Faster, up to a limit", "Быстрее — до предела")],
            [t("Temperature", "Температура"), t("Faster up to an optimum, then slower", "Быстрее до оптимума, потом медленнее")],
            [t("Water", "Вода"), t("Too little slows it down", "Без воды процесс замедляется")],
        ]
        var equation = Slide(layout: .quote)
        equation.quote = SlideQuote(text: "6CO₂ + 6H₂O → C₆H₁₂O₆ + 6O₂", author: t("The overall equation", "Итоговое уравнение фотосинтеза"))
        equation.notes = t("Ask the class to name each part of the equation.",
                           "Попросите класс назвать каждую часть уравнения.")
        let closing = Slide(layout: .closing, title: t("Thank you!", "Спасибо!"), subtitle: t("Questions?", "Вопросы?"))
        var deck = Deck(title: t("Photosynthesis", "Фотосинтез"), slides: [cover, what, how, stages, oxygen, factors, equation, closing], theme: .forest)
        deck.id = UUID(uuidString: "F07051A7-0000-4000-8000-000000000002")!
        return deck
    }
}
#endif
