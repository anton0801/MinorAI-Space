//
//  MapResultCard.swift
//  Minor Ai
//
//  The map the assistant builds from a conversation, as one card in the chat: how far it is
//  while it builds, then its real outline, Open Map and Make Slides from Map. The conversation
//  stays where it was: going back from the map returns to it.
//

import SwiftUI

struct MapResultCard: View {
    let action: ChatAction
    let theme: AppTheme
    var onOpen: () -> Void
    var onSlides: () -> Void
    var onUpgrade: () -> Void = {}

    @ObservedObject private var store = MapStore.shared
    @ObservedObject private var center = GenerationCenter.shared

    private var map: MindMap? { store.map(action.mapID) }
    private var job: GenerationCenter.Job? { center.jobs[action.mapID] }

    var body: some View {
        VStack(spacing: 8) {
            card
            // The second step sits under the card, quieter than opening the map.
            if map != nil {
                Button(action: onSlides) {
                    HStack(spacing: 6) {
                        Text("Make Slides from Map")
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                    }
                    .minorFont(14, maxScale: 1.3)
                    .foregroundColor(MinorColor.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.plain)
            }
        }
        // The chat shows this map's progress, so no "ready" banner is needed on top of it.
        .onAppear { center.watch(action.mapID, true) }
        .onDisappear { center.watch(action.mapID, false) }
        .animation(.minorMenu, value: map == nil)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(map?.title ?? action.mapTitle)
                        .minorFont(18, .semibold, maxScale: 1.3)
                        .foregroundColor(.white)
                        .lineLimit(2)
                    Text(status)
                        .minorFont(13, maxScale: 1.3)
                        .foregroundColor(job?.error != nil ? MinorColor.dangerText : MinorColor.textTertiary)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
                if map != nil {
                    Menu {
                        Button(action: onOpen) { Label("Open Map", systemImage: "point.3.connected.trianglepath.dotted") }
                        Button(action: onSlides) { Label("Make Slides from Map", systemImage: "rectangle.on.rectangle") }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                            .frame(width: 44, height: 44)
                    }
                    .padding(.trailing, -6)
                    .padding(.top, -6)
                    .accessibilityLabel("More")
                }
            }
            if let map {
                MapMiniPreview(map: map)
                    .frame(height: 196)
                    .accessibilityHidden(true)
                Button(action: onOpen) {
                    Text("Open Map")
                        .minorFont(16, .semibold, maxScale: 1.3)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white))
                }
                .buttonStyle(PressScale())
            } else if let job, job.error == nil {
                building(job)
            } else if let error = job?.error, error.suggestsUpgrade {
                Button(action: onUpgrade) {
                    Text(AccountStore.shared.effectivePlan == .plus ? "Get PRO" : "Get Minor Plus")
                        .minorFont(15, .semibold, maxScale: 1.3)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Capsule().fill(MinorColor.accent))
                }
                .buttonStyle(PressScale())
            } else if job?.error != nil {
                Button { center.retry(action.mapID) } label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                        .minorFont(15, .semibold, maxScale: 1.3)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Capsule().fill(Color.white))
                }
                .buttonStyle(PressScale())
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(theme.chatRectangle))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(theme.chatStroke, lineWidth: 1))
    }

    private var status: String {
        if let map { return L("Map ready · \(map.nodeCount) ideas") }
        if let error = job?.error { return error.errorDescription ?? L("Couldn’t build the map.") }
        if job != nil { return L("Building the map…") }
        return L("This map isn’t available.")
    }

    private func building(_ job: GenerationCenter.Job) -> some View {
        let steps = [L("Reading"), L("Finding the main ideas"), L("Building branches"), L("Adding details")]
        return VStack(alignment: .leading, spacing: 10) {
            ProgressView(value: Double(min(job.step, 4)) / 4)
                .tint(MinorColor.accent)
            HStack(spacing: 8) {
                ProgressView().tint(MinorColor.textSecondary).scaleEffect(0.8)
                Text(steps[min(job.step, steps.count - 1)])
                    .minorFont(14, maxScale: 1.3)
                    .foregroundColor(MinorColor.textSecondary)
            }
            Text("You can keep chatting; the map stays here.")
                .minorFont(12, style: .caption1, maxScale: 1.3)
                .foregroundColor(MinorColor.textTertiary)
        }
        .accessibilityElement(children: .combine)
    }
}

// The topic and its main branches with their colors and icons, as the map draws them.
struct MapMiniPreview: View {
    let map: MindMap

    var body: some View {
        GeometryReader { geo in
            let branches = Array(map.root.children.filter { !$0.isSuggestion }.prefix(5))
            let w = geo.size.width, h = geo.size.height
            let rootSize = CGSize(width: min(w * 0.36, 140), height: 40)
            let root = CGPoint(x: 6 + rootSize.width / 2, y: h / 2)
            let rowH = h / CGFloat(max(branches.count, 1))
            let branchX = w * 0.5
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    for (i, branch) in branches.enumerated() {
                        let y = rowH * (CGFloat(i) + 0.5)
                        var path = Path()
                        let start = CGPoint(x: root.x + rootSize.width / 2, y: root.y)
                        let end = CGPoint(x: branchX, y: y)
                        path.move(to: start)
                        path.addCurve(to: end, control1: CGPoint(x: (start.x + end.x) / 2, y: start.y), control2: CGPoint(x: (start.x + end.x) / 2, y: end.y))
                        context.stroke(path, with: .color(color(branch, i)), lineWidth: 2)
                    }
                }
                Text(map.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.black)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
                    .frame(width: rootSize.width, height: rootSize.height)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                    .position(root)
                ForEach(Array(branches.enumerated()), id: \.element.id) { i, branch in
                    HStack(spacing: 6) {
                        if let icon = branch.icon { Text(icon).font(.system(size: 13)) }
                        Text(branch.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: min(rowH - 6, 32))
                    .background(Capsule().fill(color(branch, i).opacity(0.14)))
                    .overlay(Capsule().stroke(color(branch, i), lineWidth: 1.5))
                    .frame(width: w - branchX - 4, alignment: .leading)
                    .position(x: branchX + (w - branchX - 4) / 2, y: rowH * (CGFloat(i) + 0.5))
                }
            }
        }
    }

    private func color(_ branch: MindNode, _ i: Int) -> Color {
        (branch.color ?? map.mapPalette.colors[i % map.mapPalette.colors.count]).color
    }
}
