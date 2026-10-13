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
    // False while the screen is covered (a map, a chat or the Building screen on top of it).
    var isActive: Bool = true
    var onUpgrade: () -> Void
    var onUpgradePro: () -> Void = {}
    var onStart: (MapInput, AIModelOption) -> Void
    var onOpenMap: (UUID) -> Void
    var onToday: () -> Void = {}
    var onAllMaps: () -> Void = {}
    var onTemplates: () -> Void = {}

    @ObservedObject private var store = MapStore.shared
    @ObservedObject private var account = AccountStore.shared
    @ObservedObject private var network = NetworkMonitor.shared
    @ObservedObject private var recents = RecentDocuments.shared
    @State private var text = ""
    @State private var attachment: MapInput?
    @State private var showChatPicker = false
    @State private var notice: String?
    @State private var noticeIsLimit = false
    @State private var showConsent = false
    @State private var canPaste = false
    @State private var showOptions = false
    @State private var showScanChoice = false
    @State private var showScanner = false
    @State private var showScanPhotos = false
    @State private var scanPhotos: [PhotosPickerItem] = []
    @State private var reading = false
    @AppStorage("mapModel") private var mapModelID = AIModelCatalog.defaultMap.apiModelID
    @StateObject private var voice = VoiceRecorder()
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var fieldFocused: Bool

    // The ways to start a map besides typing a topic.
    private enum Tile: CaseIterable {
        case document, link, youtube, voice, scan, chat

        var icon: String {
            switch self {
            case .document: return "doc.text"
            case .link: return "link"
            case .youtube: return "play.rectangle"
            case .voice: return "mic"
            case .scan: return "doc.viewfinder"
            case .chat: return "bubble.left"
            }
        }
        var title: String {
            switch self {
            case .document: return L("Document")
            case .link: return L("Link")
            case .youtube: return L("YouTube")
            case .voice: return L("Voice")
            case .scan: return L("Scan")
            case .chat: return L("From Chat")
            }
        }
        var caption: String {
            switch self {
            case .document: return L("PDF, TXT, RTF")
            case .link: return L("Article or website")
            case .youtube: return L("Video subtitles")
            case .voice: return L("Record a thought")
            case .scan: return L("Photo of your notes")
            case .chat: return L("Pick a conversation")
            }
        }
        var needsPlus: Bool { self == .youtube || self == .voice }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Start from a topic or material.")
                    .minorFont(15, maxScale: 1.4)
                    .foregroundColor(MinorColor.textSecondary)
                    .padding(.bottom, 16)

                if !network.isOnline {
                    banner(L("You’re offline. Maps need a connection to generate."), danger: true)
                        .padding(.bottom, 10)
                }
                if let notice {
                    HStack(spacing: 10) {
                        Text(notice).minorFont(13, style: .footnote, maxScale: 1.4).frame(maxWidth: .infinity, alignment: .leading)
                        if noticeIsLimit {
                            Button("Get Minor Plus", action: onUpgrade).font(.system(size: 13, weight: .semibold))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(theme.chatRectangle))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.chatStroke, lineWidth: 1))
                    .padding(.bottom, 10)
                }

                if account.isOverFreeLimit {
                    limitCard
                } else if voice.state == .listening {
                    listeningBar
                } else {
                    topicCard
                }

                optionsRow.padding(.top, 12)

                Text("From Material")
                    .minorFont(17, .semibold, maxScale: 1.3)
                    .padding(.top, 26)
                    .padding(.bottom, 12)
                    .accessibilityAddTraits(.isHeader)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(Tile.allCases, id: \.self) { tile in
                        tileView(tile)
                    }
                }

                templatesRow.padding(.top, 10)

                if let recent = recentMap {
                    HStack {
                        Text("Recently").minorFont(17, .semibold, maxScale: 1.3).accessibilityAddTraits(.isHeader)
                        Spacer()
                        Button(action: onAllMaps) {
                            HStack(spacing: 4) {
                                Text("All Maps")
                                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                            }
                            .minorFont(14, .medium, maxScale: 1.3)
                            .foregroundColor(MinorColor.accent)
                            .frame(minHeight: 44)
                        }
                    }
                    .padding(.top, 22)
                    Button {
                        voice.cancel()
                        onOpenMap(recent.id)
                    } label: { MapCardView(map: recent) }
                        .buttonStyle(PressScale())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(theme.background.ignoresSafeArea())
        .foregroundColor(MinorColor.textPrimary)
        .navigationTitle(Text("New Map"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: onToday) { Label("Today", systemImage: "calendar") }
                    Button(action: onAllMaps) { Label("Library", systemImage: "books.vertical") }
                    Button(action: onTemplates) { Label("Templates", systemImage: "square.grid.2x2") }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.system(size: 17))
                }
                .accessibilityLabel("More")
            }
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
                .accessibilityElement(children: .combine)
            }
        }
        .sheet(isPresented: $showOptions) {
            MapOptionsSheet(theme: theme, selection: $mapModelID, onUpgrade: onUpgrade, onUpgradePro: onUpgradePro)
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
        // A map stopped or failed while being made: what was typed or picked comes back to edit.
        .onReceive(GenerationCenter.shared.$returnedInput) { input in
            guard let input else { return }
            DispatchQueue.main.async { GenerationCenter.shared.returnedInput = nil }
            switch input {
            case .topic(let topic):
                text = topic
                attachment = nil
            case .link(let url), .youtube(let url):
                text = url
                attachment = nil
            case .text:
                text = ""
                attachment = input
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { fieldFocused = true }
        }
    }

    // The map opened last (or edited last), offered to continue.
    private var recentMap: MindMap? {
        guard let entry = recents.latest(1, maps: store.maps, decks: []).first else { return nil }
        return store.map(entry.id)
    }

    private func banner(_ text: String, danger: Bool) -> some View {
        Text(text)
            .minorFont(13, style: .footnote, maxScale: 1.4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(MinorColor.danger.opacity(0.25)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(MinorColor.danger.opacity(0.6), lineWidth: 1))
    }

    private var limitCard: some View {
        VStack(spacing: 10) {
            UsageMeterView()
            Text("You’ve used \(account.freeMapLimit) of \(account.freeMapLimit) free maps this month. They come back on \(account.resetDateText).")
                .minorFont(13, style: .footnote, maxScale: 1.4)
                .foregroundColor(MinorColor.textSecondary)
                .multilineTextAlignment(.center)
            Button(action: onUpgrade) {
                Text("Get Minor Plus")
                    .minorFont(16, .semibold, maxScale: 1.3)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Capsule().fill(MinorColor.sendFill))
            }
        }
    }

    // "Map Options": the model that builds the map, in its own sheet.
    private var optionsRow: some View {
        Button { showOptions = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "slider.horizontal.3").font(.system(size: 16)).frame(width: 24)
                Text("Map Options").minorFont(16, maxScale: 1.4)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundColor(MinorColor.textTertiary)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(RoundedRectangle(cornerRadius: 14).fill(theme.chatRectangle))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.chatStroke, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Map Options, model \(mapModel.displayName)"))
    }

    private var templatesRow: some View {
        Button(action: onTemplates) {
            HStack(spacing: 12) {
                Image(systemName: "square.grid.2x2").font(.system(size: 18)).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Templates").minorFont(15, .medium, maxScale: 1.4)
                    Text("Ready structure").minorFont(12, style: .caption1, maxScale: 1.4).foregroundColor(MinorColor.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundColor(MinorColor.textTertiary)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 56)
            .background(RoundedRectangle(cornerRadius: 14).fill(theme.chatRectangle))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.chatStroke, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .accessibilityElement(children: .combine)
    }

    // MARK: - Tiles

    private func tileView(_ tile: Tile) -> some View {
        let locked = tile.needsPlus && !account.isPaid
        let active = isActive(tile)
        return Button { tap(tile) } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: tile.icon).font(.system(size: 19)).frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tile.title).minorFont(14, .medium, maxScale: 1.4).fixedSize(horizontal: false, vertical: true)
                    Text(tile.caption)
                        .minorFont(11, style: .caption2, maxScale: 1.4)
                        .foregroundColor(MinorColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 14).fill(theme.chatRectangle))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(active ? MinorColor.accent : theme.chatStroke, lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                if locked {
                    HStack(spacing: 3) {
                        Image(systemName: "lock.fill").font(.system(size: 9))
                        Text("Plus").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(MinorColor.textSecondary)
                    .padding(8)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(PressScale())
        .accessibilityElement(children: .combine)
        .accessibilityValue(locked ? Text("Minor Plus") : Text(""))
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func isActive(_ tile: Tile) -> Bool {
        switch attachment {
        case .some(.text(_, let source)):
            return (tile == .document && source.kind == .document) || (tile == .chat && source.kind == .chat) || (tile == .scan && source.kind == .scan) || (tile == .voice && source.kind == .voice)
        case .some(.link): return tile == .link
        case .some(.youtube): return tile == .youtube
        default:
            if voice.state == .listening { return tile == .voice }
            if let url = linkInText { return tile == (Self.isYouTube(url) ? .youtube : .link) }
            return false
        }
    }

    private func tap(_ tile: Tile) {
        notice = nil
        // Every tile starts a new map: with this month's free maps used up, the paywall opens.
        if account.isOverFreeLimit { return onUpgrade() }
        switch tile {
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

    // The model that builds the map; the plan's choice falls back to the standard one.
    private var mapModel: AIModelOption {
        let chosen = AIModelCatalog.option(apiID: mapModelID) ?? AIModelCatalog.defaultMap
        return account.allowsMaps(with: chosen) ? chosen : AIModelCatalog.defaultMap
    }

    private var listeningBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(voice.transcript.isEmpty ? L("Listening…") : voice.transcript)
                    .font(.system(size: 15))
                    .lineLimit(2)
                    .truncationMode(.head)
                Text(String(format: "%d:%02d", Int(voice.elapsed) / 60, Int(voice.elapsed) % 60) + " · " + L("The recording stays on this iPhone"))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundColor(MinorColor.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
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
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Stop and build map")
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(minHeight: 72)
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
        if heard.count > 3 { attachVoice(heard) }
    }

    private func finish(_ heard: String) {
        guard heard.count > 3 else {
            voice.discardRecording()
            show(L("Didn’t catch that. Try again."))
            return
        }
        // Kept as the source, so nothing is lost if AI consent is still needed.
        attachVoice(heard)
        start()
    }

    // The recording becomes the material's original, its words timed passages.
    private func attachVoice(_ heard: String) {
        let draft = SourceImport.voice(heard, recording: voice.recording)
        voice.discardRecording()
        SourceDrafts.shared.put(draft, for: heard)
        attachment = .text(heard, source: MapSource(kind: .voice, label: L("Voice note")))
    }

    // The topic field first; a picked source shows in its place with a way to remove it.
    private var topicCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let chip = attachmentChip {
                HStack(spacing: 10) {
                    Image(systemName: chip.icon).font(.system(size: 16)).frame(width: 34, height: 34)
                        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.08)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(chip.label).minorFont(15, .medium, maxScale: 1.4).lineLimit(2)
                        Text(chip.kind).minorFont(12, style: .caption1, maxScale: 1.4).foregroundColor(MinorColor.textTertiary)
                    }
                    Spacer(minLength: 4)
                    Button { attachment = nil } label: {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .bold))
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.white.opacity(0.1)))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Remove source")
                }
            } else {
                TextField("", text: $text, axis: .vertical)
                    .placeholder(when: text.isEmpty, alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("What is the map about?").foregroundColor(MinorColor.textSecondary)
                            Text("For example, launching a podcast").minorFont(13, style: .footnote, maxScale: 1.4).foregroundColor(MinorColor.textTertiary)
                        }
                    }
                    .minorFont(17, maxScale: 1.4)
                    .lineLimit(1...4)
                    .focused($fieldFocused)
                    .submitLabel(.go)
                    .onSubmit(start)
                    .textInputAutocapitalization(.sentences)
                    .accessibilityLabel("Topic or link")
                if let url = linkInText {
                    Label(Self.isYouTube(url) ? L("YouTube video: subtitles become the map") : L("Link: \(url.host ?? url.absoluteString)"),
                          systemImage: Self.isYouTube(url) ? "play.rectangle" : "link")
                        .minorFont(13, style: .footnote, maxScale: 1.4)
                        .foregroundColor(MinorColor.accent)
                }
            }
            HStack(spacing: 10) {
                if attachment == nil && canPaste && (text.isEmpty || text == "https://") {
                    // The system Paste button reads the clipboard without the "Allow Paste" prompt.
                    PasteButton(payloadType: String.self) { strings in
                        guard let pasted = strings.first?.trimmingCharacters(in: .whitespacesAndNewlines), !pasted.isEmpty else { return }
                        Task { @MainActor in text = pasted }
                    }
                    .buttonBorderShape(.capsule)
                    .tint(theme.chatStroke)
                }
                Spacer(minLength: 0)
                Button(action: start) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.black)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(MinorColor.sendFill))
                        .frame(width: 44, height: 44)
                }
                .disabled(!canStart)
                .opacity(canStart ? 1 : 0.35)
                .accessibilityLabel("Build Map")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.top, 14)
        .padding(.bottom, 6)
        .frame(minHeight: 120, alignment: .top)
        .minorSurface(theme)
    }

    private var attachmentChip: (icon: String, label: String, kind: String)? {
        switch attachment {
        case .some(.link(let url)):
            return ("link", URL(string: url)?.host ?? url, L("Link"))
        case .some(.youtube):
            return ("play.rectangle", L("YouTube video"), L("YouTube"))
        case .some(.text(_, let source)):
            switch source.kind {
            case .chat: return ("bubble.left", source.label, L("Chat"))
            case .voice: return ("mic", source.label, L("Voice note"))
            case .scan: return ("doc.viewfinder", source.label, L("Scan"))
            default: return ("doc.text", source.label, L("Document"))
            }
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
            let label = pages.count == 1 ? L("Scan") : L("Scan · \(pages.count) pages")
            // The pages are kept as the original, with where each recognized line is.
            let draft = await SourceImport.scan(pages, name: L("Scan"))
            reading = false
            guard let draft else {
                return show(L("No text found in these pictures. Try a sharper photo with more light."))
            }
            SourceDrafts.shared.put(draft, for: draft.text)
            if let problem = draft.originalError { show(problem) }
            attachment = .text(draft.text, source: MapSource(kind: .scan, label: label))
        }
    }

    // MARK: - Documents

    private func importDocument(_ url: URL) {
        let isPaid = account.isPaid
        Task {
            do {
                let document = try await Attachments.loadDocument(at: url, maxPages: isPaid ? 300 : 10)
                // The file is kept as the original while it can still be read.
                let draft = await Task.detached(priority: .userInitiated) {
                    SourceImport.document(at: url, text: document.text, pages: document.pages)
                }.value
                SourceDrafts.shared.put(draft, for: document.text)
                if let problem = draft.originalError { show(problem) }
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

// Map Options: the model that builds new maps. Standard models for everyone, Claude Opus with
// Plus, GPT-6 Astra and Claude Fable with PRO. The choice is kept for the next map.
struct MapOptionsSheet: View {
    let theme: AppTheme
    @Binding var selection: String
    var onUpgrade: () -> Void
    var onUpgradePro: () -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var account = AccountStore.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Model")
                        .textCase(.uppercase)
                        .minorFont(13, .semibold, style: .footnote, maxScale: 1.3)
                        .foregroundColor(MinorColor.textTertiary)
                        .padding(.bottom, 2)
                    ForEach(AIModelCatalog.mapModels) { model in
                        row(model)
                    }
                    Text("Stronger models write deeper maps and use more of the monthly AI allowance.")
                        .minorFont(13, style: .footnote, maxScale: 1.4)
                        .foregroundColor(MinorColor.textSecondary)
                        .padding(.top, 8)
                }
                .padding(20)
            }
            .background(MinorColor.sheet.ignoresSafeArea())
            .navigationTitle(Text("Map Options"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundColor(.white)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }

    private var current: String {
        let chosen = AIModelCatalog.option(apiID: selection) ?? AIModelCatalog.defaultMap
        return (account.allowsMaps(with: chosen) ? chosen : AIModelCatalog.defaultMap).apiModelID
    }

    private func row(_ model: AIModelOption) -> some View {
        let allowed = account.allowsMaps(with: model)
        let chosen = model.apiModelID == current
        return Button {
            if allowed {
                Haptics.selection()
                selection = model.apiModelID
            } else {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { model.mapPlan == .pro ? onUpgradePro() : onUpgrade() }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(chosen ? MinorColor.accent : MinorColor.textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName).minorFont(16, .medium, maxScale: 1.4).foregroundColor(allowed ? .white : MinorColor.textSecondary)
                    Text(model.mapPlan == .free ? L("Standard") : model.mapPlan == .plus ? L("Advanced") : L("Frontier"))
                        .minorFont(12, style: .caption1, maxScale: 1.4)
                        .foregroundColor(MinorColor.textTertiary)
                }
                Spacer()
                if !allowed {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill").font(.system(size: 10))
                        Text(model.mapPlan == .pro ? "PRO" : "Plus").font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(MinorColor.textSecondary)
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 56)
            .background(RoundedRectangle(cornerRadius: 14).fill(chosen ? Color.white.opacity(0.1) : MinorColor.fillRow))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(chosen ? MinorColor.accent.opacity(0.6) : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}
