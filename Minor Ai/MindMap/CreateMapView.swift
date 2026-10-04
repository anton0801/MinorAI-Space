//
//  CreateMapView.swift
//  Minor Ai
//
//  Start a Map (Mind mode): source tiles, recent maps and the topic field.
//  Background, haze and glow come from the home screen behind it.
//

import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct CreateMapView: View {
    let theme: AppTheme
    let conversations: [Conversation]
    // False while the screen is hidden behind the home screen (it stays in the hierarchy).
    var isActive: Bool = true
    var onClose: () -> Void
    var onOpenSidebar: () -> Void
    var onUpgrade: () -> Void
    var onUpgradePro: () -> Void = {}
    var onStart: (MapInput, AIModelOption) -> Void
    var onOpenMap: (UUID) -> Void
    var onAskAssistant: (String) -> Void = { _ in }
    var onNewDeck: () -> Void = {}

    @ObservedObject private var store = MapStore.shared
    @ObservedObject private var account = AccountStore.shared
    @ObservedObject private var network = NetworkMonitor.shared
    @State private var text = ""
    @State private var attachment: MapInput?
    @State private var showChatPicker = false
    @State private var notice: String?
    @State private var noticeIsLimit = false
    @State private var showConsent = false
    @State private var canPaste = false
    @State private var showToday = false
    @State private var showTemplates = false
    @State private var showScanChoice = false
    @State private var showScanner = false
    @State private var showScanPhotos = false
    @State private var scanPhotos: [PhotosPickerItem] = []
    @State private var reading = false
    @AppStorage("mapModel") private var mapModelID = AIModelCatalog.defaultMap.apiModelID
    @StateObject private var voice = VoiceRecorder()
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var fieldFocused: Bool

    private enum Tile: CaseIterable {
        case topic, document, link, youtube, voice, scan, chat, template

        var icon: String {
            switch self {
            case .topic: return "textformat"
            case .document: return "doc.text"
            case .link: return "link"
            case .youtube: return "play.rectangle"
            case .voice: return "mic"
            case .scan: return "doc.viewfinder"
            case .chat: return "bubble.left"
            case .template: return "square.grid.2x2"
            }
        }
        var title: String {
            switch self {
            case .topic: return L("Topic")
            case .document: return L("Document")
            case .link: return L("Link")
            case .youtube: return L("YouTube")
            case .voice: return L("Voice")
            case .scan: return L("Scan")
            case .chat: return L("From Chat")
            case .template: return L("Template")
            }
        }
        var caption: String {
            switch self {
            case .topic: return L("Type any subject")
            case .document: return L("PDF, TXT or RTF")
            case .link: return L("Article or web page")
            case .youtube: return L("Video transcript")
            case .voice: return L("Talk it through")
            case .scan: return L("Notes, slides, a whiteboard")
            case .chat: return L("Turn a chat into a map")
            case .template: return L("Ready structures")
            }
        }
        var needsPlus: Bool { self == .youtube || self == .voice }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onOpenSidebar) {
                    Image("Slider").resizable().scaledToFit().frame(width: 25, height: 25).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Your Maps")
                Spacer()
                Button(action: onUpgrade) {
                    HStack(spacing: 5) {
                        Image("minlogo").resizable().scaledToFit().frame(width: 28, height: 28)
                        Text("Minor Plus").font(.system(size: 16)).foregroundColor(.white)
                    }
                    .padding(.trailing, 8)
                    .frame(width: 130, height: 35)
                    .background(Capsule().fill(theme.chatRectangle))
                    .overlay(Capsule().stroke(theme.chatStroke, lineWidth: 1))
                }
                .opacity(account.isPaid ? 0 : 1)
                .allowsHitTesting(!account.isPaid)
                .accessibilityHidden(account.isPaid)
                .accessibilityLabel("Get Minor Plus")
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 14)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Start a Map")
                        .font(.system(size: 22, weight: .bold))
                    Text("Pick a source or just type a topic.")
                        .font(.system(size: 15))
                        .foregroundColor(MinorColor.textSecondary)
                        .padding(.top, 4)
                        .padding(.bottom, 20)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(Tile.allCases, id: \.self) { tile in
                            tileView(tile)
                        }
                    }

                    HStack(spacing: 10) {
                        shortcut("calendar", L("Today"), detail: todayDetail, highlight: TaskAgenda.dueCount(in: store.maps) > 0) { showToday = true }
                        shortcut("rectangle.on.rectangle.angled", L("Slides"), detail: L("AI presentation")) { onNewDeck() }
                    }
                    .padding(.top, 12)

                    if !store.maps.isEmpty {
                        Text("RECENT")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(MinorColor.textTertiary)
                            .padding(.top, 24)
                            .padding(.bottom, 10)
                        VStack(spacing: 8) {
                            ForEach(store.maps.prefix(2)) { map in
                                Button {
                                    voice.cancel()
                                    onOpenMap(map.id)
                                } label: { MapCardView(map: map) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 16)
            }

            VStack(spacing: 8) {
                if !network.isOnline {
                    Text("You’re offline. Maps need a connection to generate.")
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(MinorColor.danger.opacity(0.25)))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(MinorColor.danger.opacity(0.6), lineWidth: 1))
                }
                if let notice {
                    HStack(spacing: 10) {
                        Text(notice).font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading)
                        if noticeIsLimit {
                            Button("Get Minor Plus", action: onUpgrade).font(.system(size: 13, weight: .semibold))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(theme.chatRectangle))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.chatStroke, lineWidth: 1))
                }
                if account.isOverFreeLimit {
                    UsageMeterView()
                    Text("You’ve used \(account.freeMapLimit) of \(account.freeMapLimit) free maps this month. They come back on \(account.resetDateText).")
                        .font(.system(size: 13))
                        .foregroundColor(MinorColor.textSecondary)
                        .multilineTextAlignment(.center)
                    Button(action: onUpgrade) {
                        Text("Get Minor Plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Capsule().fill(MinorColor.sendFill))
                    }
                } else {
                    composer
                }
                Button(action: onClose) {
                    Image(systemName: "house.fill").font(.system(size: 26)).foregroundColor(.white).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Home")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
        }
        .foregroundColor(MinorColor.textPrimary)
        .onReceive(GenerationCenter.shared.$todayRequest) { requested in
            guard requested else { return }
            GenerationCenter.shared.todayRequest = false
            showTemplates = false
            showToday = true
        }
        .confirmationDialog("Scan", isPresented: $showScanChoice, titleVisibility: .hidden) {
            if DocumentScanner.isAvailable {
                Button("Scan with Camera") { showScanner = true }
            }
            Button("Choose Photos") { showScanPhotos = true }
            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScanner { pages in
                showScanner = false
                readScans(pages)
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showScanPhotos, selection: $scanPhotos, maxSelectionCount: 10, matching: .images)
        .onChange(of: scanPhotos) { items in
            guard !items.isEmpty else { return }
            Task {
                var pages: [UIImage] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = await Task.detached(priority: .userInitiated, operation: { Attachments.downsampled(data, maxPixels: 2_500) }).value {
                        pages.append(image)
                    }
                }
                scanPhotos = []
                readScans(pages)
            }
        }
        .overlay {
            if reading {
                ZStack {
                    Color.black.opacity(0.6).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView().tint(.white)
                        Text("Reading the text…").font(.system(size: 15, weight: .medium))
                    }
                    .padding(24)
                    .background(RoundedRectangle(cornerRadius: 18).fill(theme.chatRectangle))
                }
            }
        }
        .sheet(isPresented: $showToday) {
            TodayView(theme: theme, onOpen: { mapID, nodeID in
                GenerationCenter.shared.focusNode = nodeID
                onOpenMap(mapID)
            }, onAsk: {
                showToday = false
                onAskAssistant(L("Plan my day: look at my tasks and deadlines and make a short plan for today, most important first."))
            }, onStudy: { mapID in
                GenerationCenter.shared.studyRequest = mapID
                onOpenMap(mapID)
            })
        }
        .sheet(isPresented: $showTemplates) {
            TemplatesView(theme: theme) { template in createFromTemplate(template) }
        }
        .sheet(isPresented: $showConsent) {
            AIConsentView(
                onAllow: {
                    showConsent = false
                    start()
                },
                onDecline: { showConsent = false }
            )
        }
        .sheet(isPresented: $showChatPicker) {
            ChatPickerView(conversations: conversations, theme: theme) { conversation in
                showChatPicker = false
                // Only what the person and the assistant said: not the hidden app data the
                // assistant reads (map outlines, task lists), and not empty picture messages.
                let transcript = conversation.messages
                    .filter { !$0.isHidden && !$0.text.isEmpty }
                    .map { "\($0.role == .user ? "User" : "Assistant"): \($0.text)" }
                    .joined(separator: "\n\n")
                attachment = .text(transcript, source: MapSource(kind: .chat, label: conversation.title))
            }
        }
        .task { await account.refresh() }
        .onAppear {
            voice.onAutoFinish = { heard in finish(heard) }
            canPaste = UIPasteboard.general.hasStrings || UIPasteboard.general.hasURLs
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-demoToday") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { showToday = true }
            }
            if ProcessInfo.processInfo.arguments.contains("-demoTemplates") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { showTemplates = true }
            }
            if ProcessInfo.processInfo.arguments.contains("-demoImport") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { tap(.document) }
            }
            #endif
        }
        .onChange(of: isActive) { active in
            if active {
                canPaste = UIPasteboard.general.hasStrings || UIPasteboard.general.hasURLs
                Task { await account.refresh() }
            } else {
                keepVoiceNote()
                fieldFocused = false
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background { keepVoiceNote() }
            if phase == .active { canPaste = UIPasteboard.general.hasStrings || UIPasteboard.general.hasURLs }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in
            canPaste = UIPasteboard.general.hasStrings || UIPasteboard.general.hasURLs
        }
        .onChange(of: text) { value in
            // A long paste is material to map, not a topic.
            guard value.count > 300, Self.link(in: value) == nil else { return }
            attachment = .text(value, source: MapSource(kind: .document, label: L("Pasted text")))
            text = ""
        }
        .onDisappear { voice.cancel() }
    }

    // MARK: - Tiles

    private func tileView(_ tile: Tile) -> some View {
        let locked = tile.needsPlus && !account.isPaid
        let active = isActive(tile)
        return Button { tap(tile) } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: tile.icon).font(.system(size: 20)).frame(height: 24, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tile.title).font(.system(size: 15, weight: .medium))
                    Text(tile.caption).font(.system(size: 12)).foregroundColor(MinorColor.textTertiary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(theme.chatRectangle))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(active ? MinorColor.accent : theme.chatStroke, lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                if locked {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill").font(.system(size: 10))
                        Text("Plus").font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(MinorColor.textSecondary)
                    .padding(12)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func isActive(_ tile: Tile) -> Bool {
        switch attachment {
        case .some(.text(_, let source)):
            return (tile == .document && source.kind == .document) || (tile == .chat && source.kind == .chat) || (tile == .scan && source.kind == .scan)
        case .some(.link): return tile == .link
        case .some(.youtube): return tile == .youtube
        default:
            if voice.state == .listening { return tile == .voice }
            if let url = linkInText { return tile == (Self.isYouTube(url) ? .youtube : .link) }
            return tile == .topic && attachment == nil
        }
    }

    private func tap(_ tile: Tile) {
        notice = nil
        // Every tile starts a new map: with this month's free maps used up, the paywall opens.
        if account.isOverFreeLimit { return onUpgrade() }
        switch tile {
        case .topic:
            attachment = nil
            fieldFocused = true
        case .document:
            DocumentPicker.present { importDocument($0) }
        case .link:
            attachment = nil
            if text.isEmpty { text = "https://" }
            fieldFocused = true
        case .youtube:
            guard account.isPaid else { return onUpgrade() }
            attachment = nil
            fieldFocused = true
            if linkInText.map(Self.isYouTube) != true { show(L("Paste a YouTube link into the field.")) }
        case .voice:
            guard account.isPaid else { return onUpgrade() }
            guard voice.state != .starting, voice.state != .listening, voice.state != .finishing else { return }
            fieldFocused = false
            attachment = nil
            Task {
                await voice.start()
                switch voice.state {
                case .denied: show(L("Allow microphone and speech recognition for Minor in Settings to talk through an idea."))
                case .failed: show(L("Voice input isn’t available right now. Check that no other app is using the microphone."))
                default: break
                }
            }
        case .scan:
            showScanChoice = true
        case .template:
            showTemplates = true
        case .chat:
            if conversations.isEmpty {
                show(L("No chats yet. Start one from the home screen."))
            } else {
                showChatPicker = true
            }
        }
    }

    // MARK: - Field

    private var linkInText: URL? { Self.link(in: text) }

    @ViewBuilder
    private var composer: some View {
        if voice.state == .listening {
            listeningBar
        } else {
            modelPicker
            fieldBar
        }
    }

    // The model that builds the map; the plan's choice falls back to the standard one.
    private var mapModel: AIModelOption {
        let chosen = AIModelCatalog.option(apiID: mapModelID) ?? AIModelCatalog.defaultMap
        return account.allowsMaps(with: chosen) ? chosen : AIModelCatalog.defaultMap
    }

    // Standard models for everyone; Claude Opus with Plus; GPT-6 Astra and Claude Fable with PRO.
    private var modelPicker: some View {
        Menu {
            ForEach(AIModelCatalog.mapModels) { model in
                Button {
                    if account.allowsMaps(with: model) {
                        mapModelID = model.apiModelID
                    } else if model.mapPlan == .pro {
                        onUpgradePro()
                    } else {
                        onUpgrade()
                    }
                } label: {
                    if model == mapModel {
                        Label(model.displayName, systemImage: "checkmark")
                    } else if !account.allowsMaps(with: model) {
                        Label("\(model.displayName) · \(model.mapPlan == .pro ? "PRO" : "Plus")", systemImage: "lock.fill")
                    } else {
                        Text(model.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "cpu").font(.system(size: 12))
                Text(mapModel.displayName).font(.system(size: 13))
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10))
            }
            .foregroundColor(MinorColor.textSecondary)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .overlay(Capsule().stroke(theme.chatStroke, lineWidth: 1))
            .contentShape(Capsule())
        }
        .accessibilityLabel("Map model: \(mapModel.displayName)")
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var listeningBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(voice.transcript.isEmpty ? L("Listening…") : voice.transcript)
                    .font(.system(size: 15))
                    .lineLimit(1)
                    .truncationMode(.head)
                Text(String(format: "%d:%02d", Int(voice.elapsed) / 60, Int(voice.elapsed) % 60))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundColor(MinorColor.textTertiary)
            }
            Spacer(minLength: 8)
            HStack(spacing: 3) {
                ForEach(0..<7, id: \.self) { i in
                    Capsule()
                        .fill(MinorColor.textPrimary)
                        .frame(width: 3, height: 6 + voice.level * CGFloat([10, 18, 26, 20, 26, 14, 8][i]))
                }
            }
            .animation(.easeOut(duration: 0.12), value: voice.level)
            .accessibilityHidden(true)
            Button(action: finishVoice) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.black)
                    .frame(width: 12, height: 12)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(MinorColor.sendFill))
            }
            .accessibilityLabel("Stop and build map")
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .frame(height: 60)
        .minorSurface(theme)
    }

    private func finishVoice() {
        Task { finish(await voice.finish()) }
    }

    // Leaving the screen or the app stops the microphone but keeps what was said as the source,
    // ready to build when the person comes back.
    private func keepVoiceNote() {
        guard voice.state == .listening || voice.state == .starting else { return }
        let heard = voice.stop()
        if heard.count > 3 {
            attachment = .text(heard, source: MapSource(kind: .voice, label: L("Voice note")))
        }
    }

    private func finish(_ heard: String) {
        guard heard.count > 3 else {
            show(L("Didn’t catch that. Try again."))
            return
        }
        // Kept as the source, so nothing is lost if AI consent is still needed.
        attachment = .text(heard, source: MapSource(kind: .voice, label: L("Voice note")))
        start()
    }

    private var fieldBar: some View {
        HStack(spacing: 10) {
            if let chip = attachmentChip {
                HStack(spacing: 6) {
                    Image(systemName: chip.icon).font(.system(size: 13))
                    Text(chip.label).font(.system(size: 14)).lineLimit(1)
                    Button { attachment = nil } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .bold)) }
                        .accessibilityLabel("Remove source")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(theme.chatStroke, lineWidth: 1))
                Spacer(minLength: 0)
            } else {
                TextField("", text: $text)
                    .placeholder(when: text.isEmpty) {
                        Text("Map any topic or paste a link").foregroundColor(theme.placeholderText)
                    }
                    .font(.system(size: 17))
                    .focused($fieldFocused)
                    .submitLabel(.go)
                    .onSubmit(start)
                    .textInputAutocapitalization(.sentences)
                    .accessibilityLabel("Topic or link")
                if canPaste && (text.isEmpty || text == "https://") {
                    // The system Paste button reads the clipboard without the "Allow Paste" prompt.
                    PasteButton(payloadType: String.self) { strings in
                        guard let pasted = strings.first?.trimmingCharacters(in: .whitespacesAndNewlines), !pasted.isEmpty else { return }
                        Task { @MainActor in text = pasted }
                    }
                    .labelStyle(.iconOnly)
                    .buttonBorderShape(.capsule)
                    .tint(theme.chatStroke)
                }
            }
            Button(action: start) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.black)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(MinorColor.sendFill))
            }
            .disabled(!canStart)
            .opacity(canStart ? 1 : 0.4)
            .accessibilityLabel("Build Map")
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .frame(height: 60)
        .minorSurface(theme)
    }

    private var attachmentChip: (icon: String, label: String)? {
        switch attachment {
        case .some(.link(let url)):
            return ("link", URL(string: url)?.host ?? url)
        case .some(.youtube):
            return ("play.rectangle", L("YouTube video"))
        case .some(.text(_, let source)):
            return (source.kind == .chat ? "bubble.left" : "doc.text", source.label)
        default:
            return nil
        }
    }

    private var canStart: Bool {
        guard network.isOnline else { return false }
        return attachment != nil || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text != "https://"
    }

    private func start() {
        guard canStart else { return }
        // Building a map needs an account; the topic, link or recording waits in place.
        guard AuthService.shared.isSignedIn else {
            fieldFocused = false
            return AuthGate.shared.require { start() }
        }
        // Ask for AI consent here, so the topic, link or recording stays in place if it's declined.
        guard AIConsent.isGiven else {
            fieldFocused = false
            showConsent = true
            return
        }
        fieldFocused = false
        if let attachment {
            onStart(attachment, mapModel)
        } else if let url = linkInText {
            if Self.isYouTube(url) {
                guard account.isPaid else { return onUpgrade() }
                onStart(.youtube(url.absoluteString), mapModel)
            } else {
                onStart(.link(url.absoluteString), mapModel)
            }
        } else {
            onStart(.topic(text.trimmingCharacters(in: .whitespacesAndNewlines)), mapModel)
        }
        text = ""
        attachment = nil
    }

    private func show(_ message: String, isLimit: Bool = false) {
        notice = message
        noticeIsLimit = isLimit
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { if notice == message { notice = nil } }
    }

    // MARK: - Scans

    // Text recognized on the phone; the map is built from it like from a document.
    private func readScans(_ pages: [UIImage]) {
        guard !pages.isEmpty else { return }
        reading = true
        Task {
            let text = await TextRecognizer.text(from: pages)
            reading = false
            guard text.trimmingCharacters(in: .whitespacesAndNewlines).count > 20 else {
                return show(L("No text found in these pictures. Try a sharper photo with more light."))
            }
            attachment = .text(text, source: MapSource(kind: .scan, label: pages.count == 1 ? L("Scan") : L("Scan · \(pages.count) pages")))
        }
    }

    // MARK: - Today and templates

    // A template map counts as one of the month's maps (checked on the server, like AI maps).
    private func createFromTemplate(_ template: MapTemplate) {
        guard AuthService.shared.isSignedIn else { return AuthGate.shared.require { createFromTemplate(template) } }
        if account.isOverFreeLimit { return onUpgrade() }
        Task {
            do {
                try await MapService.shared.countNewMap()
                account.noteMapCreated()
                let map = template.makeMap()
                store.save(map)
                onOpenMap(map.id)
            } catch BackendError.limitReached(let kind) {
                account.noteLimitReached(kind: kind)
                onUpgrade()
            } catch {
                show((error as? LocalizedError)?.errorDescription ?? L("Something went wrong. Try again."))
            }
        }
    }

    private var todayDetail: String {
        let due = TaskAgenda.dueCount(in: store.maps)
        return due > 0 ? L("\(due) tasks due") : L("Tasks and deadlines")
    }

    private func shortcut(_ icon: String, _ title: String, detail: String, highlight: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(highlight ? MinorColor.accent : MinorColor.textPrimary)
                    .frame(height: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .semibold))
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundColor(highlight ? MinorColor.accent : MinorColor.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
            .foregroundColor(MinorColor.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(theme.chatRectangle))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(highlight ? MinorColor.accent.opacity(0.6) : theme.chatStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Documents

    private func importDocument(_ url: URL) {
        let isPaid = account.isPaid
        Task {
            do {
                let document = try await Attachments.loadDocument(at: url, maxPages: isPaid ? 300 : 10)
                attachment = .text(document.text, source: MapSource(kind: .document, label: document.name))
            } catch {
                let tooLong: Bool
                if case Attachments.DocumentError.tooLong = error { tooLong = true } else { tooLong = false }
                show(Attachments.message(for: error, isPaid: isPaid), isLimit: tooLong && !isPaid)
            }
        }
    }

    static func isYouTube(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host == "youtu.be" || host.hasSuffix("youtube.com")
    }

    static func link(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(" "), trimmed.count > 8,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue),
              let match = detector.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              match.range.length == (trimmed as NSString).length
        else { return nil }
        return match.url
    }
}

extension MapInput: Equatable {
    static func == (lhs: MapInput, rhs: MapInput) -> Bool {
        switch (lhs, rhs) {
        case (.topic(let a), .topic(let b)): return a == b
        case (.link(let a), .link(let b)): return a == b
        case (.youtube(let a), .youtube(let b)): return a == b
        case (.text(let a, let s), .text(let b, let t)): return a == b && s == t
        default: return false
        }
    }
}

struct ChatPickerView: View {
    let conversations: [Conversation]
    let theme: AppTheme
    var onPick: (Conversation) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Turn a Chat Into a Map")
                .font(.system(size: 20, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(conversations) { conversation in
                        Button { onPick(conversation) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(conversation.title).font(.system(size: 16, weight: .medium)).lineLimit(1)
                                Text(conversation.updatedAt, style: .date).font(.system(size: 12)).foregroundColor(MinorColor.textTertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(MinorColor.fillRow))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .foregroundColor(MinorColor.textPrimary)
        .padding(.horizontal, 20)
        .background(MinorColor.sheet.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }
}
