//
//  SourceImport.swift
//  Minor Ai
//
//  Turning what the person picked into a material's original and passages:
//  - a PDF, TXT or RTF file: copied into the private folder, PDFs cut into passages per page with
//    where they are on it;
//  - scanned pages: put together as one PDF (the original), passages from the recognized lines
//    with their boxes;
//  - a voice note: the recording, passages from the recognized words with their times;
//  - another file for an existing material: the same content keeps the material's version; a
//    different one starts a new version, and earlier citations are shown as needing a check.
//  When the original can't be kept, the text still is, and the person is told so plainly.
//

import PDFKit
import UIKit

enum SourceImport {
    // A picked document already read as text (Attachments.readDocument): its original and passages.
    // Call off the main thread.
    static func document(at url: URL, text: String, pages: Int, version: Int = 1, materialID: UUID = UUID()) -> SourceDraft {
        var draft = SourceDraft(materialID: materialID, version: version, text: text, segments: [], pages: pages)
        do {
            draft.original = try OriginalStore.keep(fileAt: url, name: url.lastPathComponent)
        } catch {
            draft.originalError = (error as? LocalizedError)?.errorDescription ?? OriginalStore.ImportError.writeFailed.errorDescription
        }
        if url.pathExtension.lowercased() == "pdf", let pdf = PDFDocument(url: draft.original.flatMap(OriginalStore.url(for:)) ?? url), !pdf.isLocked {
            draft.segments = SourceSegmenter.pdf(pdf, materialID: materialID, version: version).segments
        }
        if draft.segments.isEmpty {
            draft.segments = SourceSegmenter.text(String(text.prefix(ProjectMaterial.textLimit)), materialID: materialID, version: version)
        }
        return draft
    }

    // Scanned pages: the recognized text, one PDF of the pages as the original, and passages with
    // the boxes of their lines. Nil when no text was found.
    static func scan(_ images: [UIImage], name: String) async -> SourceDraft? {
        let lines = await TextRecognizer.lines(from: images)
        let materialID = UUID()
        let cut = SourceSegmenter.scan(lines, materialID: materialID, version: 1)
        guard cut.text.trimmingCharacters(in: .whitespacesAndNewlines).count > 20 else { return nil }
        var draft = SourceDraft(materialID: materialID, text: cut.text, segments: cut.segments, pages: images.count)
        do {
            let data = await Task.detached(priority: .userInitiated) { pdf(of: images) }.value
            draft.original = try await Task.detached(priority: .userInitiated) { try OriginalStore.keep(data: data, ext: "pdf", name: name + ".pdf") }.value
        } catch {
            draft.originalError = (error as? LocalizedError)?.errorDescription ?? OriginalStore.ImportError.writeFailed.errorDescription
        }
        return draft
    }

    // One page per picture, each the picture's shape, JPEG inside.
    static func pdf(of images: [UIImage]) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        return renderer.pdfData { context in
            for image in images {
                autoreleasepool {
                    let size = image.size
                    guard size.width > 0, size.height > 0 else { return }
                    let width: CGFloat = 612
                    let bounds = CGRect(x: 0, y: 0, width: width, height: (width * size.height / size.width).rounded())
                    context.beginPage(withBounds: bounds, pageInfo: [:])
                    let jpeg = image.jpegData(compressionQuality: 0.75).flatMap(UIImage.init(data:)) ?? image
                    jpeg.draw(in: bounds)
                }
            }
        }
    }

    // A voice note: the recording kept as the original and the words as timed passages; without a
    // recording or word times, the transcript is kept as text with no player.
    @MainActor
    static func voice(_ text: String, recording: VoiceRecorder.Recording?) -> SourceDraft {
        let materialID = UUID()
        var draft = SourceDraft(materialID: materialID, text: text, segments: [])
        if let recording {
            do {
                draft.original = try OriginalStore.adopt(recording.file, name: L("Voice note") + ".m4a", mime: "audio/mp4")
                draft.duration = recording.duration
                let timed = SourceSegmenter.speech(recording.words, materialID: materialID, version: 1)
                if !timed.isEmpty {
                    draft.segments = timed
                    draft.text = timed.map(\.text).joined(separator: " ")
                }
            } catch {
                draft.originalError = (error as? LocalizedError)?.errorDescription
            }
        }
        if draft.segments.isEmpty { draft.segments = SourceSegmenter.text(text, materialID: materialID, version: 1) }
        return draft
    }

    // MARK: - Attaching an original to an existing material

    enum AttachResult: Equatable {
        case sameContent      // the original of what was read: citations stay as they are
        case newVersion       // a different file: a new version; earlier citations need a check
    }

    // Reads `url` as the material's original (off the main thread) and returns the changed material.
    // The same content (by its hash, or the same text) keeps the version; anything else starts the
    // next one with its own passages. Citations are never moved to the new passages.
    static func attach(_ url: URL, to material: ProjectMaterial, isPaid: Bool) async throws -> (ProjectMaterial, AttachResult) {
        let read = try await Attachments.loadDocument(at: url, maxPages: isPaid ? 300 : 10)
        return try await Task.detached(priority: .userInitiated) {
            if let sha = OriginalStore.sha256(of: url), material.original?.sha256 == sha, material.originalStatus != .available {
                // The same file again (after it was lost or removed): it simply comes back.
                var restored = material
                restored.original = try OriginalStore.keep(fileAt: url, name: url.lastPathComponent)
                return (restored, .sameContent)
            }
            let same = sameText(material.text ?? "", read.text)
            let version = same ? material.version : material.version + 1
            let draft = document(at: url, text: read.text, pages: read.pages, version: version, materialID: material.id)
            guard let original = draft.original else {
                throw OriginalStore.ImportError.writeFailed
            }
            var updated = material
            updated.original = original
            updated.pages = read.pages
            // Same content that already has passages: they stay, so its citations stay exact.
            if same && material.segments != nil { return (updated, .sameContent) }
            updated.version = version
            updated.segments = draft.segments.isEmpty ? nil : draft.segments
            updated.text = String(read.text.prefix(ProjectMaterial.textLimit))
            return (updated, same ? .sameContent : .newVersion)
        }.value
    }

    // The saved text and the file's text say the same (saved text may be the file's beginning).
    static func sameText(_ saved: String, _ read: String) -> Bool {
        func flat(_ text: String) -> String { text.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        let a = flat(saved), b = flat(read)
        guard !a.isEmpty, !b.isEmpty else { return false }
        return a == b || b.hasPrefix(a) || a.hasPrefix(b) && b.count > 200
    }
}
