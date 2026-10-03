//
//  ChatMessage.swift
//  Minor Ai
//

import Foundation

enum ChatRole: String, Codable {
    case user
    case assistant
}

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let role: ChatRole
    var text: String
    var images: [Data]?      // JPEG, already resized for upload
    var fileName: String?    // attached document, shown as a chip
    var fileText: String?    // its text, sent to the model but not shown
    var model: String?       // API id of the model that answered (assistant messages)
    var imagePrompt: String? // what a created picture shows, so later messages can refer to it
    var hidden: Bool?        // app data and the assistant's requests for it: sent to the model, not shown
    var maps: [MapMention]?  // maps attached with @, shown as chips
    var mapText: String?     // their outlines when sent, read by the model
    var action: ChatAction?  // what the assistant did in a map (a card with Open and Undo)
    var tasksText: String?   // the person's tasks, attached by "Plan My Day"

    init(id: UUID = UUID(), role: ChatRole, text: String, images: [Data]? = nil, fileName: String? = nil, fileText: String? = nil, model: String? = nil, imagePrompt: String? = nil, hidden: Bool? = nil, maps: [MapMention]? = nil, mapText: String? = nil, action: ChatAction? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.images = images
        self.fileName = fileName
        self.fileText = fileText
        self.model = model
        self.imagePrompt = imagePrompt
        self.hidden = hidden
        self.maps = maps
        self.mapText = mapText
        self.action = action
    }

    var isHidden: Bool { hidden == true }

    // What the model reads: the typed text plus any attached document or map.
    var contentForModel: String {
        if role == .assistant, text.isEmpty, let imagePrompt {
            return "(The app created this picture: \(imagePrompt))"
        }
        if role == .assistant, text.isEmpty, let action {
            return action.descriptionForModel
        }
        var content = text
        if let mapText, !mapText.isEmpty {
            content += "\n\nApp data, the maps I attached:\n\(mapText)"
        }
        if let tasksText, !tasksText.isEmpty {
            content += "\n\nApp data, my tasks from all my maps:\n\(tasksText)"
        }
        if let fileName, let fileText, !fileText.isEmpty {
            content += "\n\nAttached file “\(fileName)”:\n\(fileText.prefix(40_000))"
        }
        return content
    }
}

// A map attached to a message with @.
struct MapMention: Codable, Equatable, Hashable {
    var id: UUID
    var title: String
}

// Something the assistant did in a map at the person's request.
struct ChatAction: Codable, Equatable {
    enum Kind: String, Codable {
        case edited      // the map changed; Undo restores it
        case images      // pictures for some ideas (pending until the person confirms)
        case opened
    }
    var kind: Kind
    var mapID: UUID
    var mapTitle: String
    var summary: String = ""
    var undone: Bool?
    var imageNodes: [UUID]?   // .images: the ideas to illustrate
    var imageHint: String?
    var imagesDone: Int?      // .images: nil until started
    var imagesFailed: Bool?

    var descriptionForModel: String {
        switch kind {
        case .edited:
            return undone == true
                ? "(The app changed the map “\(mapTitle)”, then the user undid it.)"
                : "(The app changed the map “\(mapTitle)”: \(summary).)"
        case .images:
            return "(The app offered to create \(imageNodes?.count ?? 0) pictures in the map “\(mapTitle)”.)"
        case .opened:
            return "(The app opened the map “\(mapTitle)”.)"
        }
    }
}
