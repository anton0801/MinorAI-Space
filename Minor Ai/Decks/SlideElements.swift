//
//  SlideElements.swift
//  Minor Ai
//
//  Free elements on a slide: text, shapes, icons, pictures, tables, charts and QR codes. Drawn
//  at their size on the 1280×720 slide; the slide places, turns and fades them.
//

import CoreImage.CIFilterBuiltins
import SwiftUI

struct SlideElementView: View {
    let element: SlideElement
    let style: SlideStyle

    private var textColor: Color { element.color.map { Color(hex: $0) } ?? style.text }
    private var fill: Color { (element.fill.map { Color(hex: $0) } ?? style.accent).opacity(element.fillOpacity) }

    var body: some View {
        content
            .frame(width: element.w, height: element.h)
    }

    @ViewBuilder
    private var content: some View {
        switch element.kind {
        case .text:
            label(element.text, color: textColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: frameAlignment)
        case .shape:
            ZStack {
                if element.shape == .line {
                    ElementShape(kind: .line)
                        .stroke(element.stroke.map { Color(hex: $0) } ?? fill, style: StrokeStyle(lineWidth: max(element.strokeWidth, 6), lineCap: .round))
                } else {
                    ElementShape(kind: element.shape).fill(fill)
                    if element.strokeWidth > 0 {
                        ElementShape(kind: element.shape)
                            .stroke(element.stroke.map { Color(hex: $0) } ?? style.text, lineWidth: element.strokeWidth)
                    }
                }
                if !element.text.isEmpty {
                    label(element.text, color: element.color.map { Color(hex: $0) } ?? (element.fill == nil ? style.onAccent : textColor))
                        .padding(.horizontal, 24)
                }
            }
        case .icon:
            Image(systemName: element.symbol)
                .resizable()
                .scaledToFit()
                .foregroundColor(element.fill.map { Color(hex: $0) } ?? style.accent)
                .opacity(element.fillOpacity)
        case .image:
            if let id = element.image {
                NodePicture(id: id)
                    .frame(width: element.w, height: element.h)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 24).fill(style.card)
                    Image(systemName: "photo").font(.system(size: 64)).foregroundColor(style.secondary)
                }
            }
        case .table:
            ElementTable(rows: element.rows, style: style, fontSize: element.fontSize)
        case .chart:
            ChartView(spec: element.chart ?? ChartSpec(), style: style)
        case .qr:
            QRImage(text: element.link)
                .padding(element.w * 0.06)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
        }
    }

    private var frameAlignment: Alignment {
        switch element.align {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    private func label(_ text: String, color: Color) -> some View {
        Text(text)
            .font((element.titleFont ? style.titleFont : style.bodyFont).font(element.fontSize, element.bold ? .bold : .regular))
            .italic(element.italic)
            .foregroundColor(color)
            .multilineTextAlignment(element.align == .center ? .center : element.align == .trailing ? .trailing : .leading)
            .minimumScaleFactor(0.4)
    }
}

struct ElementShape: Shape {
    let kind: SlideElement.Shape

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        switch kind {
        case .rect: p.addRect(rect)
        case .roundRect: p.addRoundedRect(in: rect, cornerSize: CGSize(width: min(w, h) * 0.18, height: min(w, h) * 0.18))
        case .ellipse: p.addEllipse(in: rect)
        case .triangle:
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
        case .diamond:
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            p.closeSubpath()
        case .arrow:
            let head = min(w * 0.4, h)
            p.move(to: CGPoint(x: rect.minX, y: rect.minY + h * 0.3))
            p.addLine(to: CGPoint(x: rect.maxX - head, y: rect.minY + h * 0.3))
            p.addLine(to: CGPoint(x: rect.maxX - head, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX - head, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX - head, y: rect.minY + h * 0.7))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + h * 0.7))
            p.closeSubpath()
        case .star:
            let center = CGPoint(x: rect.midX, y: rect.midY)
            for i in 0..<10 {
                let angle = -Double.pi / 2 + Double(i) * Double.pi / 5
                let r = i % 2 == 0 ? 1.0 : 0.42
                let point = CGPoint(x: center.x + CGFloat(cos(angle) * r) * w / 2, y: center.y + CGFloat(sin(angle) * r) * h / 2)
                if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
            }
            p.closeSubpath()
        case .hexagon:
            let inset = w * 0.25
            p.move(to: CGPoint(x: rect.minX + inset, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            p.closeSubpath()
        case .line:
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
        return p
    }
}

private struct ElementTable: View {
    let rows: [[String]]
    let style: SlideStyle
    let fontSize: Double

    var body: some View {
        let columns = rows.map(\.count).max() ?? 0
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { r, row in
                HStack(spacing: 0) {
                    ForEach(0..<columns, id: \.self) { c in
                        Text(c < row.count ? row[c] : "")
                            .font(style.body(min(fontSize, 30), r == 0 ? .bold : .regular))
                            .foregroundColor(style.text)
                            .lineLimit(2)
                            .minimumScaleFactor(0.5)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                            .padding(.horizontal, 18)
                    }
                }
                .background(r == 0 ? style.accent.opacity(style.isLight ? 0.14 : 0.2) : (r % 2 == 0 ? style.card : Color.clear))
                .overlay(alignment: .bottom) {
                    if r < rows.count - 1 { Rectangle().fill(style.line).frame(height: 1) }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(style.line, lineWidth: 1.5))
    }
}

// Bar, line, pie and donut charts drawn from the numbers.
struct ChartView: View {
    let spec: ChartSpec
    let style: SlideStyle

    // Whole numbers without ".0". Int(value) traps past ±9.2e18, so huge or odd values
    // (typed by hand or synced from elsewhere) are formatted as decimals instead.
    static func format(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        if value.rounded() == value, let whole = Int(exactly: value) { return String(whole) }
        return abs(value) >= 1e15 ? String(format: "%.3g", value) : String(format: "%.1f", value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !spec.title.isEmpty {
                Text(spec.title)
                    .font(style.title(30, .bold))
                    .foregroundColor(style.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            GeometryReader { geo in
                switch spec.kind {
                case .bar: bars(geo.size)
                case .line: line(geo.size)
                case .pie, .donut: pie(geo.size)
                }
            }
        }
    }

    private var values: [Double] { spec.values.map { max($0, 0) } }
    private var top: Double { max(values.max() ?? 1, 0.0001) }
    private func color(_ i: Int) -> Color { style.palette[i % max(style.palette.count, 1)] }

    private func bars(_ size: CGSize) -> some View {
        let count = max(values.count, 1)
        let gap = size.width * 0.04
        let barWidth = (size.width - gap * CGFloat(count - 1)) / CGFloat(count)
        let labelHeight: CGFloat = 34
        return HStack(alignment: .bottom, spacing: gap) {
            ForEach(values.indices, id: \.self) { i in
                VStack(spacing: 6) {
                    if spec.showValues {
                        Text(Self.format(spec.values[i]))
                            .font(style.body(22, .semibold))
                            .foregroundColor(style.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                    RoundedRectangle(cornerRadius: min(barWidth * 0.18, 14))
                        .fill(LinearGradient(colors: [color(i), color(i).opacity(0.7)], startPoint: .top, endPoint: .bottom))
                        .frame(height: max((size.height - labelHeight - 40) * CGFloat(values[i] / top), 4))
                    Text(i < spec.labels.count ? spec.labels[i] : "")
                        .font(style.body(20))
                        .foregroundColor(style.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(height: labelHeight)
                }
                .frame(width: barWidth)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .bottom)
    }

    private func line(_ size: CGSize) -> some View {
        let labelHeight: CGFloat = 34
        let plot = CGSize(width: size.width, height: size.height - labelHeight - 10)
        let step = values.count > 1 ? plot.width / CGFloat(values.count - 1) : 0
        let points = values.indices.map { i in
            CGPoint(x: CGFloat(i) * step, y: plot.height - plot.height * 0.85 * CGFloat(values[i] / top) - 10)
        }
        return ZStack(alignment: .topLeading) {
            ForEach(0..<4, id: \.self) { i in
                Rectangle().fill(style.line).frame(height: 1).offset(y: plot.height * CGFloat(i) / 3)
            }
            Path { p in
                guard let first = points.first else { return }
                p.move(to: CGPoint(x: first.x, y: plot.height))
                points.forEach { p.addLine(to: $0) }
                p.addLine(to: CGPoint(x: points.last?.x ?? 0, y: plot.height))
                p.closeSubpath()
            }
            .fill(LinearGradient(colors: [style.accent.opacity(0.35), style.accent.opacity(0)], startPoint: .top, endPoint: .bottom))
            Path { p in
                guard let first = points.first else { return }
                p.move(to: first)
                points.dropFirst().forEach { p.addLine(to: $0) }
            }
            .stroke(style.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            ForEach(points.indices, id: \.self) { i in
                Circle().fill(style.accent).frame(width: 18, height: 18).position(points[i])
                if spec.showValues {
                    Text(Self.format(spec.values[i]))
                        .font(style.body(20, .semibold))
                        .foregroundColor(style.text)
                        .position(x: points[i].x, y: points[i].y - 26)
                }
                Text(i < spec.labels.count ? spec.labels[i] : "")
                    .font(style.body(20))
                    .foregroundColor(style.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .position(x: points[i].x, y: plot.height + labelHeight / 2 + 6)
            }
        }
        .padding(.horizontal, 20)
    }

    private func pie(_ size: CGSize) -> some View {
        let total = max(values.reduce(0, +), 0.0001)
        let diameter = min(size.height, size.width * 0.5)
        var start = -90.0
        let slices: [(Double, Double)] = values.map { value in
            defer { start += value / total * 360 }
            return (start, start + value / total * 360)
        }
        return HStack(spacing: 36) {
            ZStack {
                ForEach(slices.indices, id: \.self) { i in
                    PieSlice(start: .degrees(slices[i].0), end: .degrees(slices[i].1))
                        .fill(color(i))
                }
                if spec.kind == .donut {
                    Circle().fill(style.background.first).frame(width: diameter * 0.55, height: diameter * 0.55)
                }
            }
            .frame(width: diameter, height: diameter)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(values.indices, id: \.self) { i in
                    HStack(spacing: 12) {
                        Circle().fill(color(i)).frame(width: 18, height: 18)
                        Text(i < spec.labels.count ? spec.labels[i] : "")
                            .font(style.body(24))
                            .foregroundColor(style.text)
                            .lineLimit(1)
                        if spec.showValues {
                            Text(verbatim: "\(Int((values[i] / total * 100).rounded()))%")
                                .font(style.body(24, .semibold))
                                .foregroundColor(style.secondary)
                        }
                    }
                }
            }
            .minimumScaleFactor(0.5)
        }
        .frame(width: size.width, height: size.height, alignment: .leading)
    }
}

private struct PieSlice: Shape {
    let start: Angle
    let end: Angle
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        p.move(to: center)
        p.addArc(center: center, radius: min(rect.width, rect.height) / 2, startAngle: start, endAngle: end, clockwise: false)
        p.closeSubpath()
        return p
    }
}

// A QR code for a link, sharp at any size.
struct QRImage: View {
    let text: String

    var body: some View {
        if let image = Self.image(text) {
            Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
        } else {
            Image(systemName: "qrcode").resizable().scaledToFit().foregroundColor(.black)
        }
    }

    static func image(_ text: String, scale: CGFloat = 12) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// Icons to choose from: SF Symbols that read well on slides.
enum IconCatalog {
    static let symbols: [String] = [
        "star.fill", "sparkles", "bolt.fill", "flame.fill", "heart.fill", "checkmark.seal.fill", "checkmark.circle.fill", "xmark.circle.fill",
        "lightbulb.fill", "target", "flag.fill", "trophy.fill", "crown.fill", "rosette", "medal.fill", "gift.fill",
        "chart.bar.fill", "chart.line.uptrend.xyaxis", "chart.pie.fill", "dollarsign.circle.fill", "creditcard.fill", "cart.fill", "bag.fill", "banknote.fill",
        "person.fill", "person.2.fill", "person.3.fill", "bubble.left.and.bubble.right.fill", "hand.thumbsup.fill", "megaphone.fill", "envelope.fill", "phone.fill",
        "clock.fill", "calendar", "hourglass", "timer", "rocket.fill", "airplane", "car.fill", "map.fill",
        "globe.europe.africa.fill", "building.2.fill", "house.fill", "graduationcap.fill", "book.fill", "pencil", "paintbrush.fill", "camera.fill",
        "gearshape.fill", "wrench.and.screwdriver.fill", "hammer.fill", "cpu.fill", "desktopcomputer", "iphone", "wifi", "lock.fill",
        "shield.fill", "leaf.fill", "drop.fill", "sun.max.fill", "moon.fill", "cloud.fill", "snowflake", "atom",
        "brain.head.profile", "puzzlepiece.fill", "link", "arrow.right.circle.fill", "arrow.up.right", "arrow.triangle.2.circlepath", "plus.circle.fill", "exclamationmark.triangle.fill",
    ]
}
