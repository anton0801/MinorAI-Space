//
//  DiagramEditor.swift
//  Minor Ai
//
//  Editing a slide's diagram: the panel (Steps / Links / Style for a process, cycle or hierarchy;
//  Items / Axes / Style for a matrix) and the stage above it, where a tap selects a box and a drag
//  moves it. Every change is one command the editor can undo and redo: adding, removing, renaming,
//  connecting, moving and styling. A typed name counts when it is submitted or the field is left;
//  moving a box puts the diagram in manual arrangement, and "Arrange Automatically" is its own
//  command. Nobody has to draw an arrow with a finger: a connection is two steps chosen from lists.
//

import SwiftUI

extension SlideDiagram {
    // Every box where it is now, kept by hand from here on (nothing jumps when one box is moved).
    func pinned(to geometry: DiagramGeometry) -> SlideDiagram {
        var copy = self
        let centers = Dictionary(uniqueKeysWithValues: geometry.boxes.map { ($0.id, [Double($0.frame.midX), Double($0.frame.midY)]) })
        copy.items = allItems.map { item in
            var item = item
            if item.position == nil { item.position = centers[item.id] }
            return item
        }
        copy.arrangement = .manual
        return copy
    }

    // Back to the automatic arrangement (positions are dropped).
    func arrangedAutomatically() -> SlideDiagram {
        var copy = self
        copy.arrangement = .auto
        copy.items = allItems.map { var item = $0; item.position = nil; return item }
        return copy
    }

    var depth: Int {
        var best = 0
        for item in allItems {
            var level = 0
            var current = item.parent
            var seen: Set<UUID> = [item.id]
            while let parent = current, !seen.contains(parent), let node = node(parent) {
                seen.insert(parent)
                level += 1
                current = node.parent
            }
            best = max(best, level)
        }
        return best
    }
}

// MARK: - Panel

struct DiagramPanel: View {
    let diagram: SlideDiagram          // with ids (structured)
    @Binding var selection: UUID?
    var onChange: (SlideDiagram) -> Void
    var onDone: () -> Void

    enum Tab: Hashable { case items, links, style }

    @State private var tab: Tab = .items
    @State private var names: [UUID: String] = [:]
    @FocusState private var focused: UUID?
    @State private var converting: DiagramKind?
    @State private var removing: UUID?
    @State private var addingLink = false
    @State private var linkFrom: UUID?
    @State private var linkTo: UUID?
    @State private var problem: String?
    @State private var labeling: UUID?
    @State private var labelText = ""

    static let icons = ["lightbulb", "mic", "scissors", "paperplane", "doc.text", "person.2", "chart.bar", "calendar",
                        "checkmark.circle", "star", "flag", "target", "gearshape", "cart", "house", "book"]

    private var isMatrix: Bool { diagram.kindValue == .matrix }
    private var items: [DiagramNode] { diagram.allItems }

    var body: some View {
        VStack(spacing: 0) {
            EditorSheetHeader(title: L("Diagram"), subtitle: diagram.kindValue.name, onDone: done)
                .padding(.horizontal, 16)
                .padding(.top, 14)
            MinorSegments(items: isMatrix
                          ? [(Tab.items, "Items", nil), (Tab.links, "Axes", nil), (Tab.style, "Style", nil)]
                          : [(Tab.items, "Steps", nil), (Tab.links, "Links", nil), (Tab.style, "Style", nil)],
                          selection: $tab, height: 32)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if let problem {
                            Label(problem, systemImage: "exclamationmark.circle")
                                .minorFont(13, maxScale: 1.3)
                                .foregroundColor(MinorColor.dangerText)
                        }
                        switch tab {
                        case .items: isMatrix ? AnyView(matrixItems) : AnyView(steps)
                        case .links: isMatrix ? AnyView(axesTab) : AnyView(links)
                        case .style: AnyView(styleTab)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .onChange(of: selection) { id in
                    guard let id, tab == .items else { return }
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
                }
            }
            if tab == .items { addButton }
        }
        .foregroundColor(MinorColor.textPrimary)
        .background(MinorColor.editorSheet.ignoresSafeArea())
        .preferredColorScheme(.dark)
        #if DEBUG
        .onAppear {
            // -demoDiagramTab links|style: opens on that tab.
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-demoDiagramTab"), args.indices.contains(i + 1) {
                tab = args[i + 1] == "links" ? .links : args[i + 1] == "style" ? .style : .items
            }
        }
        #endif
        .onChange(of: focused) { [focused] _ in
            // Leaving a name field counts as submitting it.
            if let previous = focused { commitName(previous) }
        }
        .confirmationDialog(converting.map { L("Change to \($0.name)?") } ?? "", isPresented: Binding(get: { converting != nil }, set: { if !$0 { converting = nil } }),
                            titleVisibility: .visible, presenting: converting) { kind in
            Button(L("Change to \(kind.name)")) { change(diagram.converted(to: kind)) }
            Button("Cancel", role: .cancel) {}
        } message: { kind in
            Text(diagram.conversionNotes(to: kind).joined(separator: "\n"))
        }
        .confirmationDialog(removalTitle, isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible, presenting: removing) { id in
            if diagram.kindValue == .hierarchy, diagram.impactOfRemoving(id).children > 0 {
                Button("Delete with Its Branch", role: .destructive) { remove(id, lift: false) }
                Button("Delete, Keep Its Children") { remove(id, lift: true) }
            } else {
                Button("Delete", role: .destructive) { remove(id, lift: false) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { id in
            Text(removalMessage(id))
        }
        .alert("Connection Label", isPresented: Binding(get: { labeling != nil }, set: { if !$0 { labeling = nil } })) {
            TextField("Label", text: $labelText)
            Button("Save") {
                guard let id = labeling else { return }
                var d = diagram
                d.updateEdge(id) { $0.label = String(labelText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40)) }
                change(d)
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Steps

    private var steps: some View {
        VStack(spacing: 8) {
            if items.isEmpty {
                Text(diagram.kindValue == .hierarchy ? "Add the top item." : "Add the first step.")
                    .minorFont(14, maxScale: 1.3)
                    .foregroundColor(MinorColor.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(Array(orderedItems.enumerated()), id: \.element.0.id) { i, entry in
                stepRow(entry.0, number: i + 1, level: entry.1)
                    .id(entry.0.id)
            }
        }
    }

    // A hierarchy lists its items as a tree; steps in their order.
    private var orderedItems: [(DiagramNode, Int)] {
        guard diagram.kindValue == .hierarchy else { return items.map { ($0, 0) } }
        var result: [(DiagramNode, Int)] = []
        var seen: Set<UUID> = []
        func walk(_ parent: UUID?, _ level: Int) {
            for item in items where item.parent == parent && !seen.contains(item.id) {
                seen.insert(item.id)
                result.append((item, level))
                walk(item.id, level + 1)
            }
        }
        walk(nil, 0)
        result += items.filter { !seen.contains($0.id) }.map { ($0, 0) }
        return result
    }

    private func stepRow(_ item: DiagramNode, number: Int, level: Int) -> some View {
        let chosen = selection == item.id
        return HStack(spacing: 10) {
            if diagram.kindValue != .hierarchy {
                Text("\(number)")
                    .minorFont(14, .semibold, maxScale: 1.2)
                    .monospacedDigit()
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            iconMenu(item)
            TextField("", text: Binding(get: { names[item.id] ?? item.label }, set: { names[item.id] = $0 }))
                .minorFont(15, maxScale: 1.3)
                .focused($focused, equals: item.id)
                .submitLabel(.done)
                .onSubmit { commitName(item.id) }
                .accessibilityLabel(Text(L("Name of step \(number)")))
            Menu {
                stepMenu(item)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text(L("More for \(item.label)")))
        }
        .padding(.leading, 10 + CGFloat(level) * 18)
        .padding(.trailing, 4)
        .frame(minHeight: 52)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(chosen ? 0.1 : 0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(chosen ? MinorColor.accent.opacity(0.7) : Color.white.opacity(0.06), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { selection = item.id }
    }

    private func iconMenu(_ item: DiagramNode) -> some View {
        Menu {
            Button { setIcon(item.id, nil) } label: { Label("No Icon", systemImage: "nosign") }
            ForEach(Self.icons, id: \.self) { name in
                Button { setIcon(item.id, name) } label: { Label(name, systemImage: name) }
            }
        } label: {
            Image(systemName: item.icon ?? "plus")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(item.icon == nil ? MinorColor.textTertiary : .black)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 9).fill(item.icon == nil ? Color.white.opacity(0.06) : MinorColor.accent))
        }
        .accessibilityLabel(item.icon == nil ? Text("Add Icon") : Text("Change Icon"))
    }

    @ViewBuilder
    private func stepMenu(_ item: DiagramNode) -> some View {
        switch diagram.kindValue {
        case .process, .cycle:
            Button { insert(after: item.id) } label: { Label("Insert Step After", systemImage: "plus") }
            Button { move(item.id, -1) } label: { Label("Move Earlier", systemImage: "arrow.up") }
                .disabled(items.first?.id == item.id)
            Button { move(item.id, 1) } label: { Label("Move Later", systemImage: "arrow.down") }
                .disabled(items.last?.id == item.id)
        case .hierarchy:
            Button { addChild(to: item.id) } label: { Label("Add Item Under It", systemImage: "arrow.turn.down.right") }
            if item.parent != nil {
                Menu {
                    ForEach(items.filter { $0.id != item.id && $0.id != item.parent && !diagram.descendants(of: item.id).contains($0.id) }) { target in
                        Button(target.label.isEmpty ? L("Untitled") : target.label) { reparent(item.id, under: target.id) }
                    }
                } label: { Label("Move Under…", systemImage: "arrow.uturn.right") }
            }
        case .matrix:
            EmptyView()
        }
        Divider()
        Button(role: .destructive) { askRemove(item.id) } label: { Label("Delete", systemImage: "trash") }
    }

    private var addButton: some View {
        Button(action: add) {
            Label(isMatrix ? L("Add Item") : diagram.kindValue == .hierarchy ? L("Add Item") : L("Add Step"), systemImage: "plus")
                .minorFont(17, .semibold, maxScale: 1.3)
                .foregroundColor(.black)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white))
        }
        .buttonStyle(PressScale())
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    // MARK: Links

    private var links: some View {
        VStack(alignment: .leading, spacing: 8) {
            let edges = drawnLinks
            if edges.isEmpty {
                Text("No connections yet.")
                    .minorFont(14, maxScale: 1.3)
                    .foregroundColor(MinorColor.textTertiary)
            }
            ForEach(Array(edges.enumerated()), id: \.element.id) { i, edge in
                linkRow(edge, number: i + 1)
            }
            if addingLink {
                newLink
            } else {
                Button {
                    linkFrom = selection ?? items.first?.id
                    linkTo = items.first { $0.id != linkFrom }?.id
                    problem = nil
                    addingLink = true
                } label: {
                    Label("Add Connection", systemImage: "plus")
                        .minorFont(15, .medium, maxScale: 1.3)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.18), lineWidth: 1))
                }
                .buttonStyle(PressScale())
                .disabled(items.count < 2)
            }
            arrangementRow.padding(.top, 6)
            Text(diagram.kindValue == .hierarchy ? "Lines follow the parents." : "Connections follow the steps.")
                .minorFont(12, style: .caption1, maxScale: 1.3)
                .foregroundColor(MinorColor.textTertiary)
                .padding(.leading, 4)
        }
    }

    // A hierarchy's parent links (from the parents) and every saved connection.
    private var drawnLinks: [DiagramEdge] {
        var list: [DiagramEdge] = []
        if diagram.kindValue == .hierarchy {
            list += items.compactMap { item in
                item.parent.map { DiagramEdge(id: SlideDiagram.stableID(item.id, "parent"), from: $0, to: item.id, directed: false, sequence: true) }
            }
        }
        return list + diagram.allEdges
    }

    private func linkRow(_ edge: DiagramEdge, number: Int) -> some View {
        let parentLink = diagram.kindValue == .hierarchy && edge.sequence
        return HStack(spacing: 8) {
            Text("\(number)")
                .minorFont(14, .semibold, maxScale: 1.2)
                .monospacedDigit()
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.white.opacity(0.08)))
            endpoint(edge.from)
            Image(systemName: edge.directed ? "arrow.right" : "minus")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(MinorColor.textSecondary)
            endpoint(edge.to)
            Spacer(minLength: 0)
            Menu {
                if parentLink {
                    Menu {
                        ForEach(items.filter { $0.id != edge.to && !diagram.descendants(of: edge.to).contains($0.id) && $0.id != edge.from }) { target in
                            Button(target.label) { reparent(edge.to, under: target.id) }
                        }
                    } label: { Label("Move Under…", systemImage: "arrow.uturn.right") }
                } else {
                    if !edge.sequence {
                        Menu {
                            ForEach(items.filter { $0.id != edge.to }) { node in Button(node.label) { retarget(edge.id, from: node.id) } }
                        } label: { Label("Change Start", systemImage: "arrow.left.to.line") }
                        Menu {
                            ForEach(items.filter { $0.id != edge.from }) { node in Button(node.label) { retarget(edge.id, to: node.id) } }
                        } label: { Label("Change End", systemImage: "arrow.right.to.line") }
                        Button { retarget(edge.id, from: edge.to, to: edge.from) } label: { Label("Reverse", systemImage: "arrow.left.arrow.right") }
                    }
                    Button {
                        labelText = edge.label
                        labeling = edge.id
                    } label: { Label("Label", systemImage: "textformat") }
                    Button {
                        var d = diagram
                        d.updateEdge(edge.id) { $0.directed.toggle() }
                        change(d)
                    } label: { Label(edge.directed ? "Without Arrow" : "With Arrow", systemImage: "arrow.right") }
                    if !edge.sequence {
                        Divider()
                        Button(role: .destructive) {
                            var d = diagram
                            d.removeEdge(edge.id)
                            change(d)
                        } label: { Label("Delete Connection", systemImage: "trash") }
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text(L("More for connection \(number)")))
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .frame(minHeight: 54)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(number): \(label(of: edge.from)) \(edge.directed ? "→" : "–") \(label(of: edge.to))\(edge.label.isEmpty ? "" : ", " + edge.label)"))
    }

    private func label(of id: UUID) -> String { diagram.node(id)?.label ?? "" }

    private func endpoint(_ id: UUID) -> some View {
        let node = diagram.node(id)
        return HStack(spacing: 8) {
            if let icon = node?.icon {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8).fill(MinorColor.accent))
            }
            Text(node?.label ?? "")
                .minorFont(14, maxScale: 1.3)
                .lineLimit(1)
        }
        .frame(maxWidth: 120, alignment: .leading)
    }

    private var newLink: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                picker(L("From (connection)"), selection: $linkFrom)
                Image(systemName: "arrow.right").foregroundColor(MinorColor.textSecondary)
                picker(L("To (connection)"), selection: $linkTo)
            }
            HStack {
                Button("Cancel") { addingLink = false }
                    .minorFont(15, maxScale: 1.3)
                    .foregroundColor(MinorColor.textSecondary)
                Spacer()
                Button {
                    guard let from = linkFrom, let to = linkTo else { return }
                    var d = diagram
                    do {
                        try d.connect(from, to)
                        change(d)
                        addingLink = false
                    } catch {
                        problem = message(error)
                    }
                } label: {
                    Text("Connect")
                        .minorFont(15, .semibold, maxScale: 1.3)
                        .foregroundColor(.black)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 40)
                        .background(Capsule().fill(Color.white))
                }
                .buttonStyle(PressScale())
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
    }

    private func picker(_ title: String, selection: Binding<UUID?>) -> some View {
        Menu {
            ForEach(items) { node in
                Button(node.label.isEmpty ? L("Untitled") : node.label) { selection.wrappedValue = node.id }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).minorFont(11, style: .caption2, maxScale: 1.2).foregroundColor(MinorColor.textTertiary)
                Text(selection.wrappedValue.flatMap { diagram.node($0)?.label } ?? L("Choose"))
                    .minorFont(15, .medium, maxScale: 1.3)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .frame(minHeight: 46)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
        }
        .accessibilityLabel(Text(title))
    }

    private var arrangementRow: some View {
        Menu {
            Button {
                change(diagram.arrangedAutomatically())
            } label: { Label("Arrange Automatically", systemImage: "wand.and.stars") }
            Button {
                selection = selection ?? items.first?.id
            } label: { Label("By Hand: Drag the Boxes on the Slide", systemImage: "hand.draw") }
        } label: {
            HStack {
                Text("Arrangement").minorFont(16, maxScale: 1.3)
                Spacer()
                Text(diagram.arrangement == .manual ? L("By hand") : L("Automatic"))
                    .minorFont(16, maxScale: 1.3)
                    .foregroundColor(MinorColor.textSecondary)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundColor(MinorColor.textTertiary)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
        }
        .foregroundColor(MinorColor.textPrimary)
    }

    // MARK: Matrix

    private var matrixItems: some View {
        VStack(spacing: 8) {
            ForEach(items) { item in
                HStack(spacing: 8) {
                    TextField("", text: Binding(get: { names[item.id] ?? item.label }, set: { names[item.id] = $0 }))
                        .minorFont(15, maxScale: 1.3)
                        .focused($focused, equals: item.id)
                        .submitLabel(.done)
                        .onSubmit { commitName(item.id) }
                    if diagram.matrix == .values {
                        valueField(item, axis: 0)
                        valueField(item, axis: 1)
                    } else {
                        Menu {
                            ForEach(0..<4, id: \.self) { q in
                                Button(quadrantName(q)) {
                                    var d = diagram
                                    let value = d.value(inQuadrant: q)
                                    d.updateNode(item.id) { $0.quadrant = q; $0.value = value }
                                    change(d)
                                }
                            }
                        } label: {
                            Text(quadrantName(item.quadrant ?? 0))
                                .minorFont(13, maxScale: 1.2)
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .frame(minHeight: 34)
                                .background(Capsule().fill(Color.white.opacity(0.08)))
                        }
                    }
                    Button(role: .destructive) { askRemove(item.id) } label: {
                        Image(systemName: "trash").font(.system(size: 14)).frame(width: 36, height: 40)
                    }
                    .accessibilityLabel(Text(L("Delete \(item.label)")))
                }
                .padding(.leading, 12)
                .frame(minHeight: 52)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(selection == item.id ? 0.1 : 0.05)))
                .id(item.id)
                .onTapGesture { selection = item.id }
            }
        }
    }

    private func quadrantName(_ q: Int) -> String {
        let name = diagram.axesValue.quadrants.indices.contains(q) ? diagram.axesValue.quadrants[q] : ""
        return name.isEmpty ? L("Quadrant \(q + 1)") : name
    }

    private func valueField(_ item: DiagramNode, axis: Int) -> some View {
        let value = item.value ?? diagram.value(inQuadrant: item.quadrant ?? 0)
        return TextField(axis == 0 ? "X" : "Y", value: Binding(get: { value[axis] }, set: { new in
            var d = diagram
            var v = item.value ?? value
            v[axis] = new
            let quadrant = d.quadrant(of: v)
            d.updateNode(item.id) { node in
                node.value = v
                node.quadrant = quadrant
            }
            change(d)
        }), format: .number.precision(.fractionLength(0...1)))
        .keyboardType(.decimalPad)
        .multilineTextAlignment(.center)
        .frame(width: 52, height: 34)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
        .accessibilityLabel(Text(axis == 0 ? L("Horizontal value") : L("Vertical value")))
    }

    private var axesTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            MinorSegments(items: [(MatrixMode.quadrants, "2 × 2", nil), (MatrixMode.values, "By Values", nil)],
                          selection: Binding(get: { diagram.matrix ?? .quadrants }, set: { mode in
                              var d = diagram
                              d.setMatrixMode(mode)
                              change(d)
                          }), height: 32)
            axisFields(L("Horizontal"), \.x)
            axisFields(L("Vertical"), \.y)
            if diagram.matrix != .values {
                Text("Quadrants").minorFont(13, .semibold, maxScale: 1.3).foregroundColor(MinorColor.textTertiary)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(0..<4, id: \.self) { q in
                        commitField(L("Quadrant \(q + 1)"), diagram.axesValue.quadrants.indices.contains(q) ? diagram.axesValue.quadrants[q] : "") { text in
                            var d = diagram
                            var axes = d.axesValue
                            while axes.quadrants.count < 4 { axes.quadrants.append("") }
                            axes.quadrants[q] = text
                            d.axes = axes
                            change(d)
                        }
                    }
                }
            }
        }
    }

    private func axisFields(_ title: String, _ path: WritableKeyPath<DiagramAxes, DiagramAxis>) -> some View {
        let axis = diagram.axesValue[keyPath: path]
        func set(_ change: (inout DiagramAxis) -> Void) {
            var d = diagram
            var axes = d.axesValue
            change(&axes[keyPath: path])
            d.axes = axes
            self.change(d)
        }
        return VStack(alignment: .leading, spacing: 6) {
            Text(title).minorFont(13, .semibold, maxScale: 1.3).foregroundColor(MinorColor.textTertiary)
            commitField(L("Axis name"), axis.title) { text in set { $0.title = text } }
            HStack(spacing: 8) {
                commitField(L("Low end"), axis.low) { text in set { $0.low = text } }
                commitField(L("High end"), axis.high) { text in set { $0.high = text } }
            }
            if diagram.matrix == .values {
                HStack(spacing: 8) {
                    numberField(L("From"), axis.min) { v in set { $0.min = min(v, $0.max - 0.1) } }
                    numberField(L("To"), axis.max) { v in set { $0.max = max(v, $0.min + 0.1) } }
                }
            }
        }
    }

    private func commitField(_ placeholder: String, _ value: String, commit: @escaping (String) -> Void) -> some View {
        CommitTextField(placeholder: placeholder, value: value, commit: commit)
    }

    private func numberField(_ title: String, _ value: Double, commit: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 6) {
            Text(title).minorFont(13, maxScale: 1.2).foregroundColor(MinorColor.textTertiary)
            TextField(title, value: Binding(get: { value }, set: commit), format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .padding(.horizontal, 10)
                .frame(minHeight: 40)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
        }
    }

    // MARK: Style

    private var styleTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Kind").minorFont(13, .semibold, maxScale: 1.3).foregroundColor(MinorColor.textTertiary)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(DiagramKind.allCases) { kind in
                    let chosen = diagram.kindValue == kind
                    Button {
                        guard !chosen else { return }
                        converting = kind
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: kind.icon).font(.system(size: 16, weight: .semibold))
                            Text(kind.name).minorFont(15, .medium, maxScale: 1.3)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 48)
                        .background(RoundedRectangle(cornerRadius: 12).fill(chosen ? Color.white : Color.white.opacity(0.06)))
                        .foregroundColor(chosen ? .black : MinorColor.textPrimary)
                    }
                    .buttonStyle(PressScale())
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                }
            }
            if diagram.kindValue == .hierarchy {
                Text("Layout").minorFont(13, .semibold, maxScale: 1.3).foregroundColor(MinorColor.textTertiary)
                MinorSegments(items: [(false, "Tree", nil), (true, "Around the Center", nil)],
                              selection: Binding(get: { diagram.radial == true }, set: { radial in
                                  guard !radial || diagram.depth <= 1 else {
                                      problem = L("Around the center shows one level. Move the deeper items up first.")
                                      return
                                  }
                                  var d = diagram
                                  d.radial = radial
                                  change(d)
                              }), height: 32)
            }
            if !isMatrix {
                Text("Boxes").minorFont(13, .semibold, maxScale: 1.3).foregroundColor(MinorColor.textTertiary)
                MinorSegments(items: [(true, "Filled", nil), (false, "Outline (boxes)", nil)],
                              selection: Binding(get: { diagram.filled != false }, set: { filled in
                                  var d = diagram
                                  d.filled = filled
                                  change(d)
                              }), height: 32)
                Toggle(isOn: Binding(get: { diagram.showIcons != false }, set: { show in
                    var d = diagram
                    d.showIcons = show
                    change(d)
                })) {
                    Text("Show Icons").minorFont(15, maxScale: 1.3)
                }
                .tint(MinorColor.accent)
            }
        }
    }

    // MARK: Commands

    private func change(_ new: SlideDiagram) {
        problem = nil
        onChange(new)
    }

    private func done() {
        if let field = focused { commitName(field) }
        focused = nil
        onDone()
    }

    private func commitName(_ id: UUID) {
        guard let text = names[id] else { return }
        names[id] = nil
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard trimmed != diagram.node(id)?.label else { return }
        var d = diagram
        d.updateNode(id) { $0.label = trimmed }
        change(d)
    }

    private func setIcon(_ id: UUID, _ icon: String?) {
        var d = diagram
        d.updateNode(id) { $0.icon = icon }
        if icon != nil { d.showIcons = true }
        change(d)
    }

    private func add() {
        var d = diagram
        let id: UUID
        switch d.kindValue {
        case .process, .cycle:
            id = d.insertStep(after: selection ?? d.allItems.last?.id, label: L("New step"))
        case .hierarchy:
            id = d.addChild(to: selection, label: L("New item"))
            if d.allItems.count == 1 { d.updateNode(id) { $0.parent = nil } }
        case .matrix:
            var node = DiagramNode(label: L("New item"))
            node.quadrant = selection.flatMap { d.node($0)?.quadrant } ?? 0
            node.value = d.value(inQuadrant: node.quadrant ?? 0)
            d.items = d.allItems + [node]
            id = node.id
        }
        change(d)
        selection = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { focused = id }
    }

    private func insert(after id: UUID) {
        var d = diagram
        let new = d.insertStep(after: id, label: L("New step"))
        change(d)
        selection = new
    }

    private func addChild(to parent: UUID) {
        var d = diagram
        let new = d.addChild(to: parent, label: L("New item"))
        change(d)
        selection = new
    }

    private func move(_ id: UUID, _ offset: Int) {
        var d = diagram
        d.moveStep(id, by: offset)
        change(d)
    }

    private func reparent(_ id: UUID, under parent: UUID) {
        var d = diagram
        do {
            try d.move(id, under: parent)
            change(d)
        } catch {
            problem = message(error)
        }
    }

    private func retarget(_ id: UUID, from: UUID? = nil, to: UUID? = nil) {
        var d = diagram
        do {
            try d.changeEdge(id, from: from, to: to)
            change(d)
        } catch {
            problem = message(error)
        }
    }

    // Removing asks first when it takes connections or ideas below with it.
    private func askRemove(_ id: UUID) {
        let impact = diagram.impactOfRemoving(id)
        if impact.edges.isEmpty && impact.children == 0 {
            remove(id, lift: false)
        } else {
            removing = id
        }
    }

    private func remove(_ id: UUID, lift: Bool) {
        var d = diagram
        d.remove(id, liftChildren: lift)
        if selection == id { selection = nil }
        change(d)
    }

    private var removalTitle: String {
        removing.flatMap { diagram.node($0) }.map { L("Delete “\($0.label)”?") } ?? ""
    }

    private func removalMessage(_ id: UUID) -> String {
        let impact = diagram.impactOfRemoving(id)
        var lines: [String] = []
        if impact.children > 0 { lines.append(L("Items under it: \(impact.children).")) }
        let extra = impact.edges.filter { !$0.sequence }.count
        if extra > 0 { lines.append(L("Connections that go with it: \(extra).")) }
        if impact.reconnects { lines.append(L("The steps before and after it will be connected.")) }
        return lines.joined(separator: " ")
    }

    private func message(_ error: Error) -> String {
        switch error as? DiagramProblem {
        case .sameNode?: return L("A connection needs two different steps.")
        case .duplicate?: return L("These steps are already connected.")
        case .wouldLoop?: return L("An item can’t go under itself or its own branch.")
        default: return L("That step isn’t on the diagram any more.")
        }
    }
}

// A text field that commits once, when submitted or left.
private struct CommitTextField: View {
    let placeholder: String
    let value: String
    var commit: (String) -> Void
    @State private var text: String?
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: Binding(get: { text ?? value }, set: { text = $0 }))
            .minorFont(15, maxScale: 1.3)
            .focused($focused)
            .submitLabel(.done)
            .onSubmit(save)
            .onChange(of: focused) { if !$0 { save() } }
            .padding(.horizontal, 10)
            .frame(minHeight: 42)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
    }

    private func save() {
        guard let text else { return }
        self.text = nil
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        if trimmed != value { commit(trimmed) }
    }
}

// MARK: - Stage

// The slide while its diagram is edited: a tap selects a box, a drag moves it (one command when
// the finger lifts). In a matrix a drag changes the item's quadrant or values.
struct DiagramStage: View {
    let slide: Slide
    let deck: Deck
    let index: Int
    @Binding var selection: UUID?
    var onChange: (SlideDiagram) -> Void

    @State private var dragging: UUID?
    @State private var offset: CGSize = .zero

    private var diagram: SlideDiagram { (slide.diagram ?? SlideDiagram(center: slide.title)).structured(slideID: slide.id) }

    private func geometry(_ d: SlideDiagram) -> DiagramGeometry {
        DiagramLayout.geometry(d, slideID: slide.id, title: slide.title, scale: CGFloat(slide.text?.body.scale ?? 1))
    }

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / SlideView.size.width
            SlideCanvas(slide: shown, deck: deck, index: index, selectedPart: selection.map(DiagramView.key))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let start = CGPoint(x: value.startLocation.x / scale, y: value.startLocation.y / scale)
                            if dragging == nil, hypot(value.translation.width, value.translation.height) > 6,
                               let box = geometry(diagram).boxes.first(where: { $0.frame.contains(start) }) {
                                dragging = box.id
                                selection = box.id
                            }
                            if dragging != nil { offset = CGSize(width: value.translation.width / scale, height: value.translation.height / scale) }
                        }
                        .onEnded { value in
                            let start = CGPoint(x: value.startLocation.x / scale, y: value.startLocation.y / scale)
                            if let id = dragging {
                                drop(id)
                            } else {
                                // A tap: the box under it, or nothing.
                                selection = geometry(diagram).boxes.first { $0.frame.insetBy(dx: -6, dy: -6).contains(start) }?.id
                                Haptics.selection()
                            }
                            dragging = nil
                            offset = .zero
                        }
                )
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Slide \(index + 1): diagram"))
        .accessibilityValue(Text(selection.flatMap { diagram.node($0)?.label }.map { L("Selected: \($0)") } ?? ""))
    }

    // The slide with the box under the finger where it is being dragged.
    private var shown: Slide {
        guard let id = dragging else { return slide }
        var copy = slide
        copy.diagram = moved(id, by: offset)
        return copy
    }

    private func moved(_ id: UUID, by offset: CGSize) -> SlideDiagram {
        let d = diagram
        let current = geometry(d)
        guard let box = current.boxes.first(where: { $0.id == id }) else { return d }
        let center = CGPoint(x: box.frame.midX + offset.width, y: box.frame.midY + offset.height)
        if d.kindValue == .matrix, let grid = current.axes?.grid {
            var m = d
            if m.matrix == .values {
                let axes = m.axesValue
                let fx = Double((center.x - grid.minX) / grid.width), fy = Double((grid.maxY - center.y) / grid.height)
                let value = [axes.x.min + min(max(fx, 0), 1) * (axes.x.max - axes.x.min), axes.y.min + min(max(fy, 0), 1) * (axes.y.max - axes.y.min)]
                let quadrant = m.quadrant(of: value)
                m.updateNode(id) { $0.value = value.map { ($0 * 10).rounded() / 10 }; $0.quadrant = quadrant }
            } else {
                let q = (center.y < grid.midY ? 0 : 2) + (center.x < grid.midX ? 0 : 1)
                let value = m.value(inQuadrant: q)
                m.updateNode(id) { $0.quadrant = q; $0.value = value }
            }
            return m
        }
        var pinned = d.pinned(to: current)
        pinned.updateNode(id) { $0.position = [Double(center.x), Double(center.y)] }
        return pinned
    }

    private func drop(_ id: UUID) {
        guard abs(offset.width) > 2 || abs(offset.height) > 2 else { return }
        onChange(moved(id, by: offset))
        Haptics.impact(.light)
    }
}

// The slide above the diagram's panel stays usable (select and drag boxes) while the panel is half up.
struct StageStaysUsable: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content.presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.52)))
        } else {
            content
        }
    }
}
