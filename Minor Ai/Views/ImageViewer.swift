//
//  ImageViewer.swift
//  Minor Ai
//
//  Full-screen picture: pinch to zoom, share, save to Photos, and report AI images
//  (App Store Review 1.2 asks for a way to report generated content).
//

import Photos
import SwiftUI
import UIKit

struct ViewerItem: Identifiable {
    let id = UUID()
    let image: UIImage
    var isAI = false
    var onReport: (() -> Void)?
}

struct ImageViewer: View {
    let item: ViewerItem

    @Environment(\.dismiss) private var dismiss
    @GestureState private var pinch: CGFloat = 1
    @State private var zoom: CGFloat = 1
    @State private var saved = false
    @State private var saveFailed = false
    @State private var confirmReport = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image(uiImage: item.image)
                .resizable()
                .scaledToFit()
                .scaleEffect(min(max(zoom * pinch, 1), 4))
                .gesture(
                    MagnificationGesture()
                        .updating($pinch) { value, state, _ in state = value }
                        .onEnded { value in withAnimation(.minorFit) { zoom = min(max(zoom * value, 1), 4) } }
                )
                .onTapGesture(count: 2) { withAnimation(.minorFit) { zoom = zoom > 1 ? 1 : 2 } }
                .accessibilityLabel(item.isAI ? "Image created with AI" : "Photo")
                .accessibilityAddTraits(.isImage)

            VStack {
                HStack(spacing: 4) {
                    toolbarButton("xmark", "Close") { dismiss() }
                    Spacer()
                    ShareLink(item: Image(uiImage: item.image), preview: SharePreview("Minor AI", image: Image(uiImage: item.image))) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Share")
                    toolbarButton(saved ? "checkmark" : "square.and.arrow.down", saved ? "Saved" : "Save to Photos") { save() }
                        .alert("Couldn’t save to Photos", isPresented: $saveFailed) {
                            Button("OK", role: .cancel) {}
                        } message: {
                            Text("Allow Minor to add photos in iOS Settings → Privacy & Security → Photos.")
                        }
                    if item.onReport != nil {
                        toolbarButton("flag", "Report") { confirmReport = true }
                    }
                }
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                Spacer()
                if item.isAI {
                    Label("Created with AI", systemImage: "sparkles")
                        .font(.system(size: 13))
                        .foregroundColor(MinorColor.textSecondary)
                        .padding(.bottom, 12)
                }
            }
        }
        .confirmationDialog("Report this image?", isPresented: $confirmReport, titleVisibility: .visible) {
            Button("Report and Hide", role: .destructive) {
                item.onReport?()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The image is hidden and its description is sent to us for review.")
        }
        .accessibilityAction(.escape) { dismiss() }
    }

    private func toolbarButton(_ icon: String, _ label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }

    // "Saved" only when the picture really reached Photos (access may be denied).
    private func save() {
        let image = item.image
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                saveFailed = true
                Haptics.error()
                return
            }
            do {
                try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAsset(from: image) }
                saved = true
                Haptics.success()
            } catch {
                saveFailed = true
                Haptics.error()
            }
        }
    }
}
