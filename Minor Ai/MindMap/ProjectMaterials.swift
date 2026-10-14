//
//  ProjectMaterials.swift
//  Minor Ai
//
//  Where a project's ideas come from, and what it remembers.
//  - Materials: the documents, links, notes and chats a map was made from or that were added to
//    it later. The text taken from them is kept on this iPhone, and since 2.1 the original file and
//    the passages ideas cite (SourceModels.swift), privately: sharing a map never shares them.
//  - Each idea records its origin: a material, Minor (an AI suggestion), a person, or a template.
//    Nothing is recorded for ideas from before this existed, and that is said plainly instead of
//    guessing.
//  - About the Project: the goal, decisions and open questions the person confirmed, kept on this
//    iPhone and given to the project chat as context.
//

import Foundation

// Where an idea came from. Stored as a short string ("you", "ai", "template", "m:<id>").
enum NodeOrigin: Equatable, Codable {
    case person
    case ai
    case template
    case material(UUID)

    var materialID: UUID? {
        if case .material(let id) = self { return id }
        return nil
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "you": self = .person
        case "ai": self = .ai
        case "template": self = .template
        default:
            guard raw.hasPrefix("m:"), let id = UUID(uuidString: String(raw.dropFirst(2))) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown origin"))
            }
            self = .material(id)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .person: try c.encode("you")
        case .ai: try c.encode("ai")
        case .template: try c.encode("template")
        case .material(let id): try c.encode("m:" + id.uuidString)
        }
    }
}

extension MindNode {
    // This idea and everything below it with `origin`, keeping origins already recorded.
    func withOrigin(_ origin: NodeOrigin) -> MindNode {
        var copy = self
        if copy.origin == nil { copy.origin = origin }
        copy.children = children.map { $0.withOrigin(origin) }
        return copy
    }

    // Ideas in this branch whose origin is `origin` (by material id for materials).
    func count(from origin: NodeOrigin) -> Int {
        (self.origin == origin ? 1 : 0) + children.reduce(0) { $0 + $1.count(from: origin) }
    }
}

// A new idea a material brings, under the existing idea it belongs to (Add Material).
struct MaterialAddition: Identifiable, Equatable {
    var id: UUID { node.id }
    let parentID: UUID
    let parentPath: [String]   // from the topic down to the parent
    let node: MindNode         // with the ideas under it
    var sources: [UUID: [String]] = [:]   // passages each of these ideas names (checked when added)
}

extension MindNode {
    // Only what a reply adds to this tree: new ideas matched to their existing parents by title.
    // Ideas that already exist are never changed.
    func additions(from reply: APINode) -> [MaterialAddition] {
        var result: [MaterialAddition] = []
        func key(_ title: String) -> String { title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        func walk(_ incoming: APINode, into existing: MindNode, path: [String]) {
            for child in incoming.children ?? [] {
                let wanted = key(child.title)
                guard !wanted.isEmpty else { continue }
                if let match = existing.children.first(where: { key($0.title) == wanted }) {
                    walk(child, into: match, path: path + [match.title])
                } else {
                    let node = child.toNode(aiAdded: true, collapseBelow: .max)
                    result.append(MaterialAddition(parentID: existing.id, parentPath: path, node: node, sources: child.sources(matching: node)))
                }
            }
        }
        walk(reply, into: self, path: [title])
        return result
    }
}

struct ProjectMaterial: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: MapSource.Kind
    var title: String
    var text: String?       // the text taken from it, as Minor read it (at most `textLimit` characters)
    var url: String?        // links and videos
    var pages: Int?         // documents and scans
    var addedAt = Date()
    // Since 2.1 (all optional, so earlier materials read as "only the text is saved"):
    var original: OriginalAsset?
    var segments: [SourceSegment]?
    var citations: [Citation]?
    var version = 1             // goes up when a different original replaces the first
    var extractedAt: Date?      // when a page or a video was read
    var duration: Double?       // a recording's length, in seconds

    static let textLimit = 400_000   // as much as a paid plan's map reads

    init(kind: MapSource.Kind, title: String, text: String? = nil, url: String? = nil, pages: Int? = nil) {
        self.kind = kind
        self.title = String(title.prefix(200))
        self.text = text.map { String($0.prefix(Self.textLimit)) }
        self.url = url
        self.pages = pages
    }

    private enum CodingKeys: String, CodingKey { case id, kind, title, text, url, pages, addedAt, original, segments, citations, version, extractedAt, duration }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = (try? c.decode(MapSource.Kind.self, forKey: .kind)) ?? .document
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        text = try? c.decodeIfPresent(String.self, forKey: .text)
        url = try? c.decodeIfPresent(String.self, forKey: .url)
        pages = try? c.decodeIfPresent(Int.self, forKey: .pages)
        addedAt = (try? c.decodeIfPresent(Date.self, forKey: .addedAt)) ?? Date()
        original = try? c.decodeIfPresent(OriginalAsset.self, forKey: .original)
        segments = (try? c.decodeIfPresent([Lossy<SourceSegment>].self, forKey: .segments))?.compactMap(\.value)
        citations = (try? c.decodeIfPresent([Lossy<Citation>].self, forKey: .citations))?.compactMap(\.value)
        version = (try? c.decodeIfPresent(Int.self, forKey: .version)) ?? 1
        extractedAt = try? c.decodeIfPresent(Date.self, forKey: .extractedAt)
        duration = try? c.decodeIfPresent(Double.self, forKey: .duration)
    }

    // A material from what was read before it existed: the file's original and its passages.
    init(kind: MapSource.Kind, title: String, draft: SourceDraft, url: String? = nil) {
        self.init(kind: kind, title: title, text: draft.text, url: url, pages: draft.pages)
        id = draft.materialID
        version = draft.version
        original = draft.original
        segments = draft.segments.isEmpty ? nil : draft.segments
        duration = draft.duration
    }

    // What the server read from a page or a video, kept as this material's text and passages.
    mutating func adopt(_ fetched: MapService.FetchedSource) {
        let passages = SourceSegmenter.fetched(fetched.segments, materialID: id, version: version)
        guard !passages.isEmpty else { return }
        segments = passages
        text = String(passages.map(\.text).joined(separator: "\n\n").prefix(Self.textLimit))
        extractedAt = fetched.extractedAt
    }

    // Citations for ideas from the ids the AI gave them (checked; see Citation.make).
    mutating func cite(_ sources: [UUID: [String]]) {
        var list = citations ?? []
        for (nodeID, ids) in sources {
            guard let citation = Citation.make(nodeID: nodeID, ids: ids, in: self) else { continue }
            list.removeAll { $0.nodeID == nodeID }
            list.append(citation)
        }
        citations = list.isEmpty ? nil : list
    }

    // The material a map was made from, when there is something to keep (a topic is just a prompt).
    static func from(_ input: MapInput, draft: SourceDraft? = nil) -> ProjectMaterial? {
        switch input {
        case .topic: return nil
        case .link(let url): return ProjectMaterial(kind: .link, title: url, url: url)
        case .youtube(let url): return ProjectMaterial(kind: .youtube, title: url, url: url)
        case .text(let text, let source):
            guard source.kind != .topic else { return nil }
            if let draft { return ProjectMaterial(kind: source.kind, title: source.label, draft: draft) }
            return ProjectMaterial(kind: source.kind, title: source.label, text: text)
        }
    }

    // A sentence of the material that mentions `phrase` (found by searching the saved text, never
    // written by AI), or nil. Only for showing where a word is; it is not a citation.
    func passage(mentioning phrase: String) -> String? {
        let wanted = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard wanted.count >= 3, let text, let range = text.range(of: wanted, options: [.caseInsensitive, .diacriticInsensitive]) else { return nil }
        let stops: Set<Character> = [".", "!", "?", "\n", "…"]
        var start = range.lowerBound
        var steps = 0
        while start > text.startIndex, steps < 220 {
            let previous = text.index(before: start)
            if stops.contains(text[previous]) { break }
            start = previous
            steps += 1
        }
        var end = range.upperBound
        steps = 0
        while end < text.endIndex, steps < 220 {
            let character = text[end]
            end = text.index(after: end)
            steps += 1
            if stops.contains(character) { break }
        }
        let sentence = text[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)
        return sentence.isEmpty ? nil : sentence
    }
}

// Materials per map, one file each (they can be long), in Application Support/Materials.
@MainActor
final class ProjectMaterialStore: ObservableObject {
    static let shared = ProjectMaterialStore()

    // Loaded on first use, without publishing (reading happens while views draw); changes publish.
    private var cache: [UUID: [ProjectMaterial]] = [:]
    @Published private(set) var revision = 0
    private let folder: URL
    private let io = DispatchQueue(label: "com.minorailifegroup.MinorAI.materials", qos: .utility)

    private init() {
        let base = FileManager.default.appSupportURL
        folder = base.appendingPathComponent("Materials", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func file(_ mapID: UUID) -> URL { folder.appendingPathComponent("\(mapID.uuidString).json") }

    func materials(for mapID: UUID) -> [ProjectMaterial] {
        if let cached = cache[mapID] { return cached }
        let decoder = JSONDecoder()
        let url = file(mapID)
        // After any write or delete still in progress.
        let loaded = io.sync { try? Data(contentsOf: url) }
            .flatMap { try? decoder.decode([Lossy<ProjectMaterial>].self, from: $0) }?
            .compactMap(\.value) ?? []
        cache[mapID] = loaded
        return loaded
    }

    func material(_ id: UUID, in mapID: UUID) -> ProjectMaterial? {
        materials(for: mapID).first { $0.id == id }
    }

    func add(_ material: ProjectMaterial, to mapID: UUID) {
        var list = materials(for: mapID)
        list.append(material)
        write(list, for: mapID)
    }

    func remove(_ id: UUID, from mapID: UUID) {
        write(materials(for: mapID).filter { $0.id != id }, for: mapID)
        cleanOriginals()
    }

    // Changes one material in place; nothing happens when it is gone.
    @discardableResult
    func update(_ id: UUID, in mapID: UUID, _ change: (inout ProjectMaterial) -> Void) -> ProjectMaterial? {
        var list = materials(for: mapID)
        guard let index = list.firstIndex(where: { $0.id == id }) else { return nil }
        change(&list[index])
        write(list, for: mapID)
        return list[index]
    }

    // Each citation of an idea, with its material.
    func citations(of nodeID: UUID, in mapID: UUID) -> [(material: ProjectMaterial, citation: Citation)] {
        materials(for: mapID).flatMap { material in material.citations(of: nodeID).map { (material, $0) } }
    }

    // The person removed the original: its passages and quotes stay, the file goes.
    func removeOriginal(of id: UUID, in mapID: UUID) {
        update(id, in: mapID) { $0.original?.state = .removed }
        cleanOriginals()
    }

    // A copy of the map gets copies of its materials (the ideas point to them by id); citations
    // follow the copied ideas' new ids.
    func copy(from source: UUID, to target: UUID, renamed: [UUID: UUID] = [:]) {
        var list = materials(for: source)
        guard !list.isEmpty else { return }
        for i in list.indices {
            list[i].citations = list[i].citations?.compactMap { citation in
                guard let node = renamed[citation.nodeID] else { return renamed.isEmpty ? citation : nil }
                var copy = citation
                copy.id = UUID()
                copy.nodeID = node
                return copy
            }
        }
        write(list, for: target)
    }

    // The map was deleted.
    func delete(_ mapID: UUID) {
        cache[mapID] = []
        revision += 1
        let url = file(mapID)
        io.async { try? FileManager.default.removeItem(at: url) }
        cleanOriginals()
    }

    // Sign out or account deletion.
    func deleteAll() {
        cache = [:]
        revision += 1
        let folder = folder
        io.async {
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            OriginalStore.removeAll()
        }
    }

    // Original files no material refers to (in any map) are removed, after pending writes.
    func cleanOriginals() {
        let folder = folder
        let held = SourceDrafts.shared.heldPaths
        io.async {
            let decoder = JSONDecoder()
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            var used = held
            for file in files where file.pathExtension == "json" {
                guard let data = try? Data(contentsOf: file),
                      let list = try? decoder.decode([Lossy<ProjectMaterial>].self, from: data) else {
                    // A file that can't be read might still need its originals: keep everything.
                    if FileManager.default.fileExists(atPath: file.path) { return }
                    continue
                }
                for material in list.compactMap(\.value) {
                    if let original = material.original, original.state == .ready { used.insert(original.path) }
                }
            }
            OriginalStore.removeUnused(keeping: used)
        }
    }

    func flush() { io.sync {} }

    private func write(_ list: [ProjectMaterial], for mapID: UUID) {
        cache[mapID] = list
        revision += 1
        let url = file(mapID)
        let encoder = JSONEncoder()
        io.async {
            if list.isEmpty {
                try? FileManager.default.removeItem(at: url)
                return
            }
            guard let data = try? encoder.encode(list) else { return }
            try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }
}

// MARK: - About the Project

struct ProjectMemory: Codable, Equatable {
    struct Item: Codable, Equatable, Identifiable {
        var id = UUID()
        var text: String
        var byMinor = false    // proposed by Minor and accepted by the person

        init(text: String, byMinor: Bool = false) {
            self.text = text
            self.byMinor = byMinor
        }
    }

    // Something Minor proposes to remember; nothing is kept until the person accepts it.
    struct Suggestion: Codable, Equatable, Identifiable {
        enum Kind: String, Codable { case goal, decision, question }
        var id = UUID()
        var kind: Kind
        var text: String
    }

    var goal = ""
    var decisions: [Item] = []
    var questions: [Item] = []
    var suggestions: [Suggestion] = []
    var updatedAt = Date()

    var isEmpty: Bool { goal.isEmpty && decisions.isEmpty && questions.isEmpty }

    static let itemLimit = 20
    static let textLimit = 300

    static func clean(_ text: String) -> String? {
        let line = text.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return line.isEmpty ? nil : String(line.prefix(textLimit))
    }

    private enum CodingKeys: String, CodingKey { case goal, decisions, questions, suggestions, updatedAt }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        goal = (try? c.decodeIfPresent(String.self, forKey: .goal)) ?? ""
        decisions = (try? c.decodeIfPresent([Item].self, forKey: .decisions)) ?? []
        questions = (try? c.decodeIfPresent([Item].self, forKey: .questions)) ?? []
        suggestions = (try? c.decodeIfPresent([Suggestion].self, forKey: .suggestions)) ?? []
        updatedAt = (try? c.decodeIfPresent(Date.self, forKey: .updatedAt)) ?? Date()
    }

    // What the project chat is told, so answers build on what the person settled.
    var contextText: String? {
        guard !isEmpty else { return nil }
        var lines = ["What the user confirmed about this project (use it as settled unless they say otherwise):"]
        if !goal.isEmpty { lines.append("Goal: \(goal)") }
        if !decisions.isEmpty { lines.append("Decisions: " + decisions.map(\.text).joined(separator: "; ")) }
        if !questions.isEmpty { lines.append("Open questions (not decided yet): " + questions.map(\.text).joined(separator: "; ")) }
        return lines.joined(separator: "\n")
    }
}

@MainActor
final class ProjectMemoryStore: ObservableObject {
    static let shared = ProjectMemoryStore()

    @Published private(set) var memories: [UUID: ProjectMemory] = [:]
    private let file: URL
    private let io = DispatchQueue(label: "com.minorailifegroup.MinorAI.memory", qos: .utility)

    private init() {
        let base = FileManager.default.appSupportURL
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        file = base.appendingPathComponent("ProjectMemory.json")
        if let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode([String: Lossy<ProjectMemory>].self, from: data) {
            for (key, value) in saved {
                if let id = UUID(uuidString: key), let memory = value.value { memories[id] = memory }
            }
        }
    }

    func memory(for mapID: UUID) -> ProjectMemory { memories[mapID] ?? ProjectMemory() }

    func update(_ mapID: UUID, _ change: (inout ProjectMemory) -> Void) {
        var memory = memory(for: mapID)
        change(&memory)
        memory.decisions = Array(memory.decisions.prefix(ProjectMemory.itemLimit))
        memory.questions = Array(memory.questions.prefix(ProjectMemory.itemLimit))
        memory.updatedAt = Date()
        memories[mapID] = memory.isEmpty && memory.suggestions.isEmpty ? nil : memory
        persist()
    }

    func copy(from source: UUID, to target: UUID) {
        guard let memory = memories[source] else { return }
        memories[target] = memory
        persist()
    }

    func delete(_ mapID: UUID) {
        guard memories[mapID] != nil else { return }
        memories[mapID] = nil
        persist()
    }

    func deleteAll() {
        memories = [:]
        persist()
    }

    func flush() { io.sync {} }

    private func persist() {
        let snapshot = Dictionary(uniqueKeysWithValues: memories.map { ($0.key.uuidString, $0.value) })
        let file = file
        io.async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }
}
