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
        var sources: [UUID: [String]] = [:]   // the passages each idea names (checked by the material)
        var fetched: FetchedSource?           // what the server read from a page or a video
    }

    // A passage the server cut from a page or a video, with its time in a video.
    struct FetchedSegment: Decodable, Equatable {
        let id: String
        let text: String
        let start: Double?
        let end: Double?
    }

    struct FetchedSource: Decodable, Equatable {
        let segments: [FetchedSegment]
        let extractedAt: Date

        private enum CodingKeys: String, CodingKey { case segments, extractedAt }

        init(segments: [FetchedSegment], extractedAt: Date) {
            self.segments = segments
            self.extractedAt = extractedAt
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            segments = (try? c.decode([Lossy<FetchedSegment>].self, forKey: .segments))?.compactMap(\.value) ?? []
            let raw = (try? c.decode(String.self, forKey: .extractedAt)) ?? ""
            extractedAt = AccountStore.parseDate(raw) ?? Date()
        }
    }

    // What the server is sent about a material: its passages when the app has them (the text is
    // then only a short label), or a request to get passages back from a page or a video.
    private struct Source: Encodable {
        struct Passage: Encodable { let id: String; let text: String }
        let kind: String
        let value: String
        var segments: [Passage]?
        var withSources: Bool?

        init(_ input: MapInput, segments: [SourceSegment]?) {
            switch input {
            case .topic(let topic):
                (kind, value) = ("topic", topic)
            case .link(let url):
                (kind, value) = ("link", url)
                withSources = true
            case .youtube(let url):
                (kind, value) = ("youtube", url)
                withSources = true
            case .text(let text, _):
                kind = "text"
                if let segments, !segments.isEmpty {
                    self.segments = segments.map { Passage(id: $0.id, text: $0.text) }
                    value = String(text.prefix(300))
                } else {
                    value = text
                }
            }
        }
    }

    // `model` picks the map quality; the server checks the plan allows it. `segments`: the
    // passages of the material, so ideas can say where they come from.
    func generate(_ input: MapInput, model: AIModelOption = AIModelCatalog.defaultMap, segments: [SourceSegment]? = nil) async throws -> Generated {
        struct Body: Encodable { let action = "map"; let source: Source; let quality: String }
        let reply: MapReply = try await BackendClient.shared.invoke("ai", body: Body(source: Source(input, segments: segments), quality: model.apiModelID))
        let root = reply.map.toNode(aiAdded: false)
        return Generated(root: root, truncated: reply.truncated ?? false, sources: reply.map.sources(matching: root), fetched: reply.source)
    }

    func expand(_ map: MindMap, node id: UUID, hint: ExpandHint = .more) async throws -> [MindNode] {
        struct Body: Encodable { let action = "expand"; let mapTitle: String; let path: [String]; let existing: [String]; let hint: String }
        guard let path = map.root.path(to: id), let node = path.last else { return [] }
        let body = Body(mapTitle: map.title, path: path.map(\.title), existing: node.children.map(\.title), hint: hint.rawValue)
        let reply: ChildrenReply = try await BackendClient.shared.invoke("ai", body: body)
        // "Next Steps" become tasks with checkboxes.
        return reply.children.map { MindNode(title: $0.title, isAIAdded: true, isTask: hint == .steps, origin: .ai) }
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

    // MARK: - Continuing a project

    // What a new material adds to the map: the map back with additions, of which the editor keeps
    // only the new ideas (shown for confirmation first). `truncated`: a long material was read from
    // its beginning.
    func addMaterial(_ map: MindMap, input: MapInput, segments: [SourceSegment]? = nil) async throws -> (tree: APINode, truncated: Bool, fetched: FetchedSource?) {
        struct Body: Encodable { let action = "material"; let map: APINode; let source: Source }
        // A topic typed here is read as text.
        let readable: MapInput
        if case .topic(let text) = input { readable = .text(text, source: MapSource(kind: .document, label: "")) } else { readable = input }
        let reply: MapReply = try await BackendClient.shared.invoke("ai", body: Body(map: APINode(map.root), source: Source(readable, segments: segments)))
        return (reply.map, reply.truncated ?? false, reply.source)
    }

    struct NextStep: Decodable, Identifiable, Equatable {
        var id: String { title }
        let title: String
        let detail: String
    }

    // At most three small next actions for an idea; nothing is added until the person chooses.
    func nextSteps(_ map: MindMap, node id: UUID, goal: String) async throws -> [NextStep] {
        struct Body: Encodable { let action = "nextSteps"; let mapTitle: String; let path: [String]; let existing: [String]; let goal: String }
        struct Reply: Decodable { let steps: [NextStep] }
        guard let path = map.root.path(to: id), let node = path.last else { return [] }
        let body = Body(mapTitle: map.title, path: path.map(\.title), existing: node.children.map(\.title), goal: goal)
        let reply: Reply = try await BackendClient.shared.invoke("ai", body: body)
        return Array(reply.steps.filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }.prefix(3))
    }

    // Suggestions for About the Project from the map: a goal (only when there is none), decisions
    // the map states as settled, open questions. None is kept until the person accepts it.
    func suggestMemory(_ map: MindMap, memory: ProjectMemory) async throws -> [ProjectMemory.Suggestion] {
        struct Current: Encodable { let goal: String; let decisions: [String]; let questions: [String] }
        struct Body: Encodable { let action = "memory"; let map: APINode; let memory: Current }
        struct Reply: Decodable { let goal: String?; let decisions: [String]?; let questions: [String]? }
        let current = Current(goal: memory.goal, decisions: memory.decisions.map(\.text), questions: memory.questions.map(\.text))
        let reply: Reply = try await BackendClient.shared.invoke("ai", body: Body(map: APINode(map.root), memory: current))
        var suggestions: [ProjectMemory.Suggestion] = []
        if let goal = reply.goal.flatMap(ProjectMemory.clean), memory.goal.isEmpty { suggestions.append(.init(kind: .goal, text: goal)) }
        suggestions += (reply.decisions ?? []).compactMap(ProjectMemory.clean).map { .init(kind: .decision, text: $0) }
        suggestions += (reply.questions ?? []).compactMap(ProjectMemory.clean).map { .init(kind: .question, text: $0) }
        return suggestions
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
        var src: String?            // the ref of the idea the question is about, when Minor named one
        var nodeID: UUID?           // that idea, only when it is on the map

        private enum CodingKeys: String, CodingKey { case question, options, answer, why, src }
    }

    // Study → Quiz: multiple-choice questions about the map. Ideas go with short refs, so a
    // question can say which idea it is about; a ref the map doesn't have links nothing.
    func quiz(_ map: MindMap, count: Int = 8) async throws -> [QuizQuestion] {
        struct Body: Encodable { let action = "quiz"; let map: APINode; let count: Int }
        struct Reply: Decodable { let questions: [QuizQuestion] }
        let (tree, refs) = MapRefs.make(map.root)
        let reply: Reply = try await BackendClient.shared.invoke("ai", body: Body(map: tree, count: count))
        return reply.questions.filter { $0.options.indices.contains($0.answer) }.map { question in
            var question = question
            question.nodeID = question.src.flatMap { refs[$0] }.flatMap { id in
                id != map.root.id && map.root.node(id) != nil ? id : nil
            }
            return question
        }
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

    private struct MapReply: Decodable { let map: APINode; let truncated: Bool?; let source: FetchedSource? }
    private struct ChildrenReply: Decodable { let children: [APINode] }
}
