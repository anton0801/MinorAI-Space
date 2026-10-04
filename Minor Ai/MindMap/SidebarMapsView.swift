//
//  SidebarMapsView.swift
//  Minor Ai
//
//  Your Maps in the sidebar: pinned and recent maps, empty state and the free-plan meter.
//

import SwiftUI

enum SidebarTab: Hashable, CaseIterable { case maps, decks, chats }

struct SidebarSegment: View {
    @Binding var selection: SidebarTab

    private let width: CGFloat = 330
    private var segment: CGFloat { width / CGFloat(SidebarTab.allCases.count) }
    private var index: Int { SidebarTab.allCases.firstIndex(of: selection) ?? 0 }

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(MinorColor.track)
            Capsule().fill(MinorColor.fillThumb).frame(width: segment).offset(x: CGFloat(index) * segment)
            HStack(spacing: 0) {
                segment("Maps", .maps)
                segment("Slides", .decks)
                segment("Chats", .chats)
            }
        }
        .frame(width: width, height: 40)
        .overlay(Capsule().stroke(MinorColor.divider, lineWidth: 1))
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selection)
    }

    private func segment(_ title: LocalizedStringKey, _ tab: SidebarTab) -> some View {
        Button {
            Haptics.selection()
            selection = tab
        } label: {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(selection == tab ? MinorColor.textPrimary : MinorColor.textSecondary)
                .frame(width: segment, height: 40)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
    }
}

struct SidebarMapsView: View {
    var onOpen: (UUID) -> Void
    var onOpenJob: (UUID) -> Void = { _ in }

    @State private var pendingDelete: MindMap?
    @ObservedObject private var store = MapStore.shared
    @ObservedObject private var account = AccountStore.shared
    @ObservedObject private var generation = GenerationCenter.shared

    var body: some View {
        VStack(spacing: 0) {
            if store.maps.isEmpty && generation.running.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "map")
                        .font(.system(size: 44))
                    Text("No Maps Yet")
                        .font(.system(size: 18, weight: .bold))
                    Text("Tap the globe on the home screen to start one.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(MinorColor.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 40)
                Spacer()
            } else {
                List {
                    if !generation.running.isEmpty {
                        Section {
                            ForEach(generation.running) { job in
                                Button { onOpenJob(job.id) } label: { BuildingCardView(job: job) }
                                    .buttonStyle(.plain)
                                    .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) { generation.cancel(job.id) } label: { Label("Stop", systemImage: "stop.fill") }
                                    }
                            }
                        } header: {
                            Text("BUILDING")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(MinorColor.textTertiary)
                                .padding(.leading, 4)
                        }
                    }
                    if !store.pinned.isEmpty {
                        section("Pinned", maps: store.pinned)
                    }
                    if !store.recent.isEmpty {
                        section("Recent", maps: store.recent)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            if !account.isPaid {
                UsageMeterView()
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
            }
        }
        .foregroundColor(MinorColor.textPrimary)
        .task { await account.refresh() }
        .confirmationDialog(
            pendingDelete.map(confirmDeleteTitle) ?? "",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { map in
            Button("Delete Map", role: .destructive) { store.delete(map.id) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func confirmDeleteTitle(_ map: MindMap) -> String {
        L("Delete “\(map.title)”? This can’t be undone.")
    }

    private func section(_ title: LocalizedStringKey, maps: [MindMap]) -> some View {
        Section {
            ForEach(maps) { map in
                Button { onOpen(map.id) } label: {
                    MapCardView(map: map, trailing: map.isPinned ? .pin : .chevron)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                // No full swipe: deleting a map can't be undone, so it always asks first.
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) { pendingDelete = map } label: { Label("Delete", systemImage: "trash") }
                    Button { store.togglePin(map.id) } label: {
                        Label(map.isPinned ? "Unpin" : "Pin", systemImage: map.isPinned ? "pin.slash" : "pin")
                    }
                    .tint(MinorColor.premium)
                }
            }
        } header: {
            Text(title)
                .textCase(.uppercase)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(MinorColor.textTertiary)
                .padding(.leading, 4)
        }
    }
}

// A map still being built: bare thumbnail, label and live progress (or the failure).
struct BuildingCardView: View {
    let job: GenerationCenter.Job

    var body: some View {
        HStack(spacing: 12) {
            Canvas { context, size in
                let root = CGRect(x: 6, y: size.height / 2 - 5, width: 14, height: 10)
                var path = Path()
                path.move(to: CGPoint(x: root.maxX, y: root.midY))
                path.addLine(to: CGPoint(x: 40, y: root.midY))
                context.stroke(path, with: .color(MinorColor.textTertiary), style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
                context.fill(Path(roundedRect: root, cornerRadius: 3), with: .color(MinorColor.sendFill))
            }
            .frame(width: 64, height: 48)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.35)))
            VStack(alignment: .leading, spacing: 2) {
                Text(job.label)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(MinorColor.textPrimary)
                    .lineLimit(1)
                if job.error != nil {
                    Text("Couldn’t build · Retry")
                        .font(.system(size: 12))
                        .foregroundColor(MinorColor.danger)
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text("Building… \(job.progress)%")
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundColor(MinorColor.textPrimary)
                    }
                }
            }
            Spacer(minLength: 8)
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(MinorColor.fillRow))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
