//
//  MapService.swift
//  Minor Ai
//
//  AI actions on maps, served by the `ai` edge function. Provider keys live only on the server.
//

import Foundation

enum MapInput {
    case topic(String)
    case link(String)
    case youtube(String)
    case text(String, source: MapSource)

    var source: MapSource {
        switch self {
        case .topic(let topic): return MapSource(kind: .topic, label: topic)
        case .link(let url): return MapSource(kind: .link, label: url)
        case .youtube(let url): return MapSource(kind: .youtube, label: url)
        case .text(_, let source): return source
        }
    }
}

// How Expand should grow an idea (DesignSystem → node card → AI actions).
enum ExpandHint: String {
    case more = ""
    case examples
    case steps
    case questions
}

final class MapService {
    static let shared = MapService()

    struct Generated {
        let root: MindNode
        let truncated: Bool   // a long document was mapped from its beginning
    }

    // `model` picks the map quality; the server checks the plan allows it.
    func generate(_ input: MapInput, model: AIModelOption = AIModelCatalog.defaultMap) async throws -> Generated {
        struct Source: Encodable { let kind: String; let value: String }
        struct Body: Encodable { let action = "map"; let source: Source; let quality: String }
        let source: Source
        switch input {
        case .topic(let topic): source = Source(kind: "topic", value: topic)
        case .link(let url): source = Source(kind: "link", value: url)
        case .youtube(let url): source = Source(kind: "youtube", value: url)
        case .text(let text, _): source = Source(kind: "text", value: text)
        }
        let reply: MapReply = try await BackendClient.shared.invoke("ai", body: Body(source: source, quality: model.apiModelID))
        return Generated(root: reply.map.toNode(aiAdded: false), truncated: reply.truncated ?? false)
    }

    func expand(_ map: MindMap, node id: UUID, hint: ExpandHint = .more) async throws -> [MindNode] {
        struct Body: Encodable { let action = "expand"; let mapTitle: String; let path: [String]; let existing: [String]; let hint: String }
        guard let path = map.root.path(to: id), let node = path.last else { return [] }
        let body = Body(mapTitle: map.title, path: path.map(\.title), existing: node.children.map(\.title), hint: hint.rawValue)
        let reply: ChildrenReply = try await BackendClient.shared.invoke("ai", body: body)
        // "Next Steps" become tasks with checkboxes.
        return reply.children.map { MindNode(title: $0.title, isAIAdded: true, isTask: hint == .steps) }
    }

    // A short note that explains the idea and how its children connect.
    func summarize(_ map: MindMap, node id: UUID) async throws -> String {
        struct Body: Encodable { let action = "summarize"; let mapTitle: String; let path: [String]; let children: [String] }
        struct Reply: Decodable { let note: String }
        guard let path = map.root.path(to: id), let node = path.last else { return "" }
        let body = Body(mapTitle: map.title, path: path.map(\.title), children: node.children.map(\.title))
        let reply: Reply = try await BackendClient.shared.invoke("ai", body: body)
        return reply.note
    }

    // What a command in any wording turned out to ask for.
    enum EditResult {
        case map(APINode)                              // merged into the map, so notes, colors and ids survive
        case images(titles: [String], prompt: String)  // AI pictures for these ideas
        case question                                  // an answer in words: the chat about the map
    }

    func edit(_ map: MindMap, command: String, selected: String? = nil) async throws -> EditResult {
        struct Body: Encodable { let action = "edit"; let map: APINode; let command: String; let selected: String? }
        let body = Body(map: APINode(map.root), command: command, selected: selected)
        let reply: EditReply = try await BackendClient.shared.invoke("ai", body: body)
        return try reply.result()
    }

    // New ideas for what the map is missing. The editor adds only the new ones, as suggestions.
    func improve(_ map: MindMap) async throws -> APINode {
        let command = "Suggest what this map is missing: add 4 to 10 new ideas where they help most (missing aspects, examples, steps, risks, questions to answer). Keep every existing idea and every field exactly as it is; only add new ideas. Return the map."
        guard case .map(let tree) = try await edit(map, command: command) else { throw BackendError.aiFailed }
        return tree
    }

    // Templates and copies make maps without AI; they still count toward the month's maps.
    func countNewMap() async throws {
        struct Body: Encodable { let action = "template" }
        struct Reply: Decodable { let counted: Bool }
        let _: Reply = try await BackendClient.shared.invoke("ai", body: Body())
    }

    struct QuizQuestion: Decodable, Identifiable, Equatable {
        var id: String { question }
        let question: String
        let options: [String]
        let answer: Int
        let why: String
    }

    // Study → Quiz: multiple-choice questions about the map.
    func quiz(_ map: MindMap, count: Int = 8) async throws -> [QuizQuestion] {
        struct Body: Encodable { let action = "quiz"; let map: APINode; let count: Int }
        struct Reply: Decodable { let questions: [QuizQuestion] }
        let reply: Reply = try await BackendClient.shared.invoke("ai", body: Body(map: APINode(map.root), count: count))
        return reply.questions.filter { $0.options.indices.contains($0.answer) }
    }

    struct EditReply: Decodable {
        var map: APINode?
        var images: [String]?
        var prompt: String?
        var question: Bool?

        func result() throws -> EditResult {
            if question == true { return .question }
            if let images { return .images(titles: images, prompt: prompt ?? "") }
            guard let map else { throw BackendError.aiFailed }
            return .map(map)
        }
    }

    private struct MapReply: Decodable { let map: APINode; let truncated: Bool? }
    private struct ChildrenReply: Decodable { let children: [APINode] }
}
