//
//  ProjectTests.swift
//  Minor AiTests
//
//  The project around a map: when its presentation's source has really changed, the private
//  project chat that survives reopening, proposals that never overwrite newer edits or a viewer's
//  map, and the recent documents list.
//

import Foundation
import Testing
@testable import Minor_Ai

private func projectMap() -> MindMap {
    func node(_ title: String, _ children: [MindNode] = []) -> MindNode { MindNode(title: title, children: children) }
    return MindMap(root: node("Podcast launch", [
        node("Audience", [node("Designers"), node("Students")]),
        node("Format", [node("Interviews"), node("Solo episodes")]),
        node("Recording", [node("Microphone")]),
        node("Timeline"),
    ]))
}

@MainActor
struct ProjectTests {
    @Test func fingerprintIgnoresViewAndStyleButNotContent() {
        var map = projectMap()
        let before = map.contentFingerprint
        map.root.children[0].isCollapsed = true
        map.root.children[1].color = .pink
        map.isPinned = true
        map.root.children[2].children.append(MindNode(title: "Waiting for a decision", isSuggestion: true))
        #expect(map.contentFingerprint == before, "Collapsing, colors, pins and pending suggestions aren't content")
        map.root.children[3].title = "Schedule"
        #expect(map.contentFingerprint != before)
    }

    @Test func deckSourceFieldsRoundTripAndOldDecksStillLoad() throws {
        var deck = Deck(title: "Launch", slides: [Slide(layout: .cover, title: "Launch")], sourceMapID: UUID())
        deck.sourceNodeID = UUID()
        deck.sourceRevision = "abc123"
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Deck.self, from: encoder.encode(deck))
        #expect(decoded.sourceNodeID == deck.sourceNodeID && decoded.sourceRevision == "abc123")
        let old = #"{"id":"\#(UUID().uuidString)","title":"Old","slides":[]}"#
        let legacy = try decoder.decode(Deck.self, from: Data(old.utf8))
        #expect(legacy.sourceNodeID == nil && legacy.sourceRevision == nil && !legacy.sourceChanged)
    }

    @Test func deckNoticesOnlyRealChangesInItsSource() throws {
        let map = projectMap()
        MapStore.shared.save(map)
        defer { MapStore.shared.delete(map.id) }
        var deck = Deck(title: "Launch", slides: [], sourceMapID: map.id)
        deck.sourceRevision = map.contentFingerprint
        #expect(!deck.sourceChanged)
        _ = MapStore.shared.update(map.id) { $0.root.children[0].isCollapsed = true }
        #expect(!deck.sourceChanged, "Collapsing a branch doesn't make the slides out of date")
        _ = MapStore.shared.update(map.id) { $0.root.children[0].title = "Listeners" }
        #expect(deck.sourceChanged)

        // A deck from one branch watches that branch only.
        let format = map.root.children[1].id
        var branchDeck = Deck(title: "Format", slides: [], sourceMapID: map.id)
        branchDeck.sourceNodeID = format
        branchDeck.sourceRevision = try #require(MapStore.shared.map(map.id)?.branch(format)).contentFingerprint
        _ = MapStore.shared.update(map.id) { $0.root.children[2].title = "Studio" }
        #expect(!branchDeck.sourceChanged)
        _ = MapStore.shared.update(map.id) { $0.root.children[1].children.append(MindNode(title: "Live shows")) }
        #expect(branchDeck.sourceChanged)
        // The branch deleted: the source is gone, never silently replaced by the whole map.
        _ = MapStore.shared.update(map.id) { $0.root.children.remove(at: 1) }
        #expect(branchDeck.sourceContent == nil)
    }

    @Test func projectChatKeepsItsDraftAndMessagesWhenReopened() {
        let mapID = UUID()
        defer { ProjectChatStore.shared.delete(mapID) }
        let first = ProjectChatModel(mapID: mapID)
        first.draft = "What is missing"
        first.save()
        let reopened = ProjectChatModel(mapID: mapID)
        #expect(reopened.draft == "What is missing")
        // The assistant's main history doesn't see it.
        #expect(!ChatViewModel.shared.conversations.contains { $0.id == mapID })
    }

    // A proposal that adds "Teachers" under Audience.
    private func proposal(for map: MindMap) -> ChatMessage {
        var proposed = map.root
        proposed.children[0].children.append(MindNode(title: "Teachers"))
        var action = ChatAction(kind: .mapProposal, mapID: map.id, mapTitle: map.title, summary: "+1 idea")
        action.command = "Add teachers to the audience"
        action.proposal = proposed
        action.base = map.root.editFingerprint
        action.added = map.root.addedTitles(in: proposed)
        return ChatMessage(role: .assistant, text: "", action: action)
    }

    private func hasTeachers(_ id: UUID) -> Bool {
        MapStore.shared.map(id)?.root.children.first?.children.contains { $0.title == "Teachers" } ?? false
    }

    @Test func proposalNeverOverwritesNewerEditsAndCanBeUndone() throws {
        let map = projectMap()
        MapStore.shared.save(map)
        defer { MapStore.shared.delete(map.id) }
        let message = proposal(for: map)
        #expect(message.action?.added == ["Audience › Teachers"])
        ProjectChatStore.shared.save(ProjectChatRecord(messages: [message]), for: map.id)
        let model = ProjectChatModel(mapID: map.id)

        // Edited by hand after the answer: shown as out of date and not applied.
        _ = MapStore.shared.update(map.id) { $0.root.children[3].title = "Schedule" }
        #expect(model.isStale(try #require(model.messages.first?.action)))
        model.apply(message.id)
        #expect(!hasTeachers(map.id))
        #expect(MapStore.shared.map(map.id)?.root.children[3].title == "Schedule", "The newer edit stays")

        // Back as the answer saw it (a collapsed branch doesn't count): applied, then undone.
        _ = MapStore.shared.update(map.id) {
            $0.root.children[3].title = "Timeline"
            $0.root.children[1].isCollapsed = true
        }
        #expect(!model.isStale(try #require(model.messages.first?.action)))
        model.apply(message.id)
        #expect(hasTeachers(map.id))
        #expect(MapStore.shared.map(map.id)?.root.children[1].isCollapsed == true, "The person's collapsed branch stays collapsed")
        #expect(model.canUndo(message.id))
        model.undo(message.id)
        #expect(!hasTeachers(map.id))
        #expect(!model.canUndo(message.id))
    }

    @Test func viewerCannotApplyProposals() {
        var map = projectMap()
        map.collab = CollabInfo(isOwner: false, version: 1, role: .viewer)
        MapStore.shared.save(map)
        defer { MapStore.shared.removeSynced(map.id) }
        let message = proposal(for: map)
        ProjectChatStore.shared.save(ProjectChatRecord(messages: [message]), for: map.id)
        defer { ProjectChatStore.shared.delete(map.id) }
        let model = ProjectChatModel(mapID: map.id)
        model.apply(message.id)
        #expect(!hasTeachers(map.id))
        #expect(model.errorMessage != nil)
    }

    @Test func recentDocumentsShowOpenedFirstAndDropDeleted() {
        let opened = MindMap(root: MindNode(title: "Opened"))
        var edited = MindMap(root: MindNode(title: "Edited long ago"))
        edited.updatedAt = Date(timeIntervalSinceNow: -86_400 * 30)
        let deck = Deck(title: "Slides", slides: [])
        let recents = RecentDocuments.shared
        defer { [opened.id, edited.id, deck.id].forEach(recents.forget) }
        recents.opened(.map, opened.id, at: Date(timeIntervalSinceNow: -60))
        recents.opened(.deck, deck.id, at: Date())
        #expect(recents.latest(3, maps: [opened, edited], decks: [deck]).map(\.id) == [deck.id, opened.id, edited.id])
        // A deleted deck drops out instead of showing a broken row.
        #expect(recents.latest(2, maps: [opened, edited], decks: []).map(\.id) == [opened.id, edited.id])
    }

    @Test func branchMapKeepsOnlyItsOwnConnections() throws {
        var map = projectMap()
        let format = map.root.children[1]
        map.links = [
            MapLink(from: format.children[0].id, to: format.children[1].id),
            MapLink(from: format.children[0].id, to: map.root.children[0].id),
        ]
        let branch = try #require(map.branch(format.id))
        #expect(branch.root.id == format.id && branch.links.count == 1)
    }
}
