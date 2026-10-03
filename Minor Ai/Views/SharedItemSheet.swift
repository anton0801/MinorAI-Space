//
//  SharedItemSheet.swift
//  Minor Ai
//
//  A page or text shared to Minor from another app (see the MinorShare extension): one tap
//  builds a map from it.
//

import SwiftUI

struct SharedItemSheet: View {
    let item: SharedItem
    let theme: AppTheme
    var onBuild: () -> Void
    var onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: item.url != nil ? "link" : "doc.text")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(MinorColor.accent)
                Text("Shared to Minor")
                    .font(.system(size: 18, weight: .bold))
            }
            VStack(alignment: .leading, spacing: 4) {
                if let title = item.title {
                    Text(title).font(.system(size: 16, weight: .semibold)).lineLimit(2)
                }
                if let url = item.url {
                    Text(URL(string: url)?.host ?? url)
                        .font(.system(size: 14))
                        .foregroundColor(MinorColor.textSecondary)
                        .lineLimit(1)
                } else if let text = item.text {
                    Text(text)
                        .font(.system(size: 14))
                        .foregroundColor(MinorColor.textSecondary)
                        .lineLimit(4)
                }
            }
            Button(action: onBuild) {
                Label("Build a Map", systemImage: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Capsule().fill(MinorColor.accent))
            }
            .buttonStyle(.plain)
            Button(action: onDiscard) {
                Text("Not Now")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(MinorColor.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
            }
            .buttonStyle(.plain)
        }
        .padding(22)
        .foregroundColor(MinorColor.textPrimary)
        .background(theme.background.ignoresSafeArea())
        .presentationDetents([.height(320)])
        .preferredColorScheme(.dark)
    }

    // What to build: a web page, a YouTube video or the shared text.
    static func input(for item: SharedItem) -> MapInput {
        if let raw = item.url, let url = URL(string: raw) {
            return CreateMapView.isYouTube(url) ? .youtube(raw) : .link(raw)
        }
        return .text(item.text ?? "", source: MapSource(kind: .document, label: item.title ?? L("Shared text")))
    }
}
