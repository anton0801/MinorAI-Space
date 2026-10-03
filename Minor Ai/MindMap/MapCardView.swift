//
//  MapCardView.swift
//  Minor Ai
//
//  Map row for Your Maps and Recent: thumbnail, title, node count and date.
//  Also the free-plan usage meter.
//

import SwiftUI

struct MapCardView: View {
    let map: MindMap
    var trailing: Trailing = .chevron

    enum Trailing { case chevron, pin, none }

    var body: some View {
        HStack(spacing: 12) {
            MapThumbnail(map: map)
            VStack(alignment: .leading, spacing: 2) {
                Text(map.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(MinorColor.textPrimary)
                    .lineLimit(1)
                Text("\(map.nodeCount) nodes · \(Self.relative(map.updatedAt))")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundColor(MinorColor.textTertiary)
            }
            Spacer(minLength: 8)
            switch trailing {
            case .chevron:
                Image(systemName: "chevron.right").font(.system(size: 14)).foregroundColor(MinorColor.textTertiary)
            case .pin:
                Image(systemName: "pin").font(.system(size: 14)).foregroundColor(MinorColor.textTertiary)
            case .none:
                EmptyView()
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(MinorColor.fillRow))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    static func relative(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return L("Today") }
        if calendar.isDateInYesterday(date) { return L("Yesterday") }
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.current.locale
        // Templates put day and month in the order each language uses ("Oct 3" / "3 окт.").
        formatter.setLocalizedDateFormatFromTemplate(calendar.isDate(date, equalTo: Date(), toGranularity: .year) ? "MMMd" : "yMMMd")
        return formatter.string(from: date)
    }
}

// 64×48 sketch of the map: white root and the first branches in their colors.
struct MapThumbnail: View {
    let map: MindMap

    var body: some View {
        Canvas { context, size in
            let root = CGRect(x: 6, y: size.height / 2 - 5, width: 14, height: 10)
            let branches = Array(map.root.children.prefix(3))
            let ys: [CGFloat] = branches.count == 1 ? [24] : branches.count == 2 ? [16, 32] : [10, 24, 38]
            for (i, _) in branches.enumerated() {
                let color = (map.root.children[i].color ?? BranchColor.forBranch(at: i)).color
                var path = Path()
                path.move(to: CGPoint(x: root.maxX, y: root.midY))
                path.addCurve(to: CGPoint(x: 34, y: ys[i]), control1: CGPoint(x: 27, y: root.midY), control2: CGPoint(x: 27, y: ys[i]))
                context.stroke(path, with: .color(color), lineWidth: 1.5)
                context.fill(Path(roundedRect: CGRect(x: 34, y: ys[i] - 3, width: i % 2 == 0 ? 24 : 20, height: 6), cornerRadius: 3), with: .color(color.opacity(0.8)))
            }
            context.fill(Path(roundedRect: root, cornerRadius: 3), with: .color(MinorColor.sendFill))
        }
        .frame(width: 64, height: 48)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.35)))
        .accessibilityHidden(true)
    }
}

struct UsageMeterView: View {
    @ObservedObject var account = AccountStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Free Maps").font(.system(size: 13))
                Spacer()
                Text("\(min(account.mapsUsed, account.freeMapLimit)) of \(account.freeMapLimit) this month")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(MinorColor.fillThumb)
                    Capsule()
                        .fill(MinorColor.accent)
                        .frame(width: geo.size.width * CGFloat(min(account.mapsUsed, account.freeMapLimit)) / CGFloat(account.freeMapLimit))
                }
            }
            .frame(height: 4)
            Text("Resets on \(account.resetDateText). Minor Plus removes the limit.")
                .font(.system(size: 12))
                .foregroundColor(MinorColor.textTertiary)
        }
        .foregroundColor(MinorColor.textPrimary)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(MinorColor.fillRow))
    }
}
