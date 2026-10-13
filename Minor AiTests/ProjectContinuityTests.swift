//
//  ProjectContinuityTests.swift
//  Minor AiTests
//
//  Labels and origins on ideas (old maps still load, new fields round-trip, search finds labels),
//  materials and what a new one adds, About the Project, and saved map themes.
//

import Foundation
import Testing
@testable import Minor_Ai

@MainActor
struct ProjectContinuityTests {
    private func roundTrip(_ node: MindNode) throws -> MindNode {
        try JSONDecoder().decode(MindNode.self, from: JSONEncoder().encode(node))
    }

    @Test func oldIdeasLoadAndUnlabeledIdeasAreWrittenAsBefore() throws {
        let old = #"{"id":"\#(UUID().uuidString)","title":"Pricing","children":[]}"#
        let node = try JSONDecoder().decode(MindNode.self, from: Data(old.utf8))
        #expect(node.labels.isEmpty && node.origin == nil)
        let json = String(decoding: try JSONEncoder().encode(node), as: UTF8.self)
        #expect(!json.contains("labels") && !json.contains("origin"), "Nothing new is written for an idea without labels or origin")
        // A broken value in a newer file never makes the idea unreadable.
        let odd = #"{"id":"\#(UUID().uuidString)","title":"X","labels":"oops","origin":"martian"}"#
        let tolerant = try JSONDecoder().decode(MindNode.self, from: Data(odd.utf8))
        #expect(tolerant.title == "X" && tolerant.labels.isEmpty && tolerant.origin == nil)
    }

    @Test func labelsAndOriginsRoundTrip() throws {
        var node = MindNode(title: "Pricing")
        node.labels = ["Idea", "To review"]
        node.origin = .material(UUID())
        let decoded = try roundTrip(node)
        #expect(decoded.labels == ["Idea", "To review"] && decoded.origin == node.origin)
        for origin in [NodeOrigin.person, .ai, .template] {
            node.origin = origin
            #expect(try roundTrip(node).origin == origin)
        }
    }

    @Test func labelsAreCleanedAndLimited() {
        #expect(MindNode.cleanLabel("  #To   review \n") == "To review")
        #expect(MindNode.cleanLabel("   ") == nil && MindNode.cleanLabel("###") == nil)
        #expect(MindNode.cleanLabel(String(repeating: "a", count: 40))?.count == MindNode.maxLabelLength)
        let many = (1...12).map { "Label \($0)" } + ["label 1"]
        let clean = MindNode.cleanLabels(many)
        #expect(clean.count == MindNode.maxLabels && clean.first == "Label 1")
        #expect(MindNode.cleanLabels(["Idea", "IDEA", "idea "]) == ["Idea"], "Each label once, ignoring case")
    }

    @Test func searchFindsLabelsAndHashLooksOnlyAtLabels() {
        var node = MindNode(title: "Script", note: "Interview questions")
        node.labels = ["To review"]
        #expect(node.matches(search: "review"))
        #expect(node.matches(search: "#to rev"))
        #expect(node.matches(search: "script") && node.matches(search: "INTERVIEW"))
        #expect(!node.matches(search: "#script"), "#word looks at labels only")
        #expect(!node.matches(search: "#") && !node.matches(search: "  "))
    }

    @Test func mapLabelsAreListedMostUsedFirst() {
        var root = MindNode(title: "Launch", children: [MindNode(title: "A"), MindNode(title: "B"), MindNode(title: "C")])
        root.children[0].labels = ["Idea"]
        root.children[1].labels = ["To review", "idea"]
        root.children[2].labels = ["To review"]
        root.labels = ["Budget"]
        #expect(root.allLabels == ["Idea", "To review", "Budget"])
    }

    @Test func originsAreKeptWhenStamping() {
        var root = MindNode(title: "Launch", children: [MindNode(title: "Mine", origin: .person), MindNode(title: "New")])
        root = root.withOrigin(.ai)
        #expect(root.origin == .ai && root.children[0].origin == .person && root.children[1].origin == .ai)
        let material = UUID()
        #expect(MindNode(title: "x", children: [MindNode(title: "y")]).withOrigin(.material(material)).count(from: .material(material)) == 2)
    }

    @Test func materialAdditionsAreOnlyTheNewIdeasUnderTheirParents() throws {
        let root = MindNode(title: "Podcast", children: [
            MindNode(title: "Audience", children: [MindNode(title: "Students")]),
            MindNode(title: "Format"),
        ])
        let reply = #"""
        {"title":"Podcast","children":[
          {"title":"Audience","children":[{"title":"students"},{"title":"Teachers"}]},
          {"title":"Format","children":[{"title":"Interviews","children":[{"title":"20–30 minutes"}]}]},
          {"title":"Promotion"}
        ]}
        """#
        let additions = root.additions(from: try JSONDecoder().decode(APINode.self, from: Data(reply.utf8)))
        #expect(additions.map(\.node.title) == ["Teachers", "Interviews", "Promotion"], "Existing ideas (in any case) aren't added again")
        #expect(additions[0].parentID == root.children[0].id && additions[0].parentPath == ["Podcast", "Audience"])
        #expect(additions[1].node.count == 2, "A new idea keeps the ideas under it")
        #expect(additions[2].parentID == root.id)
    }

    @Test func passagesComeFromTheSavedTextOnly() {
        let material = ProjectMaterial(kind: .document, title: "Brief.pdf", text: "Intro line. Talks with practitioners last 20–30 minutes! Other part.")
        #expect(material.passage(mentioning: "practitioners") == "Talks with practitioners last 20–30 minutes!")
        #expect(material.passage(mentioning: "Budget") == nil, "No passage is made up when the text doesn't mention the idea")
        #expect(material.passage(mentioning: "ab") == nil)
        #expect(ProjectMaterial(kind: .link, title: "site", url: "https://example.com").passage(mentioning: "site") == nil)
    }

    @Test func materialsFollowTheirMap() throws {
        let store = ProjectMaterialStore.shared
        let mapID = UUID(), copyID = UUID()
        defer { store.delete(mapID); store.delete(copyID) }
        let material = ProjectMaterial(kind: .document, title: "Brief.pdf", text: String(repeating: "x", count: ProjectMaterial.textLimit + 50), pages: 6)
        #expect(material.text?.count == ProjectMaterial.textLimit, "Very long text is capped")
        store.add(material, to: mapID)
        #expect(store.materials(for: mapID).map(\.id) == [material.id])
        store.copy(from: mapID, to: copyID)
        #expect(store.material(material.id, in: copyID)?.pages == 6, "A copy of the map keeps its materials")
        store.remove(material.id, from: mapID)
        #expect(store.materials(for: mapID).isEmpty && store.materials(for: copyID).count == 1)
        // A new material made from what a map is created from; a topic is not a material.
        #expect(ProjectMaterial.from(.topic("Podcast")) == nil)
        #expect(ProjectMaterial.from(.link("https://example.com"))?.url == "https://example.com")
        #expect(ProjectMaterial.from(.text("Notes", source: MapSource(kind: .voice, label: "Voice note")))?.kind == .voice)
    }

    @Test func deletingAMapRemovesItsPrivateProjectData() {
        let map = MindMap(root: MindNode(title: "Temp"))
        MapStore.shared.save(map)
        ProjectMaterialStore.shared.add(ProjectMaterial(kind: .document, title: "a", text: "b"), to: map.id)
        ProjectMemoryStore.shared.update(map.id) { $0.goal = "Ship it" }
        MapStore.shared.delete(map.id)
        #expect(ProjectMaterialStore.shared.materials(for: map.id).isEmpty)
        #expect(ProjectMemoryStore.shared.memory(for: map.id).isEmpty)
    }

    @Test func projectMemoryIsContextOnlyWhenSomethingWasConfirmed() throws {
        let store = ProjectMemoryStore.shared
        let mapID = UUID()
        defer { store.delete(mapID) }
        #expect(store.memory(for: mapID).contextText == nil)
        store.update(mapID) { $0.suggestions = [.init(kind: .decision, text: "Weekly episodes")] }
        #expect(store.memory(for: mapID).contextText == nil, "A suggestion isn't a decision until it's accepted")
        store.update(mapID) { memory in
            memory.goal = "Launch three episodes"
            memory.decisions = [.init(text: "Interviews")]
            memory.questions = [.init(text: "Who is the first guest?")]
        }
        let context = try #require(store.memory(for: mapID).contextText)
        #expect(context.contains("Launch three episodes") && context.contains("Interviews") && context.contains("Who is the first guest?"))
        store.update(mapID) { $0.decisions = [] }
        #expect(!(store.memory(for: mapID).contextText ?? "").contains("Interviews"), "A removed decision stops counting")
        #expect(ProjectMemory.clean("  line one\nline two ") == "line one line two")
        #expect(ProjectMemory.clean(" \n ") == nil)
    }

    @Test func savedThemesApplyEveryDesignSetting() {
        var map = MindMap(root: MindNode(title: "A"))
        map.style = "pills"
        map.palette = "ocean"
        map.lines = "elbow"
        map.lineWeight = "bold"
        map.canvas = "grid"
        let theme = SavedMapTheme(name: "Night", map: map)
        var other = MindMap(root: MindNode(title: "B"))
        #expect(!theme.matches(other))
        theme.apply(to: &other)
        #expect(theme.matches(other) && other.mapStyle == .pills && other.canvasBackground == .grid)
        #expect(other.root.title == "B", "A theme never changes the content")
    }

    @Test func aiIdeasListPendingSuggestionsFirst() {
        var root = MindNode(title: "Launch", children: [MindNode(title: "Kept", origin: .ai), MindNode(title: "Mine", origin: .person)])
        root.children[1].children = [MindNode(title: "Waiting", isSuggestion: true, origin: .ai)]
        let ideas = SourcesSheet.aiIdeas(in: root)
        #expect(ideas.map(\.node.title) == ["Waiting", "Kept"])
        #expect(ideas[0].path == ["Launch", "Mine"])
    }
}
