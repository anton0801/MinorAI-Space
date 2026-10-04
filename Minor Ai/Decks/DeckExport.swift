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
// Text and shapes go where the app's own slide puts them (measured from SlideView), with sizes
// fitted in the font PowerPoint uses, so the file looks like the slide in the app and the PDF.
@MainActor
private final class SlideWriter {
    let deck: Deck
    let slide: Slide
    let index: Int
    let style: SlideStyle
    private let probe: SlideLayoutProbe

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
        let style = deck.style(for: slide)
        self.style = style
        probe = Self.measure(deck: deck, slide: slide, index: index, style: style)
    }

    // Lays the slide out off screen and reads where each part landed.
    private static func measure(deck: Deck, slide: Slide, index: Int, style: SlideStyle) -> SlideLayoutProbe {
        let probe = SlideLayoutProbe()
        let view = SlideView(slide: slide, style: style, index: index, total: deck.slides.count, deckTitle: deck.title,
                             sectionNumber: SlideCanvas.sectionNumber(of: index, in: deck), brand: deck.brand, showElements: false, probe: probe)
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(SlideView.size)
        renderer.render { _, draw in
            if let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                draw(context)
            }
        }
        return probe
    }

    // MARK: Units and colors

    private func e(_ v: CGFloat) -> Int { Int((Double(v) * emu).rounded()) }
    private func pt(_ size: CGFloat) -> Int { Int((size * 0.75 * 100).rounded()) }   // hundredths of a point
    private func hex(_ color: Color) -> String { XML.hex(color, over: style.background.first) }
    private var textHex: String { hex(style.text) }
    private var secondaryHex: String { hex(style.secondary) }
    private var accentHex: String { hex(style.accent) }
    private func paletteHex(_ i: Int) -> String { hex(style.palette[i % max(style.palette.count, 1)]) }
    private var palette: [String] { (0..<max(style.palette.count, 1)).map(paletteHex) }

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

    // A preset outline; a rounded rectangle gets the corner radius the slide draws.
    private func geometryXML(_ geometry: String, radius: CGFloat?, w: CGFloat, h: CGFloat) -> String {
        guard geometry == "roundRect", let radius else { return "<a:prstGeom prst=\"\(geometry)\"><a:avLst/></a:prstGeom>" }
        let adj = Int(min(50000, max(0, radius / max(min(w, h), 1) * 100000)))
        return "<a:prstGeom prst=\"roundRect\"><a:avLst><a:gd name=\"adj\" fmla=\"val \(adj)\"/></a:avLst></a:prstGeom>"
    }

    private func fillXML(_ fill: String?, alpha: Double = 1, gradient: [String]? = nil, angle: Double = 0) -> String {
        if let gradient, gradient.count > 1 {
            let stops = gradient.enumerated().map { i, color in "<a:gs pos=\"\(i * 100000 / (gradient.count - 1))\"><a:srgbClr val=\"\(color)\"/></a:gs>" }.joined()
            return "<a:gradFill rotWithShape=\"1\"><a:gsLst>\(stops)</a:gsLst><a:lin ang=\"\(Int(angle * 60000))\" scaled=\"0\"/></a:gradFill>"
        }
        guard let fill else { return "<a:noFill/>" }
        let alphaXML = alpha < 1 ? "<a:alpha val=\"\(Int(alpha * 100000))\"/>" : ""
        return "<a:solidFill><a:srgbClr val=\"\(fill)\">\(alphaXML)</a:srgbClr></a:solidFill>"
    }

    // MARK: Text

    private func run(_ text: String, size: CGFloat, color: String, bold: Bool = false, italic: Bool = false, font: DeckFont? = nil, alpha: Double = 1,
                     tracking: CGFloat = 0, gradient: [String]? = nil, gradientAngle: Double = 90) -> String {
        let typeface = XML.escape((font ?? style.bodyFont).officeName)
        let alphaXML = alpha < 1 ? "<a:alpha val=\"\(Int(alpha * 100000))\"/>" : ""
        // Letter spacing in hundredths of a point, as the slide's tracking.
        let spacing = tracking == 0 ? "" : " spc=\"\(Int((tracking * 75).rounded()))\""
        let fill = gradient != nil ? fillXML(nil, gradient: gradient, angle: gradientAngle) : "<a:solidFill><a:srgbClr val=\"\(color)\">\(alphaXML)</a:srgbClr></a:solidFill>"
        return "<a:r><a:rPr lang=\"en-US\" sz=\"\(pt(size))\" b=\"\(bold ? 1 : 0)\" i=\"\(italic ? 1 : 0)\"\(spacing) dirty=\"0\">\(fill)<a:latin typeface=\"\(typeface)\"/><a:cs typeface=\"\(typeface)\"/></a:rPr><a:t>\(XML.escape(text))</a:t></a:r>"
    }

    // Lines broken where they break in this font and width, joined with line breaks: viewers
    // that wrap text in shapes their own way (iOS Quick Look ignores the padding) show the same lines.
    private func brokenRuns(_ text: String, width: CGFloat, size: CGFloat, color: String, bold: Bool = false, italic: Bool = false, font: DeckFont? = nil) -> (runs: String, width: CGFloat) {
        let font = font ?? style.bodyFont
        let storage = NSTextStorage(string: text, attributes: [.font: officeFont(font, size, bold: bold, italic: italic)])
        let manager = NSLayoutManager()
        storage.addLayoutManager(manager)
        let container = NSTextContainer(size: CGSize(width: max(width, 1), height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        var lines: [String] = []
        var widest: CGFloat = 0
        manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: container)) { _, used, _, glyphs, _ in
            let range = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            lines.append((text as NSString).substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines))
            widest = max(widest, used.width)
        }
        let runs = (lines.isEmpty ? [text] : lines).map { run($0, size: size, color: color, bold: bold, italic: italic, font: font) }.joined(separator: "<a:br/>")
        return (runs, widest)
    }

    // The height of a line in the font the app draws the slide with.
    private func lineHeight(_ font: DeckFont, _ size: CGFloat, bold: Bool) -> CGFloat {
        switch font {
        case .system, .rounded, .serif, .mono: return UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular).lineHeight
        default: return officeFont(font, size, bold: bold, italic: false).lineHeight
        }
    }

    // `lineHeight` sets lines exactly as far apart as the slide's own font does.
    private func paragraph(_ runs: String, align: String = "l", bullet: String? = nil, indent: CGFloat = 34, spaceBefore: CGFloat = 0, lineHeight: CGFloat? = nil) -> String {
        let bulletXML = bullet.map { "<a:buClr><a:srgbClr val=\"\($0)\"/></a:buClr><a:buSzPct val=\"140000\"/><a:buFont typeface=\"Arial\"/><a:buChar char=\"•\"/>" } ?? "<a:buNone/>"
        let margin = bullet == nil ? "" : " marL=\"\(e(indent))\" indent=\"-\(e(indent))\""
        let spacing = lineHeight.map { "<a:lnSpc><a:spcPts val=\"\(Int(($0 * 75).rounded()))\"/></a:lnSpc>" } ?? ""
        let before = spaceBefore > 0 ? "<a:spcBef><a:spcPts val=\"\(Int((spaceBefore * 75).rounded()))\"/></a:spcBef>" : ""
        return "<a:p><a:pPr algn=\"\(align)\"\(margin)>\(spacing)\(before)\(bulletXML)</a:pPr>\(runs)</a:p>"
    }

    @discardableResult
    private func textBox(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, paragraphs: [String], anchor: String = "t", fill: String? = nil, fillAlpha: Double = 1,
                         gradient: [String]? = nil, gradientAngle: Double = 0, geometry: String = "rect", radius: CGFloat? = nil,
                         line: String? = nil, lineWidth: CGFloat = 2, rotation: Double = 0, inset: CGSize = .zero, wrap: Bool = true) -> Int {
        let id = newID()
        let lineXML = line.map { "<a:ln w=\"\(e(lineWidth))\"><a:solidFill><a:srgbClr val=\"\($0)\"/></a:solidFill></a:ln>" } ?? "<a:ln><a:noFill/></a:ln>"
        let plain = fill == nil && gradient == nil && line == nil
        // A shape with its own outline is a shape that holds text, not a plain text box.
        let kind = plain ? "<p:cNvSpPr txBox=\"1\"/>" : "<p:cNvSpPr/>"
        let body = paragraphs.isEmpty ? "<a:p><a:endParaRPr lang=\"en-US\"/></a:p>" : paragraphs.joined()
        shapes += "<p:sp><p:nvSpPr><p:cNvPr id=\"\(id)\" name=\"Text \(id)\"/>\(kind)<p:nvPr/></p:nvSpPr><p:spPr>\(xfrm(x, y, w, h, rotation: rotation))\(geometryXML(geometry, radius: radius, w: w, h: h))\(fillXML(fill, alpha: fillAlpha, gradient: gradient, angle: gradientAngle))\(lineXML)</p:spPr><p:txBody><a:bodyPr wrap=\"\(wrap ? "square" : "none")\" lIns=\"\(e(inset.width))\" tIns=\"\(e(inset.height))\" rIns=\"\(e(inset.width))\" bIns=\"\(e(inset.height))\" anchor=\"\(anchor)\"><a:normAutofit/></a:bodyPr><a:lstStyle/>\(body)</p:txBody></p:sp>"
        textShapes.insert(id)
        return id
    }

    // The font PowerPoint and Keynote will draw with, to size text the way it will look there.
    private func officeFont(_ font: DeckFont, _ size: CGFloat, bold: Bool, italic: Bool) -> UIFont {
        var traits: UIFontDescriptor.SymbolicTraits = []
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        let family = UIFontDescriptor(fontAttributes: [.family: font.officeName])
        return UIFont(descriptor: family.withSymbolicTraits(traits) ?? family, size: size)
    }

    // The font the app draws the slide with, to know how many lines a text takes there.
    private func appFont(_ font: DeckFont, _ size: CGFloat, bold: Bool) -> UIFont {
        let system = UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
        switch font {
        case .system: return system
        case .rounded, .serif, .mono:
            let design: UIFontDescriptor.SystemDesign = font == .rounded ? .rounded : font == .serif ? .serif : .monospaced
            return system.fontDescriptor.withDesign(design).map { UIFont(descriptor: $0, size: size) } ?? system
        default: return officeFont(font, size, bold: bold, italic: false)
        }
    }

    private func lineCount(_ text: String, _ font: UIFont, width: CGFloat, kern: CGFloat = 0) -> Int {
        let storage = NSTextStorage(string: text, attributes: [.font: font, .kern: kern])
        let manager = NSLayoutManager()
        storage.addLayoutManager(manager)
        let container = NSTextContainer(size: CGSize(width: max(width, 1), height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        var count = 0
        manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: container)) { _, _, _, _, _ in count += 1 }
        return max(count, 1)
    }

    // The largest size up to `size` at which the text fits the box in that font, in no more lines
    // than the app's font takes, the way the slide shrinks text that doesn't fit.
    private func fitted(_ text: String, font: DeckFont, size: CGFloat, bold: Bool, italic: Bool = false, tracking: CGFloat = 0, in box: CGSize) -> CGFloat {
        guard !text.isEmpty, box.width > 4, box.height > 4 else { return size }
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let appLines = lineCount(text, appFont(font, size, bold: bold), width: box.width, kern: tracking)
        var s = size
        while s > size * 0.4 {
            let office = officeFont(font, s, bold: bold, italic: italic)
            let kern = tracking * s / size
            let attributes: [NSAttributedString.Key: Any] = [.font: office, .kern: kern]
            let height = (text as NSString).boundingRect(with: CGSize(width: box.width, height: .greatestFiniteMagnitude),
                                                         options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil).height
            let widest = words.map { ($0 as NSString).size(withAttributes: attributes).width }.max() ?? 0
            if height <= box.height * 1.08 && widest <= box.width && lineCount(text, office, width: box.width, kern: kern) <= appLines { return s }
            s -= max(0.5, size * 0.03)
        }
        return size * 0.4
    }

    // An editable text box where the slide draws this text: the measured frame, widened to `room`
    // for a font that runs a little wider, with the size fitted to it.
    @discardableResult
    private func placedText(_ key: String, _ text: String, size: CGFloat, font: DeckFont? = nil, bold: Bool = false, italic: Bool = false, color: String? = nil,
                            align: String = "l", tracking: CGFloat = 0, room: CGFloat? = nil, fit: Bool = true, gradient: [String]? = nil, gradientAngle: Double = 90, fallback: CGRect) -> Int? {
        guard !text.isEmpty else { return nil }
        let font = font ?? style.bodyFont
        var frame = probe[key] ?? fallback
        if let room, room > frame.width {
            let extra = room - frame.width
            if align == "ctr" { frame.origin.x -= extra / 2 } else if align == "r" { frame.origin.x -= extra }
            frame.size.width = room
        }
        let lines = text.components(separatedBy: "\n")
        let s = fit ? fitted(text, font: font, size: size, bold: bold, italic: italic, tracking: tracking, in: frame.size) : size
        let spacing = lineHeight(font, s, bold: bold)
        let paragraphs = lines.map {
            paragraph(run($0, size: s, color: color ?? textHex, bold: bold, italic: italic, font: font, tracking: tracking * s / size, gradient: gradient, gradientAngle: gradientAngle), align: align, lineHeight: spacing)
        }
        return textBox(x: frame.minX, y: frame.minY, w: frame.width, h: frame.height + 6, paragraphs: paragraphs)
    }

    // A list as one text box with real bullets, lined up with the slide's own list.
    @discardableResult
    private func bulletBox(_ key: String, items: [String], size: CGFloat, dots: [String], right: CGFloat, fallback: CGRect) -> Int? {
        guard !items.isEmpty else { return nil }
        let indent = size * 0.42 + 22               // the dot and the gap before the text
        let frames = items.indices.compactMap { probe["\(key).text.\($0)"] }
        guard frames.count == items.count, let first = frames.first, let last = frames.last else {
            let paragraphs = items.enumerated().map { i, item in
                paragraph(run(item, size: size, color: textHex), bullet: dots[i % dots.count], indent: indent, spaceBefore: i == 0 ? 0 : size * 0.5)
            }
            return textBox(x: fallback.minX, y: fallback.minY, w: fallback.width, h: fallback.height, paragraphs: paragraphs)
        }
        let x = first.minX - indent
        let w = max(right - x, (frames.map(\.maxX).max() ?? right) - x)
        let paragraphs = items.enumerated().map { i, item -> String in
            let s = fitted(item, font: style.bodyFont, size: size, bold: false, in: CGSize(width: w - indent, height: frames[i].height))
            let gap = i == 0 ? 0 : max(0, frames[i].minY - frames[i - 1].maxY)
            return paragraph(run(item, size: s, color: textHex), bullet: dots[i % dots.count], indent: indent, spaceBefore: gap, lineHeight: lineHeight(style.bodyFont, s, bold: false))
        }
        return textBox(x: x, y: first.minY, w: w, h: last.maxY - first.minY + size * 0.4, paragraphs: paragraphs)
    }

    // MARK: Shapes and pictures

    @discardableResult
    private func shape(_ frame: CGRect, geometry: String = "rect", radius: CGFloat? = nil, fill: String? = nil, alpha: Double = 1, gradient: [String]? = nil,
                       angle: Double = 0, line: String? = nil, lineWidth: CGFloat = 0, rotation: Double = 0) -> Int {
        let id = newID()
        let lineXML = line.map { "<a:ln w=\"\(e(lineWidth))\"><a:solidFill><a:srgbClr val=\"\($0)\"/></a:solidFill></a:ln>" } ?? "<a:ln><a:noFill/></a:ln>"
        shapes += "<p:sp><p:nvSpPr><p:cNvPr id=\"\(id)\" name=\"Shape \(id)\"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr>\(xfrm(frame.minX, frame.minY, frame.width, frame.height, rotation: rotation))\(geometryXML(geometry, radius: radius, w: frame.width, h: frame.height))\(fillXML(fill, alpha: alpha, gradient: gradient, angle: angle))\(lineXML)</p:spPr></p:sp>"
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

    // Pictures fill their frame and are cropped, never stretched, as on the slide.
    private func cover(_ image: CGSize, _ box: CGSize) -> String {
        guard image.width > 0, image.height > 0, box.width > 0, box.height > 0 else { return "<a:srcRect/>" }
        let imageAspect = image.width / image.height, boxAspect = box.width / box.height
        if abs(imageAspect - boxAspect) < 0.01 { return "<a:srcRect/>" }
        if imageAspect > boxAspect {
            let side = Int((1 - boxAspect / imageAspect) / 2 * 100000)
            return "<a:srcRect l=\"\(side)\" r=\"\(side)\"/>"
        }
        let side = Int((1 - imageAspect / boxAspect) / 2 * 100000)
        return "<a:srcRect t=\"\(side)\" b=\"\(side)\"/>"
    }

    @discardableResult
    private func picture(rel: String, frame: CGRect, radius: CGFloat = 0, crop: String = "<a:srcRect/>", rotation: Double = 0, alpha: Double = 1) -> Int {
        let id = newID()
        let alphaXML = alpha < 1 ? "<a:alphaModFix amt=\"\(Int(alpha * 100000))\"/>" : ""
        let geometry = geometryXML(radius > 0 ? "roundRect" : "rect", radius: radius, w: frame.width, h: frame.height)
        shapes += "<p:pic><p:nvPicPr><p:cNvPr id=\"\(id)\" name=\"Picture \(id)\"/><p:cNvPicPr><a:picLocks noChangeAspect=\"1\"/></p:cNvPicPr><p:nvPr/></p:nvPicPr><p:blipFill><a:blip r:embed=\"\(rel)\">\(alphaXML)</a:blip>\(crop)<a:stretch><a:fillRect/></a:stretch></p:blipFill><p:spPr>\(xfrm(frame.minX, frame.minY, frame.width, frame.height, rotation: rotation))\(geometry)</p:spPr></p:pic>"
        return id
    }

    // A user's picture from the map store, cropped to the frame.
    @discardableResult
    private func photo(_ id: UUID, frame: CGRect, radius: CGFloat, rotation: Double = 0, alpha: Double = 1) -> Int? {
        guard let data = MapStore.shared.imageData(id) else { return nil }
        let size = MapStore.shared.image(id)?.size ?? frame.size
        return picture(rel: addMedia(data, ext: "jpeg"), frame: frame, radius: radius, crop: cover(size, frame.size), rotation: rotation, alpha: alpha)
    }

    @discardableResult
    private func table(rows: [[String]], frame: CGRect, heights: [CGFloat], size: CGFloat, padding: CGFloat, firstColumnBold: Bool = true) -> Int {
        let id = newID()
        let columns = max(rows.map(\.count).max() ?? 1, 1)
        let colWidth = e(frame.width / CGFloat(columns))
        let total = heights.reduce(0, +)
        var xml = "<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id=\"\(id)\" name=\"Table \(id)\"/><p:cNvGraphicFramePr><a:graphicFrameLocks noGrp=\"1\"/></p:cNvGraphicFramePr><p:nvPr/></p:nvGraphicFramePr><p:xfrm><a:off x=\"\(e(frame.minX))\" y=\"\(e(frame.minY))\"/><a:ext cx=\"\(e(frame.width))\" cy=\"\(e(total))\"/></p:xfrm><a:graphic><a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/table\"><a:tbl><a:tblPr firstRow=\"1\"/><a:tblGrid>"
        xml += String(repeating: "<a:gridCol w=\"\(colWidth)\"/>", count: columns) + "</a:tblGrid>"
        let header = hex(style.accent.opacity(style.isLight ? 0.14 : 0.18))
        let stripe = hex(style.card)
        func edge(_ side: String, _ width: CGFloat) -> String { "<a:\(side) w=\"\(e(width))\"><a:solidFill><a:srgbClr val=\"\(hex(style.line))\"/></a:solidFill></a:\(side)>" }
        for (r, row) in rows.enumerated() {
            let height = e(r < heights.count ? heights[r] : heights.last ?? 76)
            xml += "<a:tr h=\"\(height)\">"
            for c in 0..<columns {
                let text = c < row.count ? row[c] : ""
                let fill = r == 0 ? fillXML(header) : (r % 2 == 0 ? fillXML(stripe) : "<a:noFill/>")
                let bold = r == 0 || (firstColumnBold && c == 0)
                let cell = paragraph(run(text, size: size, color: textHex, bold: bold))
                // A line under each row and around the table, as on the slide.
                let borders = (c == 0 ? edge("lnL", 1.5) : "") + (c == columns - 1 ? edge("lnR", 1.5) : "") + (r == 0 ? edge("lnT", 1.5) : "") + edge("lnB", r == rows.count - 1 ? 1.5 : 1)
                xml += "<a:tc><a:txBody><a:bodyPr/><a:lstStyle/>\(cell)</a:txBody><a:tcPr marL=\"\(e(padding))\" marR=\"\(e(padding))\" marT=\"0\" marB=\"0\" anchor=\"ctr\">\(borders)\(fill)</a:tcPr></a:tc>"
            }
            xml += "</a:tr>"
        }
        shapes += xml + "</a:tbl></a:graphicData></a:graphic></p:graphicFrame>"
        return id
    }

    // Something drawn by the app (icon, chart, picture placeholder) as a sharp picture.
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
        // The fill with the soft light in the corners (or a photo with its shade) as one picture,
        // drawn by the app: PowerPoint has no blur to make that light itself.
        if bg.kind == .image || style.glow {
            let renderer = ImageRenderer(content: SlideBackdrop(slide: slide, style: style))
            renderer.proposedSize = ProposedViewSize(SlideView.size)
            renderer.scale = 1.5
            if let data = renderer.uiImage?.jpegData(compressionQuality: 0.85) {
                let rel = addMedia(data, ext: "jpeg")
                return "<p:bg><p:bgPr><a:blipFill dpi=\"0\" rotWithShape=\"1\"><a:blip r:embed=\"\(rel)\"/><a:srcRect/><a:stretch><a:fillRect/></a:stretch></a:blipFill><a:effectLst/></p:bgPr></p:bg>"
            }
        }
        let fill = bg.kind == .solid ? "<a:solidFill><a:srgbClr val=\"\(hex(bg.first))\"/></a:solidFill>" : gradient(bg)
        return "<p:bg><p:bgPr>\(fill)<a:effectLst/></p:bgPr></p:bg>"
    }

    private func gradient(_ bg: SlideBackground) -> String {
        "<a:gradFill rotWithShape=\"1\"><a:gsLst><a:gs pos=\"0\"><a:srgbClr val=\"\(hex(bg.first))\"/></a:gs><a:gs pos=\"100000\"><a:srgbClr val=\"\(hex(bg.last))\"/></a:gs></a:gsLst><a:lin ang=\"\(Int(((bg.angle.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360) * 60000))\" scaled=\"0\"/></a:gradFill>"
    }

    private func layout() {
        let full = width - pad * 2
        let second = style.palette.count > 1 ? paletteHex(1) : accentHex
        func title(_ size: CGFloat, top: CGFloat, height: CGFloat) {
            placedText("title", slide.title, size: size, font: style.titleFont, bold: true, tracking: -1, room: full, fallback: CGRect(x: pad, y: top, width: full, height: height))
        }

        switch slide.layout {
        case .cover:
            shape(probe["bar"] ?? CGRect(x: pad + 10, y: 230, width: 96, height: 10), geometry: "roundRect", radius: 5, fill: accentHex)
            placedText("title", slide.title, size: 92, font: style.titleFont, bold: true, tracking: -2.5, room: 1000, fallback: CGRect(x: pad + 10, y: 262, width: 1000, height: 220))
            placedText("subtitle", slide.subtitle, size: 34, color: secondaryHex, room: 1000, fallback: CGRect(x: pad + 10, y: 500, width: 1000, height: 120))
        case .section:
            let number = String(format: "%02d", SlideCanvas.sectionNumber(of: index, in: deck))
            placedText("number", number, size: 200, font: style.titleFont, bold: true, color: accentHex, fit: false, gradient: [accentHex, second], fallback: CGRect(x: pad + 10, y: 220, width: 300, height: 260))
            let room = probe["title"].map { width - pad - 10 - $0.minX }
            placedText("title", slide.title, size: 72, font: style.titleFont, bold: true, tracking: -1.5, room: room, fallback: CGRect(x: 420, y: 250, width: 780, height: 160))
            placedText("subtitle", slide.subtitle, size: 30, color: secondaryHex, room: room, fallback: CGRect(x: 420, y: 420, width: 780, height: 100))
        case .bullets:
            title(56, top: 76, height: 140)
            placedText("subtitle", slide.subtitle, size: 26, color: secondaryHex, room: full, fallback: CGRect(x: pad, y: 160, width: full, height: 40))
            if let box = bulletBox("b", items: slide.bullets, size: slide.bullets.count > 4 ? 32 : 40, dots: palette, right: width - pad, fallback: CGRect(x: pad, y: 240, width: full, height: 380)) {
                for i in slide.bullets.indices { step([.paragraph(box, i)]) }
            }
        case .twoColumns:
            title(52, top: 70, height: 120)
            let columns = Array(slide.columns.prefix(3))
            let gap: CGFloat = 28
            let w = (full - gap * CGFloat(max(columns.count - 1, 0))) / CGFloat(max(columns.count, 1))
            for (i, column) in columns.enumerated() {
                let card = probe["col.\(i)"] ?? CGRect(x: pad + CGFloat(i) * (w + gap), y: 210, width: w, height: 410)
                let color = paletteHex(i)
                var ids = [shape(card, geometry: "roundRect", radius: 30, fill: hex(style.card), line: hex(style.line), lineWidth: 1.5)]
                ids.append(shape(probe["col.\(i).bar"] ?? CGRect(x: card.minX + 32, y: card.minY + 32, width: 56, height: 8), geometry: "roundRect", radius: 4, fill: color))
                if let text = placedText("col.\(i).title", column.title, size: 38, font: style.titleFont, bold: true, room: card.width - 64,
                                         fallback: CGRect(x: card.minX + 32, y: card.minY + 60, width: card.width - 64, height: 100)) {
                    ids.append(text)
                }
                if let list = bulletBox("col.\(i)", items: column.bullets, size: column.bullets.count > 4 ? 26 : 30, dots: [color], right: card.maxX - 32,
                                        fallback: CGRect(x: card.minX + 32, y: card.minY + 170, width: card.width - 64, height: card.height - 200)) {
                    ids.append(list)
                }
                step(ids.map { .shape($0) })
            }
        case .imageText:
            let frame = probe["image"] ?? CGRect(x: pad, y: 80, width: 520, height: 560)
            if let image = slide.image, photo(image.id, frame: frame, radius: 36) != nil {
                // The picture is in.
            } else {
                // Room for a picture, as the slide shows it.
                let placeholder = ZStack {
                    LinearGradient(colors: [style.accent, style.palette.dropFirst().first ?? style.accent], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .opacity(0.3)
                    Image(systemName: "sparkles").font(style.body(80, .light)).foregroundColor(style.text.opacity(0.6))
                }
                // Corners cut into the picture itself: not every viewer rounds a picture's outline.
                if let rel = rendered(placeholder.clipShape(RoundedRectangle(cornerRadius: 36)), size: frame.size) { picture(rel: rel, frame: frame, radius: 36) }
            }
            let right = width - pad
            placedText("title", slide.title, size: 52, font: style.titleFont, bold: true, tracking: -1, room: probe["title"].map { right - $0.minX },
                       fallback: CGRect(x: 660, y: 120, width: 540, height: 140))
            if let box = bulletBox("b", items: slide.bullets, size: 28, dots: palette, right: right, fallback: CGRect(x: 660, y: 280, width: 540, height: 320)) {
                for i in slide.bullets.indices { step([.paragraph(box, i)]) }
            }
        case .bigNumber:
            placedText("title", slide.title, size: 34, bold: true, color: secondaryHex, align: "ctr", room: full, fallback: CGRect(x: pad, y: 130, width: full, height: 70))
            placedText("stat", slide.stat?.value ?? "", size: 230, font: style.titleFont, bold: true, color: accentHex, align: "ctr", tracking: -6, room: full,
                       gradient: [accentHex, second], gradientAngle: 0, fallback: CGRect(x: pad, y: 200, width: full, height: 260))
            placedText("label", slide.stat?.label ?? "", size: 36, align: "ctr", room: 900, fallback: CGRect(x: 190, y: 470, width: 900, height: 130))
        case .quote:
            // The mark is set taller than its frame on the slide, so it isn't shrunk to fit.
            let mark = probe["mark"] ?? CGRect(x: pad + 20, y: 90, width: 200, height: 170)
            placedText("mark", "“", size: 260, font: style.titleFont, bold: true, color: accentHex, fit: false, fallback: mark)
            placedText("quote", slide.quote?.text ?? slide.title, size: 54, bold: true, italic: true, tracking: -0.8, room: 1060, fallback: CGRect(x: pad + 20, y: 260, width: 1060, height: 280))
            if let author = slide.quote?.author, !author.isEmpty {
                placedText("author", "— \(author)", size: 30, color: secondaryHex, room: 1060, fallback: CGRect(x: pad + 20, y: 560, width: 1000, height: 60))
            }
        case .timeline:
            title(52, top: 76, height: 120)
            let items = Array(slide.items.prefix(6))
            let line = probe["line"] ?? CGRect(x: pad, y: 330, width: full, height: 6)
            shape(line, geometry: "roundRect", radius: 3, gradient: Array(palette.prefix(max(items.count, 2))))
            let gap: CGFloat = 24
            let w = (full - gap * CGFloat(max(items.count - 1, 0))) / CGFloat(max(items.count, 1))
            for (i, item) in items.enumerated() {
                let x = pad + CGFloat(i) * (w + gap)
                var ids = [shape(probe["t.\(i).dot"] ?? CGRect(x: x, y: line.midY - 18, width: 36, height: 36), geometry: "ellipse", fill: paletteHex(i),
                                 line: hex(style.background.first), lineWidth: 6)]
                let titleFrame = probe["t.\(i).title"] ?? CGRect(x: x, y: line.maxY + 40, width: w, height: 90)
                if let text = placedText("t.\(i).title", item.title, size: items.count > 4 ? 28 : 34, font: style.titleFont, bold: true, room: w, fallback: titleFrame) {
                    ids.append(text)
                }
                if let detail = placedText("t.\(i).detail", item.detail, size: items.count > 4 ? 22 : 26, color: secondaryHex, room: w,
                                           fallback: CGRect(x: x, y: titleFrame.maxY + 16, width: w, height: 160)) {
                    ids.append(detail)
                }
                step(ids.map { .shape($0) })
            }
        case .table:
            title(52, top: 70, height: 120)
            let rows = Array(slide.table.prefix(6))
            let rowHeight: CGFloat = rows.count > 5 ? 64 : 76
            let frame = probe["table"] ?? CGRect(x: pad, y: 210, width: full, height: rowHeight * CGFloat(rows.count))
            let heights = rows.indices.map { probe["row.\($0)"]?.height ?? rowHeight }
            table(rows: rows, frame: frame, heights: heights, size: rows.count > 5 ? 24 : 28, padding: 26)
        case .diagram:
            title(48, top: 60, height: 100)
            let nodes = Array((slide.diagram?.nodes ?? []).prefix(6))
            let center = probe["center"] ?? CGRect(x: 640 - 115, y: 420 - 115, width: 230, height: 230)
            let middle = CGPoint(x: center.midX, y: center.midY)
            let frames: [CGRect] = nodes.indices.map { i in
                if let frame = probe["node.\(i)"] { return frame }
                let angle = -Double.pi / 2 + Double(i) * 2 * Double.pi / Double(max(nodes.count, 1))
                return CGRect(x: 640 + CGFloat(cos(angle)) * 420 - 150, y: 420 + CGFloat(sin(angle)) * 210 - 36, width: 300, height: 72)
            }
            let lines = frames.map { line(from: middle, to: CGPoint(x: $0.midX, y: $0.midY), color: hex(style.line)) }
            let label = slide.diagram?.center ?? slide.title
            let labelSize = fitted(label, font: style.titleFont, size: 30, bold: true, in: center.insetBy(dx: 26, dy: 26).size)
            let labelLines = brokenRuns(label, width: center.width - 52, size: labelSize, color: hex(style.onAccent), bold: true, font: style.titleFont)
            textBox(x: center.minX, y: center.minY, w: center.width, h: center.height,
                    paragraphs: [paragraph(labelLines.runs, align: "ctr", lineHeight: lineHeight(style.titleFont, labelSize, bold: true))],
                    anchor: "ctr", gradient: [accentHex, second], gradientAngle: 45, geometry: "ellipse", wrap: false)
            for (i, node) in nodes.enumerated() {
                let frame = frames[i]
                let size = fitted(node, font: style.bodyFont, size: 25, bold: true, in: CGSize(width: frame.width - 48, height: frame.height - 22))
                let label = brokenRuns(node, width: frame.width - 48, size: size, color: textHex, bold: true)
                let box = textBox(x: frame.minX, y: frame.minY, w: frame.width, h: frame.height, paragraphs: [paragraph(label.runs, align: "ctr", lineHeight: lineHeight(style.bodyFont, size, bold: true))], anchor: "ctr",
                                  fill: style.isLight ? "FFFFFF" : "1D1A20", geometry: "roundRect", radius: frame.height / 2, line: paletteHex(i), lineWidth: 3, wrap: false)
                step([.shape(lines[i]), .shape(box)])
            }
        case .closing:
            placedText("title", slide.title, size: 84, font: style.titleFont, bold: true, align: "ctr", tracking: -2, room: 1040, fallback: CGRect(x: 120, y: 200, width: 1040, height: 200))
            shape(probe["bar"] ?? CGRect(x: 570, y: 420, width: 140, height: 10), geometry: "roundRect", radius: 5, gradient: [accentHex, second])
            placedText("subtitle", slide.subtitle, size: 34, color: secondaryHex, align: "ctr", room: 1040, fallback: CGRect(x: 120, y: 450, width: 1040, height: 120))
        }
    }

    private func footerAndBrand() {
        let brand = deck.brand
        if slide.layout != .cover && slide.layout != .closing && deck.slides.count > 1 {
            let footer = brand.map { $0.footer.isEmpty ? deck.title : $0.footer } ?? deck.title
            let color = hex(style.secondary.opacity(0.8))
            placedText("footer", footer, size: 18, color: color, room: 800, fallback: CGRect(x: pad, y: 656, width: 800, height: 30))
            if brand?.showNumbers != false {
                placedText("page", "\(index + 1) / \(deck.slides.count)", size: 18, color: color, align: "r", room: 200, fallback: CGRect(x: width - pad - 200, y: 656, width: 200, height: 30))
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
        picture(rel: addMedia(data, ext: "png"), frame: CGRect(x: x, y: y, width: width, height: height))
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
        let frame = CGRect(x: x, y: y, width: w, height: h)
        let align = el.align == .center ? "ctr" : el.align == .trailing ? "r" : "l"
        let font = el.titleFont ? style.titleFont : style.bodyFont
        switch el.kind {
        case .text:
            let color = el.color.map { hex(Color(hex: $0)) } ?? textHex
            let size = fitted(el.text, font: font, size: CGFloat(el.fontSize), bold: el.bold, italic: el.italic, in: frame.size)
            let paragraphs = el.text.components(separatedBy: "\n").map {
                paragraph(run($0, size: size, color: color, bold: el.bold, italic: el.italic, font: font, alpha: el.opacity), align: align)
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
            let size = fitted(el.text, font: font, size: CGFloat(el.fontSize), bold: el.bold, italic: el.italic, in: CGSize(width: w - 48, height: h))
            var block: CGFloat = 0
            let paragraphs = el.text.isEmpty ? [] : el.text.components(separatedBy: "\n").map { line -> String in
                let broken = brokenRuns(line, width: w - 48, size: size, color: textColor, bold: el.bold, italic: el.italic, font: font)
                block = max(block, broken.width)
                return paragraph(broken.runs, align: align, lineHeight: lineHeight(font, size, bold: el.bold))
            }
            // On the slide the text is a block in the middle of the shape, its lines aligned inside it.
            let side = align == "ctr" ? 24 : max(24, (w - block) / 2)
            return [textBox(x: x, y: y, w: w, h: h, paragraphs: paragraphs, anchor: "ctr", fill: fill, fillAlpha: el.fillOpacity * el.opacity, geometry: geometry,
                            radius: min(w, h) * 0.18, line: el.strokeWidth > 0 ? (el.stroke.map { hex(Color(hex: $0)) } ?? textHex) : nil,
                            lineWidth: CGFloat(el.strokeWidth), rotation: el.rotation, inset: CGSize(width: side, height: 0), wrap: false)]
        case .icon:
            let color = el.fill.map { Color(hex: $0) } ?? style.accent
            let view = Image(systemName: el.symbol).resizable().scaledToFit().foregroundColor(color.opacity(el.fillOpacity))
            guard let rel = rendered(view, size: frame.size) else { return nil }
            return [picture(rel: rel, frame: frame, rotation: el.rotation, alpha: el.opacity)]
        case .image:
            guard let id = el.image, let picture = photo(id, frame: frame, radius: 24, rotation: el.rotation, alpha: el.opacity) else { return nil }
            return [picture]
        case .table:
            guard !el.rows.isEmpty else { return nil }
            let heights = Array(repeating: h / CGFloat(el.rows.count), count: el.rows.count)
            return [table(rows: el.rows, frame: frame, heights: heights, size: min(CGFloat(el.fontSize), 30), padding: 18, firstColumnBold: false)]
        case .chart:
            let view = ChartView(spec: el.chart ?? ChartSpec(), style: style)
            guard let rel = rendered(view, size: frame.size) else { return nil }
            return [picture(rel: rel, frame: frame, rotation: el.rotation, alpha: el.opacity)]
        case .qr:
            guard let image = QRImage.image(el.link, scale: 16), let data = image.pngData() else { return nil }
            let inset = w * 0.06
            let card = shape(frame, geometry: "roundRect", radius: 16, fill: "FFFFFF", rotation: el.rotation)
            let code = picture(rel: addMedia(data, ext: "png"), frame: frame.insetBy(dx: inset, dy: inset), rotation: el.rotation)
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
