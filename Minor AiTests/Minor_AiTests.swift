//
//  Minor_AiTests.swift
//  Minor AiTests
//
//  Logic tests for the mind map model, layout, parsing and export.
//

import Foundation
import SwiftUI
import Testing
@testable import Minor_Ai

private func sampleMap() -> MindMap {
    func node(_ title: String, _ children: [MindNode] = []) -> MindNode { MindNode(title: title, children: children) }
    let root = node("Launch plan", [
        node("Audience", [node("Students"), node("Creators"), node("Small teams")]),
        node("Pricing", [node("Free · 3 maps"), node("Plus · $9.99", [node("Monthly"), node("Yearly")])]),
        node("Channels", [node("App Store"), node("TikTok")]),
        node("Timeline"),
        node("Risks", [node("API costs"), node("Competition"), node("A very long idea title that should wrap onto more than one line in the node")]),
    ])
    return MindMap(root: root)
}

struct TreeTests {
    @Test func pathParentAndCount() throws {
        let map = sampleMap()
        let yearly = try #require(map.root.children[1].children[1].children.last)
        let path = try #require(map.root.path(to: yearly.id))
        #expect(path.map(\.title) == ["Launch plan", "Pricing", "Plus · $9.99", "Yearly"])
        #expect(map.root.parent(of: yearly.id)?.title == "Plus · $9.99")
        #expect(map.nodeCount == 18)
    }

    @Test func updateAndRemove() {
        var map = sampleMap()
        let pricing = map.root.children[1]
        #expect(map.root.update(pricing.id) { $0.title = "Price" })
        #expect(map.root.node(pricing.id)?.title == "Price")
        let removed = map.root.remove(pricing.id)
        #expect(removed?.title == "Price")
        #expect(map.root.node(pricing.id) == nil)
        #expect(map.nodeCount == 13)
        #expect(map.root.remove(UUID()) == nil)
    }

    @Test func collapsedCountsHiddenDescendants() {
        var map = sampleMap()
        let pricing = map.root.children[1].id
        map.root.update(pricing) { $0.isCollapsed = true }
        let node = map.root.node(pricing)!
        #expect(node.visibleChildren.isEmpty)
        #expect(node.hiddenCount == 4)
    }

    @Test func branchColorsWrapAndInherit() {
        #expect(BranchColor.forBranch(at: 6) == .mint)
        #expect(BranchColor.forBranch(at: -1) == .coral)
        let map = sampleMap()
        let leaf = map.root.children[2].children[0]
        #expect(map.branchColor(for: leaf.id) == .lilac)
        #expect(map.branchColor(for: map.root.id) == nil)
    }

    @Test func apiConversionCollapsesDeepBranches() {
        let api = APINode(title: "Root", children: [
            APINode(title: "A", children: [APINode(title: "A1", children: [APINode(title: "A1a")])]),
        ])
        let root = api.toNode(aiAdded: false)
        #expect(root.isCollapsed == false)
        #expect(root.children[0].isCollapsed == false)
        #expect(root.children[0].children[0].isCollapsed == true)
        let roundTrip = APINode(root)
        #expect(roundTrip.children?.first?.children?.first?.title == "A1")
    }

    @Test func outlineIsIndentedMarkdown() {
        let outline = sampleMap().outline
        #expect(outline.hasPrefix("# Launch plan"))
        #expect(outline.contains("\n- Pricing\n  - Free · 3 maps\n  - Plus · $9.99\n    - Monthly"))
    }

    @Test func mapCodableRoundTrip() throws {
        var map = sampleMap()
        map.layout = "balanced"
        map.root.children[0].color = .sun
        map.root.children[0].note = "Who it is for"
        let data = try JSONEncoder().encode(map)
        let decoded = try JSONDecoder().decode(MindMap.self, from: data)
        #expect(decoded == map)
    }
}

struct LayoutTests {
    private func assertNoOverlaps(_ layout: MapLayout) {
        let frames = layout.nodes.map(\.frame)
        for i in frames.indices {
            for j in frames.indices where j > i {
                #expect(!frames[i].insetBy(dx: 1, dy: 1).intersects(frames[j].insetBy(dx: 1, dy: 1)),
                        "\(layout.nodes[i].title) overlaps \(layout.nodes[j].title)")
            }
        }
    }

    @Test func treeLayoutHasNoOverlapsAndGrowsRight() {
        let map = sampleMap()
        let layout = MapLayout(map: map)
        #expect(layout.nodes.count == map.nodeCount)
        assertNoOverlaps(layout)
        for node in layout.nodes {
            guard let parent = node.parentID.flatMap(layout.node) else { continue }
            #expect(node.frame.minX >= parent.frame.maxX + MapMetrics.levelGap - 0.5)
            #expect(layout.connector(to: node) != nil)
        }
        #expect(layout.nodes.allSatisfy { $0.frame.minX >= 0 && $0.frame.maxX <= layout.size.width })
        #expect(layout.nodes.allSatisfy { $0.frame.minY >= 0 && $0.frame.maxY <= layout.size.height })
    }

    @Test func balancedLayoutUsesBothSides() {
        let map = sampleMap()
        let layout = MapLayout(map: map, balanced: true)
        assertNoOverlaps(layout)
        let root = layout.node(map.root.id)!
        let levelOne = layout.nodes.filter { $0.level == 1 }
        #expect(levelOne.contains { $0.frame.maxX <= root.frame.minX })
        #expect(levelOne.contains { $0.frame.minX >= root.frame.maxX })
        #expect(layout.nodes.allSatisfy { $0.frame.minX >= 0 && $0.frame.maxX <= layout.size.width })
    }

    @Test func collapsedBranchesAreNotLaidOut() {
        var map = sampleMap()
        map.root.update(map.root.children[0].id) { $0.isCollapsed = true }
        let layout = MapLayout(map: map)
        #expect(layout.nodes.count == map.nodeCount - 3)
        #expect(layout.node(map.root.children[0].id)?.hiddenCount == 3)
    }

    @Test func subtreeAndHitTesting() {
        let map = sampleMap()
        let layout = MapLayout(map: map)
        let pricing = map.root.children[1]
        #expect(layout.subtree(pricing.id).count == 5)
        let frame = layout.node(pricing.id)!.frame
        #expect(layout.node(at: CGPoint(x: frame.midX, y: frame.midY))?.id == pricing.id)
        #expect(layout.node(at: CGPoint(x: frame.midX, y: frame.midY), excluding: [pricing.id]) == nil)
    }

    @Test func nodeSizesRespectLimits() {
        let long = String(repeating: "word ", count: 60)
        let branch = NodeStyle(level: 1).size(for: long)
        #expect(branch.width <= MapMetrics.nodeMaxWidth + 1)
        #expect(abs(branch.height - (2 * 21 + 20)) < 0.5)
        let root = NodeStyle(level: 0).size(for: "Hi")
        #expect(root.height >= MapMetrics.nodeMinHeight)
        let withIcons = NodeStyle(level: 2).size(for: "Short", icons: 2)
        #expect(withIcons.width > NodeStyle(level: 2).size(for: "Short").width + 39)
    }

    @Test func fitKeepsMapInsideChrome() {
        let content = CGSize(width: 1200, height: 900)
        let screen = CGSize(width: 393, height: 852)
        let insets = EdgeInsets(top: 110, leading: 16, bottom: 170, trailing: 16)
        let viewport = CanvasViewport.fit(content, in: screen, insets: insets)
        #expect(viewport.scale <= 1 && viewport.scale >= MapMetrics.zoomRange.lowerBound)
        #expect(viewport.offset.width >= 16 - 0.5)
        #expect(viewport.offset.height >= 110 - 0.5)
        #expect(viewport.offset.height + content.height * viewport.scale <= screen.height - 170 + 0.5)
    }
}

struct ParsingTests {
    @Test func ideasFromListReply() {
        let reply = """
        Here are some ideas:
        - **Freemium**: three maps a month
        * Student discount
        2. Yearly plan — save 15%
        Thanks!
        """
        #expect(NodeChatView.ideas(from: reply) == ["Freemium", "Student discount", "Yearly plan"])
    }

    @Test func ideasFallBackToFirstSentence() {
        #expect(NodeChatView.ideas(from: "Pricing should stay simple. Two tiers are enough.") == ["Pricing should stay simple"])
    }

    @Test func linkDetection() {
        #expect(CreateMapView.link(in: "https://example.com/article")?.host == "example.com")
        #expect(CreateMapView.link(in: "example.com/page")?.host == "example.com")
        #expect(CreateMapView.link(in: "photosynthesis for kids") == nil)
        #expect(CreateMapView.link(in: "read https://example.com now") == nil)
        #expect(CreateMapView.isYouTube(URL(string: "https://youtu.be/arj7oStGLkU")!))
        #expect(CreateMapView.isYouTube(URL(string: "https://m.youtube.com/watch?v=arj7oStGLkU")!))
        #expect(!CreateMapView.isYouTube(URL(string: "https://notyoutube.com.evil.io/x")!))
    }

    @Test func opmlEscapesAndParses() throws {
        var map = sampleMap()
        map.root.title = "R&D <plan> \"2027\""
        let opml = ExportSheetView.opml(map)
        #expect(opml.contains("R&amp;D &lt;plan&gt; &quot;2027&quot;"))
        let parser = XMLParser(data: Data(opml.utf8))
        #expect(parser.parse(), "OPML must be well-formed XML")
    }

    @Test func backendErrorCodes() {
        #expect(BackendError.from(code: "limit_reached", kind: "chats") == .limitReached(kind: "chats"))
        #expect(BackendError.from(code: "plan_required", kind: nil) == .planRequired)
        #expect(BackendError.from(code: "video_unreachable", kind: nil) == .linkUnreachable)
        #expect(BackendError.from(code: "something_new", kind: nil) == .server(code: "something_new"))
        #expect(BackendError.limitReached(kind: "maps").errorDescription?.isEmpty == false)
    }

    @Test func messageContentIncludesAttachedFile() {
        let message = ChatMessage(role: .user, text: "Summarize", fileName: "notes.txt", fileText: "Line one")
        #expect(message.contentForModel == "Summarize\n\nAttached file “notes.txt”:\nLine one")
        #expect(ChatMessage(role: .user, text: "Hi").contentForModel == "Hi")
    }

    @Test func conversationTitles() {
        #expect(Conversation.makeTitle(from: [ChatMessage(role: .user, text: "  ")]) == L("New chat"))
        #expect(Conversation.makeTitle(from: [ChatMessage(role: .user, text: "", images: [Data([1])])]) == L("Photo"))
        #expect(Conversation.makeTitle(from: [ChatMessage(role: .user, text: String(repeating: "a", count: 50))]).hasSuffix("…"))
    }

    @Test func modelCatalog() {
        #expect(AIModelCatalog.default.tier == .lite)
        #expect(AIModelCatalog.all.filter { $0.tier == .frontier }.map(\.apiModelID).sorted() == ["claude-fable-5-1", "gpt-6-astra"])
        // Usage multipliers grow with model strength.
        let byTier = Dictionary(grouping: AIModelCatalog.all, by: \.tier).mapValues { $0.map(\.usage).max() ?? 0 }
        #expect(byTier[.lite]! < byTier[.standard]! && byTier[.standard]! < byTier[.advanced]! && byTier[.advanced]! < byTier[.frontier]!)
        // Maps: no lite models; Opus needs Plus, the frontier models need PRO.
        #expect(!AIModelCatalog.mapModels.contains { $0.tier == .lite })
        #expect(AIModelCatalog.option(apiID: "claude-opus-5-5")?.mapPlan == .plus)
        #expect(AIModelCatalog.option(apiID: "gpt-6-astra")?.mapPlan == .pro)
        #expect(AIModelCatalog.defaultMap.mapPlan == .free)
    }

    @Test func localizationKeysHaveRussian() throws {
        let bundle = try #require(Bundle.main.path(forResource: "ru", ofType: "lproj").flatMap(Bundle.init(path:)))
        #expect(bundle.localizedString(forKey: "Start a Map", value: nil, table: nil) == "Новая карта")
        #expect(bundle.localizedString(forKey: "Monthly", value: nil, table: nil) == "Ежемесячно")
    }
}

struct EditMergeTests {
    @Test func keepsNotesIdsAndColorsOfSurvivingIdeas() throws {
        var map = sampleMap()
        let pricing = map.root.children[1]
        map.root.update(pricing.id) { $0.note = "Check competitors"; $0.color = .lilac; $0.isCollapsed = true }
        let edited = APINode(title: "Launch plan", children: [
            APINode(title: "Pricing", children: [APINode(title: "Free · 3 maps"), APINode(title: "Plus · $9.99"), APINode(title: "Team plan")]),
            APINode(title: "Audience"),
        ])
        let merged = map.root.merged(with: edited)
        let newPricing = try #require(merged.children.first)
        #expect(newPricing.id == pricing.id)
        #expect(newPricing.note == "Check competitors")
        #expect(newPricing.color == .lilac)
        #expect(newPricing.isCollapsed)
        #expect(newPricing.isAIAdded == false)
        #expect(newPricing.children.map(\.isAIAdded) == [false, false, true])
        #expect(merged.children.map(\.title) == ["Pricing", "Audience"])
        #expect(merged.node(map.root.children[3].id) == nil, "Timeline was removed by the edit")
    }

    @Test func renamedIdeaKeepsItsNoteByPosition() throws {
        var map = sampleMap()
        let timeline = map.root.children[3]
        map.root.update(timeline.id) { $0.note = "Q4" }
        let edited = APINode(title: "Launch plan", children: map.root.children.map { child in
            APINode(title: child.id == timeline.id ? "Roadmap" : child.title)
        })
        let merged = map.root.merged(with: edited)
        let renamed = try #require(merged.node(timeline.id))
        #expect(renamed.title == "Roadmap")
        #expect(renamed.note == "Q4")
    }

    @Test func matchingIgnoresCaseAndSpaces() {
        let map = sampleMap()
        let edited = APINode(title: "Launch plan", children: [APINode(title: "  pricing ")])
        #expect(map.root.merged(with: edited).children.first?.id == map.root.children[1].id)
    }

    @Test func editRepliesDecodeToTheirKind() throws {
        func decode(_ json: String) throws -> MapService.EditResult {
            try JSONDecoder().decode(MapService.EditReply.self, from: Data(json.utf8)).result()
        }
        guard case .question = try decode(#"{"question": true}"#) else { Issue.record("question"); return }
        guard case .images(let titles, let prompt) = try decode(#"{"images": ["Pricing", "Brand"], "prompt": "flat style"}"#) else { Issue.record("images"); return }
        #expect(titles == ["Pricing", "Brand"] && prompt == "flat style")
        guard case .map(let tree) = try decode(#"{"map": {"title": "Plan", "children": [{"title": "A", "task": true}]}}"#) else { Issue.record("map"); return }
        #expect(tree.children?.first?.task == true)
        #expect(throws: (any Error).self) { try decode("{}") }
    }

    @Test func picturesFindTheIdeasTheAINamed() {
        let map = sampleMap()
        let ids = MapEditorView.nodes(titled: ["  PRICING.", "Nothing like this", map.root.title], in: map.root)
        #expect(ids == [map.root.children[1].id, map.root.id])
    }

    @Test func fullyExpandedOpensEveryBranch() {
        var map = sampleMap()
        for child in map.root.children { map.root.update(child.id) { $0.isCollapsed = true } }
        #expect(map.fullyExpanded.root.children.allSatisfy { !$0.isCollapsed })
        #expect(map.fullyExpanded.root.count == map.root.count)
    }
}

struct DecodingTests {
    @Test func nodeWithMissingFieldsStillDecodes() throws {
        let json = #"{"title":"Root","children":[{"title":"Child"}]}"#
        let node = try JSONDecoder().decode(MindNode.self, from: Data(json.utf8))
        #expect(node.title == "Root")
        #expect(node.children.first?.title == "Child")
        #expect(node.note.isEmpty && !node.isCollapsed)
    }

    @Test func oneBrokenConversationDoesNotHideTheOthers() throws {
        let good = Conversation(title: "Hello", messages: [ChatMessage(role: .user, text: "Hi")])
        let encoder = JSONEncoder()
        let goodJSON = String(decoding: try encoder.encode(good), as: UTF8.self)
        let list = "[\(goodJSON), {\"id\": 42}]"
        let decoded = try JSONDecoder().decode([Lossy<Conversation>].self, from: Data(list.utf8)).compactMap(\.value)
        #expect(decoded.map(\.title) == ["Hello"])
    }

    @Test func oldMessagesWithoutModelDecode() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","role":"assistant","text":"Hi"}"#
        let message = try JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))
        #expect(message.model == nil)
    }

    @Test @MainActor func usagePeriodIsUTCYearMonth() {
        #expect(AccountStore.period.range(of: #"^\d{4}-\d{2}$"#, options: .regularExpression) != nil)
    }

    @Test func newBackendCodes() {
        #expect(BackendError.from(code: "map_too_large", kind: nil) == .mapTooLarge)
        #expect(BackendError.from(code: "ai_busy", kind: nil) == .busy)
        #expect(BackendError.planRequired.suggestsUpgrade)
        #expect(!BackendError.offline.suggestsUpgrade)
    }
}

struct NodeDetailsTests {
    @Test func newFieldsDecodeAndDefault() throws {
        let old = try JSONDecoder().decode(MindNode.self, from: Data(#"{"title":"Old"}"#.utf8))
        #expect(old.image == nil && old.icon == nil && !old.isTask && old.priority == nil && !old.isCallout)
        let json = #"{"title":"New","icon":"🎯","isTask":true,"isDone":true,"priority":7,"link":"https://a.b","isCallout":true,"image":{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","aspect":0.75,"isAI":true}}"#
        let node = try JSONDecoder().decode(MindNode.self, from: Data(json.utf8))
        #expect(node.icon == "🎯" && node.isTask && node.isDone && node.link == "https://a.b" && node.isCallout)
        #expect(node.priority == nil, "priority outside 1…3 is dropped")
        #expect(node.image?.aspect == 0.75 && node.image?.isAI == true)
    }

    @Test func editMergeKeepsPictureIconAndTask() throws {
        var map = sampleMap()
        let pricing = map.root.children[1]
        let picture = NodeImage(id: UUID(), aspect: 1, isAI: false)
        map.root.update(pricing.id) { $0.image = picture; $0.icon = "💰"; $0.isTask = true }
        let edited = APINode(title: "Launch plan", children: [APINode(title: "Pricing"), APINode(title: "Brand new", icon: "🚀")])
        let merged = map.root.merged(with: edited)
        let kept = try #require(merged.node(pricing.id))
        #expect(kept.image == picture && kept.icon == "💰" && kept.isTask, "fields the reply leaves out stay")
        #expect(merged.children.last?.icon == "🚀", "new ideas take the AI's icon")

        // A command can change or remove fields explicitly.
        var changed = APINode(title: "Pricing", icon: "🧾")
        changed.task = false
        changed.priority = 1
        changed.note = "Keep it simple"
        let edited2 = APINode(title: "Launch plan", children: [changed])
        let after = try #require(map.root.merged(with: edited2).node(pricing.id))
        #expect(after.icon == "🧾" && !after.isTask && after.priority == 1 && after.note == "Keep it simple")
        #expect(after.image == picture, "pictures are never changed by text edits")
    }

    @Test func longNotesSurviveAnUnchangedEdit() throws {
        var map = sampleMap()
        let pricing = map.root.children[1]
        let long = String(repeating: "Detail. ", count: 80)
        map.root.update(pricing.id) { $0.note = long }
        let sent = APINode(map.root)                       // what the AI receives
        let merged = map.root.merged(with: sent)           // the AI changed nothing
        #expect(merged.node(pricing.id)?.note == long)
    }

    @Test func taskProgressCountsDescendants() {
        var root = MindNode(title: "Plan", children: [
            MindNode(title: "A", isTask: true, isDone: true),
            MindNode(title: "B", children: [MindNode(title: "B1", isTask: true), MindNode(title: "B2", isTask: true, isDone: true)]),
        ])
        #expect(root.taskProgress.done == 2 && root.taskProgress.total == 3)
        root.update(root.children[1].children[0].id) { $0.isDone = true }
        #expect(root.taskProgress.done == 3)
    }

    @Test func createdPicturesStayInTheConversation() throws {
        let picture = ChatMessage(role: .assistant, text: "", images: [Data([1])], model: "image", imagePrompt: "A blue BMW M5 at night")
        #expect(picture.contentForModel.contains("A blue BMW M5 at night"), "the model knows what \"it\" refers to")
        let old = try JSONDecoder().decode(ChatMessage.self, from: Data(#"{"id":"\#(UUID().uuidString)","role":"assistant","text":"Hi"}"#.utf8))
        #expect(old.imagePrompt == nil && old.contentForModel == "Hi", "saved chats from before still load")
    }

    @Test func emojiIconsAreCleaned() {
        #expect(MindNode.cleanIcon("🎯") == "🎯")
        #expect(MindNode.cleanIcon("❤️") == "❤️")
        #expect(MindNode.cleanIcon("ab") == nil)
        #expect(MindNode.cleanIcon("1") == nil)
        #expect(MindNode.cleanIcon("🎯🚀") == nil)
    }

    @Test func pictureMakesANodeTaller() {
        let style = NodeStyle(level: 1)
        var node = MindNode(title: "Pricing")
        let plain = style.size(for: NodeDecor(node), title: node.title)
        node.image = NodeImage(id: UUID(), aspect: 0.75)
        let withPicture = style.size(for: NodeDecor(node), title: node.title)
        #expect(withPicture.height > plain.height + 100)
        #expect(withPicture.width >= style.imageNodeWidth)
    }
}

@MainActor
struct WorkspaceTests {
    @Test func refsAreShortAndStable() {
        let id = UUID(uuidString: "3F9A2C10-0000-4000-8000-000000000000")!
        #expect(Workspace.ref(id) == "m-3f9a2c")
    }

    @Test func indexShowsPinnedFirstWithProgress() {
        var first = sampleMap()
        first.root.update(first.root.children[0].children[0].id) { $0.isTask = true; $0.isDone = true }
        first.root.update(first.root.children[0].children[1].id) { $0.isTask = true }
        var pinned = MindMap(root: MindNode(title: "Pinned"))
        pinned.isPinned = true
        let index = Workspace.index([first, pinned])
        #expect(index.map(\.title) == ["Pinned", "Launch plan"])
        #expect(index[1].tasksDone == 1 && index[1].tasksTotal == 2 && index[1].ideas == first.nodeCount)
    }

    @Test func outlineFitsTheLimit() {
        var map = sampleMap()
        map.root.update(map.root.children[1].id) { $0.note = "Two paid tiers"; $0.priority = 1 }
        let full = Workspace.outline(of: map)
        #expect(full.contains("- Pricing (priority 1) — note: Two paid tiers"))
        #expect(full.contains("    - Monthly"), "nested ideas are indented")
        let short = Workspace.outline(of: map, limit: 160)
        #expect(short.count <= 200 && short.contains("more ideas"))
    }

    @Test func openTasksPutDueAndPriorityFirst() {
        var map = sampleMap()
        let ids = map.root.children.map(\.id)
        map.root.update(ids[0]) { $0.isTask = true; $0.priority = 3 }
        map.root.update(ids[1]) { $0.isTask = true; $0.priority = 1 }
        map.root.update(ids[2]) { $0.isTask = true; $0.due = Date(timeIntervalSince1970: 1_800_000_000) }
        map.root.update(ids[3]) { $0.isTask = true; $0.isDone = true }
        let text = Workspace.openTasks([map])
        let lines = text.split(separator: "\n").map(String.init)
        #expect(lines[0].contains("3 open and 1 done"))
        #expect(lines[1].contains("Channels") && lines[2].contains("Pricing") && lines[3].contains("Audience"))
    }

    @Test func diffCountsAddedChangedRemoved() {
        let map = sampleMap()
        var root = map.root
        root.children[0].title = "Users"
        root.children.removeLast()
        root.children.append(MindNode(title: "New"))
        root.children.append(MindNode(title: "Newer"))
        root.update(map.root.children[0].id) { $0.isCollapsed = true }
        let diff = MapDiff(old: map.root, new: root)
        #expect(diff.added == 2 && diff.changed == 1 && diff.removed == 4, "a removed branch counts its ideas")
        #expect(MapDiff(old: map.root, new: map.root).isEmpty)
    }

    @Test func mentionsFollowTheTypedText() {
        let maps = [MindMap(root: MindNode(title: "Spanish verbs")), MindMap(root: MindNode(title: "Launch plan"))]
        #expect(Mentions.query(in: "hi @spa", picked: []) == "spa")
        #expect(Mentions.query(in: "mail@spa", picked: []) == nil, "an @ inside a word is not a mention")
        #expect(Mentions.matches("spa", in: maps).map(\.title) == ["Spanish verbs"])
        #expect(Mentions.matches("", in: maps).count == 2)
        let text = Mentions.insert(maps[0], into: "add to @spa")
        #expect(text == "add to @Spanish verbs ")
        let picked = [MapMention(id: maps[0].id, title: "Spanish verbs")]
        #expect(Mentions.query(in: text, picked: picked) == nil, "a picked map closes the list")
        #expect(Mentions.used(picked, in: text) == picked)
        #expect(Mentions.used(picked, in: "add to") == [])
    }

    @Test func hiddenDataAndCardsReachTheModel() throws {
        let card = ChatMessage(role: .assistant, text: "", action: ChatAction(kind: .edited, mapID: UUID(), mapTitle: "Spanish", summary: "+3 ideas"))
        #expect(card.contentForModel.contains("Spanish") && card.contentForModel.contains("+3 ideas"))
        let mention = ChatMessage(role: .user, text: "rate it", mapText: "Map m-000000 \"Spanish\"")
        #expect(mention.contentForModel.hasPrefix("rate it") && mention.contentForModel.contains("App data"))
        let old = try JSONDecoder().decode(ChatMessage.self, from: Data(#"{"id":"\#(UUID().uuidString)","role":"user","text":"Hi"}"#.utf8))
        #expect(!old.isHidden && old.action == nil)
    }
}

struct StyleTests {
    @Test func colorsCarryOnToDescendants() {
        var map = sampleMap()
        let plus = map.root.children[1].children[1]
        map.root.update(plus.id) { $0.color = .red }
        let layout = MapLayout(map: map)
        #expect(layout.node(plus.id)?.color == .red)
        #expect(layout.node(plus.children[0].id)?.color == .red, "children take their parent's color")
        #expect(layout.node(map.root.children[1].children[0].id)?.color == BranchColor.forBranch(at: 1), "siblings keep the branch color")
        #expect(map.branchColor(for: plus.children[1].id) == .red)
    }

    @Test func paletteChangesDefaultBranchColors() {
        var map = sampleMap()
        map.palette = MapPalette.sunset.rawValue
        let layout = MapLayout(map: map)
        #expect(layout.node(map.root.children[0].id)?.color == .coral)
        #expect(layout.node(map.root.children[1].id)?.color == .orange)
        #expect(map.branchColor(for: map.root.children[1].children[0].id) == .orange)
    }

    @Test func looksDecodeTolerantly() throws {
        let json = #"{"title":"A","look":{"shape":"star","fill":"solid","size":"large","bold":true}}"#
        let node = try JSONDecoder().decode(MindNode.self, from: Data(json.utf8))
        #expect(node.look?.shape == .auto && node.look?.fill == .solid && node.look?.size == .large && node.look?.bold == true)
        let plain = try JSONDecoder().decode(MindNode.self, from: Data(#"{"title":"A","look":{}}"#.utf8))
        #expect(plain.look == nil, "a default look is stored as none")
        var map = MindMap(root: MindNode(title: "Root"))
        map.lines = "elbow"
        map.palette = "ocean"
        let decoded = try JSONDecoder().decode(MindMap.self, from: JSONEncoder().encode(map))
        #expect(decoded.lineStyle == .elbow && decoded.mapPalette == .ocean && decoded.canvasBackground == .dots)
    }

    @Test func shapesAndTextSizeChangeTheNodeSize() {
        var node = MindNode(title: "Pricing")
        func size() -> CGSize {
            let decor = NodeDecor(node)
            return NodeStyle(level: 1, look: decor.look).size(for: decor, title: node.title)
        }
        let plain = size()
        node.look = NodeLook(shape: .ellipse)
        #expect(size().width > plain.width + 20)
        node.look = NodeLook(shape: .diamond)
        #expect(size().height > plain.height * 1.4)
        node.look = NodeLook(size: .huge, bold: true)
        #expect(size().width > plain.width && size().height > plain.height)
    }

    @Test func lineStylesConnectTheSamePoints() throws {
        let map = sampleMap()
        let layout = MapLayout(map: map)
        let child = try #require(layout.node(map.root.children[0].id))
        let parent = try #require(layout.node(map.root.id))
        for style in LineStyle.allCases {
            let path = try #require(layout.connector(to: child, style: style))
            let box = path.boundingRect
            #expect(abs(box.minX - parent.frame.maxX) < 1 && abs(box.maxX - child.frame.minX) < 1, "\(style)")
        }
    }

    @Test func branchListsDescendantsWithDepth() {
        let map = sampleMap()
        let layout = MapLayout(map: map)
        let pricing = map.root.children[1]
        let branch = layout.branch(of: pricing.id)
        #expect(branch.first?.node.id == pricing.id && branch.first?.depth == 0)
        #expect(branch.map(\.depth).max() == 2)
        #expect(branch.count == pricing.count)
    }
}

struct SuggestionTests {
    @Test func improvementsAddOnlyNewIdeasAsSuggestions() {
        let map = sampleMap()
        // The AI changed a note, dropped a branch and added three ideas (one is a new branch).
        var reply = APINode(map.root)
        reply.children?[0].note = "Changed"
        reply.children?.removeLast()
        reply.children?[1].children?.append(APINode(title: "Student discount"))
        reply.children?.append(APINode(title: "Partners", children: [APINode(title: "Schools")]))
        let (root, added) = map.root.grafting(additionsFrom: reply)
        #expect(added == 3)
        #expect(root.children[0].note.isEmpty, "existing ideas stay as they were")
        #expect(root.children[1].children.last?.title == "Student discount" && root.children[1].children.last?.isSuggestion == true)
        #expect(root.children.contains { $0.title == "Risks" }, "dropped ideas stay")
        #expect(root.suggestionCount == 3)
        #expect(root.children.last?.title == "Partners" && root.children.last?.isSuggestion == true)
    }

    @Test func acceptingKeepsParentsAndDismissRemoves() throws {
        var root = sampleMap().root
        let branch = MindNode(title: "Partners", children: [MindNode(title: "Schools")]).asSuggestion
        root.children.append(branch)
        let child = try #require(branch.children.first)
        root.accept(child.id)
        #expect(root.node(branch.id)?.isSuggestion == false, "a kept idea keeps its parent")
        #expect(root.suggestionCount == 0)
        root.children.append(MindNode(title: "Maybe").asSuggestion)
        root.dismissAll()
        #expect(!root.children.contains { $0.title == "Maybe" })
    }
}

struct FrameAndLinkTests {
    @Test func framesMakeRoomAndEncloseTheirBranch() throws {
        var map = sampleMap()
        let plain = MapLayout(map: map)
        map.root.update(map.root.children[1].id) { $0.frame = "Money" }
        let framed = MapLayout(map: map)
        #expect(framed.size.height > plain.size.height)
        let group = try #require(framed.groups.first)
        for member in framed.branch(of: map.root.children[1].id) {
            #expect(group.rect.contains(member.node.frame), "the frame holds \(member.node.title)")
        }
        // Neighbors stay outside the frame.
        for sibling in [map.root.children[0], map.root.children[2]] {
            let frame = try #require(framed.node(sibling.id)?.frame)
            #expect(!group.rect.intersects(frame), "\(sibling.title) is outside")
        }
    }

    @Test func brokenLinksAreDropped() {
        var map = sampleMap()
        let a = map.root.children[0].id, b = map.root.children[1].id
        map.links = [MapLink(from: a, to: b, label: "feeds"), MapLink(from: a, to: a)]
        map.dropBrokenLinks()
        #expect(map.links.count == 1)
        map.root.remove(b)
        map.dropBrokenLinks()
        #expect(map.links.isEmpty)
    }

    @Test func linkArrowsRunBetweenIdeas() throws {
        var map = sampleMap()
        let link = MapLink(from: map.root.children[0].id, to: map.root.children[3].id)
        map.links = [link]
        let layout = MapLayout(map: map)
        let geometry = try #require(layout.linkGeometry(link))
        let from = try #require(layout.node(link.from)?.frame)
        let to = try #require(layout.node(link.to)?.frame)
        #expect(geometry.mid.y > from.midY && geometry.mid.y < to.midY)
        map.root.update(map.root.children[0].id) { $0.isCollapsed = true }
        let hidden = MapLink(from: map.root.children[0].children[0].id, to: link.to)
        #expect(MapLayout(map: map).linkGeometry(hidden) == nil, "hidden ideas have no arrow")
    }

    @Test func fitRectCentersABranch() {
        let rect = CGRect(x: 400, y: 300, width: 200, height: 100)
        let viewport = CanvasViewport.fit(rect: rect, in: CGSize(width: 400, height: 800), insets: EdgeInsets(), maxScale: 1.5)
        #expect(viewport.scale == 1.5)
        let centerX = viewport.offset.width + rect.midX * viewport.scale
        let centerY = viewport.offset.height + rect.midY * viewport.scale
        #expect(abs(centerX - 200) < 0.5 && abs(centerY - 400) < 0.5)
    }
}

@MainActor
struct TaskTests {
    @Test func agendaGroupsTasksByDueDate() {
        var map = sampleMap()
        let calendar = Calendar.current
        let now = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        let ids = map.root.children.map(\.id)
        map.root.update(ids[0]) { $0.isTask = true; $0.due = calendar.date(byAdding: .day, value: -2, to: now) }
        map.root.update(ids[1]) { $0.isTask = true; $0.due = now }
        map.root.update(ids[2]) { $0.isTask = true; $0.due = calendar.date(byAdding: .day, value: 3, to: now) }
        map.root.update(ids[3]) { $0.isTask = true; $0.priority = 1 }
        map.root.update(ids[4]) { $0.isTask = true; $0.isDone = true; $0.due = calendar.date(byAdding: .day, value: -1, to: now) }
        let sections = TaskAgenda.sections(TaskAgenda.tasks(in: [map]), now: now)
        #expect(sections.map(\.kind) == [.overdue, .today, .week, .important])
        #expect(sections[0].tasks.map(\.title) == ["Audience"], "done tasks are never overdue")
        #expect(TaskAgenda.dueCount(in: [map], now: now) == 2)
    }

    @Test func remindersComeOnlyForOpenFutureTasks() {
        var map = sampleMap()
        let now = Date()
        let ids = map.root.children.map(\.id)
        map.root.update(ids[0]) { $0.isTask = true; $0.due = now.addingTimeInterval(7200) }
        map.root.update(ids[1]) { $0.isTask = true; $0.due = now.addingTimeInterval(3600) }
        map.root.update(ids[2]) { $0.isTask = true; $0.isDone = true; $0.due = now.addingTimeInterval(3600) }
        map.root.update(ids[3]) { $0.isTask = true; $0.due = now.addingTimeInterval(-60) }
        let items = Reminders.upcoming(in: [map], after: now)
        #expect(items.map(\.title) == ["Pricing", "Audience"])
    }
}

@MainActor
struct StudyAndTemplateTests {
    @Test func flashcardsComeFromIdeasWithContent() {
        var map = sampleMap()
        map.root.update(map.root.children[3].id) { $0.note = "Ship in January" }
        let cards = Flashcards.make(from: map)
        #expect(cards.contains { $0.front == "Audience" && $0.back.count == 3 })
        #expect(cards.contains { $0.front == "Timeline" && $0.back.isEmpty && $0.note == "Ship in January" })
        #expect(!cards.contains { $0.front == "Students" }, "leaves without notes have no card")
    }

    @Test func templatesMakeMaps() {
        for template in MapTemplate.all {
            let map = template.makeMap()
            #expect(map.root.children.count == template.branches.count)
            #expect(map.root.children.allSatisfy { $0.icon != nil })
        }
        let week = MapTemplate.all.first { $0.id == "week" }!.makeMap()
        #expect(week.root.children[1].children.allSatisfy { $0.isTask })
    }
}

@MainActor
struct SyncAndWidgetTests {
    @Test func postgresTimestampsParse() throws {
        let date = try #require(MapSync.date("2026-10-03T17:03:55.123456+00:00"))
        #expect(abs(date.timeIntervalSince1970 - 1_791_047_035.123) < 0.01)
        #expect(MapSync.date("2026-10-03T17:03:55Z") != nil)
        #expect(MapSync.date("yesterday") == nil)
    }

    @Test func mapHashFollowsContent() {
        var map = sampleMap()
        let first = MapSync.hash(map)
        #expect(first == MapSync.hash(map), "the same map hashes the same")
        map.root.children[0].title = "People"
        #expect(MapSync.hash(map) != first)
    }

    @Test func syncedMapsSurviveTheRoundTrip() throws {
        var map = sampleMap()
        map.links = [MapLink(from: map.root.children[0].id, to: map.root.children[1].id, label: "feeds")]
        map.root.children[0].look = NodeLook(shape: .hexagon)
        let data = try MapSync.encoder.encode(map)
        let back = try MapSync.decoder.decode(MindMap.self, from: data)
        #expect(back.root == map.root && back.links == map.links)
    }

    @Test func widgetShowsTasksDueTodayAndEarlier() {
        var map = sampleMap()
        let calendar = Calendar.current
        let now = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        let ids = map.root.children.map(\.id)
        map.root.update(ids[0]) { $0.isTask = true; $0.due = calendar.date(byAdding: .hour, value: 3, to: now) }
        map.root.update(ids[1]) { $0.isTask = true; $0.due = calendar.date(byAdding: .day, value: -1, to: now) }
        map.root.update(ids[2]) { $0.isTask = true; $0.due = calendar.date(byAdding: .day, value: 2, to: now) }
        map.root.update(ids[3]) { $0.isTask = true; $0.isDone = true; $0.due = now }
        let snapshot = WidgetBridge.snapshot(of: [map], now: now, language: "ru")
        #expect(snapshot.tasks.map(\.title) == ["Pricing", "Audience"])
        #expect(snapshot.dueCount == 2 && snapshot.doneToday == 1 && snapshot.openCount == 3 && snapshot.language == "ru")
    }

    @Test func sharedLinksBecomeTheRightSource() {
        let page = SharedItem(title: "Photosynthesis", url: "https://en.wikipedia.org/wiki/Photosynthesis")
        guard case .link = SharedItemSheet.input(for: page) else { Issue.record("page"); return }
        let video = SharedItem(url: "https://youtu.be/abc")
        guard case .youtube = SharedItemSheet.input(for: video) else { Issue.record("video"); return }
        let text = SharedItem(title: "Notes", text: "Mitochondria make energy")
        guard case .text(let body, let source) = SharedItemSheet.input(for: text) else { Issue.record("text"); return }
        #expect(body == "Mitochondria make energy" && source.label == "Notes")
    }
}

struct DictationAndPlanTests {
    @Test func dictationAddsToWhatWasTyped() {
        #expect(DictationButton.join("", "buy milk") == "buy milk")
        #expect(DictationButton.join("Remind me to ", "buy milk") == "Remind me to buy milk")
        #expect(DictationButton.join("Hello", "") == "Hello", "nothing heard keeps the text")
    }

    @Test func planMyDaySendsTheTasks() {
        var message = ChatMessage(role: .user, text: "Plan my day")
        message.tasksText = "Open tasks: - [ ] Call the bank"
        #expect(message.contentForModel.contains("my tasks") && message.contentForModel.contains("Call the bank"))
    }
}

@MainActor
struct DeckTests {
    @Test func layoutsCarryContentOver() {
        let slide = Slide(layout: .bullets, title: "Plan", bullets: ["One", "Two", "Three", "Four"])
        #expect(slide.converted(to: .twoColumns).columns.map(\.bullets) == [["One", "Two"], ["Three", "Four"]])
        #expect(slide.converted(to: .timeline).items.map(\.title) == ["One", "Two", "Three", "Four"])
        #expect(slide.converted(to: .diagram).diagram?.nodes.count == 4)
        #expect(slide.converted(to: .table).table.count == 5)
        #expect(slide.converted(to: .bullets).bullets == slide.bullets)
    }

    @Test func editedDecksKeepPictures() {
        var old = Slide(layout: .imageText, title: "Think in maps", bullets: ["a"])
        old.image = NodeImage(id: UUID(), aspect: 1)
        let other = Slide(layout: .bullets, title: "Why")
        let reply = APIDeck(Deck(title: "D", slides: [Slide(layout: .cover, title: "New cover"), Slide(layout: .imageText, title: "think in maps", bullets: ["b"]), other]))
        let slides = reply.toSlides(keeping: [old, other])
        #expect(slides[1].image == old.image && slides[1].id == old.id && slides[1].bullets == ["b"])
        #expect(slides[2].id == other.id)
        #expect(slides[0].image == nil)
    }

    @Test func decksDecodeTolerantly() throws {
        let json = #"{"id":"\#(UUID().uuidString)","title":"T","slides":[{"layout":"hologram","title":"A"},{"title":"B","bullets":["x"]}]}"#
        let deck = try JSONDecoder().decode(Deck.self, from: Data(json.utf8))
        #expect(deck.slides.map(\.layout) == [.bullets, .bullets] && deck.deckTheme == .midnight)
    }

    @Test func zipChecksumsAreRight() {
        #expect(ZipWriter.crc32(Data("The quick brown fox jumps over the lazy dog".utf8)) == 0x414F_A339)
    }

    @Test func powerPointFileIsWellFormed() throws {
        let url = try DeckExport.pptx(DemoMap.deck())
        let data = try Data(contentsOf: url)
        #expect(data.starts(with: [0x50, 0x4B, 0x03, 0x04]), "a zip file")
        // Every XML part parses.
        var offset = 0
        var parts = 0
        while offset + 30 < data.count, data[offset..<offset + 4].elementsEqual([0x50, 0x4B, 0x03, 0x04]) {
            func u16(_ at: Int) -> Int { Int(data[at]) | Int(data[at + 1]) << 8 }
            func u32(_ at: Int) -> Int { u16(at) | u16(at + 2) << 16 }
            let size = u32(offset + 18)
            let nameLength = u16(offset + 26)
            let name = String(decoding: data[(offset + 30)..<(offset + 30 + nameLength)], as: UTF8.self)
            let body = data[(offset + 30 + nameLength)..<(offset + 30 + nameLength + size)]
            if name.hasSuffix(".xml") || name.hasSuffix(".rels") {
                #expect(XMLParser(data: Data(body)).parse(), "\(name) parses")
            }
            parts += 1
            offset += 30 + nameLength + size
        }
        #expect(parts > 40)
    }
}

struct CollabMergeTests {
    private func titles(_ node: MindNode) -> [String] { [node.title] + node.children.flatMap(titles) }

    @Test func editsToDifferentIdeasBothSurvive() {
        let base = sampleMap()
        var local = base, remote = base
        local.root.update(base.root.children[0].id) { $0.title = "People" }
        remote.root.update(base.root.children[1].id) { $0.title = "Prices" }
        local.root.update(base.root.children[0].id) { $0.children.append(MindNode(title: "Teachers")) }
        remote.root.update(base.root.children[2].id) { $0.children.append(MindNode(title: "YouTube")) }
        let merged = CollabMerge.merge(base: base, local: local, remote: remote)
        let all = titles(merged.root)
        #expect(all.contains("People") && all.contains("Prices") && all.contains("Teachers") && all.contains("YouTube"))
        #expect(merged.root.children.map(\.id) == base.root.children.map(\.id), "branch order kept")
    }

    @Test func deletesWin() {
        let base = sampleMap()
        let x = base.root.children[3].id, y = base.root.children[4].id
        var local = base, remote = base
        local.root.remove(x)                                        // deleted here
        remote.root.update(x) { $0.title = "Timeline v2" }          // edited there
        remote.root.remove(y)                                       // deleted there
        local.root.update(y) { $0.title = "Risks v2" }              // edited here
        let merged = CollabMerge.merge(base: base, local: local, remote: remote)
        #expect(merged.root.node(x) == nil && merged.root.node(y) == nil)
    }

    @Test func sameIdeaThisDeviceWins() {
        let base = sampleMap()
        let id = base.root.children[0].id
        var local = base, remote = base
        local.root.update(id) { $0.title = "Mine" }
        remote.root.update(id) { $0.title = "Theirs" }
        #expect(CollabMerge.merge(base: base, local: local, remote: remote).root.node(id)?.title == "Mine")
    }

    @Test func movesAndFoldsAndLinks() {
        let base = sampleMap()
        let students = base.root.children[0].children[0].id
        var local = base, remote = base
        // Moved here under Pricing; folded here; a connection added on each side.
        let moved = local.root.remove(students)!
        local.root.update(base.root.children[1].id) { $0.children.append(moved) }
        local.root.update(base.root.children[2].id) { $0.isCollapsed = true }
        local.links = [MapLink(from: base.root.children[0].id, to: base.root.children[1].id)]
        remote.links = [MapLink(from: base.root.children[2].id, to: base.root.children[3].id)]
        remote.root.update(base.root.children[2].id) { $0.isCollapsed = false }
        let merged = CollabMerge.merge(base: base, local: local, remote: remote)
        #expect(merged.root.parent(of: students)?.id == base.root.children[1].id)
        #expect(merged.root.node(base.root.children[2].id)?.isCollapsed == true, "folding is personal")
        #expect(merged.links.count == 2)
    }

    @Test func nothingChangedHereTakesTheirs() {
        let base = sampleMap()
        var remote = base
        remote.root.children.append(MindNode(title: "New branch"))
        remote.palette = "ocean"
        let merged = CollabMerge.merge(base: base, local: base, remote: remote)
        #expect(merged.root == remote.root && merged.palette == "ocean")
    }
}

// The server takes only Latin letters and digits; the app must say so before sending.
@Suite struct PasswordRulesTests {
    @Test func cyrillicLettersDontCount() {
        #expect(PasswordRules.check("Пароль2024").latinLetter == false)
        #expect(PasswordRules.problem(in: "Пароль2024") != nil)
    }

    @Test func latinLetterAndDigitPass() {
        #expect(PasswordRules.problem(in: "Minor2024") == nil)
        #expect(PasswordRules.problem(in: "мой Minor 7") == nil)
    }

    @Test func lengthAndDigitAreRequired() {
        #expect(PasswordRules.problem(in: "Mi12") != nil)
        #expect(PasswordRules.problem(in: "Minorabc") != nil)
    }
}

// Maps shared before roles existed stay editable; viewers can't edit.
@Suite struct CollabRoleTests {
    @Test func legacyInfoDecodesAsEditorOrOwner() throws {
        let member = try JSONDecoder().decode(CollabInfo.self, from: Data(#"{"isOwner":false,"version":3}"#.utf8))
        #expect(member.role == .editor && member.canEdit)
        let owner = try JSONDecoder().decode(CollabInfo.self, from: Data(#"{"isOwner":true,"version":1}"#.utf8))
        #expect(owner.role == .owner)
    }

    @Test func viewerCannotEdit() throws {
        let info = CollabInfo(isOwner: false, version: 2, role: .viewer)
        let round = try JSONDecoder().decode(CollabInfo.self, from: JSONEncoder().encode(info))
        #expect(round.role == .viewer && !round.canEdit)
    }
}

// Presentation design: old files still open, looks, templates, building up and the PowerPoint file.
@MainActor
@Suite struct DeckDesignTests {
    @Test func oldDecksStillDecode() throws {
        let json = #"{"id":"6F1B1C5E-2B0B-4F44-9E0B-1B2E3C4D5E6F","title":"Old","slides":[{"layout":"bullets","title":"A","bullets":["x"]}],"theme":"paper"}"#
        let deck = try JSONDecoder().decode(Deck.self, from: Data(json.utf8))
        #expect(deck.look == nil && deck.brand == nil && deck.transition == .fade)
        #expect(deck.slides[0].elements.isEmpty && deck.slides[0].buildBullets == .none)
        #expect(deck.style.isLight)
    }

    @Test func designSurvivesARoundTrip() throws {
        var deck = DemoMap.designedDeck()
        deck.slides[1].background = SlideBackground(kind: .solid, colors: ["#FFFFFF"], angle: 0)
        let back = try JSONDecoder().decode(Deck.self, from: JSONEncoder().encode(deck))
        #expect(back == deck)
        #expect(back.style(for: back.slides[1]).isLight)
        #expect(!back.style(for: back.slides[0]).isLight)
    }

    @Test func paletteFollowsTheAccent() {
        let palette = DeckLook.palette(from: "#2FFF9E")
        #expect(palette.count == 6 && palette[0] == "#2FFF9E")
        #expect(Set(palette).count == 6)
    }

    @Test func buildStepsCountPointsAndElements() {
        var slide = Slide(layout: .bullets, title: "T", bullets: ["a", "b", "c"])
        #expect(Deck.buildSteps(slide) == 0)
        slide.buildBullets = .fade
        var element = SlideElement.new(.icon)
        element.build = .zoom
        slide.elements = [element, SlideElement.new(.text)]
        #expect(Deck.buildSteps(slide) == 4)
    }

    @Test func templatesFillWithContentAndKeepDesign() throws {
        let template = DeckTemplates.all[0]
        #expect(template.layouts.first == .cover && template.layouts.last == .closing)
        let generated = template.layouts.map { Slide(layout: $0, title: "AI \($0.rawValue)") }
        let deck = template.fill(with: generated, title: "Filled")
        #expect(deck.title == "Filled" && deck.look == template.deck.look)
        #expect(deck.slides[1].title == "AI bullets" && deck.slides[1].elements.count == template.deck.slides[1].elements.count)
        #expect(deck.slides[1].buildBullets == template.deck.slides[1].buildBullets)
        #expect(Set(deck.slides.map(\.id)).isDisjoint(with: Set(template.deck.slides.map(\.id))))
    }

    @Test func powerPointHasMotionAndElements() throws {
        let url = try DeckExport.pptx(DemoMap.designedDeck())
        let data = try Data(contentsOf: url)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("<p:timing>") && text.contains("<p:transition"))
        #expect(text.contains("prst=\"roundRect\"") && text.contains("Avenir Next"))
        #expect(text.contains("ppt/media/") && text.contains("<p:bldP"))
    }
}

@MainActor
struct LimitsAndInvitesTests {
    @Test func percentsReadWell() {
        #expect(UsageView.percent(0) == "0%")
        #expect(UsageView.percent(0.004) == "<1%")
        #expect(UsageView.percent(0.126) == "13%")
        #expect(UsageView.percent(1.4) == "140%")
        #expect(UsageView.percent(-0.2) == "0%")
    }

    @Test func serverDatesParse() throws {
        #expect(AccountStore.parseDate("2026-11-01T00:00:00.000Z") != nil)
        #expect(AccountStore.parseDate("2026-10-12T10:00:00+00:00") != nil)
        let micro = try #require(AccountStore.parseDate("2026-10-12T10:00:00.123456+00:00"))
        let plain = try #require(AccountStore.parseDate("2026-10-12T10:00:00+00:00"))
        #expect(abs(micro.timeIntervalSince(plain) - 0.123) < 0.01)
        #expect(AccountStore.parseDate("2026-10-12 10:00:00.123456+00") != nil)
        #expect(AccountStore.parseDate("soon") == nil)
    }

    @Test func usageReportDecodes() throws {
        let json = """
        {"plan":"plus","bonusUntil":"2026-10-12T10:00:00.5+00:00","resetsAt":"2026-11-01T00:00:00.000Z",
         "allowance":{"limit":2000000,"used":500000,"areas":{"maps":200000,"decks":100000,"chat":150000,"images":0}},
         "counts":{"maps":{"used":3,"limit":300},"decks":{"used":1,"limit":20},"expands":{"used":0,"limit":3000},
                   "chats":{"used":12,"limit":5000},"images":{"used":60,"limit":60},"fetches":{"used":2,"limit":1000}}}
        """
        let report = try JSONDecoder().decode(UsageReport.self, from: Data(json.utf8))
        #expect(report.bonusDate != nil && report.resetDate != nil)
        #expect(report.counts.images.share == 1 && report.counts.maps.share == 0.01)
        #expect(report.allowance.areas.maps == 200_000)
    }

    @Test func invitationCodesAreCleaned() {
        #expect(InviteService.clean(" k7m2-q9xa ") == "K7M2Q9XA")
        #expect(InviteService.clean("O0I1abcdefghij") == "ABCDEFGH")
        #expect(InviteService.isValid("K7M2Q9XA"))
        #expect(!InviteService.isValid("K7M2Q9X"))
        #expect(!InviteService.isValid("K7M2Q9X0"))
    }

    @Test func inviteErrorsMapFromServerCodes() {
        #expect(InviteService.InviteError.from("invite_device_used") == .deviceUsed)
        #expect(InviteService.InviteError.from("device_check_failed") == .deviceCheck)
        #expect(InviteService.InviteError.from("something_new") == .other)
        #expect(InviteService.InviteError.notFound.errorDescription?.isEmpty == false)
        #expect(InviteService.InviteError.from("no_codes") == .noCodes)
    }

    @Test func discountsCoverPlansOnSale() {
        #expect(InviteService.discountProducts.count == 4)
        #expect(!InviteService.discountProducts.contains { $0.contains("HalfYear") })
        #expect(Set(InviteService.discountProducts.map(InviteService.productName)).count == 4)
    }

    @Test func inviteStatusDecodesOldAndNewServers() throws {
        let old = #"{"code":"K7M2Q9XA","link":"https://minorai.site/invite/#c=K7M2Q9XA","friends":3,"active":1,"subscribed":0,"bonusUntil":null,"bonusDays":0,"redeemed":false,"canRedeem":false,"days":{"friend":7,"join":7,"purchase":30}}"#
        let status = try JSONDecoder().decode(InviteService.Status.self, from: Data(old.utf8))
        #expect(status.friendLimit == 3 && status.isFull && status.percentText == "30%")
        let new = #"{"code":"K7M2Q9XA","link":"x","friends":1,"active":1,"subscribed":1,"bonusUntil":null,"bonusDays":0,"redeemed":false,"canRedeem":true,"days":{"friend":3,"join":3},"limit":3,"discountPercent":30,"discountsAvailable":0,"discounts":[{"code":"AB12","product":"com.minorailifegroup.MinorAI.plusYearlyPlan","url":"https://apps.apple.com/redeem?ctx=offercodes&id=6737686540&code=AB12"}]}"#
        let fresh = try JSONDecoder().decode(InviteService.Status.self, from: Data(new.utf8))
        #expect(!fresh.isFull && fresh.discounts?.first?.code == "AB12")
    }
}

// Fixes from the pre-release audit.
@MainActor
struct AuditFixTests {
    @Test func chartNumbersNeverCrash() {
        #expect(ChartView.format(12) == "12")
        #expect(ChartView.format(1.25) == "1.2" || ChartView.format(1.25) == "1.3")
        #expect(!ChartView.format(9_999_999_999_999_999_999).isEmpty)   // Int(value) used to trap here
        #expect(ChartView.format(.infinity) == "0" && ChartView.format(.nan) == "0")
        #expect(!ChartView.format(-1e30).isEmpty)
    }

    @Test func powerPointTextHasNoForbiddenCharacters() {
        let escaped = XML.escape("A\u{0B}B\u{0C}C\u{01}D & <E> \"F\"\tG\nH")
        #expect(escaped == "A B CD &amp; &lt;E&gt; &quot;F&quot;\tG\nH")
    }

    @Test func mergeKeepsNewNestedIdeasUnderTheirParent() {
        let a = MindNode(title: "A")
        let base = MindMap(root: MindNode(title: "Root", children: [a]))
        var local = base
        let step1 = MindNode(title: "Step 1"), step2 = MindNode(title: "Step 2")
        local.root.children.append(MindNode(title: "Plan", children: [MindNode(title: "Phase", children: [step1, step2])]))
        var remote = base
        remote.root.children[0].title = "A (renamed there)"
        let merged = CollabMerge.merge(base: base, local: local, remote: remote)
        let plan = merged.root.children.first { $0.title == "Plan" }
        #expect(merged.root.children.count == 2)
        #expect(plan?.children.first?.title == "Phase" && plan?.children.first?.children.count == 2)
        #expect(merged.root.children.first?.title == "A (renamed there)")
    }

    @Test func crossedMovesDontLoseBranches() {
        let a = MindNode(title: "A"), b = MindNode(title: "B")
        let base = MindMap(root: MindNode(title: "Root", children: [a, b]))
        // Here A went under B; there B went under A.
        var local = base
        local.root.children = [MindNode(id: b.id, title: "B", children: [MindNode(id: a.id, title: "A")])]
        var remote = base
        remote.root.children = [MindNode(id: a.id, title: "A", children: [MindNode(id: b.id, title: "B")])]
        let merged = CollabMerge.merge(base: base, local: local, remote: remote)
        func titles(_ node: MindNode) -> [String] { [node.title] + node.children.flatMap(titles) }
        #expect(Set(titles(merged.root)) == ["Root", "A", "B"])
    }

    @Test func duplicateLinksInSharedDataDontCrash() {
        let a = MindNode(title: "A"), b = MindNode(title: "B")
        var map = MindMap(root: MindNode(title: "Root", children: [a, b]))
        let link = MapLink(from: a.id, to: b.id)
        map.links = [link, link]
        let merged = CollabMerge.merge(base: map, local: map, remote: map)
        #expect(merged.links.count == 1)
    }

    @Test func deckEditKeepsTextTheServerOnlyShortened() {
        #expect(DeckService.unlessOnlyShortened("Line one\nLine two", "Line one Line two") == "Line one\nLine two")
        #expect(DeckService.unlessOnlyShortened(String(repeating: "word ", count: 300), String(repeating: "word ", count: 100) + "…") == String(repeating: "word ", count: 300))
        #expect(DeckService.unlessOnlyShortened("Old title", "New title") == "New title")
        #expect(DeckService.hasWords(Slide(layout: .bullets, title: "T")))
        var picture = Slide(layout: .bullets, title: "")
        picture.bullets = []
        #expect(!DeckService.hasWords(picture))
    }
}

struct ChatRetryTests {
    @Test func failedMessagesKeepTheirReasonOnDisk() throws {
        var message = ChatMessage(role: .user, text: "Plan my exam")
        message.failed = "You’re offline."
        message.imageRequest = true
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: data)
        #expect(decoded.failed == "You’re offline." && decoded.imageRequest == true)
        // Chats saved before Retry existed still load.
        let old = #"{"id":"\#(UUID().uuidString)","role":"user","text":"Hi"}"#
        let legacy = try JSONDecoder().decode(ChatMessage.self, from: Data(old.utf8))
        #expect(legacy.failed == nil && legacy.imageRequest == nil)
    }
}
