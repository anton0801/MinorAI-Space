//
//  EditorSheetChrome.swift
//  Minor Ai
//
//  Pieces shared by the map editor's panels (Focus design): the sheet header with Done, titled
//  sections, a wrapping row for chips, and how the person's own labels look.
//

import SwiftUI

// "Node Style" with what it applies to under it, and a white Done button (or a round ×).
struct EditorSheetHeader: View {
    let title: String
    var subtitle: String?
    var closeButton = false     // a round × instead of Done, for panels that only show or send
    var onDone: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .minorFont(21, .bold, style: .title3, maxScale: 1.3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .minorFont(13, style: .footnote, maxScale: 1.3)
                        .foregroundColor(MinorColor.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if closeButton {
                Button(action: onDone) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, -7)
                .accessibilityLabel("Close")
            } else {
                Button(action: onDone) {
                    Text("Done")
                        .minorFont(15, .semibold, maxScale: 1.3)
                        .foregroundColor(.black)
                        .padding(.horizontal, 15)
                        .frame(minHeight: 30)
                        .background(Capsule().fill(Color.white))
                        // A full-size target around the compact button.
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                        .padding(.vertical, -7)
                }
                .buttonStyle(PressScale())
            }
        }
    }
}

// How tall the editors' panels open: just their content, with the map (or slide) in view above.
// iOS adds the home indicator's area below these heights.
enum EditorSheetHeight {
    static let nodeStyle: CGFloat = 334
    static let marks: CGFloat = 286
    static let mapDesign: CGFloat = 348
    static let mapView: CGFloat = 422
    static let deckStyle: CGFloat = 400
    static let slideText: CGFloat = 300
}

struct EditorSection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .minorFont(15, .semibold, style: .subheadline, maxScale: 1.3)
                .foregroundColor(MinorColor.textPrimary)
            content
        }
    }
}

// Lays chips out left to right and wraps to the next line when a row is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + CGFloat(max(rows.count - 1, 0)) * lineSpacing
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            var size = subviews[index].sizeThatFits(.unspecified)
            size.width = min(size.width, width)
            if !row.indices.isEmpty && row.width + spacing + size.width > width {
                rows.append(row)
                row = Row()
            }
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

extension BranchColor {
    // The same label always gets the same color, on every device (no random hashing).
    static func forLabel(_ label: String) -> BranchColor {
        let colors: [BranchColor] = [.mint, .sky, .lilac, .pink, .sun, .coral, .teal, .orange]
        let sum = label.lowercased().unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return colors[sum % colors.count]
    }
}

// Labels under an idea's title on the map: a colored dot and the label, the first two and "+N".
struct NodeLabelsLine: View {
    let labels: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(labels.prefix(2), id: \.self) { label in
                HStack(spacing: 3) {
                    Circle().fill(BranchColor.forLabel(label).color).frame(width: 6, height: 6)
                    Text(label).font(.system(size: 12)).lineLimit(1)
                }
            }
            if labels.count > 2 {
                Text("+\(labels.count - 2)").font(.system(size: 12).monospacedDigit())
            }
        }
        .foregroundColor(MinorColor.textSecondary)
    }
}

// A label as a chip: tinted with its color, with × to remove it when `onRemove` is set.
struct LabelChip: View {
    let label: String
    var onRemove: (() -> Void)?

    var body: some View {
        let color = BranchColor.forLabel(label)
        HStack(spacing: 2) {
            Text(label)
                .minorFont(13, maxScale: 1.3)
                .lineLimit(1)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(color.color)
                        .frame(width: 26, height: 31)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Remove label \(label)"))
            }
        }
        .foregroundColor(MinorColor.textPrimary)
        .padding(.leading, 11)
        .padding(.trailing, onRemove == nil ? 11 : 2)
        .frame(minHeight: 31)
        .background(RoundedRectangle(cornerRadius: 9).fill(color.color.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(color.color.opacity(0.75), lineWidth: 1))
    }
}
