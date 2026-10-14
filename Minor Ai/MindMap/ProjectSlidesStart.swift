//
//  ProjectSlidesStart.swift
//  Minor Ai
//
//  The Slides tab before a presentation is made in this visit: what to make it from (the whole
//  map or one branch), a template, how many slides, and an explicit Create. Switching to this tab
//  never starts anything by itself. A blank presentation can start from one empty slide.
//

import SwiftUI

struct ProjectSlidesStart: View {
    let mapID: UUID
    let theme: AppTheme
    let tabs: AnyView
    var branch: UUID?              // the idea selected on the map, offered as the branch
    var onBack: () -> Void
    var onUpgrade: (_ pro: Bool) -> Void
    var onCreated: (UUID) -> Void

    @ObservedObject private var maps = MapStore.shared
    @ObservedObject private var account = AccountStore.shared
    @ObservedObject private var saved = TemplateStore.shared
    @State private var wholeMap = true
    @State private var branchID: UUID?
    @State private var template: DeckTemplate?
    @State private var slides = 8
    @State private var working = false
    @State private var error: String?
    @State private var errorIsLimit = false
    @State private var showTemplates = false
    @State private var task: Task<Void, Never>?

    private var map: MindMap? { maps.map(mapID) }

    // The look the new slides will have (the template's, or the theme matching the map).
    private var writingTheme: DeckTheme {
        if let ready = template?.deck.theme.flatMap(DeckTheme.init(rawValue:)) { return ready }
        return map.map { DeckTheme.matching($0.mapPalette) } ?? .midnight
    }

    private var maxSlides: Int {
        switch account.effectivePlan {
        case .free: return 8
        case .plus: return 20
        case .pro: return 30
        }
    }

    // The branch to use: the one picked here, or the idea selected on the map.
    private var chosenBranch: MindNode? {
        guard let map else { return nil }
        let id = branchID ?? branch
        guard let id, id != map.root.id else { return nil }
        return map.root.node(id)
    }

    var body: some View {
        VStack(spacing: 0) {
            ProjectHeader(title: map?.title ?? "", status: L("No presentations yet"), onBack: onBack) { EmptyView() }
            tabs
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    illustration
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Slides from your map")
                            .minorFont(34, .heavy, style: .largeTitle, maxScale: 1.2)
                            .fixedSize(horizontal: false, vertical: true)
                        Capsule().fill(MinorColor.accent).frame(width: 36, height: 3)
                        Text("Gather your ideas into a presentation.")
                            .minorFont(16, maxScale: 1.4)
                            .foregroundColor(MinorColor.textSecondary)
                    }
                    .padding(.bottom, 4)

                    sourceCard
                    optionRow(title: "Template", value: template?.name ?? L("Theme to match the map")) { showTemplates = true }
                    slidesRow

                    if let error {
                        HStack(spacing: 10) {
                            Text(error).minorFont(13, style: .footnote, maxScale: 1.4).frame(maxWidth: .infinity, alignment: .leading)
                            if errorIsLimit {
                                Button(account.isPaid ? "Get PRO" : "Get Minor Plus") { onUpgrade(account.isPaid) }
                                    .font(.system(size: 13, weight: .semibold))
                            }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(MinorColor.danger.opacity(0.25)))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(MinorColor.danger.opacity(0.6), lineWidth: 1))
                    }

                    VStack(spacing: 8) {
                        Button(action: working ? cancel : create) {
                            HStack(spacing: 8) {
                                if working { ProgressView().tint(.black) }
                                Text(working ? "Writing slides… Tap to stop" : "Create Presentation")
                                    .minorFont(16, .semibold, maxScale: 1.3)
                            }
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white))
                        }
                        .buttonStyle(PressScale())
                        .disabled(map == nil || (!wholeMap && chosenBranch == nil))
                        Button(action: blank) {
                            Text("Start with a Blank Slide")
                                .minorFont(15, .medium, maxScale: 1.3)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
                        }
                        .buttonStyle(PressScale())
                        .disabled(working)
                    }
                    Text("Presentations you made before open from the Library.")
                        .minorFont(12, style: .caption1, maxScale: 1.4)
                        .foregroundColor(MinorColor.textTertiary)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        // The slides being written, as when a presentation is made from New Presentation.
        .overlay {
            if working {
                WritingSlidesView(theme: writingTheme, onStop: cancel)
                    .transition(.opacity)
            }
        }
        .animation(.minorMenu, value: working)
        .foregroundColor(MinorColor.textPrimary)
        .background(theme.background.ignoresSafeArea())
        .sheet(isPresented: $showTemplates) {
            DeckTemplateChooser(theme: theme, selection: template?.id) { picked in template = picked }
        }
        .onAppear { slides = min(slides, maxSlides) }
        .onChange(of: branch) { _ in if !wholeMap { branchID = nil } }
        .onDisappear { task?.cancel() }
    }

    // Three slides joined by the map's lines.
    private var illustration: some View {
        Canvas { context, size in
            let cards = [CGRect(x: size.width / 2 - 150, y: 10, width: 112, height: 72),
                         CGRect(x: size.width / 2 - 68, y: 44, width: 112, height: 72),
                         CGRect(x: size.width / 2 + 10, y: 74, width: 134, height: 92)]
            for (i, card) in cards.enumerated() {
                context.fill(Path(roundedRect: card, cornerRadius: 8), with: .color(Color.white.opacity(0.06)))
                context.stroke(Path(roundedRect: card, cornerRadius: 8), with: .color(Color.white.opacity(0.4)), lineWidth: 1.2)
                if i == 2 {
                    // The last slide carries a picture.
                    let frame = card.insetBy(dx: 12, dy: 12)
                    context.stroke(Path(roundedRect: frame, cornerRadius: 5), with: .color(Color.white.opacity(0.35)), lineWidth: 1.2)
                    var hill = Path()
                    hill.move(to: CGPoint(x: frame.minX + 6, y: frame.maxY - 6))
                    hill.addLine(to: CGPoint(x: frame.midX - 4, y: frame.midY))
                    hill.addLine(to: CGPoint(x: frame.midX + 10, y: frame.maxY - 18))
                    hill.addLine(to: CGPoint(x: frame.maxX - 22, y: frame.midY + 4))
                    hill.addLine(to: CGPoint(x: frame.maxX - 6, y: frame.maxY - 6))
                    context.stroke(hill, with: .color(Color.white.opacity(0.45)), lineWidth: 1.4)
                    context.stroke(Path(ellipseIn: CGRect(x: frame.maxX - 26, y: frame.minY + 8, width: 10, height: 10)), with: .color(Color.white.opacity(0.45)), lineWidth: 1.4)
                } else {
                    for line in 0..<3 {
                        let y = card.minY + 16 + CGFloat(line) * 11
                        context.fill(Path(roundedRect: CGRect(x: card.minX + 12, y: y, width: line == 0 ? 54 : 74 - CGFloat(line * 12), height: 3.5), cornerRadius: 1.75), with: .color(Color.white.opacity(line == 0 ? 0.6 : 0.3)))
                    }
                }
                if i < 2 {
                    var path = Path()
                    path.move(to: CGPoint(x: card.midX, y: card.maxY))
                    path.addCurve(to: CGPoint(x: cards[i + 1].minX, y: cards[i + 1].midY), control1: CGPoint(x: card.midX, y: card.maxY + 14), control2: CGPoint(x: cards[i + 1].minX - 14, y: cards[i + 1].midY))
                    context.stroke(path, with: .color(MinorColor.accent.opacity(0.8)), lineWidth: 1.5)
                    context.fill(Path(ellipseIn: CGRect(x: cards[i + 1].minX - 3, y: cards[i + 1].midY - 3, width: 6, height: 6)), with: .color(MinorColor.accent))
                }
            }
        }
        .frame(height: 176)
        .background(DotPattern().padding(.horizontal, -16).mask(LinearGradient(colors: [.clear, .white, .white, .clear], startPoint: .top, endPoint: .bottom)))
        .accessibilityHidden(true)
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Source")
                .minorFont(13, .semibold, maxScale: 1.3)
                .foregroundColor(MinorColor.textSecondary)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)
            radio(L("Whole map"), selected: wholeMap) { wholeMap = true }
            Divider().overlay(Color.white.opacity(0.08)).padding(.leading, 48)
            HStack(spacing: 0) {
                radio(chosenBranch.map { L("Branch: \($0.title)") } ?? L("Choose a branch"), selected: !wholeMap) {
                    wholeMap = false
                }
                if let map, !map.root.children.isEmpty {
                    Menu {
                        ForEach(branchOptions(map), id: \.id) { option in
                            Button {
                                wholeMap = false
                                branchID = option.id
                            } label: { Text(option.title) }
                        }
                    } label: {
                        Text("Choose").minorFont(14, .medium, maxScale: 1.3).foregroundColor(MinorColor.accent)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                    }
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    // Main branches and their ideas, indented by level.
    private func branchOptions(_ map: MindMap) -> [(id: UUID, title: String)] {
        var result: [(UUID, String)] = []
        func walk(_ node: MindNode, depth: Int) {
            guard depth <= 2 else { return }
            if depth > 0 { result.append((node.id, String(repeating: "   ", count: depth - 1) + node.title)) }
            node.children.forEach { walk($0, depth: depth + 1) }
        }
        walk(map.root, depth: 0)
        return result.map { (id: $0.0, title: $0.1) }
    }

    private func radio(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(selected ? MinorColor.accent : MinorColor.textTertiary)
                Text(title).minorFont(15, maxScale: 1.4).lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func optionRow(title: LocalizedStringKey, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title).minorFont(16, .semibold, maxScale: 1.4)
                Spacer(minLength: 8)
                // The chosen template's cover.
                if let template, let first = template.deck.slides.first {
                    SlideCanvas(slide: first, deck: template.deck, index: 0)
                        .frame(width: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .accessibilityHidden(true)
                }
                Text(value).minorFont(13, maxScale: 1.3).foregroundColor(MinorColor.textSecondary).lineLimit(1)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundColor(MinorColor.textTertiary)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .accessibilityElement(children: .combine)
    }

    private var slidesRow: some View {
        HStack(spacing: 12) {
            Text("Length").minorFont(16, .semibold, maxScale: 1.4)
            Spacer(minLength: 8)
            if let template {
                Text(L("\(template.deck.slides.count) slides, as in the template"))
                    .minorFont(14, maxScale: 1.3)
                    .foregroundColor(MinorColor.textSecondary)
            } else {
                Stepper(value: $slides, in: 4...maxSlides) {
                    Text(L("\(slides) slides")).minorFont(14, maxScale: 1.3).foregroundColor(MinorColor.textSecondary)
                }
                .fixedSize()
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    // MARK: - Create

    private func create() {
        guard !working, let map else { return }
        guard AuthService.shared.isSignedIn || GenerationCenter.demoGenerate else { return AuthGate.shared.require(create) }
        guard AIConsent.isGiven || GenerationCenter.demoGenerate else {
            error = L("Allow AI in Settings → AI Data Sharing to create presentations.")
            errorIsLimit = false
            return
        }
        if account.isOverFreeDeckLimit {
            error = L("You’ve made this month’s free presentation. Minor Plus makes up to 20 a month.")
            errorIsLimit = true
            return
        }
        let nodeID = wholeMap ? nil : chosenBranch?.id
        if !wholeMap && nodeID == nil { return }
        let content = nodeID.flatMap { map.branch($0) } ?? map
        working = true
        error = nil
        let count = slides
        let template = template
        task = Task {
            defer {
                working = false
                task = nil
            }
            do {
                let generated = try await DeckService.shared.generate(.map(content), slides: count, quality: AccountStore.shared.allowedMapModelID, layouts: template?.layouts)
                try Task.checkCancellation()
                var deck = template?.fill(with: generated.slides, title: generated.title)
                    ?? Deck(title: generated.title, slides: generated.slides, theme: .matching(map.mapPalette), sourceMapID: mapID)
                deck.sourceMapID = mapID
                deck.sourceNodeID = nodeID
                deck.sourceRevision = content.contentFingerprint
                deck.lineage = generated.lineage
                DeckStore.shared.save(deck)
                Telemetry.log("deck_created", ["source": nodeID == nil ? "project_map" : "project_branch", "slides": deck.slides.count, "template": template?.id ?? "none"])
                account.noteDeckCreated()
                Haptics.success()
                onCreated(deck.id)
            } catch {
                guard !(Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled) else { return }
                Haptics.error()
                if case BackendError.limitReached(let kind) = error { account.noteLimitReached(kind: kind) }
                errorIsLimit = (error as? BackendError)?.suggestsUpgrade ?? false
                self.error = (error as? LocalizedError)?.errorDescription ?? L("Something went wrong. Try again.")
            }
        }
    }

    private func cancel() {
        task?.cancel()
    }

    // One empty title slide in the map's colors, to fill by hand (no AI, nothing counted).
    private func blank() {
        guard let map else { return }
        let nodeID = wholeMap ? nil : chosenBranch?.id
        let content = nodeID.flatMap { map.branch($0) } ?? map
        var deck = Deck(title: content.title, slides: [Slide(layout: .cover, title: content.title)], theme: .matching(map.mapPalette), sourceMapID: mapID)
        deck.sourceNodeID = nodeID
        deck.sourceRevision = content.contentFingerprint
        DeckStore.shared.save(deck)
        Telemetry.log("deck_created", ["source": "project_blank", "slides": 1, "template": "none"])
        onCreated(deck.id)
    }
}

// Presentation templates to start from, or none (a theme matching the map).
struct DeckTemplateChooser: View {
    let theme: AppTheme
    let selection: String?
    var onPick: (DeckTemplate?) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var saved = TemplateStore.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    choice(nil)
                    ForEach(DeckTemplates.all + saved.templates) { template in choice(template) }
                }
                .padding(20)
            }
            .background(MinorColor.sheet.ignoresSafeArea())
            .navigationTitle(Text("Template"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.foregroundColor(.white) }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }

    private func choice(_ template: DeckTemplate?) -> some View {
        let chosen = template?.id == selection
        return Button {
            Haptics.selection()
            onPick(template)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                if let template, let first = template.deck.slides.first {
                    SlideCanvas(slide: first, deck: template.deck)
                        .frame(width: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08))
                        .frame(width: 96, height: 54)
                        .overlay(Image(systemName: "paintpalette").foregroundColor(MinorColor.textSecondary))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(template?.name ?? L("Theme to match the map")).minorFont(16, .medium, maxScale: 1.3)
                    Text(template.map { L("\($0.deck.slides.count) slides") } ?? L("The AI chooses the layouts"))
                        .minorFont(13, style: .footnote, maxScale: 1.3)
                        .foregroundColor(MinorColor.textSecondary)
                }
                Spacer()
                if chosen { Image(systemName: "checkmark").foregroundColor(MinorColor.accent) }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(chosen ? Color.white.opacity(0.1) : MinorColor.fillRow))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

// The faint dot grid of the map canvas, behind the picture.
private struct DotPattern: View {
    var body: some View {
        Canvas { context, size in
            var dots = Path()
            for x in stride(from: 6.0, to: size.width, by: 18) {
                for y in stride(from: 6.0, to: size.height, by: 18) {
                    dots.addEllipse(in: CGRect(x: x - 0.9, y: y - 0.9, width: 1.8, height: 1.8))
                }
            }
            context.fill(dots, with: .color(.white.opacity(0.07)))
        }
    }
}
