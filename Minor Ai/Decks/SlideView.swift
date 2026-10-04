//
//  SlideView.swift
//  Minor Ai
//
//  Draws one slide on a 1280×720 canvas in its layout and style. The same view is used for
//  the editor, thumbnails, the presenter, external displays and PDF export.
//

import SwiftUI

struct SlideView: View {
    let slide: Slide
    let style: SlideStyle
    var index = 0
    var total = 1
    var deckTitle = ""
    var sectionNumber = 1
    var brand: DeckBrand? = nil
    var reveal: Int? = nil          // presenting: how many build steps are shown (nil: all)
    var showElements = true         // the element editor draws them itself
    var probe: SlideLayoutProbe? = nil  // PowerPoint export: where each part lands

    static let size = CGSize(width: 1280, height: 720)
    private let pad: CGFloat = 80

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            content
                .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
            if slide.layout != .cover && slide.layout != .closing && total > 1 {
                footer
            }
            if let logo = brand?.logo, slide.layout != .cover || brand?.onCover != false {
                logoView(logo)
            }
            if showElements {
                ForEach(slide.elements) { element in
                    SlideElementView(element: element, style: style)
                        .rotationEffect(.degrees(element.rotation))
                        .opacity(element.opacity)
                        .modifier(Reveal(effect: element.build, shown: shown(element)))
                        .position(x: element.x + element.w / 2, y: element.y + element.h / 2)
                }
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipped()
        .coordinateSpace(name: SlideLayoutProbe.space)
        .foregroundColor(style.text)
        .environment(\.colorScheme, style.isLight ? .light : .dark)
        // A slide is a fixed 1280×720 picture: its text mustn't grow with the phone's text size
        // (that would break the layout and change exported PDFs and PowerPoint files).
        .environment(\.dynamicTypeSize, .large)
    }

    // MARK: - Pieces

    // MARK: Building up while presenting

    // The layout's i-th point (bullet, column, step…) is on screen.
    private func shown(_ i: Int) -> Bool {
        guard let reveal, slide.buildBullets != .none else { return true }
        return i < reveal
    }

    private func shown(_ element: SlideElement) -> Bool {
        guard let reveal, element.build != .none else { return true }
        let order = slide.elements.filter { $0.build != .none }.firstIndex { $0.id == element.id } ?? 0
        return reveal >= slide.buildUnits + order + 1
    }

    private func unit(_ i: Int) -> Reveal { Reveal(effect: slide.buildBullets, shown: shown(i)) }

    private var background: some View { SlideBackdrop(slide: slide, style: style) }

    private func logoView(_ id: UUID) -> some View {
        let size = CGFloat(brand?.size ?? 64)
        let corner = brand?.corner ?? .topRight
        let alignment: Alignment = corner == .topLeft ? .topLeading : corner == .topRight ? .topTrailing : corner == .bottomLeft ? .bottomLeading : .bottomTrailing
        return Group {
            if let image = MapStore.shared.image(id) {
                Image(uiImage: image).resizable().scaledToFit()
            }
        }
        .frame(maxWidth: 360, maxHeight: size, alignment: alignment)
        .padding(.horizontal, 48)
        .padding(.vertical, corner == .bottomLeft || corner == .bottomRight ? 70 : 40)
        .frame(width: Self.size.width, height: Self.size.height, alignment: alignment)
    }

    private var footer: some View {
        HStack {
            Text(brand.map { $0.footer.isEmpty ? deckTitle : $0.footer } ?? deckTitle)
                .lineLimit(1)
                .probed("footer", probe)
            Spacer()
            if brand?.showNumbers != false {
                Text("\(index + 1) / \(total)")
                    .monospacedDigit()
                    .probed("page", probe)
            }
        }
        .font(style.body(18, .medium))
        .foregroundColor(style.secondary.opacity(0.8))
        .padding(.horizontal, pad)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .bottom)
        .padding(.bottom, 36)
    }

    private func titleText(_ text: String, size: CGFloat = 56) -> some View {
        Text(text)
            .font(style.title(size, .bold))
            .tracking(-1)
            .lineLimit(2)
            .minimumScaleFactor(0.6)
            .fixedSize(horizontal: false, vertical: true)
            .probed("title", probe)
    }

    // `key` names the list for the PowerPoint export ("b.text.0", "col.1.text.2"…).
    private func bulletList(_ items: [String], size: CGFloat = 32, spacing: CGFloat = 22, dot: Color? = nil, builds: Bool = true, key: String = "b") -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                HStack(alignment: .firstTextBaseline, spacing: 22) {
                    Circle()
                        .fill(dot ?? style.palette[i % style.palette.count])
                        .frame(width: size * 0.42, height: size * 0.42)
                        .offset(y: -size * 0.12)
                    Text(item)
                        .font(style.body(size, .regular))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .fixedSize(horizontal: false, vertical: true)
                        .probed("\(key).text.\(i)", probe)
                }
                .modifier(builds ? unit(i) : Reveal(effect: .none, shown: true))
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch slide.layout {
        case .cover: cover
        case .section: section
        case .bullets: bullets
        case .twoColumns: twoColumns
        case .imageText: imageText
        case .bigNumber: bigNumber
        case .quote: quote
        case .timeline: timeline
        case .table: table
        case .diagram: diagram
        case .closing: closing
        }
    }

    // MARK: - Layouts

    private var cover: some View {
        VStack(alignment: .leading, spacing: 28) {
            Capsule().fill(style.accent).frame(width: 96, height: 10)
                .probed("bar", probe)
            Text(slide.title)
                .font(style.title(92, .heavy))
                .tracking(-2.5)
                .lineLimit(3)
                .minimumScaleFactor(0.5)
                .probed("title", probe)
            if !slide.subtitle.isEmpty {
                Text(slide.subtitle)
                    .font(style.body(34, .medium))
                    .foregroundColor(style.secondary)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                    .probed("subtitle", probe)
            }
        }
        .frame(maxWidth: 1000, alignment: .leading)
        .padding(.horizontal, pad + 10)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .leading)
    }

    private var section: some View {
        HStack(alignment: .center, spacing: 56) {
            Text(String(format: "%02d", sectionNumber))
                .font(style.title(200, .heavy).monospacedDigit())
                .foregroundStyle(LinearGradient(colors: [style.accent, style.palette.dropFirst().first ?? style.accent], startPoint: .top, endPoint: .bottom))
                .probed("number", probe)
            VStack(alignment: .leading, spacing: 18) {
                Text(slide.title)
                    .font(style.title(72, .bold))
                    .tracking(-1.5)
                    .lineLimit(3)
                    .minimumScaleFactor(0.55)
                    .probed("title", probe)
                if !slide.subtitle.isEmpty {
                    Text(slide.subtitle)
                        .font(style.body(30))
                        .foregroundColor(style.secondary)
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                        .probed("subtitle", probe)
                }
            }
        }
        .padding(.horizontal, pad + 10)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .leading)
    }

    private var bullets: some View {
        VStack(alignment: .leading, spacing: 44) {
            titleText(slide.title)
            if !slide.subtitle.isEmpty {
                Text(slide.subtitle).font(style.body(26)).foregroundColor(style.secondary).lineLimit(2).probed("subtitle", probe).padding(.top, -26)
            }
            bulletList(slide.bullets, size: slide.bullets.count > 4 ? 32 : 40, spacing: slide.bullets.count > 4 ? 22 : 34)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, pad)
        .padding(.top, 76)
        .padding(.bottom, 90)
    }

    private var twoColumns: some View {
        VStack(alignment: .leading, spacing: 40) {
            titleText(slide.title, size: 52)
            HStack(alignment: .top, spacing: 28) {
                ForEach(Array(slide.columns.prefix(3).enumerated()), id: \.offset) { i, column in
                    let color = style.palette[i % style.palette.count]
                    VStack(alignment: .leading, spacing: 20) {
                        Capsule().fill(color).frame(width: 56, height: 8)
                            .probed("col.\(i).bar", probe)
                        Text(column.title)
                            .font(style.title(38, .bold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                            .probed("col.\(i).title", probe)
                        bulletList(column.bullets, size: column.bullets.count > 4 ? 26 : 30, spacing: 18, dot: color, builds: false, key: "col.\(i)")
                        Spacer(minLength: 0)
                    }
                    .padding(32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .probed("col.\(i)", probe)
                    .background(RoundedRectangle(cornerRadius: 30).fill(style.card))
                    .overlay(RoundedRectangle(cornerRadius: 30).stroke(style.line, lineWidth: 1.5))
                    .modifier(unit(i))
                }
            }
        }
        .padding(.horizontal, pad)
        .padding(.top, 70)
        .padding(.bottom, 96)
    }

    private var imageText: some View {
        HStack(alignment: .center, spacing: 60) {
            Group {
                if let image = slide.image {
                    NodePicture(id: image.id)
                } else {
                    // Room for a picture: the AI can draw one from the slide's description.
                    ZStack {
                        // Transparent as a whole, not in the colors: PDF drops a gradient's own transparency.
                        LinearGradient(colors: [style.accent, style.palette.dropFirst().first ?? style.accent], startPoint: .topLeading, endPoint: .bottomTrailing)
                            .opacity(0.3)
                        Image(systemName: "sparkles")
                            .font(style.body(80, .light))
                            .foregroundColor(style.text.opacity(0.6))
                    }
                }
            }
            .frame(width: 520, height: 560)
            .clipShape(RoundedRectangle(cornerRadius: 36))
            .probed("image", probe)
            VStack(alignment: .leading, spacing: 36) {
                titleText(slide.title, size: 52)
                bulletList(slide.bullets, size: 28, spacing: 18)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, pad)
        .frame(width: Self.size.width, height: Self.size.height)
    }

    private var bigNumber: some View {
        VStack(spacing: 18) {
            if !slide.title.isEmpty {
                Text(slide.title)
                    .font(style.body(34, .semibold))
                    .foregroundColor(style.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .probed("title", probe)
            }
            Text(slide.stat?.value ?? "")
                .font(style.title(230, .heavy))
                .tracking(-6)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .foregroundStyle(LinearGradient(colors: [style.accent, style.palette.dropFirst().first ?? style.accent], startPoint: .leading, endPoint: .trailing))
                .probed("stat", probe)
            Text(slide.stat?.label ?? "")
                .font(style.body(36, .medium))
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
                .probed("label", probe)
                .frame(maxWidth: 900)
        }
        .padding(.horizontal, pad)
        .frame(width: Self.size.width, height: Self.size.height)
    }

    private var quote: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("“")
                .font(style.title(260, .heavy))
                .foregroundColor(style.accent)
                .frame(height: 170, alignment: .top)
                .probed("mark", probe)
            Text(slide.quote?.text ?? slide.title)
                .font(style.body(54, .semibold).italic())
                .tracking(-0.8)
                .lineLimit(5)
                .minimumScaleFactor(0.55)
                .probed("quote", probe)
            if let author = slide.quote?.author, !author.isEmpty {
                Text("— \(author)")
                    .font(style.body(30, .medium))
                    .foregroundColor(style.secondary)
                    .probed("author", probe)
                    .padding(.top, 18)
            }
        }
        .frame(maxWidth: 1060, alignment: .leading)
        .padding(.horizontal, pad + 20)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .leading)
    }

    private var timeline: some View {
        let items = Array(slide.items.prefix(6))
        return VStack(alignment: .leading, spacing: 0) {
            titleText(slide.title, size: 52)
            Spacer(minLength: 40)
            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(LinearGradient(colors: style.palette.prefix(max(items.count, 2)).map { $0 }, startPoint: .leading, endPoint: .trailing))
                    .frame(height: 6)
                    .probed("line", probe)
                    .padding(.top, 15)
                HStack(alignment: .top, spacing: 24) {
                    ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                        VStack(alignment: .leading, spacing: 16) {
                            Circle()
                                .fill(style.palette[i % style.palette.count])
                                .frame(width: 36, height: 36)
                                .overlay(Circle().stroke(style.background.first, lineWidth: 6))
                                .probed("t.\(i).dot", probe)
                            Text(item.title)
                                .font(style.title(items.count > 4 ? 28 : 34, .bold))
                                .lineLimit(2)
                                .minimumScaleFactor(0.7)
                                .probed("t.\(i).title", probe)
                            if !item.detail.isEmpty {
                                Text(item.detail)
                                    .font(style.body(items.count > 4 ? 22 : 26))
                                    .foregroundColor(style.secondary)
                                    .lineLimit(5)
                                    .minimumScaleFactor(0.75)
                                    .probed("t.\(i).detail", probe)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .modifier(unit(i))
                    }
                }
            }
            Spacer(minLength: 40)
        }
        .padding(.horizontal, pad)
        .padding(.top, 76)
        .padding(.bottom, 110)
    }

    private var table: some View {
        let rows = Array(slide.table.prefix(6))
        let columns = rows.map(\.count).max() ?? 0
        return VStack(alignment: .leading, spacing: 40) {
            titleText(slide.title, size: 52)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { r, row in
                    HStack(spacing: 0) {
                        ForEach(0..<columns, id: \.self) { c in
                            Text(c < row.count ? row[c] : "")
                                .font(style.body(rows.count > 5 ? 24 : 28, r == 0 ? .bold : (c == 0 ? .semibold : .regular)))
                                .lineLimit(2)
                                .minimumScaleFactor(0.7)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 26)
                                .padding(.vertical, rows.count > 5 ? 16 : 22)
                        }
                    }
                    .background(r == 0 ? style.accent.opacity(style.isLight ? 0.14 : 0.18) : (r % 2 == 0 ? style.card : Color.clear))
                    .overlay(alignment: .bottom) {
                        if r < rows.count - 1 { Rectangle().fill(style.line).frame(height: 1) }
                    }
                    .probed("row.\(r)", probe)
                    .modifier(r == 0 ? Reveal(effect: .none, shown: true) : unit(r - 1))
                }
            }
            .probed("table", probe)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(style.line, lineWidth: 1.5))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, pad)
        .padding(.top, 70)
        .padding(.bottom, 90)
    }

    private var diagram: some View {
        let nodes = Array((slide.diagram?.nodes ?? []).prefix(6))
        let center = CGPoint(x: Self.size.width / 2, y: 420)
        let positions: [CGPoint] = nodes.indices.map { i in
            let angle = -Double.pi / 2 + Double(i) * 2 * Double.pi / Double(max(nodes.count, 1))
            return CGPoint(x: center.x + CGFloat(cos(angle)) * 420, y: center.y + CGFloat(sin(angle)) * 210)
        }
        return ZStack(alignment: .topLeading) {
            titleText(slide.title, size: 48)
                .padding(.horizontal, pad)
                .padding(.top, 60)
            Path { path in
                for point in positions {
                    path.move(to: center)
                    path.addLine(to: point)
                }
            }
            .stroke(style.line, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [2, 10]))
            Circle()
                .fill(LinearGradient(colors: [style.accent, style.palette.dropFirst().first ?? style.accent], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 230, height: 230)
                .overlay(
                    Text(slide.diagram?.center ?? slide.title)
                        .font(style.title(30, .bold))
                        .foregroundColor(style.onAccent)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.6)
                        .padding(26)
                )
                .probed("center", probe)
                .position(center)
            ForEach(Array(nodes.enumerated()), id: \.offset) { i, node in
                let color = style.palette[i % style.palette.count]
                Text(node)
                    .font(style.body(25, .semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .frame(maxWidth: 300)
                    .background(Capsule().fill(style.isLight ? Color.white : Color(hex: "#1D1A20")))
                    .overlay(Capsule().stroke(color, lineWidth: 3))
                    .probed("node.\(i)", probe)
                    .modifier(unit(i))
                    .position(positions[i])
            }
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
    }

    private var closing: some View {
        VStack(spacing: 26) {
            Text(slide.title)
                .font(style.title(84, .heavy))
                .tracking(-2)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.5)
                .probed("title", probe)
            Capsule()
                .fill(LinearGradient(colors: [style.accent, style.palette.dropFirst().first ?? style.accent], startPoint: .leading, endPoint: .trailing))
                .frame(width: 140, height: 10)
                .probed("bar", probe)
            if !slide.subtitle.isEmpty {
                Text(slide.subtitle)
                    .font(style.body(34, .medium))
                    .foregroundColor(style.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                    .probed("subtitle", probe)
            }
        }
        .frame(maxWidth: 1040)
        .padding(.horizontal, pad)
        .frame(width: Self.size.width, height: Self.size.height)
    }
}

// The slide's background: its fill and the soft light in the corners. Also the background
// picture of a PowerPoint slide, so it looks the same there.
struct SlideBackdrop: View {
    let slide: Slide
    let style: SlideStyle

    var body: some View {
        ZStack {
            fill
            // Soft light in the corners; stronger on title slides.
            let strong = slide.layout == .cover || slide.layout == .closing || slide.layout == .section
            if style.glow && style.background.kind != .image {
                Circle()
                    .fill(style.accent.opacity(style.isLight ? 0.10 : (strong ? 0.22 : 0.10)))
                    .frame(width: 760, height: 760)
                    .blur(radius: 140)
                    .offset(x: 520, y: -300)
                Circle()
                    .fill((style.palette.dropFirst().first ?? style.accent).opacity(style.isLight ? 0.08 : (strong ? 0.18 : 0.07)))
                    .frame(width: 640, height: 640)
                    .blur(radius: 140)
                    .offset(x: -520, y: 340)
            }
        }
        .frame(width: SlideView.size.width, height: SlideView.size.height)
    }

    @ViewBuilder
    private var fill: some View {
        let bg = style.background
        switch bg.kind {
        case .solid:
            bg.first
        case .gradient:
            LinearGradient(colors: [bg.first, bg.last], startPoint: bg.points.0, endPoint: bg.points.1)
        case .image:
            if let id = bg.image {
                NodePicture(id: id)
                    .frame(width: SlideView.size.width, height: SlideView.size.height)
                    .clipped()
                    .overlay(Color.black.opacity(bg.dim))
            } else {
                LinearGradient(colors: [bg.first, bg.last], startPoint: bg.points.0, endPoint: bg.points.1)
            }
        }
    }

}

// Where the parts of a slide land on its 1280×720 canvas, for the PowerPoint export: its
// editable boxes go exactly where the slide draws them. Filled while a slide renders off screen.
final class SlideLayoutProbe {
    static let space = "slide"
    private(set) var frames: [String: CGRect] = [:]

    subscript(key: String) -> CGRect? { frames[key] }

    func mark(_ key: String, _ frame: CGRect) -> some View {
        frames[key] = frame
        return Color.clear
    }
}

extension View {
    // Reports this view's frame to the probe (only while exporting).
    @ViewBuilder
    func probed(_ key: String, _ probe: SlideLayoutProbe?) -> some View {
        if let probe {
            background(GeometryReader { geo in probe.mark(key, geo.frame(in: .named(SlideLayoutProbe.space))) })
        } else {
            self
        }
    }
}

// A slide scaled to the space it gets (editor, thumbnails, presenter).
struct SlideCanvas: View {
    let slide: Slide
    let deck: Deck
    var index = 0
    var reveal: Int? = nil

    var body: some View {
        GeometryReader { geo in
            SlideView(slide: slide, style: deck.style(for: slide), index: index, total: deck.slides.count, deckTitle: deck.title,
                      sectionNumber: Self.sectionNumber(of: index, in: deck), brand: deck.brand, reveal: reveal)
                .scaleEffect(geo.size.width / SlideView.size.width, anchor: .topLeading)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                // The full-size slide under the scale doesn't take touches; the whole picture does.
                .allowsHitTesting(false)
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Slide \(index + 1): \(slide.plainText.prefix(4).joined(separator: ". "))"))
    }

    // "01", "02"… for section slides, in order.
    static func sectionNumber(of index: Int, in deck: Deck) -> Int {
        deck.slides.prefix(index + 1).filter { $0.layout == .section }.count
    }
}
