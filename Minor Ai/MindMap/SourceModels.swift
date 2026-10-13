//
//  SourceModels.swift
//  Minor Ai
//
//  Where exactly an idea comes from. A material keeps:
//  - its original (a PDF, a scan, a voice recording) in the app's private folder, when there is a
//    file to keep: OriginalAsset says which file, its size, its SHA-256 and whether it is still kept;
//  - its passages (SourceSegment): the text the AI read, cut into numbered pieces with where each
//    one is in the original — a PDF page and the place on it, a scan line, seconds into a recording
//    or a video;
//  - citations: which passages an idea came from. The AI names passages only by their ids; the app
//    checks every id against the material and quotes only its own saved text, so a quote can't be
//    made up. An id that doesn't check out leaves the citation unverified instead of being guessed.
//
//  Everything is versioned: attaching a different file starts a new version, and citations of an
//  earlier version are shown as needing a check, never moved to new places by guesswork. Materials
//  that existed before have no passages; they say "only the text is saved" and can get their
//  original attached. Nothing here is shared with people the map is shared with.
//

import CryptoKit
import Foundation
import PDFKit
import UIKit

// A file kept as a material's original, by its content (the same file is kept once).
struct OriginalAsset: Codable, Equatable {
    enum State: String, Codable { case ready, removed }

    var id = UUID()
    var path: String       // inside the Originals folder; never the person's own path
    var mime: String
    var size: Int
    var sha256: String
    var name: String       // the file name as picked, for showing
    var state: State = .ready
    var addedAt = Date()

    var isPDF: Bool { mime == "application/pdf" }
    var isAudio: Bool { mime.hasPrefix("audio/") }
}

// A numbered piece of a material's text and where it is in the original.
struct SourceSegment: Codable, Equatable, Identifiable {
    var id: String            // "s12", stable within the material's version
    var materialID: UUID
    var version: Int
    var text: String
    var page: Int?            // file page index, from 0 (PDF, scan); shown from 1
    var range: [Int]?         // [location, length] in UTF-16: in the page's text (PDF) or the material's text
    var rects: [[Double]]?    // [x, y, width, height] in 0…1 of the page from its top left (PDF text layer, OCR)
    var start: Double?        // seconds into a recording or a video
    var end: Double?
    var confidence: Double?   // recognized text (OCR, speech): the least certain part, 0…1

    var nsRange: NSRange? {
        guard let range, range.count == 2, range[0] >= 0, range[1] > 0 else { return nil }
        return NSRange(location: range[0], length: range[1])
    }

    // Recognized text Vision or Speech wasn't sure about: a quote from it needs a look at the original.
    var isUncertain: Bool { (confidence ?? 1) < 0.6 }
}

// Which passages of a material an idea came from.
struct Citation: Codable, Equatable, Identifiable {
    enum Status: String, Codable {
        case exact        // every id named a passage of this material
        case unverified   // the AI named passages the material doesn't have
    }

    var id = UUID()
    var nodeID: UUID
    var segmentIDs: [String]
    var version: Int
    var excerpt: String       // copied from the saved passages when the citation was made
    var status: Status
    var createdAt = Date()

    static let excerptLimit = 400

    // A citation from the ids the AI gave, checked against the material: each id must be one of its
    // passages, of its current version, with a place that fits the original (a page it has, a time
    // within the recording). No ids: no citation (the idea only links to the material).
    static func make(nodeID: UUID, ids: [String]?, in material: ProjectMaterial) -> Citation? {
        // Nothing named, or nothing of the material kept to check against: no citation.
        guard let ids, !ids.isEmpty, material.segments?.isEmpty == false else { return nil }
        let passages = Dictionary((material.segments ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen: Set<String> = []
        let valid = ids.compactMap { id -> SourceSegment? in
            guard seen.insert(id).inserted, let segment = passages[id], material.fits(segment) else { return nil }
            return segment
        }
        guard !valid.isEmpty else {
            return Citation(nodeID: nodeID, segmentIDs: [], version: material.version, excerpt: "", status: .unverified)
        }
        var excerpt = valid.map(\.text).joined(separator: " … ")
        if excerpt.count > excerptLimit { excerpt = String(excerpt.prefix(excerptLimit - 1)) + "…" }
        return Citation(nodeID: nodeID, segmentIDs: valid.map(\.id), version: material.version, excerpt: excerpt, status: .exact)
    }
}

extension ProjectMaterial {
    // A passage belongs here and its place is possible in the original.
    func fits(_ segment: SourceSegment) -> Bool {
        guard segment.materialID == id, segment.version == version else { return false }
        if let page = segment.page {
            guard page >= 0, page < max(pages ?? 1, 1) else { return false }
        }
        if let start = segment.start {
            guard start >= 0, (segment.end ?? start) >= start else { return false }
            if let duration, start > duration + 1 { return false }
        }
        return true
    }

    // Citations of one idea.
    func citations(of nodeID: UUID) -> [Citation] {
        (citations ?? []).filter { $0.nodeID == nodeID }
    }

    func segment(_ id: String) -> SourceSegment? {
        segments?.first { $0.id == id }
    }

    // What there is of the original now.
    enum OriginalStatus: Equatable {
        case none          // nothing was kept (old materials, links, pasted text)
        case available     // on this iPhone
        case missing       // recorded but the file isn't there
        case removed       // the person removed it
    }

    var originalStatus: OriginalStatus {
        guard let original else { return .none }
        if original.state == .removed { return .removed }
        return OriginalStore.url(for: original) == nil ? .missing : .available
    }

    // A document or scan made before originals were kept: its original can be attached.
    var canAttachOriginal: Bool { kind == .document || kind == .scan }
}

// What was read from a file before a material exists (a map is still being built, or Add Material
// waits for a decision). The material takes it over by its id.
struct SourceDraft {
    let materialID: UUID
    var version = 1
    var original: OriginalAsset?
    var originalError: String?     // why the original couldn't be kept (the text still is)
    var text: String
    var segments: [SourceSegment]
    var pages: Int?
    var duration: Double?
}

// Drafts by the text a map is built from, until the map's material is made.
@MainActor
final class SourceDrafts {
    static let shared = SourceDrafts()
    private var drafts: [String: SourceDraft] = [:]

    // `text`: exactly the text the map is built from (the input's text).
    func put(_ draft: SourceDraft, for text: String) {
        drafts[Self.key(text)] = draft
    }

    func draft(for text: String) -> SourceDraft? { drafts[Self.key(text)] }

    @discardableResult
    func take(for text: String) -> SourceDraft? { drafts.removeValue(forKey: Self.key(text)) }

    // Originals of drafts not yet made into materials: never cleaned up meanwhile.
    var heldPaths: Set<String> { Set(drafts.values.compactMap { $0.original?.path }) }

    // A draft for any text input: the one read from a file, or passages cut from the text itself.
    func prepare(for input: MapInput) -> SourceDraft? {
        guard case .text(let text, let source) = input, source.kind != .topic else { return nil }
        if let draft = draft(for: text) { return draft }
        let id = UUID()
        let kept = String(text.prefix(ProjectMaterial.textLimit))
        let draft = SourceDraft(materialID: id, text: kept, segments: SourceSegmenter.text(kept, materialID: id, version: 1))
        put(draft, for: text)
        return draft
    }

    private static func key(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Cutting text into passages

enum SourceSegmenter {
    static let target = 280     // characters a passage aims for
    static let maximum = 900    // a passage is never longer

    // Passages of `text` as UTF-16 ranges: sentences grouped up to `target` characters, never across
    // a block (a paragraph, a heading, a line that ends a sentence), long sentences cut in pieces.
    static func ranges(in text: String) -> [NSRange] {
        let ns = text as NSString
        var groups: [NSRange] = []
        for block in blocks(in: ns) {
            var sentences: [NSRange] = []
            ns.enumerateSubstrings(in: block, options: [.bySentences, .substringNotRequired]) { _, range, _, _ in
                sentences.append(range)
            }
            if sentences.isEmpty { sentences = [block] }
            var current: NSRange?
            for sentence in sentences {
                for piece in pieces(of: sentence, in: ns) {
                    if let open = current, open.length + piece.length > target {
                        groups.append(open)
                        current = nil
                    }
                    if let open = current {
                        current = NSRange(location: open.location, length: NSMaxRange(piece) - open.location)
                    } else {
                        current = piece
                    }
                }
            }
            if let open = current { groups.append(open) }
        }
        return groups.filter { ns.substring(with: $0).contains { !$0.isWhitespace } }
    }

    // Lines joined into blocks; a block ends at an empty line, after a line that ends a sentence,
    // and after a short line without an ending (a heading).
    static func blocks(in ns: NSString) -> [NSRange] {
        var lines: [NSRange] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byLines, .substringNotRequired]) { _, range, _, _ in
            lines.append(range)
        }
        var blocks: [NSRange] = []
        var current: NSRange?
        var previous = ""
        for line in lines {
            let content = ns.substring(with: line).trimmingCharacters(in: .whitespaces)
            if content.isEmpty {
                if let open = current { blocks.append(open) }
                current = nil
                continue
            }
            if let open = current {
                let ended = previous.last.map { ".!?…:;".contains($0) } ?? false
                if ended || previous.count < 40 {
                    blocks.append(open)
                    current = nil
                }
            }
            if let open = current {
                current = NSRange(location: open.location, length: NSMaxRange(line) - open.location)
            } else {
                current = line
            }
            previous = content
        }
        if let open = current { blocks.append(open) }
        return blocks
    }

    // A sentence longer than `maximum` in pieces, never inside a character.
    private static func pieces(of sentence: NSRange, in ns: NSString) -> [NSRange] {
        var pieces: [NSRange] = []
        var location = sentence.location
        while location < NSMaxRange(sentence) {
            var piece = ns.rangeOfComposedCharacterSequences(for: NSRange(location: location, length: min(maximum, NSMaxRange(sentence) - location)))
            piece.length = min(piece.length, NSMaxRange(sentence) - piece.location)
            guard piece.length > 0 else { break }
            pieces.append(piece)
            location = NSMaxRange(piece)
        }
        return pieces
    }

    private static func clean(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    // Plain text (TXT, RTF, pasted, a chat, a link's saved text): passages with ranges in the text.
    static func text(_ text: String, materialID: UUID, version: Int) -> [SourceSegment] {
        let ns = text as NSString
        var out: [SourceSegment] = []
        for range in ranges(in: text) {
            let piece = clean(ns.substring(with: range))
            guard !piece.isEmpty else { continue }
            out.append(SourceSegment(id: "s\(out.count + 1)", materialID: materialID, version: version, text: piece, range: [range.location, range.length]))
        }
        return out
    }

    // A PDF: passages per page with their range in the page's text and, where the PDF's text layer
    // gives it, the lines they cover on the page. The text is what the reader uses: pages joined.
    static func pdf(_ document: PDFDocument, materialID: UUID, version: Int, textLimit: Int = ProjectMaterial.textLimit) -> (text: String, segments: [SourceSegment]) {
        var out: [SourceSegment] = []
        var texts: [String] = []
        var total = 0
        for index in 0..<document.pageCount {
            guard total < textLimit, let page = document.page(at: index), let string = page.string, !string.isEmpty else { continue }
            texts.append(string)
            total += string.count + 1
            let bounds = page.bounds(for: .cropBox)
            for range in ranges(in: string) {
                let piece = clean((string as NSString).substring(with: range))
                guard !piece.isEmpty else { continue }
                var segment = SourceSegment(id: "s\(out.count + 1)", materialID: materialID, version: version, text: piece, page: index, range: [range.location, range.length])
                segment.rects = lineRects(page: page, range: range, bounds: bounds)
                out.append(segment)
            }
        }
        let text = texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (String(text.prefix(textLimit)), out)
    }

    // The lines a range covers, in 0…1 of the page from its top left; nil when the PDF doesn't say.
    static func lineRects(page: PDFPage, range: NSRange, bounds: CGRect) -> [[Double]]? {
        guard bounds.width > 0, bounds.height > 0, let selection = page.selection(for: range) else { return nil }
        let lines = selection.selectionsByLine().prefix(16).map { $0.bounds(for: page) }.filter { $0.width > 0 && $0.height > 0 }
        guard !lines.isEmpty else { return nil }
        return lines.map { rect in
            [Double((rect.minX - bounds.minX) / bounds.width), Double((bounds.maxY - rect.maxY) / bounds.height),
             Double(rect.width / bounds.width), Double(rect.height / bounds.height)]
        }
    }

    // Scanned pages: recognized lines grouped into passages, each with the boxes of its lines.
    static func scan(_ pages: [[TextRecognizer.Line]], materialID: UUID, version: Int) -> (text: String, segments: [SourceSegment]) {
        var out: [SourceSegment] = []
        var pageTexts: [String] = []
        for (index, lines) in pages.enumerated() {
            pageTexts.append(lines.map(\.text).joined(separator: "\n"))
            var group: [TextRecognizer.Line] = []
            func close() {
                guard !group.isEmpty else { return }
                let text = clean(group.map(\.text).joined(separator: " "))
                if !text.isEmpty {
                    out.append(SourceSegment(id: "s\(out.count + 1)", materialID: materialID, version: version, text: text, page: index,
                                             rects: group.map { [Double($0.box.minX), Double($0.box.minY), Double($0.box.width), Double($0.box.height)] },
                                             confidence: group.map(\.confidence).min()))
                }
                group = []
            }
            for line in lines {
                // A wide gap above a line starts a new paragraph.
                if let last = group.last, line.box.minY - last.box.maxY > last.box.height * 1.2 { close() }
                group.append(line)
                let length = group.reduce(0) { $0 + $1.text.count }
                if length >= target || line.text.hasSuffix(".") && length > target / 2 { close() }
            }
            close()
        }
        return (pageTexts.filter { !$0.isEmpty }.joined(separator: "\n\n"), out)
    }

    // Words heard in a recording, with their times, grouped into passages at pauses and sentence ends.
    static func speech(_ words: [VoiceRecorder.Word], materialID: UUID, version: Int) -> [SourceSegment] {
        var out: [SourceSegment] = []
        var group: [VoiceRecorder.Word] = []
        func close() {
            guard let first = group.first, let last = group.last else { return }
            let text = group.map(\.text).joined(separator: " ")
            out.append(SourceSegment(id: "s\(out.count + 1)", materialID: materialID, version: version, text: text,
                                     start: first.start, end: last.start + last.duration, confidence: group.map(\.confidence).min()))
            group = []
        }
        for word in words {
            if let last = group.last, word.start - (last.start + last.duration) > 1.2 { close() }
            group.append(word)
            let length = group.reduce(0) { $0 + $1.text.count + 1 }
            let sentenceEnd = word.text.last.map { ".!?…".contains($0) } ?? false
            if length >= 220 || sentenceEnd && length > 40 { close() }
        }
        close()
        return out
    }

    // Passages the server cut from a page or a video it read.
    static func fetched(_ passages: [MapService.FetchedSegment], materialID: UUID, version: Int) -> [SourceSegment] {
        var seen: Set<String> = []
        return passages.compactMap { item in
            let text = clean(item.text)
            guard !text.isEmpty, item.id.range(of: #"^s[1-9]\d{0,5}$"#, options: .regularExpression) != nil, seen.insert(item.id).inserted else { return nil }
            var segment = SourceSegment(id: item.id, materialID: materialID, version: version, text: String(text.prefix(2000)))
            if let start = item.start, start >= 0 {
                segment.start = start
                segment.end = max(start, item.end ?? start)
            }
            return segment
        }
    }
}

// MARK: - Times

enum SourceTime {
    // "2:14" or "1:02:14": whole seconds, never more precise than the recording allows.
    static func text(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
