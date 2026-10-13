//
//  LibraryView.swift
//  Minor Ai
//
//  The Library: saved maps, presentations and chats in one place. The assistant's top button and
//  Menu → Library open this same screen with the same state. Search works within the chosen tab;
//  pinned items come first, then the rest in the chosen order; each row's "…" has what the person
//  may do with it. Everything is local, so it works offline and while sync runs.
//

import SwiftUI

// A full-width capsule switch between a few tabs (Maps / Slides, Map / Slides / Chat).
struct MinorSegments<Item: Hashable>: View {
    let items: [(Item, LocalizedStringKey, String?)]   // value, title, SF Symbol
    @Binding var selection: Item
    var height: CGFloat = 40

    // Editors' panels use a compact control (about 30 high) with smaller type and corners.
    private var compact: Bool { height <= 32 }
    private var radius: CGFloat { compact ? 9 : 14 }

    // The design system's segment control: a dark track with a faint outline, the chosen segment
    // on a 20% white thumb in white text, the others in secondary text with a thin line between.
    var body: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                segment(items[i].0, items[i].1, items[i].2)
                    .overlay(alignment: .leading) {
                        if i > 0, selection != items[i].0, selection != items[i - 1].0 {
                            Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: height * 0.45)
                        }
                    }
            }
        }
        .background(RoundedRectangle(cornerRadius: radius).fill(MinorColor.track))
        .overlay(RoundedRectangle(cornerRadius: radius).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    private func segment(_ value: Item, _ title: LocalizedStringKey, _ icon: String?) -> some View {
        let chosen = selection == value
        return Button {
            guard !chosen else { return }
            Haptics.selection()
            withAnimation(.minorMenu) { selection = value }
        } label: {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 13)) }
                Text(title).minorFont(compact ? 14 : 15, chosen ? .semibold : .medium, maxScale: 1.3).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundColor(chosen ? .white : MinorColor.textSecondary)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(RoundedRectangle(cornerRadius: radius - 3).fill(chosen ? MinorColor.fillThumb : Color.clear).padding(3))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

// What the Library keeps while the app runs: the tab (also across launches) and the search. A
// document opened from it covers it, so on return the list is where it was.
@MainActor
final class LibraryState: ObservableObject {
    static let shared = LibraryState()

    @Published var tab: LibraryTab {
        didSet { UserDefaults.standard.set(tab.rawValue, forKey: "libraryTab") }
    }
    @Published var query = ""
    // Set when the Library comes in from the assistant: its list fades in once (not on the return
    // from a document, and not on a push from the menu).
    @Published var fadePending = false

    private init() {
        tab = LibraryTab(rawValue: UserDefaults.standard.string(forKey: "libraryTab") ?? "") ?? .maps
    }
}

struct LibraryView: View {
    let theme: AppTheme
    var onOpenMap: (UUID) -> Void
    var onOpenDeck: (UUID) -> Void
    var onOpenChat: (Conversation) -> Void
    var onOpenJob: (UUID) -> Void
    var onNewMap: () -> Void
    var onNewDeck: () -> Void
    var onNewChat: () -> Void
    var onLimits: () -> Void
    var onSettings: () -> Void

    enum Sort: String, CaseIterable { case opened, edited, name }

    @ObservedObject private var state = LibraryState.shared
    @ObservedObject private var maps = MapStore.shared
    @ObservedObject private var decks = DeckStore.shared
    @ObservedObject private var chats = ChatViewModel.shared
    @ObservedObject private var recents = RecentDocuments.shared
    @ObservedObject private var generation = GenerationCenter.shared
    @ObservedObject private var account = AccountStore.shared
    @AppStorage("librarySort") private var sort: Sort = .opened
    @FocusState private var searchFocused: Bool
    @AccessibilityFocusState private var titleFocused: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = true
    @State private var titleScrolledAway = false
    @State private var height: CGFloat = 800
    @State private var confirm: Confirm?
    @State private var renaming: Item?
    @State private var renameText = ""
    @State private var notice: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                title
                searchField.padding(.top, 14)
                MinorSegments(items: [(.maps, "Maps", nil), (.decks, "Slides", nil), (.chats, "Chats", nil)], selection: $state.tab)
                    .padding(.top, 14)

                VStack(alignment: .leading, spacing: 0) {
                    if state.tab == .maps { building }
                    list
                    unreadableNote
                }
                .opacity(shown ? 1 : 0)
                .offset(y: shown || reduceMotion ? 0 : 8)

                if !bottomPinned { bottomBlock.padding(.top, 28) }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .coordinateSpace(name: "library")
        .onPreferenceChange(TitleBottom.self) { bottom in
            let away = bottom < 4
            if away != titleScrolledAway { titleScrolledAway = away }
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if bottomPinned {
                bottomBlock
                    .padding(.horizontal, 16)
                    .background(theme.background.ignoresSafeArea())
            }
        }
        .background(GeometryReader { geo in
            Color.clear
                .onAppear { height = geo.size.height }
                .onChange(of: geo.size.height) { height = $0 }
        })
        .background(theme.background.ignoresSafeArea())
        .foregroundColor(MinorColor.textPrimary)
        .navigationTitle(Text("Library"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The big title is in the list; once it scrolls away the bar shows it small.
            ToolbarItem(placement: .principal) {
                Text("Library")
                    .minorFont(17, .semibold, maxScale: 1.2)
                    .opacity(titleScrolledAway ? 1 : 0)
                    .animation(.easeOut(duration: 0.15), value: titleScrolledAway)
                    .accessibilityHidden(true)
            }
            ToolbarItem(placement: .navigationBarTrailing) { newButton }
        }
        .confirmationDialog(confirm?.title ?? "", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                            titleVisibility: .visible, presenting: confirm) { item in
            Button(item.action, role: .destructive) { perform(item) }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            if let message = item.message { Text(message) }
        }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Save") { rename() }
            Button("Cancel", role: .cancel) {}
        }
        .alert(notice ?? "", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .onAppear {
            fadeInIfNeeded()
            DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.2 : 0.35)) { titleFocused = true }
        }
        .onChange(of: state.fadePending) { _ in fadeInIfNeeded() }
        .task { await account.refresh() }
    }

    // MARK: - Top

    private var title: some View {
        Text("Library")
            .minorFont(34, .bold, style: .largeTitle, maxScale: 1.3)
            .accessibilityAddTraits(.isHeader)
            .accessibilityFocused($titleFocused)
            .padding(.top, 2)
            .background(GeometryReader { geo in
                Color.clear.preference(key: TitleBottom.self, value: geo.frame(in: .named("library")).maxY)
            })
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(MinorColor.textSecondary)
                .accessibilityHidden(true)
            TextField("", text: $state.query)
                .placeholder(when: state.query.isEmpty) {
                    Text(searchPrompt).foregroundColor(MinorColor.textTertiary).lineLimit(1)
                }
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .accessibilityLabel(Text(searchPrompt))
            if !state.query.isEmpty {
                Button { state.query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(MinorColor.textTertiary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Clear Search")
            }
        }
        .minorFont(17, maxScale: 1.4)
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { searchFocused = true }
    }

    private var searchPrompt: String {
        switch state.tab {
        case .maps: return L("Search maps")
        case .decks: return L("Search presentations")
        case .chats: return L("Search chats")
        }
    }

    private var newButton: some View {
        Button {
            searchFocused = false
            switch state.tab {
            case .maps: onNewMap()
            case .decks: onNewDeck()
            case .chats: onNewChat()
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.white.opacity(0.1)))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text(newTitle))
    }

    private var newTitle: LocalizedStringKey {
        switch state.tab {
        case .maps: return "New Map"
        case .decks: return "New Presentation"
        case .chats: return "New Chat"
        }
    }

    // MARK: - Lists

    // Maps still being built (open to watch, Stop from the context menu).
    @ViewBuilder
    private var building: some View {
        if state.query.isEmpty, !generation.running.isEmpty {
            sectionHeader("Building", sortable: false)
            VStack(spacing: 8) {
                ForEach(generation.running) { job in
                    Button { onOpenJob(job.id) } label: { BuildingCardView(job: job) }
                        .buttonStyle(PressScale())
                        .contextMenu {
                            Button(role: .destructive) { generation.cancel(job.id) } label: { Label("Stop", systemImage: "stop.fill") }
                        }
                        .accessibilityAction(named: "Stop") { generation.cancel(job.id) }
                }
            }
            .padding(.top, 10)
        }
    }

    @ViewBuilder
    private var list: some View {
        let all = sorted(items.filter(matches))
        if isEmptyTab {
            empty
        } else if all.isEmpty {
            if !state.query.isEmpty { noResults }
        } else if !state.query.isEmpty {
            sectionHeader("Results", sortable: true)
            rows(all)
        } else {
            let pinned = all.filter(\.pinned)
            let rest = all.filter { !$0.pinned }
            if !pinned.isEmpty {
                sectionHeader("Pinned", sortable: true)
                rows(pinned)
            }
            if !rest.isEmpty {
                sectionHeader(restTitle, sortable: pinned.isEmpty)
                rows(rest)
            }
        }
    }

    private func rows(_ items: [Item]) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(items) { item in
                row(item)
            }
        }
    }

    private func row(_ item: Item) -> some View {
        HStack(spacing: 10) {
            Button { open(item) } label: {
                HStack(spacing: 14) {
                    thumbnail(item)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title.isEmpty ? L("Untitled") : item.title)
                            .minorFont(17, .semibold, maxScale: 1.4)
                            .foregroundColor(MinorColor.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 5) {
                            if item.shared {
                                Image(systemName: "person.2.fill")
                                    .font(.system(size: 11))
                                    .accessibilityLabel("Shared")
                            }
                            Text(meta(item))
                                .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                        }
                        .minorFont(15, maxScale: 1.4)
                        .foregroundColor(MinorColor.textSecondary)
                    }
                    Spacer(minLength: 4)
                    if item.pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 15))
                            .rotationEffect(.degrees(45))
                            .foregroundColor(MinorColor.accent)
                            .accessibilityLabel("Pinned")
                    }
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressScale())
            .accessibilityElement(children: .combine)
            more(item)
        }
        .overlay(alignment: .bottom) { line }
    }

    @ViewBuilder
    private func thumbnail(_ item: Item) -> some View {
        switch item.kind {
        case .map(let map):
            LibraryMapThumbnail(map: map)
        case .deck(let deck):
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.35))
                if let first = deck.slides.first(where: { !$0.isHidden }) ?? deck.slides.first {
                    SlideCanvas(slide: first, deck: deck)
                        .frame(width: 76, height: 42.75)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
            }
            .frame(width: 88, height: 68)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
            .accessibilityHidden(true)
        case .chat:
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 19))
                .foregroundColor(MinorColor.textSecondary)
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
                .accessibilityHidden(true)
        }
    }

    // The row's "…": what this person may do with it. A member of someone else's map leaves it
    // (and keeps a copy); only the owner deletes a shared map for good.
    private func more(_ item: Item) -> some View {
        Menu {
            Button { open(item) } label: { Label("Open", systemImage: "arrow.up.right") }
            if item.canRename {
                Button {
                    renameText = item.title
                    renaming = item
                } label: { Label("Rename", systemImage: "pencil") }
            }
            Button { togglePin(item) } label: {
                Label(item.pinned ? "Unpin" : "Pin", systemImage: item.pinned ? "pin.slash" : "pin")
            }
            if case .chat = item.kind {} else {
                Button { duplicate(item) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
            }
            Divider()
            switch item.kind {
            case .map(let map) where map.collab.map { !$0.isOwner } == true:
                Button(role: .destructive) { confirm = .leaveMap(map) } label: { Label("Leave Map", systemImage: "rectangle.portrait.and.arrow.right") }
            case .map(let map):
                Button(role: .destructive) { confirm = .deleteMap(map) } label: { Label("Delete", systemImage: "trash") }
            case .deck(let deck):
                Button(role: .destructive) { confirm = .deleteDeck(deck) } label: { Label("Delete", systemImage: "trash") }
            case .chat(let chat):
                Button(role: .destructive) { confirm = .deleteChat(chat) } label: { Label("Delete", systemImage: "trash") }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.white.opacity(0.09)))
                .frame(width: 44, height: 56)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text("More for \(item.title)"))
    }

    private func sectionHeader(_ title: LocalizedStringKey, sortable: Bool) -> some View {
        HStack(alignment: .center) {
            Text(title)
                .minorFont(16, .medium, style: .subheadline, maxScale: 1.3)
                .foregroundColor(MinorColor.textSecondary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if sortable {
                Menu {
                    Picker(selection: $sort) {
                        Text("Recently Opened").tag(Sort.opened)
                        Text("Recently Edited").tag(Sort.edited)
                        Text("Name").tag(Sort.name)
                    } label: { EmptyView() }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(MinorColor.textSecondary)
                        .frame(width: 44, height: 36)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Sort")
                .accessibilityValue(Text(sortTitle))
            }
        }
        .frame(minHeight: 36)
        .padding(.top, 18)
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) { line }
    }

    private var line: some View {
        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
    }

    // MARK: - States

    @ViewBuilder
    private var empty: some View {
        switch state.tab {
        case .maps:
            emptyState(icon: "point.3.connected.trianglepath.dotted", title: "No Maps Yet",
                       text: "Start from a topic, a document, a link or your voice.", action: "New Map", onNewMap)
        case .decks:
            emptyState(icon: "rectangle.on.rectangle.angled", title: "No Presentations Yet",
                       text: "Make one from a map, a topic or a chat in about half a minute.", action: "New Presentation", onNewDeck)
        case .chats:
            emptyState(icon: "bubble.left.and.bubble.right", title: "No Chats Yet",
                       text: "Ask Minor anything; your conversations stay here.", action: "New Chat", onNewChat)
        }
    }

    private func emptyState(icon: String, title: LocalizedStringKey, text: LocalizedStringKey, action: LocalizedStringKey, _ perform: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 38)).foregroundColor(MinorColor.textSecondary).accessibilityHidden(true)
            Text(title).minorFont(18, .bold, maxScale: 1.4).accessibilityAddTraits(.isHeader)
            Text(text)
                .minorFont(15, maxScale: 1.4)
                .foregroundColor(MinorColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: perform) {
                Label(action, systemImage: "plus")
                    .minorFont(16, .semibold, maxScale: 1.3)
                    .foregroundColor(.black)
                    .padding(.horizontal, 22)
                    .frame(minHeight: 46)
                    .background(Capsule().fill(Color.white))
            }
            .buttonStyle(PressScale())
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 48)
        .padding(.bottom, 12)
    }

    private var noResults: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 30)).foregroundColor(MinorColor.textSecondary).accessibilityHidden(true)
            Text("Nothing found for “\(state.query)”")
                .minorFont(16, .semibold, maxScale: 1.4)
                .multilineTextAlignment(.center)
            Button("Clear Search") { state.query = "" }
                .minorFont(15, .medium, maxScale: 1.3)
                .foregroundColor(MinorColor.accent)
                .frame(minHeight: 44)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }

    // Files set aside because they couldn't be read: said plainly, with a retry.
    @ViewBuilder
    private var unreadableNote: some View {
        let count = state.tab == .maps ? maps.unreadable : state.tab == .decks ? decks.unreadable : 0
        if count > 0 {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "exclamationmark.triangle").foregroundColor(MinorColor.textSecondary).accessibilityHidden(true)
                Text(state.tab == .maps ? L("Maps that couldn’t be read: \(count)") : L("Presentations that couldn’t be read: \(count)"))
                    .foregroundColor(MinorColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                Button("Try Again") {
                    if state.tab == .maps { maps.retryUnreadable() } else { decks.retryUnreadable() }
                    let left = state.tab == .maps ? maps.unreadable : decks.unreadable
                    if left == count { notice = L("Still can’t read them. They are kept on this iPhone; a later update may open them.") }
                }
                .foregroundColor(MinorColor.accent)
                .frame(minHeight: 44)
            }
            .minorFont(14, maxScale: 1.4)
            .padding(.top, 14)
        }
    }

    // MARK: - Bottom

    // The month's limit (when it applies) and Settings: pinned under the list while there's room,
    // part of the list with large text, on short screens and while typing.
    private var bottomPinned: Bool {
        !searchFocused && typeSize <= .xxLarge && height >= 640
    }

    private var bottomBlock: some View {
        VStack(spacing: 0) {
            line
            if let limit {
                Button(action: onLimits) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(limit.title).minorFont(17, .semibold, maxScale: 1.3)
                            Spacer(minLength: 8)
                            Text(L("\(limit.used) of \(limit.limit)"))
                                .minorFont(17, maxScale: 1.3)
                                .monospacedDigit()
                                .foregroundColor(MinorColor.textSecondary)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.06))
                                Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1)
                                Capsule()
                                    .fill(MinorColor.accent)
                                    .frame(width: geo.size.width * limit.share)
                                    .opacity(limit.used > 0 ? 1 : 0)
                            }
                        }
                        .frame(height: 12)
                    }
                    .foregroundColor(MinorColor.textPrimary)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressScale())
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("\(limit.title), \(L("\(limit.used) of \(limit.limit)"))"))
                .accessibilityHint("Opens your limits")
                line
            }
            Button(action: onSettings) {
                HStack(spacing: 14) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 20))
                        .frame(width: 26)
                        .accessibilityHidden(true)
                    Text("Settings").minorFont(17, maxScale: 1.4)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(MinorColor.textTertiary)
                        .accessibilityHidden(true)
                }
                .foregroundColor(MinorColor.textPrimary)
                .frame(minHeight: 54)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressScale())
            line
        }
    }

    private struct Limit {
        let title: String
        let used: Int
        let limit: Int
        var share: CGFloat { limit > 0 ? CGFloat(min(used, limit)) / CGFloat(limit) : 0 }
    }

    // The limit of the open tab from the account: always on the free plan, on a paid one only when
    // most of it is used. Chats count only when the server reports a limit.
    private var limit: Limit? {
        let report = account.report
        let free = !account.isPaid
        func shown(_ used: Int, _ limit: Int) -> Bool { limit > 0 && (free || Double(used) >= Double(limit) * 0.8) }
        switch state.tab {
        case .maps:
            let total = report?.counts.maps.limit ?? (free ? account.freeMapLimit : 0)
            let used = report?.counts.maps.used ?? account.mapsUsed
            return shown(used, total) ? Limit(title: L("Maps this month"), used: min(used, total), limit: total) : nil
        case .decks:
            let total = report?.counts.decks.limit ?? (free ? account.freeDeckLimit : 0)
            let used = report?.counts.decks.used ?? account.decksUsed
            return shown(used, total) ? Limit(title: L("Presentations this month"), used: min(used, total), limit: total) : nil
        case .chats:
            guard let chats = report?.counts.chats, Double(chats.used) >= Double(chats.limit) * 0.8, chats.limit > 0 else { return nil }
            return Limit(title: L("Chats this month"), used: min(chats.used, chats.limit), limit: chats.limit)
        }
    }

    // MARK: - Data

    struct Item: Identifiable {
        enum Kind {
            case map(MindMap)
            case deck(Deck)
            case chat(Conversation)
        }
        let kind: Kind
        let id: UUID
        let title: String
        let pinned: Bool
        let opened: Date
        let edited: Date

        var shared: Bool {
            if case .map(let map) = kind { return map.collab != nil }
            return false
        }

        // A viewer of a shared map can't change its name.
        var canRename: Bool {
            if case .map(let map) = kind { return map.collab?.role != .viewer }
            return true
        }
    }

    private var isEmptyTab: Bool {
        switch state.tab {
        case .maps: return maps.maps.isEmpty && generation.running.isEmpty
        case .decks: return decks.decks.isEmpty
        case .chats: return chats.conversations.isEmpty
        }
    }

    private var items: [Item] {
        switch state.tab {
        case .maps:
            return maps.maps.map { Item(kind: .map($0), id: $0.id, title: $0.title, pinned: $0.isPinned, opened: recents.openedAt($0.id) ?? $0.updatedAt, edited: $0.updatedAt) }
        case .decks:
            return decks.decks.map { Item(kind: .deck($0), id: $0.id, title: $0.title, pinned: $0.isPinned, opened: recents.openedAt($0.id) ?? $0.updatedAt, edited: $0.updatedAt) }
        case .chats:
            return chats.conversations.map { Item(kind: .chat($0), id: $0.id, title: $0.title, pinned: $0.isPinned, opened: $0.updatedAt, edited: $0.updatedAt) }
        }
    }

    // The title, and what's inside: a map's first ideas, a chat's messages.
    private func matches(_ item: Item) -> Bool {
        let q = state.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        if item.title.localizedCaseInsensitiveContains(q) { return true }
        switch item.kind {
        case .map(let map): return map.root.children.contains { $0.title.localizedCaseInsensitiveContains(q) }
        case .deck: return false
        case .chat(let chat): return chat.messages.contains { !$0.isHidden && $0.text.localizedCaseInsensitiveContains(q) }
        }
    }

    private func sorted(_ list: [Item]) -> [Item] {
        switch sort {
        case .opened: return list.sorted { $0.opened > $1.opened }
        case .edited: return list.sorted { $0.edited > $1.edited }
        case .name: return list.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }

    private var restTitle: LocalizedStringKey {
        switch sort {
        case .opened: return "Recent"
        case .edited: return "Recently Edited"
        case .name: return "By Name"
        }
    }

    private var sortTitle: String {
        switch sort {
        case .opened: return L("Recently Opened")
        case .edited: return L("Recently Edited")
        case .name: return L("By Name")
        }
    }

    // "28 nodes · Yesterday": the opened date when sorting by it, otherwise the last change.
    private func meta(_ item: Item) -> String {
        let date = MapCardView.relative(sort == .opened ? item.opened : item.edited)
        switch item.kind {
        case .map(let map): return "\(L("\(map.nodeCount) nodes")) · \(date)"
        case .deck(let deck): return "\(L("\(deck.slides.count) slides")) · \(date)"
        case .chat(let chat): return "\(L("\(chat.visibleCount) messages")) · \(date)"
        }
    }

    // MARK: - Actions

    // A row can outlive its document (deleted on another device, left meanwhile): say so.
    private func open(_ item: Item) {
        searchFocused = false
        switch item.kind {
        case .map(let map):
            guard maps.map(map.id) != nil else { return notice = L("This map is no longer available.") }
            onOpenMap(map.id)
        case .deck(let deck):
            guard decks.deck(deck.id) != nil else { return notice = L("This presentation is no longer available.") }
            onOpenDeck(deck.id)
        case .chat(let chat):
            guard let current = chats.conversations.first(where: { $0.id == chat.id }) else { return notice = L("This chat is no longer available.") }
            onOpenChat(current)
        }
    }

    private func togglePin(_ item: Item) {
        Haptics.selection()
        withAnimation(.minorMenu) {
            switch item.kind {
            case .map(let map): maps.togglePin(map.id)
            case .deck(let deck): decks.togglePin(deck.id)
            case .chat(let chat): chats.togglePin(chat.id)
            }
        }
    }

    private func duplicate(_ item: Item) {
        withAnimation(.minorMenu) {
            switch item.kind {
            case .map(let map): _ = maps.duplicate(map.id)
            case .deck(let deck): decks.duplicate(deck.id)
            case .chat: break
            }
        }
    }

    private func rename() {
        guard let item = renaming else { return }
        renaming = nil
        switch item.kind {
        case .map(let map): maps.rename(map.id, to: renameText)
        case .deck(let deck): decks.rename(deck.id, to: renameText)
        case .chat(let chat): chats.rename(chat.id, to: renameText)
        }
    }

    private enum Confirm: Identifiable {
        case deleteMap(MindMap), leaveMap(MindMap), deleteDeck(Deck), deleteChat(Conversation)

        var id: UUID {
            switch self {
            case .deleteMap(let map), .leaveMap(let map): return map.id
            case .deleteDeck(let deck): return deck.id
            case .deleteChat(let chat): return chat.id
            }
        }

        var title: String {
            switch self {
            case .deleteMap(let map): return L("Delete “\(map.title)”? This can’t be undone.")
            case .leaveMap: return L("Leave this map?")
            case .deleteDeck(let deck): return L("Delete “\(deck.title)”?")
            case .deleteChat: return L("Delete this chat?")
            }
        }

        var message: String? {
            switch self {
            case .deleteMap(let map) where map.collab?.isOwner == true: return L("People on the map keep their own copy.")
            case .leaveMap: return L("You keep your own copy on this iPhone; changes from others stop coming in.")
            default: return nil
            }
        }

        var action: String {
            switch self {
            case .deleteMap: return L("Delete Map")
            case .leaveMap: return L("Leave Map")
            case .deleteDeck: return L("Delete Presentation")
            case .deleteChat: return L("Delete Chat")
            }
        }
    }

    private func perform(_ item: Confirm) {
        switch item {
        case .deleteMap(let map):
            withAnimation(.minorMenu) { maps.delete(map.id) }
        case .leaveMap(let map):
            Task {
                do {
                    try await CollabService.shared.leave(map.id)
                    Haptics.success()
                } catch {
                    notice = (error as? LocalizedError)?.errorDescription ?? L("Couldn’t do that. Try again.")
                }
            }
        case .deleteDeck(let deck):
            withAnimation(.minorMenu) {
                decks.delete(deck.id)
                recents.forget(deck.id)
            }
        case .deleteChat(let chat):
            withAnimation(.minorMenu) { chats.deleteConversation(chat.id) }
        }
    }

    // Entered from the assistant: the list comes in as one block, fading and rising 8 pt.
    private func fadeInIfNeeded() {
        guard state.fadePending else { return }
        state.fadePending = false
        guard !reduceMotion else { return }
        var quiet = Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet) { shown = false }
        withAnimation(.easeOut(duration: 0.22).delay(0.08)) { shown = true }
    }
}

private struct TitleBottom: PreferenceKey {
    static var defaultValue: CGFloat = 100
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// A map in the Library: its central idea with up to five branches in their colors, on a dotted
// tile (a sketch of the real map, not a picture of it).
struct LibraryMapThumbnail: View {
    let map: MindMap

    var body: some View {
        Canvas { context, size in
            let dot = GraphicsContext.Shading.color(.white.opacity(0.07))
            var y: CGFloat = 5
            while y < size.height {
                var x: CGFloat = 5
                while x < size.width {
                    context.fill(Path(ellipseIn: CGRect(x: x - 0.6, y: y - 0.6, width: 1.2, height: 1.2)), with: dot)
                    x += 8
                }
                y += 8
            }
            let branches = Array(map.root.children.prefix(5))
            let rightCount = (branches.count + 1) / 2
            let root = CGRect(x: size.width / 2 - 11, y: size.height / 2 - 6.5, width: 22, height: 13)
            func ys(_ count: Int) -> [CGFloat] {
                switch count {
                case 0: return []
                case 1: return [size.height / 2]
                case 2: return [size.height * 0.29, size.height * 0.71]
                default: return [size.height * 0.2, size.height / 2, size.height * 0.8]
                }
            }
            let right = ys(rightCount)
            let left = ys(branches.count - rightCount)
            for (i, node) in branches.enumerated() {
                let onRight = i < rightCount
                let level = onRight ? right[i] : left[i - rightCount]
                let color = (node.color ?? BranchColor.forBranch(at: i)).color
                let start = CGPoint(x: onRight ? root.maxX : root.minX, y: root.midY)
                let pill = CGRect(x: onRight ? size.width - 22 : 7, y: level - 4, width: 15, height: 8)
                let end = CGPoint(x: onRight ? pill.minX : pill.maxX, y: level)
                var path = Path()
                path.move(to: start)
                path.addCurve(to: end, control1: CGPoint(x: (start.x + end.x) / 2, y: start.y), control2: CGPoint(x: (start.x + end.x) / 2, y: end.y))
                context.stroke(path, with: .color(color), lineWidth: 1.5)
                let shape = Path(roundedRect: pill, cornerRadius: 3)
                context.fill(shape, with: .color(color.opacity(0.14)))
                context.stroke(shape, with: .color(color), lineWidth: 1.4)
            }
            let center = Path(roundedRect: root, cornerRadius: 4)
            context.fill(center, with: .color(Color.black.opacity(0.4)))
            context.stroke(center, with: .color(Color.white.opacity(0.75)), lineWidth: 1.5)
        }
        .frame(width: 88, height: 68)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.35)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .accessibilityHidden(true)
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
