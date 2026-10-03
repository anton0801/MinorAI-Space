//
//  VersionHistoryView.swift
//  Minor Ai
//
//  Earlier versions of a map kept on this device (one every 10 minutes of editing, the last 30).
//  Tap one to see it; Restore brings it back, and the current map becomes a version itself.
//

import SwiftUI

struct VersionHistoryView: View {
    let mapID: UUID
    let theme: AppTheme
    var onRestored: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var versions: [MapStore.Version] = []
    @State private var preview: MapStore.Version?

    var body: some View {
        NavigationStack {
            List {
                if versions.isEmpty {
                    Text("Versions appear here as you edit: one every 10 minutes, the last 30.")
                        .font(.system(size: 15))
                        .foregroundColor(MinorColor.textSecondary)
                        .listRowBackground(theme.chatRectangle)
                }
                ForEach(versions) { version in
                    Button { preview = version } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundColor(MinorColor.accent)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(version.date.formatted(.dateTime.day().month().hour().minute().locale(AppLanguage.current.locale)))
                                    .font(.system(size: 16, weight: .medium))
                                Text(summary(version))
                                    .font(.system(size: 13))
                                    .foregroundColor(MinorColor.textTertiary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(MinorColor.textChevron)
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(theme.chatRectangle)
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.background.ignoresSafeArea())
            .foregroundColor(MinorColor.textPrimary)
            .navigationTitle("Version History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundColor(MinorColor.accent)
                }
            }
            .sheet(item: $preview) { version in
                VersionPreview(version: version, theme: theme) {
                    MapStore.shared.restore(version, of: mapID)
                    Haptics.success()
                    preview = nil
                    dismiss()
                    onRestored()
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { versions = MapStore.shared.versions(of: mapID) }
    }

    private func summary(_ version: MapStore.Version) -> String {
        let relative = version.date.formatted(.relative(presentation: .named).locale(AppLanguage.current.locale))
        guard let map = MapStore.shared.load(version) else { return relative }
        return L("\(relative) · \(map.nodeCount) ideas")
    }
}

private struct VersionPreview: View {
    let version: MapStore.Version
    let theme: AppTheme
    var onRestore: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var confirm = false

    var body: some View {
        NavigationStack {
            Group {
                if let map = MapStore.shared.load(version) {
                    let layout = MapLayout(map: map.fullyExpanded)
                    GeometryReader { geo in
                        ScrollView([.horizontal, .vertical]) {
                            let scale = min(1, geo.size.width / max(layout.size.width, 1))
                            MapSnapshotView(layout: layout, theme: theme, mapStyle: map.mapStyle, lineStyle: map.lineStyle, lineWeight: map.lineWeightValue, links: map.links, watermark: false)
                                .frame(width: layout.size.width, height: layout.size.height)
                                .scaleEffect(scale, anchor: .topLeading)
                                .frame(width: layout.size.width * scale, height: layout.size.height * scale, alignment: .topLeading)
                        }
                    }
                } else {
                    Text("This version can’t be opened.")
                        .foregroundColor(MinorColor.textSecondary)
                }
            }
            .background(theme.background.ignoresSafeArea())
            .navigationTitle(version.date.formatted(.dateTime.day().month().hour().minute().locale(AppLanguage.current.locale)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.foregroundColor(MinorColor.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Restore") { confirm = true }.foregroundColor(MinorColor.accent)
                }
            }
            .confirmationDialog("Restore this version? The current map is kept in the history.", isPresented: $confirm, titleVisibility: .visible) {
                Button("Restore", action: onRestore)
                Button("Cancel", role: .cancel) {}
            }
        }
        .preferredColorScheme(.dark)
    }
}
