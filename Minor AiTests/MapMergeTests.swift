//
//  MapMergeTests.swift
//  Minor AiTests
//
//  Updating slides from the map, field by field: the map's change comes in where the person didn't
//  write; their own words stay and a real disagreement is a conflict; a kept text isn't asked again
//  until the map changes again; new ideas and branches arrive once, in place; removed ideas take
//  only untouched bullets; skipped changes stay on offer; design, notes and order are never touched.
//

import Foundation
import Testing
@testable import Minor_Ai

@MainActor
struct MapMergeTests {
    // A map with two branches and a deck whose slides 2 and 3 are linked to them, bullets too.
    private func setup() -> (map: MindMap, deck: Deck) {
        let map = MindMap(root: MindNode(title: "Plan", children: [
            MindNode(title: "Audience", children: [MindNode(title: "Students"), MindNode(title: "Teams")]),
            MindNode(title: "Pricing", children: [MindNode(title: "Free"), MindNode(title: "Plus")]),
            MindNode(title: "Risks", children: [MindNode(title: "Costs")]),
        ]))
        func slide(_ node: MindNode) -> Slide {
            var s = Slide(layout: .bullets, title: node.title, bullets: node.children.map(\.title))
            s.bulletIDs = s.bullets.map { _ in UUID() }
            return s
        }
        var cover = Slide(layout: .cover, title: "Plan")
        cover.notes = "Hello"
        var slides = [cover, slide(map.root.children[0]), slide(map.root.children[1]), Slide(layout: .closing, title: "Thanks")]
        slides[2].notes = "Say the yearly price"
        slides[2].transition = .push
        var lineage = DeckLineage.manual([(slides[1], map.root.children[0]), (slides[2], map.root.children[1])], map: map)
        for (index, node) in [(1, map.root.children[0]), (2, map.root.children[1])] {
            for (k, child) in node.children.enumerated() {
                lineage.links.append(LineageLink(nodeID: child.id, slideID: slides[index].id, field: .bullet(slides[index].bulletIDs![k]), nodeText: child.title, base: child.title))
            }
        }
        var deck = Deck(title: "Plan", slides: slides, sourceMapID: map.id)
        deck.lineage = lineage
        deck.sourceRevision = map.contentFingerprint
        return (map, deck)
    }

    private func rename(_ map: inout MindMap, _ path: [Int], _ title: String) {
        var node = map.root
        for i in path { node = node.children[i] }
        map.root.update(node.id) { $0.title = title }
    }

    @Test func aChangeComesInWhereThePersonDidntWrite() {
        var (map, deck) = setup()
        deck.slides[1].bullets[0] = "Students with iPad"          // the person's own words
        rename(&map, [1, 1], "Plus · $9.99")                        // the map's change
        let update = MapUpdate.compute(deck: deck, map: map)
        #expect(update.visible.count == 1)
        let change = update.visible[0]
        #expect(change.kind == .change && change.include && change.current == "Plus" && change.proposal == "Plus · $9.99")
        let after = update.applied(to: deck, content: map)
        #expect(after.slides[2].bullets == ["Free", "Plus · $9.99"])
        #expect(after.slides[1].bullets[0] == "Students with iPad")  // untouched by the map: stays
        #expect(after.sourceRevision == map.contentFingerprint)
        // Design, notes, transitions and order stay.
        #expect(after.slides.map(\.id) == deck.slides.map(\.id))
        #expect(after.slides[0].notes == "Hello" && after.slides[2].notes == "Say the yearly price" && after.slides[2].transition == .push)
        // Nothing left to offer, and running it again adds nothing.
        #expect(MapUpdate.compute(deck: after, map: map).visible.isEmpty)
    }

    @Test func bothChangedIsAConflictAndAKeptTextIsntAskedAgain() {
        var (map, deck) = setup()
        deck.slides[1].bullets[1] = "Small teams of 3–5"
        rename(&map, [0, 1], "Companies")
        var update = MapUpdate.compute(deck: deck, map: map)
        #expect(update.conflicts.count == 1 && update.conflicts[0].choice == .mine && update.changeCount == 0)
        let kept = update.applied(to: deck, content: map)
        #expect(kept.slides[1].bullets[1] == "Small teams of 3–5")
        #expect(MapUpdate.compute(deck: kept, map: map).visible.isEmpty)     // not asked again
        var later = map
        rename(&later, [0, 1], "Enterprises")                                 // the map changes again
        #expect(MapUpdate.compute(deck: kept, map: later).conflicts.count == 1)
        // Taking the map's words, or one's own.
        update.changes[0].choice = .map
        #expect(update.changeCount == 1)
        #expect(update.applied(to: deck, content: map).slides[1].bullets[1] == "Companies")
        update.changes[0].choice = .custom("Companies and small teams")
        let custom = update.applied(to: deck, content: map)
        #expect(custom.slides[1].bullets[1] == "Companies and small teams")
        #expect(MapUpdate.compute(deck: custom, map: map).visible.isEmpty)
    }

    @Test func theSameWordsOnBothSidesNeedNoQuestion() {
        var (map, deck) = setup()
        deck.slides[1].bullets[0] = "Pupils"
        rename(&map, [0, 0], "Pupils")
        let update = MapUpdate.compute(deck: deck, map: map)
        #expect(update.visible.isEmpty && update.changes.count == 1 && update.changes[0].kind == .agreed)
        let after = update.applied(to: deck, content: map)
        #expect(MapUpdate.compute(deck: after, map: map).changes.isEmpty)
    }

    @Test func newIdeasArriveOnceInPlace() throws {
        var (map, deck) = setup()
        map.root.update(map.root.children[1].id) { $0.children.insert(MindNode(title: "Team plan"), at: 1) }
        let update = MapUpdate.compute(deck: deck, map: map)
        let addition = try #require(update.visible.first)
        #expect(addition.kind == .addition && addition.proposal == "Team plan" && addition.include)
        let after = update.applied(to: deck, content: map)
        #expect(after.slides[2].bullets == ["Free", "Team plan", "Plus"])      // after its sibling
        #expect(after.slides[2].bulletIDs?.count == 3)
        #expect(MapUpdate.compute(deck: after, map: map).visible.isEmpty)       // no duplicate next time
    }

    @Test func aNewBranchBecomesASlideButBranchesLeftOutDont() throws {
        var (map, deck) = setup()
        // "Risks" was in the map and left out of the slides: not new.
        #expect(MapUpdate.compute(deck: deck, map: map).visible.isEmpty)
        map.root.children.insert(MindNode(title: "Channels", children: [MindNode(title: "TikTok")]), at: 2)
        let update = MapUpdate.compute(deck: deck, map: map)
        let new = try #require(update.visible.first)
        #expect(new.kind == .newSlide && update.visible.count == 1)
        let after = update.applied(to: deck, content: map)
        #expect(after.slides.count == 5 && after.slides[3].title == "Channels" && after.slides[3].bullets == ["TikTok"])
        #expect(after.slides[4].layout == .closing)
        #expect(MapUpdate.compute(deck: after, map: map).visible.isEmpty)
    }

    @Test func removedIdeasTakeOnlyUntouchedBullets() {
        var (map, deck) = setup()
        deck.slides[1].bullets[1] = "Teams, written by me"
        map.root.update(map.root.children[0].id) { $0.children.removeAll() }
        let update = MapUpdate.compute(deck: deck, map: map)
        let removals = update.visible.filter { $0.kind == .removal }
        #expect(removals.count == 2)
        #expect(removals.first { $0.current == "Students" }?.include == true)
        #expect(removals.first { $0.current == "Teams, written by me" }?.include == false)
        let after = update.applied(to: deck, content: map)
        #expect(after.slides[1].bullets == ["Teams, written by me"])            // kept as the person's own
        #expect(MapUpdate.compute(deck: after, map: map).visible.isEmpty)       // and no longer linked
    }

    @Test func skippedChangesStayOnOffer() {
        var (map, deck) = setup()
        rename(&map, [1, 0], "Free · 3 maps")
        rename(&map, [1, 1], "Plus · $9.99")
        var update = MapUpdate.compute(deck: deck, map: map)
        let skipped = update.changes.firstIndex { $0.proposal == "Free · 3 maps" }!
        update.changes[skipped].include = false
        #expect(update.changeCount == 1)
        let after = update.applied(to: deck, content: map)
        #expect(after.slides[2].bullets == ["Free", "Plus · $9.99"])
        #expect(after.sourceRevision == deck.sourceRevision)                    // still offered
        let again = MapUpdate.compute(deck: after, map: map)
        #expect(again.visible.map(\.proposal) == ["Free · 3 maps"])
    }

    @Test func decisionsCarryToAFreshComparison() {
        var (map, deck) = setup()
        deck.slides[1].bullets[1] = "Mine"
        rename(&map, [0, 1], "Companies")
        rename(&map, [1, 1], "Plus · $9.99")
        var first = MapUpdate.compute(deck: deck, map: map)
        first.changes[first.changes.firstIndex { $0.kind == .conflict }!].choice = .map
        first.changes[first.changes.firstIndex { $0.kind == .change }!].include = false
        // Meanwhile another idea changes: the comparison is made again, the earlier decisions stay.
        rename(&map, [0, 0], "Pupils")
        let fresh = MapUpdate.compute(deck: deck, map: map).carrying(first)
        #expect(fresh.changes.first { $0.kind == .conflict }?.choice == .map)
        #expect(fresh.changes.first { $0.proposal == "Plus · $9.99" }?.include == false)
        #expect(fresh.changes.first { $0.proposal == "Pupils" }?.include == true)
    }

    @Test func bulletIdsFollowTheirBullets() {
        var slide = Slide(layout: .bullets, title: "T", bullets: ["a", "b", "c"])
        slide.alignBulletIDs(from: nil)
        let ids = slide.bulletKeys
        var edited = slide
        edited.bullets.insert("new", at: 1)
        edited.bulletIDs = nil
        edited.alignBulletIDs(from: slide)
        #expect(edited.bulletKeys[0] == ids[0] && edited.bulletKeys[2] == ids[1] && edited.bulletKeys[3] == ids[2])
        #expect(!ids.contains(edited.bulletKeys[1]))
        var removed = slide
        removed.bullets.remove(at: 0)
        removed.alignBulletIDs(from: slide)        // ids kept in step by the change stay; else they follow
        #expect(removed.bulletIDs?.count == 2)
        var renamed = slide
        renamed.bullets[2] = "C!"
        renamed.alignBulletIDs(from: slide)
        #expect(renamed.bulletKeys == ids)
    }

    @Test func presentationsFromBeforeStillOpen() throws {
        let json = #"{"id":"\#(UUID().uuidString)","title":"Old","slides":[{"id":"\#(UUID().uuidString)","layout":"timeline","title":"Plan","items":[{"title":"Beta","detail":"Nov"}],"bullets":["x"]}]}"#
        let a = try JSONDecoder().decode(Deck.self, from: Data(json.utf8))
        let b = try JSONDecoder().decode(Deck.self, from: Data(json.utf8))
        #expect(a.lineage == nil && a.slides[0].bulletIDs == nil)
        #expect(a.slides[0].items[0].id == b.slides[0].items[0].id)          // the same id every read
        #expect(a.slides[0].bulletKeys == b.slides[0].bulletKeys)
        let round = try JSONDecoder().decode(Deck.self, from: JSONEncoder().encode(a))
        #expect(round == a)
    }

    @Test func linksComeOnlyFromRefsTheMapHas() throws {
        let map = MindMap(root: MindNode(title: "Plan", children: [MindNode(title: "Audience", children: [MindNode(title: "Students")])]))
        let made = MapRefs.make(map.root)
        #expect(made.refs.count == 3 && made.tree.ref == "n1")
        var slide = Slide(layout: .bullets, title: "Who it’s for", bullets: ["Students on iPad", "Everyone"])
        slide.alignBulletIDs(from: nil)
        var api = APISlide(slide)
        api.src = "n2"
        api.bulletSrc = ["n3", "n99"]
        let lineage = try #require(DeckLineage.build(slides: [slide], api: [api], refs: made.refs, map: map))
        #expect(lineage.slides.count == 1 && lineage.slides[0].nodeID == map.root.children[0].id)
        #expect(lineage.links.count == 2)                                       // the title and one bullet; "n99" links nothing
        #expect(lineage.links.contains { $0.field == .bullet(slide.bulletKeys[0]) && $0.nodeText == "Students" && $0.base == "Students on iPad" })
        #expect(lineage.branches == [map.root.children[0].id])
    }
}
