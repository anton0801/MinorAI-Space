//
//  ChatView.swift
//  Minor Ai
//
//  Full-screen conversation view, styled to match the active sphere theme.
//  Answers render Markdown; any answer can be copied or turned into a mind map.
//

import PhotosUI
import SwiftUI

struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel
    let theme: AppTheme
    @Binding var model: AIModelOption
    var onHome: () -> Void
    var onMapThis: (String) -> Void = { _ in }
    var onUpgrade: () -> Void = {}

    @State private var draft: String = ""
    @State private var images: [Data] = []
    @State private var file: Attachments.Document?
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showPhotos = false
    @State private var attachError: String?
    @State private var imageMode = false
    @State private var viewer: ViewerItem?
    @State private var mentions: [MapMention] = []
    @State private var dictating = false
    @State private var voiceMode = false
    @ObservedObject private var speaker = Speaker.shared
    @FocusState private var inputFocused: Bool
    @ObservedObject private var mapStore = MapStore.shared

    private let accent = Color(red: 47/255, green: 255/255, blue: 158/255)

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                messages
                if let error = bannerError {
                    errorBanner(error)
                }
                if !images.isEmpty || file != nil {
                    attachmentsRow
                }
                if !mentionMatches.isEmpty {
                    MentionSuggestions(maps: mentionMatches, theme: theme, onPick: pickMention)
                }
                composer
            }
        }
        .photosPicker(isPresented: $showPhotos, selection: $photoItems, maxSelectionCount: 4, matching: .images)
        .onChange(of: photoItems) { items in loadPhotos(items) }
        .fullScreenCover(item: $viewer) { item in ImageViewer(item: item) }
        .fullScreenCover(isPresented: $voiceMode) {
            VoiceModeView(viewModel: viewModel, model: model, theme: theme) { voiceMode = false }
        }
        .onDisappear { speaker.stop() }
        #if DEBUG
        .onAppear { if ProcessInfo.processInfo.arguments.contains("-demoVoice") { voiceMode = true } }
        #endif
        .onChange(of: viewModel.restoredDraft?.id) { _ in
            // Consent was declined: the message and attachments go back into the field.
            guard !viewModel.messages.isEmpty, let restored = viewModel.restoredDraft else { return }
            draft = restored.text
            images = restored.images
            file = restored.file
            viewModel.restoredDraft = nil
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onHome) {
                Image(systemName: "house.fill")
                    .foregroundColor(.white)
                    .font(.system(size: 18))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Home")
            // Any model, any plan: the number shows how fast it uses the monthly AI allowance.
            Menu {
                ForEach(AIModelCatalog.all) { option in
                    Button {
                        model = option
                    } label: {
                        if option == model {
                            Label(option.displayName, systemImage: "checkmark")
                        } else {
                            Text("\(option.displayName)  ×\(option.usage)")
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(model.displayName)
                        .font(.system(size: 17, weight: .semibold))
                    Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(minHeight: 44)
            }
            .accessibilityLabel("AI model: \(model.displayName)")
            Spacer()
            Button {
                guard AuthService.shared.isSignedIn else { return AuthGate.shared.require { voiceMode = true } }
                Telemetry.log("voice_mode_start")
                voiceMode = true
            } label: {
                Image(systemName: "waveform")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(MinorColor.accent))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Voice Mode")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.messages.filter { !$0.isHidden }) { message in
                        bubble(for: message)
                            .id(message.id)
                    }
                    if viewModel.isSending {
                        typingIndicator
                            .id("typing")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.messages.count) { _ in
                scrollToBottom(proxy)
            }
            .onChange(of: viewModel.isSending) { _ in
                scrollToBottom(proxy)
            }
            .onAppear { scrollToBottom(proxy) }
        }
    }

    @ViewBuilder
    private func bubble(for message: ChatMessage) -> some View {
        let isUser = message.role == .user
        HStack {
            if isUser { Spacer(minLength: 40) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                if let images = message.images, !images.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(images.enumerated()), id: \.offset) { _, data in
                            if let image = UIImage(data: data) {
                                // Created images are shown larger; tap opens the full-screen viewer.
                                let side: CGFloat = isUser ? (images.count == 1 ? 180 : 84) : 240
                                Button {
                                    viewer = ViewerItem(image: image, isAI: !isUser, onReport: isUser ? nil : { viewModel.reportImage(message.id) })
                                } label: {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: side, height: side)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button { UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil) } label: { Label("Save to Photos", systemImage: "square.and.arrow.down") }
                                    if !isUser {
                                        Button(role: .destructive) { viewModel.reportImage(message.id) } label: { Label("Report", systemImage: "flag") }
                                    }
                                }
                            }
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(isUser ? "\(images.count) photo\(images.count == 1 ? "" : "s")" : "Image created with AI")
                }
                if let maps = message.maps, !maps.isEmpty {
                    ForEach(maps, id: \.self) { mention in
                        Button { viewModel.openMap(mention.id) } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: 13))
                                Text(mention.title).font(.system(size: 14)).lineLimit(1)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .overlay(RoundedRectangle(cornerRadius: 15).stroke(accent.opacity(0.6), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(mapStore.map(mention.id) == nil)
                        .accessibilityLabel("Open map \(mention.title)")
                    }
                }
                if message.tasksText != nil {
                    HStack(spacing: 6) {
                        Image(systemName: "checklist").font(.system(size: 13))
                        Text("Tasks attached").font(.system(size: 14)).lineLimit(1)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .overlay(RoundedRectangle(cornerRadius: 15).stroke(accent.opacity(0.6), lineWidth: 1))
                }
                if let action = message.action {
                    ActionCard(
                        action: action,
                        theme: theme,
                        canUndo: (action.kind == .edited || action.kind == .deckEdited) && action.undone != true && viewModel.canUndo(message.id),
                        mapExists: viewModel.targetExists(action),
                        onOpen: { viewModel.openTarget(action) },
                        onUndo: { viewModel.undoAction(message.id) },
                        onCreateImages: { viewModel.createImages(message.id) }
                    )
                }
                if let name = message.fileName {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text").font(.system(size: 13))
                        Text(name).font(.system(size: 14)).lineLimit(1)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .overlay(RoundedRectangle(cornerRadius: 15).stroke(theme.chatStroke, lineWidth: 1))
                }
                if !message.text.isEmpty {
                    Group {
                        if isUser {
                            Text(message.text)
                        } else {
                            MarkdownText(text: message.text)
                        }
                    }
                    .foregroundColor(.white)
                    .font(.system(size: 16))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isUser ? accent.opacity(0.18) : theme.chatRectangle)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(isUser ? accent.opacity(0.6) : theme.chatStroke, lineWidth: 1)
                            )
                    )
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = message.text
                        } label: { Label("Copy", systemImage: "doc.on.doc") }
                        if !isUser {
                            Button { toggleReading(message) } label: {
                                Label(speaker.speakingID == message.id ? "Stop Reading" : "Read Aloud", systemImage: speaker.speakingID == message.id ? "stop.fill" : "speaker.wave.2")
                            }
                        }
                        if !isUser && message.text.count >= 80 {
                            Button {
                                onMapThis(message.text)
                            } label: { Label("Map This", systemImage: "point.3.connected.trianglepath.dotted") }
                        }
                    }
                }
                if isUser, let reason = message.failed {
                    failureNote(message, reason: reason)
                }
                if !isUser, let used = message.model, used != model.apiModelID, let option = AIModelCatalog.option(apiID: used) {
                    Text("Answered by \(option.displayName)")
                        .font(.system(size: 12))
                        .foregroundColor(MinorColor.textTertiary)
                }
                if !isUser, !message.text.isEmpty, message.id == viewModel.messages.last(where: { !$0.isHidden })?.id {
                    Button { toggleReading(message) } label: {
                        Image(systemName: speaker.speakingID == message.id ? "stop.fill" : "speaker.wave.2")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 34, height: 30)
                            .overlay(RoundedRectangle(cornerRadius: 15).stroke(theme.chatStroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(speaker.speakingID == message.id ? "Stop Reading" : "Read Aloud")
                }
                if !isUser, message.id == viewModel.messages.last?.id, message.text.count > 120 {
                    Button { onMapThis(message.text) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles").font(.system(size: 12, weight: .semibold))
                            Text("Map This").font(.system(size: 14))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .overlay(RoundedRectangle(cornerRadius: 15).stroke(theme.chatStroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
            if !isUser { Spacer(minLength: 40) }
        }
    }

    private var typingIndicator: some View {
        HStack {
            TypingDots(color: theme.placeholderText)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(theme.chatRectangle)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(theme.chatStroke, lineWidth: 1)
                        )
                )
            Spacer(minLength: 40)
        }
        .accessibilityLabel("Minor is typing")
    }

    // A message that got no answer shows its reason under it with Retry; the banner is for other
    // problems, and for limits (it has the upgrade button).
    private var bannerError: String? {
        if let attachError { return attachError }
        guard let error = viewModel.errorMessage else { return nil }
        if !viewModel.limitReached, viewModel.messages.last(where: { !$0.isHidden })?.failed != nil { return nil }
        return error
    }

    private func retry(_ message: ChatMessage) {
        guard AuthService.shared.isSignedIn else {
            return AuthGate.shared.require { viewModel.retry(message.id, model: model) }
        }
        viewModel.retry(message.id, model: model)
    }

    private func failureNote(_ message: ChatMessage, reason: String) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            Label(reason, systemImage: "exclamationmark.circle")
                .font(.system(size: 12))
                .foregroundColor(MinorColor.dangerText)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
            if viewModel.canRetry(message.id) {
                Button { retry(message) } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .overlay(Capsule().stroke(MinorColor.dangerText.opacity(0.8), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(spacing: 10) {
            Text(text)
                .foregroundColor(.white)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
            if viewModel.limitReached && !AccountStore.shared.isPro {
                Button(AccountStore.shared.isPaid ? "Get PRO" : "Get Minor Plus", action: onUpgrade)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.red.opacity(0.25))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.red.opacity(0.6), lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var attachmentsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(images.enumerated()), id: \.offset) { index, data in
                    if let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(alignment: .topTrailing) {
                                removeButton { if images.indices.contains(index) { images.remove(at: index) } }
                            }
                    }
                }
                if let file {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text").font(.system(size: 13))
                        Text(file.name).font(.system(size: 14)).lineLimit(1)
                        removeButton { self.file = nil }
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 36)
                    .overlay(RoundedRectangle(cornerRadius: 15).stroke(theme.chatStroke, lineWidth: 1))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }

    private func removeButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(MinorColor.closeFill))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .offset(x: 8, y: -8)
        .accessibilityLabel("Remove attachment")
    }

    private var composer: some View {
        HStack(spacing: 10) {
            Menu {
                Button { showPhotos = true } label: { Label("Photo Library", systemImage: "photo") }
                Button { DocumentPicker.present { attachFile($0) } } label: { Label("File", systemImage: "doc.text") }
                if !mapStore.maps.isEmpty {
                    // Starts a mention; the list of maps appears above the field.
                    Button {
                        draft += draft.isEmpty || draft.hasSuffix(" ") ? "@" : " @"
                        inputFocused = true
                    } label: { Label("Mind Map", systemImage: "point.3.connected.trianglepath.dotted") }
                }
            } label: {
                Image(systemName: "plus")
                    .foregroundColor(.white)
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 32, height: 32)
                    .overlay(Circle().stroke(theme.chatStroke, lineWidth: 1))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Attach")
            .disabled(imageMode)
            // Image mode: the message becomes a description for an AI picture.
            Button {
                imageMode.toggle()
                Haptics.selection()
            } label: {
                Image(systemName: imageMode ? "paintbrush.pointed.fill" : "paintbrush.pointed")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(imageMode ? .black : .white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(imageMode ? MinorColor.accent : Color.clear))
                    .overlay(Circle().stroke(imageMode ? Color.clear : theme.chatStroke, lineWidth: 1))
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Create an image")
            .accessibilityAddTraits(imageMode ? .isSelected : [])
            TextField("", text: $draft, axis: .vertical)
                .accessibilityLabel(imageMode ? "Image description" : "Message")
                .lineLimit(1...5)
                .foregroundColor(.white)
                .placeholder(when: draft.isEmpty) {
                    Text(imageMode ? "Describe an image" : "Message")
                        .foregroundColor(theme.placeholderText)
                }
                .focused($inputFocused)
                .submitLabel(.send)
                .onSubmit(sendDraft)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 17))

            // Dictation: the words appear in the field; the person checks them and sends.
            DictationButton(text: $draft, stroke: theme.chatStroke, onError: { attachError = $0 }, onListeningChange: { dictating = $0 })

            Button(action: sendDraft) {
                Group {
                    if viewModel.isSending {
                        ProgressView()
                            .tint(.black)
                    } else {
                        Image(systemName: "arrow.up")
                            .foregroundColor(.black)
                            .font(.system(size: 16, weight: .bold))
                    }
                }
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.9))
                .clipShape(Circle())
            }
            .disabled(!canSend || viewModel.isSending || dictating)
            .opacity((canSend && !dictating) || viewModel.isSending ? 1 : 0.4)
            .padding(.trailing, 12)
            .accessibilityLabel("Send")
        }
        .padding(.leading, 4)
        .padding(.vertical, 8)
        .frame(minHeight: 60)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(theme.chatRectangle)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(theme.chatStroke, lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // A picture is drawn from words, so image mode needs text; attachments wait for a normal message.
    private var canSend: Bool {
        let hasText = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return imageMode ? hasText : hasText || !images.isEmpty || file != nil
    }

    private func sendDraft() {
        guard canSend, !viewModel.isSending, !dictating else { return }
        guard AuthService.shared.isSignedIn else { return AuthGate.shared.require { sendDraft() } }
        let text = draft
        let maps = Mentions.used(mentions, in: text)
        draft = ""
        mentions = []
        viewModel.send(text, model: model, images: imageMode ? [] : images, file: imageMode ? nil : file, maps: imageMode ? [] : maps, asImage: imageMode)
        // In image mode the attached photos and file weren't sent: they stay for the next message.
        if !imageMode {
            images = []
            file = nil
        }
        attachError = nil
        imageMode = false
    }

    private func toggleReading(_ message: ChatMessage) {
        if speaker.speakingID == message.id {
            speaker.stop()
        } else {
            speaker.speak(message.text, id: message.id)
        }
    }

    // MARK: - @ mentions

    private var mentionMatches: [MindMap] {
        guard !imageMode, let query = Mentions.query(in: draft, picked: mentions) else { return [] }
        return Mentions.matches(query, in: mapStore.maps)
    }

    private func pickMention(_ map: MindMap) {
        draft = Mentions.insert(map, into: draft)
        if !mentions.contains(where: { $0.id == map.id }) { mentions.append(MapMention(id: map.id, title: map.title)) }
        Haptics.selection()
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) {
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
            images = Array((images + loaded).prefix(4))
            photoItems = []
        }
    }

    private func attachFile(_ url: URL) {
        let isPaid = AccountStore.shared.isPaid
        Task {
            do {
                file = try await Attachments.loadDocument(at: url, maxPages: isPaid ? 300 : 10)
                attachError = nil
            } catch {
                attachError = Attachments.message(for: error, isPaid: isPaid)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.25)) {
            if viewModel.isSending {
                proxy.scrollTo("typing", anchor: .bottom)
            } else if let last = viewModel.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

// Three dots that pulse in turn (DesignSystem → Motion → typing indicator).
struct TypingDots: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                    .opacity(reduceMotion ? 1 : (phase ? 1 : 0.35))
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(Double(index) * 0.15),
                        value: phase
                    )
            }
        }
        .onAppear { phase = true }
    }
}
