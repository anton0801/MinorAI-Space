//
//  DeckElementEditor.swift
//  Minor Ai
//
//  Placing free elements on a slide: tap to select (tap again to edit), drag to move with guides
//  that snap to the slide and to other elements, corner handles to resize, the top handle to
//  turn. And the sheet with an element's settings.
//

import PhotosUI
import SwiftUI

struct SlideElementEditor: View {
    let deck: Deck
    let index: Int
    @Binding var selection: UUID?
    var onChange: ([SlideElement]) -> Void
    var onEdit: (SlideElement) -> Void

    @State private var draft: [SlideElement]?
    @State private var origin: CGRect?
    @State private var guides: [Guide] = []

    struct Guide: Hashable { let vertical: Bool; let at: CGFloat }

    private var slide: Slide { deck.slides[index] }
    private var style: SlideStyle { deck.style(for: slide) }
    private var elements: [SlideElement] { draft ?? slide.elements }

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / SlideView.size.width
            ZStack(alignment: .topLeading) {
                SlideView(slide: slide, style: style, index: index, total: deck.slides.count, deckTitle: deck.title,
                          sectionNumber: SlideCanvas.sectionNumber(of: index, in: deck), brand: deck.brand, showElements: false)
                    .scaleEffect(s, anchor: .topLeading)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                    .allowsHitTesting(false)
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { selection = nil }
                ForEach(elements) { element in
                    SlideElementView(element: element, style: style)
                        .rotationEffect(.degrees(element.rotation))
                        .opacity(element.opacity)
                        .scaleEffect(s)
                        .frame(width: element.w * s, height: element.h * s)
                        .contentShape(Rectangle())
                        .position(x: (element.x + element.w / 2) * s, y: (element.y + element.h / 2) * s)
                        .onTapGesture {
                            if selection == element.id { onEdit(element) } else { selection = element.id }
                            Haptics.selection()
                        }
                        .gesture(moveGesture(element, scale: s))
                        .accessibilityElement()
                        .accessibilityLabel(Self.describe(element))
                        .accessibilityAddTraits(selection == element.id ? [.isButton, .isSelected] : .isButton)
                }
                ForEach(guides, id: \.self) { guide in
                    Rectangle()
                        .fill(Color(hex: "#FF4FD8"))
                        .frame(width: guide.vertical ? 1 : geo.size.width, height: guide.vertical ? geo.size.height : 1)
                        .offset(x: guide.vertical ? guide.at * s : 0, y: guide.vertical ? 0 : guide.at * s)
                        .allowsHitTesting(false)
                }
                if let selected = elements.first(where: { $0.id == selection }) {
                    chrome(selected, scale: s)
                }
            }
            .coordinateSpace(name: "slide")
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipped()
    }

    static func describe(_ element: SlideElement) -> String {
        switch element.kind {
        case .text: return L("Text: \(element.text)")
        case .shape: return element.text.isEmpty ? L("Shape") : L("Shape: \(element.text)")
        case .icon: return L("Icon")
        case .image: return L("Picture")
        case .table: return L("Table")
        case .chart: return L("Chart: \(element.chart?.title ?? "")")
        case .qr: return L("QR code")
        }
    }

    // MARK: - Selection: outline, resize handles, turn handle

    private func chrome(_ element: SlideElement, scale s: CGFloat) -> some View {
        let frame = CGRect(x: element.x * s, y: element.y * s, width: element.w * s, height: element.h * s)
        let corners: [(UnitPoint, CGPoint)] = [
            (.topLeading, CGPoint(x: frame.minX, y: frame.minY)), (.topTrailing, CGPoint(x: frame.maxX, y: frame.minY)),
            (.bottomLeading, CGPoint(x: frame.minX, y: frame.maxY)), (.bottomTrailing, CGPoint(x: frame.maxX, y: frame.maxY)),
        ]
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .stroke(MinorColor.accent, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                .frame(width: frame.width, height: frame.height)
                .rotationEffect(.degrees(element.rotation))
                .position(x: frame.midX, y: frame.midY)
                .allowsHitTesting(false)
            ForEach(corners.indices, id: \.self) { i in
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().stroke(MinorColor.accent, lineWidth: 2))
                    .frame(width: 18, height: 18)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
                    .position(corners[i].1)
                    .gesture(resizeGesture(element, corner: corners[i].0, scale: s))
                    .accessibilityHidden(true)
            }
            // Turn handle above the element.
            Path { p in
                p.move(to: CGPoint(x: frame.midX, y: frame.minY))
                p.addLine(to: CGPoint(x: frame.midX, y: frame.minY - 26))
            }
            .stroke(MinorColor.accent, lineWidth: 1.5)
            .allowsHitTesting(false)
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.black)
                .frame(width: 22, height: 22)
                .background(Circle().fill(MinorColor.accent))
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
                .position(x: frame.midX, y: frame.minY - 34)
                .gesture(rotateGesture(element, scale: s))
                .accessibilityHidden(true)
        }
    }

    // MARK: - Gestures

    private func update(_ id: UUID, _ change: (inout SlideElement) -> Void) {
        var list = draft ?? slide.elements
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        change(&list[i])
        draft = list
    }

    private func commit() {
        if let draft, draft != slide.elements { onChange(draft) }
        draft = nil
        origin = nil
        guides = []
    }

    private func moveGesture(_ element: SlideElement, scale s: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("slide"))
            .onChanged { value in
                if origin == nil {
                    origin = element.frame
                    selection = element.id
                }
                guard let start = origin else { return }
                var rect = start.offsetBy(dx: value.translation.width / s, dy: value.translation.height / s)
                rect = snap(rect, moving: element.id)
                // At least 40 units stay on the slide, so an element can't be dragged out of reach.
                let x = min(max(rect.minX, 40 - rect.width), 1280 - 40)
                let y = min(max(rect.minY, 40 - rect.height), 720 - 40)
                update(element.id) { $0.x = x; $0.y = y }
            }
            .onEnded { _ in commit() }
    }

    private func resizeGesture(_ element: SlideElement, corner: UnitPoint, scale s: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("slide"))
            .onChanged { value in
                if origin == nil { origin = element.frame }
                guard let start = origin else { return }
                let dx = value.translation.width / s, dy = value.translation.height / s
                var minX = start.minX, minY = start.minY, maxX = start.maxX, maxY = start.maxY
                if corner.x == 0 { minX += dx } else { maxX += dx }
                if corner.y == 0 { minY += dy } else { maxY += dy }
                var w = max(maxX - minX, 30), h = max(maxY - minY, 24)
                if element.keepsAspect {
                    let side = max(w, h)
                    w = side
                    h = side
                }
                let x = corner.x == 0 ? start.maxX - w : start.minX
                let y = corner.y == 0 ? start.maxY - h : start.minY
                update(element.id) { $0.x = x; $0.y = y; $0.w = w; $0.h = h }
            }
            .onEnded { _ in commit() }
    }

    private func rotateGesture(_ element: SlideElement, scale s: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("slide"))
            .onChanged { value in
                let center = CGPoint(x: (element.x + element.w / 2) * s, y: (element.y + element.h / 2) * s)
                var angle = atan2(value.location.y - center.y, value.location.x - center.x) * 180 / .pi + 90
                // Holds at the quarter and eighth turns.
                let nearest = (angle / 45).rounded() * 45
                if abs(angle - nearest) < 4 { angle = nearest }
                angle = (angle + 360).truncatingRemainder(dividingBy: 360)
                update(element.id) { $0.rotation = angle }
            }
            .onEnded { _ in
                Haptics.selection()
                commit()
            }
    }

    // Lines up with the slide's middle and margins and with other elements' edges and middles.
    private func snap(_ rect: CGRect, moving id: UUID) -> CGRect {
        let threshold: CGFloat = 9
        var xs: [CGFloat] = [80, 640, 1200]
        var ys: [CGFloat] = [60, 360, 660]
        for other in elements where other.id != id {
            xs += [other.frame.minX, other.frame.midX, other.frame.maxX]
            ys += [other.frame.minY, other.frame.midY, other.frame.maxY]
        }
        var result = rect
        var found: [Guide] = []
        func best(_ candidates: [CGFloat], _ edges: [CGFloat]) -> (CGFloat, CGFloat)? {
            var pick: (CGFloat, CGFloat)?
            for target in candidates {
                for edge in edges where abs(target - edge) < threshold {
                    if pick == nil || abs(target - edge) < abs(pick!.0) { pick = (target - edge, target) }
                }
            }
            return pick
        }
        if let (shift, line) = best(xs, [rect.minX, rect.midX, rect.maxX]) {
            result.origin.x += shift
            found.append(Guide(vertical: true, at: line))
        }
        if let (shift, line) = best(ys, [rect.minY, rect.midY, rect.maxY]) {
            result.origin.y += shift
            found.append(Guide(vertical: false, at: line))
        }
        if found != guides {
            if !found.isEmpty && found.count > guides.count { Haptics.selection() }
            guides = found
        }
        return result
    }
}

// MARK: - An element's settings

struct ElementInspector: View {
    let style: SlideStyle
    let theme: AppTheme
    var onSave: (SlideElement) -> Void
    var onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var element: SlideElement
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotos = false
    @State private var showIcons = false

    init(element: SlideElement, style: SlideStyle, theme: AppTheme, onSave: @escaping (SlideElement) -> Void, onDelete: @escaping () -> Void) {
        self.style = style
        self.theme = theme
        self.onSave = onSave
        self.onDelete = onDelete
        _element = State(initialValue: element)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    let scale = min(280 / max(element.w, 1), 130 / max(element.h, 1), 1)
                    SlideElementView(element: element, style: style)
                        .rotationEffect(.degrees(element.rotation))
                        .opacity(element.opacity)
                        .scaleEffect(scale)
                        .frame(width: element.w * scale, height: element.h * scale)
                        .frame(maxWidth: .infinity)
                        .frame(height: 160)
                        .background(style.background.first)
                        .clipped()
                        .listRowInsets(EdgeInsets())
                        .accessibilityHidden(true)
                }
                content
                Section("Look") {
                    slider(L("Opacity"), value: $element.opacity, range: 0.1...1)
                    slider(L("Turn"), value: $element.rotation, range: 0...359, step: 1, unit: "°")
                    // Effects other than Fade are part of Minor Plus (as in the toolbar's menu).
                    Picker("Comes In", selection: $element.build) {
                        ForEach(BuildEffect.allCases.filter { AccountStore.shared.isPaid || $0 == .none || $0 == .fade || $0 == element.build }) {
                            Label($0.name, systemImage: $0.icon).tag($0)
                        }
                    }
                }
                Section {
                    Button(role: .destructive) {
                        onDelete()
                        dismiss()
                    } label: { Label("Delete Element", systemImage: "trash") }
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.background.ignoresSafeArea())
            .navigationTitle(SlideElementEditor.describe(element).components(separatedBy: ":").first ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(element)
                        dismiss()
                    }
                    .foregroundColor(MinorColor.accent)
                }
            }
            .photosPicker(isPresented: $showPhotos, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let picture = MapStore.shared.storeImage(data, isAI: false) {
                        element.image = picture.id
                    }
                    photoItem = nil
                }
            }
            .sheet(isPresented: $showIcons) {
                IconPicker(selected: element.symbol, theme: theme) { element.symbol = $0 }
                    .presentationDetents([.medium, .large])
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        switch element.kind {
        case .text:
            Section("Text") {
                TextField("Text", text: $element.text, axis: .vertical).lineLimit(1...6)
                textControls
            }
            colorSection(L("Color"), selection: $element.color, automatic: L("Like the theme"))
        case .shape:
            Section("Shape") {
                Picker("Shape", selection: $element.shape) {
                    ForEach(SlideElement.Shape.allCases, id: \.self) { shape in
                        Text(Self.shapeName(shape)).tag(shape)
                    }
                }
                slider(L("Fill"), value: $element.fillOpacity, range: 0...1)
                slider(L("Outline"), value: $element.strokeWidth, range: 0...16, step: 1, unit: " pt")
                TextField("Text inside", text: $element.text, axis: .vertical).lineLimit(1...4)
                if !element.text.isEmpty { textControls }
            }
            colorSection(L("Fill Color"), selection: $element.fill, automatic: L("Accent"))
            if element.strokeWidth > 0 { colorSection(L("Outline Color"), selection: $element.stroke, automatic: L("Like the text")) }
        case .icon:
            Section("Icon") {
                Button { showIcons = true } label: {
                    HStack {
                        Image(systemName: element.symbol).font(.system(size: 22))
                        Text("Choose Icon")
                        Spacer()
                        Image(systemName: "chevron.right").foregroundColor(MinorColor.textTertiary)
                    }
                }
            }
            colorSection(L("Color"), selection: $element.fill, automatic: L("Accent"))
        case .image:
            Section("Picture") {
                Button { showPhotos = true } label: { Label(element.image == nil ? "Choose Photo" : "Replace Photo", systemImage: "photo") }
            }
        case .table:
            TableEditor(rows: $element.rows)
            Section { slider(L("Text Size"), value: $element.fontSize, range: 16...30, step: 1, unit: " pt") }
        case .chart:
            ChartEditor(chart: Binding(get: { element.chart ?? ChartSpec() }, set: { element.chart = $0 }))
        case .qr:
            Section {
                TextField("https://", text: $element.link)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    // A QR code holds about 2 KB; longer text can't be drawn as one.
                    .onChange(of: element.link) { value in
                        if value.count > 1_000 { element.link = String(value.prefix(1_000)) }
                    }
            } header: {
                Text("Link")
            } footer: {
                Text("Up to 1,000 characters.")
            }
        }
    }

    private var textControls: some View {
        Group {
            slider(L("Size"), value: $element.fontSize, range: 14...160, step: 1, unit: " pt")
            Toggle("Bold", isOn: $element.bold)
            Toggle("Italic", isOn: $element.italic)
            Toggle("Title Font", isOn: $element.titleFont)
            Picker("Align", selection: $element.align) {
                Image(systemName: "text.alignleft").tag(SlideElement.Align.leading)
                Image(systemName: "text.aligncenter").tag(SlideElement.Align.center)
                Image(systemName: "text.alignright").tag(SlideElement.Align.trailing)
            }
            .pickerStyle(.segmented)
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double = 0.05, unit: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(verbatim: unit == nil ? "\(Int(value.wrappedValue * 100))%" : "\(Int(value.wrappedValue))\(unit!)")
                    .foregroundColor(MinorColor.textTertiary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range, step: step)
        }
    }

    private func colorSection(_ title: String, selection: Binding<String?>, automatic: String) -> some View {
        Section(title) {
            ColorChoices(selection: selection, style: style, automatic: automatic)
        }
    }

    static func shapeName(_ shape: SlideElement.Shape) -> String {
        switch shape {
        case .rect: return L("Rectangle")
        case .roundRect: return L("Rounded Rectangle")
        case .ellipse: return L("Circle")
        case .triangle: return L("Triangle")
        case .diamond: return L("Diamond")
        case .arrow: return L("Arrow")
        case .star: return L("Star")
        case .line: return L("Line")
        case .hexagon: return L("Hexagon")
        }
    }
}

// The theme's colors first, then any color.
struct ColorChoices: View {
    @Binding var selection: String?
    let style: SlideStyle
    let automatic: String

    private var swatches: [String] {
        var list = style.palette.map { UIColor($0).hexString }
        list += ["#FFFFFF", "#18171B", "#8A8790"]
        var seen = Set<String>()
        return list.filter { seen.insert($0).inserted }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Button { selection = nil } label: {
                    Text(automatic)
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .overlay(Capsule().stroke(selection == nil ? MinorColor.accent : Color.white.opacity(0.2), lineWidth: selection == nil ? 2 : 1))
                }
                .buttonStyle(.plain)
                ForEach(swatches, id: \.self) { hex in
                    Button { selection = hex } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 30, height: 30)
                            .overlay(Circle().stroke(selection == hex ? MinorColor.accent : Color.white.opacity(0.25), lineWidth: selection == hex ? 3 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(hex)
                }
                ColorPicker("", selection: Binding(get: { Color(hex: selection ?? "#FFFFFF") }, set: { selection = UIColor($0).hexString }), supportsOpacity: false)
                    .labelsHidden()
                    .accessibilityLabel("Any color")
            }
            .padding(.vertical, 4)
        }
    }
}

struct IconPicker: View {
    let selected: String
    let theme: AppTheme
    var onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                    ForEach(IconCatalog.symbols, id: \.self) { symbol in
                        Button {
                            onPick(symbol)
                            dismiss()
                        } label: {
                            Image(systemName: symbol)
                                .font(.system(size: 22))
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(RoundedRectangle(cornerRadius: 12).fill(symbol == selected ? MinorColor.accent.opacity(0.25) : theme.chatRectangle))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(symbol == selected ? MinorColor.accent : theme.chatStroke, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(symbol.replacingOccurrences(of: ".", with: " "))
                    }
                }
                .padding(16)
            }
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("Icons")
            .navigationBarTitleDisplayMode(.inline)
        }
        .foregroundColor(MinorColor.textPrimary)
        .preferredColorScheme(.dark)
    }
}

private struct TableEditor: View {
    @Binding var rows: [[String]]

    private var columns: Int { max(rows.map(\.count).max() ?? 1, 1) }

    var body: some View {
        Section {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 6) {
                    ForEach(0..<columns, id: \.self) { c in
                        // Bounds-checked: a field can still be updated while its row is removed.
                        TextField("", text: Binding(
                            get: { rows.indices.contains(r) && c < rows[r].count ? rows[r][c] : "" },
                            set: { value in
                                guard rows.indices.contains(r) else { return }
                                while rows[r].count <= c { rows[r].append("") }
                                rows[r][c] = value
                            }
                        ))
                        .font(.system(size: 14, weight: r == 0 ? .semibold : .regular))
                        .textFieldStyle(.roundedBorder)
                    }
                }
            }
            HStack {
                Button("+ Row") { rows.append(Array(repeating: "", count: columns)) }.disabled(rows.count >= 8)
                Spacer()
                Button("− Row") { _ = rows.popLast() }.disabled(rows.count <= 2)
            }
            .buttonStyle(.borderless)
            HStack {
                Button("+ Column") { rows = rows.map { $0 + [""] } }.disabled(columns >= 5)
                Spacer()
                Button("− Column") { rows = rows.map { Array($0.prefix(columns - 1)) } }.disabled(columns <= 1)
            }
            .buttonStyle(.borderless)
        } header: { Text("Table") }
    }
}

private struct ChartEditor: View {
    @Binding var chart: ChartSpec

    var body: some View {
        Section {
            Picker("Type", selection: $chart.kind) {
                Image(systemName: "chart.bar.fill").tag(ChartSpec.Kind.bar)
                Image(systemName: "chart.xyaxis.line").tag(ChartSpec.Kind.line)
                Image(systemName: "chart.pie.fill").tag(ChartSpec.Kind.pie)
                Image(systemName: "circle.circle").tag(ChartSpec.Kind.donut)
            }
            .pickerStyle(.segmented)
            TextField("Title", text: $chart.title)
            Toggle("Show Values", isOn: $chart.showValues)
        } header: { Text("Chart") }
        Section {
            ForEach(chart.labels.indices, id: \.self) { i in
                HStack {
                    // Bounds-checked: a field can still be updated while its row is swiped away.
                    TextField("Label", text: Binding(
                        get: { chart.labels.indices.contains(i) ? chart.labels[i] : "" },
                        set: { if chart.labels.indices.contains(i) { chart.labels[i] = $0 } }
                    ))
                    TextField("0", value: Binding(get: { i < chart.values.count ? chart.values[i] : 0 }, set: { value in
                        guard chart.labels.indices.contains(i) else { return }
                        while chart.values.count <= i { chart.values.append(0) }
                        // Same range the server accepts; also keeps the chart drawable.
                        chart.values[i] = value.isFinite ? min(max(value, -1e12), 1e12) : 0
                    }), format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
                }
            }
            .onDelete { offsets in
                chart.labels.remove(atOffsets: offsets)
                chart.values.remove(atOffsets: offsets.filter { $0 < chart.values.count }.reduce(into: IndexSet()) { $0.insert($1) })
            }
            Button("+ Add Value") {
                chart.labels.append(L("New"))
                chart.values.append(10)
            }
            .disabled(chart.labels.count >= 12)
        } header: { Text("Data") }
    }
}
