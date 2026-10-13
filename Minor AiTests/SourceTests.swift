//
//  SourceTests.swift
//  Minor AiTests
//
//  Originals, passages and citations: earlier materials still load as "only the text"; a PDF keeps
//  its original and finds a sentence on page 4 with its lines, also after it is saved and read back;
//  citations take only ids the material has; another file is a new version and earlier citations
//  need a check; the same file comes back without changing anything; recordings, scans, pages and
//  videos keep their places.
//

import Foundation
import PDFKit
import Testing
import UIKit
@testable import Minor_Ai

// One at a time: removing materials cleans unused originals in the background.
@MainActor
@Suite(.serialized)
struct SourceTests {
    // A PDF with real text: page 4 of `pages` says `sentence` (in a paragraph of its own).
    private func pdf(pages: Int = 6, sentence: String = "Episodes are talks with practitioners of 20 to 30 minutes.", other: String = "Background") -> URL {
        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { context in
            for index in 0..<pages {
                context.beginPage()
                ("Page heading \(index + 1)" as NSString).draw(at: CGPoint(x: 60, y: 60), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 28)])
                let body = index == 3
                    ? "The podcast is built around honest conversations.\n\n\(sentence)\n\nEach episode keeps to one topic."
                    : "\(other) text of page \(index + 1) about the project and its plans, long enough to be read."
                (body as NSString).draw(in: CGRect(x: 60, y: 130, width: 492, height: 600), withAttributes: [.font: UIFont.systemFont(ofSize: 18)])
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
        try? data.write(to: url)
        return url
    }

    private func roundTrip(_ material: ProjectMaterial) throws -> ProjectMaterial {
        try JSONDecoder().decode(ProjectMaterial.self, from: JSONEncoder().encode(material))
    }

    @Test func earlierMaterialsLoadWithOnlyTheirText() throws {
        let json = #"{"id":"\#(UUID().uuidString)","kind":"document","title":"Notes.pdf","text":"Some saved text.","pages":3,"addedAt":700000000}"#
        let material = try JSONDecoder().decode(ProjectMaterial.self, from: Data(json.utf8))
        #expect(material.original == nil && material.segments == nil && material.citations == nil)
        #expect(material.version == 1)
        #expect(material.originalStatus == .none)
        #expect(material.canAttachOriginal)
        // No passages: nothing an idea could cite, so no citation is made.
        #expect(Citation.make(nodeID: UUID(), ids: ["s1"], in: material) == nil)
    }

    @Test func passagesFollowParagraphsAndHeadingsAndMapBackToTheText() {
        let text = "Pricing\nThree plans keep it simple.\n\nFree gives 3 maps a month. Plus is $12.99 and PRO is $24.99.\n\nYearly saves up to 27%."
        let id = UUID()
        let passages = SourceSegmenter.text(text, materialID: id, version: 1)
        #expect(passages.map(\.text) == ["Pricing", "Three plans keep it simple.", "Free gives 3 maps a month. Plus is $12.99 and PRO is $24.99.", "Yearly saves up to 27%."])
        #expect(passages.map(\.id) == ["s1", "s2", "s3", "s4"])
        for passage in passages {
            let range = try! #require(passage.nsRange)
            #expect((text as NSString).substring(with: range).split(whereSeparator: \.isWhitespace).joined(separator: " ") == passage.text)
            #expect(passage.materialID == id && passage.page == nil)
        }
        // A sentence longer than the limit is cut, never inside a character.
        let long = String(repeating: "слово ", count: 400)
        let pieces = SourceSegmenter.text(long, materialID: id, version: 1)
        #expect(pieces.count > 1 && pieces.allSatisfy { $0.text.count <= SourceSegmenter.maximum })
    }

    @Test func aPDFKeepsItsOriginalAndFindsTheSentenceOnPage4() throws {
        let sentence = "Episodes are talks with practitioners of 20 to 30 minutes."
        let url = pdf(sentence: sentence)
        let document = try Attachments.readDocument(at: url, maxPages: 300)
        let draft = SourceImport.document(at: url, text: document.text, pages: document.pages)
        let original = try #require(draft.original)
        let kept = try #require(OriginalStore.url(for: original))
        #expect(original.isPDF && original.sha256 == OriginalStore.sha256(of: url) && original.size > 0)
        #expect(kept.deletingLastPathComponent().standardizedFileURL == OriginalStore.folder.standardizedFileURL)
        #expect(!original.path.contains("/"))   // never the person's own path

        var material = ProjectMaterial(kind: .document, title: "Brief.pdf", draft: draft)
        let passage = try #require(material.segments?.first { $0.text == sentence })
        #expect(passage.page == 3)   // shown as page 4
        #expect(!(passage.rects ?? []).isEmpty)
        let node = UUID()
        material.cite([node: [passage.id]])

        // Saved and read again, as after a relaunch: the same original, page and marked lines.
        let reopened = try roundTrip(material)
        #expect(reopened.originalStatus == .available)
        let citation = try #require(reopened.citations(of: node).first)
        #expect(citation.status == .exact && citation.excerpt == sentence && citation.version == 1)
        let again = try #require(reopened.segment(citation.segmentIDs[0]))
        let keptOriginal = try #require(reopened.original)
        let keptURL = try #require(OriginalStore.url(for: keptOriginal))
        let file = try #require(PDFDocument(url: keptURL))
        let index = try #require(again.page)
        let page = try #require(file.page(at: index))
        let rects = PDFSourceView.checkedRects(again, on: page, isScan: false)
        #expect(!rects.isEmpty)
        // A passage whose text the page doesn't have isn't marked.
        var wrong = again
        wrong.text = "Something the page never said."
        #expect(PDFSourceView.checkedRects(wrong, on: page, isScan: false).isEmpty)
    }

    @Test func citationsTakeOnlyPassagesTheMaterialHas() throws {
        let id = UUID()
        var material = ProjectMaterial(kind: .document, title: "Doc", draft: SourceDraft(
            materialID: id, text: "One. Two.", segments: [
                SourceSegment(id: "s1", materialID: id, version: 1, text: "One.", page: 0),
                SourceSegment(id: "s2", materialID: id, version: 1, text: "Two.", page: 5),   // page 6 of 2: impossible
                SourceSegment(id: "s3", materialID: UUID(), version: 1, text: "Elsewhere."),  // another material
                SourceSegment(id: "s4", materialID: id, version: 2, text: "Later."),          // another version
            ], pages: 2))
        let node = UUID()
        let exact = try #require(Citation.make(nodeID: node, ids: ["s1", "s9", "s1"], in: material))
        #expect(exact.status == .exact && exact.segmentIDs == ["s1"] && exact.excerpt == "One.")
        for ids in [["s2"], ["s3"], ["s4"], ["s99"]] {
            let unverified = try #require(Citation.make(nodeID: node, ids: ids, in: material))
            #expect(unverified.status == .unverified && unverified.segmentIDs.isEmpty && unverified.excerpt.isEmpty)
        }
        #expect(Citation.make(nodeID: node, ids: [], in: material) == nil)
        #expect(Citation.make(nodeID: node, ids: nil, in: material) == nil)
        // One citation per idea: citing again replaces it.
        material.cite([node: ["s1"]])
        material.cite([node: ["s99"]])
        #expect(material.citations(of: node).count == 1 && material.citations(of: node)[0].status == .unverified)
    }

    @Test func anotherFileIsANewVersionAndTheSameFileChangesNothing() async throws {
        let sentence = "Episodes are talks with practitioners of 20 to 30 minutes."
        let first = pdf(sentence: sentence)
        let read = try Attachments.readDocument(at: first, maxPages: 300)
        // A material from before originals were kept: its text only.
        var material = ProjectMaterial(kind: .document, title: "Brief.pdf", text: read.text, pages: read.pages)

        let (attached, result) = try await SourceImport.attach(first, to: material, isPaid: true)
        #expect(result == .sameContent && attached.version == 1 && attached.originalStatus == .available)
        material = attached
        let passage = try #require(material.segments?.first { $0.text == sentence })
        let node = UUID()
        material.cite([node: [passage.id]])

        // The same content again keeps the passages, so the citation stays exact.
        let (same, sameResult) = try await SourceImport.attach(pdf(sentence: sentence), to: material, isPaid: true)
        #expect(sameResult == .sameContent && same.version == 1 && same.segments == material.segments)

        // A different file: a new version with its own passages; the old citation needs a check.
        let (changed, changedResult) = try await SourceImport.attach(pdf(sentence: "Episodes are long interviews of two hours.", other: "Changed"), to: material, isPaid: true)
        #expect(changedResult == .newVersion && changed.version == 2)
        #expect(changed.segments?.allSatisfy { $0.version == 2 } == true)
        let old = try #require(changed.citations(of: node).first)
        #expect(old.version != changed.version)          // shown as "needs a check"
        #expect(old.excerpt == sentence)                 // its quote is kept as it was
        #expect(changed.text?.contains("two hours") == true)
    }

    @Test func aLostOriginalComesBackFromTheSameFile() async throws {
        let url = pdf()
        let read = try Attachments.readDocument(at: url, maxPages: 300)
        var material = ProjectMaterial(kind: .document, title: "Brief.pdf", draft: SourceImport.document(at: url, text: read.text, pages: read.pages))
        material.original?.state = .removed
        #expect(material.originalStatus == .removed)
        let (restored, result) = try await SourceImport.attach(url, to: material, isPaid: true)
        #expect(result == .sameContent && restored.originalStatus == .available && restored.version == material.version)
    }

    @Test func pagesAndVideosKeepWhatTheServerRead() throws {
        let json = #"{"segments":[{"id":"s1","text":"  Intro   words ","start":12.5,"end":30},{"id":"x2","text":"bad id"},{"id":"s2","text":"No time"},{"id":"s1","text":"duplicate"}],"extractedAt":"2026-10-11T09:00:00.000Z"}"#
        let fetched = try JSONDecoder().decode(MapService.FetchedSource.self, from: Data(json.utf8))
        var video = ProjectMaterial(kind: .youtube, title: "Talk", url: "https://www.youtube.com/watch?v=abcdefghijk")
        video.adopt(fetched)
        #expect(video.segments?.map(\.id) == ["s1", "s2"])
        #expect(video.segments?.first?.text == "Intro words" && video.segments?.first?.start == 12.5 && video.segments?.first?.end == 30)
        #expect(video.segments?.last?.start == nil)
        #expect(video.extractedAt != nil && video.text == "Intro words\n\nNo time")
        #expect(VideoLink.url(video.url!, at: 134.9)?.absoluteString == "https://www.youtube.com/watch?v=abcdefghijk&t=134s")
        #expect(VideoLink.url(video.url!, at: nil)?.absoluteString == video.url)
    }

    @Test func recordingsAndScansKeepTheirPlaces() {
        let id = UUID()
        let words: [VoiceRecorder.Word] = [
            .init(text: "Let’s", start: 1.0, duration: 0.3, confidence: 0.9),
            .init(text: "start.", start: 1.4, duration: 0.4, confidence: 0.8),
            .init(text: "Students", start: 4.0, duration: 0.5, confidence: 0.4),
            .init(text: "first", start: 4.6, duration: 0.3, confidence: 0.9),
        ]
        let spoken = SourceSegmenter.speech(words, materialID: id, version: 1)
        #expect(spoken.map(\.text) == ["Let’s start.", "Students first"])
        #expect(spoken[0].start == 1.0 && abs((spoken[0].end ?? 0) - 1.8) < 0.001 && spoken[1].start == 4.0)
        #expect(spoken[1].isUncertain && !spoken[0].isUncertain)

        let lines: [[TextRecognizer.Line]] = [[
            .init(text: "Lecture 3", box: CGRect(x: 0.1, y: 0.05, width: 0.3, height: 0.04), confidence: 0.95),
            .init(text: "Cells divide by mitosis.", box: CGRect(x: 0.1, y: 0.3, width: 0.7, height: 0.04), confidence: 0.9),
        ]]
        let scan = SourceSegmenter.scan(lines, materialID: id, version: 1)
        #expect(scan.text == "Lecture 3\nCells divide by mitosis.")
        #expect(scan.segments.count == 2 && scan.segments.allSatisfy { $0.page == 0 })
        #expect(scan.segments[1].rects == [[0.1, 0.3, 0.7, 0.04]])
        #expect(scan.segments[1].confidence == 0.9)
    }

    @Test func aReplyNamesPassagesOfTheIdeasItMade() throws {
        let json = #"{"title":"Root","children":[{"title":"A","src":["s2"],"children":[{"title":"A1","src":["s5","s6"]}]},{"title":"B"}]}"#
        let reply = try JSONDecoder().decode(APINode.self, from: Data(json.utf8))
        let root = reply.toNode(aiAdded: false)
        let sources = reply.sources(matching: root)
        #expect(sources[root.children[0].id] == ["s2"])
        #expect(sources[root.children[0].children[0].id] == ["s5", "s6"])
        #expect(sources[root.children[1].id] == nil && sources.count == 2)
        // What the app sends never carries ids.
        let sent = String(decoding: try JSONEncoder().encode(APINode(root)), as: UTF8.self)
        #expect(!sent.contains("src"))
    }

    @Test func aCopiedMapsCitationsFollowItsNewIdeas() {
        let store = ProjectMaterialStore.shared
        let source = UUID(), target = UUID()
        let node = UUID(), renamed = UUID()
        let id = UUID()
        var material = ProjectMaterial(kind: .document, title: "Doc", draft: SourceDraft(materialID: id, text: "One.", segments: [SourceSegment(id: "s1", materialID: id, version: 1, text: "One.")]))
        material.cite([node: ["s1"]])
        store.add(material, to: source)
        store.copy(from: source, to: target, renamed: [node: renamed])
        #expect(store.citations(of: renamed, in: target).count == 1)
        #expect(store.citations(of: node, in: target).isEmpty)
        #expect(store.citations(of: node, in: source).count == 1)
        store.delete(source)
        store.delete(target)
        store.flush()
    }
}
