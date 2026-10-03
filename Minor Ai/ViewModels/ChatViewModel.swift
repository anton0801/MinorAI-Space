//
//  ChatViewModel.swift
//  Minor Ai
//

import Foundation

@MainActor
final class ChatViewModel: ObservableObject {
    // One for the app: changing the language rebuilds the screens, not the chats in flight.
    static let shared = ChatViewModel()

    @Published var messages: [ChatMessage] = []
    @Published var errorMessage: String?
    @Published var conversations: [Conversation] = []
    @Published var limitReached = false
    // Conversations waiting for a reply. Each reply goes back to the conversation that asked,
    // even when the person has opened another one meanwhile.
    @Published private(set) var sending: Set<UUID> = []

    private let service: AIService
    private let store: ConversationStore
    private var currentID: UUID?

    init(service: AIService = .shared, store: ConversationStore = .shared) {
        self.service = service
        self.store = store
        self.conversations = store.loadAll()
    }

    var isSending: Bool { currentID.map { sending.contains($0) } ?? false }

    // A send waiting for the one-time AI consent (see AIConsentView).
    @Published var needsConsent = false
    private var pendingSend: (() -> Void)?

    // What was typed and attached when consent was declined, handed back to the input field.
    struct Draft: Identifiable {
        let id = UUID()
        let text: String
        let images: [Data]
        let file: Attachments.Document?
    }
    @Published var restoredDraft: Draft?
    private var pendingDraft: Draft?

    // A mind map the person asked for in the chat; the home screen builds it.
    struct MapRequest: Identifiable, Equatable {
        let id = UUID()
        let input: MapInput
        static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    }
    @Published var mapRequest: MapRequest?
    // A map the assistant opened; the home screen shows it in the editor.
    @Published var openMapRequest: UUID?

    // Undo for the assistant's map changes this session: the map before and after the change.
    private var undoStates: [UUID: (mapID: UUID, before: MindNode, after: MindNode)] = [:]

    func resumeAfterConsent() {
        needsConsent = false
        pendingDraft = nil
        let action = pendingSend
        pendingSend = nil
        action?()
    }

    func cancelPendingSend() {
        needsConsent = false
        pendingSend = nil
        if let pendingDraft { restoredDraft = pendingDraft }
        pendingDraft = nil
    }

    func send(_ text: String, model: AIModelOption, images: [Data] = [], file: Attachments.Document? = nil, maps: [MapMention] = [], withTasks: Bool = false, asImage: Bool = false) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !images.isEmpty || file != nil, !isSending else { return }
        // The image switch in the composer creates a picture right away. Otherwise the model decides
        // from the wording whether a picture or a map is wanted.
        if images.isEmpty, file == nil, !trimmed.isEmpty, asImage {
            return generateImage(trimmed)
        }
        guard AIConsent.isGiven else {
            pendingSend = { [weak self] in self?.send(text, model: model, images: images, file: file, maps: maps, withTasks: withTasks) }
            pendingDraft = Draft(text: text, images: images, file: file)
            needsConsent = true
            return
        }

        errorMessage = nil
        limitReached = false
        // Maps attached with @ travel as their outlines at the time of sending.
        let attached = maps.compactMap { MapStore.shared.map($0.id) }
        var message = ChatMessage(
            role: .user,
            text: trimmed,
            images: images.isEmpty ? nil : images,
            fileName: file?.name,
            fileText: file?.text,
            maps: attached.isEmpty ? nil : attached.map { MapMention(id: $0.id, title: $0.title) },
            mapText: attached.isEmpty ? nil : attached.map { Workspace.outline(of: $0) }.joined(separator: "\n\n")
        )
        // "Plan My Day": the tasks go with the message, so the plan never depends on the model asking.
        if withTasks { message.tasksText = Workspace.openTasks() }
        messages.append(message)
        let conversationID = persistCurrent()
        sending.insert(conversationID)

        let history = messages
        Task {
            defer { sending.remove(conversationID) }
            do {
                try await respond(to: history, model: model, conversationID: conversationID)
            } catch is CancellationError {
                return
            } catch {
                guard currentID == conversationID else { return }
                if case BackendError.limitReached(let kind) = error {
                    limitReached = true
                    AccountStore.shared.noteLimitReached(kind: kind)
                }
                errorMessage = (error as? LocalizedError)?.errorDescription ?? L("Something went wrong. Try again.")
            }
        }
    }

    // An AI picture in reply to a description. It is stored with the conversation, on the device.
    func generateImage(_ prompt: String, quality: String? = nil) {
        guard !isSending else { return }
        guard AIConsent.isGiven else {
            pendingSend = { [weak self] in self?.generateImage(prompt, quality: quality) }
            pendingDraft = Draft(text: prompt, images: [], file: nil)
            needsConsent = true
            return
        }
        errorMessage = nil
        limitReached = false
        messages.append(ChatMessage(role: .user, text: prompt))
        let conversationID = persistCurrent()
        sending.insert(conversationID)
        Task {
            defer { sending.remove(conversationID) }
            do {
                let data = try await service.generateImage(prompt: prompt, quality: quality)
                append(ChatMessage(role: .assistant, text: "", images: [data], model: "image", imagePrompt: prompt), to: conversationID)
            } catch is CancellationError {
                return
            } catch {
                guard currentID == conversationID else { return }
                if case BackendError.limitReached(let kind) = error {
                    limitReached = true
                    AccountStore.shared.noteLimitReached(kind: kind)
                }
                errorMessage = (error as? LocalizedError)?.errorDescription ?? L("Something went wrong. Try again.")
            }
        }
    }

    // The assistant's turn. It may first read maps or tasks (the app answers with hidden "App data"
    // messages and asks again), then reply, or act: a picture, a new map, a change to a map, opening one.
    private func respond(to history: [ChatMessage], model: AIModelOption, conversationID: UUID) async throws {
        var history = history
        for step in 0..<3 {
            let workspace = Workspace.isEnabled ? Workspace.index() : nil
            let answer = try await service.answer(to: history, model: model, intents: true, workspace: workspace)
            guard let intent = answer.intent else {
                append(ChatMessage(role: .assistant, text: answer.text, model: answer.model), to: conversationID)
                return
            }
            switch intent.kind {
            case .image:
                let data = try await service.generateImage(prompt: intent.prompt)
                append(ChatMessage(role: .assistant, text: "", images: [data], model: "image", imagePrompt: intent.prompt), to: conversationID)
                return
            case .map:
                startMap(intent, history: history, conversationID: conversationID)
                return
            case .read, .tasks:
                guard step < 2 else { break }
                let request: String
                let data: String
                if intent.kind == .tasks {
                    request = "TASKS"
                    data = Workspace.openTasks()
                } else {
                    let refs = intent.maps ?? []
                    request = "READ: " + refs.joined(separator: ", ")
                    let found = refs.compactMap(Workspace.map(ref:))
                    data = found.isEmpty
                        ? "No map with that reference. The maps are listed in App data."
                        : found.map { Workspace.outline(of: $0, limit: 12_000 / found.count) }.joined(separator: "\n\n")
                }
                let pair = [
                    ChatMessage(role: .assistant, text: request, model: answer.model, hidden: true),
                    ChatMessage(role: .user, text: "App data, the reply to \(request):\n\(data)", hidden: true),
                ]
                pair.forEach { append($0, to: conversationID) }
                history += pair
                continue
            case .edit:
                guard let ref = intent.maps?.first, let command = intent.command else { break }
                try await editMap(ref: ref, command: command, conversationID: conversationID)
                return
            case .open:
                guard let ref = intent.maps?.first, let map = Workspace.map(ref: ref) else {
                    append(ChatMessage(role: .assistant, text: L("I couldn't find that map. Try @ to pick it from your maps.")), to: conversationID)
                    return
                }
                append(ChatMessage(role: .assistant, text: "", action: ChatAction(kind: .opened, mapID: map.id, mapTitle: map.title)), to: conversationID)
                if currentID == conversationID { openMapRequest = map.id }
                return
            }
            break
        }
        append(ChatMessage(role: .assistant, text: L("Something went wrong. Try again.")), to: conversationID)
    }

    // A change to an existing map, asked for in the chat. The card in the chat can undo it.
    private func editMap(ref: String, command: String, conversationID: UUID) async throws {
        guard let map = Workspace.map(ref: ref) else {
            append(ChatMessage(role: .assistant, text: L("I couldn't find that map. Try @ to pick it from your maps.")), to: conversationID)
            return
        }
        let result = try await MapService.shared.edit(map, command: command)
        guard let current = MapStore.shared.map(map.id) else { return }
        switch result {
        case .map(let tree):
            let root = current.root.merged(with: tree)
            let diff = MapDiff(old: current.root, new: root)
            guard !diff.isEmpty else {
                append(ChatMessage(role: .assistant, text: L("Nothing to change in “\(map.title)”.")), to: conversationID)
                return
            }
            MapStore.shared.update(map.id) { $0.root = root }
            let message = ChatMessage(role: .assistant, text: "", action: ChatAction(kind: .edited, mapID: map.id, mapTitle: root.title, summary: diff.summary))
            undoStates[message.id] = (map.id, current.root, root)
            append(message, to: conversationID)
            Haptics.success()
        case .images(let titles, let hint):
            var ids = current.root.ids(titled: titles)
            if ids.isEmpty { ids = [current.root.id] }
            let action = ChatAction(kind: .images, mapID: map.id, mapTitle: map.title, imageNodes: Array(ids.prefix(8)), imageHint: hint)
            append(ChatMessage(role: .assistant, text: "", action: action), to: conversationID)
        case .question:
            append(ChatMessage(role: .assistant, text: L("I couldn't tell what to change in “\(map.title)”. Try saying it differently.")), to: conversationID)
        }
    }

    func canUndo(_ messageID: UUID) -> Bool {
        guard let state = undoStates[messageID] else { return false }
        return MapStore.shared.map(state.mapID)?.root == state.after
    }

    // Restores the map as it was before the assistant's change (only while nothing else changed it).
    func undoAction(_ messageID: UUID) {
        guard canUndo(messageID), let state = undoStates[messageID] else { return }
        MapStore.shared.update(state.mapID) { $0.root = state.before }
        undoStates[messageID] = nil
        updateAction(messageID) { $0.undone = true }
        Haptics.success()
    }

    func openMap(_ id: UUID) {
        guard MapStore.shared.map(id) != nil else { return }
        openMapRequest = id
    }

    // Pictures the assistant offered for ideas in a map, made one after another after the person agrees.
    func createImages(_ messageID: UUID) {
        guard let action = messages.first(where: { $0.id == messageID })?.action, action.kind == .images,
              action.imagesDone == nil, let nodes = action.imageNodes else { return }
        updateAction(messageID) { $0.imagesDone = 0 }
        Task {
            var done = 0
            for id in nodes {
                guard let map = MapStore.shared.map(action.mapID), let path = map.root.path(to: id) else { continue }
                do {
                    let context = AIService.NodeContext(mapTitle: map.title, path: path.map(\.title))
                    let data = try await service.generateImage(prompt: action.imageHint ?? "", context: context)
                    guard let picture = MapStore.shared.storeImage(data, isAI: true) else { continue }
                    MapStore.shared.update(action.mapID) { $0.root.update(id) { $0.image = picture } }
                    done += 1
                    updateAction(messageID) { $0.imagesDone = done }
                } catch {
                    updateAction(messageID) { $0.imagesFailed = true }
                    if case BackendError.limitReached(let kind) = error {
                        limitReached = true
                        AccountStore.shared.noteLimitReached(kind: kind)
                    }
                    errorMessage = (error as? LocalizedError)?.errorDescription ?? L("Something went wrong. Try again.")
                    break
                }
            }
            if done > 0 { Haptics.success() }
        }
    }

    private func updateAction(_ messageID: UUID, _ change: (inout ChatAction) -> Void) {
        if let index = messages.firstIndex(where: { $0.id == messageID }), var action = messages[index].action {
            change(&action)
            messages[index].action = action
            persistCurrent()
            return
        }
        for c in conversations.indices {
            guard let index = conversations[c].messages.firstIndex(where: { $0.id == messageID }),
                  var action = conversations[c].messages[index].action else { continue }
            change(&action)
            conversations[c].messages[index].action = action
            store.saveAll(conversations)
            return
        }
    }

    // A map of a topic, or of this conversation ("MAP: ^"). The chat notes it, and the home screen
    // shows the map being built.
    private func startMap(_ intent: AIService.Intent, history: [ChatMessage], conversationID: UUID) {
        let input: MapInput
        let topic: String
        if intent.mapsConversation {
            let text = history.filter { !$0.isHidden }.map(\.contentForModel).filter { !$0.isEmpty }.joined(separator: "\n\n")
            topic = Conversation.makeTitle(from: history)
            input = .text(String(text.suffix(60_000)), source: MapSource(kind: .chat, label: topic))
        } else {
            topic = intent.prompt
            input = .topic(intent.prompt)
        }
        append(ChatMessage(role: .assistant, text: L("Creating a mind map: \(topic)")), to: conversationID)
        guard currentID == conversationID else { return }
        mapRequest = MapRequest(input: input)
    }

    // Someone reported a created image: it is hidden at once and the description goes for review.
    func reportImage(_ messageID: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        let prompt = messages[index].imagePrompt ?? messages[..<index].last(where: { $0.role == .user })?.text ?? ""
        messages[index].images = nil
        messages[index].text = L("Image hidden. Thanks for letting us know.")
        persistCurrent()
        Task { try? await service.report(kind: "image", content: prompt, reason: "reported in chat") }
    }

    // Adds a reply to its conversation, and to the screen when that conversation is open.
    private func append(_ message: ChatMessage, to conversationID: UUID) {
        if currentID == conversationID {
            messages.append(message)
            persistCurrent()
            return
        }
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        conversations[index].messages.append(message)
        conversations[index].updatedAt = Date()
        conversations.sort { $0.updatedAt > $1.updatedAt }
        store.saveAll(conversations)
    }

    // Persists the open conversation (created on the first message) and returns its id.
    @discardableResult
    private func persistCurrent() -> UUID {
        let id = currentID ?? UUID()
        currentID = id
        guard !messages.isEmpty else { return id }
        let convo = Conversation(
            id: id,
            title: Conversation.makeTitle(from: messages),
            messages: messages,
            updatedAt: Date()
        )
        if let index = conversations.firstIndex(where: { $0.id == id }) {
            conversations[index] = convo
        } else {
            conversations.insert(convo, at: 0)
        }
        conversations.sort { $0.updatedAt > $1.updatedAt }
        store.saveAll(conversations)
        return id
    }

    // Open a saved conversation in the chat view.
    func open(_ conversation: Conversation) {
        currentID = conversation.id
        errorMessage = nil
        limitReached = false
        messages = conversations.first { $0.id == conversation.id }?.messages ?? conversation.messages
    }

    // Return to the launcher by clearing the visible thread (it is already saved).
    func endSession() {
        currentID = nil
        errorMessage = nil
        limitReached = false
        messages = []
    }

    func deleteAll() {
        conversations = []
        sending = []
        store.saveAll([])
        endSession()
    }

    func deleteConversation(_ id: UUID) {
        conversations.removeAll { $0.id == id }
        store.saveAll(conversations)
        if currentID == id { endSession() }
    }
}
