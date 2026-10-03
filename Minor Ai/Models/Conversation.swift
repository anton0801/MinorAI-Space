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

    init(id: UUID = UUID(), title: String, messages: [ChatMessage], updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.messages = messages
        self.updatedAt = updatedAt
    }

    // Title derived from the first user message, trimmed to a short label.
    static func makeTitle(from messages: [ChatMessage]) -> String {
        let first = messages.first(where: { $0.role == .user && !$0.isHidden })
        var trimmed = (first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { trimmed = first?.fileName ?? (first?.images?.isEmpty == false ? L("Photo") : "") }
        if trimmed.isEmpty { return L("New chat") }
        return trimmed.count > 40 ? String(trimmed.prefix(40)) + "…" : trimmed
    }
}
