//
//  NodeCardView.swift
//  Minor Ai
//
//  Node card (DesignSystem → screens → 5): title, note, source and AI actions for one idea.
//

import SwiftUI

struct NodeCardView: View {
    let map: MindMap
    let nodeID: UUID
    let theme: AppTheme
    var onRename: () -> Void
    var onSaveNote: (String) -> Void
    var onExpand: (ExpandHint) -> Void
    var onAsk: () -> Void
    var onDelete: () -> Void
    var onOpenImage: () -> Void = {}
    var onAddPhoto: () -> Void = {}
    var onGenerateImage: () -> Void = {}
    var onUpgrade: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var isSummarizing = false
    @State private var error: String?
    @State private var errorIsLimit = false
    @FocusState private var noteFocused: Bool

    private var node: MindNode? { map.root.node(nodeID) }
    private var isRoot: Bool { nodeID == map.root.id }

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(MinorColor.fillThumb).frame(width: 36, height: 5).padding(.top, 8)
            HStack(alignment: .top, spacing: 10) {
                if let color = map.branchColor(for: nodeID) {
                    Circle().fill(color.color).frame(width: 10, height: 10).padding(.top, 8)
                }
                Button { act(onRename) } label: {
                    Text(node?.title ?? "")
                        .font(.system(size: 20, weight: .bold))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Rename")
                if noteFocused {
                    Button("Done") {
                        noteFocused = false
                        commit()
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .frame(height: 30)
                } else {
                    Button { commit(); dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(MinorColor.closeFill))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Close")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let picture = node?.image {
                        Button { act(onOpenImage) } label: {
                            NodePicture(id: picture.id)
                                .frame(maxWidth: .infinity)
                                .frame(height: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(alignment: .bottomLeading) {
                                    if picture.isAI {
                                        Label("AI", systemImage: "sparkles")
                                            .font(.system(size: 12, weight: .semibold))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Capsule().fill(.black.opacity(0.55)))
                                            .padding(8)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(picture.isAI ? "Image created with AI" : "Photo")
                    }
                    if let link = node?.link, let url = URL(string: link) {
                        Link(destination: url) {
                            HStack(spacing: 10) {
                                Image(systemName: "link").font(.system(size: 17)).frame(width: 24)
                                Text(url.host ?? link).font(.system(size: 15)).lineLimit(1)
                                Spacer()
                                Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundColor(MinorColor.textPrimary)
                            .padding(.horizontal, 20)
                            .frame(minHeight: 50)
                            .background(RoundedRectangle(cornerRadius: 10).fill(MinorColor.row))
                        }
                    }
                    ZStack(alignment: .topLeading) {
                        if note.isEmpty {
                            Text("Add a note")
                                .font(.system(size: 17))
                                .foregroundColor(theme.placeholderText)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $note)
                            .font(.system(size: 17))
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 88)
                            .focused($noteFocused)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 10).fill(MinorColor.row))

                    if let source = map.source, source.kind != .topic {
                        HStack(spacing: 10) {
                            Image(systemName: icon(for: source.kind)).font(.system(size: 17)).frame(width: 24)
                            Text("From “\(source.label)”").font(.system(size: 15)).lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .frame(height: 50)
                        .background(RoundedRectangle(cornerRadius: 10).fill(MinorColor.row))
                    }

                    if let error {
                        HStack {
                            Text(error).font(.system(size: 13))
                            Spacer()
                            if errorIsLimit { Button("Get Minor Plus", action: onUpgrade).font(.system(size: 13, weight: .semibold)) }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(MinorColor.danger.opacity(0.25)))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(MinorColor.danger.opacity(0.6), lineWidth: 1))
                    }

                    VStack(alignment: .leading, spacing: 15) {
                        Text("AI").font(.system(size: 14, weight: .medium)).foregroundColor(MinorColor.textTertiary)
                        VStack(spacing: 0) {
                            action("sparkles", "Expand with AI") { act { onExpand(.more) } }
                            action("text.alignleft", isSummarizing ? "Summarizing…" : "Summarize Branch") { summarize() }
                            action("lightbulb", "Find Examples") { act { onExpand(.examples) } }
                            action("checklist", "Next Steps") { act { onExpand(.steps) } }
                            action("bubble.left", "Ask in Chat") { act { onAsk() } }
                            action("wand.and.stars", node?.image == nil ? "Create Image with AI" : "New AI Image") { act { onGenerateImage() } }
                            action("photo", node?.image == nil ? "Add Photo" : "Replace Photo", last: true) { act { onAddPhoto() } }
                        }
                        .background(MinorColor.row)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    if !isRoot {
                        Button {
                            dismiss()
                            onDelete()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "trash").font(.system(size: 17)).frame(width: 24)
                                Text("Delete Node").font(.system(size: 17))
                                Spacer()
                            }
                            .foregroundColor(MinorColor.danger)
                            .padding(.horizontal, 20)
                            .frame(height: 50)
                            .background(RoundedRectangle(cornerRadius: 10).fill(MinorColor.row))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .foregroundColor(MinorColor.textPrimary)
        .background(MinorColor.sheet.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .onAppear { note = node?.note ?? "" }
        .onDisappear(perform: commit)
    }

    private func action(_ icon: String, _ title: LocalizedStringKey, last: Bool = false, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 17)).frame(width: 24)
                Text(title).font(.system(size: 17))
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 15)).foregroundColor(MinorColor.textChevron)
            }
            .padding(.horizontal, 20)
            .frame(height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSummarizing)
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(MinorColor.divider).frame(height: 1) } }
    }

    private func act(_ run: () -> Void) {
        commit()
        dismiss()
        run()
    }

    private func commit() {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != (node?.note ?? "") { onSaveNote(trimmed) }
    }

    private func summarize() {
        guard !isSummarizing else { return }
        guard AuthService.shared.isSignedIn else {
            error = BackendError.signInRequired.errorDescription
            return
        }
        guard AIConsent.isGiven else {
            error = L("Allow Minor to use AI first: send any request from the map or chat.")
            return
        }
        isSummarizing = true
        error = nil
        Task {
            do {
                let summary = try await MapService.shared.summarize(map, node: nodeID)
                note = note.isEmpty ? summary : note + "\n\n" + summary
                commit()
                Haptics.success()
            } catch {
                Haptics.error()
                if case BackendError.limitReached(let kind) = error { AccountStore.shared.noteLimitReached(kind: kind) }
                errorIsLimit = (error as? BackendError)?.suggestsUpgrade ?? false
                self.error = (error as? LocalizedError)?.errorDescription ?? L("Couldn’t summarize. Try again.")
            }
            isSummarizing = false
        }
    }

    private func icon(for kind: MapSource.Kind) -> String {
        switch kind {
        case .topic: return "textformat"
        case .document: return "doc.text"
        case .link: return "link"
        case .youtube: return "play.rectangle"
        case .voice: return "mic"
        case .chat: return "bubble.left"
        }
    }
}
