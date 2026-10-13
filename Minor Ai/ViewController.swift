//
//  ViewController.swift
//  Minor Ai
//
//  Created by Stefano  on 2/3/25.
//

import PhotosUI
import SwiftUI

// Представление для UIVisualEffectView
struct BlurView: UIViewRepresentable {
    let style: UIBlurEffect.Style
    
    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: style))
        return view
    }
    
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: style)
    }
}

struct ContentView: View {
    @State private var askText: String = "" // Текст для "Ask me anything"
    @State private var homeMentions: [MapMention] = []   // maps attached with @
    @State private var pendingShare: SharedItem?          // a page or text shared from another app
    @State private var homeDictating = false
    @State private var homeVoice = false
    // An invite link that was opened: the invitation shows before anyone joins.
    @State private var pendingInvite: InviteLink?
    @State private var joinedMapID: UUID?

    struct InviteLink: Identifiable {
        let token: String
        var id: String { token }
    }
    @State private var openDeckID: UUID?
    @State private var newDeck: NewDeckRequest?

    struct NewDeckRequest: Identifiable {
        let id = UUID()
        let mapID: UUID?
        var template: String? = nil
    }
    #if DEBUG
    @State private var slideGallery = false
    #endif
    @Environment(\.scenePhase) private var scenePhase
    @State private var homeImages: [Data] = []
    @State private var homeFile: Attachments.Document?
    @State private var homePhotoItems: [PhotosPickerItem] = []
    @State private var showHomePhotos = false
    @State private var homeError: String?
    @State private var homeImageMode = false
    @ObservedObject private var gate = AuthGate.shared
    @State private var showConsent = false
    @State private var afterConsent: (() -> Void)?
    @State private var generatingJobID: UUID?
    @ObservedObject private var generation = GenerationCenter.shared
    @ObservedObject private var account = AccountStore.shared
    @State private var openMapID: UUID?
    @State private var openMapTab: ProjectTab = .map   // the tab a project opens on
    // The menu over the assistant and the place open in it. Opened from the assistant's "Create
    // a Map", Back from New Map returns straight to the assistant.
    @State private var menuOpen = false
    @State private var menuPath: [MenuDestination] = []
    @State private var menuFromAssistant = false
    // The Library comes in from the side when opened from the assistant's (or a chat's) top
    // button; the menu itself rises from the bottom.
    @State private var menuEntry: MenuEntry = .rise
    @State private var libraryOpener: LibraryOpener = .assistant
    @State private var menuDrag: CGFloat = 0
    @State private var containerHeight: CGFloat = 900
    @State private var containerWidth: CGFloat = 393
    @AccessibilityFocusState private var menuButtonFocused: Bool
    @AccessibilityFocusState private var libraryButtonFocused: Bool
    @FocusState private var homeFieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverOn
    @ObservedObject private var splash = LaunchSplash.shared
    @State private var greetingShown = false
    @State private var templateError: String?
    @State private var isBlurActive: Bool = false
    @State private var showSettings = false
    @State private var showUsage = false
    @State private var inviteSheet: InviteSheet?
    @State private var paywallTier: SubscriptionStore.Tier = .plus
    @AppStorage("didOnboard") private var didOnboard = false
    // The onboarding cover has its own state that body reads, rather than a Binding(get:set:)
    // over the @AppStorage that body never read.
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "didOnboard")
    // Phones with a Home button (iPhone SE) have no bottom inset for the Menu button to sit in.
    @State private var hasHomeIndicator = true
    // A link that arrived during onboarding, opened once it is done.
    @State private var pendingLink: URL?
    @State private var mainScreenOffsetY: CGFloat = 0
    @State private var selectedSphere: Int? = UserDefaults.standard.integer(forKey: "SelectedSphere") != 0 ? UserDefaults.standard.integer(forKey: "SelectedSphere") : nil
    @State private var selectedModel: AIModelOption = AIModelCatalog.default
    @ObservedObject private var chatVM = ChatViewModel.shared
    @ObservedObject private var subscriptions = SubscriptionStore.shared
    @ObservedObject private var recents = RecentDocuments.shared

    private var theme: AppTheme { AppTheme(sphere: selectedSphere) }

    // Цвета берутся из общего AppTheme (см. AppTheme.swift), чтобы ChatView и
    // ContentView использовали единую палитру по выбранной сфере.
    private var backgroundColor: Color { theme.background }
    private var chatRectangleColor: Color { theme.chatRectangle }
    private var chatStrokeColor: Color { theme.chatStroke }
    private var placeholderTextColor: Color { theme.placeholderText }
    private var minorPlusRectangleColor: Color { theme.minorPlusRectangle }
    private var minorPlusStrokeColor: Color { theme.minorPlusStroke }
    private var blurColor: Color { theme.blur }
    
    // Everything on screen, bottom to top; the modifiers in body add sheets and routing.
    private var layers: some View {
        ZStack {
            backgroundColor // Динамический фон приложения
                .ignoresSafeArea()

            // The bottom inset and the screen height come from the layout (a reader inside the safe
            // area sees them; the keyboard doesn't count). Read from the window, as before, it froze
            // this screen on iOS 26: no state change redrew it after the first frame, so "Not Now"
            // and signing in couldn't close onboarding (App Review, 2.0 (2)).
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        hasHomeIndicator = geo.safeAreaInsets.bottom > 0
                        containerHeight = geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom
                        containerWidth = geo.size.width + geo.safeAreaInsets.leading + geo.safeAreaInsets.trailing
                    }
                    .onChange(of: geo.safeAreaInsets.bottom) { hasHomeIndicator = $0 > 0 }
                    .onChange(of: geo.size.height) { containerHeight = $0 + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom }
                    .onChange(of: geo.size.width) { containerWidth = $0 + geo.safeAreaInsets.leading + geo.safeAreaInsets.trailing }
            }
            .ignoresSafeArea(.keyboard)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            assistantLayer

            // Paywall поверх всего, включая редактор карты
            if isBlurActive {
                PaywallView(tier: paywallTier, onClose: closePaywall)
                    .transition(.opacity)
                    .zIndex(20)
            }

            
            // Экран диалога поверх лаунчера, когда есть сообщения
            if !chatVM.messages.isEmpty {
                ChatView(
                    viewModel: chatVM,
                    theme: theme,
                    model: $selectedModel,
                    onLibrary: { openLibrary(.chats, from: .chat) },
                    onMapThis: { answer in
                        let title = Conversation.makeTitle(from: chatVM.messages)
                        withConsent { chatVM.makeMap(from: answer, title: title) }
                    },
                    onUpgrade: { openPaywall(from: "chat") },
                    onLockedModel: { model in openPaywall(pro: model.chatPlan == .pro, from: "chat_model") }
                )
                .transition(.move(edge: .bottom))
                .modifier(TopLayer(isTop: topLayer == .chat))
                .zIndex(10)
            }

            menuLayer

            // Построение карты, затем редактор
            if let jobID = generatingJobID {
                GeneratingView(
                    jobID: jobID,
                    theme: theme,
                    onDone: { id in
                        openMapID = id
                        generatingJobID = nil
                        leaveNewMap()
                    },
                    onClose: { generatingJobID = nil },
                    onUpgrade: { openPaywall(from: "generating") }
                )
                .id(jobID)
                .transition(.move(edge: .bottom))
                .modifier(TopLayer(isTop: topLayer == .building))
                .zIndex(11)
            }

            // A map that finished building in the background
            if let readyID = generation.ready, let map = MapStore.shared.map(readyID) {
                VStack {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles").foregroundColor(theme.glowSolid)
                        Text("“\(map.title)” is ready")
                            .font(.system(size: 15))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Button("Open") {
                            generation.ready = nil
                            generatingJobID = nil
                            openMapID = readyID
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .background(Capsule().fill(theme.chatRectangle))
                    .overlay(Capsule().stroke(theme.chatStroke, lineWidth: 1))
                    .padding(.horizontal, 16)
                    .onTapGesture { generation.ready = nil }
                    Spacer()
                }
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(15)
                .task(id: readyID) {
                    try? await Task.sleep(nanoseconds: 6_000_000_000)
                    if generation.ready == readyID { generation.ready = nil }
                }
            }

            if let id = openMapID {
                // A map opens as a project: Map, Slides and Chat over the same document.
                ProjectView(
                    mapID: id,
                    theme: theme,
                    initialTab: openMapTab,
                    onClose: {
                        openMapID = nil
                        openMapTab = .map
                    },
                    onUpgrade: { pro in openPaywall(pro: pro, from: "map_editor") }
                )
                .id(id)
                .transition(.move(edge: .bottom))
                .modifier(TopLayer(isTop: topLayer == .map))
                .zIndex(12)
            }

            if let id = openDeckID {
                DeckEditorView(
                    deckID: id,
                    theme: theme,
                    onClose: { openDeckID = nil },
                    onOpenMap: { map in
                        openDeckID = nil
                        openMapID = map
                    },
                    onUpgrade: { pro in openPaywall(pro: pro, from: "deck_editor") }
                )
                .id(id)
                .transition(.move(edge: .bottom))
                .modifier(TopLayer(isTop: topLayer == .deck))
                .zIndex(13)
            }
        }
    }

    var body: some View {
        layers
        .animation(.easeInOut(duration: 0.3), value: chatVM.messages.isEmpty)
        .animation(.easeInOut(duration: 0.3), value: openMapID)
        .animation(.easeInOut(duration: 0.3), value: openDeckID)
        .animation(.easeInOut(duration: 0.3), value: generatingJobID)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: generation.ready)
        .photosPicker(isPresented: $showHomePhotos, selection: $homePhotoItems, maxSelectionCount: 4, matching: .images)
        .onChange(of: homePhotoItems) { items in
            guard !items.isEmpty else { return }
            Task {
                var loaded: [Data] = []
                for item in items {
                    // Shrunk off the main thread, so a big photo doesn't freeze the screen.
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let prepared = await Task.detached(priority: .userInitiated, operation: { Attachments.preparedImage(from: data) }).value {
                        loaded.append(prepared)
                    }
                }
                homeImages = Array((homeImages + loaded).prefix(4))
                homePhotoItems = []
            }
        }
        .onAppear {
            if let id = generation.openRequest { openRequested(id) }
            // The screen was rebuilt for a new language while Settings was open.
            if LanguageSettings.shared.reopenSettings {
                LanguageSettings.shared.reopenSettings = false
                showSettings = true
            }
        }
        // A plan that ended (or invitation days that ran out) no longer includes a stronger chat model.
        .onChange(of: account.effectivePlan) { _ in
            if !account.allowsChat(with: selectedModel) { selectedModel = AIModelCatalog.default }
        }
        .onChange(of: openMapID) { id in
            if let id { RecentDocuments.shared.opened(.map, id) }
        }
        // Back from the Library to the menu: its search starts empty next time.
        .onChange(of: menuPath) { path in
            if !path.contains(.library) { LibraryState.shared.query = "" }
        }
        .onChange(of: openDeckID) { id in
            if let id { RecentDocuments.shared.opened(.deck, id) }
        }
        .onChange(of: generation.openRequest) { id in
            if let id { openRequested(id) }
        }
        #if DEBUG
        .fullScreenCover(isPresented: $slideGallery) { SlideGallery() }
        #endif
        .sheet(item: $newDeck) { request in
            NewDeckView(theme: theme, preselectedMap: request.mapID, preselectedTemplate: request.template, onCreated: { id in
                openDeckID = id
            }, onUpgrade: { openPaywall(from: "new_deck") })
        }
        .onChange(of: generation.routeRequest) { url in
            guard let url else { return }
            generation.routeRequest = nil
            openLink(url)
        }
        .onChange(of: chatVM.openDeckRequest) { id in
            guard let id else { return }
            chatVM.openDeckRequest = nil
            openDeckID = id
        }
        .onOpenURL { url in openLink(url) }
        .onChange(of: scenePhase) { phase in
            if phase == .active { checkSharedItems() }
        }
        .sheet(item: $pendingShare) { item in
            SharedItemSheet(item: item, theme: theme, onBuild: {
                pendingShare = nil
                item.remove()
                withConsent { generatingJobID = GenerationCenter.shared.start(SharedItemSheet.input(for: item)) }
            }, onDiscard: {
                pendingShare = nil
                item.remove()
            })
        }
        // A stopped or failed map's input goes back to New Map's field, opened if needed.
        .onChange(of: generation.returnedInput == nil) { empty in
            guard !empty, !(menuOpen && menuPath.last == .newMap) else { return }
            openMenu(to: .newMap)
        }
        .onChange(of: generation.topicRequest) { topic in
            // Siri or Shortcuts asked for a map about a topic.
            guard let topic else { return }
            generation.topicRequest = nil
            if isBlurActive { closePaywall() }
            closeOverlays()
            openMapID = nil
            chatVM.endSession()
            withConsent { generatingJobID = GenerationCenter.shared.start(.topic(topic)) }
        }
        .onChange(of: chatVM.openMapRequest) { id in
            // The assistant opened a map, or the person tapped Open on a card.
            guard let id else { return }
            chatVM.openMapRequest = nil
            openMapID = id
        }
        .onChange(of: chatVM.slidesRequest) { id in
            // "Make Slides from Map" on the chat's map card: the project opens on Slides, which
            // waits for the person to choose how to make them.
            guard let id else { return }
            chatVM.slidesRequest = nil
            openMapTab = .slides
            openMapID = id
        }
        .onChange(of: chatVM.mapRequest) { request in
            // The person asked the chat for a mind map.
            guard let request else { return }
            chatVM.mapRequest = nil
            withConsent { generatingJobID = GenerationCenter.shared.start(request.input) }
        }
        .onChange(of: chatVM.restoredDraft?.id) { _ in
            // Consent was declined: the message and attachments go back into the home field.
            guard chatVM.messages.isEmpty, let draft = chatVM.restoredDraft else { return }
            askText = draft.text
            homeImages = draft.images
            homeFile = draft.file
            chatVM.restoredDraft = nil
        }
        .onChange(of: selectedSphere) { sphere in
            UserDefaults.standard.set(sphere ?? 0, forKey: "SelectedSphere")
        }
        .task {
            await AccountStore.shared.refresh()
        }
        // Originals left by an interrupted import or a removed material.
        .task { ProjectMaterialStore.shared.cleanOriginals() }
        #if DEBUG
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-demoMap") {
                // -demoProjectSlides: the project opens on its (empty) Slides tab.
                if args.contains("-demoProjectSlides") { openMapTab = .slides }
                openMapID = DemoMap.install().id
            }
            // A shared map this person can only view (-demoViewer, with -demoSelect or -demoCard).
            if args.contains("-demoViewer") {
                var map = DemoMap.install()
                map.collab = CollabInfo(isOwner: false, version: 1, role: .viewer)
                MapStore.shared.save(map)
                openMapID = map.id
            }
            // The home field with "@" typed: the list of maps to attach (-demoMention).
            if args.contains("-demoMention") {
                _ = DemoMap.install()
                askText = "@"
            }
            // A chat whose last message got no answer (-demoFailed): the reason and Retry under it.
            if args.contains("-demoFailed") {
                var failed = ChatMessage(role: .user, text: "Make a study plan for my exam")
                failed.failed = BackendError.offline.errorDescription
                chatVM.messages = [
                    ChatMessage(role: .user, text: "Hi!"),
                    ChatMessage(role: .assistant, text: "Hi! What are we working on today?"),
                    failed,
                ]
            }
            if args.contains("-mindMode") { _ = DemoMap.install(); openMenu(to: .newMap) }
            if args.contains("-menu") { _ = DemoMap.install(); openMenu() }
            if args.contains("-settings") { showSettings = true }
            if args.contains("-demoToday") { _ = DemoMap.install(); openMenu(to: .today) }
            if args.contains("-demoTemplates") { openMenu(to: .templates(args.contains("-decks") ? .decks : .maps)) }
            if args.contains("-demoResume") { RecentDocuments.shared.opened(.map, DemoMap.install().id) }
            // -noResume: the plain assistant (Create a Map · Make Slides), whatever was opened before.
            if args.contains("-noResume") { RecentDocuments.shared.clear() }
            // The Library from Menu (-demoLibrary) or from the assistant's top button (-sidebarMaps,
            // -sidebarDecks, -libraryChats); -demoManyMaps adds 120 maps for this run only.
            // The sample map and presentation, nothing opened (-demoInstall).
            if args.contains("-demoInstall") { _ = DemoMap.install(); DeckStore.shared.save(DemoMap.deck()) }
            if args.contains("-demoManyMaps") { MapStore.shared.addForScreenshots(DemoMap.many(120)) }
            if args.contains("-demoLibrary") { _ = DemoMap.install(); DeckStore.shared.save(DemoMap.deck()); LibraryState.shared.tab = .maps; openMenu(to: .library) }
            if args.contains("-sidebarMaps") { _ = DemoMap.install(); openLibrary(.maps) }
            if args.contains("-libraryChats") { chatVM.installDemoConversations(); openLibrary(.chats) }
            if args.contains("-onboarding") { didOnboard = false; showOnboarding = true }
            if args.contains("-sidebarDecks") { DeckStore.shared.save(DemoMap.deck()); openLibrary(.decks) }
            if args.contains("-demoChat") { chatVM.messages = DemoMap.chat }
            // A conversation that made a map: the card with Open Map and Make Slides (-demoChatMap).
            if args.contains("-demoChatMap") {
                let map = DemoMap.install()
                chatVM.messages = [
                    ChatMessage(role: .user, text: L("I want to launch an app. Help me plan it.")),
                    ChatMessage(role: .assistant, text: L("Let’s start with the audience, pricing and channels. I put the plan on a map."),
                                action: ChatAction(kind: .mapCreated, mapID: map.id, mapTitle: map.title)),
                ]
            }
            if args.contains("-demoSlides") { slideGallery = true }
            if args.contains("-demoDeck") || args.contains("-demoExport") || args.contains("-demoPresentDeck") {
                var deck = DemoMap.deck()
                // -demoHiddenSlide: the fifth slide hidden (export and presenting skip it).
                if args.contains("-demoHiddenSlide"), deck.slides.count > 4 { deck.slides[4].isHidden = true }
                DeckStore.shared.save(deck)
                openDeckID = deck.id
                if args.contains("-demoExport") {
                    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    if let pdf = try? DeckExport.pdf(deck) { try? FileManager.default.copyItem(at: pdf, to: documents.appendingPathComponent("demo.pdf")) }
                    if let pptx = try? DeckExport.pptx(deck) { try? FileManager.default.copyItem(at: pptx, to: documents.appendingPathComponent("demo.pptx")) }
                }
            }
            // Every kind of diagram, from slide N (-demoDiagrams N).
            if let i = args.firstIndex(of: "-demoDiagrams") {
                let deck = DemoMap.diagramDeck()
                DeckStore.shared.save(deck)
                if args.indices.contains(i + 1), let slide = Int(args[i + 1]) { UserDefaults.standard.set(slide, forKey: "demoDeckSlide") }
                openDeckID = deck.id
                // -demoDiagramsExport: each diagram slide on its own, as PDF and PowerPoint, in Documents.
                if args.contains("-demoDiagramsExport") {
                    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    for (n, slide) in deck.slides.enumerated() {
                        var single = deck
                        single.slides = [slide]
                        for ext in ["pdf", "pptx"] { try? FileManager.default.removeItem(at: documents.appendingPathComponent("diagram-\(n).\(ext)")) }
                        if let pdf = try? DeckExport.pdf(single) { try? FileManager.default.copyItem(at: pdf, to: documents.appendingPathComponent("diagram-\(n).pdf")) }
                        if let pptx = try? DeckExport.pptx(single) { try? FileManager.default.copyItem(at: pptx, to: documents.appendingPathComponent("diagram-\(n).pptx")) }
                    }
                }
            }
            if args.contains("-demoMerge") { openDeckID = DemoMap.installMergeDemo().id }
            if args.contains("-demoDesign") {
                let deck = DemoMap.designedDeck()
                DeckStore.shared.save(deck)
                openDeckID = deck.id
                if args.contains("-demoDesignExport") {
                    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    for name in ["design.pdf", "design.pptx"] { try? FileManager.default.removeItem(at: documents.appendingPathComponent(name)) }
                    if let pdf = try? DeckExport.pdf(deck) { try? FileManager.default.copyItem(at: pdf, to: documents.appendingPathComponent("design.pdf")) }
                    if let pptx = try? DeckExport.pptx(deck) { try? FileManager.default.copyItem(at: pptx, to: documents.appendingPathComponent("design.pptx")) }
                }
            }
            if args.contains("-demoNewDeck") { _ = DemoMap.install(); newDeck = NewDeckRequest(mapID: nil) }
            if args.contains("-demoAgent") {
                let map = DemoMap.install()
                chatVM.messages = DemoMap.agentChat(map)
            }
            // Creating the Map at its third stage (-demoCreating, -demoStopAsk asks to stop) or failed
            // offline (-demoCreateFailed), from New Map.
            if args.contains("-demoCreating") || args.contains("-demoCreateFailed") {
                _ = DemoMap.install()
                openMenu(to: .newMap)
                let topic = AppLanguage.current.resolved == .russian ? "План запуска подкаста: подготовка, запись и продвижение" : "Podcast launch plan: preparation, recording and promotion"
                generatingJobID = GenerationCenter.shared.installDemoJob(.topic(topic), step: 2, error: args.contains("-demoCreateFailed") ? .offline : nil)
            }
            if args.contains("-demoBuilding") {
                _ = DemoMap.install()
                _ = GenerationCenter.shared.start(.topic("Photosynthesis"))
                openLibrary(.maps)
            }
            if args.contains("-demoPaywall") { openPaywall(pro: args.contains("-paywallPro"), from: "debug") }
            if args.contains("-demoUsage") {
                AccountStore.shared.installDemo()
                InviteService.shared.installDemo()
                showUsage = true
            }
            if args.contains("-demoInvite") {
                AccountStore.shared.installDemo()
                InviteService.shared.installDemo()
                inviteSheet = InviteSheet(code: nil)
            }
            if args.contains("-demoSignIn") { AuthGate.shared.require {} }
            if args.contains("-demoJoin") { pendingInvite = InviteLink(token: "demo-invite-token-0000") }
        }
        #endif
        // A voice conversation from the start screen; "Go to Chat" leaves it in the chat.
        .fullScreenCover(isPresented: $homeVoice) {
            VoiceModeView(viewModel: chatVM, model: selectedModel, theme: theme) { homeVoice = false }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(
                selectedSphere: $selectedSphere,
                onUpgrade: { pro in
                    showSettings = false
                    openPaywall(pro: pro, from: "settings")
                },
                onDataDeleted: {
                    chatVM.deleteAll()
                    openMapID = nil
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showUsage) {
            UsageView(onUpgrade: { pro in
                showUsage = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { openPaywall(pro: pro, from: "limits") }
            })
        }
        .sheet(item: $inviteSheet) { request in InviteView(initialCode: request.code) }
        // The invitation to a shared map; the map opens once the sheet has closed.
        .sheet(item: $pendingInvite, onDismiss: {
            guard let id = joinedMapID else { return }
            joinedMapID = nil
            if isBlurActive { closePaywall() }
            chatVM.endSession()
            openMapID = id
        }) { invite in
            JoinInviteView(token: invite.token, theme: theme, onJoined: { id in
                joinedMapID = id
                pendingInvite = nil
            }, onClose: { pendingInvite = nil })
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $gate.isPresented, onDismiss: { gate.finish() }) {
            SignInView(onFinish: { gate.close() })
        }
        .sheet(isPresented: $showConsent, onDismiss: { afterConsent = nil }) {
            AIConsentView(
                onAllow: {
                    showConsent = false
                    let action = afterConsent
                    afterConsent = nil
                    action?()
                },
                onDecline: {
                    showConsent = false
                    afterConsent = nil
                }
            )
        }
        .sheet(isPresented: Binding(get: { chatVM.needsConsent }, set: { if !$0 { chatVM.cancelPendingSend() } })) {
            AIConsentView(onAllow: { chatVM.resumeAfterConsent() }, onDecline: { chatVM.cancelPendingSend() })
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(onFinish: {
                Telemetry.log("onboarding_complete", ["method": AuthService.shared.isSignedIn ? "signed_in" : "not_now"])
                didOnboard = true
                showOnboarding = false
                if let url = pendingLink {
                    pendingLink = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { openLink(url) }
                }
            })
        }
        .alert("Couldn’t create the map", isPresented: Binding(get: { templateError != nil }, set: { if !$0 { templateError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(templateError ?? "")
        }
    }

    // The assistant: steps back a little and fades while the menu rises over it; moves
    // a little aside while the Library slides in over it.
    private var assistantLayer: some View {
        assistant
            .scaleEffect(menuOpen && menuEntry == .rise && !reduceMotion ? 0.97 : 1)
            .offset(y: menuOpen && menuEntry == .rise && !reduceMotion ? -16 : 0)
            .opacity(menuOpen && menuEntry == .rise ? 0 : 1)
            .animation(reduceMotion ? .easeInOut(duration: 0.14) : .easeOut(duration: menuOpen ? 0.18 : 0.23), value: menuOpen)
            .offset(x: menuOpen && menuEntry == .slide && !reduceMotion ? (menuDrag - containerWidth) * 0.3 : 0)
            .offset(y: mainScreenOffsetY)
            .animation(.spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0.2), value: mainScreenOffsetY)
            .allowsHitTesting(!menuOpen)
            .accessibilityHidden(topLayer != .home)
    }

    // The menu: rises from the bottom (a crossfade with Reduce Motion) and stays in place
    // when closed, so its stack and scroll position survive. The Library opened from the
    // top button comes in from the side instead, over a chat too, and follows the finger
    // back from the left edge.
    private var menuLayer: some View {
        menu
            .offset(x: menuEntry == .slide && !reduceMotion ? (menuOpen ? menuDrag : containerWidth) : 0,
                    y: menuEntry == .rise && !menuOpen && !reduceMotion ? containerHeight + 40 : 0)
            .opacity(reduceMotion ? (menuOpen ? 1 : 0) : 1)
            .allowsHitTesting(menuOpen)
            .simultaneousGesture(libraryBackGesture)
            .accessibilityHidden(topLayer != .menu)
            .accessibilityAddTraits(topLayer == .menu && voiceOverOn ? .isModal : [])
            .accessibilityAction(.escape) {
                if menuPath.isEmpty || (menuFromAssistant && menuPath.count == 1) { closeMenu() }
            }
            .zIndex(10.5)
    }

    // MARK: - Assistant

    private var assistant: some View {
        ZStack(alignment: .top) {
            // A tap on empty space puts the keyboard away. It sits under everything else, so it
            // only gets taps that no button takes (a gesture over the whole screen used to win
            // over buttons in lists).
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { homeFieldFocused = false }
                .accessibilityHidden(true)

            // The theme's glow along the bottom edge.
            VStack {
                Spacer()
                Rectangle()
                    .fill(blurColor)
                    .frame(height: 120)
                    .blur(radius: 50)
                    .opacity(0.5)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            // The logo exactly where the splash lands (screen height / 2.5 below the safe area),
            // and the invitation under it. The keyboard doesn't move them.
            GeometryReader { geo in
                let fullHeight = geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom
                VStack(spacing: 18) {
                    Image("logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 110, height: 110)
                        .opacity(0.92)
                        .accessibilityHidden(true)
                    greeting
                }
                .frame(maxWidth: .infinity)
                .padding(.top, max(0, fullHeight / 2.5 - 55))
                .padding(.horizontal, 24)
            }
            .ignoresSafeArea(.keyboard)
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                GeometryReader { geo in topBar(width: geo.size.width) }
                    .frame(height: 52)
                Spacer(minLength: 0)
                bottomStack
            }
        }
        .onAppear { if splash.revealed { greetingShown = true } }
        .onChange(of: splash.revealed) { revealed in
            guard revealed else { return }
            // After the portal has opened, so the words don't compete with the splash.
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: 0.4).delay(0.55)) { greetingShown = true }
        }
    }

    private var greeting: some View {
        VStack(spacing: 6) {
            Text("What shall we think about?")
                .minorFont(22, .semibold, style: .title2, maxScale: 1.3)
            Text("Type or start talking.")
                .minorFont(15, style: .subheadline, maxScale: 1.3)
                .foregroundColor(MinorColor.textSecondary)
        }
        .multilineTextAlignment(.center)
        .opacity(greetingShown ? 1 : 0)
        .offset(y: greetingShown || reduceMotion ? 0 : 6)
        .accessibilityElement(children: .combine)
        .accessibilityHidden(!greetingShown)
    }

    // Library on the left, Get Plus (or the name for subscribers) in the middle, the model on the right.
    private func topBar(width: CGFloat) -> some View {
        let side = max(84, (width - 146) / 2 - 12)
        return ZStack {
            if account.isPaid {
                Text(verbatim: "Minor AI")
                    .minorFont(17, .semibold, maxScale: 1.2)
                    .accessibilityAddTraits(.isHeader)
            } else {
                Button(action: { openPaywall(from: "get_plus_button") }) {
                    // "Get Plus", not the plan's name: free users read "Minor Plus" as their plan.
                    // In the title's place, as the title is for subscribers.
                    HStack(spacing: 5) {
                        Image(systemName: "sparkle").font(.system(size: 12, weight: .semibold)).foregroundColor(MinorColor.accent)
                        Text("Get Plus")
                            .minorFont(17, .semibold, maxScale: 1.2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .frame(height: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("Get Minor Plus")
            }
            HStack(spacing: 0) {
                Button { openLibrary() } label: {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Library")
                .accessibilityFocused($libraryButtonFocused)
                Spacer(minLength: 8)
                modelPicker
                    .frame(maxWidth: side, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
    }

    // Light models for every plan; a stronger one shows the plan that opens it. The number says how
    // much faster a model uses the monthly AI allowance than the lightest one.
    private var modelPicker: some View {
        Menu {
            ForEach(AIModelCatalog.all) { model in
                Button {
                    if account.allowsChat(with: model) {
                        selectedModel = model
                    } else {
                        openPaywall(pro: model.chatPlan == .pro, from: "chat_model")
                    }
                } label: {
                    if model == selectedModel {
                        Label(model.displayName, systemImage: "checkmark")
                    } else if !account.allowsChat(with: model) {
                        Label("\(model.displayName) · \(model.chatPlan == .pro ? "PRO" : "Plus")", systemImage: "lock.fill")
                    } else {
                        Text("\(model.displayName)  ×\(model.usage)")
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text("Model")
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Capsule().fill(chatRectangleColor))
            .overlay(Capsule().stroke(chatStrokeColor, lineWidth: 1))
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("AI model: \(selectedModel.displayName)")
        .accessibilityHint(Text("Light models are free; stronger ones come with Minor Plus or PRO."))
    }

    private var bottomStack: some View {
        VStack(spacing: 0) {
            // "@" lists the person's maps right above the card, never over the field being typed in.
            if !homeMentionMatches.isEmpty {
                MentionSuggestions(maps: homeMentionMatches, theme: theme) { map in
                    askText = Mentions.insert(map, into: askText)
                    if !homeMentions.contains(where: { $0.id == map.id }) { homeMentions.append(MapMention(id: map.id, title: map.title)) }
                    Haptics.selection()
                }
                .padding(.horizontal, -16)
                .padding(.bottom, 6)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            if homeAccessoryShown {
                homeAccessory
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 10)
            } else if homeMentionMatches.isEmpty {
                if let resume = resumeEntry {
                    resumeRow(resume.entry, title: resume.title).padding(.bottom, 10)
                } else {
                    quickActions.padding(.bottom, 8)
                }
            }
            composer
            if !homeFieldFocused {
                menuButton
                    .padding(.top, 12)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, hasHomeIndicator ? 2 : 12)
        .animation(.easeOut(duration: 0.18), value: homeFieldFocused)
    }

    // The project last opened here (within two weeks), to go back to in one tap.
    private var resumeEntry: (entry: RecentDocuments.Entry, title: String)? {
        let since = Date(timeIntervalSinceNow: -14 * 86_400)
        for entry in recents.entries.prefix(6) where entry.openedAt > since {
            if entry.kind == .map, let map = MapStore.shared.map(entry.id) { return (entry, map.title) }
            if entry.kind == .deck, let deck = DeckStore.shared.deck(entry.id) { return (entry, deck.title) }
        }
        return nil
    }

    private func resumeRow(_ entry: RecentDocuments.Entry, title: String) -> some View {
        Button {
            if entry.kind == .map { openMapID = entry.id } else { openDeckID = entry.id }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: entry.kind == .map ? "point.3.connected.trianglepath.dotted" : "rectangle.on.rectangle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(MinorColor.accent)
                    .frame(width: 26)
                Text(L("Continue: \(title)"))
                    .minorFont(15, .medium, maxScale: 1.3)
                    .foregroundColor(.white)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MinorColor.textTertiary)
            }
            .padding(.horizontal, 4)
            .frame(minHeight: 54)
            .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // Quiet starts for the two main results, so nobody has to guess the right words.
    private var quickActions: some View {
        HStack(spacing: 6) {
            Button { openMenu(to: .newMap, fromAssistant: true) } label: {
                Text("Create a Map").frame(minHeight: 44).contentShape(Rectangle())
            }
            Text(verbatim: "·").accessibilityHidden(true)
            Button { newDeck = NewDeckRequest(mapID: nil) } label: {
                Text("Make Slides").frame(minHeight: 44).contentShape(Rectangle())
            }
        }
        .minorFont(14, maxScale: 1.3)
        .foregroundColor(MinorColor.textSecondary)
        .buttonStyle(.plain)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("", text: $askText, axis: .vertical)
                .placeholder(when: askText.isEmpty) {
                    Text(homeImageMode ? "Describe an image" : "Ask Minor")
                        .foregroundColor(placeholderTextColor)
                }
                .foregroundColor(.white)
                .font(.system(size: 17))
                .lineLimit(1...4)
                .focused($homeFieldFocused)
                .textFieldStyle(PlainTextFieldStyle())
                .accessibilityLabel(homeImageMode ? "Describe an image" : "Ask Minor")
                .padding(.horizontal, 4)
                // The text area keeps the card 120 pt tall and grows with longer messages.
                .frame(minHeight: 52, alignment: .topLeading)
            HStack(alignment: .center, spacing: 10) {
                Menu {
                    Button { showHomePhotos = true } label: { Label("Photo Library", systemImage: "photo") }
                    Button { DocumentPicker.present { attachHomeFile($0) } } label: { Label("File", systemImage: "doc.text") }
                    if !MapStore.shared.maps.isEmpty {
                        Button { askText += askText.isEmpty || askText.hasSuffix(" ") ? "@" : " @" } label: {
                            Label("Mind Map", systemImage: "point.3.connected.trianglepath.dotted")
                        }
                    }
                    Button { homeImageMode.toggle() } label: {
                        Label(homeImageMode ? "Back to Chat" : "Create an Image", systemImage: "paintbrush.pointed")
                    }
                } label: {
                    Image(systemName: "plus")
                        .foregroundColor(.white)
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 32, height: 32)
                        .overlay(Circle().stroke(homeFile != nil ? MinorColor.accent : chatStrokeColor, lineWidth: 1))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .padding(.leading, -6)
                .accessibilityLabel("Attach")

                Button(action: { showHomePhotos = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.system(size: 15))
                            .frame(width: 20, height: 20)
                        Text(homeImages.isEmpty ? "Media" : "\(homeImages.count) Photo\(homeImages.count == 1 ? "" : "s")")
                            .font(.system(size: 14))
                            .lineLimit(1)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(!homeImages.isEmpty ? MinorColor.accent : chatStrokeColor, lineWidth: 1)
                    )
                    .frame(height: 44)
                    .contentShape(Rectangle())
                }
                Spacer(minLength: 0)
                DictationButton(text: $askText, stroke: chatStrokeColor, onError: { homeError = $0 }, onListeningChange: { homeDictating = $0 })
                // With nothing typed, the round button starts a voice conversation.
                Button {
                    if canSendFromHome { sendFromHome() } else { startHomeVoice() }
                } label: {
                    Image(systemName: canSendFromHome ? "arrow.up" : "waveform")
                        .foregroundColor(.black)
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.9))
                        .clipShape(Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .disabled(homeDictating || (homeImageMode && !canSendFromHome))
                .opacity(homeDictating || (homeImageMode && !canSendFromHome) ? 0.4 : 1)
                .accessibilityLabel(canSendFromHome ? "Send" : "Voice Mode")
                .padding(.trailing, -6)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .minorSurface(theme)
    }

    // The way to everything else: new maps and slides, Today, the Library, templates, settings.
    private var menuButton: some View {
        Button { openMenu() } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2").font(.system(size: 19))
                Text("Menu").minorFont(15, .medium, maxScale: 1.3)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .frame(minWidth: 112, minHeight: 44)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PressScale())
        .accessibilityFocused($menuButtonFocused)
    }

    // MARK: - Menu

    private var menu: some View {
        MenuView(
            theme: theme,
            path: $menuPath,
            isOpen: menuOpen,
            onClose: closeMenu,
            onNewDeck: { newDeck = NewDeckRequest(mapID: nil) },
            onOpenMap: { openMapID = $0 },
            onOpenDeck: { openDeckID = $0 },
            onOpenJob: { generatingJobID = $0 },
            onSettings: { showSettings = true }
        ) { place in
            menuDestination(place)
        }
    }

    @ViewBuilder
    private func menuDestination(_ place: MenuDestination) -> some View {
        Group {
            switch place {
            case .newMap:
                CreateMapView(
                    theme: theme,
                    conversations: chatVM.conversations,
                    // Covered by a map or the Building screen counts as inactive.
                    isActive: menuOpen && menuPath.last == .newMap && openMapID == nil && generatingJobID == nil,
                    onUpgrade: { openPaywall(from: "create_map") },
                    onUpgradePro: { openPaywall(pro: true, from: "create_map") },
                    onStart: { input, model in
                        withConsent { generatingJobID = GenerationCenter.shared.start(input, model: model) }
                    },
                    onOpenMap: { openMapID = $0 },
                    onToday: { push(.today) },
                    onAllMaps: {
                        LibraryState.shared.tab = .maps
                        push(.library)
                    },
                    onTemplates: { push(.templates(.maps)) }
                )
            case .library:
                LibraryView(
                    theme: theme,
                    onOpenMap: { openMapID = $0 },
                    onOpenDeck: { openDeckID = $0 },
                    onOpenChat: { conversation in
                        // The chat lives on the assistant: the Library steps away to show it.
                        chatVM.open(conversation)
                        closeMenu()
                    },
                    onOpenJob: { generatingJobID = $0 },
                    onNewMap: { push(.newMap) },
                    onNewDeck: { newDeck = NewDeckRequest(mapID: nil) },
                    onNewChat: {
                        // The earlier conversation stays in Chats.
                        chatVM.endSession()
                        closeMenu()
                    },
                    onLimits: { showUsage = true },
                    onSettings: { showSettings = true }
                )
            case .today:
                TodayView(theme: theme, onOpen: { mapID, nodeID in
                    GenerationCenter.shared.focusNode = nodeID
                    openMapID = mapID
                }, onAsk: {
                    // "Plan My Day": the chat assistant reads the tasks and answers.
                    closeMenu()
                    AuthGate.shared.require {
                        chatVM.send(L("Plan my day: look at my tasks and deadlines and make a short plan for today, most important first."), model: selectedModel, withTasks: true)
                    }
                }, onStudy: { mapID in
                    GenerationCenter.shared.studyRequest = mapID
                    openMapID = mapID
                }, onOpenMaps: { openLibrary(.maps) }, embedded: true)
            case .templates(let tab):
                TemplateLibraryView(theme: theme, tab: tab, onPickMap: createFromTemplate, onPickDeck: { template in
                    newDeck = NewDeckRequest(mapID: nil, template: template.id)
                })
            }
        }
        .modifier(BackToAssistant(active: menuFromAssistant && menuPath.count == 1 && menuPath.first == place, onBack: closeMenu))
    }

    private func push(_ place: MenuDestination) {
        guard menuPath.last != place else { return }
        menuPath.append(place)
    }

    private func openMenu(to place: MenuDestination? = nil, fromAssistant: Bool = false) {
        if menuOpen {
            if let place, menuPath.last != place { menuPath.append(place) }
            return
        }
        Haptics.impact(.light)
        present(.rise, path: place.map { [$0] } ?? [], fromAssistant: fromAssistant && place != nil)
    }

    // The Library straight from the assistant's (or a chat's) top button: it slides in from the
    // side, without the menu under it, and Back returns to where it was opened. Its tab and search
    // are LibraryState's, so it opens as it was left unless a tab is asked for.
    private func openLibrary(_ tab: LibraryTab? = nil, from opener: LibraryOpener = .assistant) {
        if let tab { LibraryState.shared.tab = tab }
        if menuOpen {
            push(.library)
            return
        }
        libraryOpener = opener
        LibraryState.shared.fadePending = true
        present(.slide, path: [.library], fromAssistant: true)
    }

    private func present(_ entry: MenuEntry, path: [MenuDestination], fromAssistant: Bool) {
        homeFieldFocused = false
        let moved = menuEntry != entry
        var quiet = Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet) {
            menuEntry = entry
            menuDrag = 0
            menuPath = path
            menuFromAssistant = fromAssistant
        }
        let animation: Animation
        if reduceMotion {
            animation = .easeInOut(duration: entry == .slide ? 0.18 : 0.14)
        } else {
            // Ease-out, no spring: up for the menu, across for the Library.
            animation = entry == .slide ? .timingCurve(0.22, 0.61, 0.36, 1, duration: 0.3) : .timingCurve(0.2, 0.85, 0.25, 1, duration: 0.3)
        }
        let show = { withAnimation(animation) { menuOpen = true } }
        // A layer that just changed sides is drawn there once before it moves in.
        if moved { DispatchQueue.main.async(execute: show) } else { show() }
    }

    private func closeMenu() {
        guard menuOpen else { return }
        let slide = menuEntry == .slide
        let animation: Animation
        if reduceMotion {
            animation = .easeInOut(duration: 0.14)
        } else {
            animation = slide ? .timingCurve(0.22, 0.61, 0.36, 1, duration: 0.28) : .timingCurve(0.4, 0, 0.6, 1, duration: 0.23)
        }
        withAnimation(animation) { menuOpen = false }
        // Once it is gone the stack goes back to the menu itself, and VoiceOver to the button that
        // opened it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard !menuOpen else { return }
            var quiet = Transaction()
            quiet.disablesAnimations = true
            withTransaction(quiet) {
                menuPath = []
                menuFromAssistant = false
                menuEntry = .rise
                menuDrag = 0
            }
            LibraryState.shared.query = ""
            if !slide {
                menuButtonFocused = true
            } else if libraryOpener == .assistant && chatVM.messages.isEmpty {
                libraryButtonFocused = true
            }
        }
    }

    // Back from the Library's left edge, following the finger (only where it came in from the side).
    private var libraryBackGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { value in
                guard menuOpen, menuEntry == .slide, !reduceMotion, menuPath.count == 1, value.startLocation.x < 24 else { return }
                let dx = value.translation.width
                guard menuDrag > 0 || dx > abs(value.translation.height) else { return }
                menuDrag = max(0, dx)
            }
            .onEnded { value in
                guard menuDrag > 0 else { return }
                if value.translation.width > containerWidth * 0.35 || value.predictedEndTranslation.width > containerWidth * 0.6 {
                    closeMenu()
                } else {
                    withAnimation(.easeOut(duration: 0.2)) { menuDrag = 0 }
                }
            }
    }

    // A map was built from New Map: Back from it goes to the menu (or the assistant, if New Map
    // was opened from there), not to an emptied New Map.
    private func leaveNewMap() {
        guard menuOpen, menuPath.last == .newMap else { return }
        var quiet = Transaction()
        quiet.disablesAnimations = true
        if menuFromAssistant && menuPath.count == 1 {
            withTransaction(quiet) {
                menuOpen = false
                menuPath = []
                menuFromAssistant = false
            }
        } else {
            withTransaction(quiet) { _ = menuPath.popLast() }
        }
    }

    // A template map counts as one of the month's maps; signing in comes first.
    private func createFromTemplate(_ template: MapTemplate) {
        guard AuthService.shared.isSignedIn else { return AuthGate.shared.require { createFromTemplate(template) } }
        if account.isOverFreeLimit { return openPaywall(from: "templates") }
        Task {
            do {
                let map = try await template.create()
                openMapID = map.id
            } catch BackendError.limitReached(let kind) {
                account.noteLimitReached(kind: kind)
                openPaywall(from: "templates")
            } catch {
                templateError = (error as? LocalizedError)?.errorDescription ?? L("Something went wrong. Try again.")
            }
        }
    }

    // `source` says what opened it, for the paywall funnel in analytics.
    private func openPaywall(from source: String) {
        openPaywall(pro: false, from: source)
    }

    // Opens the paywall with Plus or PRO already selected (PRO for PRO-only features).
    private func openPaywall(pro: Bool, from source: String) {
        paywallTier = pro || account.effectivePlan == .plus ? .pro : .plus
        Telemetry.log("paywall_view", ["tier": paywallTier == .pro ? "pro" : "plus", "source": source])
        withAnimation(.easeInOut(duration: 0.35)) {
            isBlurActive = true
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0.2)) {
            mainScreenOffsetY = -50
        }
    }

    // Runs an AI action now, or after the one-time consent if it was never given.
    // AI needs an account (asked for first) and the one-time consent.
    // A PDF, TXT or RTF file attached to the first message.
    private func attachHomeFile(_ url: URL) {
        let isPaid = account.isPaid
        Task {
            do {
                homeFile = try await Attachments.loadDocument(at: url, maxPages: isPaid ? 300 : 10)
                homeError = nil
            } catch {
                homeError = Attachments.message(for: error, isPaid: isPaid)
            }
        }
    }

    private func withConsent(_ action: @escaping () -> Void) {
        guard AuthService.shared.isSignedIn else {
            return AuthGate.shared.require { withConsent(action) }
        }
        if AIConsent.isGiven {
            action()
        } else {
            afterConsent = action
            showConsent = true
        }
    }

    // A picture is drawn from words, so image mode needs text; attachments wait for a normal message.
    private func startHomeVoice() {
        guard AuthService.shared.isSignedIn else { return AuthGate.shared.require { homeVoice = true } }
        Telemetry.log("voice_mode_start")
        homeVoice = true
    }

    private var canSendFromHome: Bool {
        let hasText = !askText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return homeImageMode ? hasText : hasText || !homeImages.isEmpty || homeFile != nil
    }

    private func sendFromHome() {
        guard canSendFromHome else { return }
        // The typed text stays in the field while the person signs in, then goes out.
        guard AuthService.shared.isSignedIn else { return AuthGate.shared.require { sendFromHome() } }
        let text = askText
        let maps = Mentions.used(homeMentions, in: text)
        askText = ""
        homeMentions = []
        chatVM.send(text, model: selectedModel, images: homeImageMode ? [] : homeImages, file: homeImageMode ? nil : homeFile, maps: homeImageMode ? [] : maps, asImage: homeImageMode)
        // In image mode the attached photos and file weren't sent: they stay for the next message.
        if !homeImageMode {
            homeImages = []
            homeFile = nil
        }
        homeImageMode = false
    }

    private var homeMentionMatches: [MindMap] {
        guard !homeImageMode, let query = Mentions.query(in: askText, picked: homeMentions) else { return [] }
        return Mentions.matches(query, in: MapStore.shared.maps)
    }

    // Something shows in the row above the home card (attachments, an error or the hint).
    private var homeAccessoryShown: Bool {
        !homeImages.isEmpty || homeFile != nil || homeError != nil
    }

    // Above the input card: attached photos and file, or the one-time Mind Map hint.
    @ViewBuilder
    private var homeAccessory: some View {
        if !homeImages.isEmpty || homeFile != nil {
            HStack(spacing: 8) {
                ForEach(Array(homeImages.enumerated()), id: \.offset) { index, data in
                    if let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .onTapGesture { if homeImages.indices.contains(index) { homeImages.remove(at: index) } }
                            .accessibilityLabel("Remove photo")
                            .accessibilityAddTraits(.isButton)
                    }
                }
                if let file = homeFile {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text").font(.system(size: 12))
                        Text(file.name).font(.system(size: 13)).lineLimit(1)
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .overlay(Capsule().stroke(chatStrokeColor, lineWidth: 1))
                    .onTapGesture { homeFile = nil }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Remove \(file.name)"))
                    .accessibilityAddTraits(.isButton)
                }
            }
        } else if let homeError {
            Text(homeError)
                .font(.system(size: 13))
                .foregroundColor(MinorColor.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .onTapGesture { self.homeError = nil }
                .task(id: homeError) {
                    try? await Task.sleep(nanoseconds: 6_000_000_000)
                    self.homeError = nil
                }
        }
    }

    private func closePaywall() {
        withAnimation(.easeInOut(duration: 0.3)) {
            isBlurActive = false
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0.2)) {
            mainScreenOffsetY = 0
        }
    }


    // A "map is ready" notification was tapped: show that map, whatever was open.
    // minorai://today, minorai://map/<id>, minorai://task/<map id>/<idea id> (widget taps).
    private func openLink(_ url: URL) {
        guard url.scheme == SharedContainer.scheme else { return }
        // Onboarding covers everything (sheets can't show above it): the link waits for it.
        guard !showOnboarding else {
            pendingLink = url
            return
        }
        let parts = url.pathComponents.filter { $0 != "/" }.compactMap(UUID.init(uuidString:))
        switch url.host {
        case "today":
            if isBlurActive { closePaywall() }
            closeOverlays()
            openMapID = nil
            chatVM.endSession()
            if menuOpen { menuPath = [.today] } else { openMenu(to: .today) }
        case "map":
            if let map = parts.first { generation.openRequest = map }
        case "task":
            if parts.count == 2 {
                generation.focusNode = parts[1]
                generation.openRequest = parts[0]
            }
        case "join":
            // minorai://join/<invite secret>: the invitation to a shared map, before joining it.
            if let token = url.pathComponents.filter({ $0 != "/" }).first { joinShared(token) }
        case "invite":
            // minorai://invite/<friend's code> from an invitation link, or minorai://invite from a notification.
            let code = url.pathComponents.filter { $0 != "/" }.first.map(InviteService.clean).flatMap { $0.isEmpty ? nil : $0 }
            if let code, InviteService.isValid(code) { InviteService.shared.pendingCode = code }
            presentOverSettings { inviteSheet = InviteSheet(code: code) }
        case "usage":
            presentOverSettings { showUsage = true }
        default:
            break
        }
    }

    // Only one sheet shows at a time: any open one closes first, then the requested screen opens.
    private func presentOverSettings(_ open: @escaping () -> Void) {
        if isBlurActive { closePaywall() }
        let sheetOpen = showSettings || showUsage || inviteSheet != nil || newDeck != nil || pendingInvite != nil
        guard sheetOpen else { return open() }
        showSettings = false
        showUsage = false
        inviteSheet = nil
        newDeck = nil
        pendingInvite = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: open)
    }

    // A map opened from a notification, a widget or Siri must not end up hidden under a
    // presentation or a sheet.
    private func closeOverlays() {
        openDeckID = nil
        showSettings = false
        showUsage = false
        inviteSheet = nil
        newDeck = nil
    }

    // Shows what the link offers; joining happens there, after sign-in if needed.
    private func joinShared(_ token: String) {
        presentOverSettings { pendingInvite = InviteLink(token: token) }
    }

    // Pages and text shared from other apps, one at a time.
    private func checkSharedItems() {
        guard pendingShare == nil, generatingJobID == nil, let next = SharedItem.pending().first else { return }
        pendingShare = next
    }

    private enum Layer { case home, menu, chat, building, map, deck }
    enum MenuEntry { case rise, slide }
    enum LibraryOpener { case assistant, chat }

    // The full-screen layer on top; VoiceOver reads only that one.
    private var topLayer: Layer {
        if openDeckID != nil { return .deck }
        if openMapID != nil { return .map }
        if generatingJobID != nil { return .building }
        if menuOpen { return .menu }
        if !chatVM.messages.isEmpty { return .chat }
        return .home
    }

    private func openRequested(_ id: UUID) {
        generation.openRequest = nil
        guard MapStore.shared.map(id) != nil else { return }
        if isBlurActive { closePaywall() }
        closeOverlays()
        generatingJobID = nil
        openMapID = id
    }
}

extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content) -> some View {
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // RGBA (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

// A request to show Invite Friends, with a friend's code from a link.
struct InviteSheet: Identifiable {
    let id = UUID()
    let code: String?
}

// A full-screen layer: modal for VoiceOver when on top, hidden from it when covered. The modal
// mark is set only while VoiceOver runs: UI tests would otherwise take the layer for an alert.
private struct TopLayer: ViewModifier {
    let isTop: Bool
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    func body(content: Content) -> some View {
        content
            .accessibilityAddTraits(isTop && voiceOver ? .isModal : [])
            .accessibilityHidden(!isTop)
    }
}

// Opened from the assistant (Create a Map), the first screen in the menu goes Back to the assistant.
private struct BackToAssistant: ViewModifier {
    let active: Bool
    var onBack: () -> Void

    func body(content: Content) -> some View {
        if active {
            content
                .navigationBarBackButtonHidden(true)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: onBack) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold))
                                Text("Assistant")
                            }
                        }
                        .accessibilityLabel("Back to Assistant")
                    }
                }
        } else {
            content
        }
    }
}
