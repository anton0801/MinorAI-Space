//
//  DiagramTests.swift
//  Minor AiTests
//
//  Diagrams as data: diagrams saved before still open and are written as before; inserting,
//  removing, connecting and moving keep the rules of each kind (a process's connection splits, a
//  cycle stays closed, a hierarchy never loops); changing the kind or the matrix mode loses nothing;
//  boxes don't overlap and connections end on their boxes' sides; PowerPoint gets connectors
//  attached to the shapes.
//

import Foundation
import Testing
@testable import Minor_Ai

@MainActor
struct DiagramTests {
    private func process(_ labels: [String], cycle: Bool = false) -> SlideDiagram {
        var d = SlideDiagram()
        d.kind = cycle ? .cycle : .process
        for label in labels { d.insertStep(after: d.allItems.last?.id, label: label) }
        return d
    }

    private func pairs(_ d: SlideDiagram, sequence: Bool = true) -> [[String]] {
        d.allEdges.filter { $0.sequence == sequence }.map { [d.node($0.from)!.label, d.node($0.to)!.label] }
    }

    @Test func diagramsSavedBeforeOpenWithStableIdsAndAreWrittenAsBefore() throws {
        let json = #"{"center":"Minor AI","nodes":["Maps","Slides","Chat"]}"#
        let old = try JSONDecoder().decode(SlideDiagram.self, from: Data(json.utf8))
        let slide = UUID()
        let a = old.structured(slideID: slide), b = old.structured(slideID: slide)
        #expect(a.kindValue == .hierarchy && a.radial == true)
        #expect(a.allItems.map(\.id) == b.allItems.map(\.id))   // the same ids every time
        #expect(a.allItems.map(\.label) == ["Minor AI", "Maps", "Slides", "Chat"])
        #expect(a.allItems.dropFirst().allSatisfy { $0.parent == a.allItems[0].id })
        // Unchanged, it is written exactly as before.
        let written = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
        #expect(Set(written.keys) == ["center", "nodes"])
        // Changed, it keeps center and nodes for earlier apps.
        var edited = a
        edited.updateNode(a.allItems[1].id) { $0.label = "Mind maps" }
        edited.syncLegacy(title: "Title")
        #expect(edited.center == "Minor AI" && edited.nodes == ["Mind maps", "Slides", "Chat"])
        let again = try JSONDecoder().decode(SlideDiagram.self, from: JSONEncoder().encode(edited))
        #expect(again == edited)
    }

    @Test func insertingAfterAStepSplitsItsConnection() throws {
        var d = process(["A", "B", "C"])
        let a = d.allItems[0].id, c = d.allItems[2].id
        let bc = try #require(d.allEdges.first { $0.sequence && d.node($0.to)?.label == "C" }).id
        try d.connect(a, c, label: "skip")
        d.insertStep(after: a, label: "N")
        #expect(d.allItems.map(\.label) == ["A", "N", "B", "C"])
        #expect(pairs(d) == [["A", "N"], ["N", "B"], ["B", "C"]])
        #expect(d.allEdges.contains { $0.id == bc })              // the untouched connection keeps its id
        #expect(pairs(d, sequence: false) == [["A", "C"]])         // the extra one stays
        // Moving a step changes the order and its connections, not the extra one.
        d.moveStep(d.allItems[3].id, by: -3)
        #expect(d.allItems.map(\.label) == ["C", "A", "N", "B"])
        #expect(pairs(d) == [["C", "A"], ["A", "N"], ["N", "B"]])
        #expect(pairs(d, sequence: false) == [["A", "C"]])
    }

    @Test func aCycleClosesOnlyWithThreeOrMoreSteps() {
        #expect(process([], cycle: true).allEdges.isEmpty)
        #expect(process(["A"], cycle: true).allEdges.isEmpty)
        #expect(pairs(process(["A", "B"], cycle: true)) == [["A", "B"]])
        var d = process(["A", "B", "C"], cycle: true)
        #expect(pairs(d) == [["A", "B"], ["B", "C"], ["C", "A"]])
        d.insertStep(after: d.allItems[2].id, label: "D")
        #expect(pairs(d) == [["A", "B"], ["B", "C"], ["C", "D"], ["D", "A"]])
        d.remove(d.allItems[1].id)
        #expect(pairs(d) == [["A", "C"], ["C", "D"], ["D", "A"]])
    }

    @Test func removingAStepSaysWhatGoesAndJoinsItsNeighbours() throws {
        var d = process(["A", "B", "C"])
        try d.connect(d.allItems[1].id, d.allItems[0].id)
        let impact = d.impactOfRemoving(d.allItems[1].id)
        #expect(impact.edges.count == 3 && impact.reconnects && impact.children == 0)
        d.remove(d.allItems[1].id)
        #expect(pairs(d) == [["A", "C"]] && pairs(d, sequence: false).isEmpty)
    }

    @Test func aHierarchyNeverLoops() throws {
        var d = SlideDiagram()
        d.kind = .hierarchy
        let root = d.addChild(to: nil, label: "Root")
        let a = d.addChild(to: root, label: "A")
        let a1 = d.addChild(to: a, label: "A1")
        let b = d.addChild(to: root, label: "B")
        #expect(throws: DiagramProblem.sameNode) { try d.move(a, under: a) }
        #expect(throws: DiagramProblem.wouldLoop) { try d.move(a, under: a1) }
        try d.move(a1, under: b)
        #expect(d.node(a1)?.parent == b)
        #expect(d.impactOfRemoving(b).children == 1)
        var lifted = d
        lifted.remove(b, liftChildren: true)
        #expect(lifted.node(a1)?.parent == root && lifted.node(b) == nil)
        var cut = d
        cut.remove(b)
        #expect(cut.node(a1) == nil && cut.allItems.count == 2)
    }

    @Test func connectionsAreChecked() throws {
        var d = process(["A", "B"])
        let a = d.allItems[0].id, b = d.allItems[1].id
        #expect(throws: DiagramProblem.sameNode) { try d.connect(a, a) }
        #expect(throws: DiagramProblem.duplicate) { try d.connect(a, b) }
        #expect(throws: DiagramProblem.missingNode) { try d.connect(a, UUID()) }
        let back = try d.connect(b, a)
        #expect(throws: DiagramProblem.duplicate) { try d.changeEdge(back, from: a, to: b) }
        try d.changeEdge(back, from: b, to: a)
    }

    @Test func changingKindOrMatrixModeLosesNothing() throws {
        var d = process(["A", "B", "C"])
        try d.connect(d.allItems[0].id, d.allItems[2].id)
        let matrix = d.converted(to: .matrix)
        #expect(matrix.allEdges.count == d.allEdges.count)   // kept, though not drawn
        #expect(!matrix.conversionNotes(to: .matrix).isEmpty || d.conversionNotes(to: .matrix).count > 0)
        let back = matrix.converted(to: .process)
        #expect(pairs(back, sequence: false) == [["A", "C"]] && pairs(back) == [["A", "B"], ["B", "C"]])

        var m = matrix
        m.updateNode(m.allItems[0].id) { $0.quadrant = 3 }
        m.setMatrixMode(.values)
        let value = try #require(m.allItems[0].value)
        m.setMatrixMode(.quadrants)
        #expect(m.allItems[0].quadrant == 3 && m.allItems[0].value == value)
        #expect(m.quadrant(of: m.value(inQuadrant: 1)) == 1 && m.quadrant(of: m.value(inQuadrant: 2)) == 2)

        let tree = d.converted(to: .hierarchy)
        #expect(tree.allItems.filter { $0.parent == nil }.count == 1 && tree.allEdges.count == 1)
        let steps = tree.converted(to: .cycle)
        #expect(steps.allItems.map(\.label) == ["A", "B", "C"] && pairs(steps).count == 3)
    }

    @Test func boxesDontOverlapAndConnectionsEndOnTheirSides() {
        let long = "Очень длинное название шага, которое не помещается в одну строку"
        for kind in DiagramKind.allCases {
            for count in [0, 1, 4, 12] {
                var d = SlideDiagram()
                d.kind = kind
                for i in 0..<count {
                    switch kind {
                    case .hierarchy: d.addChild(to: i == 0 ? nil : d.allItems[(i - 1) / 3].id, label: i % 3 == 0 ? long : "Шаг \(i + 1)")
                    case .matrix:
                        var node = DiagramNode(label: i % 3 == 0 ? long : "Шаг \(i + 1)")
                        node.quadrant = i % 4
                        d.items = d.allItems + [node]
                    default: d.insertStep(after: d.allItems.last?.id, label: i % 3 == 0 ? long : "Шаг \(i + 1)")
                    }
                }
                let g = DiagramLayout.geometry(d, slideID: UUID(), title: "T")
                #expect(g.boxes.count == count, "\(kind) \(count): every item is drawn, none cut")
                #expect(g.empty == (count == 0))
                for box in g.boxes {
                    #expect(box.fontSize >= DiagramLayout.minFont)
                    #expect(CGRect(x: 0, y: 0, width: 1280, height: 720).insetBy(dx: -1, dy: -1).contains(box.frame), "\(kind) \(count) box inside the slide")
                }
                if !g.overflow {
                    for i in g.boxes.indices { for j in g.boxes.indices where j > i {
                        #expect(!g.boxes[i].frame.insetBy(dx: 1, dy: 1).intersects(g.boxes[j].frame), "\(kind) \(count) overlap")
                    } }
                }
                let frames = Dictionary(uniqueKeysWithValues: g.boxes.map { ($0.id, $0.frame) })
                for c in g.connectors {
                    let a = frames[c.from]!, b = frames[c.to]!
                    #expect(onSide(c.start, a, c.startSide) && onSide(c.end, b, c.endSide), "\(kind) \(count) connector ends on its boxes")
                }
            }
        }
    }

    private func onSide(_ p: CGPoint, _ r: CGRect, _ side: DiagramGeometry.Side) -> Bool {
        let close: (CGFloat, CGFloat) -> Bool = { abs($0 - $1) < 0.5 }
        switch side {
        case .top: return close(p.y, r.minY) && close(p.x, r.midX)
        case .bottom: return close(p.y, r.maxY) && close(p.x, r.midX)
        case .left: return close(p.x, r.minX) && close(p.y, r.midY)
        case .right: return close(p.x, r.maxX) && close(p.y, r.midY)
        }
    }

    @Test func aMovedBoxTakesItsConnectionsAlong() throws {
        let d = process(["A", "B", "C"])
        let slide = UUID()
        let auto = DiagramLayout.geometry(d, slideID: slide, title: "T")
        var manual = d.pinned(to: auto)
        #expect(DiagramLayout.geometry(manual, slideID: slide, title: "T").boxes.map(\.frame) == auto.boxes.map(\.frame))  // nothing jumps
        manual.updateNode(d.allItems[1].id) { $0.position = [640, 600] }
        let moved = DiagramLayout.geometry(manual, slideID: slide, title: "T")
        let b = try #require(moved.boxes.first { $0.id == d.allItems[1].id })
        #expect(abs(b.frame.midX - 640) < 0.5 && abs(b.frame.midY - 600) < 0.5)
        let into = try #require(moved.connectors.first { $0.to == b.id })
        #expect(onSide(into.end, b.frame, into.endSide))
        // Arranging automatically is its own change and puts it back.
        #expect(DiagramLayout.geometry(manual.arrangedAutomatically(), slideID: slide, title: "T").boxes.map(\.frame) == auto.boxes.map(\.frame))
    }

    @Test func powerPointGetsShapesAndAttachedConnectors() throws {
        var d = process(["Idea", "Recording", "Editing", "Publishing"])
        try d.connect(d.allItems[0].id, d.allItems[3].id, label: "fast track")
        var slide = Slide(layout: .diagram, title: "Path")
        slide.diagram = d
        var tree = SlideDiagram()
        tree.kind = .hierarchy
        let root = tree.addChild(to: nil, label: "Root")
        tree.addChild(to: root, label: "Left")
        tree.addChild(to: root, label: "Right")
        var second = Slide(layout: .diagram, title: "Tree")
        second.diagram = tree
        let deck = Deck(title: "D", slides: [slide, second])
        for (index, expected) in [(0, 4), (1, 2)] {
            let xml = DeckExport.slideXML(deck, index)
            let ids = Set(xml.matches(of: /<p:sp><p:nvSpPr><p:cNvPr id="(\d+)"/).map { String($0.1) })
            let connectors = xml.matches(of: /<p:cxnSp>.*?<\/p:cxnSp>/).map { String($0.0) }
            let attached = connectors.filter { $0.contains("stCxn") }
            #expect(attached.count == expected)
            for c in attached {
                let start = try #require(c.firstMatch(of: /stCxn id="(\d+)"/)).1, end = try #require(c.firstMatch(of: /endCxn id="(\d+)"/)).1
                #expect(ids.contains(String(start)) && ids.contains(String(end)), "connectors point at shapes on the slide")
            }
            if index == 0 {
                #expect(attached.filter { $0.contains("tailEnd") }.count == 4)          // arrows
                #expect(xml.contains("fast track") && xml.contains("Recording"))       // labels are text
            } else {
                #expect(attached.allSatisfy { $0.contains("bentConnector3") })          // tree elbows
            }
        }
    }

    // The radial diagram's middle is a real circle in PowerPoint, so every viewer draws it round.
    @Test func radialCentreIsAnEllipseInPowerPoint() {
        var radial = SlideDiagram()
        radial.kind = .hierarchy
        radial.radial = true
        let root = radial.addChild(to: nil, label: "Minor AI")
        for label in ["Maps", "Slides", "Chat"] { radial.addChild(to: root, label: label) }
        var slide = Slide(layout: .diagram, title: "Done")
        slide.diagram = radial
        let xml = DeckExport.slideXML(Deck(title: "D", slides: [slide]), 0)
        #expect(xml.matches(of: /prst="ellipse"/).count == 1)
    }
}
