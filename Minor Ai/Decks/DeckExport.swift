//
//  DeckExport.swift
//  Minor Ai
//
//  A presentation as a PDF (vector, one page per slide) or a PowerPoint file (.pptx) built on
//  the phone: editable text boxes and shapes, pictures, tables, speaker notes, backgrounds,
//  transitions and things that come in one by one, for PowerPoint, Keynote and Google Slides.
//

import SwiftUI
import UIKit

enum DeckExport {
    enum ExportError: Error { case cannotCreate }

    private static func fileURL(_ deck: Deck, ext: String) -> URL {
        let name = deck.title.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Export", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("\(name.isEmpty ? "Presentation" : String(name.prefix(60))).\(ext)")
    }

    // MARK: - PDF

    @MainActor
    static func pdf(_ deck: Deck) throws -> URL {
        let url = fileURL(deck, ext: "pdf")
        var box = CGRect(origin: .zero, size: SlideView.size)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { throw ExportError.cannotCreate }
        for (i, slide) in deck.slides.enumerated() {
            let view = SlideView(slide: slide, style: deck.style(for: slide), index: i, total: deck.slides.count, deckTitle: deck.title,
                                 sectionNumber: SlideCanvas.sectionNumber(of: i, in: deck), brand: deck.brand)
            let renderer = ImageRenderer(content: view)
            renderer.proposedSize = ProposedViewSize(SlideView.size)
            renderer.render { _, draw in
                context.beginPDFPage(nil)
                draw(context)
                context.endPDFPage()
            }
        }
        context.closePDF()
        return url
    }

    // MARK: - PowerPoint

    @MainActor
    static func pptx(_ deck: Deck) throws -> URL {
        let url = fileURL(deck, ext: "pptx")
        var zip = ZipWriter()
        let builder = PPTXBuilder(deck: deck)
        for (name, data) in builder.parts() { zip.add(name, data) }
        try zip.finish().write(to: url, options: .atomic)
        return url
    }
}

// MARK: - PPTX parts

private struct PPTXBuilder {
    let deck: Deck

    static let ns = #"xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main""#
    static let head = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#

    @MainActor
    func parts() -> [(String, Data)] {
        var parts: [(String, String)] = []
        var media: [(String, Data)] = []
        let count = deck.slides.count

        var types = """
        \(Self.head)<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="jpeg" ContentType="image/jpeg"/><Default Extension="png" ContentType="image/png"/><Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/><Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/><Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/><Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/><Override PartName="/ppt/theme/theme2.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/><Override PartName="/ppt/notesMasters/notesMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.notesMaster+xml"/><Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/><Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
        """
        for i in 1...max(count, 1) where count > 0 {
            types += #"<Override PartName="/ppt/slides/slide\#(i).xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/><Override PartName="/ppt/notesSlides/notesSlide\#(i).xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.notesSlide+xml"/>"#
        }
        types += "</Types>"
        parts.append(("[Content_Types].xml", types))

        parts.append(("_rels/.rels", "\(Self.head)<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"ppt/presentation.xml\"/><Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties\" Target=\"docProps/core.xml\"/><Relationship Id=\"rId3\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties\" Target=\"docProps/app.xml\"/></Relationships>"))

        let now = ISO8601DateFormatter().string(from: Date())
        parts.append(("docProps/core.xml", "\(Self.head)<cp:coreProperties xmlns:cp=\"http://schemas.openxmlformats.org/package/2006/metadata/core-properties\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:dcterms=\"http://purl.org/dc/terms/\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"><dc:title>\(XML.escape(deck.title))</dc:title><dc:creator>Minor AI</dc:creator><dcterms:created xsi:type=\"dcterms:W3CDTF\">\(now)</dcterms:created><dcterms:modified xsi:type=\"dcterms:W3CDTF\">\(now)</dcterms:modified></cp:coreProperties>"))
        parts.append(("docProps/app.xml", "\(Self.head)<Properties xmlns=\"http://schemas.openxmlformats.org/officeDocument/2006/extended-properties\"><Application>Minor AI</Application><Slides>\(count)</Slides></Properties>"))

        // Presentation: slides, master, notes master, 16:9 size.
        var slideIDs = ""
        var presRels = "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster\" Target=\"slideMasters/slideMaster1.xml\"/>"
        for i in 1...max(count, 1) where count > 0 {
            slideIDs += "<p:sldId id=\"\(255 + i)\" r:id=\"rId\(i + 10)\"/>"
            presRels += "<Relationship Id=\"rId\(i + 10)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide\" Target=\"slides/slide\(i).xml\"/>"
        }
        presRels += "<Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme\" Target=\"theme/theme1.xml\"/><Relationship Id=\"rId3\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesMaster\" Target=\"notesMasters/notesMaster1.xml\"/>"
        parts.append(("ppt/presentation.xml", "\(Self.head)<p:presentation \(Self.ns) saveSubsetFonts=\"1\"><p:sldMasterIdLst><p:sldMasterId id=\"2147483648\" r:id=\"rId1\"/></p:sldMasterIdLst><p:notesMasterIdLst><p:notesMasterId r:id=\"rId3\"/></p:notesMasterIdLst><p:sldIdLst>\(slideIDs)</p:sldIdLst><p:sldSz cx=\"12192000\" cy=\"6858000\"/><p:notesSz cx=\"6858000\" cy=\"9144000\"/></p:presentation>"))
        parts.append(("ppt/_rels/presentation.xml.rels", XML.rels(presRels)))

        let emptyTree = "<p:spTree><p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/></p:spTree>"
        parts.append(("ppt/slideMasters/slideMaster1.xml", "\(Self.head)<p:sldMaster \(Self.ns)><p:cSld><p:bg><p:bgRef idx=\"1001\"><a:schemeClr val=\"bg1\"/></p:bgRef></p:bg>\(emptyTree)</p:cSld><p:clrMap bg1=\"lt1\" tx1=\"dk1\" bg2=\"lt2\" tx2=\"dk2\" accent1=\"accent1\" accent2=\"accent2\" accent3=\"accent3\" accent4=\"accent4\" accent5=\"accent5\" accent6=\"accent6\" hlink=\"hlink\" folHlink=\"folHlink\"/><p:sldLayoutIdLst><p:sldLayoutId id=\"2147483649\" r:id=\"rId1\"/></p:sldLayoutIdLst><p:txStyles><p:titleStyle><a:lvl1pPr><a:defRPr sz=\"4400\"/></a:lvl1pPr></p:titleStyle><p:bodyStyle><a:lvl1pPr><a:defRPr sz=\"2400\"/></a:lvl1pPr></p:bodyStyle><p:otherStyle><a:lvl1pPr><a:defRPr sz=\"1800\"/></a:lvl1pPr></p:otherStyle></p:txStyles></p:sldMaster>"))
        parts.append(("ppt/slideMasters/_rels/slideMaster1.xml.rels", XML.rels("<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout\" Target=\"../slideLayouts/slideLayout1.xml\"/><Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme\" Target=\"../theme/theme1.xml\"/>")))
        parts.append(("ppt/slideLayouts/slideLayout1.xml", "\(Self.head)<p:sldLayout \(Self.ns) type=\"blank\" preserve=\"1\"><p:cSld name=\"Blank\">\(emptyTree)</p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>"))
        parts.append(("ppt/slideLayouts/_rels/slideLayout1.xml.rels", XML.rels("<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster\" Target=\"../slideMasters/slideMaster1.xml\"/>")))
        parts.append(("ppt/theme/theme1.xml", themeXML(name: "Minor")))
        parts.append(("ppt/theme/theme2.xml", themeXML(name: "Minor Notes")))
        parts.append(("ppt/notesMasters/notesMaster1.xml", "\(Self.head)<p:notesMaster \(Self.ns)><p:cSld>\(emptyTree)</p:cSld><p:clrMap bg1=\"lt1\" tx1=\"dk1\" bg2=\"lt2\" tx2=\"dk2\" accent1=\"accent1\" accent2=\"accent2\" accent3=\"accent3\" accent4=\"accent4\" accent5=\"accent5\" accent6=\"accent6\" hlink=\"hlink\" folHlink=\"folHlink\"/></p:notesMaster>"))
        parts.append(("ppt/notesMasters/_rels/notesMaster1.xml.rels", XML.rels("<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme\" Target=\"../theme/theme2.xml\"/>")))

        for (i, slide) in deck.slides.enumerated() {
            let n = i + 1
            let writer = SlideWriter(deck: deck, slide: slide, index: i)
            parts.append(("ppt/slides/slide\(n).xml", writer.xml()))
            parts.append(("ppt/slides/_rels/slide\(n).xml.rels", XML.rels("<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout\" Target=\"../slideLayouts/slideLayout1.xml\"/><Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesSlide\" Target=\"../notesSlides/notesSlide\(n).xml\"/>" + writer.rels)))
            media += writer.media
            parts.append(("ppt/notesSlides/notesSlide\(n).xml", notesXML(slide.notes)))
            parts.append(("ppt/notesSlides/_rels/notesSlide\(n).xml.rels", XML.rels("<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesMaster\" Target=\"../notesMasters/notesMaster1.xml\"/><Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide\" Target=\"../slides/slide\(n).xml\"/>")))
        }
        return parts.map { ($0.0, Data($0.1.utf8)) } + media
    }

    private func notesXML(_ notes: String) -> String {
        let paragraphs = notes.isEmpty ? "<a:p><a:endParaRPr lang=\"en-US\"/></a:p>" : notes.components(separatedBy: "\n").map { "<a:p><a:r><a:rPr lang=\"en-US\" dirty=\"0\"/><a:t>\(XML.escape($0))</a:t></a:r></a:p>" }.joined()
        return "\(Self.head)<p:notes \(Self.ns)><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/><p:sp><p:nvSpPr><p:cNvPr id=\"2\" name=\"Slide Image\"/><p:cNvSpPr><a:spLocks noGrp=\"1\" noRot=\"1\" noChangeAspect=\"1\"/></p:cNvSpPr><p:nvPr><p:ph type=\"sldImg\"/></p:nvPr></p:nvSpPr><p:spPr><a:xfrm><a:off x=\"381000\" y=\"685800\"/><a:ext cx=\"6096000\" cy=\"3429000\"/></a:xfrm></p:spPr></p:sp><p:sp><p:nvSpPr><p:cNvPr id=\"3\" name=\"Notes\"/><p:cNvSpPr><a:spLocks noGrp=\"1\"/></p:cNvSpPr><p:nvPr><p:ph type=\"body\" idx=\"1\"/></p:nvPr></p:nvSpPr><p:spPr><a:xfrm><a:off x=\"685800\" y=\"4343400\"/><a:ext cx=\"5486400\" cy=\"4114800\"/></a:xfrm></p:spPr><p:txBody><a:bodyPr/><a:lstStyle/>\(paragraphs)</p:txBody></p:sp></p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:notes>"
    }

    private func themeXML(name: String) -> String {
        let style = deck.style
        let accent = XML.hex(style.accent, over: style.background.first)
        let colors = (0..<6).map { XML.hex(style.palette[$0 % max(style.palette.count, 1)], over: style.background.first) }
        let major = XML.escape(style.titleFont.officeName), minor = XML.escape(style.bodyFont.officeName)
        return "\(Self.head)<a:theme xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" name=\"\(name)\"><a:themeElements><a:clrScheme name=\"Minor\"><a:dk1><a:srgbClr val=\"\(style.isLight ? "18171B" : "000000")\"/></a:dk1><a:lt1><a:srgbClr val=\"FFFFFF\"/></a:lt1><a:dk2><a:srgbClr val=\"\(XML.hex(style.background.first, over: .black))\"/></a:dk2><a:lt2><a:srgbClr val=\"EEECE9\"/></a:lt2><a:accent1><a:srgbClr val=\"\(accent)\"/></a:accent1><a:accent2><a:srgbClr val=\"\(colors[1])\"/></a:accent2><a:accent3><a:srgbClr val=\"\(colors[2])\"/></a:accent3><a:accent4><a:srgbClr val=\"\(colors[3])\"/></a:accent4><a:accent5><a:srgbClr val=\"\(colors[4])\"/></a:accent5><a:accent6><a:srgbClr val=\"\(colors[5])\"/></a:accent6><a:hlink><a:srgbClr val=\"\(accent)\"/></a:hlink><a:folHlink><a:srgbClr val=\"\(colors[2])\"/></a:folHlink></a:clrScheme><a:fontScheme name=\"Minor\"><a:majorFont><a:latin typeface=\"\(major)\"/><a:ea typeface=\"\"/><a:cs typeface=\"\"/></a:majorFont><a:minorFont><a:latin typeface=\"\(minor)\"/><a:ea typeface=\"\"/><a:cs typeface=\"\"/></a:minorFont></a:fontScheme><a:fmtScheme name=\"Minor\"><a:fillStyleLst><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill></a:fillStyleLst><a:lnStyleLst><a:ln w=\"9525\"><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill></a:ln><a:ln w=\"25400\"><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill></a:ln><a:ln w=\"38100\"><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill></a:ln></a:lnStyleLst><a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst><a:bgFillStyleLst><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill></a:bgFillStyleLst></a:fmtScheme></a:themeElements><a:objectDefaults/><a:extraClrSchemeLst/></a:theme>"
    }
}

// Small XML helpers shared by the parts.
enum XML {
    // Also drops control characters XML 1.0 doesn't allow (a vertical tab or form feed pasted from a
    // PDF would otherwise make PowerPoint and Keynote refuse the file).
    static func escape(_ text: String) -> String {
        let allowed = String(String.UnicodeScalarView(text.unicodeScalars.compactMap { scalar -> Unicode.Scalar? in
            switch scalar.value {
            case 0x09, 0x0A, 0x0D: return scalar
            case 0x0B, 0x0C: return " "
            case 0x00...0x1F, 0xFFFE, 0xFFFF: return nil
            default: return scalar
            }
        }))
        return allowed.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func rels(_ body: String) -> String {
        "\(PPTXBuilder.head)<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\(body)</Relationships>"
    }

    // Colors with transparency are blended over the slide background.
    static func hex(_ color: Color, over background: Color) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        if a < 1 {
            var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
            UIColor(background).getRed(&br, green: &bg, blue: &bb, alpha: &ba)
            r = r * a + br * (1 - a); g = g * a + bg * (1 - a); b = b * a + bb * (1 - a)
        }
        return String(format: "%02X%02X%02X", Int(max(0, min(1, r)) * 255), Int(max(0, min(1, g)) * 255), Int(max(0, min(1, b)) * 255))
    }
}

// One slide: its shapes, pictures, background, transition and what comes in on each tap.
@MainActor
private final class SlideWriter {
    let deck: Deck
    let slide: Slide
    let index: Int
    let style: SlideStyle

    private(set) var rels = ""
    private(set) var media: [(String, Data)] = []
    private var shapes = ""
    private var nextID = 2
    private var nextRel = 3
    private var textShapes: Set<Int> = []           // shapes with text, for the build list
    private var steps: [(targets: [Target], effect: BuildEffect)] = []
    private var paragraphBuilds: Set<Int> = []

    enum Target { case shape(Int), paragraph(Int, Int) }

    private let emu: Double = 9525                  // per design unit (1280 units = 13.333 in)
    private let pad: CGFloat = 80
    private let width: CGFloat = 1280

    init(deck: Deck, slide: Slide, index: Int) {
        self.deck = deck
        self.slide = slide
        self.index = index
        self.style = deck.style(for: slide)
    }

    // MARK: Units and colors

    private func e(_ v: CGFloat) -> Int { Int((Double(v) * emu).rounded()) }
    private func pt(_ size: CGFloat) -> Int { Int((size * 0.75 * 100).rounded()) }   // hundredths of a point
    private func hex(_ color: Color) -> String { XML.hex(color, over: style.background.first) }
    private var textHex: String { hex(style.text) }
    private var secondaryHex: String { hex(style.secondary) }
    private var accentHex: String { hex(style.accent) }
    private func paletteHex(_ i: Int) -> String { hex(style.palette[i % max(style.palette.count, 1)]) }

    private func newID() -> Int { defer { nextID += 1 }; return nextID }

    private func addMedia(_ data: Data, ext: String) -> String {
        let rel = "rId\(nextRel)"
        nextRel += 1
        let name = "s\(index + 1)_\(rel).\(ext)"
        media.append(("ppt/media/\(name)", data))
        rels += "<Relationship Id=\"\(rel)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"../media/\(name)\"/>"
        return rel
    }

    private func xfrm(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, rotation: Double = 0) -> String {
        let rot = rotation == 0 ? "" : " rot=\"\(Int((rotation.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) * 60000))\""
        return "<a:xfrm\(rot)><a:off x=\"\(e(x))\" y=\"\(e(y))\"/><a:ext cx=\"\(e(max(w, 1)))\" cy=\"\(e(max(h, 1)))\"/></a:xfrm>"
    }

    // MARK: Text

    private func run(_ text: String, size: CGFloat, color: String, bold: Bool = false, italic: Bool = false, font: DeckFont? = nil, alpha: Double = 1) -> String {
        let typeface = XML.escape((font ?? style.bodyFont).officeName)
        let alphaXML = alpha < 1 ? "<a:alpha val=\"\(Int(alpha * 100000))\"/>" : ""
        return "<a:r><a:rPr lang=\"en-US\" sz=\"\(pt(size))\" b=\"\(bold ? 1 : 0)\" i=\"\(italic ? 1 : 0)\" dirty=\"0\"><a:solidFill><a:srgbClr val=\"\(color)\">\(alphaXML)</a:srgbClr></a:solidFill><a:latin typeface=\"\(typeface)\"/><a:cs typeface=\"\(typeface)\"/></a:rPr><a:t>\(XML.escape(text))</a:t></a:r>"
    }

    private func titleRun(_ text: String, size: CGFloat, color: String? = nil) -> String {
        run(text, size: size, color: color ?? textHex, bold: true, font: style.titleFont)
    }

    private func paragraph(_ runs: String, align: String = "l", bullet: String? = nil, spaceAfter: Int = 0) -> String {
        let bulletXML = bullet.map { "<a:buClr><a:srgbClr val=\"\($0)\"/></a:buClr><a:buFont typeface=\"Arial\"/><a:buChar char=\"•\"/>" } ?? "<a:buNone/>"
        let margin = bullet == nil ? "" : " marL=\"\(e(34))\" indent=\"-\(e(34))\""
        return "<a:p><a:pPr algn=\"\(align)\"\(margin)><a:spcAft><a:spcPts val=\"\(spaceAfter * 100)\"/></a:spcAft>\(bulletXML)</a:pPr>\(runs)</a:p>"
    }

    @discardableResult
    private func textBox(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, paragraphs: [String], anchor: String = "t", fill: String? = nil, fillAlpha: Double = 1,
                         geometry: String = "rect", line: String? = nil, lineWidth: CGFloat = 2, rotation: Double = 0) -> Int {
        let id = newID()
        let alphaXML = fillAlpha < 1 ? "<a:alpha val=\"\(Int(fillAlpha * 100000))\"/>" : ""
        let fillXML = fill.map { "<a:solidFill><a:srgbClr val=\"\($0)\">\(alphaXML)</a:srgbClr></a:solidFill>" } ?? "<a:noFill/>"
        let lineXML = line.map { "<a:ln w=\"\(e(lineWidth))\"><a:solidFill><a:srgbClr val=\"\($0)\"/></a:solidFill></a:ln>" } ?? "<a:ln><a:noFill/></a:ln>"
        let inset = fill == nil && line == nil ? 0 : e(18)
        // A shape with its own geometry is a shape that holds text, not a plain text box.
        let kind = fill == nil && line == nil ? "<p:cNvSpPr txBox=\"1\"/>" : "<p:cNvSpPr/>"
        shapes += "<p:sp><p:nvSpPr><p:cNvPr id=\"\(id)\" name=\"Text \(id)\"/>\(kind)<p:nvPr/></p:nvSpPr><p:spPr>\(xfrm(x, y, w, h, rotation: rotation))<a:prstGeom prst=\"\(geometry)\"><a:avLst/></a:prstGeom>\(fillXML)\(lineXML)</p:spPr><p:txBody><a:bodyPr wrap=\"square\" lIns=\"\(inset)\" tIns=\"\(inset)\" rIns=\"\(inset)\" bIns=\"\(inset)\" anchor=\"\(anchor)\"><a:normAutofit/></a:bodyPr><a:lstStyle/>\(paragraphs.isEmpty ? "<a:p><a:endParaRPr lang=\"en-US\"/></a:p>" : paragraphs.joined())</p:txBody></p:sp>"
        textShapes.insert(id)
        return id
    }

    @discardableResult
    private func rect(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, fill: String, geometry: String = "rect", alpha: Double = 1, rotation: Double = 0) -> Int {
        let id = newID()
        let alphaXML = alpha < 1 ? "<a:alpha val=\"\(Int(alpha * 100000))\"/>" : ""
        shapes += "<p:sp><p:nvSpPr><p:cNvPr id=\"\(id)\" name=\"Shape \(id)\"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr>\(xfrm(x, y, w, h, rotation: rotation))<a:prstGeom prst=\"\(geometry)\"><a:avLst/></a:prstGeom><a:solidFill><a:srgbClr val=\"\(fill)\">\(alphaXML)</a:srgbClr></a:solidFill><a:ln><a:noFill/></a:ln></p:spPr></p:sp>"
        return id
    }

    @discardableResult
    private func line(from: CGPoint, to: CGPoint, color: String, width: CGFloat = 3, dotted: Bool = true) -> Int {
        let id = newID()
        let flipH = to.x < from.x ? " flipH=\"1\"" : ""
        let flipV = to.y < from.y ? " flipV=\"1\"" : ""
        shapes += "<p:cxnSp><p:nvCxnSpPr><p:cNvPr id=\"\(id)\" name=\"Line \(id)\"/><p:cNvCxnSpPr/><p:nvPr/></p:nvCxnSpPr><p:spPr><a:xfrm\(flipH)\(flipV)><a:off x=\"\(e(min(from.x, to.x)))\" y=\"\(e(min(from.y, to.y)))\"/><a:ext cx=\"\(e(abs(to.x - from.x)))\" cy=\"\(e(abs(to.y - from.y)))\"/></a:xfrm><a:prstGeom prst=\"line\"><a:avLst/></a:prstGeom><a:ln w=\"\(e(width))\" cap=\"rnd\"><a:solidFill><a:srgbClr val=\"\(color)\"/></a:solidFill>\(dotted ? "<a:prstDash val=\"sysDot\"/>" : "")</a:ln></p:spPr></p:cxnSp>"
        return id
    }

    @discardableResult
    private func picture(rel: String, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, rounded: Bool = true, rotation: Double = 0, alpha: Double = 1) -> Int {
        let id = newID()
        let geometry = rounded ? "<a:prstGeom prst=\"roundRect\"><a:avLst><a:gd name=\"adj\" fmla=\"val 7000\"/></a:avLst></a:prstGeom>" : "<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom>"
        let alphaXML = alpha < 1 ? "<a:alphaModFix amt=\"\(Int(alpha * 100000))\"/>" : ""
        shapes += "<p:pic><p:nvPicPr><p:cNvPr id=\"\(id)\" name=\"Picture \(id)\"/><p:cNvPicPr><a:picLocks noChangeAspect=\"1\"/></p:cNvPicPr><p:nvPr/></p:nvPicPr><p:blipFill><a:blip r:embed=\"\(rel)\">\(alphaXML)</a:blip><a:srcRect/><a:stretch><a:fillRect/></a:stretch></p:blipFill><p:spPr>\(xfrm(x, y, w, h, rotation: rotation))\(geometry)</p:spPr></p:pic>"
        return id
    }

    @discardableResult
    private func table(rows: [[String]], x: CGFloat, y: CGFloat, w: CGFloat, rowHeight: CGFloat? = nil, size: CGFloat? = nil) -> Int {
        let id = newID()
        let columns = max(rows.map(\.count).max() ?? 1, 1)
        let colWidth = e(w / CGFloat(columns))
        let height = e(rowHeight ?? (rows.count > 5 ? 64 : 76))
        var xml = "<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id=\"\(id)\" name=\"Table \(id)\"/><p:cNvGraphicFramePr><a:graphicFrameLocks noGrp=\"1\"/></p:cNvGraphicFramePr><p:nvPr/></p:nvGraphicFramePr><p:xfrm><a:off x=\"\(e(x))\" y=\"\(e(y))\"/><a:ext cx=\"\(e(w))\" cy=\"\(height * rows.count)\"/></p:xfrm><a:graphic><a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/table\"><a:tbl><a:tblPr firstRow=\"1\"/><a:tblGrid>"
        xml += String(repeating: "<a:gridCol w=\"\(colWidth)\"/>", count: columns) + "</a:tblGrid>"
        let header = hex(style.accent.opacity(style.isLight ? 0.14 : 0.2))
        let stripe = hex(style.card)
        for (r, row) in rows.enumerated() {
            xml += "<a:tr h=\"\(height)\">"
            for c in 0..<columns {
                let text = c < row.count ? row[c] : ""
                let fill = r == 0 ? header : (r % 2 == 0 ? stripe : hex(style.background.first))
                xml += "<a:tc><a:txBody><a:bodyPr/><a:lstStyle/>\(paragraph(run(text, size: size ?? (rows.count > 5 ? 24 : 28), color: textHex, bold: r == 0 || c == 0)))</a:txBody><a:tcPr marL=\"\(e(22))\" marR=\"\(e(22))\" anchor=\"ctr\"><a:solidFill><a:srgbClr val=\"\(fill)\"/></a:solidFill></a:tcPr></a:tc>"
            }
            xml += "</a:tr>"
        }
        shapes += xml + "</a:tbl></a:graphicData></a:graphic></p:graphicFrame>"
        return id
    }

    // Something drawn by the app (icon, chart, QR code) as a sharp picture.
    private func rendered<V: View>(_ view: V, size: CGSize) -> String? {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 2
        guard let data = renderer.uiImage?.pngData() else { return nil }
        return addMedia(data, ext: "png")
    }

    // MARK: Building up

    private func step(_ targets: [Target]) {
        guard slide.buildBullets != .none, !targets.isEmpty else { return }
        steps.append((targets, slide.buildBullets))
    }

    // MARK: The slide

    func xml() -> String {
        let background = backgroundXML()
        layout()
        footerAndBrand()
        elements()
        return "\(PPTXBuilder.head)<p:sld \(PPTXBuilder.ns)><p:cSld>\(background)<p:spTree><p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>\(shapes)</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>\(transitionXML())\(timingXML())</p:sld>"
    }

    private func backgroundXML() -> String {
        let bg = style.background
        let fill: String
        switch bg.kind {
        case .solid:
            fill = "<a:solidFill><a:srgbClr val=\"\(hex(bg.first))\"/></a:solidFill>"
        case .gradient:
            fill = gradient(bg)
        case .image:
            if let id = bg.image, let data = MapStore.shared.imageData(id) {
                let rel = addMedia(data, ext: "jpeg")
                fill = "<a:blipFill dpi=\"0\" rotWithShape=\"1\"><a:blip r:embed=\"\(rel)\"/><a:srcRect/><a:stretch><a:fillRect/></a:stretch></a:blipFill>"
                if bg.dim > 0 { rect(x: 0, y: 0, w: 1280, h: 720, fill: "000000", alpha: bg.dim) }
            } else {
                fill = gradient(bg)
            }
        }
        return "<p:bg><p:bgPr>\(fill)<a:effectLst/></p:bgPr></p:bg>"
    }

    private func gradient(_ bg: SlideBackground) -> String {
        "<a:gradFill rotWithShape=\"1\"><a:gsLst><a:gs pos=\"0\"><a:srgbClr val=\"\(hex(bg.first))\"/></a:gs><a:gs pos=\"100000\"><a:srgbClr val=\"\(hex(bg.last))\"/></a:gs></a:gsLst><a:lin ang=\"\(Int(((bg.angle.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360) * 60000))\" scaled=\"0\"/></a:gradFill>"
    }

    private func layout() {
        // The box id isn't needed for titles (they don't build in), so the result is dropped here.
        let title = { (size: CGFloat, y: CGFloat, h: CGFloat) in
            _ = self.textBox(x: self.pad, y: y, w: self.width - self.pad * 2, h: h, paragraphs: [self.paragraph(self.titleRun(self.slide.title, size: size))])
        }
        let bulletParagraphs = { (items: [String], size: CGFloat) -> [String] in
            items.enumerated().map { i, item in self.paragraph(self.run(item, size: size, color: self.textHex), bullet: self.paletteHex(i), spaceAfter: Int(size * 0.5)) }
        }

        switch slide.layout {
        case .cover:
            rect(x: pad + 10, y: 230, w: 96, h: 10, fill: accentHex, geometry: "roundRect")
            textBox(x: pad + 10, y: 262, w: 1040, h: 220, paragraphs: [paragraph(titleRun(slide.title, size: 92))], anchor: "b")
            if !slide.subtitle.isEmpty {
                textBox(x: pad + 10, y: 500, w: 1040, h: 120, paragraphs: [paragraph(run(slide.subtitle, size: 34, color: secondaryHex))])
            }
        case .section:
            let number = String(format: "%02d", SlideCanvas.sectionNumber(of: index, in: deck))
            textBox(x: pad + 10, y: 220, w: 300, h: 260, paragraphs: [paragraph(titleRun(number, size: 200, color: accentHex))], anchor: "ctr")
            textBox(x: 420, y: 250, w: 780, h: 160, paragraphs: [paragraph(titleRun(slide.title, size: 72))], anchor: "b")
            if !slide.subtitle.isEmpty {
                textBox(x: 420, y: 420, w: 780, h: 100, paragraphs: [paragraph(run(slide.subtitle, size: 30, color: secondaryHex))])
            }
        case .bullets:
            title(56, 76, 140)
            let size: CGFloat = slide.bullets.count > 4 ? 32 : 40
            let box = textBox(x: pad, y: 240, w: width - pad * 2, h: 380, paragraphs: bulletParagraphs(slide.bullets, size))
            for i in slide.bullets.indices { step([.paragraph(box, i)]) }
        case .twoColumns:
            title(52, 70, 120)
            let columns = Array(slide.columns.prefix(3))
            let gap: CGFloat = 28
            let w = (width - pad * 2 - gap * CGFloat(max(columns.count - 1, 0))) / CGFloat(max(columns.count, 1))
            for (i, column) in columns.enumerated() {
                let x = pad + CGFloat(i) * (w + gap)
                let card = rect(x: x, y: 210, w: w, h: 410, fill: hex(style.card), geometry: "roundRect")
                let bar = rect(x: x + 32, y: 242, w: 56, h: 8, fill: paletteHex(i), geometry: "roundRect")
                let text = textBox(x: x + 32, y: 266, w: w - 64, h: 330, paragraphs: [paragraph(titleRun(column.title, size: 38), spaceAfter: 12)] + bulletParagraphs(column.bullets, 28))
                step([.shape(card), .shape(bar), .shape(text)])
            }
        case .imageText:
            if let image = slide.image, let data = MapStore.shared.imageData(image.id) {
                picture(rel: addMedia(data, ext: "jpeg"), x: pad, y: 80, w: 520, h: 560)
            } else {
                rect(x: pad, y: 80, w: 520, h: 560, fill: hex(style.accent.opacity(0.3)), geometry: "roundRect")
            }
            let box = textBox(x: 660, y: 120, w: 540, h: 480, paragraphs: [paragraph(titleRun(slide.title, size: 52), spaceAfter: 18)] + bulletParagraphs(slide.bullets, 28), anchor: "ctr")
            for i in slide.bullets.indices { step([.paragraph(box, i + 1)]) }
        case .bigNumber:
            if !slide.title.isEmpty {
                textBox(x: pad, y: 130, w: width - pad * 2, h: 70, paragraphs: [paragraph(run(slide.title, size: 34, color: secondaryHex, bold: true), align: "ctr")])
            }
            textBox(x: pad, y: 200, w: width - pad * 2, h: 260, paragraphs: [paragraph(titleRun(slide.stat?.value ?? "", size: 230, color: accentHex), align: "ctr")], anchor: "ctr")
            textBox(x: 190, y: 470, w: 900, h: 130, paragraphs: [paragraph(run(slide.stat?.label ?? "", size: 36, color: textHex), align: "ctr")])
        case .quote:
            textBox(x: pad + 20, y: 90, w: 300, h: 200, paragraphs: [paragraph(titleRun("“", size: 260, color: accentHex))])
            textBox(x: pad + 20, y: 260, w: 1060, h: 280, paragraphs: [paragraph(run(slide.quote?.text ?? slide.title, size: 54, color: textHex, bold: true, italic: true))])
            if let author = slide.quote?.author, !author.isEmpty {
                textBox(x: pad + 20, y: 560, w: 1000, h: 60, paragraphs: [paragraph(run("— \(author)", size: 30, color: secondaryHex))])
            }
        case .timeline:
            title(52, 76, 120)
            let items = Array(slide.items.prefix(6))
            rect(x: pad, y: 330, w: width - pad * 2, h: 6, fill: accentHex)
            let gap: CGFloat = 24
            let w = (width - pad * 2 - gap * CGFloat(max(items.count - 1, 0))) / CGFloat(max(items.count, 1))
            for (i, item) in items.enumerated() {
                let x = pad + CGFloat(i) * (w + gap)
                let dot = rect(x: x, y: 315, w: 36, h: 36, fill: paletteHex(i), geometry: "ellipse")
                var paragraphs = [paragraph(titleRun(item.title, size: items.count > 4 ? 28 : 34), spaceAfter: 8)]
                if !item.detail.isEmpty { paragraphs.append(paragraph(run(item.detail, size: items.count > 4 ? 22 : 26, color: secondaryHex))) }
                let text = textBox(x: x, y: 370, w: w, h: 250, paragraphs: paragraphs)
                step([.shape(dot), .shape(text)])
            }
        case .table:
            title(52, 70, 120)
            table(rows: Array(slide.table.prefix(6)), x: pad, y: 210, w: width - pad * 2)
        case .diagram:
            title(48, 60, 100)
            let nodes = Array((slide.diagram?.nodes ?? []).prefix(6))
            let center = CGPoint(x: 640, y: 420)
            let positions: [CGPoint] = nodes.indices.map { i in
                let angle = -Double.pi / 2 + Double(i) * 2 * Double.pi / Double(max(nodes.count, 1))
                return CGPoint(x: center.x + CGFloat(cos(angle)) * 420, y: center.y + CGFloat(sin(angle)) * 210)
            }
            let lines = positions.map { line(from: center, to: $0, color: hex(style.line)) }
            textBox(x: center.x - 115, y: center.y - 115, w: 230, h: 230, paragraphs: [paragraph(run(slide.diagram?.center ?? slide.title, size: 30, color: hex(style.onAccent), bold: true, font: style.titleFont), align: "ctr")], anchor: "ctr", fill: accentHex, geometry: "ellipse")
            for (i, node) in nodes.enumerated() {
                let p = positions[i]
                let box = textBox(x: p.x - 150, y: p.y - 36, w: 300, h: 72, paragraphs: [paragraph(run(node, size: 25, color: textHex, bold: true), align: "ctr")], anchor: "ctr", fill: style.isLight ? "FFFFFF" : "1D1A20", geometry: "roundRect", line: paletteHex(i))
                step([.shape(lines[i]), .shape(box)])
            }
        case .closing:
            textBox(x: 120, y: 200, w: 1040, h: 200, paragraphs: [paragraph(titleRun(slide.title, size: 84), align: "ctr")], anchor: "b")
            rect(x: 570, y: 420, w: 140, h: 10, fill: accentHex, geometry: "roundRect")
            if !slide.subtitle.isEmpty {
                textBox(x: 120, y: 450, w: 1040, h: 120, paragraphs: [paragraph(run(slide.subtitle, size: 34, color: secondaryHex), align: "ctr")])
            }
        }
    }

    private func footerAndBrand() {
        let brand = deck.brand
        if slide.layout != .cover && slide.layout != .closing && deck.slides.count > 1 {
            let footer = brand.map { $0.footer.isEmpty ? deck.title : $0.footer } ?? deck.title
            textBox(x: pad, y: 656, w: 600, h: 30, paragraphs: [paragraph(run(footer, size: 18, color: secondaryHex))])
            if brand?.showNumbers != false {
                textBox(x: 900, y: 656, w: 300, h: 30, paragraphs: [paragraph(run("\(index + 1) / \(deck.slides.count)", size: 18, color: secondaryHex), align: "r")])
            }
        }
        guard let brand, let logo = brand.logo, slide.layout != .cover || brand.onCover,
              let image = MapStore.shared.image(logo), let data = image.pngData() else { return }
        let height = CGFloat(brand.size)
        let width = min(height * image.size.width / max(image.size.height, 1), 360)
        let left = brand.corner == .topLeft || brand.corner == .bottomLeft
        let top = brand.corner == .topLeft || brand.corner == .topRight
        let x = left ? 48 : 1280 - 48 - width
        let y = top ? 40 : 720 - 70 - height
        picture(rel: addMedia(data, ext: "png"), x: x, y: y, w: width, h: height, rounded: false)
    }

    // MARK: Free elements

    private func elements() {
        for element in slide.elements {
            guard let ids = write(element) else { continue }
            if element.build != .none { steps.append((ids.map { .shape($0) }, element.build)) }
        }
    }

    private func write(_ el: SlideElement) -> [Int]? {
        let x = CGFloat(el.x), y = CGFloat(el.y), w = CGFloat(el.w), h = CGFloat(el.h)
        let align = el.align == .center ? "ctr" : el.align == .trailing ? "r" : "l"
        let font = el.titleFont ? style.titleFont : style.bodyFont
        switch el.kind {
        case .text:
            let color = el.color.map { hex(Color(hex: $0)) } ?? textHex
            let paragraphs = el.text.components(separatedBy: "\n").map {
                paragraph(run($0, size: CGFloat(el.fontSize), color: color, bold: el.bold, italic: el.italic, font: font, alpha: el.opacity), align: align)
            }
            return [textBox(x: x, y: y, w: w, h: h, paragraphs: paragraphs, anchor: "ctr", rotation: el.rotation)]
        case .shape:
            let fill = hex(el.fill.map { Color(hex: $0) } ?? style.accent)
            if el.shape == .line {
                let id = line(from: CGPoint(x: x, y: y + h / 2), to: CGPoint(x: x + w, y: y + h / 2), color: el.stroke.map { hex(Color(hex: $0)) } ?? fill, width: CGFloat(max(el.strokeWidth, 6)), dotted: false)
                return [id]
            }
            let geometry: String
            switch el.shape {
            case .rect: geometry = "rect"
            case .roundRect: geometry = "roundRect"
            case .ellipse: geometry = "ellipse"
            case .triangle: geometry = "triangle"
            case .diamond: geometry = "diamond"
            case .arrow: geometry = "rightArrow"
            case .star: geometry = "star5"
            case .hexagon: geometry = "hexagon"
            case .line: geometry = "line"
            }
            let textColor = el.color.map { hex(Color(hex: $0)) } ?? (el.fill == nil ? hex(style.onAccent) : textHex)
            let paragraphs = el.text.isEmpty ? [] : el.text.components(separatedBy: "\n").map {
                paragraph(run($0, size: CGFloat(el.fontSize), color: textColor, bold: el.bold, italic: el.italic, font: font), align: align)
            }
            return [textBox(x: x, y: y, w: w, h: h, paragraphs: paragraphs, anchor: "ctr", fill: fill, fillAlpha: el.fillOpacity * el.opacity, geometry: geometry,
                            line: el.strokeWidth > 0 ? (el.stroke.map { hex(Color(hex: $0)) } ?? textHex) : nil, lineWidth: CGFloat(el.strokeWidth), rotation: el.rotation)]
        case .icon:
            let color = el.fill.map { Color(hex: $0) } ?? style.accent
            let view = Image(systemName: el.symbol).resizable().scaledToFit().foregroundColor(color.opacity(el.fillOpacity))
            guard let rel = rendered(view, size: CGSize(width: w, height: h)) else { return nil }
            return [picture(rel: rel, x: x, y: y, w: w, h: h, rounded: false, rotation: el.rotation, alpha: el.opacity)]
        case .image:
            guard let id = el.image, let data = MapStore.shared.imageData(id) else { return nil }
            return [picture(rel: addMedia(data, ext: "jpeg"), x: x, y: y, w: w, h: h, rotation: el.rotation, alpha: el.opacity)]
        case .table:
            guard !el.rows.isEmpty else { return nil }
            return [table(rows: el.rows, x: x, y: y, w: w, rowHeight: h / CGFloat(el.rows.count), size: min(CGFloat(el.fontSize), 30))]
        case .chart:
            let view = ChartView(spec: el.chart ?? ChartSpec(), style: style)
            guard let rel = rendered(view, size: CGSize(width: w, height: h)) else { return nil }
            return [picture(rel: rel, x: x, y: y, w: w, h: h, rounded: false, rotation: el.rotation, alpha: el.opacity)]
        case .qr:
            guard let image = QRImage.image(el.link, scale: 16), let data = image.pngData() else { return nil }
            let inset = w * 0.06
            let card = rect(x: x, y: y, w: w, h: h, fill: "FFFFFF", geometry: "roundRect", rotation: el.rotation)
            let code = picture(rel: addMedia(data, ext: "png"), x: x + inset, y: y + inset, w: w - inset * 2, h: h - inset * 2, rounded: false, rotation: el.rotation)
            return [card, code]
        }
    }

    // MARK: Motion

    private func transitionXML() -> String {
        switch slide.transition ?? deck.transition {
        case .none: return ""
        case .fade: return "<p:transition spd=\"med\"><p:fade/></p:transition>"
        case .push: return "<p:transition spd=\"med\"><p:push dir=\"l\"/></p:transition>"
        case .zoom: return "<p:transition spd=\"med\"><p:zoom/></p:transition>"
        case .wipe: return "<p:transition spd=\"med\"><p:wipe dir=\"l\"/></p:transition>"
        }
    }

    // Each tap brings in the next step: entrance effects in PowerPoint's own timing format.
    private func timingXML() -> String {
        guard !steps.isEmpty else { return "" }
        var id = 3
        func next() -> Int { defer { id += 1 }; return id }
        func target(_ t: Target) -> String {
            switch t {
            case .shape(let spid): return "<p:spTgt spid=\"\(spid)\"/>"
            case .paragraph(let spid, let p): return "<p:spTgt spid=\"\(spid)\"><p:txEl><p:pRg st=\"\(p)\" end=\"\(p)\"/></p:txEl></p:spTgt>"
            }
        }
        func anim(_ attr: String, from: String, to: String, tgt: String, dur: Int) -> String {
            "<p:anim calcmode=\"lin\" valueType=\"num\"><p:cBhvr additive=\"base\"><p:cTn id=\"\(next())\" dur=\"\(dur)\" fill=\"hold\"/><p:tgtEl>\(tgt)</p:tgtEl><p:attrNameLst><p:attrName>\(attr)</p:attrName></p:attrNameLst></p:cBhvr><p:tavLst><p:tav tm=\"0\"><p:val><p:strVal val=\"\(from)\"/></p:val></p:tav><p:tav tm=\"100000\"><p:val><p:strVal val=\"\(to)\"/></p:val></p:tav></p:tavLst></p:anim>"
        }
        func fade(_ tgt: String, dur: Int) -> String {
            "<p:animEffect transition=\"in\" filter=\"fade\"><p:cBhvr><p:cTn id=\"\(next())\" dur=\"\(dur)\"/><p:tgtEl>\(tgt)</p:tgtEl></p:cBhvr></p:animEffect>"
        }
        func effect(_ t: Target, _ kind: BuildEffect, first: Bool) -> String {
            let tgt = target(t)
            let preset: (Int, Int)
            switch kind {
            case .fly: preset = (2, 4)
            case .rise: preset = (42, 0)
            case .zoom: preset = (53, 16)
            default: preset = (10, 0)
            }
            let container = next()
            var body = "<p:set><p:cBhvr><p:cTn id=\"\(next())\" dur=\"1\" fill=\"hold\"><p:stCondLst><p:cond delay=\"0\"/></p:stCondLst></p:cTn><p:tgtEl>\(tgt)</p:tgtEl><p:attrNameLst><p:attrName>style.visibility</p:attrName></p:attrNameLst></p:cBhvr><p:to><p:strVal val=\"visible\"/></p:to></p:set>"
            switch kind {
            case .fly:
                body += anim("ppt_x", from: "#ppt_x", to: "#ppt_x", tgt: tgt, dur: 500) + anim("ppt_y", from: "1+#ppt_h/2", to: "#ppt_y", tgt: tgt, dur: 500)
            case .rise:
                body += fade(tgt, dur: 700) + anim("ppt_y", from: "#ppt_y+0.1", to: "#ppt_y", tgt: tgt, dur: 700)
            case .zoom:
                body += anim("ppt_w", from: "0", to: "#ppt_w", tgt: tgt, dur: 500) + anim("ppt_h", from: "0", to: "#ppt_h", tgt: tgt, dur: 500) + fade(tgt, dur: 500)
            default:
                body += fade(tgt, dur: 500)
            }
            return "<p:par><p:cTn id=\"\(container)\" presetID=\"\(preset.0)\" presetClass=\"entr\" presetSubtype=\"\(preset.1)\" fill=\"hold\" grpId=\"0\" nodeType=\"\(first ? "clickEffect" : "withEffect")\"><p:stCondLst><p:cond delay=\"0\"/></p:stCondLst><p:childTnLst>\(body)</p:childTnLst></p:cTn></p:par>"
        }

        var clicks = ""
        var built: [Int: Bool] = [:]       // shape id → built by paragraph
        for step in steps {
            let outer = next(), inner = next()
            let effects = step.targets.enumerated().map { i, t -> String in
                switch t {
                case .shape(let spid): if built[spid] == nil { built[spid] = false }
                case .paragraph(let spid, _): built[spid] = true
                }
                return effect(t, step.effect, first: i == 0)
            }.joined()
            clicks += "<p:par><p:cTn id=\"\(outer)\" fill=\"hold\"><p:stCondLst><p:cond delay=\"indefinite\"/></p:stCondLst><p:childTnLst><p:par><p:cTn id=\"\(inner)\" fill=\"hold\"><p:stCondLst><p:cond delay=\"0\"/></p:stCondLst><p:childTnLst>\(effects)</p:childTnLst></p:cTn></p:par></p:childTnLst></p:cTn></p:par>"
        }
        let builds = built.keys.sorted().compactMap { spid -> String? in
            guard textShapes.contains(spid) else { return nil }
            return built[spid] == true ? "<p:bldP spid=\"\(spid)\" grpId=\"0\" build=\"p\"/>" : "<p:bldP spid=\"\(spid)\" grpId=\"0\" animBg=\"1\"/>"
        }.joined()
        let buildList = builds.isEmpty ? "" : "<p:bldLst>\(builds)</p:bldLst>"
        return "<p:timing><p:tnLst><p:par><p:cTn id=\"1\" dur=\"indefinite\" restart=\"never\" nodeType=\"tmRoot\"><p:childTnLst><p:seq concurrent=\"1\" nextAc=\"seek\"><p:cTn id=\"2\" dur=\"indefinite\" nodeType=\"mainSeq\"><p:childTnLst>\(clicks)</p:childTnLst></p:cTn><p:prevCondLst><p:cond evt=\"onPrev\" delay=\"0\"><p:tgtEl><p:sldTgt/></p:tgtEl></p:cond></p:prevCondLst><p:nextCondLst><p:cond evt=\"onNext\" delay=\"0\"><p:tgtEl><p:sldTgt/></p:tgtEl></p:cond></p:nextCondLst></p:seq></p:childTnLst></p:cTn></p:par></p:tnLst>\(buildList)</p:timing>"
    }
}

// MARK: - ZIP (stored, no compression: what .pptx readers expect at minimum)

struct ZipWriter {
    private var output = Data()
    private var central = Data()
    private var count: UInt16 = 0

    private static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data { crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }

    private static func le16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
    private static func le32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }

    mutating func add(_ name: String, _ data: Data) {
        let nameData = Data(name.utf8)
        let crc = Self.crc32(data)
        let size = UInt32(data.count)
        let offset = UInt32(output.count)
        // Local file header.
        output += Self.le32(0x0403_4B50) + Self.le16(20) + Self.le16(0x0800) + Self.le16(0) + Self.le16(0) + Self.le16(0x21)
        output += Self.le32(crc) + Self.le32(size) + Self.le32(size) + Self.le16(UInt16(nameData.count)) + Self.le16(0)
        output += nameData + data
        // Central directory entry.
        central += Self.le32(0x0201_4B50) + Self.le16(20) + Self.le16(20) + Self.le16(0x0800) + Self.le16(0) + Self.le16(0) + Self.le16(0x21)
        central += Self.le32(crc) + Self.le32(size) + Self.le32(size) + Self.le16(UInt16(nameData.count)) + Self.le16(0) + Self.le16(0)
        central += Self.le16(0) + Self.le16(0) + Self.le32(0) + Self.le32(offset) + nameData
        count += 1
    }

    func finish() -> Data {
        var data = output
        let start = UInt32(data.count)
        data += central
        data += Self.le32(0x0605_4B50) + Self.le16(0) + Self.le16(0) + Self.le16(count) + Self.le16(count)
        data += Self.le32(UInt32(central.count)) + Self.le32(start) + Self.le16(0)
        return data
    }
}
