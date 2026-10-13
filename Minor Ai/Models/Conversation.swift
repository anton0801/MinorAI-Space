//
//  Conversation.swift
//  Minor Ai
//

import Foundation

struct Conversation: Identifiable, Codable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    var updatedAt: Date
    var isPinned = false   // kept on top of the Library's Chats
    var renamed = false    // a title the person gave it, kept when new messages come

    init(id: UUID = UUID(), title: String, messages: [ChatMessage], updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.messages = messages
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey { case id, title, messages, updatedAt, isPinned, renamed }

    // Conversations saved before pinning and renaming read as neither.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        messages = try c.decode([ChatMessage].self, forKey: .messages)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        isPinned = (try? c.decodeIfPresent(Bool.self, forKey: .isPinned)) ?? false
        renamed = (try? c.decodeIfPresent(Bool.self, forKey: .renamed)) ?? false
    }

    // Messages the person sees (not the hidden context the app adds).
    var visibleCount: Int { messages.filter { !$0.isHidden }.count }

    // Title derived from the first user message, trimmed to a short label.
    static func makeTitle(from messages: [ChatMessage]) -> String {
        let first = messages.first(where: { $0.role == .user && !$0.isHidden })
        var trimmed = (first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { trimmed = first?.fileName ?? (first?.images?.isEmpty == false ? L("Photo") : "") }
        if trimmed.isEmpty { return L("New chat") }
        return trimmed.count > 40 ? String(trimmed.prefix(40)) + "…" : trimmed
    }
}
