//
//  ProjectChat.swift
//  Minor Ai
//
//  The project's own chat: a private conversation about one map, kept on this iPhone with its
//  draft (it isn't synced and isn't shared with people on a shared map). It sees the map, and
//  the idea or slide in focus when the person keeps them in the context. Changes it suggests to
//  the map wait as a proposal: they are applied only when the person agrees, after checking that
//  the map hasn't changed since, and can be undone.
//

import CryptoKit
import SwiftUI

struct ProjectChatRecord: Codable, Equatable {
    var messages: [ChatMessage] = []
    var draft = ""
    var updatedAt = Date()
}

@MainActor
final class ProjectChatStore {
    static let shared = ProjectChatStore()

    private let file: URL
    private let io = DispatchQueue(label: "com.minorailifegroup.MinorAI.projectchats", qos: .utility)
    private var records: [UUID: ProjectChatRecord] = [:]

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        file = base.appendingPathComponent("ProjectChats.json")
        if let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode([String: Lossy<ProjectChatRecord>].self, from: data) {
            for (key, value) in saved {
                if let id = UUID(uuidString: key), let record = value.value { records[id] = record }
            }
        }
    }

    func record(for mapID: UUID) -> ProjectChatRecord { records[mapID] ?? ProjectChatRecord() }

    func save(_ record: ProjectChatRecord, for mapID: UUID) {
        if record.messages.isEmpty && record.draft.isEmpty {
            records[mapID] = nil
        } else {
            records[mapID] = record
        }
        persist()
    }

    // The map was deleted: its chat goes too.
    func delete(_ mapID: UUID) {
        guard records[mapID] != nil else { return }
        records[mapID] = nil
        persist()
    }

    func deleteAll() {
        records = [:]
        persist()
    }

    func flush() { io.sync {} }

    private func persist() {
        let snapshot = Dictionary(uniqueKeysWithValues: records.map { ($0.key.uuidString, $0.value) })
        let file = file
        io.async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }
}

extension MindNode {
    // The tree as it would be saved, with collapsing left out (that is a personal view, not an edit).
    var editFingerprint: String {
        var copy = self
        func open(_ node: inout MindNode) {
            node.isCollapsed = false
            for i in node.children.indices { open(&node.children[i]) }
        }
        open(&copy)
        // Sorted keys: the same tree always gives the same bytes.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = (try? encoder.encode(copy)) ?? Data()
        return SHA256.hash(data: data).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    // The same tree with the collapsed branches of `other` (where the ids match).
    func keepingCollapse(from other: MindNode) -> MindNode {
        var collapsed: Set<UUID> = []
        func collect(_ node: MindNode) {
            if node.isCollapsed { collapsed.insert(node.id) }
            node.children.forEach(collect)
        }
        collect(other)
        var copy = self
        func apply(_ node: inout MindNode) {
            node.isCollapsed = collapsed.contains(node.id) && !node.children.isEmpty
            for i in node.children.indices { apply(&node.children[i]) }
        }
        apply(&copy)
        return copy
    }

    // "Branch › New idea" for each idea in `new` that isn't in this tree.
    func addedTitles(in new: MindNode) -> [String] {
        var known: Set<UUID> = []
        func collect(_ node: MindNode) {
            known.insert(node.id)
            node.children.forEach(collect)
        }
        collect(self)
        var result: [String] = []
        func walk(_ node: MindNode, parent: String?) {
            if !known.contains(node.id) {
                result.append(parent.map { "\($0) › \(node.title)" } ?? node.title)
            }
            for child in node.children { walk(child, parent: node.title) }
        }
        walk(new, parent: nil)
        return result
    }
}

@MainActor
final class ProjectChatModel: ObservableObject {
    let mapID: UUID

    @Published private(set) var messages: [ChatMessage]
    @Published var draft: String { didSet { scheduleSave() } }
    @Published private(set) var sending = false
    @Published var errorMessage: String?
    @Published var errorSuggestsUpgrade = false
    @Published var needsConsent = false
    // A presentation the chat made: the project shows it on the Slides tab.
    @Published var deckRequest: UUID?

    struct Context {
        var branch: UUID?
        var deck: Deck?
        var slide: Slide?
    }

    private var task: Task<Void, Never>?
    private var pending: (() -> Void)?
    private var saveWork: DispatchWorkItem?
    private var deckUndo: [UUID: (deckID: UUID, before: Deck, after: Deck)] = [:]

    init(mapID: UUID) {
        self.mapID = mapID
        let record = ProjectChatStore.shared.record(for: mapID)
        messages = record.messages
        draft = record.draft
    }

    var map: MindMap? { MapStore.shared.map(mapID) }
    var isViewer: Bool { map?.collab?.role == .viewer }

    // MARK: Sending

    func send(_ text: String, model: AIModelOption, context: Context) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !sending, let map else { return }
        guard AuthService.shared.isSignedIn else {
            return AuthGate.shared.require { [weak self] in self?.send(text, model: model, context: context) }
        }
        guard AIConsent.isGiven else {
            pending = { [weak self] in self?.send(text, model: model, context: context) }
            needsConsent = true
            return
        }
        errorMessage = nil
        errorSuggestsUpgrade = false
        var message = ChatMessage(role: .user, text: trimmed)
        // What the model reads with this message: the map now, and the idea or slide in focus.
        message.mapText = contextText(map, context)
        messages.append(message)
        draft = ""
        save()
        Telemetry.log("project_chat_message", ["model": model.apiModelID, "branch": context.branch == nil ? 0 : 1, "slide": context.slide == nil ? 0 : 1])
        run(messageID: message.id, model: model, context: context)
    }

    func resumeAfterConsent() {
        needsConsent = false
        let action = pending
        pending = nil
        action?()
    }

    func cancelConsent() {
        needsConsent = false
        pending = nil
    }

    func stop() {
        task?.cancel()
    }

    // The last message that got no answer is sent again as it was.
    func retry(_ messageID: UUID, model: AIModelOption, context: Context) {
        guard !sending, let index = messages.firstIndex(where: { $0.id == messageID }), messages[index].failed != nil,
              messages.last(where: { !$0.isHidden })?.id == messageID else { return }
        messages[index].failed = nil
        if let map { messages[index].mapText = contextText(map, context) }
        errorMessage = nil
        save()
        run(messageID: messageID, model: model, context: context)
    }

    func canRetry(_ messageID: UUID) -> Bool {
        !sending && messages.last(where: { !$0.isHidden })?.id == messageID
    }

    func clear() {
        task?.cancel()
        messages = []
        errorMessage = nil
        save()
    }

    private func run(messageID: UUID, model: AIModelOption, context: Context) {
        sending = true
        task = Task { [weak self] in
            guard let self else { return }
            let background = BackgroundTime(name: "Project chat")
            defer {
                background.end()
                self.sending = false
                self.task = nil
            }
            do {
                try await self.respond(model: model, context: context)
            } catch {
                if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                    self.mark(messageID, failed: L("Stopped"))
                } else {
                    self.failed(messageID, error)
                }
            }
        }
    }

    // Earlier messages go without their map snapshots: only the latest one carries the map as it is now.
    private func requestHistory() -> [ChatMessage] {
        let lastUser = messages.lastIndex { $0.role == .user && !$0.isHidden }
        return messages.enumerated().map { index, message in
            var copy = message
            if index != lastUser { copy.mapText = nil }
            return copy
        }
    }

    private func contextText(_ map: MindMap, _ context: Context) -> String {
        var text = "The user's mind map this chat is about (they see it in the app):\n" + Workspace.outline(of: map, limit: 12_000)
        if let memory = ProjectMemoryStore.shared.memory(for: map.id).contextText { text += "\n\n" + memory }
        if let id = context.branch, id != map.root.id, let path = map.root.path(to: id) {
            text += "\n\nThe user has selected this idea and means it unless they say otherwise: " + path.map(\.title).joined(separator: " › ")
        }
        if let deck = context.deck, let slide = context.slide, let number = deck.slides.firstIndex(where: { $0.id == slide.id }) {
            text += "\n\nThe user is looking at slide \(number + 1) of the presentation “\(deck.title)”: " + slide.plainText.joined(separator: " / ")
        }
        return text
    }

    // The assistant's turn: an answer, or a proposal for the map, a picture, a presentation.
    private func respond(model: AIModelOption, context: Context) async throws {
        var history = requestHistory()
        for step in 0..<3 {
            guard let map else { return }
            let answer = try await AIService.shared.answer(to: history, model: model, intents: true, workspace: Workspace.index([map]))
            try Task.checkCancellation()
            guard let intent = answer.intent else {
                append(ChatMessage(role: .assistant, text: answer.text, model: answer.model))
                return
            }
            switch intent.kind {
            case .edit:
                guard let command = intent.command else { break }
                try await propose(command: command, branch: context.branch)
                return
            case .read, .tasks:
                guard step < 2 else { break }
                let request = intent.kind == .tasks ? "TASKS" : "READ: " + (intent.maps ?? []).joined(separator: ", ")
                let data = intent.kind == .tasks ? Workspace.openTasks([map]) : Workspace.outline(of: map, limit: 12_000)
                let pair = [
                    ChatMessage(role: .assistant, text: request, model: answer.model, hidden: true),
                    ChatMessage(role: .user, text: "App data, the reply to \(request):\n\(data)", hidden: true),
                ]
                pair.forEach(append)
                history += pair
                continue
            case .image:
                let data = try await AIService.shared.generateImage(prompt: intent.prompt)
                append(ChatMessage(role: .assistant, text: "", images: [data], model: "image", imagePrompt: intent.prompt))
                return
            case .deck:
                try await makeDeck(branch: context.branch)
                return
            case .editdeck:
                guard let deck = context.deck, let command = intent.command else {
                    append(ChatMessage(role: .assistant, text: L("Open the presentation on the Slides tab, then ask again.")))
                    return
                }
                try await editDeck(deck, command: command)
                return
            case .map:
                // A new map is a project of its own: built in the background and announced when ready.
                let topic = intent.mapsConversation ? Conversation.makeTitle(from: messages) : intent.prompt
                let input: MapInput = intent.mapsConversation
                    ? .text(messages.filter { !$0.isHidden }.map(\.contentForModel).joined(separator: "\n\n"), source: MapSource(kind: .chat, label: topic))
                    : .topic(intent.prompt)
                _ = GenerationCenter.shared.start(input)
                append(ChatMessage(role: .assistant, text: L("Creating a new mind map: \(topic). It will be in the Library when it’s ready.")))
                return
            case .open:
                if let ref = intent.maps?.first, let deck = Workspace.deck(ref: ref) {
                    deckRequest = deck.id
                    append(ChatMessage(role: .assistant, text: "", action: ChatAction(kind: .deckOpened, mapID: deck.id, mapTitle: deck.title)))
                } else {
                    append(ChatMessage(role: .assistant, text: L("This map is open: switch to the Map tab to see it.")))
                }
                return
            }
            break
        }
        append(ChatMessage(role: .assistant, text: L("Something went wrong. Try again.")))
    }

    // MARK: Map proposals

    private func propose(command: String, branch: UUID?) async throws {
        guard let current = map else { return }
        let selected = branch.flatMap { current.root.node($0)?.title }
        let result = try await MapService.shared.edit(current, command: command, selected: selected)
        try Task.checkCancellation()
        switch result {
        case .map(let tree):
            let proposed = current.root.merged(with: tree)
            let diff = MapDiff(old: current.root, new: proposed)
            guard !diff.isEmpty else {
                append(ChatMessage(role: .assistant, text: L("Nothing to change in “\(current.title)”.")))
                return
            }
            var action = ChatAction(kind: .mapProposal, mapID: mapID, mapTitle: proposed.title, summary: diff.summary)
            action.command = command
            action.proposal = proposed
            action.base = current.root.editFingerprint
            action.added = current.root.addedTitles(in: proposed)
            append(ChatMessage(role: .assistant, text: "", action: action))
        case .images:
            append(ChatMessage(role: .assistant, text: L("To add pictures, select an idea on the map and choose Create Image with AI.")))
        case .question:
            append(ChatMessage(role: .assistant, text: L("I couldn't tell what to change in “\(current.title)”. Try saying it differently.")))
        }
    }

    // The map changed (by hand, from another device, by a person editing together) since the answer.
    func isStale(_ action: ChatAction) -> Bool {
        guard action.kind == .mapProposal, action.applied != true, let map else { return false }
        return map.root.editFingerprint != action.base
    }

    func apply(_ messageID: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }), var action = messages[index].action,
              action.kind == .mapProposal, action.applied != true, action.dismissed != true,
              let proposal = action.proposal, let latest = map else { return }
        // Checked here, not only by hiding the button: access can change while the screen is open.
        guard !isViewer else {
            errorMessage = L("This map is shared with you to view. The owner can make you an editor.")
            return
        }
        guard latest.root.editFingerprint == action.base else { return }
        let result = proposal.keepingCollapse(from: latest.root)
        MapStore.shared.update(mapID) { $0.root = result }
        action.applied = true
        action.before = latest.root
        action.proposal = result
        messages[index].action = action
        save()
        Telemetry.log("project_chat_apply", ["added": action.added?.count ?? 0])
        Haptics.success()
    }

    func dismiss(_ messageID: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }), var action = messages[index].action else { return }
        action.dismissed = true
        action.proposal = nil
        messages[index].action = action
        save()
    }

    func canUndo(_ messageID: UUID) -> Bool {
        guard let action = messages.first(where: { $0.id == messageID })?.action else { return false }
        if action.kind == .deckEdited, let state = deckUndo[messageID] {
            return DeckStore.shared.deck(state.deckID)?.slides == state.after.slides
        }
        guard action.kind == .mapProposal, action.applied == true, action.undone != true,
              let after = action.proposal, action.before != nil, let map else { return false }
        return map.root.editFingerprint == after.editFingerprint
    }

    func undo(_ messageID: UUID) {
        guard canUndo(messageID), let index = messages.firstIndex(where: { $0.id == messageID }), var action = messages[index].action else { return }
        if action.kind == .deckEdited, let state = deckUndo[messageID] {
            DeckStore.shared.save(state.before)
            deckUndo[messageID] = nil
        } else if let before = action.before, let latest = map {
            MapStore.shared.update(mapID) { $0.root = before.keepingCollapse(from: latest.root) }
        }
        action.undone = true
        messages[index].action = action
        save()
        Haptics.success()
    }

    // Asks again with the same words, on the map as it is now.
    func recalculate(_ messageID: UUID, model: AIModelOption, branch: UUID?) {
        guard !sending, let index = messages.firstIndex(where: { $0.id == messageID }), let command = messages[index].action?.command else { return }
        dismiss(messageID)
        sending = true
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                self.sending = false
                self.task = nil
            }
            do {
                try await self.propose(command: command, branch: branch)
            } catch {
                if !(Task.isCancelled || error is CancellationError) { self.report(error) }
            }
        }
    }

    // MARK: Presentations

    private func makeDeck(branch: UUID?) async throws {
        guard let map else { return }
        if AccountStore.shared.isOverFreeDeckLimit { throw BackendError.limitReached(kind: "decks") }
        let nodeID = branch == map.root.id ? nil : branch
        let content = nodeID.flatMap { map.branch($0) } ?? map
        let slides = AccountStore.shared.effectivePlan == .free ? 7 : 10
        let generated = try await DeckService.shared.generate(.map(content), slides: slides, quality: AccountStore.shared.allowedMapModelID)
        try Task.checkCancellation()
        var deck = Deck(title: generated.title, slides: generated.slides, theme: .matching(map.mapPalette), sourceMapID: mapID)
        deck.sourceNodeID = nodeID
        deck.sourceRevision = content.contentFingerprint
        deck.lineage = generated.lineage
        DeckStore.shared.save(deck)
        AccountStore.shared.noteDeckCreated()
        Telemetry.log("deck_created", ["source": "project_chat", "slides": deck.slides.count, "template": "none"])
        append(ChatMessage(role: .assistant, text: "", action: ChatAction(kind: .deckCreated, mapID: deck.id, mapTitle: deck.title, summary: L("\(deck.slides.count) slides"))))
        deckRequest = deck.id
        Haptics.success()
    }

    private func editDeck(_ deck: Deck, command: String) async throws {
        let edited = try await DeckService.shared.edit(deck, command: command)
        try Task.checkCancellation()
        guard let current = DeckStore.shared.deck(deck.id) else { return }
        var updated = current
        updated.title = edited.title
        updated.slides = edited.slides
        DeckStore.shared.save(updated)
        let saved = DeckStore.shared.deck(deck.id) ?? updated
        let change = updated.slides.count - current.slides.count
        let summary = change > 0 ? L("+\(change) slides") : change < 0 ? L("\(-change) slides removed") : L("slides updated")
        let message = ChatMessage(role: .assistant, text: "", action: ChatAction(kind: .deckEdited, mapID: deck.id, mapTitle: updated.title, summary: summary))
        deckUndo[message.id] = (deck.id, current, saved)
        append(message)
        Haptics.success()
    }

    // MARK: Storage and errors

    private func append(_ message: ChatMessage) {
        messages.append(message)
        save()
    }

    private func mark(_ messageID: UUID, failed reason: String) {
        if let index = messages.firstIndex(where: { $0.id == messageID }) {
            messages[index].failed = reason
            save()
        }
    }

    private func failed(_ messageID: UUID, _ error: Error) {
        mark(messageID, failed: (error as? LocalizedError)?.errorDescription ?? L("Something went wrong. Try again."))
        report(error)
    }

    private func report(_ error: Error) {
        if case BackendError.limitReached(let kind) = error { AccountStore.shared.noteLimitReached(kind: kind) }
        errorSuggestsUpgrade = (error as? BackendError)?.suggestsUpgrade ?? false
        errorMessage = (error as? LocalizedError)?.errorDescription ?? L("Something went wrong. Try again.")
        Haptics.error()
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [self] in save() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func save() {
        saveWork?.cancel()
        ProjectChatStore.shared.save(ProjectChatRecord(messages: messages, draft: draft, updatedAt: Date()), for: mapID)
    }
}
