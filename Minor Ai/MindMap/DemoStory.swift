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

// Marketing fixtures for the App Store screenshots. Only used with an explicit
// -campaign <travel|study|podcast> launch argument; -campaignLibrary adds the other maps, two
// presentations and one day of tasks across them; -campaignLang de|es writes the examples in
// German or Spanish (the app's own interface stays as it is). Real documents, rendered by the app.
#if DEBUG
import UIKit
import PDFKit

enum CampaignDemo {
    static var topic: String? { value(after: "-campaign") }
    static var isOn: Bool { topic != nil }
    static var withLibrary: Bool { ProcessInfo.processInfo.arguments.contains("-campaignLibrary") }
    private static var lang: String { value(after: "-campaignLang") ?? "en" }
    private static func value(after flag: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }
    // The example's text in the campaign's language.
    private static func l(_ en: String, _ de: String, _ es: String) -> String { lang == "de" ? de : lang == "es" ? es : en }

    private static let travelID = UUID(uuidString: "C0150000-0000-4000-8000-000000000002")!
    private static let podcastID = UUID(uuidString: "C0150000-0000-4000-8000-000000000001")!
    private static let studyID = UUID(uuidString: "F07051A7-0000-4000-8000-000000000001")!

    // Titles other fixtures look up (focus, tasks for Today).
    private static var kyoto: String { l("Kyoto", "Kyoto", "Kioto") }
    private static var lightReactions: String { l("Light reactions", "Lichtreaktion", "Fase luminosa") }
    private static var recordEpisode: String { l("Record episode one", "Folge 1 aufnehmen", "Grabar el episodio 1") }
    private static var coverArt: String { l("Design the cover art", "Cover gestalten", "Diseñar la portada") }
    private static var bookHotels: String { l("Book hotels", "Hotels buchen", "Reservar hoteles") }
    private static var trainTickets: String { l("Train tickets", "Zugtickets", "Billetes de tren") }
    private static var cookingClass: String { l("Cooking class", "Kochkurs", "Clase de cocina") }
    private static var notesChapter: String { l("Notes on chapter 5", "Kapitel 5 zusammenfassen", "Resumir el tema 5") }
    private static var reviewLight: String { l("Review the light reactions", "Lichtreaktion wiederholen", "Repasar la fase luminosa") }
    private static var labReport: String { l("Hand in the lab report", "Laborbericht abgeben", "Entregar el informe de laboratorio") }
    private static var practiceTest: String { l("Practice test", "Probetest", "Simulacro de examen") }

    private static func leaves(_ titles: [String]) -> [MindNode] { titles.map { MindNode(title: $0) } }
    private static func branch(_ title: String, _ icon: String, _ children: [String], collapsed: Bool = false) -> MindNode {
        var node = MindNode(title: title, children: leaves(children))
        node.icon = icon
        node.isCollapsed = collapsed
        return node
    }
    private static func task(_ title: String, day: Int?, hour: Int = 9, done: Bool = false) -> MindNode {
        var node = MindNode(title: title)
        node.isTask = true
        node.isDone = done
        if let day {
            let calendar = Calendar.current
            let date = calendar.date(byAdding: .day, value: day, to: Date()) ?? Date()
            node.due = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date)
        }
        return node
    }
    private static func find(_ title: String, in node: MindNode) -> MindNode? {
        if node.title == title { return node }
        for child in node.children { if let found = find(title, in: child) { return found } }
        return nil
    }

    // The idea the screenshot flags act on (-demoSelect, -demoTask, -demoNextSteps, -demoProposal).
    static func focus(in map: MindMap) -> UUID? {
        let title = topic == "study" ? lightReactions : topic == "podcast" ? recordEpisode : kyoto
        return find(title, in: map.root)?.id
    }

    static func map() -> MindMap { map(topic ?? "travel") }

    static func map(_ topic: String) -> MindMap {
        switch topic {
        case "study": return studyMap()
        case "podcast": return podcastMap()
        default: return travelMap()
        }
    }

    private static func travelMap() -> MindMap {
        var tokyo = branch(l("Tokyo", "Tokio", "Tokio"), "🗼", [l("Asakusa temple", "Asakusa-Tempel", "Templo Asakusa"), l("Shibuya at night", "Shibuya bei Nacht", "Shibuya de noche"),
                                                                 l("Sushi breakfast", "Sushi-Frühstück", "Desayuno de sushi"), l("Mt Fuji day trip", "Ausflug zum Fuji", "Excursión al Fuji")])
        tokyo.note = l("Stay near a station. Keep the first afternoon light after the flight.",
                       "Nahe am Bahnhof wohnen. Den ersten Nachmittag nach dem Flug locker planen.",
                       "Alójate cerca de una estación. Tómate con calma la primera tarde tras el vuelo.")
        tokyo.labels = [l("Days 1–4", "Tag 1–4", "Días 1–4")]
        var kyotoBranch = branch(kyoto, "⛩️", ["Fushimi Inari", l("Bamboo grove", "Bambuswald", "Bosque de bambú"), l("Tea in Gion", "Tee in Gion", "Té en Gion")])
        kyotoBranch.labels = [l("Days 5–7", "Tag 5–7", "Días 5–7")]
        kyotoBranch.note = l("Go to Fushimi Inari before 8 am, when the paths are quiet.",
                             "Vor 8 Uhr zum Fushimi Inari – dann sind die Wege noch leer.",
                             "Ve a Fushimi Inari antes de las 8, cuando los caminos están tranquilos.")
        var osaka = branch("Osaka", "🍜", [l("Street food tour", "Streetfood-Tour", "Comida callejera"), l("Osaka Castle", "Burg Osaka", "Castillo de Osaka"), l("Nara deer park", "Hirschpark Nara", "Ciervos de Nara")])
        osaka.labels = [l("Days 8–10", "Tag 8–10", "Días 8–10")]
        var bookings = branch(l("Book ahead", "Vorab buchen", "Reservar antes"), "🎟️", [])
        bookings.children = [task(bookHotels, day: -2, hour: 12, done: true), task(trainTickets, day: 1, hour: 18), task(cookingClass, day: 3, hour: 14)]
        bookings.priority = 1
        let packing = branch(l("Pack light", "Leicht packen", "Equipaje ligero"), "🎒",
                             [l("Passport + copies", "Reisepass + Kopien", "Pasaporte + copias"), l("Walking shoes", "Bequeme Schuhe", "Calzado cómodo"),
                              l("Travel adapter", "Reiseadapter", "Adaptador de viaje"), "eSIM", l("Rain jacket", "Regenjacke", "Chubasquero")], collapsed: true)
        var budget = branch(l("Budget", "Budget", "Presupuesto"), "💴",
                            [l("Hotels · $1,200", "Hotels · 1.200 €", "Hoteles · 1200 €"), l("Trains · $450", "Züge · 450 €", "Trenes · 450 €"),
                             l("Food · $600", "Essen · 600 €", "Comida · 600 €"), l("Activities · $350", "Aktivitäten · 350 €", "Actividades · 350 €"),
                             l("Reserve · $600", "Reserve · 600 €", "Reserva · 600 €")], collapsed: true)
        budget.labels = [l("$3,200", "3.200 €", "3200 €")]
        var map = MindMap(id: travelID, root: MindNode(title: l("Japan in 10 days", "Japan in 10 Tagen", "Japón en 10 días"), children: [tokyo, kyotoBranch, osaka, bookings, packing, budget]),
                          isPinned: true, source: MapSource(kind: .topic, label: l("A first trip to Japan", "Die erste Reise nach Japan", "Un primer viaje a Japón")))
        map.style = "pills"
        map.palette = "vivid"
        map.root.look = NodeLook(shape: .rounded, fill: .solid, bold: true)
        map.links = [MapLink(from: map.root.children[0].id, to: map.root.children[1].id, label: l("Bullet train · 2h 15m", "Shinkansen · 2 Std. 15 Min.", "Tren bala · 2 h 15 min"))]
        return map
    }

    private static func studyMap() -> MindMap {
        var light = branch(lightReactions, "☀️", [l("In the thylakoids", "In den Thylakoiden", "En los tilacoides"), l("Light splits water", "Licht spaltet Wasser", "La luz rompe el agua"), "O₂ + ATP + NADPH"])
        light.note = l("Light energy is converted into chemical energy. Oxygen comes from water.",
                       "Lichtenergie wird in chemische Energie umgewandelt. Der Sauerstoff stammt aus dem Wasser.",
                       "La energía de la luz se convierte en energía química. El oxígeno procede del agua.")
        light.labels = [l("Key concept", "Kernbegriff", "Concepto clave")]
        var calvin = branch(l("Calvin cycle", "Calvin-Zyklus", "Ciclo de Calvin"), "🔄", [l("In the stroma", "Im Stroma", "En el estroma"), l("CO₂ → sugars", "CO₂ → Zucker", "CO₂ → azúcares"), l("Uses ATP + NADPH", "Nutzt ATP + NADPH", "Usa ATP + NADPH")])
        calvin.note = l("RuBisCO fixes carbon dioxide. ATP and NADPH power the production of G3P, used to make sugars.",
                        "RuBisCO bindet CO₂. ATP und NADPH treiben die Bildung von G3P an, aus dem Zucker entsteht.",
                        "La RuBisCO fija el CO₂. El ATP y el NADPH impulsan la producción de G3P, con el que se fabrican azúcares.")
        calvin.labels = [l("Exam topic", "Prüfungsthema", "Tema de examen")]
        // The equation's long formula would run off a phone; the rate's factors fit.
        let equation = branch(l("The overall equation", "Die Gesamtgleichung", "La ecuación global"), "🧪",
                              ["6CO₂ + 6H₂O → C₆H₁₂O₆ + 6O₂", l("Needs light and chlorophyll", "Braucht Licht und Chlorophyll", "Necesita luz y clorofila")], collapsed: true)
        let rate = branch(l("What affects the rate", "Was die Rate beeinflusst", "Qué afecta a la velocidad"), "🌡️", [l("Light", "Licht", "Luz"), l("CO₂ level", "CO₂-Gehalt", "Nivel de CO₂"), l("Temperature", "Temperatur", "Temperatura")])
        let matters = branch(l("Why it matters", "Warum das wichtig ist", "Por qué importa"), "🌍",
                             [l("The oxygen we breathe", "Der Sauerstoff, den wir atmen", "El oxígeno que respiramos"), l("The start of food chains", "Der Anfang der Nahrungsketten", "El inicio de las cadenas alimentarias"),
                              l("Takes CO₂ out of the air", "Holt CO₂ aus der Luft", "Retira CO₂ del aire")], collapsed: true)
        var prep = branch(l("Exam prep", "Prüfungsvorbereitung", "Preparar el examen"), "📅", [], collapsed: true)
        prep.children = [task(notesChapter, day: 0, hour: 10, done: true), task(reviewLight, day: 0, hour: 14), task(l("Solve 10 practice problems", "10 Übungsaufgaben lösen", "Hacer 10 ejercicios"), day: 0, hour: 17),
                         task(labReport, day: -1, hour: 18), task(practiceTest, day: 2, hour: 16)]
        var map = MindMap(id: studyID, root: MindNode(title: l("Photosynthesis", "Fotosynthese", "Fotosíntesis"), children: [light, calvin, equation, rate, matters, prep]), isPinned: true,
                          source: MapSource(kind: .topic, label: l("Photosynthesis: exam prep", "Fotosynthese: Prüfungsvorbereitung", "Fotosíntesis: preparar el examen")))
        map.style = "pills"
        map.palette = "forest"
        return map
    }

    private static func podcastMap() -> MindMap {
        let concept = branch(l("The show", "Die Show", "El programa"), "🎙️", [l("Home cooks", "Hobbyköche", "Cocineros caseros"), l("20-minute episodes", "20-Minuten-Folgen", "Episodios de 20 minutos"),
                                                                        l("One recipe + one story", "Ein Rezept + eine Geschichte", "Una receta + una historia")], collapsed: true)
        var episodes = branch(l("Season one", "Staffel eins", "Temporada 1"), "🍋", [l("The perfect pantry", "Der perfekte Vorrat", "La despensa perfecta"), l("Sunday pasta", "Pasta am Sonntag", "Pasta de domingo"),
                                                                                  l("Cooking for friends", "Kochen für Freunde", "Cocinar para amigos")])
        episodes.labels = [l("6 episodes", "6 Folgen", "6 episodios")]
        var production = branch(l("Production", "Produktion", "Producción"), "🎧", [])
        production.children = [task(l("Write the trailer", "Trailer schreiben", "Escribir el tráiler"), day: 0, hour: 10, done: true), task(recordEpisode, day: 1, hour: 10),
                               task(l("Edit the first cut", "Rohschnitt bearbeiten", "Editar el primer montaje"), day: 2, hour: 18)]
        production.note = l("Record in a quiet room. Keep a backup track and leave ten seconds of room tone.",
                            "In einem ruhigen Raum aufnehmen. Eine Backup-Spur mitlaufen lassen und zehn Sekunden Raumton aufnehmen.",
                            "Graba en una habitación tranquila. Guarda una pista de respaldo y deja diez segundos de ambiente.")
        production.labels = [l("This week", "Diese Woche", "Esta semana")]
        var launch = branch(l("Share the show", "Show bekannt machen", "Dar a conocer el programa"), "📣", [])
        launch.children = [task(coverArt, day: -1, hour: 16), task(l("Invite the first guest", "Ersten Gast einladen", "Contactar al primer invitado"), day: 0, hour: 16),
                           task(l("Publish the trailer", "Trailer veröffentlichen", "Publicar el tráiler"), day: 4, hour: 12)]
        launch.priority = 1
        let kit = branch(l("Recording kit", "Aufnahme-Set", "Equipo de grabación"), "🎚️", [l("USB microphone", "USB-Mikrofon", "Micrófono USB"), l("Closed-back headphones", "Geschlossene Kopfhörer", "Auriculares cerrados"),
                                                                                     l("Quiet room", "Ruhiger Raum", "Habitación tranquila"), l("Backup recording", "Backup-Aufnahme", "Grabación de respaldo")], collapsed: true)
        let review = branch(l("After each episode", "Nach jeder Folge", "Tras cada episodio"), "📝", [l("Collect listener questions", "Hörerfragen sammeln", "Recoger preguntas de oyentes"),
                                                                                                  l("Review the recording", "Aufnahme anhören", "Revisar la grabación"), l("Choose the next recipe", "Nächstes Rezept wählen", "Elegir la próxima receta")], collapsed: true)
        var map = MindMap(id: podcastID, root: MindNode(title: l("Cooking podcast", "Koch-Podcast", "Pódcast de cocina"), children: [concept, episodes, production, launch, kit, review]),
                          isPinned: false, source: MapSource(kind: .topic, label: l("A six-episode cooking podcast", "Ein Koch-Podcast mit sechs Folgen", "Un pódcast de cocina de seis episodios")))
        map.palette = "sunset"
        map.style = "pills"
        return map
    }

    // A small map for the Library: a title, its branches and a few ideas under each.
    private static func extra(_ id: Int, _ title: String, _ palette: String, _ branches: [(String, String, [String])], daysAgo: Int) -> MindMap {
        var map = MindMap(id: UUID(uuidString: String(format: "C0150000-0000-4000-8000-0000000001%02d", id))!,
                          root: MindNode(title: title, children: branches.map { branch($0.0, $0.1, $0.2) }))
        map.palette = palette
        map.style = "pills"
        map.updatedAt = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        map.createdAt = map.updatedAt
        return map
    }

    // The Japan trip gets an AI picture of Mt Fuji on its day trip (a drawing; no photo is shipped).
    @MainActor
    private static func addPicture(to map: inout MindMap) {
        guard map.id == travelID else { return }
        let size = CGSize(width: 960, height: 600)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            let sky = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
                UIColor(red: 0.98, green: 0.62, blue: 0.48, alpha: 1).cgColor,
                UIColor(red: 0.99, green: 0.83, blue: 0.67, alpha: 1).cgColor,
                UIColor(red: 0.72, green: 0.80, blue: 0.93, alpha: 1).cgColor,
            ] as CFArray, locations: [0, 0.55, 1])!
            cg.drawLinearGradient(sky, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            UIColor(red: 0.95, green: 0.33, blue: 0.30, alpha: 0.95).setFill()
            cg.fillEllipse(in: CGRect(x: 640, y: 70, width: 150, height: 150))
            func mountain(_ points: [CGPoint], _ color: UIColor) {
                let path = UIBezierPath()
                path.move(to: points[0])
                points.dropFirst().forEach { path.addLine(to: $0) }
                path.close()
                color.setFill()
                path.fill()
            }
            // Mt Fuji: the cone, then its snow cap with a ragged edge.
            mountain([CGPoint(x: 40, y: 600), CGPoint(x: 400, y: 165), CGPoint(x: 560, y: 165), CGPoint(x: 920, y: 600)],
                     UIColor(red: 0.31, green: 0.36, blue: 0.55, alpha: 1))
            mountain([CGPoint(x: 300, y: 285), CGPoint(x: 400, y: 165), CGPoint(x: 560, y: 165), CGPoint(x: 660, y: 285),
                      CGPoint(x: 610, y: 270), CGPoint(x: 575, y: 300), CGPoint(x: 530, y: 268), CGPoint(x: 480, y: 305),
                      CGPoint(x: 430, y: 268), CGPoint(x: 385, y: 300), CGPoint(x: 350, y: 270)], .white)
            mountain([CGPoint(x: 0, y: 600), CGPoint(x: 0, y: 470), CGPoint(x: 200, y: 420), CGPoint(x: 420, y: 500),
                      CGPoint(x: 640, y: 440), CGPoint(x: 960, y: 500), CGPoint(x: 960, y: 600)],
                     UIColor(red: 0.20, green: 0.42, blue: 0.40, alpha: 1))
        }
        guard let data = image.jpegData(compressionQuality: 0.92), let stored = MapStore.shared.storeImage(data, isAI: true) else { return }
        _ = map.root.update(map.root.children[0].children[3].id) { $0.image = stored }
    }

    @MainActor
    static func install(_ map: inout MindMap) {
        addPicture(to: &map)
        installSources(into: &map)
        MapStore.shared.save(map)
        if withLibrary { installLibrary(around: map) }
    }

    // The Library and Today: the three topics, a few other maps and both presentations; the day's
    // tasks come from three different maps.
    @MainActor
    private static func installLibrary(around current: MindMap) {
        var maps = ["travel", "study", "podcast"].map { map($0) }.filter { $0.id != current.id }
        maps += [
            extra(1, l("Half marathon · 12 weeks", "Halbmarathon · 12 Wochen", "Media maratón · 12 semanas"), "ocean", [
                (l("Weekly runs", "Läufe pro Woche", "Carreras semanales"), "🏃", [l("Easy runs", "Lockere Läufe", "Rodajes suaves"), l("Intervals", "Intervalle", "Series"), l("Long run", "Langer Lauf", "Tirada larga")]),
                (l("Strength", "Kraft", "Fuerza"), "💪", [l("Core", "Rumpf", "Core"), l("Legs", "Beine", "Piernas")]),
                (l("Race day", "Renntag", "Día de carrera"), "🏁", ["5:30/km", l("Gels at 7 km", "Gel bei km 7", "Gel en el km 7")]),
            ], daysAgo: 1),
            extra(2, l("Moving to Lisbon", "Umzug nach Lissabon", "Mudanza a Lisboa"), "sunset", [
                (l("Find a flat", "Wohnung finden", "Buscar piso"), "🏠", ["Alfama", "Príncipe Real"]),
                (l("Paperwork", "Papierkram", "Papeleo"), "📄", ["NIF", l("Bank account", "Bankkonto", "Cuenta bancaria")]),
                (l("Move day", "Umzugstag", "Día de mudanza"), "📦", [l("Movers", "Umzugsfirma", "Mudanceros"), l("Utilities", "Strom & Internet", "Luz e internet")]),
            ], daysAgo: 3),
            extra(3, l("Spanish by summer", "Spanisch bis zum Sommer", "Inglés para el verano"), "vivid", [
                (l("Every day", "Jeden Tag", "Cada día"), "🗣️", [l("15 min app", "15 Min. App", "15 min de app"), l("One podcast", "Ein Podcast", "Un pódcast")]),
                (l("Grammar", "Grammatik", "Gramática"), "📘", [l("Past tenses", "Vergangenheit", "Pasados"), l("Subjunctive", "Subjuntivo", "Condicionales")]),
                (l("Practice", "Üben", "Práctica"), "☕", [l("Tandem partner", "Tandempartner", "Intercambio"), l("Order in Spanish", "Auf Spanisch bestellen", "Pedir en inglés")]),
            ], daysAgo: 6),
        ]
        for var map in maps {
            addPicture(to: &map)
            MapStore.shared.save(map)
        }
        // One day of tasks: done this morning, three more today, one overdue, two this week.
        func retime(_ id: UUID, _ times: [String: (Int?, Int, Bool)]) {
            guard var map = MapStore.shared.map(id) else { return }
            func walk(_ node: inout MindNode) {
                if node.isTask {
                    if let time = times[node.title] {
                        let calendar = Calendar.current
                        node.isDone = time.2
                        node.due = time.0.flatMap { day in
                            calendar.date(bySettingHour: time.1, minute: 0, second: 0, of: calendar.date(byAdding: .day, value: day, to: Date()) ?? Date())
                        }
                    } else {
                        node.due = nil
                        node.isDone = true
                    }
                }
                for index in node.children.indices { walk(&node.children[index]) }
            }
            walk(&map.root)
            MapStore.shared.save(map)
        }
        retime(studyID, [notesChapter: (0, 9, true), reviewLight: (0, 19, false), labReport: (-1, 18, false), practiceTest: (2, 16, false)])
        retime(podcastID, [recordEpisode: (0, 14, false), coverArt: (nil, 9, false)])
        retime(travelID, [bookHotels: (-2, 12, true), trainTickets: (0, 16, false), cookingClass: (3, 14, false)])
        var decks = [DemoStory.deck(), deck("podcast")]
        decks[0].id = UUID(uuidString: "C0150000-0000-4000-8000-000000000004")!
        decks.forEach { DeckStore.shared.save($0) }
    }

    @MainActor
    static func installSources(into map: inout MindMap) {
        guard topic == "study", map.id == studyID else { return }
        ProjectMaterialStore.shared.delete(map.id)
        let pages = [
            (l("Photosynthesis", "Fotosynthese", "Fotosíntesis"),
             l("Biology · Chapter 5\n\nPlants use light energy to turn carbon dioxide and water into sugars. Oxygen is released as a by-product.",
               "Biologie · Kapitel 5\n\nPflanzen nutzen Lichtenergie, um aus Kohlendioxid und Wasser Zucker herzustellen. Dabei wird Sauerstoff frei.",
               "Biología · Tema 5\n\nLas plantas usan la energía de la luz para convertir el dióxido de carbono y el agua en azúcares. Se libera oxígeno como subproducto.")),
            (l("The light reactions", "Die Lichtreaktion", "La fase luminosa"),
             l("Light reactions take place in the thylakoid membranes. Light splits water, releasing oxygen. Energy is stored in ATP and NADPH.",
               "Die Lichtreaktion findet in den Thylakoidmembranen statt. Licht spaltet Wasser, dabei wird Sauerstoff frei. Die Energie wird in ATP und NADPH gespeichert.",
               "La fase luminosa ocurre en las membranas de los tilacoides. La luz rompe el agua y se libera oxígeno. La energía se guarda en ATP y NADPH.")),
            (l("The Calvin cycle", "Der Calvin-Zyklus", "El ciclo de Calvin"),
             l("The Calvin cycle takes place in the stroma. RuBisCO fixes carbon dioxide. ATP and NADPH drive the production of G3P, which is used to make sugars.",
               "Der Calvin-Zyklus läuft im Stroma ab. RuBisCO bindet Kohlendioxid. ATP und NADPH treiben die Bildung von G3P an, aus dem Zucker entsteht.",
               "El ciclo de Calvin ocurre en el estroma. La RuBisCO fija el dióxido de carbono. El ATP y el NADPH impulsan la producción de G3P, que se usa para fabricar azúcares.")),
            (l("Check your understanding", "Teste dein Wissen", "Comprueba lo que sabes"),
             l("Compare the two stages: location, inputs and outputs. Explain where the released oxygen comes from. Identify the factors that limit the rate.",
               "Vergleiche beide Phasen: Ort, Ausgangsstoffe und Produkte. Erkläre, woher der Sauerstoff stammt. Nenne die Faktoren, die die Rate begrenzen.",
               "Compara las dos fases: lugar, entradas y salidas. Explica de dónde sale el oxígeno. Identifica los factores que limitan la velocidad.")),
        ]
        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { context in
            for (title, body) in pages {
                context.beginPage()
                (title as NSString).draw(at: CGPoint(x: 54, y: 70), withAttributes: [.font: UIFont.systemFont(ofSize: 32, weight: .bold), .foregroundColor: UIColor.black])
                (body as NSString).draw(in: CGRect(x: 54, y: 140, width: 504, height: 550), withAttributes: [.font: UIFont.systemFont(ofSize: 20), .foregroundColor: UIColor.darkGray])
            }
        }
        let name = l("Biology — Chapter 5.pdf", "Biologie – Kapitel 5.pdf", "Biología – Tema 5.pdf")
        if let original = try? OriginalStore.keep(data: data, ext: "pdf", name: name), let pdf = PDFDocument(data: data) {
            let id = UUID()
            let cut = SourceSegmenter.pdf(pdf, materialID: id, version: 1)
            var material = ProjectMaterial(kind: .document, title: name, draft: SourceDraft(materialID: id, original: original, text: cut.text, segments: cut.segments, pages: pages.count))
            let marker = l("thylakoid", "Thylakoid", "tilacoides")
            let light = cut.segments.filter { $0.text.contains(marker) }.map(\.id)
            let calvin = cut.segments.filter { $0.text.contains("RuBisCO") }.map(\.id)
            material.cite([map.root.children[0].id: light, map.root.children[1].id: calvin])
            ProjectMaterialStore.shared.add(material, to: map.id)
            map.root = map.root.withOrigin(.material(id))
            map.source = MapSource(kind: .document, label: name)
        }
    }

    // The assistant made this map from one request.
    static func chat(_ map: MindMap) -> [ChatMessage] {
        let request: String
        let reply: String
        switch topic {
        case "study":
            request = l("Make a study map from my biology notes on photosynthesis. My exam is on Friday.",
                        "Mach mir aus meinen Bio-Notizen zur Fotosynthese eine Lernkarte. Die Prüfung ist am Freitag.",
                        "Hazme un mapa de estudio con mis apuntes de biología sobre la fotosíntesis. El examen es el viernes.")
            reply = l("Here’s chapter 5 as a map: both stages, the equation, what affects the rate — and a plan for the week.",
                      "Hier ist Kapitel 5 als Karte: beide Phasen, die Gleichung, was die Rate beeinflusst – und ein Plan für die Woche.",
                      "Aquí tienes el tema 5 en un mapa: las dos fases, la ecuación, qué afecta a la velocidad y un plan para la semana.")
        case "podcast":
            request = l("Plan a cooking podcast with six episodes, a recording setup and a launch checklist.",
                        "Plane einen Koch-Podcast mit sechs Folgen, einem Aufnahme-Setup und einer Checkliste für den Start.",
                        "Planifica un pódcast de cocina con seis episodios, el equipo de grabación y una lista para el lanzamiento.")
            reply = l("Here’s your season plan, with episode ideas, recording steps and a launch checklist.",
                      "Hier ist dein Staffelplan mit Folgenideen, Aufnahmeschritten und einer Checkliste für den Start.",
                      "Aquí tienes el plan de la temporada, con ideas de episodios, pasos de grabación y una lista para el lanzamiento.")
        default:
            request = l("Plan a 10-day trip to Japan for two: Tokyo, Kyoto and Osaka. Add what to book ahead and a packing list.",
                        "Plane 10 Tage Japan für zwei: Tokio, Kyoto und Osaka. Mit Buchungen und Packliste.",
                        "Planifica 10 días en Japón para dos: Tokio, Kioto y Osaka, con reservas y lista de equipaje.")
            reply = l("Here’s your trip on a map: three cities, the best day trips, what to book ahead and a light packing list.",
                      "Hier ist eure Reise als Karte: drei Städte, die besten Ausflüge, Buchungen und eine leichte Packliste.",
                      "Aquí tienes el viaje en un mapa: tres ciudades, las mejores excursiones, reservas y equipaje ligero.")
        }
        return [
            ChatMessage(role: .user, text: request),
            ChatMessage(role: .assistant, text: reply, action: ChatAction(kind: .mapCreated, mapID: map.id, mapTitle: map.title))
        ]
    }

    // Asking Minor to change the map: new ideas, then pictures for the cities.
    static func agentChat(_ map: MindMap) -> [ChatMessage] {
        [
            ChatMessage(role: .user, text: "@\(map.title) " + l("add a day trip to Hiroshima and Miyajima", "füge einen Ausflug nach Hiroshima und Miyajima hinzu", "añade una excursión a Hiroshima y Miyajima"),
                        maps: [MapMention(id: map.id, title: map.title)], mapText: "…"),
            ChatMessage(role: .assistant, text: "", action: ChatAction(kind: .edited, mapID: map.id, mapTitle: map.title, summary: L("+4 ideas") + " · " + L("1 changed"))),
            ChatMessage(role: .user, text: l("Add a picture to every city", "Füge zu jeder Stadt ein Bild hinzu", "Añade una imagen a cada ciudad")),
            ChatMessage(role: .assistant, text: "", action: ChatAction(kind: .images, mapID: map.id, mapTitle: map.title, imageNodes: Array(map.root.children.prefix(3).map(\.id)))),
        ]
    }

    // Plan My Day: today's tasks attached, and Minor's plan for them.
    static func planDay() -> [ChatMessage] {
        var ask = ChatMessage(role: .user, text: l("Plan my day. I have about four free hours after 1 pm.",
                                                   "Plane meinen Tag. Ab 13 Uhr habe ich etwa vier Stunden frei.",
                                                   "Planifica mi día. Tengo unas cuatro horas libres a partir de las 13:00."))
        ask.tasksText = [recordEpisode, trainTickets, reviewLight, coverArt].joined(separator: " · ")
        let plan = l("""
        Here’s a calm plan for your afternoon:

        **1:30 PM · \(recordEpisode)** — 90 minutes in the quiet room. Do a 30-second test take first.

        **3:30 PM · Short break** — a walk before the next block.

        **4:00 PM · \(trainTickets)** — 20 minutes. Compare the JR Pass with single tickets for Tokyo → Kyoto → Osaka.

        **7:00 PM · \(reviewLight)** — 30 minutes, then try the five-question quiz.

        The cover art is overdue. Tomorrow at 9 AM would clear it before the trailer goes out.
        """, """
        Hier ist ein entspannter Plan für deinen Nachmittag:

        **13:30 · \(recordEpisode)** — 90 Minuten im ruhigen Raum. Mach vorher eine Testaufnahme von 30 Sekunden.

        **15:30 · Kurze Pause** — ein Spaziergang vor dem nächsten Block.

        **16:00 · \(trainTickets)** — 20 Minuten. Vergleich den JR Pass mit Einzeltickets für Tokio → Kyoto → Osaka.

        **19:00 · \(reviewLight)** — 30 Minuten, danach das Quiz mit fünf Fragen.

        Das Cover ist überfällig. Morgen um 9 Uhr wäre es fertig, bevor der Trailer rausgeht.
        """, """
        Aquí tienes un plan tranquilo para tu tarde:

        **13:30 · \(recordEpisode)** — 90 minutos en la habitación tranquila. Haz antes una prueba de 30 segundos.

        **15:30 · Descanso** — un paseo antes del siguiente bloque.

        **16:00 · \(trainTickets)** — 20 minutos. Compara el JR Pass con billetes sueltos para Tokio → Kioto → Osaka.

        **19:00 · \(reviewLight)** — 30 minutos y después el test de cinco preguntas.

        La portada va con retraso. Mañana a las 9:00 la tendrías lista antes de publicar el tráiler.
        """)
        return [ask, ChatMessage(role: .assistant, text: plan)]
    }

    // Improve Map's suggestion for the focused idea, shown before it is applied.
    static func proposal(_ map: MindMap) -> (command: String, ideas: [String])? {
        switch topic {
        case "study": return (l("Add what the exam usually asks", "Ergänze typische Prüfungsfragen", "Añade lo que suele caer en el examen"),
                              [l("Where each stage happens", "Wo jede Phase abläuft", "Dónde ocurre cada fase"), l("Inputs and outputs", "Ausgangsstoffe und Produkte", "Entradas y salidas")])
        case "podcast": return (l("Make the recording day easier", "Mach den Aufnahmetag leichter", "Haz más fácil el día de grabación"),
                                [l("Warm up with a test take", "Mit einer Testaufnahme starten", "Calentar con una toma de prueba"), l("Mark mistakes with a clap", "Fehler mit einem Klatschen markieren", "Marcar errores con una palmada")])
        default: return (l("Add hidden gems in Kyoto", "Ergänze Geheimtipps in Kyoto", "Añade joyas ocultas de Kioto"),
                         [l("Nishiki Market lunch", "Mittagessen am Nishiki-Markt", "Comer en el mercado Nishiki"), l("Philosopher’s Path", "Philosophenweg", "Camino del Filósofo"),
                          l("Kiyomizu-dera at dawn", "Kiyomizu-dera bei Sonnenaufgang", "Kiyomizu-dera al amanecer")])
        }
    }

    // Next Steps for the focused idea.
    static var nextSteps: [(String, String, Bool)] {
        switch topic {
        case "study": return [(l("Redraw the light reactions from memory", "Lichtreaktion aus dem Kopf aufzeichnen", "Dibujar la fase luminosa de memoria"), l("Ten minutes, then check the map", "Zehn Minuten, dann mit der Karte vergleichen", "Diez minutos y luego revisa el mapa"), true),
                              (l("Explain the Calvin cycle out loud", "Den Calvin-Zyklus laut erklären", "Explicar el ciclo de Calvin en voz alta"), "", true),
                              (l("Do the five-question quiz", "Das Quiz mit fünf Fragen machen", "Hacer el test de cinco preguntas"), l("Before Friday", "Vor Freitag", "Antes del viernes"), false)]
        case "travel", nil: return [(l("Compare JR Pass and single tickets", "JR Pass und Einzeltickets vergleichen", "Comparar el JR Pass y billetes sueltos"), "Tokyo → Kyoto → Osaka", true),
                                    (l("Reserve a ryokan night in Kyoto", "Eine Nacht im Ryokan in Kyoto buchen", "Reservar una noche en un ryokan de Kioto"), "", true),
                                    (l("Ask the hotel about luggage forwarding", "Hotel nach Gepäckversand fragen", "Preguntar al hotel por el envío de maletas"), l("Travel light between cities", "Leicht zwischen den Städten reisen", "Viajar ligero entre ciudades"), false)]
        default: return [(l("Book a quiet room for Tuesday", "Ruhigen Raum für Dienstag buchen", "Reservar una sala tranquila el martes"), l("Two hours, soft furnishings", "Zwei Stunden, ohne Hall", "Dos horas, sin eco"), true),
                         (l("Test the microphone levels", "Mikrofonpegel testen", "Probar los niveles del micrófono"), l("Record thirty seconds first", "Vorher 30 Sekunden aufnehmen", "Graba antes 30 segundos"), true),
                         (l("Write five questions for the guest", "Fünf Fragen für den Gast schreiben", "Escribir cinco preguntas para el invitado"), l("Send them the day before", "Am Vortag schicken", "Envíalas el día antes"), false)]
        }
    }

    // The quiz on photosynthesis: the third question just answered wrong (-demoQuiz), or all five
    // answered with that one mistake (-demoQuizResult).
    static func quiz(_ map: MindMap, finished: Bool = false) -> QuizProgress {
        func q(_ text: String, _ options: [String], _ answer: Int, _ why: String, _ branch: Int) -> MapService.QuizQuestion {
            .init(question: text, options: options, answer: answer, why: why, src: nil, nodeID: map.root.children[branch].id)
        }
        var progress = QuizProgress(questions: [
            q(l("Where do the light reactions happen?", "Wo findet die Lichtreaktion statt?", "¿Dónde ocurre la fase luminosa?"),
              [l("Thylakoid membranes", "Thylakoidmembran", "Membrana de los tilacoides"), l("Cell wall", "Zellwand", "Pared celular"), l("Cytoplasm", "Zytoplasma", "Citoplasma"), l("Nucleus", "Zellkern", "Núcleo")], 0,
              l("The thylakoid membranes contain the photosystems that capture light.", "In der Thylakoidmembran sitzen die Fotosysteme, die das Licht einfangen.", "En la membrana de los tilacoides están los fotosistemas que captan la luz."), 0),
            q(l("What powers the Calvin cycle?", "Was treibt den Calvin-Zyklus an?", "¿Qué impulsa el ciclo de Calvin?"),
              [l("ATP and NADPH", "ATP und NADPH", "ATP y NADPH"), l("Oxygen alone", "Nur Sauerstoff", "Solo oxígeno"), l("Glucose", "Glukose", "Glucosa"), l("Heat", "Wärme", "Calor")], 0,
              l("ATP supplies energy; NADPH supplies reducing power.", "ATP liefert Energie, NADPH die Reduktionskraft.", "El ATP aporta energía y el NADPH, poder reductor."), 1),
            q(l("Where does the released oxygen come from?", "Woher stammt der freigesetzte Sauerstoff?", "¿De dónde sale el oxígeno liberado?"),
              [l("Carbon dioxide", "Kohlendioxid", "Dióxido de carbono"), l("Water", "Wasser", "Agua"), l("Glucose", "Glukose", "Glucosa"), l("The soil", "Dem Boden", "El suelo")], 1,
              l("Light splits water during the light reactions, releasing oxygen as a by-product.", "In der Lichtreaktion spaltet Licht Wasser – dabei wird Sauerstoff frei.", "La luz rompe el agua en la fase luminosa y se libera oxígeno."), 0),
            q(l("Where does the Calvin cycle happen?", "Wo läuft der Calvin-Zyklus ab?", "¿Dónde ocurre el ciclo de Calvin?"),
              [l("In the stroma", "Im Stroma", "En el estroma"), l("In the nucleus", "Im Zellkern", "En el núcleo"), l("In the cell wall", "In der Zellwand", "En la pared celular"), l("In the roots only", "Nur in den Wurzeln", "Solo en las raíces")], 0,
              l("The Calvin cycle takes place in the stroma of the chloroplast.", "Der Calvin-Zyklus läuft im Stroma des Chloroplasten ab.", "El ciclo de Calvin tiene lugar en el estroma del cloroplasto."), 1),
            q(l("Which factor can limit photosynthesis?", "Welcher Faktor kann die Fotosynthese begrenzen?", "¿Qué factor puede limitar la fotosíntesis?"),
              [l("Light intensity", "Lichtintensität", "Intensidad de la luz"), l("Leaf age alone", "Nur das Blattalter", "Solo la edad de la hoja"), l("Gravity", "Schwerkraft", "La gravedad"), l("Sound", "Schall", "El sonido")], 0,
              l("Light intensity, carbon dioxide and temperature can limit the rate.", "Lichtintensität, CO₂ und Temperatur können die Rate begrenzen.", "La luz, el CO₂ y la temperatura pueden limitar la velocidad."), 3)
        ])
        progress.current = finished ? 5 : 2
        progress.answers = finished ? [0: 0, 1: 0, 2: 0, 3: 0, 4: 0] : [0: 0, 1: 0, 2: 0]
        return progress
    }

    static func deck() -> Deck { deck(topic ?? "podcast") }

    static func deck(_ topic: String) -> Deck {
        if topic == "study" { return DemoStory.deck() }
        let show = l("The Weekend Table", "Wochenendküche", "La mesa del finde")
        var cover = Slide(layout: .cover, title: show, subtitle: l("A cooking podcast for curious home cooks", "Ein Koch-Podcast für neugierige Hobbyköche", "Un pódcast de cocina para cocineros curiosos"))
        cover.notes = l("Introduce the idea: a friendly twenty-minute show with one recipe and one story in every episode. The first season has six episodes.",
                        "Stell die Idee vor: eine entspannte 20-Minuten-Show mit einem Rezept und einer Geschichte pro Folge. Die erste Staffel hat sechs Folgen.",
                        "Presenta la idea: un programa cercano de veinte minutos con una receta y una historia en cada episodio. La primera temporada tiene seis episodios.")
        var badge = SlideElement.new(.shape)
        badge.text = l("SEASON ONE", "STAFFEL EINS", "TEMPORADA 1"); badge.fontSize = 23; badge.bold = true
        badge.x = 860; badge.y = 60; badge.w = 320; badge.h = 58
        badge.fill = "#E6BD83"; badge.color = "#302223"
        cover.elements = [badge]
        var concept = Slide(layout: .twoColumns, title: l("One recipe. One story.", "Ein Rezept. Eine Geschichte.", "Una receta. Una historia."))
        concept.columns = [
            SlideColumn(title: l("FOR THE LISTENER", "FÜR DIE HÖRER", "PARA QUIEN ESCUCHA"), bullets: [l("A dish worth trying", "Ein Gericht zum Nachkochen", "Un plato que apetece probar"), l("A useful kitchen habit", "Ein nützlicher Küchentrick", "Un truco útil de cocina"), l("A story to share", "Eine Geschichte zum Weitererzählen", "Una historia para compartir")]),
            SlideColumn(title: l("FOR EACH EPISODE", "IN JEDER FOLGE", "EN CADA EPISODIO"), bullets: [l("A warm introduction", "Ein herzlicher Einstieg", "Una presentación cercana"), l("A practical recipe", "Ein praktisches Rezept", "Una receta práctica"), l("One listener question", "Eine Hörerfrage", "Una pregunta de un oyente")])]
        concept.notes = l("Keep the promise small and clear. Each episode should leave the listener with something they want to cook.",
                          "Halte das Versprechen klein und klar. Nach jeder Folge soll man etwas nachkochen wollen.",
                          "Una promesa pequeña y clara. Cada episodio debe dejar al oyente con ganas de cocinar algo.")
        var process = SlideDiagram()
        process.kind = .process
        for (label, icon) in [(l("Outline", "Konzept", "Guion"), "pencil"), (l("Record", "Aufnehmen", "Grabar"), "mic"), (l("Edit", "Schneiden", "Editar"), "waveform"), (l("Publish", "Hochladen", "Publicar"), "paperplane")] {
            let id = process.insertStep(after: process.allItems.last?.id, label: label)
            process.updateNode(id) { $0.icon = icon }
        }
        var how = Slide(layout: .diagram, title: l("From recipe to episode", "Vom Rezept zur Folge", "De la receta al episodio"))
        how.diagram = process
        how.notes = l("Write a short outline, record in a quiet room, remove distractions in the edit, then publish with the recipe in the show notes.",
                      "Schreib ein kurzes Konzept, nimm in einem ruhigen Raum auf, schneide Störungen heraus und veröffentliche die Folge mit dem Rezept in den Shownotes.",
                      "Escribe un guion breve, graba en una habitación tranquila, quita las distracciones al editar y publica con la receta en las notas del episodio.")
        var season = Slide(layout: .timeline, title: l("Your first three episodes", "Die ersten drei Folgen", "Los tres primeros episodios"))
        season.items = [SlideItem(title: l("01 · The perfect pantry", "01 · Der perfekte Vorrat", "01 · La despensa perfecta"), detail: l("Build a small, useful set of staples.", "Ein kleiner, nützlicher Grundvorrat.", "Unos básicos pequeños y útiles.")),
                        SlideItem(title: l("02 · Sunday pasta", "02 · Pasta am Sonntag", "02 · Pasta de domingo"), detail: l("One sauce, three easy variations.", "Eine Soße, drei einfache Varianten.", "Una salsa, tres variantes fáciles.")),
                        SlideItem(title: l("03 · Cooking for friends", "03 · Kochen für Freunde", "03 · Cocinar para amigos"), detail: l("Plan a relaxed dinner for four.", "Ein entspanntes Essen für vier.", "Una cena tranquila para cuatro."))]
        season.notes = l("Start with topics that solve a familiar problem. Ask listeners which pantry ingredient they use most.",
                         "Starte mit Themen, die ein bekanntes Problem lösen. Frag die Hörer, welche Zutat sie am häufigsten nutzen.",
                         "Empieza por temas que resuelvan un problema conocido. Pregunta qué ingrediente de la despensa usan más.")
        var kit = Slide(layout: .table, title: l("Keep the setup simple", "Halte das Setup einfach", "Un equipo sencillo"))
        kit.table = [[l("WHAT", "WAS", "QUÉ"), l("WHY", "WARUM", "POR QUÉ")], [l("USB microphone", "USB-Mikrofon", "Micrófono USB"), l("Clear, close sound", "Klarer, naher Klang", "Sonido claro y cercano")],
                     [l("Headphones", "Kopfhörer", "Auriculares"), l("Hear noise while recording", "Störgeräusche sofort hören", "Oír el ruido al grabar")],
                     [l("Soft furnishings", "Weiche Möbel", "Textiles"), l("Reduce room echo", "Weniger Raumhall", "Menos eco")],
                     [l("Backup track", "Backup-Spur", "Pista de respaldo"), l("Keep the session safe", "Die Aufnahme absichern", "La sesión, a salvo")]]
        kit.notes = l("A quiet room matters more than a complicated setup. Test a short recording before every session.",
                      "Ein ruhiger Raum zählt mehr als teure Technik. Mach vor jeder Session eine kurze Testaufnahme.",
                      "Una sala tranquila importa más que un equipo complicado. Haz una prueba corta antes de cada sesión.")
        var checklist = Slide(layout: .bullets, title: l("Before you press Publish", "Bevor du veröffentlichst", "Antes de publicar"),
                              bullets: [l("Listen to the final cut", "Endschnitt anhören", "Escucha el montaje final"), l("Write the recipe and show notes", "Rezept und Shownotes schreiben", "Escribe la receta y las notas"),
                                        l("Check the title and cover art", "Titel und Cover prüfen", "Revisa el título y la portada"), l("Schedule the next episode", "Nächste Folge planen", "Programa el siguiente episodio")])
        checklist.notes = l("Use the same checklist every time. A repeatable process keeps production manageable.",
                            "Nutze jedes Mal dieselbe Checkliste. Ein fester Ablauf hält die Produktion überschaubar.",
                            "Usa siempre la misma lista. Un proceso repetible mantiene la producción bajo control.")
        var closing = Slide(layout: .closing, title: l("Make something worth sharing.", "Mach etwas, das man teilen will.", "Haz algo que merezca compartirse."),
                            subtitle: l("First up: The Perfect Pantry", "Als Erstes: Der perfekte Vorrat", "Primero: La despensa perfecta"))
        closing.notes = l("Close with one clear next step: record the trailer, then test the first episode with a friend.",
                          "Schließe mit einem klaren nächsten Schritt: Trailer aufnehmen, dann die erste Folge mit einem Freund testen.",
                          "Cierra con un siguiente paso claro: grabar el tráiler y probar el primer episodio con un amigo.")
        var deck = Deck(title: show, slides: [cover, concept, how, season, kit, checklist, closing], theme: .sunset)
        deck.id = UUID(uuidString: "C0150000-0000-4000-8000-000000000003")!
        deck.sourceMapID = podcastID
        deck.look = DeckLook(name: l("Warm editorial", "Warm & redaktionell", "Editorial cálido"), background: SlideBackground(kind: .gradient, colors: ["#291E30", "#50363C"], angle: 135), accent: "#E6BD83", palette: ["#E6BD83", "#B6CDA3", "#D7A6B7", "#A2BCD5"], glow: false)
        deck.brand = DeckBrand(logo: nil, corner: .topRight, size: 64, onCover: true, footer: l("THE WEEKEND TABLE · SEASON ONE", "WOCHENENDKÜCHE · STAFFEL EINS", "LA MESA DEL FINDE · TEMPORADA 1"), showNumbers: true)
        return deck
    }
}
#endif
