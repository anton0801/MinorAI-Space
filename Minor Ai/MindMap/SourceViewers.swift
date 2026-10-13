//
//  SourceViewers.swift
//  Minor Ai
//
//  Opening a material where an idea comes from:
//  - a PDF or a scan: the kept original at the page, the passage marked only where its place on the
//    page is known and still matches the page's text (or the scan's recognized lines); pages are
//    counted from 1, and a printed page number that differs is said separately;
//  - a recording: the kept audio from the passage's start, its transcript with times; a line plays
//    from where it starts, the marked line follows what is playing, leaving stops it;
//  - text (a pasted note, a TXT or RTF file, a web page's or a video's saved text): the saved text
//    with the passage marked, and for a page the date it was read.
//  "Back to the idea" closes Sources and shows the idea on the map as it was.
//

import AVFoundation
import PDFKit
import SwiftUI

// Where Sources goes when a passage is opened.
struct SourceRoute: Hashable {
    let materialID: UUID
    var segmentID: String?
    var nodeID: UUID?
    var asText = false     // the saved text even when there is an original
}

struct SourceViewer: View {
    let mapID: UUID
    let route: SourceRoute
    let theme: AppTheme
    var onBackToNode: (UUID) -> Void

    @ObservedObject private var materials = ProjectMaterialStore.shared

    var body: some View {
        let material = materials.material(route.materialID, in: mapID)
        Group {
            if let material {
                let segment = route.segmentID.flatMap { id in material.segment(id) }.flatMap { material.fits($0) ? $0 : nil }
                if !route.asText, let original = material.original, let url = OriginalStore.url(for: original), original.isPDF {
                    PDFSourceView(material: material, url: url, segment: segment, nodeTitle: nodeTitle, theme: theme, onBack: backToNode)
                } else if !route.asText, let original = material.original, let url = OriginalStore.url(for: original), original.isAudio {
                    AudioSourceView(material: material, url: url, segment: segment, nodeTitle: nodeTitle, theme: theme, onBack: backToNode)
                } else {
                    TextSourceView(material: material, segment: segment, nodeTitle: nodeTitle, theme: theme, onBack: backToNode)
                }
            } else {
                VStack(spacing: 8) {
                    Text("Source isn’t available").minorFont(17, .semibold, maxScale: 1.3)
                    Text("The material was removed from this iPhone.")
                        .minorFont(14, maxScale: 1.3)
                        .foregroundColor(MinorColor.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.background.ignoresSafeArea())
            }
        }
        .toolbarBackground(theme.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private var nodeTitle: String? {
        route.nodeID.flatMap { MapStore.shared.map(mapID)?.root.node($0)?.title }
    }

    private var backToNode: (() -> Void)? {
        guard let id = route.nodeID, MapStore.shared.map(mapID)?.root.node(id) != nil else { return nil }
        return { onBackToNode(id) }
    }
}

// The bottom card of a viewer: the idea, the exact passage, Back to the Idea.
private struct SourceFooter: View {
    let nodeTitle: String?
    let quote: String?
    var caution: String? = nil
    let onBack: (() -> Void)?

    var body: some View {
        if nodeTitle != nil || quote != nil {
            VStack(alignment: .leading, spacing: 8) {
                Capsule().fill(Color.white.opacity(0.25)).frame(width: 36, height: 5).frame(maxWidth: .infinity).accessibilityHidden(true)
                if let nodeTitle {
                    Text(quote == nil ? L("Idea “\(nodeTitle)”") : L("Source of the idea “\(nodeTitle)”"))
                        .minorFont(quote == nil ? 15 : 17, quote == nil ? .regular : .semibold, maxScale: 1.3)
                        .foregroundColor(quote == nil ? MinorColor.textSecondary : MinorColor.textPrimary)
                        .lineLimit(2)
                }
                if let quote {
                    Text("Exact passage")
                        .minorFont(13, style: .footnote, maxScale: 1.3)
                        .foregroundColor(MinorColor.textTertiary)
                    Text("«\(quote)»")
                        .minorFont(16, maxScale: 1.4)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                    if let caution {
                        Label(caution, systemImage: "exclamationmark.triangle")
                            .minorFont(13, maxScale: 1.3)
                            .foregroundColor(BranchColor.sun.color)
                    }
                }
                if let onBack {
                    Button(action: onBack) {
                        Text("Back to the Idea")
                            .minorFont(17, .semibold, maxScale: 1.3)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white))
                    }
                    .buttonStyle(PressScale())
                    .padding(.top, 6)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .background(
                UnevenTop(radius: 22).fill(MinorColor.editorSheet).ignoresSafeArea(edges: .bottom)
            )
        }
    }
}

// A rectangle with rounded top corners.
private struct UnevenTop: Shape {
    let radius: CGFloat
    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(roundedRect: rect, byRoundingCorners: [.topLeft, .topRight], cornerRadii: CGSize(width: radius, height: radius)).cgPath)
    }
}

// MARK: - PDF and scans

struct PDFSourceView: View {
    let material: ProjectMaterial
    let url: URL
    let segment: SourceSegment?
    let nodeTitle: String?
    let theme: AppTheme
    let onBack: (() -> Void)?

    @State private var document: PDFDocument?
    @State private var page = 0
    @State private var marked: [CGRect] = []   // page coordinates of the checked passage
    @State private var failed = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(material.original?.name ?? material.title)
                    .minorFont(24, .bold, maxScale: 1.3)
                    .lineLimit(2)
                Text(material.kind == .scan ? L("Scan kept on this iPhone") : L("Original on this iPhone"))
                    .minorFont(14, maxScale: 1.3)
                    .foregroundColor(MinorColor.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            if let document {
                PDFPageView(document: document, page: $page, marked: marked)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(.horizontal, 12)
                    .accessibilityLabel(Text(pageLabel(document)))
                pager(document)
            } else if failed {
                Spacer()
                Text("Couldn’t open the original.").minorFont(15, maxScale: 1.3).foregroundColor(MinorColor.textSecondary)
                Spacer()
            } else {
                Spacer()
                ProgressView().tint(.white)
                Spacer()
            }
            SourceFooter(nodeTitle: nodeTitle, quote: segment?.text, caution: caution, onBack: onBack)
        }
        .foregroundColor(MinorColor.textPrimary)
        .background(theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button { SystemShare.present(file: url, name: material.original?.name ?? material.title) } label: { Label("Share Original", systemImage: "square.and.arrow.up") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                .accessibilityLabel("More")
            }
        }
        .task { await load() }
    }

    private var caution: String? {
        guard let segment else { return nil }
        if segment.isUncertain { return L("Recognized with doubts: check it on the page.") }
        if marked.isEmpty, segment.page != nil, document != nil { return L("The exact place on the page isn’t known.") }
        return nil
    }

    private func pager(_ document: PDFDocument) -> some View {
        HStack(spacing: 18) {
            Button { page = max(0, page - 1) } label: { pagerIcon("chevron.left") }
                .disabled(page == 0)
                .accessibilityLabel("Previous Page")
            Text(pageLabel(document))
                .minorFont(15, maxScale: 1.3)
                .monospacedDigit()
                .foregroundColor(MinorColor.textSecondary)
            Button { page = min(document.pageCount - 1, page + 1) } label: { pagerIcon("chevron.right") }
                .disabled(page >= document.pageCount - 1)
                .accessibilityLabel("Next Page")
        }
        .padding(.vertical, 10)
    }

    private func pagerIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .semibold))
            .frame(width: 44, height: 44)
            .background(Circle().fill(Color.white.opacity(0.08)))
    }

    // "4 of 12", and the printed page number when the PDF has one that differs.
    private func pageLabel(_ document: PDFDocument) -> String {
        let shown = L("\(page + 1) of \(document.pageCount)")
        if let label = document.page(at: page)?.label, !label.isEmpty, label != String(page + 1) {
            return shown + " · " + L("page “\(label)” in print")
        }
        return shown
    }

    private func load() async {
        let url = url
        let segment = segment
        let kind = material.kind
        let result = await Task.detached(priority: .userInitiated) { () -> (PDFDocument, Int, [CGRect])? in
            guard let document = PDFDocument(url: url), document.pageCount > 0 else { return nil }
            guard let segment, let index = segment.page, index < document.pageCount, let pdfPage = document.page(at: index) else {
                return (document, 0, [])
            }
            return (document, index, PDFSourceView.checkedRects(segment, on: pdfPage, isScan: kind == .scan))
        }.value
        if let result {
            document = result.0
            page = result.1
            marked = result.2
        } else {
            failed = true
        }
    }

    // The passage's lines on the page, only when they are known and the page still says it: for a
    // PDF the page's text at the saved range must be the passage; a scan has its recognized boxes.
    nonisolated static func checkedRects(_ segment: SourceSegment, on page: PDFPage, isScan: Bool) -> [CGRect] {
        guard let rects = segment.rects, !rects.isEmpty else { return [] }
        if !isScan {
            guard let range = segment.nsRange, let text = page.string as NSString?, NSMaxRange(range) <= text.length else { return [] }
            let found = text.substring(with: range).split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard found == segment.text else { return [] }
        }
        let bounds = page.bounds(for: .cropBox)
        return rects.compactMap { r in
            guard r.count == 4, r.allSatisfy({ $0.isFinite && $0 >= -0.01 && $0 <= 1.01 }) else { return nil }
            return CGRect(x: bounds.minX + r[0] * bounds.width, y: bounds.maxY - (r[1] + r[3]) * bounds.height,
                          width: r[2] * bounds.width, height: r[3] * bounds.height)
        }
    }
}

// The PDF at the width of the screen, pages one under another, zoomable; it opens at the marked
// lines (highlight annotations in memory only, the file is never changed) or at the page's top.
struct PDFPageView: UIViewRepresentable {
    let document: PDFDocument
    @Binding var page: Int
    let marked: [CGRect]

    func makeCoordinator() -> Coordinator { Coordinator(page: $page) }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.autoScales = true
        view.backgroundColor = .clear
        view.pageShadowsEnabled = false
        view.pageBreakMargins = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        view.document = document
        mark(in: view)
        context.coordinator.observe(view)
        // Once laid out: to the marked lines, or to the page.
        DispatchQueue.main.async {
            guard let target = document.page(at: page) else { return }
            if let first = marked.first {
                view.go(to: first.insetBy(dx: 0, dy: -140), on: target)
            } else {
                view.go(to: target)
            }
            context.coordinator.ready = true
        }
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        guard context.coordinator.ready, let target = document.page(at: page), view.currentPage !== target else { return }
        view.go(to: target)
    }

    private func mark(in view: PDFView) {
        guard let target = document.page(at: page) else { return }
        for rect in marked {
            let annotation = PDFAnnotation(bounds: rect.insetBy(dx: -2, dy: -1), forType: .highlight, withProperties: nil)
            annotation.color = UIColor(MinorColor.accent).withAlphaComponent(0.35)
            target.addAnnotation(annotation)
        }
    }

    final class Coordinator: NSObject {
        let page: Binding<Int>
        var ready = false
        private var token: NSObjectProtocol?

        init(page: Binding<Int>) { self.page = page }

        // Scrolling to another page updates the counter.
        func observe(_ view: PDFView) {
            token = NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: view, queue: .main) { [weak self, weak view] _ in
                guard let self, self.ready, let view, let current = view.currentPage, let document = view.document else { return }
                let index = document.index(for: current)
                if index != NSNotFound, self.page.wrappedValue != index { self.page.wrappedValue = index }
            }
        }

        deinit { if let token { NotificationCenter.default.removeObserver(token) } }
    }
}

// MARK: - Recordings

struct AudioSourceView: View {
    let material: ProjectMaterial
    let url: URL
    let segment: SourceSegment?
    let nodeTitle: String?
    let theme: AppTheme
    let onBack: (() -> Void)?

    @StateObject private var player = SourcePlayer()
    @State private var levels: [Float] = []

    private var passages: [SourceSegment] {
        (material.segments ?? []).filter { $0.start != nil && material.fits($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text(material.title)
                    .minorFont(26, .bold, maxScale: 1.3)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text("\(L("Recording")) · \(SourceTime.text(player.duration))")
                    .minorFont(15, maxScale: 1.3)
                    .monospacedDigit()
                    .foregroundColor(MinorColor.textSecondary)
            }
            .padding(.horizontal, 20)
            waveform
                .frame(height: 120)
                .padding(.horizontal, 20)
                .padding(.top, 18)
            controls.padding(.top, 14)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        if !passages.isEmpty {
                            Text("Transcript")
                                .minorFont(24, .bold, maxScale: 1.3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityAddTraits(.isHeader)
                            LazyVStack(spacing: 0) {
                                ForEach(passages) { passage in
                                    transcriptRow(passage).id(passage.id)
                                }
                            }
                            .padding(.top, 6)
                        } else {
                            Text("No times were saved for this recording: it plays from the start.")
                                .minorFont(14, maxScale: 1.3)
                                .foregroundColor(MinorColor.textTertiary)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 16)
                }
                .onChange(of: playingID) { id in
                    guard let id, player.isPlaying else { return }
                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) }
                }
                .onAppear {
                    if let id = segment?.id {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
            SourceFooter(nodeTitle: nodeTitle, quote: nil, onBack: onBack.map { back in { player.stop(); back() } })
        }
        .foregroundColor(MinorColor.textPrimary)
        .background(theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task {
            player.load(url, at: segment?.start ?? 0)
            levels = await Task.detached(priority: .utility) { SourcePlayer.levels(of: url, bars: 64) }.value
        }
        .onDisappear { player.stop() }
    }

    // The passage playing now (or the opened one before anything plays).
    private var playingID: String? {
        let time = player.time
        return passages.last { ($0.start ?? 0) <= time + 0.05 }?.id ?? segment?.id
    }

    private var waveform: some View {
        GeometryReader { geo in
            let count = max(levels.count, 1)
            let width = geo.size.width / CGFloat(count)
            let duration = max(player.duration, 0.01)
            let range = segment.flatMap { s in s.start.map { ($0, s.end ?? $0) } }
            ZStack(alignment: .topLeading) {
                if let range {
                    let x0 = CGFloat(range.0 / duration) * geo.size.width
                    let x1 = CGFloat(range.1 / duration) * geo.size.width
                    Rectangle()
                        .fill(MinorColor.accent.opacity(0.14))
                        .frame(width: max(2, x1 - x0), height: geo.size.height - 24)
                        .offset(x: x0)
                    ForEach([x0, x1], id: \.self) { x in
                        Rectangle().fill(MinorColor.accent).frame(width: 2, height: geo.size.height - 24).offset(x: x - 1)
                    }
                    Text(SourceTime.text(range.0)).minorFont(13, .semibold, maxScale: 1.2).monospacedDigit()
                        .foregroundColor(MinorColor.accent)
                        .offset(x: max(0, x0 - 18), y: geo.size.height - 18)
                    Text(SourceTime.text(range.1)).minorFont(13, .semibold, maxScale: 1.2).monospacedDigit()
                        .foregroundColor(MinorColor.accent)
                        .offset(x: min(geo.size.width - 40, x1 - 18), y: geo.size.height - 18)
                }
                HStack(alignment: .center, spacing: 0) {
                    ForEach(levels.indices, id: \.self) { i in
                        let t = (Double(i) + 0.5) / Double(count) * duration
                        let inside = range.map { t >= $0.0 && t <= $0.1 } ?? false
                        Capsule()
                            .fill(inside ? MinorColor.accent : Color.white.opacity(t <= player.time ? 0.7 : 0.3))
                            .frame(width: max(1.5, width * 0.45), height: max(4, CGFloat(levels[i]) * (geo.size.height - 30)))
                            .frame(width: width)
                    }
                }
                .frame(height: geo.size.height - 24)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                player.seek(to: Double(value.location.x / geo.size.width) * duration)
            })
        }
        .accessibilityElement()
        .accessibilityLabel("Recording")
        .accessibilityValue(Text("\(SourceTime.text(player.time)) / \(SourceTime.text(player.duration))"))
        .accessibilityAdjustableAction { direction in
            player.seek(to: player.time + (direction == .increment ? 15 : -15))
        }
    }

    private var controls: some View {
        HStack(spacing: 34) {
            Button { player.seek(to: player.time - 15) } label: { round("gobackward.15", 58) }
                .accessibilityLabel("Back 15 Seconds")
            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.black)
                    .frame(width: 80, height: 80)
                    .background(Circle().fill(Color.white))
            }
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            Button { player.seek(to: player.time + 15) } label: { round("goforward.15", 58) }
                .accessibilityLabel("Forward 15 Seconds")
        }
        .buttonStyle(PressScale())
    }

    private func round(_ icon: String, _ size: CGFloat) -> some View {
        Image(systemName: icon)
            .font(.system(size: 22, weight: .medium))
            .frame(width: size, height: size)
            .background(Circle().fill(Color.white.opacity(0.07)))
    }

    private func transcriptRow(_ passage: SourceSegment) -> some View {
        let current = passage.id == playingID
        return Button { player.seek(to: passage.start ?? 0, play: true) } label: {
            HStack(alignment: .top, spacing: 14) {
                Text(SourceTime.text(passage.start ?? 0))
                    .minorFont(15, maxScale: 1.3)
                    .monospacedDigit()
                    .foregroundColor(current ? MinorColor.accent : MinorColor.textTertiary)
                    .frame(width: 52, alignment: .leading)
                Rectangle().fill(current ? MinorColor.accent : .clear).frame(width: 3).padding(.vertical, 2)
                Text(passage.text)
                    .minorFont(17, current ? .semibold : .regular, maxScale: 1.4)
                    .foregroundColor(current ? MinorColor.textPrimary : MinorColor.textSecondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
        .accessibilityLabel(Text("\(SourceTime.text(passage.start ?? 0)), \(passage.text)"))
        .accessibilityHint("Plays from here")
        .accessibilityAddTraits(current ? .isSelected : [])
    }
}

// AVAudioPlayer with a published position.
@MainActor
final class SourcePlayer: ObservableObject {
    @Published private(set) var time: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var isPlaying = false
    private var player: AVAudioPlayer?
    private var timer: Timer?

    func load(_ url: URL, at start: Double) {
        guard player == nil, let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.prepareToPlay()
        self.player = player
        duration = player.duration
        seek(to: start)
    }

    func toggle() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            timer?.invalidate()
        } else {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try? AVAudioSession.sharedInstance().setActive(true)
            player.play()
            isPlaying = true
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        }
    }

    func seek(to seconds: Double, play: Bool = false) {
        guard let player else { return }
        player.currentTime = min(max(0, seconds), max(0, player.duration - 0.05))
        time = player.currentTime
        if play && !player.isPlaying { toggle() }
    }

    func stop() {
        player?.stop()
        isPlaying = false
        timer?.invalidate()
        timer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func tick() {
        guard let player else { return }
        time = player.currentTime
        if !player.isPlaying {
            isPlaying = false
            timer?.invalidate()
        }
    }

    // Loudness of `bars` equal parts of the recording, 0…1.
    nonisolated static func levels(of url: URL, bars: Int) -> [Float] {
        guard let file = try? AVAudioFile(forReading: url), file.length > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 8192) else { return [] }
        let per = max(1, Int(file.length) / bars)
        var result: [Float] = []
        var sum: Float = 0
        var count = 0
        while file.framePosition < file.length {
            do { try file.read(into: buffer, frameCount: 8192) } catch { break }
            guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { break }
            for i in 0..<Int(buffer.frameLength) {
                sum += data[i] * data[i]
                count += 1
                if count == per {
                    result.append(sqrt(sum / Float(count)))
                    sum = 0
                    count = 0
                }
            }
        }
        let peak = max(result.max() ?? 1, 0.0001)
        return result.prefix(bars).map { min(1, max(0.06, $0 / peak)) }
    }
}

// MARK: - Text

struct TextSourceView: View {
    let material: ProjectMaterial
    let segment: SourceSegment?
    let nodeTitle: String?
    let theme: AppTheme
    let onBack: (() -> Void)?

    @Environment(\.openURL) private var openURL
    @ObservedObject private var network = NetworkMonitor.shared
    @State private var offline = false

    // The text in three parts around the passage: found by its saved range, or as the exact saved
    // passage (pages and videos keep their passages as their text).
    private var parts: (before: String, marked: String?, after: String) {
        let text = material.text ?? ""
        let ns = text as NSString
        if let segment {
            if segment.page == nil, let range = segment.nsRange, NSMaxRange(range) <= ns.length {
                return (ns.substring(to: range.location), ns.substring(with: range), ns.substring(from: NSMaxRange(range)))
            }
            let found = ns.range(of: segment.text)
            if found.location != NSNotFound {
                return (ns.substring(to: found.location), ns.substring(with: found), ns.substring(from: NSMaxRange(found)))
            }
        }
        return (text, nil, "")
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        header.padding(.bottom, 6)
                        let parts = parts
                        ForEach(Array(paragraphs(parts.before).enumerated()), id: \.offset) { _, paragraph in
                            paragraphText(paragraph)
                        }
                        if let marked = parts.marked {
                            Text(marked.trimmingCharacters(in: .whitespacesAndNewlines))
                                .minorFont(16, maxScale: 1.6)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 10).fill(MinorColor.accent.opacity(0.16)))
                                .id("marked")
                                .accessibilityLabel(Text("\(L("Exact passage")): \(marked)"))
                        }
                        ForEach(Array(paragraphs(parts.after).enumerated()), id: \.offset) { _, paragraph in
                            paragraphText(paragraph)
                        }
                    }
                    .padding(20)
                }
                .onAppear {
                    guard parts.marked != nil else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        withAnimation { proxy.scrollTo("marked", anchor: .center) }
                    }
                }
            }
            SourceFooter(nodeTitle: nodeTitle, quote: nil, onBack: onBack)
        }
        .foregroundColor(MinorColor.textPrimary)
        .background(theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .alert(L("No connection. The link opens once you’re online."), isPresented: $offline) {
            Button("Try Again") { openLink() }
            Button("OK", role: .cancel) {}
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(material.title).minorFont(22, .bold, maxScale: 1.3)
            Text(SourcesSheet.detail(material, ideas: nil))
                .minorFont(14, maxScale: 1.3)
                .foregroundColor(MinorColor.textTertiary)
            Text(note)
                .minorFont(13, style: .footnote, maxScale: 1.4)
                .foregroundColor(MinorColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            if material.url != nil {
                Button(action: openLink) {
                    Label(material.kind == .youtube ? L("Open Video") : L("Open Website"), systemImage: "safari")
                        .minorFont(14, .semibold, maxScale: 1.3)
                        .foregroundColor(MinorColor.accent)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
    }

    private var note: String {
        if let date = material.extractedAt {
            let when = date.formatted(.dateTime.day().month(.wide).year().locale(AppLanguage.current.locale))
            return material.kind == .youtube
                ? L("The video’s text as Minor read it on \(when).")
                : L("The page’s text as Minor read it on \(when). The live site may have changed since.")
        }
        switch material.originalStatus {
        case .available, .missing, .removed:
            return L("The text Minor read from this material.")
        case .none:
            return L("The text Minor read from this material. The original file isn’t kept.")
        }
    }

    private func openLink() {
        guard let link = material.url, let url = URL(string: link) else { return }
        guard network.isOnline else { return offline = true }
        openURL(url)
    }

    private func paragraphs(_ text: String) -> [String] {
        text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func paragraphText(_ paragraph: String) -> some View {
        Text(paragraph)
            .minorFont(16, maxScale: 1.6)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Opening videos at a time

enum VideoLink {
    // The video's own address with the time the passage starts, when the passage has one.
    static func url(_ link: String, at seconds: Double?) -> URL? {
        guard var components = URLComponents(string: link) else { return nil }
        guard let seconds, seconds >= 0 else { return components.url }
        var items = (components.queryItems ?? []).filter { $0.name != "t" }
        items.append(URLQueryItem(name: "t", value: "\(Int(seconds.rounded(.down)))s"))
        components.queryItems = items
        return components.url
    }
}
