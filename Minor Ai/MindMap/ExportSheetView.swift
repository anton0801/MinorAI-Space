//
//  ExportSheetView.swift
//  Minor Ai
//
//  Export Map sheet: image, PDF, OPML for Xmind / MindNode (PRO), Markdown outline,
//  copy as text. Files go out through the system share sheet.
//

import SwiftUI
import UIKit

struct ExportSheetView: View {
    let map: MindMap
    let layout: MapLayout
    let theme: AppTheme
    var onUpgrade: (_ pro: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var account = AccountStore.shared
    @State private var shareURL: URL?
    @State private var toast: String?
    @State private var isUploading = false
    @State private var isShared = false
    @State private var confirmShare = false

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(MinorColor.fillThumb).frame(width: 36, height: 5).padding(.top, 8)
            ZStack {
                Text("Export Map").font(.system(size: 20, weight: .bold))
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(MinorColor.closeFill))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Close")
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 12)

            // Scrolls at the medium sheet height on small phones and with large text.
            ScrollView {
            group("File") {
                row("photo", "Image", trailing: "PNG") { export(.png) }
                row("doc.text", "Document", trailing: "PDF") { export(.pdf) }
                row("list.bullet.indent", "Xmind, MindNode", pro: true) {
                    account.isPro ? export(.opml) : onUpgrade(true)
                }
                row("text.alignleft", "Outline", trailing: "Markdown", last: true) { export(.markdown) }
            }
            group("Share") {
                row("doc.on.doc", "Copy as Text") {
                    UIPasteboard.general.string = map.outline
                    flash(L("Copied"))
                }
                row("link", isUploading ? "Creating Link…" : isShared ? "Update Link" : "Share Link", pro: true, last: !isShared) {
                    guard account.isPro else { return onUpgrade(true) }
                    if isShared { shareLink() } else { confirmShare = true }
                }
                if isShared {
                    row("link.badge.plus", "Stop Sharing", last: true) { stopSharing() }
                }
            }
            if let toast {
                Text(toast)
                    .font(.system(size: 15))
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                    .background(Capsule().fill(MinorColor.row))
                    .padding(.top, 12)
            }
            }
        }
        .foregroundColor(MinorColor.textPrimary)
        .padding(.horizontal, 20)
        .background(MinorColor.sheet.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .sheet(item: Binding(get: { shareURL.map(ShareItem.init) }, set: { shareURL = $0?.url })) { item in
            ActivityView(items: [item.url])
        }
        .confirmationDialog("Share a link to this map?", isPresented: $confirmShare, titleVisibility: .visible) {
            Button("Create Link") { shareLink() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("An image of the map is uploaded, and anyone with the link can see it. You can stop sharing at any time.")
        }
        .onAppear { isShared = SharedMaps.contains(map.id) }
    }

    // MARK: - Rows

    private func group<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(title)
                .textCase(.uppercase)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(MinorColor.textTertiary)
            VStack(spacing: 0) { content() }
                .background(MinorColor.row)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 20)
    }

    private func row(_ icon: String, _ title: LocalizedStringKey, trailing: String? = nil, pro: Bool = false, last: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 17)).frame(width: 24)
                Text(title).font(.system(size: 17))
                Spacer()
                if pro && !account.isPro {
                    Text("PRO").font(.system(size: 13, weight: .semibold)).foregroundColor(MinorColor.pro)
                } else if let trailing {
                    Text(trailing).font(.system(size: 15)).foregroundColor(MinorColor.textChevron)
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if !last { Rectangle().fill(MinorColor.divider).frame(height: 1) }
        }
    }

    // MARK: - Export

    private enum Format { case png, pdf, opml, markdown }

    // A file name iOS and other apps accept: no path separators or reserved characters.
    private var fileName: String {
        let cleaned = map.title
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r\t"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return cleaned.isEmpty ? "Mind Map" : String(cleaned.prefix(60))
    }

    @MainActor
    private func export(_ format: Format) {
        let name = fileName
        let folder = FileManager.default.temporaryDirectory
        do {
            switch format {
            case .png:
                let url = folder.appendingPathComponent("\(name).png")
                guard let data = mapImage()?.pngData() else { return flash(L("Couldn’t export. Try again.")) }
                try data.write(to: url)
                shareURL = url
            case .pdf:
                let url = folder.appendingPathComponent("\(name).pdf")
                try Self.pdf(map: map, image: mapImage()).write(to: url)
                shareURL = url
            case .opml:
                let url = folder.appendingPathComponent("\(name).opml")
                try Self.opml(map).write(to: url, atomically: true, encoding: .utf8)
                shareURL = url
            case .markdown:
                let url = folder.appendingPathComponent("\(name).md")
                try map.outline.write(to: url, atomically: true, encoding: .utf8)
                shareURL = url
            }
        } catch {
            flash(L("Couldn’t export. Try again."))
        }
    }

    // Large maps are rendered at a lower scale so the image stays under `maxPixels`
    // (16 MP by default: bigger images can run older iPhones out of memory).
    @MainActor
    private func mapImage(maxPixels: CGFloat = 16_000_000) -> UIImage? {
        let renderer = ImageRenderer(content: MapSnapshotView(layout: layout, theme: theme, mapStyle: map.mapStyle, lineStyle: map.lineStyle, lineWeight: map.lineWeightValue, links: map.links))
        let points = max(layout.size.width * layout.size.height, 1)
        renderer.scale = min(2, sqrt(maxPixels / points))
        return renderer.uiImage
    }

    // Share Link (PRO): the `share` function stores the map image under a random name and
    // returns its public link. The same map keeps the same link when it is shared again.
    @MainActor
    private func shareLink() {
        guard !isUploading else { return }
        // The server takes images up to 8 MB.
        guard let data = mapImage(maxPixels: 6_000_000)?.pngData() else { return flash(L("Couldn’t create a link. Try again.")) }
        isUploading = true
        Task {
            defer { isUploading = false }
            struct Body: Encodable { let action = "upload"; let mapId: String; let png: String }
            struct Reply: Decodable { let url: String }
            do {
                let reply: Reply = try await BackendClient.shared.invoke(
                    "share", body: Body(mapId: map.id.uuidString.lowercased(), png: data.base64EncodedString())
                )
                SharedMaps.insert(map.id)
                isShared = true
                UIPasteboard.general.string = reply.url
                flash(L("Link copied"))
                if let url = URL(string: reply.url) { shareURL = url }
            } catch BackendError.planRequired {
                onUpgrade(true)
            } catch BackendError.sourceTooLong {
                flash(L("This map is too large to share as an image."))
            } catch BackendError.limitReached {
                flash(L("You’ve reached the limit of shared links. Stop sharing another map first."))
            } catch {
                flash((error as? LocalizedError)?.errorDescription ?? L("Couldn’t create a link. Try again."))
            }
        }
    }

    @MainActor
    private func stopSharing() {
        guard !isUploading else { return }
        isUploading = true
        Task {
            defer { isUploading = false }
            do {
                try await SharedMaps.stop(map.id)
                isShared = false
                flash(L("Link removed"))
            } catch {
                flash((error as? LocalizedError)?.errorDescription ?? L("Couldn’t remove the link. Try again."))
            }
        }
    }

    private func flash(_ text: String) {
        toast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if toast == text { toast = nil } }
    }

    // PDF: the map on the first page, then the outline as text pages.
    static func pdf(map: MindMap, image: UIImage?) -> Data {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)   // A4 in points
        let margin: CGFloat = 40
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        return renderer.pdfData { context in
            context.beginPage()
            let title = map.title as NSString
            title.draw(
                in: CGRect(x: margin, y: margin, width: page.width - margin * 2, height: 40),
                withAttributes: [.font: UIFont.systemFont(ofSize: 22, weight: .bold), .foregroundColor: UIColor.black]
            )
            if let image {
                let box = CGRect(x: margin, y: margin + 50, width: page.width - margin * 2, height: page.height - margin * 2 - 50)
                let scale = min(box.width / image.size.width, box.height / image.size.height)
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                image.draw(in: CGRect(x: box.midX - size.width / 2, y: box.minY, width: size.width, height: size.height))
            }

            let formatter = UIMarkupTextPrintFormatter(markupText: outlineHTML(map))
            let printer = UIPrintPageRenderer()
            printer.addPrintFormatter(formatter, startingAtPageAt: 0)
            printer.setValue(NSValue(cgRect: page), forKey: "paperRect")
            printer.setValue(NSValue(cgRect: page.insetBy(dx: margin, dy: margin)), forKey: "printableRect")
            printer.prepare(forDrawingPages: NSRange(location: 0, length: printer.numberOfPages))
            for index in 0..<printer.numberOfPages {
                context.beginPage()
                printer.drawPage(at: index, in: page)
            }
        }
    }

    private static func outlineHTML(_ map: MindMap) -> String {
        func escape(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        }
        func list(_ nodes: [MindNode]) -> String {
            guard !nodes.isEmpty else { return "" }
            return "<ul>" + nodes.map { node in
                let note = node.note.isEmpty ? "" : "<br><span style=\"color:#666\">\(escape(node.note))</span>"
                return "<li>\(escape(node.title))\(note)\(list(node.children))</li>"
            }.joined() + "</ul>"
        }
        let rootNote = map.root.note.isEmpty ? "" : "<p style=\"color:#666\">\(escape(map.root.note))</p>"
        return """
        <html><body style="font-family:-apple-system,Helvetica;font-size:12pt;color:#111;line-height:1.45">
        <h1 style="font-size:20pt">\(escape(map.title))</h1>\(rootNote)\(list(map.root.children))
        </body></html>
        """
    }

    static func opml(_ map: MindMap) -> String {
        func escape(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
        }
        func outline(_ node: MindNode, depth: Int) -> String {
            let pad = String(repeating: "  ", count: depth + 2)
            let text = escape(MindMap.outlineText(node))
            let note = node.note.isEmpty ? "" : " _note=\"\(escape(node.note))\""
            if node.children.isEmpty { return "\(pad)<outline text=\"\(text)\"\(note)/>" }
            let inner = node.children.map { outline($0, depth: depth + 1) }.joined(separator: "\n")
            return "\(pad)<outline text=\"\(text)\"\(note)>\n\(inner)\n\(pad)</outline>"
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head><title>\(escape(map.title))</title></head>
          <body>
        \(outline(map.root, depth: 0))
          </body>
        </opml>
        """
    }
}

// Static rendering of the whole map for image and PDF export.
struct MapSnapshotView: View {
    let layout: MapLayout
    let theme: AppTheme
    var mapStyle: MapStyle = .classic
    var lineStyle: LineStyle = .curved
    var lineWeight: LineWeight = .regular
    var links: [MapLink] = []
    var watermark = true

    var body: some View {
        ZStack(alignment: .topLeading) {
            theme.background
            if !layout.groups.isEmpty { MapGroupsLayer(layout: layout) }
            Canvas { context, _ in
                for node in layout.nodes {
                    guard let path = layout.connector(to: node, style: lineStyle) else { continue }
                    let color = node.color ?? .mint
                    context.stroke(
                        path,
                        with: .color(node.level == 1 ? color.color : color.line),
                        style: StrokeStyle(lineWidth: (node.level == 1 ? 2 : 1.5) * lineWeight.scale, lineCap: .round)
                    )
                }
            }
            if !links.isEmpty { MapLinksLayer(layout: layout, links: links) }
            ForEach(layout.nodes) { node in
                MindNodeView(node: node, theme: theme, mapStyle: mapStyle)
                    .position(x: node.frame.midX, y: node.frame.midY)
            }
            if watermark {
                Image("minlogo")
                    .resizable()
                    .frame(width: 24, height: 24)
                    .opacity(0.4)
                    .position(x: layout.size.width - 28, y: layout.size.height - 28)
            }
        }
        .frame(width: max(layout.size.width, 320), height: max(layout.size.height, 240), alignment: .topLeading)
    }
}

private struct ShareItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// Maps with a public link, remembered on this iPhone so Export can offer Stop Sharing.
enum SharedMaps {
    private static let key = "sharedMapIDs"

    static func contains(_ id: UUID) -> Bool { ids.contains(id.uuidString) }

    static func insert(_ id: UUID) {
        var all = ids
        all.insert(id.uuidString)
        UserDefaults.standard.set(Array(all), forKey: key)
    }

    static func remove(_ id: UUID) {
        var all = ids
        all.remove(id.uuidString)
        UserDefaults.standard.set(Array(all), forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: pendingKey)
    }

    // A deleted map's link is removed even if the phone is offline at that moment: the removal is
    // queued and retried whenever the app becomes active.
    private static let pendingKey = "sharedMapIDsToStop"

    static func stopOrQueue(_ id: UUID) {
        var pending = Set(UserDefaults.standard.stringArray(forKey: pendingKey) ?? [])
        pending.insert(id.uuidString)
        UserDefaults.standard.set(Array(pending), forKey: pendingKey)
        remove(id)
        Task { await retryPendingStops() }
    }

    static func retryPendingStops() async {
        let pending = UserDefaults.standard.stringArray(forKey: pendingKey) ?? []
        for raw in pending {
            guard let id = UUID(uuidString: raw) else { continue }
            if (try? await stop(id)) != nil {
                var left = Set(UserDefaults.standard.stringArray(forKey: pendingKey) ?? [])
                left.remove(raw)
                UserDefaults.standard.set(Array(left), forKey: pendingKey)
            }
        }
    }

    // Removes the public image on the server.
    static func stop(_ id: UUID) async throws {
        struct Body: Encodable { let action = "delete"; let mapId: String }
        struct Reply: Decodable { let deleted: Bool }
        let _: Reply = try await BackendClient.shared.invoke("share", body: Body(mapId: id.uuidString.lowercased()))
        remove(id)
    }

    private static var ids: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }
}
