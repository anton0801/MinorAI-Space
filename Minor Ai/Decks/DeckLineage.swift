//
//  DeckLineage.swift
//  Minor Ai
//
//  Updating slides from their map without losing what the person wrote.
//  A presentation made from a map remembers, for each linked field (a slide's title, a bullet, a
//  timeline item), the idea it came from, the idea's words then and the field's words then — the
//  last state both sides agreed on. It also remembers which idea each slide is about and that
//  idea's children then. Bullets and items have stable ids, so a link survives edits around it.
//
//  An update compares three things per field: that base, what the slide says now and what the map
//  says now. The map's words are taken as they are (no AI rewriting), only for ideas that changed:
//  - the map changed and the slide didn't: offered, ticked;
//  - the slide changed and the map didn't: nothing;
//  - both changed differently: a conflict, the person's words kept unless they choose otherwise;
//  - both say the same: nothing to ask;
//  - a new idea under a slide's idea: a new bullet after its sibling; a new main branch: a new slide;
//  - an idea gone: its bullet or slide may go, never when the person changed it.
//  Notes, design, pictures, free elements, hidden slides, transitions and the order of untouched
//  slides are never part of it. Applying is one change, Undo takes it all back.
//

import Foundation

struct DeckLineage: Codable, Equatable {
    var links: [LineageLink] = []
    var slides: [SlideSource] = []
    var branches: [UUID]?      // the map's main branches when they last agreed (a branch not here is new)

    var isEmpty: Bool { links.isEmpty && slides.isEmpty }
}

struct LineageLink: Codable, Equatable, Identifiable {
    enum Field: Codable, Hashable {
        case title
        case bullet(UUID)
        case item(UUID)
    }

    var id = UUID()
    var nodeID: UUID
    var slideID: UUID
    var field: Field
    var nodeText: String       // the idea's words when this field last agreed with it
    var base: String           // the field's words then
    var declined: String?      // the idea's words the person chose not to take (not asked again)
}

// The idea a slide is about, and that idea's children when they last agreed.
struct SlideSource: Codable, Equatable {
    var slideID: UUID
    var nodeID: UUID
    var children: [UUID]
}

// MARK: - Stable bullet ids

extension Slide {
    // The bullets' ids in step with them; bullets from before ids get theirs from the slide.
    var bulletKeys: [UUID] {
        let ids = bulletIDs ?? []
        return bullets.indices.map { i in i < ids.count ? ids[i] : SlideDiagram.stableID(id, "bullet\(i)") }
    }

    // After the bullets changed, ids follow their bullets: an edit in place keeps its id, a removed
    // bullet takes its id along, a new bullet gets a new one.
    mutating func alignBulletIDs(from old: Slide?) {
        // Ids already in step were kept by whatever changed the bullets (an update from the map,
        // an edit in place): they stay.
        if let ids = bulletIDs, ids.count == bullets.count { return }
        guard let old else {
            bulletIDs = bullets.isEmpty ? nil : bulletKeys
            return
        }
        let oldKeys = old.bulletKeys
        if bullets.count == old.bullets.count {
            bulletIDs = bullets.isEmpty ? nil : oldKeys
            return
        }
        var keys = oldKeys
        func offset(_ change: CollectionDifference<String>.Change) -> Int {
            switch change {
            case .insert(let offset, _, _), .remove(let offset, _, _): return offset
            }
        }
        let difference = bullets.difference(from: old.bullets)
        for change in difference.removals.sorted(by: { offset($0) > offset($1) }) where keys.indices.contains(offset(change)) {
            keys.remove(at: offset(change))
        }
        for change in difference.insertions.sorted(by: { offset($0) < offset($1) }) {
            keys.insert(UUID(), at: min(offset(change), keys.count))
        }
        bulletIDs = bullets.isEmpty ? nil : Array(keys.prefix(bullets.count))
    }

    func bulletIndex(_ id: UUID) -> Int? { bulletKeys.firstIndex(of: id) }
}

extension Deck {
    // Bullet ids aligned with the deck as it was before this change.
    mutating func alignBulletIDs(from old: Deck?) {
        let before = Dictionary((old?.slides ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for i in slides.indices { slides[i].alignBulletIDs(from: before[slides[i].id]) }
    }
}

// MARK: - Making the links when slides are made from a map

enum MapRefs {
    // Short refs for the ideas ("n1", "n2"…), so the AI can say where each slide comes from.
    static func make(_ root: MindNode) -> (tree: APINode, refs: [String: UUID]) {
        var refs: [String: UUID] = [:]
        func walk(_ node: MindNode) -> APINode {
            var api = APINode(node)
            let ref = "n\(refs.count + 1)"
            refs[ref] = node.id
            api.ref = ref
            api.children = node.children.isEmpty ? nil : node.children.map(walk)
            return api
        }
        return (walk(root), refs)
    }
}

extension DeckLineage {
    // Links from what the AI said each slide, bullet and item comes from; refs it didn't get, or
    // ideas the map doesn't have, link nothing.
    static func build(slides: [Slide], api: [APISlide], refs: [String: UUID], map: MindMap) -> DeckLineage? {
        var lineage = DeckLineage()
        func idea(_ ref: String?) -> MindNode? {
            ref.flatMap { refs[$0] }.flatMap { map.root.node($0) }
        }
        for (slide, reply) in zip(slides, api) {
            if let node = idea(reply.src) {
                lineage.slides.append(SlideSource(slideID: slide.id, nodeID: node.id, children: node.children.filter { !$0.isSuggestion }.map(\.id)))
                if !slide.title.isEmpty {
                    lineage.links.append(LineageLink(nodeID: node.id, slideID: slide.id, field: .title, nodeText: node.title, base: slide.title))
                }
            }
            let keys = slide.bulletKeys
            for (k, ref) in (reply.bulletSrc ?? []).enumerated() where keys.indices.contains(k) {
                guard let node = idea(ref) else { continue }
                lineage.links.append(LineageLink(nodeID: node.id, slideID: slide.id, field: .bullet(keys[k]), nodeText: node.title, base: slide.bullets[k]))
            }
            for (item, replyItem) in zip(slide.items, reply.items ?? []) {
                guard let node = idea(replyItem.src) else { continue }
                lineage.links.append(LineageLink(nodeID: node.id, slideID: slide.id, field: .item(item.id), nodeText: node.title, base: item.title))
            }
        }
        lineage.branches = map.root.children.filter { !$0.isSuggestion }.map(\.id)
        return lineage.isEmpty ? nil : lineage
    }

    // Slides linked by hand to main branches (older presentations): their titles and new ideas
    // under them can come from the map from now on. Bullets aren't linked: nothing is guessed.
    static func manual(_ pairs: [(slide: Slide, node: MindNode)], map: MindMap? = nil) -> DeckLineage {
        var lineage = DeckLineage()
        lineage.branches = map?.root.children.filter { !$0.isSuggestion }.map(\.id)
        for (slide, node) in pairs {
            lineage.slides.append(SlideSource(slideID: slide.id, nodeID: node.id, children: node.children.filter { !$0.isSuggestion }.map(\.id)))
            if !slide.title.isEmpty {
                lineage.links.append(LineageLink(nodeID: node.id, slideID: slide.id, field: .title, nodeText: node.title, base: slide.title))
            }
        }
        return lineage
    }
}

// MARK: - The update

struct MapUpdate: Identifiable {
    enum Kind: Equatable {
        case change          // the map changed, the slide didn't
        case conflict        // both changed
        case addition        // a new idea under a slide's idea
        case newSlide        // a new main branch
        case removal         // an idea gone: its bullet or item
        case slideRemoval    // an idea gone: its slide
        case agreed          // both say the same now: nothing to ask, the base moves on
    }

    enum Choice: Equatable {
        case mine
        case map
        case custom(String)
    }

    struct Change: Identifiable, Equatable {
        let id: String
        let kind: Kind
        let slideID: UUID?
        let slideNumber: Int          // from 1; for a new slide, where it goes
        let slideTitle: String
        let nodeID: UUID
        let linkID: UUID?
        let current: String           // what the slide says now
        let proposal: String          // what the map says
        var include: Bool             // ticked (changes, additions, new slides, removals)
        var choice: Choice = .mine    // conflicts
        var overflows = false         // the slide wouldn't show all of it
    }

    let id = UUID()
    let deck: Deck                    // as it was when compared
    let revision: String              // the map's content then
    var changes: [Change]

    var visible: [Change] { changes.filter { $0.kind != .agreed } }
    var conflicts: [Change] { changes.filter { $0.kind == .conflict } }
    var offers: [Change] { changes.filter { $0.kind != .agreed && $0.kind != .conflict } }

    // What will really change when applied (the button's number).
    var changeCount: Int {
        changes.filter { change in
            switch change.kind {
            case .conflict: return change.choice != .mine
            case .agreed: return false
            case .removal, .slideRemoval: return change.include
            default: return change.include
            }
        }.count
    }

    // MARK: Comparing

    static func compute(deck: Deck, map content: MindMap) -> MapUpdate {
        let lineage = deck.lineage ?? DeckLineage()
        var changes: [Change] = []
        let slides = deck.slides
        func number(_ id: UUID) -> Int { (slides.firstIndex { $0.id == id } ?? 0) + 1 }
        func slide(_ id: UUID) -> Slide? { slides.first { $0.id == id } }
        let linkedNodes = Set(lineage.links.map(\.nodeID))

        for link in lineage.links {
            guard let slide = slide(link.slideID), let current = Self.text(of: link.field, in: slide) else { continue }
            guard let node = content.root.node(link.nodeID), !node.isSuggestion else {
                // The idea is gone. A title goes with its slide (below); a bullet or item may go.
                if link.field != .title {
                    changes.append(Change(id: link.id.uuidString, kind: .removal, slideID: slide.id, slideNumber: number(slide.id), slideTitle: slide.title,
                                          nodeID: link.nodeID, linkID: link.id, current: current, proposal: "", include: current == link.base))
                }
                continue
            }
            let proposal = node.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard proposal != link.nodeText else { continue }                       // the map didn't change here
            let kind: Kind
            if current == proposal {
                kind = .agreed
            } else if current == link.base {
                kind = .change
            } else if link.declined == proposal {
                continue                                                             // already kept the person's words
            } else {
                kind = .conflict
            }
            changes.append(Change(id: link.id.uuidString, kind: kind, slideID: slide.id, slideNumber: number(slide.id), slideTitle: slide.title,
                                  nodeID: node.id, linkID: link.id, current: current, proposal: proposal, include: kind != .conflict))
        }

        for source in lineage.slides {
            guard let slide = slide(source.slideID) else { continue }
            guard let node = content.root.node(source.nodeID), !node.isSuggestion else {
                let untouched = slide.notes.isEmpty && slide.elements.isEmpty && slide.image == nil
                    && lineage.links.filter { $0.slideID == slide.id }.allSatisfy { Self.text(of: $0.field, in: slide) == $0.base }
                changes.append(Change(id: "slide-\(slide.id.uuidString)", kind: .slideRemoval, slideID: slide.id, slideNumber: number(slide.id), slideTitle: slide.title,
                                      nodeID: source.nodeID, linkID: nil, current: slide.title, proposal: "", include: untouched))
                continue
            }
            // New ideas under it, where the slide has a list to put them in.
            guard [.bullets, .imageText, .timeline].contains(slide.layout) else { continue }
            for child in node.children where !child.isSuggestion && !source.children.contains(child.id) && !linkedNodes.contains(child.id) {
                changes.append(Change(id: "add-\(slide.id.uuidString)-\(child.id.uuidString)", kind: .addition, slideID: slide.id, slideNumber: number(slide.id),
                                      slideTitle: slide.title, nodeID: child.id, linkID: nil, current: "", proposal: child.title, include: true))
            }
        }

        // Main branches added since they last agreed, when the slides follow the branches. Branches
        // that were there and left out are not new.
        let branchSlides = Set(lineage.slides.map(\.nodeID))
        let known = Set(lineage.branches ?? content.root.children.map(\.id))
        if content.root.children.contains(where: { branchSlides.contains($0.id) }) {
            for branch in content.root.children where !branch.isSuggestion && !known.contains(branch.id) && !branchSlides.contains(branch.id) && !linkedNodes.contains(branch.id) {
                let place = insertionIndex(forBranch: branch.id, deck: deck, content: content)
                changes.append(Change(id: "new-\(branch.id.uuidString)", kind: .newSlide, slideID: nil, slideNumber: place + 1, slideTitle: branch.title,
                                      nodeID: branch.id, linkID: nil, current: "", proposal: branch.title, include: true))
            }
        }

        var update = MapUpdate(deck: deck, revision: content.contentFingerprint, changes: changes)
        update.markOverflow(content: content)
        return update
    }

    static func text(of field: LineageLink.Field, in slide: Slide) -> String? {
        switch field {
        case .title: return slide.title
        case .bullet(let id): return slide.bulletIndex(id).map { slide.bullets[$0] }
        case .item(let id): return slide.items.first { $0.id == id }?.title
        }
    }

    // A new branch's slide goes after the slide of the branch before it (else before the closing slide).
    static func insertionIndex(forBranch id: UUID, deck: Deck, content: MindMap) -> Int {
        let lineage = deck.lineage ?? DeckLineage()
        let branches = content.root.children
        if let position = branches.firstIndex(where: { $0.id == id }) {
            for previous in branches[..<position].reversed() {
                if let source = lineage.slides.first(where: { $0.nodeID == previous.id }), let index = deck.slides.firstIndex(where: { $0.id == source.slideID }) {
                    return index + 1
                }
            }
        }
        if deck.slides.last?.layout == .closing { return max(deck.slides.count - 1, 0) }
        return deck.slides.count
    }

    // Changes after which a slide couldn't show everything are marked, so the person can split it.
    mutating func markOverflow(content: MindMap) {
        let after = applied(to: deck, content: content)
        for i in changes.indices {
            guard let id = changes[i].slideID, let slide = after.slides.first(where: { $0.id == id }) else { continue }
            changes[i].overflows = slide.overflow != nil && deck.slides.first { $0.id == id }?.overflow == nil
        }
    }

    // Decisions carried to a new comparison where the same change is offered again unchanged.
    func carrying(_ old: MapUpdate) -> MapUpdate {
        var copy = self
        for i in copy.changes.indices {
            if let before = old.changes.first(where: { $0.id == copy.changes[i].id }),
               before.current == copy.changes[i].current, before.proposal == copy.changes[i].proposal {
                copy.changes[i].include = before.include
                copy.changes[i].choice = before.choice
            }
        }
        return copy
    }

    // MARK: Applying

    // The deck with the chosen changes, its links moved on for what was decided, everything else
    // as it was. `content`: the map as compared.
    func applied(to deck: Deck, content: MindMap) -> Deck {
        var result = deck
        var lineage = deck.lineage ?? DeckLineage()
        func slideIndex(_ id: UUID?) -> Int? { id.flatMap { id in result.slides.firstIndex { $0.id == id } } }
        func setText(_ field: LineageLink.Field, _ text: String, slide: Int) {
            switch field {
            case .title: result.slides[slide].title = text
            case .bullet(let id): if let k = result.slides[slide].bulletIndex(id) { result.slides[slide].bullets[k] = text }
            case .item(let id): if let k = result.slides[slide].items.firstIndex(where: { $0.id == id }) { result.slides[slide].items[k].title = text }
            }
        }
        func updateLink(_ id: UUID?, _ change: (inout LineageLink) -> Void) {
            guard let id, let k = lineage.links.firstIndex(where: { $0.id == id }) else { return }
            change(&lineage.links[k])
        }

        for change in changes {
            switch change.kind {
            case .agreed:
                updateLink(change.linkID) { $0.base = change.current; $0.nodeText = change.proposal; $0.declined = nil }
            case .change:
                guard change.include, let s = slideIndex(change.slideID), let link = lineage.links.first(where: { $0.id == change.linkID }) else { continue }
                setText(link.field, change.proposal, slide: s)
                updateLink(change.linkID) { $0.base = change.proposal; $0.nodeText = change.proposal; $0.declined = nil }
            case .conflict:
                guard let s = slideIndex(change.slideID), let link = lineage.links.first(where: { $0.id == change.linkID }) else { continue }
                switch change.choice {
                case .mine:
                    updateLink(change.linkID) { $0.declined = change.proposal }
                case .map:
                    setText(link.field, change.proposal, slide: s)
                    updateLink(change.linkID) { $0.base = change.proposal; $0.nodeText = change.proposal; $0.declined = nil }
                case .custom(let text):
                    let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    setText(link.field, words, slide: s)
                    updateLink(change.linkID) { $0.base = words; $0.nodeText = change.proposal; $0.declined = nil }
                }
            case .removal:
                guard let s = slideIndex(change.slideID), let link = lineage.links.first(where: { $0.id == change.linkID }) else { continue }
                if change.include {
                    switch link.field {
                    case .bullet(let id):
                        if let k = result.slides[s].bulletIndex(id) {
                            var keys = result.slides[s].bulletKeys
                            keys.remove(at: k)
                            result.slides[s].bullets.remove(at: k)
                            result.slides[s].bulletIDs = keys.isEmpty ? nil : keys
                        }
                    case .item(let id):
                        result.slides[s].items.removeAll { $0.id == id }
                    case .title:
                        break
                    }
                }
                // Gone or kept as the person's own: no longer linked either way.
                lineage.links.removeAll { $0.id == change.linkID }
            case .slideRemoval:
                if change.include, let s = slideIndex(change.slideID), result.slides.count > 1 {
                    result.slides.remove(at: s)
                }
                lineage.slides.removeAll { $0.slideID == change.slideID }
                lineage.links.removeAll { $0.slideID == change.slideID }
            case .addition:
                guard change.include, let s = slideIndex(change.slideID), let node = content.root.node(change.nodeID) else { continue }
                let parent = lineage.slides.first { $0.slideID == change.slideID }
                if result.slides[s].layout == .timeline {
                    let item = SlideItem(title: node.title, detail: "")
                    result.slides[s].items.append(item)
                    lineage.links.append(LineageLink(nodeID: node.id, slideID: result.slides[s].id, field: .item(item.id), nodeText: node.title, base: node.title))
                } else {
                    // After the bullet of the idea before it, else at the end.
                    var keys = result.slides[s].bulletKeys
                    var at = result.slides[s].bullets.count
                    if let parentNode = parent.flatMap({ content.root.node($0.nodeID) }), let position = parentNode.children.firstIndex(where: { $0.id == node.id }) {
                        for previous in parentNode.children[..<position].reversed() {
                            if let link = lineage.links.first(where: { $0.nodeID == previous.id && $0.slideID == change.slideID }),
                               case .bullet(let id) = link.field, let k = result.slides[s].bulletIndex(id) {
                                at = k + 1
                                break
                            }
                        }
                    }
                    let id = UUID()
                    result.slides[s].bullets.insert(node.title, at: at)
                    keys.insert(id, at: at)
                    result.slides[s].bulletIDs = keys
                    lineage.links.append(LineageLink(nodeID: node.id, slideID: result.slides[s].id, field: .bullet(id), nodeText: node.title, base: node.title))
                }
                if let k = lineage.slides.firstIndex(where: { $0.slideID == change.slideID }) { lineage.slides[k].children.append(node.id) }
            case .newSlide:
                guard change.include, let branch = content.root.node(change.nodeID) else { continue }
                let children = branch.children.filter { !$0.isSuggestion }.prefix(6)
                var slide = Slide(layout: .bullets, title: branch.title, bullets: children.map(\.title))
                slide.bulletIDs = slide.bullets.map { _ in UUID() }
                let place = MapUpdate.insertionIndex(forBranch: branch.id, deck: result, content: content)
                result.slides.insert(slide, at: min(place, result.slides.count))
                lineage.slides.append(SlideSource(slideID: slide.id, nodeID: branch.id, children: children.map(\.id)))
                lineage.links.append(LineageLink(nodeID: branch.id, slideID: slide.id, field: .title, nodeText: branch.title, base: branch.title))
                for (id, child) in zip(slide.bulletIDs ?? [], children) {
                    lineage.links.append(LineageLink(nodeID: child.id, slideID: slide.id, field: .bullet(id), nodeText: child.title, base: child.title))
                }
                lineage.branches = (lineage.branches ?? []) + [branch.id]
            }
        }
        result.lineage = lineage.isEmpty ? nil : lineage
        // Fully handled: the presentation agrees with the map as it is now. Something left for
        // later keeps the old mark, so the update is still offered.
        let pending = changes.contains { ($0.kind == .change || $0.kind == .addition || $0.kind == .newSlide) && !$0.include }
        if !pending { result.sourceRevision = revision }
        return result
    }
}
