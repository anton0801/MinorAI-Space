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
    @State private var openDeckID: UUID?
    @State private var newDeck: NewDeckRequest?

    struct NewDeckRequest: Identifiable {
        let id = UUID()
        let mapID: UUID?
    }
    #if DEBUG
    @State private var slideGallery = false
    #endif
    @Environment(\.scenePhase) private var scenePhase
    @State private var homeImages: [Data] = []
    @State private var homeFile: Attachments.Document?
    @State private var homePhotoItems: [PhotosPickerItem] = []
    @State private var showHomePhotos = false
    @State private var showHomeHint = false
    @State private var homeError: String?
    @State private var homeImageMode = false
    @State private var pendingChatDelete: Conversation?
    @ObservedObject private var gate = AuthGate.shared
    @State private var showConsent = false
    @State private var afterConsent: (() -> Void)?
    @State private var sidebarTab: SidebarTab = .maps
    @State private var generatingJobID: UUID?
    @ObservedObject private var generation = GenerationCenter.shared
    @ObservedObject private var account = AccountStore.shared
    @State private var openMapID: UUID?
    @State private var chatHeight: CGFloat = 120
    @State private var chatWidth: CGFloat = min(365, UIScreen.main.bounds.width - 20)
    @State private var textFieldOffsetX: CGFloat = -5
    @State private var textFieldOffsetY: CGFloat = -10
    @State private var buttonsOffsetX: CGFloat = -100
    @State private var buttonsOffsetY: CGFloat = 20
    @State private var isMindActive: Bool = false
    @State private var isBlurActive: Bool = false
    @State private var isSidebarActive: Bool = false
    @State private var sidebarOffset: CGFloat = -UIScreen.main.bounds.width
    @State private var showSettings = false
    @State private var showUsage = false
    @State private var inviteSheet: InviteSheet?
    @State private var paywallTier: SubscriptionStore.Tier = .plus
    @AppStorage("didOnboard") private var didOnboard = false
    // The onboarding cover has its own state that body reads, rather than a Binding(get:set:)
    // over the @AppStorage that body never read.
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "didOnboard")
    // Phones with a Home button (iPhone SE) have no bottom inset for the Mind button to sit in.
    @State private var hasHomeIndicator = true
    // A link that arrived during onboarding, opened once it is done.
    @State private var pendingLink: URL?
    @State private var minorPlusOffsetY: CGFloat = -10
    @State private var mainScreenOffsetY: CGFloat = 0
    @State private var bigLogoOffsetX: CGFloat = 0
    @State private var bigLogoOffsetY: CGFloat = -90
    @State private var selectedSphere: Int? = UserDefaults.standard.integer(forKey: "SelectedSphere") != 0 ? UserDefaults.standard.integer(forKey: "SelectedSphere") : nil
    @State private var isModelMenuActive: Bool = false
    @State private var selectedModel: AIModelOption = AIModelCatalog.default
    @ObservedObject private var chatVM = ChatViewModel.shared
    @ObservedObject private var subscriptions = SubscriptionStore.shared

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
    
    var body: some View {
        ZStack {
            backgroundColor // Динамический фон приложения
                .ignoresSafeArea()

            // The bottom inset comes from the layout (a reader inside the safe area sees it; the
            // keyboard doesn't count). Read from the window, as before, it froze this screen on
            // iOS 26: no state change redrew it after the first frame, so "Not Now" and signing
            // in couldn't close onboarding (App Review, 2.0 (2)) and no home button answered.
            GeometryReader { geo in
                Color.clear
                    .onAppear { hasHomeIndicator = geo.safeAreaInsets.bottom > 0 }
                    .onChange(of: geo.safeAreaInsets.bottom) { hasHomeIndicator = $0 > 0 }
            }
            .ignoresSafeArea(.keyboard)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            VStack {
                Spacer()
                Rectangle()
                    .fill(blurColor) // Динамический цвет блюра
                    .frame(height: 120)
                    .blur(radius: 50)
                    .opacity(0.5)
            }
            .offset(y: isMindActive ? -UIScreen.main.bounds.height + 50 : 0)
            .scaleEffect(isMindActive ? 0.1 : 1, anchor: .top)
            .opacity(isMindActive ? 0 : 1)
            
            Image("logo")
                .resizable()
                .scaledToFit()
                .frame(width: 110, height: 110)
                .position(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2.5)
                .opacity(0.2)
                .offset(y: isMindActive ? -UIScreen.main.bounds.height + 50 : 0)
                .scaleEffect(isMindActive ? 0.05 : 1, anchor: .top)
                .opacity(isMindActive ? 0 : 1)
                .offset(y: mainScreenOffsetY)
                .animation(.spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0.2), value: mainScreenOffsetY)
            
            // Кнопка "Minor Plus" в центре (only for people without a plan)
            Button(action: {
                openPaywall(from: "get_plus_button")
            }) {
                // "Get Plus", not the plan's name: free users read "Minor Plus" as their plan. As
                // narrow as the old pill, so it never reaches the model name on an iPhone SE.
                Text("Get Plus")
                    .foregroundColor(.white)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 12)
                    .frame(width: 122, height: 35)
                    .background(
                        RoundedRectangle(cornerRadius: 25)
                            .fill(minorPlusRectangleColor)
                            .overlay(RoundedRectangle(cornerRadius: 25).stroke(minorPlusStrokeColor, lineWidth: 1))
                    )
            }
            .accessibilityLabel("Get Minor Plus")
            .position(x: UIScreen.main.bounds.width / 2, y: 40) // Центр
            .offset(y: minorPlusOffsetY)
            .offset(y: isMindActive ? -40 : 0)
            .scaleEffect(isMindActive ? 0.1 : 1, anchor: .top)
            .opacity(isMindActive || account.isPaid ? 0 : 1)
            .allowsHitTesting(!account.isPaid)
            .accessibilityHidden(account.isPaid)
            .animation(.spring(response: 0.6, dampingFraction: 0.7, blendDuration: 0.2), value: isMindActive)
            
            // Кнопка выбора модели с правого края (без прямоугольника)
            Button(action: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8, blendDuration: 0.2)) {
                    isModelMenuActive.toggle()
                }
            }) {
                HStack(spacing: 5) {
                    Text(selectedModel.displayName)
                        .foregroundColor(.white)
                        .font(.system(size: 16))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Image(systemName: "chevron.right")
                        .foregroundColor(.white)
                        .font(.system(size: 16))
                        .rotationEffect(.degrees(isModelMenuActive ? 90 : 0)) // Вращение на 90 градусов
                        .offset(y: isModelMenuActive ? 5 : 0) // Опускание на 5 пунктов
                        .animation(.spring(response: 0.4, dampingFraction: 0.7, blendDuration: 0), value: isModelMenuActive)
                }
            }
            .accessibilityLabel("AI model: \(selectedModel.displayName)")
            // Right-aligned in the space right of the centered "Minor Plus" pill, so long model
            // names never run under it or off the screen (iPhone SE).
            .frame(width: (UIScreen.main.bounds.width - 130) / 2 - 16, alignment: .trailing)
            .position(x: UIScreen.main.bounds.width - ((UIScreen.main.bounds.width - 130) / 2 - 16) / 2 - 12, y: 40)
            .offset(y: minorPlusOffsetY)
            .offset(y: isMindActive ? -40 : 0)
            .scaleEffect(isMindActive ? 0.1 : 1, anchor: .top)
            .opacity(isMindActive ? 0 : 1)
            .animation(.spring(response: 0.6, dampingFraction: 0.7, blendDuration: 0.2), value: isMindActive)
            
            // Кнопка для боковой панели
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isSidebarActive.toggle()
                    sidebarOffset = isSidebarActive ? 0 : -UIScreen.main.bounds.width
                }
            }) {
                Image("Slider")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 25, height: 25)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Your Maps and Chats")
            // At the left edge as on a 393-pt iPhone, not drifting inward on wider screens.
            .position(x: min(UIScreen.main.bounds.width / 2 - 160, 36.5), y: 40)
            .offset(y: minorPlusOffsetY)
            .offset(y: isMindActive ? -40 : 0)
            .scaleEffect(isMindActive ? 0.1 : 1, anchor: .top)
            .opacity(isMindActive ? 0 : 1)
            .animation(.spring(response: 0.6, dampingFraction: 0.7, blendDuration: 0.2), value: isMindActive)
            
            // Прямоугольник "Ask me anything"
            VStack {
                Spacer()
                // "@" lists the person's maps right above the card (above the attachments row or
                // hint when one shows), never over the field being typed in.
                if !homeMentionMatches.isEmpty && !isMindActive {
                    MentionSuggestions(maps: homeMentionMatches, theme: theme) { map in
                        askText = Mentions.insert(map, into: askText)
                        if !homeMentions.contains(where: { $0.id == map.id }) { homeMentions.append(MapMention(id: map.id, title: map.title)) }
                        Haptics.selection()
                    }
                    // The list has its own 16-pt side margins; the outer frame keeps the column as
                    // wide as the card, so the screen's layout doesn't widen and shift.
                    .frame(width: chatWidth + 32)
                    .frame(width: chatWidth)
                    .padding(.bottom, homeAccessoryShown ? 52 : 6)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(chatRectangleColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(chatStrokeColor, lineWidth: 1)
                        )
                        .frame(width: chatWidth, height: chatHeight)
                    
                    VStack(spacing: 0) {
                        HStack {
                            TextField("", text: $askText)
                                .accessibilityLabel("Ask me anything")
                                .foregroundColor(Color(red: 255/255, green: 255/255, blue: 255/255))
                                .placeholder(when: askText.isEmpty) {
                                    Text(homeImageMode ? "Describe an image" : "Ask me anything")
                                        .foregroundColor(placeholderTextColor)
                                }
                                .submitLabel(.done)
                                .padding(.horizontal, 32)
                                .offset(y: -10)
                                .textFieldStyle(PlainTextFieldStyle())
                                .font(.system(size: 17)) // Установил тот же размер шрифта, что в "Create miracles"
                            
                            Button(action: sendFromHome) {
                                Image(systemName: "arrow.up")
                                    .foregroundColor(.black)
                                    .font(.system(size: 16, weight: .bold))
                                    .frame(width: 34, height: 34)
                                    .background(Color.white.opacity(0.9))
                                    .clipShape(Circle())
                            }
                            .disabled(!canSendFromHome || homeDictating)
                            .opacity(canSendFromHome && !homeDictating ? 1 : 0.4)
                            .accessibilityLabel("Send")
                            .padding(.trailing, 29)
                            .offset(x: -2, y: 48)
                        }
                        .frame(height: 60) // Установил фиксированную высоту для выравнивания
                        
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
                                    .overlay(
                                        Circle()
                                            .stroke(homeFile != nil ? MinorColor.accent : chatStrokeColor, lineWidth: 1)
                                    )
                            }
                            .accessibilityLabel("Attach")
                            
                            Button(action: {
                                showHomePhotos = true
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "photo")
                                        .font(.system(size: 15))
                                        .foregroundColor(.white)
                                        .frame(width: 20, height: 20)
                                    Text(homeImages.isEmpty ? "Media" : "\(homeImages.count) Photo\(homeImages.count == 1 ? "" : "s")")
                                        .foregroundColor(.white)
                                        .font(.system(size: 14))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 15)
                                        .stroke(!homeImages.isEmpty ? Color(red: 47/255, green: 255/255, blue: 158/255) : chatStrokeColor, lineWidth: 1)
                                )
                            }
                            DictationButton(text: $askText, stroke: chatStrokeColor, onError: { homeError = $0 }, onListeningChange: { homeDictating = $0 })
                            Spacer()
                        }
                        .offset(x: 30, y: 2)
                    }
                    // The paddings above were set on a 393-pt iPhone, where the content is 28 pt
                    // wider than the card; pinning it to that keeps it inside the card on Plus,
                    // Pro Max and SE screens too.
                    .frame(width: chatWidth + 28)
                }
                .overlay(alignment: .top) {
                    homeAccessory
                        .offset(y: -44)
                }
                .offset(y: isMindActive ? -UIScreen.main.bounds.height + 50 : 0)
                .scaleEffect(isMindActive ? 0.1 : 1, anchor: .top)
                .opacity(isMindActive ? 0 : 1)
                .animation(.spring(response: 0.6, dampingFraction: 0.7, blendDuration: 0.2), value: isMindActive)
                
                Button(action: {
                    UserDefaults.standard.set(true, forKey: "didSeeMindHint")
                    showHomeHint = false
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.7, blendDuration: 0.2)) {
                        isMindActive.toggle()
                    }
                }) {
                    Image("mind")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 30, height: 30)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Mind Maps")
                .padding(.top, 8)
                .offset(y: isMindActive ? -UIScreen.main.bounds.height + 50 : 0)
                .scaleEffect(isMindActive ? 0.1 : 1, anchor: .top)
                .opacity(isMindActive ? 0 : 1)
                .animation(.spring(response: 0.6, dampingFraction: 0.7, blendDuration: 0.2), value: isMindActive)
            }
            .offset(y: mainScreenOffsetY + (isMindActive || !hasHomeIndicator ? 0 : 30))
            .animation(.spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0.2), value: mainScreenOffsetY)
            .padding(.bottom, 20)
            
            // Отдельное меню моделей с красивой анимацией
            if isModelMenuActive {
                VStack(spacing: 0.5) {
                    let models = AIModelCatalog.all
                    ForEach(models.indices, id: \.self) { index in
                        let model = models[index]
                        Button(action: {
                            withAnimation(.spring(response: 0.1, dampingFraction: 0.8, blendDuration: 0.2)) {
                                isModelMenuActive = false
                            }
                            selectedModel = model
                        }) {
                            // Every model is open to every plan; the number says how much faster it
                            // uses the monthly AI allowance than the lightest one.
                            HStack(spacing: 6) {
                                Text(model.displayName)
                                    .foregroundColor(.white)
                                    .font(.system(size: 14))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                Spacer(minLength: 4)
                                if model == selectedModel {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.white)
                                        .font(.system(size: 13))
                                } else {
                                    Text("×\(model.usage)")
                                        .foregroundColor(MinorColor.textSecondary)
                                        .font(.system(size: 12).monospacedDigit())
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(width: 200)
                            .background(Color(red: 50/255, green: 50/255, blue: 50/255))
                            .cornerRadius(
                                index == 0 ? 10 : 0,
                                corners: [.topLeft, .topRight]
                            )
                            .cornerRadius(
                                index == models.count - 1 ? 10 : 0,
                                corners: [.bottomLeft, .bottomRight]
                            )
                            .offset(y: isModelMenuActive ? 0 : -10) // Смещение вверх при открытии
                            .opacity(isModelMenuActive ? 1 : 0) // Плавное появление
                            .scaleEffect(isModelMenuActive ? 1 : 0.95) // Небольшое увеличение
                            .animation(
                                .spring(response: 0.5, dampingFraction: 0.6, blendDuration: 0.2)
                                .delay(Double(index) * 0.05),
                                value: isModelMenuActive
                            )
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("AI models. Stronger models use more of your monthly AI allowance.")
                .position(x: UIScreen.main.bounds.width - 112, y: 190) // Фиксированная позиция под кнопкой модели
                .zIndex(1)
            }
            
            VStack {
                Rectangle()
                    .fill(Color.white.opacity(0.2))
                    .frame(height: 250)
                    .blur(radius: 50)
                    .opacity(isMindActive ? 1 : 0)
                    .offset(y: isMindActive ? -210 : -250)
                Spacer()
            }
            .animation(.spring(response: 0.6, dampingFraction: 0.7, blendDuration: 0.2), value: isMindActive)
            
            // Режим Mind: экран создания карты
            CreateMapView(
                theme: theme,
                conversations: chatVM.conversations,
                // Hidden behind a map, a chat, the sidebar or the Building screen counts as inactive.
                isActive: isMindActive && !isSidebarActive && openMapID == nil && generatingJobID == nil && chatVM.messages.isEmpty,
                onClose: {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.7, blendDuration: 0.2)) {
                        isMindActive = false
                    }
                },
                onOpenSidebar: openSidebar,
                onUpgrade: { openPaywall(from: "create_map") },
                onUpgradePro: { openPaywall(pro: true, from: "create_map") },
                onStart: { input, model in
                    withConsent { generatingJobID = GenerationCenter.shared.start(input, model: model) }
                },
                onOpenMap: { id in openMapID = id },
                onAskAssistant: { text in
                    // "Plan My Day": the chat assistant reads the tasks and answers.
                    AuthGate.shared.require { chatVM.send(text, model: selectedModel, withTasks: true) }
                },
                onNewDeck: { newDeck = NewDeckRequest(mapID: nil) }
            )
            .offset(y: isMindActive ? 0 : UIScreen.main.bounds.height)
            .opacity(isMindActive ? 1 : 0)
            .allowsHitTesting(isMindActive)
            .animation(.spring(response: 0.6, dampingFraction: 0.7, blendDuration: 0.2), value: isMindActive)
            
            BlurView(style: .dark)
                .edgesIgnoringSafeArea(.all)
                .opacity(isSidebarActive ? 1 : 0)
                .animation(.easeInOut(duration: 0.3), value: isSidebarActive)
            
            // Paywall поверх всего, включая редактор карты
            if isBlurActive {
                PaywallView(tier: paywallTier, onClose: closePaywall)
                    .transition(.opacity)
                    .zIndex(20)
            }

            ZStack {
                BlurView(style: .dark)
                    .edgesIgnoringSafeArea(.all)
                    .offset(x: sidebarOffset)
                    .animation(.easeInOut(duration: 0.3), value: sidebarOffset)
                
                VStack(spacing: 0) {
                    HStack {
                        Text(sidebarTab == .maps ? "Your Maps" : sidebarTab == .decks ? "Your Presentations" : "Your Chats")
                            .foregroundColor(.white)
                            .font(.system(size: 22, weight: .bold))
                        Spacer()
                        Button(action: {
                            if sidebarTab == .decks {
                                closeSidebar()
                                newDeck = NewDeckRequest(mapID: nil)
                            } else if sidebarTab == .maps {
                                closeSidebar()
                                withAnimation(.spring(response: 0.6, dampingFraction: 0.7, blendDuration: 0.2)) {
                                    isMindActive = true
                                }
                            } else {
                                chatVM.endSession()
                                closeSidebar()
                            }
                        }) {
                            Image(systemName: "square.and.pencil")
                                .foregroundColor(.white)
                                .font(.system(size: 20))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel(sidebarTab == .maps ? "New Map" : sidebarTab == .decks ? "New Presentation" : "New Chat")
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 80)
                    .padding(.bottom, 16)

                    SidebarSegment(selection: $sidebarTab)
                        .padding(.bottom, 16)

                    if sidebarTab == .maps {
                        SidebarMapsView(onOpen: { id in
                            closeSidebar()
                            openMapID = id
                        }, onOpenJob: { id in
                            closeSidebar()
                            generatingJobID = id
                        })
                    } else if sidebarTab == .decks {
                        SidebarDecksView(onOpen: { id in
                            closeSidebar()
                            openDeckID = id
                        }, onNew: {
                            closeSidebar()
                            newDeck = NewDeckRequest(mapID: nil)
                        })
                    } else if chatVM.conversations.isEmpty {
                        Spacer()
                        VStack(spacing: 10) {
                            Image(systemName: "message")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 50, height: 50)
                                .foregroundColor(.white)
                            Text("No conversations yet")
                                .foregroundColor(.white)
                                .font(.system(size: 18, weight: .bold))
                            Text("Start one from the home screen.")
                                .foregroundColor(Color(red: 163/255, green: 163/255, blue: 163/255))
                                .font(.system(size: 15, weight: .medium))
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(chatVM.conversations) { convo in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(convo.title)
                                                .foregroundColor(.white)
                                                .font(.system(size: 16, weight: .medium))
                                                .lineLimit(1)
                                            Text(convo.updatedAt, style: .date)
                                                .foregroundColor(Color(red: 150/255, green: 150/255, blue: 150/255))
                                                .font(.system(size: 12))
                                        }
                                        Spacer()
                                        Button(action: {
                                            pendingChatDelete = convo
                                        }) {
                                            Image(systemName: "trash")
                                                .foregroundColor(MinorColor.textSecondary)
                                                .font(.system(size: 14))
                                                .frame(width: 44, height: 44)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        .accessibilityLabel("Delete chat")
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.white.opacity(0.08))
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        chatVM.open(convo)
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            isSidebarActive = false
                                            sidebarOffset = -UIScreen.main.bounds.width
                                        }
                                    }
                                    .accessibilityElement(children: .combine)
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityAction(named: "Delete chat") { pendingChatDelete = convo }
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                        }
                    }

                    Button(action: {
                        showSettings = true
                    }) {
                        Image(systemName: "gear")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 30, height: 30)
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Settings")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 20)
                    .padding(.bottom, 10)
                }
                .offset(x: sidebarOffset)
                .animation(.easeInOut(duration: 0.3), value: sidebarOffset)
                
            }
            // Off screen it must not be read by VoiceOver; open, it is a modal with an escape gesture.
            .accessibilityHidden(!isSidebarActive)
            .accessibilityAddTraits(isSidebarActive ? .isModal : [])
            .accessibilityAction(.escape) { closeSidebar() }
            
            // Экран диалога поверх лаунчера, когда есть сообщения
            if !chatVM.messages.isEmpty {
                ChatView(
                    viewModel: chatVM,
                    theme: theme,
                    model: $selectedModel,
                    onHome: { chatVM.endSession() },
                    onMapThis: { answer in
                        let title = Conversation.makeTitle(from: chatVM.messages)
                        withConsent {
                            generatingJobID = GenerationCenter.shared.start(.text(answer, source: MapSource(kind: .chat, label: title)))
                        }
                    },
                    onUpgrade: { openPaywall(from: "chat") }
                )
                .transition(.move(edge: .bottom))
                .modifier(TopLayer(isTop: topLayer == .chat))
                .zIndex(10)
            }

            // Построение карты, затем редактор
            if let jobID = generatingJobID {
                GeneratingView(
                    jobID: jobID,
                    theme: theme,
                    onDone: { id in
                        openMapID = id
                        generatingJobID = nil
                        isMindActive = false
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
                            isMindActive = false
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
                MapEditorView(
                    mapID: id,
                    theme: theme,
                    onClose: { openMapID = nil },
                    onUpgrade: { pro in openPaywall(pro: pro, from: "map_editor") },
                    onCreateDeck: { map in newDeck = NewDeckRequest(mapID: map) }
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
            showHomeHint = !UserDefaults.standard.bool(forKey: "didSeeMindHint") && MapStore.shared.maps.isEmpty
            if let id = generation.openRequest { openRequested(id) }
            // The screen was rebuilt for a new language while Settings was open.
            if LanguageSettings.shared.reopenSettings {
                LanguageSettings.shared.reopenSettings = false
                showSettings = true
            }
        }
        .onChange(of: generation.openRequest) { id in
            if let id { openRequested(id) }
        }
        #if DEBUG
        .fullScreenCover(isPresented: $slideGallery) { SlideGallery() }
        #endif
        .sheet(item: $newDeck) { request in
            NewDeckView(theme: theme, preselectedMap: request.mapID, onCreated: { id in
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
        .onChange(of: generation.topicRequest) { topic in
            // Siri or Shortcuts asked for a map about a topic.
            guard let topic else { return }
            generation.topicRequest = nil
            if isBlurActive { closePaywall() }
            closeSidebar()
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
        #if DEBUG
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-demoMap") { openMapID = DemoMap.install().id }
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
            if args.contains("-mindMode") { _ = DemoMap.install(); isMindActive = true }
            if args.contains("-sidebarMaps") { _ = DemoMap.install(); openSidebar() }
            if args.contains("-onboarding") { didOnboard = false; showOnboarding = true }
            if args.contains("-sidebarDecks") { DeckStore.shared.save(DemoMap.deck()); sidebarTab = .decks; openSidebar() }
            if args.contains("-demoChat") { chatVM.messages = DemoMap.chat }
            if args.contains("-demoSlides") { slideGallery = true }
            if args.contains("-demoDeck") || args.contains("-demoExport") || args.contains("-demoPresentDeck") {
                let deck = DemoMap.deck()
                DeckStore.shared.save(deck)
                openDeckID = deck.id
                if args.contains("-demoExport") {
                    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    if let pdf = try? DeckExport.pdf(deck) { try? FileManager.default.copyItem(at: pdf, to: documents.appendingPathComponent("demo.pdf")) }
                    if let pptx = try? DeckExport.pptx(deck) { try? FileManager.default.copyItem(at: pptx, to: documents.appendingPathComponent("demo.pptx")) }
                }
            }
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
            if args.contains("-demoBuilding") {
                _ = DemoMap.install()
                _ = GenerationCenter.shared.start(.topic("Photosynthesis"))
                openSidebar()
            }
            if args.contains("-demoPaywall") { openPaywall(from: "debug") }
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
        }
        #endif
        .sheet(isPresented: $showSettings) {
            SettingsView(
                selectedSphere: $selectedSphere,
                onUpgrade: { pro in
                    showSettings = false
                    closeSidebar()
                    openPaywall(pro: pro, from: "settings")
                },
                onDataDeleted: {
                    chatVM.deleteAll()
                    openMapID = nil
                }
            )
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showUsage) {
            UsageView(onUpgrade: { pro in
                showUsage = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { openPaywall(pro: pro, from: "limits") }
            })
        }
        .sheet(item: $inviteSheet) { request in InviteView(initialCode: request.code) }
        .sheet(isPresented: $gate.isPresented, onDismiss: { gate.finish() }) {
            SignInView(onFinish: { gate.close() })
        }
        .confirmationDialog(
            "Delete this chat?",
            isPresented: Binding(get: { pendingChatDelete != nil }, set: { if !$0 { pendingChatDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingChatDelete
        ) { convo in
            Button("Delete Chat", role: .destructive) { chatVM.deleteConversation(convo.id) }
            Button("Cancel", role: .cancel) {}
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
        .gesture(
            DragGesture()
                .onChanged { value in
                    guard sidebarSwipeEnabled else { return }
                    let translation = value.translation.width
                    if translation > 0 {
                        sidebarOffset = max(-UIScreen.main.bounds.width, -UIScreen.main.bounds.width + translation)
                    } else if isSidebarActive {
                        sidebarOffset = min(0, translation)
                    }
                }
                .onEnded { value in
                    guard sidebarSwipeEnabled else { return }
                    let translation = value.translation.width
                    if translation > 100 {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isSidebarActive = true
                            sidebarOffset = 0
                        }
                    } else if translation < -100 && isSidebarActive {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isSidebarActive = false
                            sidebarOffset = -UIScreen.main.bounds.width
                        }
                    } else {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            sidebarOffset = isSidebarActive ? 0 : -UIScreen.main.bounds.width
                        }
                    }
                }
        )
        // Tapping outside closes the model menu. Only while it is open: a tap gesture on the whole
        // screen otherwise competes with the buttons in the sidebar lists and sometimes wins.
        .gesture(
            TapGesture().onEnded {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8, blendDuration: 0.2)) {
                    isModelMenuActive = false
                }
            },
            including: isModelMenuActive ? .all : .subviews
        )
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
        !homeImages.isEmpty || homeFile != nil || homeError != nil || showHomeHint
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
            .frame(width: chatWidth, alignment: .leading)
        } else if let homeError {
            Text(homeError)
                .font(.system(size: 13))
                .foregroundColor(MinorColor.textSecondary)
                .multilineTextAlignment(.center)
                .frame(width: chatWidth)
                .onTapGesture { self.homeError = nil }
                .task(id: homeError) {
                    try? await Task.sleep(nanoseconds: 6_000_000_000)
                    self.homeError = nil
                }
        } else if showHomeHint {
            HStack(spacing: 6) {
                Text("New: turn any topic into a mind map")
                Image(systemName: "arrow.down")
            }
            .font(.system(size: 13))
            .foregroundColor(MinorColor.textSecondary)
            .transition(.opacity)
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


    // The edge swipe opens Your Maps only from the home and Mind screens, never over a map,
    // a chat or the paywall (where it fought with panning and scrolling).
    private var sidebarSwipeEnabled: Bool {
        openMapID == nil && openDeckID == nil && generatingJobID == nil && chatVM.messages.isEmpty && !isBlurActive && !showSettings
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
            closeSidebar()
            closeOverlays()
            openMapID = nil
            chatVM.endSession()
            isMindActive = true
            generation.todayRequest = true
        case "map":
            if let map = parts.first { generation.openRequest = map }
        case "task":
            if parts.count == 2 {
                generation.focusNode = parts[1]
                generation.openRequest = parts[0]
            }
        case "join":
            // minorai://join/<invite secret>: become an editor of a shared map.
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
        let sheetOpen = showSettings || showUsage || inviteSheet != nil || newDeck != nil
        guard sheetOpen else { return open() }
        showSettings = false
        showUsage = false
        inviteSheet = nil
        newDeck = nil
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

    private func joinShared(_ token: String) {
        guard AuthService.shared.isSignedIn else { return AuthGate.shared.require { joinShared(token) } }
        Task {
            do {
                let id = try await CollabService.shared.join(token: token)
                Telemetry.log("collab_join")
                if isBlurActive { closePaywall() }
                closeSidebar()
                chatVM.endSession()
                openMapID = id
            } catch {
                homeError = (error as? LocalizedError)?.errorDescription ?? L("Couldn’t open the shared map. Try again.")
            }
        }
    }

    // Pages and text shared from other apps, one at a time.
    private func checkSharedItems() {
        guard pendingShare == nil, generatingJobID == nil, let next = SharedItem.pending().first else { return }
        pendingShare = next
    }

    private enum Layer { case home, chat, building, map, deck }

    // The full-screen layer on top; VoiceOver reads only that one.
    private var topLayer: Layer {
        if openDeckID != nil { return .deck }
        if openMapID != nil { return .map }
        if generatingJobID != nil { return .building }
        if !chatVM.messages.isEmpty { return .chat }
        return .home
    }

    private func openRequested(_ id: UUID) {
        generation.openRequest = nil
        guard MapStore.shared.map(id) != nil else { return }
        if isBlurActive { closePaywall() }
        closeSidebar()
        closeOverlays()
        generatingJobID = nil
        isMindActive = false
        openMapID = id
    }

    private func openSidebar() {
        withAnimation(.easeInOut(duration: 0.3)) {
            isSidebarActive = true
            sidebarOffset = 0
        }
    }

    private func closeSidebar() {
        withAnimation(.easeInOut(duration: 0.3)) {
            isSidebarActive = false
            sidebarOffset = -UIScreen.main.bounds.width
        }
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

// A full-screen layer: modal for VoiceOver when on top, hidden from it when covered.
private struct TopLayer: ViewModifier {
    let isTop: Bool

    func body(content: Content) -> some View {
        content
            .accessibilityAddTraits(isTop ? .isModal : [])
            .accessibilityHidden(!isTop)
    }
}
