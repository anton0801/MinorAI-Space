//
//  DeckExportSheet.swift
//  Minor Ai
//
//  Export a presentation: PDF or PowerPoint, with or without hidden slides, and how many slides
//  the file will have. PowerPoint needs Plus (or PRO): without it the row says so and opens the
//  subscription over this sheet, so closing it comes back to the same choices; once the App Store
//  confirms the subscription the lock goes, and nothing is exported until asked. Making the file
//  shows real progress and can be cancelled (the unfinished file is removed, a late result is
//  dropped); a failure is said in place with Try Again; the ready file can be saved or shared as
//  often as needed.
//

import SwiftUI

struct DeckExportSheet: View {
    enum Format: String, CaseIterable, Identifiable {
        case pdf, pptx
        var id: String { rawValue }
    }

    private enum Stage: Equatable {
        case choose
        case working(Double)
        case failed(String)
        case done(URL, slides: Int)
    }

    let deck: Deck
    let theme: AppTheme

    init(deck: Deck, theme: AppTheme) {
        self.deck = deck
        self.theme = theme
        // Editable slides first for those who have them; PDF for everyone else.
        _format = State(initialValue: AccountStore.shared.isPaid ? .pptx : .pdf)
    }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var account = AccountStore.shared
    @ObservedObject private var store = SubscriptionStore.shared
    @State private var format: Format
    @State private var includeHidden = false
    @State private var stage: Stage = .choose
    @State private var task: Task<Void, Never>?
    @State private var run = UUID()               // the export whose result may still be shown
    @State private var shared: DeckEditorView.ExportFile?
    @State private var showPaywall = false
    #if DEBUG
    @MainActor private static var demoStarted = false
    #endif

    private var canPPTX: Bool { account.isPaid }
    // Until the App Store answers, "no subscription" isn't known yet.
    private var checking: Bool { !canPPTX && !store.entitlementsChecked }
    private var hiddenCount: Int { deck.slides.filter(\.isHidden).count }
    private var exported: Deck { includeHidden ? deck : deck.withoutHidden() }

    // Numbers of the exported slides whose diagram doesn't fit.
    private var crowded: [Int] {
        exported.slides.enumerated().compactMap { i, slide in
            guard slide.layout == .diagram else { return nil }
            let geometry = DiagramLayout.geometry(slide.diagram ?? SlideDiagram(center: slide.title), slideID: slide.id, title: slide.title, scale: CGFloat(slide.text?.body.scale ?? 1))
            return geometry.overflow ? i + 1 : nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            switch stage {
            case .choose, .failed:
                choose
            case .working(let fraction):
                working(fraction)
            case .done(let url, let slides):
                ready(url, slides: slides)
            }
        }
        .foregroundColor(MinorColor.textPrimary)
        .background(MinorColor.editorSheet.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onDisappear { cancel() }
        #if DEBUG
        // -demoExportReady: the file made at once, for the ready screen.
        .onAppear {
            guard ProcessInfo.processInfo.arguments.contains("-demoExportReady"), !Self.demoStarted else { return }
            Self.demoStarted = true
            start()
        }
        #endif
        .sheet(item: $shared) { file in ShareSheet(items: [file.url]) }
        // Over this sheet, so closing it comes back to the same format and hidden-slides choice.
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView(tier: .plus, onClose: { showPaywall = false })
        }
        // A subscription that ended meanwhile: PowerPoint is locked again, PDF stays.
        .onChange(of: canPPTX) { allowed in if !allowed && format == .pptx { format = .pdf } }
        .animation(.minorMenu, value: stage)
    }

    private var isReady: Bool {
        if case .done = stage { return true }
        return false
    }

    // Choosing: the title and the deck in the middle; the ready file: "Export" beside ×, as the design.
    private var header: some View {
        HStack(alignment: isReady ? .center : .top) {
            Button {
                cancel()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close")
            if isReady {
                Text("Export").minorFont(20, .bold, maxScale: 1.3).accessibilityAddTraits(.isHeader)
                Spacer()
            } else {
                Spacer()
                VStack(spacing: 2) {
                    Text("Export").minorFont(20, .bold, maxScale: 1.3)
                    Text(deck.title).minorFont(14, maxScale: 1.3).foregroundColor(MinorColor.textSecondary).lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
    }

    // MARK: - Choosing

    private var choose: some View {
        let count = exported.slides.count
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let first = exported.slides.first {
                        SlideCanvas(slide: first, deck: exported, index: 0)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .accessibilityHidden(true)
                            .padding(.bottom, 6)
                    }
                    Text("File Format").minorFont(14, maxScale: 1.3).foregroundColor(MinorColor.textSecondary)
                    pptxRow
                    formatRow(.pdf, title: L("PDF"), detail: L("For viewing · .pdf"), locked: false)
                    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1).padding(.vertical, 4)
                    if hiddenCount > 0 {
                        Toggle(isOn: $includeHidden) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Include Hidden Slides").minorFont(16, .medium, maxScale: 1.3)
                                Text(L("\(hiddenCount) hidden slides")).minorFont(13, maxScale: 1.3).foregroundColor(MinorColor.textSecondary)
                            }
                        }
                        .tint(MinorColor.accent)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Will Be Exported").minorFont(13, maxScale: 1.3).foregroundColor(MinorColor.textSecondary)
                        Text(countText(count)).minorFont(30, .bold, maxScale: 1.2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)))
                    .accessibilityElement(children: .combine)
                    if count == 0 {
                        notice("eye.slash", L("Every slide is hidden. Include hidden slides to export them."), color: MinorColor.textSecondary)
                    }
                    // Diagrams that don't fit are said before the file is made; nothing is cut off.
                    if !crowded.isEmpty {
                        notice("exclamationmark.triangle.fill", L("The diagram on slide \(crowded.map(String.init).joined(separator: ", ")) doesn’t fit at a readable size. Split it or choose another kind before exporting."), color: BranchColor.sun.color)
                    }
                    if case .failed(let message) = stage {
                        notice("exclamationmark.triangle", message, color: MinorColor.dangerText)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            Button(action: start) {
                Text(startTitle)
                    .minorFont(17, .semibold, maxScale: 1.3)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white))
            }
            .buttonStyle(PressScale())
            .disabled(count == 0)
            .opacity(count == 0 ? 0.45 : 1)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private var startTitle: String {
        if case .failed = stage { return L("Try Again") }
        return canPPTX ? L("Create File") : L("Create PDF")
    }

    // "7 slides" with the number in the accent colour.
    private func countText(_ count: Int) -> AttributedString {
        var text = AttributedString(L("\(count) slides"))
        if let range = text.range(of: "\(count)") { text[range].foregroundColor = MinorColor.accent }
        return text
    }

    @ViewBuilder
    private var pptxRow: some View {
        if canPPTX {
            formatRow(.pptx, title: L("PowerPoint"), detail: L("For editing · .pptx"), locked: false)
        } else if checking {
            HStack(spacing: 14) {
                ProgressView().tint(MinorColor.textSecondary).frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text("PowerPoint").minorFont(17, .medium, maxScale: 1.3)
                    Text("Checking your subscription…").minorFont(13, maxScale: 1.3).foregroundColor(MinorColor.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 64)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
            .accessibilityElement(children: .combine)
        } else {
            formatRow(.pptx, title: L("PowerPoint"), detail: L("Available with Plus"), locked: true)
        }
    }

    // A locked row opens the subscription; it is never chosen and never starts an export.
    private func formatRow(_ value: Format, title: String, detail: String, locked: Bool) -> some View {
        let selected = format == value && !locked
        return Button {
            Haptics.selection()
            if locked { return showPaywall = true }
            format = value
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    if locked {
                        Image(systemName: "lock").font(.system(size: 18))
                    } else {
                        Circle().stroke(selected ? MinorColor.accent : MinorColor.textTertiary, lineWidth: 1.5)
                        if selected { Circle().fill(MinorColor.accent).padding(5) }
                    }
                }
                .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(title).minorFont(17, .medium, maxScale: 1.3)
                        if locked {
                            Text(verbatim: "Plus")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(MinorColor.accent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .overlay(Capsule().stroke(MinorColor.accent, lineWidth: 1))
                        }
                    }
                    Text(detail).minorFont(13, maxScale: 1.3).foregroundColor(MinorColor.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 64)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? MinorColor.accent : Color.white.opacity(0.08), lineWidth: selected ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(locked ? L("PowerPoint, requires Plus") : "\(title), \(detail)")
        .accessibilityHint(locked ? Text("Opens the subscription") : Text(""))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func notice(_ icon: String, _ text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundColor(color)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .minorFont(14, maxScale: 1.3)
        .foregroundColor(color == MinorColor.dangerText ? color : MinorColor.textSecondary)
        .padding(.top, 2)
    }

    // MARK: - Making the file

    private func working(_ fraction: Double) -> some View {
        let total = max(exported.slides.count, 1)
        return VStack(spacing: 16) {
            Spacer()
            Text(format == .pdf ? L("Making the PDF…") : L("Making the PowerPoint file…"))
                .minorFont(19, .semibold, maxScale: 1.3)
            ProgressView(value: fraction)
                .tint(MinorColor.accent)
                .padding(.horizontal, 30)
            Text(L("Slide \(min(max(Int((fraction * Double(total)).rounded(.up)), 1), total)) of \(total)"))
                .minorFont(14, maxScale: 1.3)
                .foregroundColor(MinorColor.textSecondary)
                .monospacedDigit()
            Spacer()
            Button {
                cancel()
                stage = .choose
            } label: {
                Text("Cancel")
                    .minorFont(17, .medium, maxScale: 1.3)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.15), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .accessibilityElement(children: .contain)
    }

    private func ready(_ url: URL, slides: Int) -> some View {
        VStack(spacing: 12) {
            Spacer()
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "doc.text")
                    .font(.system(size: 92, weight: .ultraLight))
                    .foregroundColor(MinorColor.textSecondary)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.black, MinorColor.accent)
                    .offset(x: 14, y: 8)
            }
            .accessibilityHidden(true)
            Text("File Ready").minorFont(30, .heavy, maxScale: 1.3).accessibilityAddTraits(.isHeader).padding(.top, 10)
            Text(url.lastPathComponent)
                .minorFont(16, maxScale: 1.3)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            Text(L("\(slides) slides")).minorFont(14, maxScale: 1.3).foregroundColor(MinorColor.textSecondary)
            Text("Choose where to save or send the file.")
                .minorFont(14, maxScale: 1.3)
                .foregroundColor(MinorColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 14)
            Spacer()
            Button { shared = DeckEditorView.ExportFile(url: url) } label: {
                Label("Save or Share", systemImage: "square.and.arrow.up")
                    .minorFont(17, .semibold, maxScale: 1.3)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white))
            }
            .buttonStyle(PressScale())
            Button { stage = .choose } label: {
                Text("Another Format")
                    .minorFont(17, .medium, maxScale: 1.3)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // The slides are fixed when the file starts: later edits don't mix into it.
    private func start() {
        let deck = exported
        guard !deck.slides.isEmpty else { return }
        let format = canPPTX ? format : .pdf
        cancel()
        let current = UUID()
        run = current
        stage = .working(0)
        let hidden = includeHidden
        task = Task { @MainActor in
            do {
                let url = format == .pdf
                    ? try await DeckExport.pdf(deck) { value in if run == current { stage = .working(value) } }
                    : try await DeckExport.pptx(deck) { value in if run == current { stage = .working(value) } }
                // Cancelled meanwhile: the late file is dropped, not shown or shared.
                guard run == current, !Task.isCancelled else {
                    try? FileManager.default.removeItem(at: url)
                    return
                }
                stage = .done(url, slides: deck.slides.count)
                Haptics.success()
                UIAccessibility.post(notification: .announcement, argument: L("File Ready"))
                Telemetry.log("deck_export", ["format": format.rawValue, "slides": deck.slides.count, "hidden": hidden])
            } catch is CancellationError {
                if run == current { stage = .choose }
            } catch {
                guard run == current else { return }
                Haptics.error()
                stage = .failed(L("Couldn’t make the file. Nothing was lost — try again."))
            }
        }
    }

    private func cancel() {
        task?.cancel()
        task = nil
        run = UUID()
    }
}
