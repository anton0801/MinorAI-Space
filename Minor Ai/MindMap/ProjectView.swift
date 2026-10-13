//
//  ProjectView.swift
//  Minor Ai
//
//  A map as a project: Map, Slides and Chat tabs over one document. The three screens stay alive
//  while you switch, so the selection, zoom, current slide, Undo and the chat draft are kept.
//  Slides here starts a new presentation from the map (or a branch) when you ask; presentations
//  made earlier open from the Library.
//

import SwiftUI

enum ProjectTab: Hashable { case map, slides, chat }

struct ProjectView: View {
    let mapID: UUID
    let theme: AppTheme
    var onClose: () -> Void
    var onUpgrade: (_ pro: Bool) -> Void

    @State private var tab: ProjectTab = .map
    @State private var visited: Set<ProjectTab> = [.map]
    // The presentation made (or opened from the chat) in this visit.
    @State private var deckID: UUID?
    @State private var selection: UUID?
    @State private var slideID: UUID?
    @State private var focusRequest: UUID?
    @StateObject private var chat: ProjectChatModel
    @ObservedObject private var decks = DeckStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(mapID: UUID, theme: AppTheme, initialTab: ProjectTab = .map, onClose: @escaping () -> Void, onUpgrade: @escaping (_ pro: Bool) -> Void) {
        self.mapID = mapID
        self.theme = theme
        self.onClose = onClose
        self.onUpgrade = onUpgrade
        _chat = StateObject(wrappedValue: ProjectChatModel(mapID: mapID))
        _tab = State(initialValue: initialTab)
        _visited = State(initialValue: [.map, initialTab])
    }

    private var tabBar: AnyView {
        AnyView(
            MinorSegments(items: [
                (.map, "Map", "point.3.connected.trianglepath.dotted"),
                (.slides, "Slides", "rectangle.on.rectangle"),
                (.chat, "Chat", "bubble.left"),
            ], selection: Binding(get: { tab }, set: { switchTo($0) }), height: 32)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        )
    }

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

            MapEditorView(
                mapID: mapID,
                theme: theme,
                onClose: onClose,
                onUpgrade: onUpgrade,
                onCreateDeck: { _ in switchTo(.slides) },
                tabs: tabBar,
                onSelectionChange: { selection = $0 },
                onAskInChat: { id in
                    selection = id
                    switchTo(.chat)
                },
                onDiscuss: { text in
                    chat.draft = text
                    switchTo(.chat)
                },
                focusRequest: $focusRequest
            )
            .projectLayer(tab == .map)

            if visited.contains(.slides) {
                Group {
                    if let deckID, decks.deck(deckID) != nil {
                        DeckEditorView(
                            deckID: deckID,
                            theme: theme,
                            onClose: onClose,
                            onOpenMap: { _ in switchTo(.map) },
                            onUpgrade: onUpgrade,
                            tabs: tabBar,
                            onDeleted: { self.deckID = nil },
                            onSlideChange: { slideID = $0 }
                        )
                        .id(deckID)
                    } else {
                        ProjectSlidesStart(mapID: mapID, theme: theme, tabs: tabBar, branch: selection, onBack: onClose, onUpgrade: onUpgrade) { id in
                            deckID = id
                        }
                    }
                }
                .projectLayer(tab == .slides)
            }

            if visited.contains(.chat) {
                ProjectChatView(
                    model: chat,
                    theme: theme,
                    tabs: tabBar,
                    branch: selection,
                    deck: deckID.flatMap { decks.deck($0) },
                    slideID: slideID,
                    onBack: onClose,
                    onUpgrade: onUpgrade,
                    onShowOnMap: { id in
                        focusRequest = id
                        switchTo(.map)
                    },
                    onOpenSlides: { switchTo(.slides) }
                )
                .projectLayer(tab == .chat)
            }
        }
        .onChange(of: chat.deckRequest) { id in
            guard let id else { return }
            chat.deckRequest = nil
            deckID = id
        }
        .onAppear {
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-projectSlides") { switchTo(.slides) }
            if args.contains("-projectChat") { switchTo(.chat) }
            #endif
        }
    }

    private func switchTo(_ next: ProjectTab) {
        guard next != tab else { return }
        // The keyboard of the tab being left goes away with it.
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        visited.insert(next)
        Telemetry.log("project_tab", ["tab": next == .map ? "map" : next == .slides ? "slides" : "chat"])
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) { tab = next }
    }
}

private struct ProjectLayer: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content
            .opacity(active ? 1 : 0)
            .allowsHitTesting(active)
            .accessibilityHidden(!active)
            .zIndex(active ? 1 : 0)
    }
}

extension View {
    // One tab of a project: on screen when active, kept alive (and out of the way) when not.
    func projectLayer(_ active: Bool) -> some View { modifier(ProjectLayer(active: active)) }
}

// Back, the document's title and what it is doing (saved, syncing, not saved), and its actions.
struct ProjectHeader<Trailing: View>: View {
    let title: String
    let status: String
    var statusIsError = false
    var onBack: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 2) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Back")
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .minorFont(17, .semibold, maxScale: 1.25)
                    .lineLimit(1)
                Text(status)
                    .minorFont(12, style: .caption1, maxScale: 1.25)
                    .foregroundColor(statusIsError ? MinorColor.dangerText : MinorColor.textTertiary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            trailing()
        }
        .foregroundColor(MinorColor.textPrimary)
        .padding(.leading, 4)
        .padding(.trailing, 6)
        .frame(minHeight: 52)
    }
}
