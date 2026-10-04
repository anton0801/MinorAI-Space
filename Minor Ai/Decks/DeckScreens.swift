//
//  DeckScreens.swift
//  Minor Ai
//
//  New Presentation (from a map, a topic or a chat; length, audience and theme) and the list of
//  presentations in the sidebar.
//

import SwiftUI

struct NewDeckView: View {
    let theme: AppTheme
    var preselectedMap: UUID?
    var onCreated: (UUID) -> Void
    var onUpgrade: () -> Void

    enum SourceKind: String, CaseIterable, Identifiable { case map, topic, chat; var id: String { rawValue } }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var maps = MapStore.shared
    @ObservedObject private var account = AccountStore.shared
    @ObservedObject private var chats = ChatViewModel.shared
    @State private var kind: SourceKind = .map
    @State private var mapID: UUID?
    @State private var topic = ""
    @State private var chatID: UUID?
    @State private var audience = ""
    @State private var slides = 8
    @State private var deckTheme: DeckTheme = .midnight
    @State private var template: DeckTemplate?
    @ObservedObject private var saved = TemplateStore.shared
    @State private var working = false
    @State private var error: String?
    @State private var errorIsLimit = false

    private var maxSlides: Int {
        switch account.effectivePlan {
        case .free: return 8
        case .plus: return 20
        case .pro: return 30
        }
    }

    private var canCreate: Bool {
        switch kind {
        case .map: return mapID.flatMap { maps.map($0) } != nil
        case .topic: return !topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .chat: return chatID != nil
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        Picker("Source", selection: $kind) {
                            Text("From a Map").tag(SourceKind.map)
                            Text("Topic").tag(SourceKind.topic)
                            Text("From a Chat").tag(SourceKind.chat)
                        }
                        .pickerStyle(.segmented)

                        switch kind {
                        case .map: mapList
                        case .topic: topicField
                        case .chat: chatList
                        }

                        section("Audience and Goal") {
                            TextField("", text: $audience, axis: .vertical)
                                .placeholder(when: audience.isEmpty) { Text("For example: investors, 5 minutes").foregroundColor(theme.placeholderText) }
                                .lineLimit(1...3)
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 12).fill(theme.chatRectangle))
                        }

                        if let template {
                            section("Slides") {
                                Text(L("\(template.deck.slides.count) slides, as in the template"))
                                    .font(.system(size: 15))
                                    .foregroundColor(MinorColor.textSecondary)
                            }
                        } else {
                        section("Slides") {
                            HStack {
                                Text(L("\(slides) slides")).font(.system(size: 17, weight: .medium)).monospacedDigit()
                                Spacer()
                                Stepper("", value: $slides, in: 4...maxSlides).labelsHidden()
                            }
                            if account.effectivePlan == .free {
                                Text("Up to 8 slides on the free plan; Minor Plus makes up to 20.")
                                    .font(.system(size: 13))
                                    .foregroundColor(MinorColor.textTertiary)
                            }
                        }

                        }

                        section("Design") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(DeckTemplates.all + saved.templates) { item in
                                        Button {
                                            Haptics.selection()
                                            template = template?.id == item.id ? nil : item
                                        } label: {
                                            VStack(spacing: 6) {
                                                SlideCanvas(slide: item.deck.slides.first ?? Slide(layout: .cover, title: item.name), deck: item.deck)
                                                    .frame(width: 128)
                                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(template?.id == item.id ? MinorColor.accent : theme.chatStroke, lineWidth: template?.id == item.id ? 2 : 1))
                                                Label(item.name, systemImage: item.icon)
                                                    .font(.system(size: 12))
                                                    .foregroundColor(template?.id == item.id ? MinorColor.textPrimary : MinorColor.textSecondary)
                                                    .lineLimit(1)
                                            }
                                            .frame(width: 128)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel(L("Template: \(item.name)"))
                                        .accessibilityAddTraits(template?.id == item.id ? .isSelected : [])
                                    }
                                    Rectangle().fill(theme.chatStroke).frame(width: 1, height: 70)
                                    ForEach(DeckTheme.allCases) { choice in
                                        Button {
                                            Haptics.selection()
                                            deckTheme = choice
                                            template = nil
                                        } label: {
                                            VStack(spacing: 6) {
                                                SlideCanvas(slide: Slide(layout: .cover, title: previewTitle, subtitle: ""), deck: Deck(title: previewTitle, slides: [], theme: choice))
                                                    .frame(width: 128)
                                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(template == nil && deckTheme == choice ? MinorColor.accent : theme.chatStroke, lineWidth: template == nil && deckTheme == choice ? 2 : 1))
                                                Text(choice.name).font(.system(size: 12)).foregroundColor(template == nil && deckTheme == choice ? MinorColor.textPrimary : MinorColor.textSecondary)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel(choice.name)
                                        .accessibilityAddTraits(template == nil && deckTheme == choice ? .isSelected : [])
                                    }
                                }
                            }
                            if template != nil {
                                Button(action: useTemplateAsIs) {
                                    Label("Use the Template As Is", systemImage: "square.on.square")
                                        .font(.system(size: 14, weight: .medium))
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(MinorColor.accent)
                                .padding(.top, 4)
                            }
                        }

                        if let error {
                            HStack(spacing: 10) {
                                Text(error).font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading)
                                if errorIsLimit {
                                    Button(account.isPaid ? "Get PRO" : "Get Minor Plus") {
                                        dismiss()
                                        onUpgrade()
                                    }
                                    .font(.system(size: 13, weight: .semibold))
                                }
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(MinorColor.danger.opacity(0.25)))
                        }

                        Button(action: create) {
                            Label("Create Presentation", systemImage: "sparkles")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .background(Capsule().fill(MinorColor.accent))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canCreate || working)
                        .opacity(canCreate ? 1 : 0.4)
                    }
                    .padding(20)
                }
                .scrollDismissesKeyboard(.interactively)
                if working { WritingSlidesView(theme: deckTheme) }
            }
            .foregroundColor(MinorColor.textPrimary)
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("New Presentation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(MinorColor.textSecondary).disabled(working)
                }
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(working)
        .onAppear {
            slides = min(slides, maxSlides)
            if let preselectedMap, let map = maps.map(preselectedMap) {
                kind = .map
                mapID = preselectedMap
                deckTheme = DeckTheme.matching(map.mapPalette)
            } else if maps.maps.isEmpty {
                kind = .topic
            } else {
                mapID = maps.maps.first?.id
            }
        }
        .task { await account.refresh() }
    }

    private var previewTitle: String {
        switch kind {
        case .map: return mapID.flatMap { maps.map($0)?.title } ?? L("Presentation")
        case .topic: return topic.isEmpty ? L("Presentation") : topic
        case .chat: return chatID.flatMap { id in chats.conversations.first { $0.id == id }?.title } ?? L("Presentation")
        }
    }

    // MARK: - Sources

    private var mapList: some View {
        VStack(spacing: 8) {
            if maps.maps.isEmpty {
                Text("No maps yet. Pick Topic to start from a subject.")
                    .font(.system(size: 15))
                    .foregroundColor(MinorColor.textSecondary)
            }
            ForEach(maps.maps.prefix(20)) { map in
                Button { mapID = map.id } label: {
                    HStack(spacing: 12) {
                        Image(systemName: mapID == map.id ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(mapID == map.id ? MinorColor.accent : MinorColor.textTertiary)
                            .font(.system(size: 20))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(map.title).font(.system(size: 16, weight: .medium)).lineLimit(1)
                            Text(L("\(map.nodeCount) ideas")).font(.system(size: 12)).foregroundColor(MinorColor.textTertiary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 54)
                    .background(RoundedRectangle(cornerRadius: 12).fill(theme.chatRectangle))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(mapID == map.id ? MinorColor.accent.opacity(0.6) : theme.chatStroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(mapID == map.id ? .isSelected : [])
            }
        }
    }

    private var topicField: some View {
        HStack(spacing: 8) {
            TextField("", text: $topic, axis: .vertical)
                .placeholder(when: topic.isEmpty) { Text("What is the presentation about?").foregroundColor(theme.placeholderText) }
                .lineLimit(1...4)
                .font(.system(size: 17))
            DictationButton(text: $topic, stroke: theme.chatStroke)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(theme.chatRectangle))
    }

    private var chatList: some View {
        VStack(spacing: 8) {
            if chats.conversations.isEmpty {
                Text("No chats yet.")
                    .font(.system(size: 15))
                    .foregroundColor(MinorColor.textSecondary)
            }
            ForEach(chats.conversations.prefix(20)) { convo in
                Button { chatID = convo.id } label: {
                    HStack(spacing: 12) {
                        Image(systemName: chatID == convo.id ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(chatID == convo.id ? MinorColor.accent : MinorColor.textTertiary)
                            .font(.system(size: 20))
                        Text(convo.title).font(.system(size: 16, weight: .medium)).lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 50)
                    .background(RoundedRectangle(cornerRadius: 12).fill(theme.chatRectangle))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).textCase(.uppercase).font(.system(size: 13, weight: .medium)).foregroundColor(MinorColor.textTertiary)
            content()
        }
    }

    // MARK: - Create

    private func create() {
        guard AuthService.shared.isSignedIn else { return AuthGate.shared.require(create) }
        guard AIConsent.isGiven else {
            error = L("Allow AI in Settings → AI Data Sharing to create presentations.")
            errorIsLimit = false
            return
        }
        if account.isOverFreeDeckLimit {
            dismiss()
            return onUpgrade()
        }
        let source: DeckService.Source
        var mapSource: UUID?
        switch kind {
        case .map:
            guard let id = mapID, let map = maps.map(id) else { return }
            source = .map(map)
            mapSource = id
        case .topic:
            source = .topic(topic.trimmingCharacters(in: .whitespacesAndNewlines))
        case .chat:
            guard let convo = chats.conversations.first(where: { $0.id == chatID }) else { return }
            source = .text(convo.messages.filter { !$0.isHidden }.map { "\($0.role == .user ? "User" : "Assistant"): \($0.contentForModel)" }.joined(separator: "\n\n"))
        }
        working = true
        error = nil
        let count = slides
        let audience = audience
        let theme = deckTheme
        let template = template
        Task {
            defer { working = false }
            do {
                let generated = try await DeckService.shared.generate(source, slides: count, audience: audience, quality: AccountStore.shared.allowedMapModelID, layouts: template?.layouts)
                var deck = template?.fill(with: generated.slides, title: generated.title)
                    ?? Deck(title: generated.title, slides: generated.slides, theme: theme, sourceMapID: mapSource)
                deck.sourceMapID = mapSource
                DeckStore.shared.save(deck)
                account.noteDeckCreated()
                Haptics.success()
                dismiss()
                onCreated(deck.id)
            } catch {
                Haptics.error()
                if case BackendError.limitReached(let kind) = error { account.noteLimitReached(kind: kind) }
                errorIsLimit = (error as? BackendError)?.suggestsUpgrade ?? false
                self.error = (error as? LocalizedError)?.errorDescription ?? L("Something went wrong. Try again.")
            }
        }
    }
}

extension NewDeckView {
    // A template with its sample text, to fill in by hand (no AI, nothing counted).
    func useTemplateAsIs() {
        guard let template else { return }
        let deck = template.instantiate(title: previewTitle == L("Presentation") ? template.name : previewTitle)
        DeckStore.shared.save(deck)
        Haptics.success()
        dismiss()
        onCreated(deck.id)
    }
}

// While the AI writes: slides appear one by one in the chosen theme.
struct WritingSlidesView: View {
    let theme: DeckTheme
    @State private var shown = 0
    private let timer = Timer.publish(every: 0.7, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()
            VStack(spacing: 22) {
                ZStack {
                    ForEach(0..<3, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 12)
                            .fill(LinearGradient(colors: theme.background, startPoint: .topLeading, endPoint: .bottomTrailing))
                            .overlay(
                                VStack(alignment: .leading, spacing: 10) {
                                    Capsule().fill(theme.accent).frame(width: 40, height: 5)
                                    Capsule().fill(theme.text.opacity(0.8)).frame(width: 140, height: 12)
                                    Capsule().fill(theme.secondary.opacity(0.6)).frame(width: 100, height: 8)
                                }
                                .padding(18), alignment: .leading
                            )
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12)))
                            .frame(width: 240, height: 135)
                            .rotationEffect(.degrees(Double(i - 1) * 6))
                            .offset(x: CGFloat(i - 1) * 18, y: CGFloat(i - 1) * -6)
                            .opacity(shown % 4 > i ? 1 : 0.25)
                            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: shown)
                    }
                }
                .frame(height: 170)
                Text("Writing your slides…")
                    .font(.system(size: 17, weight: .semibold))
                Text("This takes about half a minute.")
                    .font(.system(size: 14))
                    .foregroundColor(MinorColor.textSecondary)
            }
        }
        .onReceive(timer) { _ in shown += 1 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Writing your slides")
    }
}

struct SidebarDecksView: View {
    var onOpen: (UUID) -> Void
    var onNew: () -> Void

    @ObservedObject private var store = DeckStore.shared
    @State private var pendingDelete: Deck?

    var body: some View {
        VStack(spacing: 0) {
            if store.decks.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "rectangle.on.rectangle.angled").font(.system(size: 44))
                    Text("No Presentations Yet").font(.system(size: 18, weight: .bold))
                    Text("Make one from a map, a topic or a chat in about half a minute.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(MinorColor.textSecondary)
                        .multilineTextAlignment(.center)
                    Button(action: onNew) {
                        Label("New Presentation", systemImage: "sparkles")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 20)
                            .frame(height: 46)
                            .background(Capsule().fill(MinorColor.accent))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                }
                .padding(.horizontal, 36)
                Spacer()
            } else {
                List {
                    ForEach(store.decks) { deck in
                        Button { onOpen(deck.id) } label: {
                            HStack(spacing: 12) {
                                if let first = deck.slides.first {
                                    SlideCanvas(slide: first, deck: deck)
                                        .frame(width: 96)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(deck.title).font(.system(size: 16, weight: .medium)).lineLimit(2)
                                    Text(L("\(deck.slides.count) slides · \(deck.updatedAt.formatted(.relative(presentation: .named).locale(AppLanguage.current.locale)))"))
                                        .font(.system(size: 12))
                                        .foregroundColor(MinorColor.textTertiary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
                            .contentShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { pendingDelete = deck } label: { Label("Delete", systemImage: "trash") }
                        }
                        .accessibilityAction(named: "Delete") { pendingDelete = deck }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .foregroundColor(MinorColor.textPrimary)
        .confirmationDialog(
            pendingDelete.map { L("Delete “\($0.title)”?") } ?? "",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { deck in
            Button("Delete Presentation", role: .destructive) { store.delete(deck.id) }
            Button("Cancel", role: .cancel) {}
        }
    }
}
