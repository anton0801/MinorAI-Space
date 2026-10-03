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
    static func make() -> MindMap {
        func node(_ title: String, _ children: [String] = []) -> MindNode {
            MindNode(title: title, children: children.map { MindNode(title: $0) })
        }
        var audience = node("Audience", ["Students who use iPad", "Creators", "Small teams", "Researchers"])
        audience.isCollapsed = true
        var positioning = node("Positioning", ["AI first", "Simple by design", "Dark and focused"])
        positioning.isCollapsed = true
        let pricing = node("Pricing", ["Free · 3 maps", "Plus · $9.99", "PRO · $19.99", "Yearly · 2 months free"])
        var channels = node("Channels", ["App Store search", "TikTok demos", "Product Hunt"])
        channels.isCollapsed = true
        var timeline = node("Timeline", ["Beta in November", "Launch in January", "iPad in spring"])
        // Tasks with progress on the branch.
        for index in timeline.children.indices { timeline.children[index].isTask = true }
        timeline.children[0].isDone = true
        var risks = node("Risks", ["API costs"])
        risks.isCollapsed = true
        var risks2 = risks
        risks2.children.append(MindNode(title: "Most users try one or two strong models a week, so the allowance covers real use.", isCallout: true))
        risks2.children[0].priority = 1
        var pricing2 = pricing
        pricing2.link = "https://minorai.site/#pricing"
        let icons = ["🎯", "💡", "💰", "📣", "📅", "⚠️"]
        var branches = [audience, positioning, pricing2, channels, timeline, risks2]
        for index in branches.indices { branches[index].icon = icons[index] }
        let root = MindNode(title: "Launch plan", children: branches)
        var map = MindMap(id: UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!, root: root, isPinned: true,
                          source: MapSource(kind: .document, label: "Pitch deck.pdf"))
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-demoLayout"), args.indices.contains(i + 1) { map.layout = args[i + 1] }
        map.root.children[2].note = "Three tiers keep the choice simple."
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
            map.root.children[4].frame = "Q1 plan"
            map.links = [MapLink(from: map.root.children[2].id, to: map.root.children[3].id, label: "drives"),
                         MapLink(from: map.root.children[4].children[0].id, to: map.root.children[5].id)]
            map.root.children[5].children.append(MindNode(title: "Users want offline maps", isSuggestion: true))
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
        ChatMessage(role: .user, text: "How should I price a mind map app?"),
        ChatMessage(role: .assistant, text: """
        ## Simple pricing
        Keep **two paid tiers** and a free plan that shows the value fast:
        - **Free**: 3 maps a month
        - **Plus**: up to 300 maps a month and all sources
        - **PRO**: Xmind export and share links

        Offer a yearly plan with `2 months free`.
        """),
    ]

    // The assistant working with a map (-demoAgent): a mention, a change card and a pictures card.
    static func agentChat(_ map: MindMap) -> [ChatMessage] {
        [
            ChatMessage(role: .user, text: "@\(map.title) add a section about risks of launching too early",
                        maps: [MapMention(id: map.id, title: map.title)], mapText: "…"),
            ChatMessage(role: .assistant, text: "", action: ChatAction(kind: .edited, mapID: map.id, mapTitle: map.title, summary: L("+4 ideas") + " · " + L("1 changed"))),
            ChatMessage(role: .user, text: "Add pictures to every branch"),
            ChatMessage(role: .assistant, text: "", action: ChatAction(kind: .images, mapID: map.id, mapTitle: map.title, imageNodes: map.root.children.map(\.id))),
        ]
    }
}
#endif
