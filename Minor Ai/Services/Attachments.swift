//
//  Attachments.swift
//  Minor Ai
//
//  Photos and documents attached to chat messages or used as map sources.
//

import PDFKit
import SwiftUI
import UIKit

enum Attachments {
    // Shrinks a photo to at most 1280 px on the long side and re-encodes it as JPEG.
    static func preparedImage(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longSide = max(image.size.width, image.size.height)
        let scale = min(1, 1280 / max(longSide, 1))
        let size = CGSize(width: floor(image.size.width * scale), height: floor(image.size.height * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.7)
    }

    struct Document {
        let name: String
        let text: String
        let pages: Int
    }

    enum DocumentError: Error {
        case unreadable
        case noText
        case tooLong(pages: Int)
        case tooBig
    }

    // Text files larger than this are refused before reading (the server reads far less anyway).
    static let maxFileBytes = 20_000_000

    // The same as readDocument, off the main thread: a 300-page PDF takes a moment.
    static func loadDocument(at url: URL, maxPages: Int) async throws -> Document {
        try await Task.detached(priority: .userInitiated) {
            try readDocument(at: url, maxPages: maxPages)
        }.value
    }

    // What to tell the person when a document can't be attached.
    static func message(for error: Error, isPaid: Bool) -> String {
        switch error as? DocumentError {
        case .tooLong(let pages)?:
            return isPaid
                ? L("This file has \(pages) pages. Minor reads up to 300.")
                : L("This file has \(pages) pages. The free plan reads up to 10; Minor Plus reads up to 300.")
        case .noText?:
            return L("This file has no text Minor can read (it may be a scan or an image).")
        case .tooBig?:
            return L("This file is too large. Try a shorter one.")
        default:
            return L("Couldn’t read this file. Use a PDF, TXT or RTF file.")
        }
    }

    // Plain text of a PDF, TXT or RTF file picked with the system importer.
    static func readDocument(at url: URL, maxPages: Int) throws -> Document {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let name = url.lastPathComponent
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if size > maxFileBytes && url.pathExtension.lowercased() != "pdf" { throw DocumentError.tooBig }
        var text = ""
        var pages = 1
        switch url.pathExtension.lowercased() {
        case "pdf":
            guard let pdf = PDFDocument(url: url) else { throw DocumentError.unreadable }
            pages = pdf.pageCount
            if pages > maxPages { throw DocumentError.tooLong(pages: pages) }
            text = (0..<pages).compactMap { pdf.page(at: $0)?.string }.joined(separator: "\n")
        case "rtf":
            guard let attributed = try? NSAttributedString(url: url, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
            else { throw DocumentError.unreadable }
            text = attributed.string
        default:
            guard let data = try? Data(contentsOf: url) else { throw DocumentError.unreadable }
            text = String(decoding: data, as: UTF8.self)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 40 else { throw DocumentError.noText }
        return Document(name: name, text: trimmed, pages: pages)
    }
}

// Markdown for chat answers: headings, bullet and numbered lists, and inline styles.
struct MarkdownText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let line):
                    inline(line).font(.system(size: 17, weight: .semibold))
                case .bullet(let line, let marker):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(marker)
                        inline(line)
                    }
                case .code(let code):
                    Text(code)
                        .font(.system(size: 14, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.3)))
                case .paragraph(let line):
                    inline(line)
                }
            }
        }
        .textSelection(.enabled)
    }

    private enum Block {
        case heading(String)
        case bullet(String, marker: String)
        case code(String)
        case paragraph(String)
    }

    private var blocks: [Block] {
        var result: [Block] = []
        var code: [String]?
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if let open = code {
                    result.append(.code(open.joined(separator: "\n")))
                    code = nil
                } else {
                    code = []
                }
                continue
            }
            if code != nil {
                code?.append(raw)
                continue
            }
            if line.isEmpty { continue }
            if let range = line.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                result.append(.heading(String(line[range.upperBound...])))
            } else if let range = line.range(of: #"^[-*•]\s+"#, options: .regularExpression) {
                result.append(.bullet(String(line[range.upperBound...]), marker: "•"))
            } else if let range = line.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) {
                result.append(.bullet(String(line[range.upperBound...]), marker: line[..<range.upperBound].trimmingCharacters(in: .whitespaces)))
            } else {
                result.append(.paragraph(line))
            }
        }
        if let open = code { result.append(.code(open.joined(separator: "\n"))) }
        return result
    }

    private func inline(_ line: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return Text((try? AttributedString(markdown: line, options: options)) ?? AttributedString(line))
    }
}
