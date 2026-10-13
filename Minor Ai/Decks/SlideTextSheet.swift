//
//  SlideTextSheet.swift
//  Minor Ai
//
//  Selecting the text a layout drew (its title, a point, a step…) by tapping it on the slide, and
//  the Text panel: size, bold, italic, color and, for the title, alignment. The style is kept by
//  role — the title, or all other text on the slide — so the text stays the slide's title and
//  points for AI, presenting and export, which draw it the same way.
//

import SwiftUI

enum SlidePart {
    enum Role { case title, body }

    // Parts that are text (not bars, lines, cards, pictures, the footer or the quote mark).
    static func isText(_ key: String) -> Bool {
        let fixed: Set<String> = ["title", "subtitle", "stat", "label", "quote", "author", "center"]
        if fixed.contains(key) { return true }
        let pieces = key.split(separator: ".")
        switch pieces.first {
        case "b": return pieces.count == 3 && pieces[1] == "text"
        case "col": return pieces.count >= 3 && (pieces[2] == "title" || pieces[2] == "text")
        case "t": return pieces.count == 3 && (pieces[2] == "title" || pieces[2] == "detail")
        case "row", "node": return pieces.count == 2
        default: return false
        }
    }

    // The text under a point of the 1280×720 slide: the smallest part around it (a little
    // forgiving at the edges, for fingers).
    static func hit(_ point: CGPoint, in frames: [String: CGRect]) -> String? {
        frames
            .filter { isText($0.key) && $0.value.insetBy(dx: -14, dy: -10).contains(point) }
            .min { $0.value.width * $0.value.height < $1.value.width * $1.value.height }?
            .key
    }

    static func role(_ key: String) -> Role { key == "title" ? .title : .body }

    // What the part is, said in words: "Title", "Point 2", "Column 1 · Point 3", "Step 2"…
    static func name(_ key: String) -> String {
        let pieces = key.split(separator: ".").map(String.init)
        func number(_ i: Int) -> Int { pieces.indices.contains(i) ? (Int(pieces[i]) ?? 0) + 1 : 1 }
        switch pieces.first {
        case "title": return L("Title")
        case "subtitle": return L("Subtitle")
        case "stat": return L("Number")
        case "label": return L("What it means")
        case "quote": return L("Quote")
        case "author": return L("Author")
        case "center": return L("Center")
        case "b": return L("Point \(number(2))")
        case "col": return pieces.count > 2 && pieces[2] == "title" ? L("Column \(number(1))") : L("Column \(number(1)) · Point \(number(3))")
        case "t": return pieces.count > 2 && pieces[2] == "detail" ? L("Step \(number(1)) · Detail") : L("Step \(number(1))")
        case "row": return number(1) == 1 ? L("Table header") : L("Row \(number(1) - 1)")
        case "node": return L("Idea \(number(1))")
        default: return L("Text")
        }
    }
}

struct SlideTextSheet: View {
    let slide: Slide
    let key: String
    let style: SlideStyle
    let theme: AppTheme
    var onChange: (_ role: SlidePart.Role, _ change: @escaping (inout SlideTextStyle.Part) -> Void) -> Void
    var onEditText: () -> Void
    var onRewrite: () -> Void
    var onFonts: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var role: SlidePart.Role { SlidePart.role(key) }
    private var part: SlideTextStyle.Part {
        (role == .title ? slide.text?.title : slide.text?.body) ?? SlideTextStyle.Part()
    }

    // Colors that go with the slide: its text, accent and palette, white and black.
    private var colors: [String] {
        var list = [UIColor(style.text).hexString, UIColor(style.accent).hexString]
        list += style.palette.prefix(4).map { UIColor($0).hexString }
        list += ["#FFFFFF", "#18171B"]
        var seen = Set<String>()
        return list.filter { seen.insert($0.uppercased()).inserted }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                EditorSheetHeader(
                    title: L("Text"),
                    subtitle: role == .title ? L("The title of this slide") : L("\(SlidePart.name(key)) and all other text on this slide")
                ) { dismiss() }
                VStack(spacing: 0) {
                    row(L("Font")) {
                        Button(action: onFonts) {
                            HStack(spacing: 6) {
                                Text((role == .title ? style.titleFont : style.bodyFont).name)
                                    .minorFont(14, maxScale: 1.3)
                                    .foregroundColor(MinorColor.textPrimary)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(MinorColor.textSecondary)
                            }
                            .padding(.horizontal, 12)
                            .frame(width: 190, height: 32)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(Text("Fonts are set in Presentation Style"))
                    }
                    divider
                    row(L("Size")) {
                        HStack(spacing: 6) {
                            stepButton("minus", L("Smaller"), enabled: part.scale > SlideTextStyle.Part.scales.lowerBound + 0.001) { change { $0.scale = max(SlideTextStyle.Part.scales.lowerBound, (($0.scale - 0.1) * 10).rounded() / 10) } }
                            Text("\(Int((part.scale * 100).rounded()))%")
                                .minorFont(15, .semibold, maxScale: 1.3)
                                .monospacedDigit()
                                .frame(minWidth: 50)
                                .accessibilityLabel(L("Size \(Int((part.scale * 100).rounded())) percent"))
                            stepButton("plus", L("Bigger"), enabled: part.scale < SlideTextStyle.Part.scales.upperBound - 0.001) { change { $0.scale = min(SlideTextStyle.Part.scales.upperBound, (($0.scale + 0.1) * 10).rounded() / 10) } }
                            toggle("bold", L("Bold text"), on: part.bold == true) { change { $0.bold = $0.bold == true ? nil : true } }
                            toggle("italic", L("Italic"), on: part.italic) { change { $0.italic.toggle() } }
                        }
                    }
                    divider
                    row(L("Color")) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                Button { change { $0.color = nil } } label: {
                                    Circle()
                                        .stroke(MinorColor.textTertiary, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                                        .overlay(Text("A").font(.system(size: 11, weight: .semibold)).foregroundColor(MinorColor.textSecondary))
                                        .frame(width: 26, height: 26)
                                        .overlay(Circle().stroke(MinorColor.accent, lineWidth: 2).padding(-3).opacity(part.color == nil ? 1 : 0))
                                        .frame(width: 38, height: 40)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Automatic color")
                                .accessibilityAddTraits(part.color == nil ? .isSelected : [])
                                ForEach(colors, id: \.self) { hex in
                                    let selected = part.color?.uppercased() == hex.uppercased()
                                    Button { change { $0.color = hex } } label: {
                                        Circle()
                                            .fill(Color(hex: hex))
                                            .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                                            .frame(width: 26, height: 26)
                                            .overlay(Circle().stroke(MinorColor.accent, lineWidth: 2).padding(-3).opacity(selected ? 1 : 0))
                                            .frame(width: 38, height: 40)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(L("Color \(hex)"))
                                    .accessibilityAddTraits(selected ? .isSelected : [])
                                }
                            }
                        }
                    }
                    if role == .title {
                        divider
                        row(L("Alignment")) {
                            HStack(spacing: 6) {
                                alignButton(.leading, "text.alignleft", L("Left"))
                                alignButton(.center, "text.aligncenter", L("Center"))
                                alignButton(.trailing, "text.alignright", L("Right"))
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))

                if !part.isDefault {
                    Button { change { $0 = SlideTextStyle.Part() } } label: {
                        Label("Reset Text Style", systemImage: "arrow.counterclockwise")
                            .minorFont(15, .medium, maxScale: 1.3)
                            .foregroundColor(MinorColor.textSecondary)
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 10) {
                    Button {
                        dismiss()
                        onEditText()
                    } label: {
                        Label("Edit Text", systemImage: "pencil")
                            .minorFont(15, .semibold, maxScale: 1.3)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white))
                    }
                    .buttonStyle(PressScale())
                    Button {
                        dismiss()
                        onRewrite()
                    } label: {
                        Label("Rewrite with AI", systemImage: "sparkles")
                            .minorFont(15, .medium, maxScale: 1.3)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))
                    }
                    .buttonStyle(PressScale())
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 22)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .foregroundColor(MinorColor.textPrimary)
        .background(MinorColor.editorSheet.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private func change(_ edit: @escaping (inout SlideTextStyle.Part) -> Void) {
        Haptics.selection()
        onChange(role, edit)
    }

    private var divider: some View { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(title).minorFont(14, maxScale: 1.3).frame(minWidth: 70, alignment: .leading)
            Spacer(minLength: 0)
            content()
        }
        .frame(minHeight: 46)
    }

    private func stepButton(_ icon: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 34, height: 32)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                .frame(height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(label)
    }

    private func toggle(_ icon: String, _ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(on ? .black : MinorColor.textPrimary)
                .frame(width: 34, height: 32)
                .background(RoundedRectangle(cornerRadius: 8).fill(on ? Color.white : Color.white.opacity(0.08)))
                .frame(height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func alignButton(_ value: SlideTextStyle.Align, _ icon: String, _ label: String) -> some View {
        let on = part.align == value
        return Button { change { $0.align = $0.align == value ? nil : value } } label: {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundColor(on ? .black : MinorColor.textPrimary)
                .frame(width: 38, height: 32)
                .background(RoundedRectangle(cornerRadius: 8).fill(on ? Color.white : Color.white.opacity(0.08)))
                .frame(height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
