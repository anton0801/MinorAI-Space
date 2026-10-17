//
//  DeckEditorView.swift
//  Minor Ai
//
//  A presentation: the slide large, a filmstrip below, and actions for the slide (edit, layout,
//  rewrite with AI, picture, notes, design, free elements) and the deck (theme, own style, brand,
//  template, present, export, change with a command).
//

import PhotosUI
import SwiftUI

struct DeckEditorView: View {
    let deckID: UUID
    let theme: AppTheme
    var onClose: () -> Void
    var onOpenMap: (UUID) -> Void = { _ in }
    var onUpgrade: (_ pro: Bool) -> Void = { _ in }
    // Inside a project: the Map / Slides / Chat switch under the header; deleting the presentation
    // goes back to the Slides start instead of closing the project; the slide on screen is the
    // chat's context.
    var tabs: AnyView? = nil
    var onDeleted: (() -> Void)? = nil
    var onSlideChange: (UUID?) -> Void = { _ in }

    @ObservedObject private var store = DeckStore.shared
    @ObservedObject private var sync = MapSync.shared
    @ObservedObject private var network = NetworkMonitor.shared
    @State private var updatePreview: UpdatePreview?
    @State private var mapUpdate: MapUpdate?
    @State private var linking = false
    @State private var sourceMissing = false
    @State private var index = 0
    // Undo and redo: the presentation as it was, with what was selected on its slide then.
    @State private var history: [Snapshot] = []
    @State private var future: [Snapshot] = []
    @State private var editingDiagram = false
    @State private var diagramSelection: UUID?

    struct Snapshot {
        let deck: Deck
        let selection: UUID?
    }
    @State private var command = ""
    @State private var isApplying = false
    @State private var rewriting: Set<UUID> = []
    @State private var drawing: Set<UUID> = []
    @State private var banner: String?
    @State private var bannerIsLimit = false
    @State private var toast: String?
    @State private var showInspector = false
    @State private var showLayouts = false
    @State private var showRewrite = false
    @State private var showNotes = false
    @State private var showThemes = false
    @State private var showAddSlide = false
    @State private var presenting = false
    @State private var renaming = false
    @State private var renameText = ""
    @State private var confirmDelete = false
    @State private var showExport = false
    @State private var showOrganizer = false
    // Text the layout drew, selected by tapping it on the slide (see SlidePart).
    @State private var selectedPart: String?
    @State private var probe = SlideLayoutProbe()
    @State private var showTextStyle = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotos = false
    // Design.
    @ObservedObject private var account = AccountStore.shared
    @State private var editingElements = false
    @State private var panelTab: PanelTab = .design
    @State private var selectedElement: UUID?
    @State private var inspecting: SlideElement?
    @State private var showLookEditor = false
    @State private var lookStart: DeckLook?
    @State private var lookForSlide = false
    @State private var showBrand = false
    @State private var showSlideDesign = false
    @State private var designPrompt: DesignPromptMode?
    @State private var savingTemplate = false
    @State private var templateName = ""
    @State private var elementPhotoItem: PhotosPickerItem?
    @State private var showElementPhotos = false
    @FocusState private var commandFocused: Bool

    // The bottom panel's tabs: the look, the words, the slide's own elements.
    enum PanelTab: Hashable { case design, text, elements }

    struct DesignPromptMode: Identifiable {
        let mode: DesignPromptSheet.Mode
        var id: String { mode == .style ? "style" : "elements" }
    }

    private var isPaid: Bool { account.isPaid }

    private var deck: Deck? { store.deck(deckID) }
    private var slide: Slide? {
        guard let deck, deck.slides.indices.contains(index) else { return nil }
        return deck.slides[index]
    }

    // The screen and its many sheets are built in groups, each behind AnyView. As one chain of ~45
    // modifiers the body was ~26 KB, and SwiftUI walks such a chain level by level on the main
    // thread's stack: opening a presentation overflowed the iPhone's 1 MB stack (the 3.0.0 crash).
    var body: some View {
        let screen = AnyView(screenContent)
        let design = AnyView(designSheets(screen))
        let look = AnyView(lookSheets(design))
        let files = AnyView(fileSheets(look))
        let text = AnyView(textSheets(files))
        return mapSheets(text)
    }

    // The header, stage, filmstrip and panel go in behind AnyView too, for the same reason.
    private var screenContent: some View {
        ZStack {
            theme.background.ignoresSafeArea()
            if let deck {
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        AnyView(header(deck))
                        if let tabs { tabs }
                    }
                    AnyView(stage(deck)).padding(.top, 8)
                    fitNotice.padding(.top, 10)
                    AnyView(slideNavigation(deck))
                    AnyView(filmstrip(deck))
                    if let banner { bannerView(banner).padding(.top, 8) }
                    AnyView(panel(deck)).padding(.top, 10)
                }
                .overlay(alignment: .bottom) {
                    if let toast {
                        Text(toast)
                            .font(.system(size: 15))
                            .padding(.horizontal, 16)
                            .frame(height: 40)
                            .background(Capsule().fill(theme.chatRectangle))
                            .overlay(Capsule().stroke(theme.chatStroke, lineWidth: 1))
                            .padding(.bottom, 90)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
            } else {
                Text("This presentation was deleted.")
                    .foregroundColor(MinorColor.textSecondary)
                    .onAppear { (onDeleted ?? onClose)() }
            }
        }
        .foregroundColor(MinorColor.textPrimary)
        .animation(.minorMenu, value: toast)
        .animation(.minorMenu, value: banner)
    }

    // Diagram, slide text, layouts, rewriting, notes and the deck's style.
    private func designSheets(_ content: AnyView) -> some View {
        content
        .sheet(isPresented: $editingDiagram) {
            if let slide, slide.layout == .diagram {
                DiagramPanel(diagram: (slide.diagram ?? SlideDiagram(center: slide.title)).structured(slideID: slide.id),
                             selection: $diagramSelection, onChange: { commitDiagram($0) }, onDone: { editingDiagram = false })
                    .presentationDetents([.fraction(0.52), .large])
                    .presentationDragIndicator(.visible)
                    .modifier(StageStaysUsable())
            }
        }
        .sheet(isPresented: $showInspector) {
            if let slide, let deck { SlideInspector(slide: slide, deck: deck, theme: theme) { updated in replaceSlide(updated) } }
        }
        .sheet(isPresented: $showLayouts) {
            if let slide, let deck {
                LayoutPicker(slide: slide, deck: deck, theme: theme) { layout in
                    mutate { $0.slides[index] = $0.slides[index].converted(to: layout) }
                }
                .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $showRewrite) {
            RewriteSheet(theme: theme) { instruction in rewrite(instruction) }
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showNotes) {
            if let slide { NotesSheet(notes: slide.notes, theme: theme) { notes in mutate(undoable: false) { $0.slides[index].notes = notes } } }
        }
        .sheet(isPresented: $showThemes) {
            if let deck {
                ThemePicker(deck: deck, slideIndex: index, theme: theme, isPaid: isPaid, onPick: { choice, forSlide in
                    if forSlide {
                        guard isPaid else { return onUpgrade(false) }
                        mutate { deck in
                            guard deck.slides.indices.contains(index) else { return }
                            switch choice {
                            case .builtIn(let ready): deck.slides[index].theme = ready.rawValue; deck.slides[index].look = nil
                            case .look(let look): deck.slides[index].look = look; deck.slides[index].theme = nil
                            }
                        }
                    } else {
                        switch choice {
                        case .builtIn(let ready): mutate { $0.theme = ready.rawValue; $0.look = nil }
                        case .look(let look): mutate { $0.look = look }
                        }
                    }
                }, onResetSlide: {
                    mutate { deck in
                        guard deck.slides.indices.contains(index) else { return }
                        deck.slides[index].look = nil
                        deck.slides[index].theme = nil
                    }
                }, onCreate: { forSlide in
                    showThemes = false
                    plus { after { lookStart = nil; lookForSlide = forSlide; showLookEditor = true } }
                }, onDescribe: {
                    showThemes = false
                    plus { after { designPrompt = DesignPromptMode(mode: .style) } }
                }, onUpgrade: {
                    showThemes = false
                    after { onUpgrade(false) }
                })
                .presentationDetents([.height(EditorSheetHeight.deckStyle), .large])
            }
        }
    }

    // Own style, brand, slide design, AI design prompts and the element inspector.
    private func lookSheets(_ content: AnyView) -> some View {
        content
        .sheet(isPresented: $showLookEditor) {
            if let deck {
                LookEditor(deck: deck, slideIndex: index, theme: theme, start: lookStart, forSlide: lookForSlide) { look in
                    if lookForSlide {
                        mutate { deck in
                            guard deck.slides.indices.contains(index) else { return }
                            deck.slides[index].look = look
                            deck.slides[index].theme = nil
                        }
                    } else {
                        mutate { $0.look = look }
                    }
                }
            }
        }
        .sheet(isPresented: $showBrand) {
            if let deck { BrandSheet(deck: deck, theme: theme) { brand in mutate { $0.brand = brand } } }
        }
        .sheet(isPresented: $showSlideDesign) {
            if let deck, deck.slides.indices.contains(index) {
                SlideDesignSheet(deck: deck, index: index, theme: theme, isPaid: isPaid, onSave: { updated, forAll in
                    mutate { deck in
                        guard let i = deck.slides.firstIndex(where: { $0.id == updated.id }) else { return }
                        deck.slides[i] = updated
                        if forAll, let transition = updated.transition {
                            deck.transition = transition
                            for j in deck.slides.indices { deck.slides[j].transition = nil }
                        }
                    }
                }, onUpgrade: {
                    showSlideDesign = false
                    after { onUpgrade(false) }
                })
            }
        }
        .sheet(item: $designPrompt) { item in
            DesignPromptSheet(mode: item.mode, theme: theme) { prompt in
                item.mode == .style ? describeStyle(prompt) : addElements(prompt)
            }
            .presentationDetents([.medium])
        }
        .sheet(item: $inspecting) { element in
            if let deck, deck.slides.indices.contains(index) {
                ElementInspector(element: element, style: deck.style(for: deck.slides[index]), theme: theme, onSave: { updated in
                    updateElement(updated.id) { $0 = updated }
                }, onDelete: { deleteElement(element.id) })
            }
        }
    }

    // Pictures, templates, new slides, export, the organizer and presenting.
    private func fileSheets(_ content: AnyView) -> some View {
        content
        .photosPicker(isPresented: $showElementPhotos, selection: $elementPhotoItem, matching: .images)
        .onChange(of: elementPhotoItem) { item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let picture = MapStore.shared.storeImage(data, isAI: false) {
                    var element = SlideElement.new(.image)
                    element.image = picture.id
                    // Fits inside the slide, so a tall screenshot keeps its handles on screen.
                    let aspect = max(picture.aspect, 0.05)
                    element.w = min(480, 600 / aspect)
                    element.h = element.w * aspect
                    element.x = (1280 - element.w) / 2
                    element.y = (720 - element.h) / 2
                    insert(element)
                }
                elementPhotoItem = nil
            }
        }
        .alert("Save as Template", isPresented: $savingTemplate) {
            TextField("Template name", text: $templateName)
            Button("Save") {
                guard let deck else { return }
                let name = templateName.trimmingCharacters(in: .whitespacesAndNewlines)
                TemplateStore.shared.save(deck, name: name.isEmpty ? deck.title : String(name.prefix(60)))
                toast(L("Saved to your templates"))
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("New presentations can start from it, with this look and these slides.")
        }
        .sheet(isPresented: $showAddSlide) {
            if let deck {
                LayoutPicker(slide: nil, deck: deck, theme: theme) { layout in addSlide(layout) }
                    .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $showExport) {
            if let deck {
                DeckExportSheet(deck: deck, theme: theme)
                    .presentationDetents([.large])
            }
        }
        .fullScreenCover(isPresented: $showOrganizer) {
            DeckOrganizerView(
                deckID: deckID,
                theme: theme,
                current: $index,
                onChange: { undoable, change in mutate(undoable: undoable, change) },
                canUndo: !history.isEmpty,
                onUndo: undo,
                onAddSlide: { after { showAddSlide = true } }
            )
        }
        // Hidden slides are skipped; a hidden slide on screen starts the show at the next one.
        .fullScreenCover(isPresented: $presenting) {
            if let deck {
                DeckPresenterView(deck: deck.withoutHidden(), start: deck.shownIndex(for: index)) { id in
                    // Back in the editor at the slide the show ended on.
                    if let shown = self.deck?.slides.firstIndex(where: { $0.id == id }) { index = shown }
                }
            }
        }
    }

    // Selection follows the slide; the selected text's panel.
    private func textSheets(_ content: AnyView) -> some View {
        content
        .onChange(of: index) { _ in
            selectedElement = nil
            selectedPart = nil
            probe = SlideLayoutProbe()
            // Another slide: the diagram's panel follows only to another diagram, without a selection.
            diagramSelection = nil
            if slide?.layout != .diagram { editingDiagram = false }
        }
        // Edited text lands somewhere else: measure again.
        .onChange(of: slide) { _ in probe = SlideLayoutProbe() }
        .onChange(of: editingElements) { editing in
            if editing {
                selectedPart = nil
                panelTab = .elements
            } else if panelTab == .elements {
                panelTab = .design
            }
        }
        // The selected text's panel; closing it ends the selection.
        .sheet(isPresented: $showTextStyle, onDismiss: { withAnimation(.minorMenu) { selectedPart = nil } }) {
            if let slide, let deck, let key = selectedPart {
                SlideTextSheet(
                    slide: slide,
                    key: key,
                    style: deck.style(for: slide),
                    theme: theme,
                    onChange: { role, change in
                        mutate { deck in
                            guard deck.slides.indices.contains(index) else { return }
                            var text = deck.slides[index].text ?? SlideTextStyle()
                            if role == .title { change(&text.title) } else { change(&text.body) }
                            deck.slides[index].text = text.isDefault ? nil : text
                        }
                    },
                    onEditText: { after { showInspector = true } },
                    onRewrite: { after { showRewrite = true } },
                    onFonts: {
                        showTextStyle = false
                        after { showThemes = true }
                    }
                )
                .presentationDetents([.height(EditorSheetHeight.slideText), .large])
                .mapVisibleBehindSheet()
            }
        }
        // Slides can change from elsewhere (sync, the chat's AI edit): keep the index valid.
        .onChange(of: deck?.slides.count ?? 0) { count in
            if index >= count { index = max(count - 1, 0) }
        }
        #if DEBUG
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            if let flag = args.firstIndex(of: "-campaignSlide"), args.indices.contains(flag + 1),
               let selected = Int(args[flag + 1]), let slides = deck?.slides, slides.indices.contains(selected) {
                index = selected
            }
            if args.contains("-demoThemes") { showThemes = true }
            if args.contains("-demoOwnStyle") { showLookEditor = true }
            if args.contains("-demoBrand") { showBrand = true }
            if args.contains("-demoElements") { index = 3; editingElements = true; selectedElement = deck?.slides[3].elements.first?.id }
            if args.contains("-demoOrganizer") { showOrganizer = true }
            if args.contains("-demoLayoutPicker") { index = 2; showLayouts = true }
            if args.contains("-demoTextSelect") { index = 2; DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { selectedPart = "b.text.1"; showTextStyle = true } }
            if args.contains("-demoTextStyle") { selectedPart = "title"; DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showTextStyle = true } }
            if args.contains("-demoExportSheet") { showExport = true }
            // -demoPresentDeck: presenting from the third slide (-demoPresenterView: the presenter's view).
            if args.contains("-demoPresentDeck") { index = 2; DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { presenting = true } }
            if args.contains("-demoThemeScope") { showThemes = true }
            if args.contains("-demoOverflow") { index = 7 }
            if args.contains("-demoDiagrams") { index = UserDefaults.standard.integer(forKey: "demoDeckSlide") }
            if args.contains("-demoMerge") { DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { updateFromMap() } }
            // -demoDiagramPanel: the diagram's panel with its third box selected.
            if args.contains("-demoDiagramPanel") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    guard let slide else { return }
                    let items = (slide.diagram ?? SlideDiagram()).structured(slideID: slide.id).allItems
                    editDiagram(select: items.count > 2 ? items[2].id : items.first?.id)
                }
            }
        }
        #endif
    }

    // Cover picture, rename, delete, and updating the slides from their map.
    private func mapSheets(_ content: AnyView) -> some View {
        content
        .photosPicker(isPresented: $showPhotos, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { item in
            guard let item, let id = slide?.id else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let picture = MapStore.shared.storeImage(data, isAI: false) {
                    mutate { deck in
                        guard let i = deck.slides.firstIndex(where: { $0.id == id }) else { return }
                        deck.slides[i].image = picture
                        if deck.slides[i].layout != .imageText { deck.slides[i] = deck.slides[i].converted(to: .imageText) }
                    }
                }
                photoItem = nil
            }
        }
        .alert("Rename", isPresented: $renaming) {
            TextField("Presentation title", text: $renameText)
            Button("Save") {
                let text = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { mutate { $0.title = String(text.prefix(90)) } }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this presentation? This can’t be undone.", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                store.delete(deckID)
                (onDeleted ?? onClose)()
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $mapUpdate) { update in
            if let deck {
                MapMergeSheet(update: update, deck: deck, theme: theme,
                              onApply: { applyMapUpdate($0) },
                              onRefresh: { refreshedUpdate() },
                              onCopy: { saveMapUpdateAsCopy($0) })
                    .presentationDetents([.large])
            }
        }
        .sheet(isPresented: $linking) {
            if let deck, let map = deck.sourceContent {
                MapLinkSheet(deck: deck, map: map, theme: theme, onLink: { lineage in
                    mutate { $0.lineage = lineage; $0.sourceRevision = map.contentFingerprint }
                    toast(L("Slides linked to the map"))
                }, onCopy: { regenerateFromMap() })
            }
        }
        .sheet(item: $updatePreview) { preview in
            if let deck {
                UpdateFromMapSheet(deck: deck, preview: preview, theme: theme, onCopy: { saveUpdateAsCopy(preview) }, onReplace: { replaceWithUpdate(preview) })
            }
        }
        .alert("The source isn’t available", isPresented: $sourceMissing) {
            if deck?.sourceNodeID != nil, let mapID = deck?.sourceMapID, MapStore.shared.map(mapID) != nil {
                Button("Use the Whole Map") {
                    mutate(undoable: false) { $0.sourceNodeID = nil }
                    updateFromMap()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deck?.sourceNodeID != nil
                 ? "The branch these slides were made from was deleted. You can update them from the whole map instead."
                 : "The map these slides were made from was deleted.")
        }
        .onChange(of: index) { _ in onSlideChange(slide?.id) }
        .onAppear { onSlideChange(slide?.id) }
    }

    // MARK: - Header and stage

    // Not saved (a write failed), syncing, offline, saved; and when the source map has changed since.
    private func saveState(_ deck: Deck) -> (text: String, error: Bool) {
        let count = L("\(deck.slides.count) slides")
        if store.failedSaves.contains(deck.id) { return ("\(count) · \(L("Not saved"))", true) }
        if MapSync.isEnabled && AuthService.shared.isSignedIn {
            if !network.isOnline { return ("\(count) · \(L("Saved on this iPhone · offline"))", false) }
            if sync.isSyncing { return ("\(count) · \(L("Syncing…"))", false) }
        }
        if deck.sourceChanged { return ("\(count) · \(L("Map changed since"))", false) }
        return ("\(count) · \(L("Saved"))", false)
    }

    private func header(_ deck: Deck) -> some View {
        HStack(spacing: 0) {
            Button(action: onClose) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Back")
            if !history.isEmpty {
                Button(action: undo) {
                    Image(systemName: "arrow.uturn.backward").font(.system(size: 17)).frame(width: 40, height: 44)
                }
                .accessibilityLabel("Undo")
            }
            if !future.isEmpty {
                Button(action: redo) {
                    Image(systemName: "arrow.uturn.forward").font(.system(size: 17)).frame(width: 40, height: 44)
                }
                .accessibilityLabel("Redo")
            }
            let state = saveState(deck)
            VStack(alignment: .leading, spacing: 1) {
                Text(deck.title).minorFont(17, .semibold, maxScale: 1.25).lineLimit(1)
                Text(state.text)
                    .minorFont(12, style: .caption1, maxScale: 1.25)
                    .foregroundColor(state.error ? MinorColor.dangerText : MinorColor.textTertiary)
                    .lineLimit(1)
            }
            .padding(.leading, 2)
            .contentShape(Rectangle())
            .onTapGesture {
                renameText = deck.title
                renaming = true
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(Text("Renames the presentation"))
            Spacer(minLength: 8)
            Button {
                guard deck.slides.contains(where: { !$0.isHidden }) else { return toast(L("Every slide is hidden. Show one in All Slides.")) }
                Telemetry.log("deck_present", ["slides": deck.slides.count])
                presenting = true
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.black)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(MinorColor.sendFill))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Present")
            Button { showExport = true } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(theme.chatRectangle))
                    .overlay(Circle().stroke(theme.chatStroke, lineWidth: 1))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Export")
            Menu {
                Button { showOrganizer = true } label: { Label("All Slides", systemImage: "square.grid.2x2") }
                Button { showThemes = true } label: { Label("Theme", systemImage: "paintpalette") }
                Button { plus { showBrand = true } } label: { Label(isPaid ? "Brand" : "Brand · Plus", systemImage: "seal") }
                Button { plus { templateName = deck.title; savingTemplate = true } } label: { Label(isPaid ? "Save as Template" : "Save as Template · Plus", systemImage: "square.on.square") }
                Button { renameText = deck.title; renaming = true } label: { Label("Rename", systemImage: "pencil") }
                if let map = deck.sourceMapID, MapStore.shared.map(map) != nil {
                    Section {
                        if tabs == nil {
                            Button { onOpenMap(map) } label: { Label("Open Source Map", systemImage: "point.3.connected.trianglepath.dotted") }
                        }
                        Button { updateFromMap() } label: {
                            Label(deck.sourceChanged ? L("Update from Map · Changes") : L("Update from Map"), systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                }
                Button(role: .destructive) { confirmDelete = true } label: { Label("Delete Presentation", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(theme.chatRectangle))
                    .overlay(Circle().stroke(theme.chatStroke, lineWidth: 1))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("More")
        }
        .foregroundColor(MinorColor.textPrimary)
        .padding(.leading, 4)
        .padding(.trailing, 6)
        .frame(minHeight: 52)
        .disabled(isApplying)
    }

    @ViewBuilder
    private func stage(_ deck: Deck) -> some View {
        if editingDiagram, deck.slides.indices.contains(index), deck.slides[index].layout == .diagram {
            DiagramStage(slide: deck.slides[index], deck: deck, index: index, selection: $diagramSelection) { commitDiagram($0) }
                .disabled(isApplying)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(MinorColor.accent.opacity(0.7), lineWidth: 1.5))
                .padding(.horizontal, 16)
                .frame(height: (UIScreen.main.bounds.width - 32) * 9 / 16 + 8)
        } else if editingElements, deck.slides.indices.contains(index) {
            SlideElementEditor(deck: deck, index: index, selection: $selectedElement, onChange: { elements in
                mutate { $0.slides[index].elements = elements }
            }, onEdit: { inspecting = $0 })
            .disabled(isApplying)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(MinorColor.accent.opacity(0.7), lineWidth: 1.5))
            .padding(.horizontal, 16)
            .frame(height: (UIScreen.main.bounds.width - 32) * 9 / 16 + 8)
        } else {
            AnyView(pager(deck))
        }
    }

    private func pager(_ deck: Deck) -> some View {
        TabView(selection: $index) {
            ForEach(Array(deck.slides.enumerated()), id: \.element.id) { i, slide in
                SlideCanvas(slide: slide, deck: deck, index: i, probe: i == index ? probe : nil, selectedPart: i == index ? selectedPart : nil)
                    // A tap selects the text under the finger; a second tap on it edits it.
                    .onTapGesture(coordinateSpace: .local) { location in tapSlide(at: location) }
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.chatStroke, lineWidth: 1))
                    .overlay {
                        if rewriting.contains(slide.id) || drawing.contains(slide.id) || isApplying {
                            ZStack {
                                RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.35))
                                Sweep().clipShape(RoundedRectangle(cornerRadius: 14))
                                ProgressView().tint(.white)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .tag(i)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(L("Edits the slide"))
                    .accessibilityAction { showInspector = true }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: (UIScreen.main.bounds.width - 32) * 9 / 16 + 8)
    }

    // Which slide is on screen (it opens All Slides) and the previous and next ones.
    private func slideNavigation(_ deck: Deck) -> some View {
        HStack(spacing: 0) {
            Button { showOrganizer = true } label: {
                Text("\(index + 1) / \(deck.slides.count)")
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundColor(MinorColor.textSecondary)
                    .frame(minWidth: 44, minHeight: 34, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("All Slides")
            .accessibilityValue(Text(L("Slide \(index + 1) of \(deck.slides.count)")))
            Spacer()
            Button { withAnimation(.minorMenu) { index = max(index - 1, 0) } } label: {
                Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold)).frame(width: 40, height: 34)
            }
            .buttonStyle(.plain)
            .disabled(index == 0)
            .opacity(index == 0 ? 0.35 : 1)
            .accessibilityLabel("Previous Slide")
            Button { withAnimation(.minorMenu) { index = min(index + 1, deck.slides.count - 1) } } label: {
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).frame(width: 40, height: 34)
            }
            .buttonStyle(.plain)
            .disabled(index >= deck.slides.count - 1)
            .opacity(index >= deck.slides.count - 1 ? 0.35 : 1)
            .accessibilityLabel("Next Slide")
        }
        .foregroundColor(MinorColor.textPrimary)
        .padding(.leading, 18)
        .padding(.trailing, 6)
        .padding(.top, 2)
    }

    // Slide units to points on the stage.
    private var stageScale: CGFloat { (UIScreen.main.bounds.width - 32) / SlideView.size.width }

    private func tapSlide(at location: CGPoint) {
        let point = CGPoint(x: location.x / stageScale, y: location.y / stageScale)
        // A diagram: a tap on a box (or anywhere but the title) opens the diagram's panel.
        if let slide, slide.layout == .diagram, SlidePart.hit(point, in: probe.frames) != "title" {
            let geometry = DiagramLayout.geometry(slide.diagram ?? SlideDiagram(center: slide.title), slideID: slide.id, title: slide.title, scale: CGFloat(slide.text?.body.scale ?? 1))
            Haptics.selection()
            editDiagram(select: geometry.boxes.first { $0.frame.insetBy(dx: -6, dy: -6).contains(point) }?.id)
            return
        }
        // A tap on text selects it and opens its panel; a second tap edits the words.
        if let key = SlidePart.hit(point, in: probe.frames) {
            if key == selectedPart {
                showInspector = true
            } else {
                Haptics.selection()
                withAnimation(.minorMenu) { selectedPart = key }
                showTextStyle = true
            }
        } else if selectedPart != nil {
            withAnimation(.minorMenu) { selectedPart = nil }
        } else {
            showInspector = true
        }
    }

    // The layout can't show everything on the slide, or a Big Number has no number: said plainly,
    // with the way to fix it.
    @ViewBuilder
    private var fitNotice: some View {
        if let slide, !editingElements {
            if slide.layout == .diagram, DiagramLayout.geometry(slide.diagram ?? SlideDiagram(center: slide.title), slideID: slide.id, title: slide.title, scale: CGFloat(slide.text?.body.scale ?? 1)).overflow {
                noticeRow(L("The diagram doesn’t fit the slide at a readable size."), action: L("Edit Diagram")) { editDiagram() }
            } else if let overflow = slide.overflow {
                noticeRow(L("This layout shows \(overflow.shown) of \(overflow.total)."), action: L("Split into Slides")) { splitSlide() }
            } else if slide.layout == .bigNumber, (slide.stat?.value ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                noticeRow(L("This slide needs a number."), action: L("Add Number")) { showInspector = true }
            }
        }
    }

    private func noticeRow(_ text: String, action: String, perform: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundColor(BranchColor.sun.color)
            Text(text)
                .minorFont(13, maxScale: 1.3)
                .foregroundColor(MinorColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: perform) {
                Text(action)
                    .minorFont(13, .semibold, maxScale: 1.3)
                    .foregroundColor(.black)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 32)
                    .background(Capsule().fill(BranchColor.sun.color))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 12).fill(BranchColor.sun.color.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(BranchColor.sun.color.opacity(0.35), lineWidth: 1))
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }

    // What doesn't fit goes to new slides right after, in the same layout.
    private func splitSlide() {
        guard let slide, let i = deck?.slides.firstIndex(where: { $0.id == slide.id }) else { return }
        let parts = slide.split()
        guard parts.count > 1 else { return }
        mutate { $0.slides.replaceSubrange(i...i, with: parts) }
        toast(L("Split into \(parts.count) slides"))
        Haptics.success()
    }

    // The bottom panel: Design, Text or Elements, the speaker notes and the AI field.
    private func panel(_ deck: Deck) -> some View {
        VStack(spacing: 10) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    MinorSegments(items: [
                        (PanelTab.design, "Design", "paintbrush.pointed"),
                        (.text, "Text", "textformat"),
                        (.elements, "Elements", "square.on.circle"),
                    ], selection: Binding(get: { panelTab }, set: { value in
                        selectedElement = nil
                        panelTab = value
                        withAnimation(.minorMenu) { editingElements = value == .elements }
                    }), height: 32)
                    switch panelTab {
                    case .design: AnyView(designPanel(deck))
                    case .text: AnyView(textPanel)
                    case .elements: AnyView(elementBar).padding(.horizontal, -12)
                    }
                    AnyView(notesRow)
                }
                .padding(.top, 12)
            }
            .disabled(isApplying)
            AnyView(composer)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(MinorColor.editorSheet)
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 1))
                .padding(.bottom, -60)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // Design: the slide's layout, background and picture, then the presentation's theme as cards
    // that show this slide.
    private func designPanel(_ deck: Deck) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if slide?.layout == .diagram {
                        action("point.3.connected.trianglepath.dotted", L("Edit Diagram")) { editDiagram() }
                    }
                    action("square.grid.2x2", L("Slide Layout")) { showLayouts = true }
                    action("wand.and.stars", L("Background and Motion")) { showSlideDesign = true }
                    Menu {
                        Button { drawImage() } label: { Label("Create Image with AI", systemImage: "wand.and.stars") }
                        Button { showPhotos = true } label: { Label("Add Photo", systemImage: "photo") }
                        if slide?.image != nil {
                            Button(role: .destructive) { mutate { $0.slides[index].image = nil } } label: { Label("Remove Image", systemImage: "photo.badge.minus") }
                        }
                    } label: { actionLabel("photo", L("Picture")) }
                    action("paintpalette", L("All Styles")) { showThemes = true }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 1)
            }
            .padding(.horizontal, -12)
            AnyView(themeCards(deck))
        }
    }

    // The ready-made themes and the person's own, each drawn with the slide on screen.
    private func themeCards(_ deck: Deck) -> some View {
        let sample = slide ?? Slide(layout: .cover, title: deck.title)
        let choices: [(id: String, name: String, choice: ThemeChoice)] =
            LookStore.shared.looks.map { ($0.id.uuidString, $0.name, ThemeChoice.look($0)) }
            + DeckTheme.allCases.map { ($0.rawValue, $0.name, ThemeChoice.builtIn($0)) }
        let width = (UIScreen.main.bounds.width - 24 - 16) / 3
        return ScrollViewReader { reader in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(choices, id: \.id) { item in
                        let chosen: Bool = {
                            switch item.choice {
                            case .builtIn(let ready): return deck.look == nil && deck.deckTheme == ready
                            case .look(let look): return deck.look?.id == look.id
                            }
                        }()
                        let (previewDeck, shown) = themePreview(item.choice, deck: deck, sample: sample)
                        Button {
                            Haptics.selection()
                            switch item.choice {
                            case .builtIn(let ready): mutate { $0.theme = ready.rawValue; $0.look = nil }
                            case .look(let look): mutate { $0.look = look }
                            }
                        } label: {
                            VStack(spacing: 5) {
                                SlideCanvas(slide: shown, deck: previewDeck, index: index)
                                    .frame(width: width)
                                    .clipShape(RoundedRectangle(cornerRadius: 7))
                                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(chosen ? MinorColor.accent : Color.white.opacity(0.1), lineWidth: chosen ? 2 : 1))
                                Text(item.name)
                                    .font(.system(size: 12, weight: chosen ? .semibold : .regular))
                                    .foregroundColor(chosen ? MinorColor.textPrimary : MinorColor.textSecondary)
                                    .lineLimit(1)
                                    .frame(width: width)
                            }
                            .padding(.vertical, 1)
                        }
                        .buttonStyle(.plain)
                        .id(item.id)
                        .accessibilityLabel(L("Theme \(item.name)"))
                        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
                    }
                }
                .padding(.horizontal, 12)
            }
            .padding(.horizontal, -12)
            .onAppear {
                let current = deck.look?.id.uuidString ?? deck.deckTheme.rawValue
                reader.scrollTo(current, anchor: .center)
            }
        }
    }

    // The deck and slide on screen drawn with a theme for the whole presentation.
    private func themePreview(_ choice: ThemeChoice, deck: Deck, sample: Slide) -> (Deck, Slide) {
        var copy = deck
        var shown = sample
        switch choice {
        case .builtIn(let ready):
            copy.theme = ready.rawValue
            copy.look = nil
        case .look(let look):
            copy.look = look
        }
        shown.look = nil
        shown.theme = nil
        return (copy, shown)
    }

    // Text: the words and how they're said; the look of a text opens when it is tapped on the slide.
    private var textPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                action("pencil", L("Edit Text")) { showInspector = true }
                action("sparkles", L("Rewrite with AI")) { showRewrite = true }
            }
            Label("Tap text on the slide to change its font, size and color.", systemImage: "hand.tap")
                .font(.system(size: 12))
                .foregroundColor(MinorColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // What the speaker says on this slide, one line of it; tap to edit.
    private var notesRow: some View {
        Button { showNotes = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "doc.text").font(.system(size: 16)).foregroundColor(MinorColor.textSecondary).frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Speaker Notes").font(.system(size: 14, weight: .medium)).foregroundColor(MinorColor.textPrimary)
                    Text(slide?.notes.isEmpty == false ? slide!.notes : L("Add what you want to say on this slide."))
                        .font(.system(size: 12))
                        .foregroundColor(MinorColor.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundColor(MinorColor.textTertiary)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func action(_ icon: String, _ title: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) { actionLabel(icon, title) }.buttonStyle(.plain)
    }

    // A chip: icon and title in a filled capsule with an inside outline; paid ones carry a "Plus"
    // tag inside, so nothing sticks out of the row.
    private func actionLabel(_ icon: String, _ title: String, plus: Bool = false, destructive: Bool = false) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold))
            Text(title).font(.system(size: 14, weight: .medium)).lineLimit(1)
            if plus { PlusBadge() }
        }
        .foregroundColor(destructive ? MinorColor.dangerText : MinorColor.textPrimary)
        .padding(.leading, 12)
        .padding(.trailing, plus ? 6 : 13)
        .padding(.vertical, 8)
        .frame(minHeight: 36)
        .background(Capsule().fill(theme.chatRectangle))
        .overlay(Capsule().strokeBorder(theme.chatStroke, lineWidth: 1))
        .contentShape(Capsule())
    }

    private func filmstrip(_ deck: Deck) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 8) {
                    ForEach(Array(deck.slides.enumerated()), id: \.element.id) { i, slide in
                        Button {
                            withAnimation(.minorMenu) { index = i }
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                SlideCanvas(slide: slide, deck: deck, index: i)
                                    .frame(width: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .opacity(slide.isHidden ? 0.4 : 1)
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(i == index ? MinorColor.accent : theme.chatStroke, lineWidth: i == index ? 2 : 1))
                                    .overlay(alignment: .topTrailing) {
                                        if slide.isHidden {
                                            Image(systemName: "eye.slash.fill")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundColor(.white)
                                                .padding(4)
                                                .background(Circle().fill(Color.black.opacity(0.6)))
                                                .padding(4)
                                        }
                                    }
                                Text("\(i + 1)")
                                    .font(.system(size: 11).monospacedDigit())
                                    .foregroundColor(i == index ? MinorColor.textPrimary : MinorColor.textTertiary)
                                    .padding(.leading, 3)
                            }
                        }
                        .buttonStyle(.plain)
                        .id(slide.id)
                        .contextMenu {
                            Button { duplicateSlide(i) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                            if i > 0 { Button { moveSlide(i, by: -1) } label: { Label("Move Left", systemImage: "arrow.left") } }
                            if i < deck.slides.count - 1 { Button { moveSlide(i, by: 1) } label: { Label("Move Right", systemImage: "arrow.right") } }
                            Button { toggleHidden(i) } label: {
                                Label(slide.isHidden ? "Show Slide" : "Hide Slide", systemImage: slide.isHidden ? "eye" : "eye.slash")
                            }
                            .disabled(!slide.isHidden && deck.slides.filter { !$0.isHidden }.count <= 1)
                            if deck.slides.count > 1 {
                                Button(role: .destructive) { deleteSlide(i) } label: { Label("Delete Slide", systemImage: "trash") }
                            }
                        }
                        .accessibilityLabel(L("Slide \(i + 1)") + (slide.isHidden ? L(", hidden") : ""))
                    }
                    Button { showAddSlide = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 45, height: 45)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.chatStroke, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add Slide")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .fixedSize(horizontal: false, vertical: true)
            .onChange(of: index) { i in
                guard deck.slides.indices.contains(i) else { return }
                withAnimation { proxy.scrollTo(deck.slides[i].id, anchor: .center) }
            }
        }
        // While AI rewrites the presentation, its result would replace changes made meanwhile.
        .disabled(isApplying)
    }

    private func bannerView(_ text: String) -> some View {
        HStack(spacing: 10) {
            Text(text).font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading)
            if bannerIsLimit {
                Button(AccountStore.shared.effectivePlan == .plus ? "Get PRO" : "Get Minor Plus") { onUpgrade(false) }
                    .font(.system(size: 13, weight: .semibold))
            }
            Button { banner = nil } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .bold)) }
                .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(MinorColor.danger.opacity(0.25)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(MinorColor.danger.opacity(0.6), lineWidth: 1))
        .padding(.horizontal, 16)
    }

    private var composer: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 15))
                .foregroundColor(MinorColor.textSecondary)
                .accessibilityHidden(true)
            TextField("", text: $command)
                .placeholder(when: command.isEmpty) {
                    Text(isApplying ? "Changing the presentation…" : "Change with AI").foregroundColor(theme.placeholderText)
                }
                .font(.system(size: 16))
                .focused($commandFocused)
                .submitLabel(.send)
                .onSubmit(applyCommand)
                .disabled(isApplying)
            DictationButton(text: $command, stroke: theme.chatStroke)
            Button(action: applyCommand) {
                Group {
                    if isApplying { ProgressView().tint(.black) } else {
                        Image(systemName: "arrow.up").font(.system(size: 16, weight: .bold)).foregroundColor(.black)
                    }
                }
                .frame(width: 34, height: 34)
                .background(Circle().fill(MinorColor.sendFill))
            }
            .disabled(command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isApplying)
            .opacity(command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isApplying ? 0.4 : 1)
            .accessibilityLabel("Send")
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(height: 50)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    // MARK: - Elements

    private var selected: SlideElement? {
        guard let deck, deck.slides.indices.contains(index) else { return nil }
        return deck.slides[index].elements.first { $0.id == selectedElement }
    }

    private var elementBar: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button {
                        selectedElement = nil
                        withAnimation(.minorMenu) { editingElements = false }
                    } label: {
                        Label("Done", systemImage: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .frame(minHeight: 36)
                            .background(Capsule().fill(MinorColor.accent))
                    }
                    .buttonStyle(.plain)
                    addChip("textformat", L("Text"), .text, paid: false)
                    addChip("square.on.circle", L("Shape"), .shape, paid: false)
                    addChip("star", L("Icon"), .icon, paid: false)
                    addChip("photo", L("Photo"), .image, paid: true)
                    addChip("tablecells", L("Table"), .table, paid: true)
                    addChip("chart.bar.xaxis", L("Chart"), .chart, paid: true)
                    addChip("qrcode", L("QR Code"), .qr, paid: true)
                    Button { plus { designPrompt = DesignPromptMode(mode: .elements) } } label: { chipLabel("sparkles", L("With AI"), paid: true) }
                        .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
            if let element = selected {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        action("slider.horizontal.3", L("Edit")) { inspecting = element }
                        Menu {
                            ForEach(BuildEffect.allCases) { effect in
                                Button {
                                    guard isPaid || effect == .none || effect == .fade else { return onUpgrade(false) }
                                    updateElement(element.id) { $0.build = effect }
                                } label: { Label(effect.name, systemImage: effect.icon) }
                            }
                        } label: { actionLabel(element.build.icon, L("Comes In")) }
                        action("square.3.layers.3d.top.filled", L("Forward")) { moveElement(element.id, by: 1) }
                        action("square.3.layers.3d.bottom.filled", L("Back")) { moveElement(element.id, by: -1) }
                        action("plus.square.on.square", L("Duplicate")) { duplicateElement(element) }
                        Button { deleteElement(element.id) } label: { actionLabel("trash", L("Delete"), destructive: true) }
                            .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 2)
                }
                .transition(.opacity)
            } else {
                Text("Tap an element to select it, tap again to edit. Drag to move.")
                    .font(.system(size: 12))
                    .foregroundColor(MinorColor.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .frame(minHeight: 36)
            }
        }
        .animation(.minorMenu, value: selectedElement)
    }

    private func chipLabel(_ icon: String, _ title: String, paid: Bool) -> some View {
        actionLabel(icon, title, plus: paid && !isPaid)
    }

    private func addChip(_ icon: String, _ title: String, _ kind: SlideElement.Kind, paid: Bool) -> some View {
        Button {
            guard !paid || isPaid else { return onUpgrade(false) }
            if kind == .image { return showElementPhotos = true }
            insert(SlideElement.new(kind))
        } label: { chipLabel(icon, title, paid: paid) }
        .buttonStyle(.plain)
    }

    private func insert(_ element: SlideElement) {
        mutate { $0.slides[index].elements.append(element) }
        selectedElement = element.id
        Haptics.impact(.light)
    }

    private func updateElement(_ id: UUID, _ change: (inout SlideElement) -> Void) {
        mutate { deck in
            guard let i = deck.slides[index].elements.firstIndex(where: { $0.id == id }) else { return }
            change(&deck.slides[index].elements[i])
        }
    }

    private func moveElement(_ id: UUID, by step: Int) {
        mutate { deck in
            var list = deck.slides[index].elements
            guard let i = list.firstIndex(where: { $0.id == id }) else { return }
            let target = min(max(i + step, 0), list.count - 1)
            list.swapAt(i, target)
            deck.slides[index].elements = list
        }
    }

    private func duplicateElement(_ element: SlideElement) {
        var copy = element
        copy.id = UUID()
        copy.x = min(element.x + 30, 1280 - element.w)
        copy.y = min(element.y + 30, 720 - element.h)
        insert(copy)
    }

    private func deleteElement(_ id: UUID) {
        mutate { $0.slides[index].elements.removeAll { $0.id == id } }
        if selectedElement == id { selectedElement = nil }
    }

    // Paid features: runs the action with Plus or PRO, otherwise offers it.
    private func plus(_ action: () -> Void) {
        if isPaid { action() } else { onUpgrade(false) }
    }

    // After one sheet closes, the next can open.
    private func after(_ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: action)
    }

    private func describeStyle(_ prompt: String) {
        guard let deck else { return }
        withAI {
            isApplying = true
            Task {
                defer { isApplying = false }
                do {
                    var look = try await DeckService.shared.style(prompt, for: deck)
                    if look.name.isEmpty { look.name = String(prompt.prefix(30)) }
                    mutate { $0.look = look }
                    LookStore.shared.save(look)
                    toast(L("New style applied"))
                    Haptics.success()
                } catch {
                    show(error)
                }
            }
        }
    }

    private func addElements(_ prompt: String) {
        guard let deck, deck.slides.indices.contains(index) else { return }
        let slide = deck.slides[index]
        withAI {
            rewriting.insert(slide.id)
            Task {
                defer { rewriting.remove(slide.id) }
                do {
                    let elements = try await DeckService.shared.elements(prompt, slide: slide, deck: deck)
                    guard !elements.isEmpty else { return toast(L("Nothing to add. Try other words.")) }
                    mutate { deck in
                        guard let i = deck.slides.firstIndex(where: { $0.id == slide.id }) else { return }
                        deck.slides[i].elements += elements
                    }
                    selectedElement = elements.first?.id
                    withAnimation(.minorMenu) { editingElements = true }
                    Haptics.success()
                } catch {
                    show(error)
                }
            }
        }
    }

    // MARK: - Changes

    private func mutate(undoable: Bool = true, _ change: (inout Deck) -> Void) {
        guard let base = deck, !base.slides.isEmpty else { return }
        // The deck may have changed since the index was set (sync, AI); changes go to a slide that exists.
        if !base.slides.indices.contains(index) { index = base.slides.count - 1 }
        var copy = base
        change(&copy)
        guard copy != base else { return }
        if undoable {
            history.append(Snapshot(deck: base, selection: diagramSelection))
            if history.count > 30 { history.removeFirst() }
            future = []
        }
        store.save(copy)
        index = min(index, max(copy.slides.count - 1, 0))
    }

    private func undo() {
        guard let previous = history.popLast() else { return }
        Haptics.impact(.light)
        if let current = deck { future.append(Snapshot(deck: current, selection: diagramSelection)) }
        restore(previous)
    }

    private func redo() {
        guard let next = future.popLast() else { return }
        Haptics.impact(.light)
        if let current = deck { history.append(Snapshot(deck: current, selection: diagramSelection)) }
        restore(next)
    }

    // The presentation as it was, and the diagram's selection then (when that box still exists).
    private func restore(_ snapshot: Snapshot) {
        store.save(snapshot.deck)
        index = min(index, max(snapshot.deck.slides.count - 1, 0))
        let slide = snapshot.deck.slides.indices.contains(index) ? snapshot.deck.slides[index] : nil
        let diagram = slide.flatMap { s in s.diagram?.structured(slideID: s.id) }
        diagramSelection = snapshot.selection.flatMap { id in diagram?.node(id) != nil ? id : nil }
    }

    // One diagram command: the slide's diagram replaced (and its words kept for earlier apps).
    private func commitDiagram(_ diagram: SlideDiagram) {
        guard let slide else { return }
        var updated = diagram
        updated.syncLegacy(title: slide.title)
        mutate { deck in
            guard let i = deck.slides.firstIndex(where: { $0.id == slide.id }) else { return }
            deck.slides[i].diagram = updated
        }
    }

    private func editDiagram(select id: UUID? = nil) {
        if let id { diagramSelection = id }
        selectedPart = nil
        editingDiagram = true
    }

    private func replaceSlide(_ updated: Slide) {
        mutate { deck in
            guard let i = deck.slides.firstIndex(where: { $0.id == updated.id }) else { return }
            deck.slides[i] = updated
        }
    }

    private func addSlide(_ layout: SlideLayout) {
        let new = Slide(layout: .bullets, title: L("New slide"), bullets: [L("First point"), L("Second point")]).converted(to: layout)
        mutate { $0.slides.insert(new, at: min(index + 1, $0.slides.count)) }
        index = min(index + 1, (deck?.slides.count ?? 1) - 1)
        showInspector = true
    }

    private func duplicateSlide(_ i: Int) {
        guard deck?.slides.indices.contains(i) == true else { return }
        mutate { deck in
            var copy = deck.slides[i]
            copy.id = UUID()
            copy.elements = copy.elements.map { var e = $0; e.id = UUID(); return e }
            deck.slides.insert(copy, at: i + 1)
        }
        // The slide on screen stays on screen.
        if i < index { index += 1 }
    }

    private func moveSlide(_ i: Int, by offset: Int) {
        mutate { deck in
            let target = i + offset
            guard deck.slides.indices.contains(target) else { return }
            deck.slides.swapAt(i, target)
        }
        index = i + offset
    }

    // Hidden slides are skipped when presenting; one slide always stays visible.
    private func toggleHidden(_ i: Int) {
        guard let deck, deck.slides.indices.contains(i) else { return }
        let hiding = !deck.slides[i].isHidden
        guard !hiding || deck.slides.filter({ !$0.isHidden }).count > 1 else { return }
        mutate { $0.slides[i].isHidden = hiding }
        toast(hiding ? L("Slide hidden: skipped when presenting") : L("Slide shown"))
    }

    private func deleteSlide(_ i: Int) {
        guard let count = deck?.slides.count, count > 1, i < count else { return }
        mutate { deck in
            deck.slides.remove(at: i)
            // Something always stays to present.
            if !deck.slides.contains(where: { !$0.isHidden }), !deck.slides.isEmpty { deck.slides[0].isHidden = false }
        }
        // The slide on screen stays on screen.
        if i < index { index -= 1 }
        toast(L("Slide deleted"))
    }

    // MARK: - AI

    private func withAI(_ action: @escaping () -> Void) {
        guard AuthService.shared.isSignedIn else { return AuthGate.shared.require(action) }
        guard AIConsent.isGiven else {
            banner = L("Allow AI in Settings → AI Data Sharing to use AI in presentations.")
            bannerIsLimit = false
            return
        }
        action()
    }

    private func rewrite(_ instruction: String) {
        guard let slide, let deck else { return }
        // The AI rewrites the slide's words; a slide with none (only elements or a picture) has
        // nothing to start from.
        guard !slide.title.isEmpty || !slide.bullets.isEmpty || slide.quote != nil || slide.stat != nil else {
            banner = L("Add a title or a few points to this slide first, then AI can rewrite it.")
            bannerIsLimit = false
            return
        }
        withAI {
            rewriting.insert(slide.id)
            Task {
                defer { rewriting.remove(slide.id) }
                do {
                    let updated = try await DeckService.shared.rewrite(slide, in: deck, instruction: instruction)
                    replaceSlide(updated)
                    Haptics.success()
                } catch {
                    show(error)
                }
            }
        }
    }

    private func drawImage() {
        guard let slide, let deck else { return }
        withAI {
            drawing.insert(slide.id)
            let prompt = slide.imagePrompt ?? "\(slide.title). \(slide.bullets.prefix(3).joined(separator: ", "))"
            Task {
                defer { drawing.remove(slide.id) }
                do {
                    let data = try await AIService.shared.generateImage(prompt: "\(prompt). An illustration for a presentation about \(deck.title); no text or letters in the image.")
                    guard let picture = MapStore.shared.storeImage(data, isAI: true) else { return }
                    mutate { deck in
                        guard let i = deck.slides.firstIndex(where: { $0.id == slide.id }) else { return }
                        deck.slides[i].image = picture
                        if deck.slides[i].layout != .imageText { deck.slides[i] = deck.slides[i].converted(to: .imageText) }
                    }
                    Haptics.success()
                } catch {
                    show(error)
                }
            }
        }
    }

    private func applyCommand() {
        let text = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isApplying, let deck else { return }
        withAI {
            commandFocused = false
            command = ""
            isApplying = true
            Task {
                defer { isApplying = false }
                do {
                    let edited = try await DeckService.shared.edit(deck, command: text)
                    mutate { $0.title = edited.title; $0.slides = edited.slides }
                    toast(L("Presentation updated"))
                    Haptics.success()
                } catch {
                    command = text
                    show(error)
                }
            }
        }
    }

    struct UpdatePreview: Identifiable {
        let id = UUID()
        let title: String
        let slides: [Slide]
        let base: [Slide]       // the slides when the update started
        let revision: String    // the source content the new slides were made from
    }

    // What the map changed since the slides last agreed with it, field by field, shown before
    // anything changes. Presentations without links can be linked by hand or updated as a copy.
    private func updateFromMap() {
        guard let deck else { return }
        guard let content = deck.sourceContent else {
            sourceMissing = true
            return
        }
        guard deck.lineage != nil else {
            linking = true
            return
        }
        let update = MapUpdate.compute(deck: deck, map: content)
        guard !update.visible.isEmpty else {
            // Only words both sides already agree on: the links move on quietly.
            mutate(undoable: false) { $0 = update.applied(to: $0, content: content) }
            toast(L("The slides already match the map"))
            return
        }
        mapUpdate = update
    }

    // The comparison again, when the map or the slides changed meanwhile.
    private func refreshedUpdate() -> MapUpdate? {
        guard let deck, let content = deck.sourceContent else { return nil }
        return MapUpdate.compute(deck: deck, map: content)
    }

    // Applied only to what was compared; one change for Undo; reported done once it is saved.
    private func applyMapUpdate(_ update: MapUpdate) -> String? {
        guard let deck, let content = deck.sourceContent else { return L("The map isn’t available any more.") }
        guard deck == update.deck, content.contentFingerprint == update.revision else { return MapMergeSheet.staleMessage }
        let result = update.applied(to: deck, content: content)
        mutate { $0 = result }
        store.flush()
        if store.failedSaves.contains(deck.id) {
            undo()
            future = []
            return L("Couldn’t save the update, so nothing changed. Try again.")
        }
        Telemetry.log("deck_update_from_map", ["mode": "merge", "changes": update.changeCount, "conflicts": update.conflicts.count])
        Haptics.success()
        toast(L("Updated from the map: \(update.changeCount)"))
        return nil
    }

    // The same choices on a separate presentation; this one stays as it is.
    private func saveMapUpdateAsCopy(_ update: MapUpdate) {
        guard let deck, let content = deck.sourceContent else { return }
        var copy = update.applied(to: deck, content: content)
        copy.id = UUID()
        copy.createdAt = Date()
        store.save(copy)
        Telemetry.log("deck_update_from_map", ["mode": "copy"])
        toast(L("Saved as a new presentation in the Library"))
    }

    // The earlier way, for presentations without links: new slides written from the map, kept as
    // a copy (or replacing these slides while they haven't changed meanwhile).
    private func regenerateFromMap() {
        guard let deck else { return }
        guard let content = deck.sourceContent else {
            sourceMissing = true
            return
        }
        let base = deck.slides
        let revision = content.contentFingerprint
        withAI {
            isApplying = true
            Task {
                defer { isApplying = false }
                do {
                    let generated = try await DeckService.shared.generate(.map(content), slides: max(deck.slides.count, 6), quality: AccountStore.shared.allowedMapModelID)
                    updatePreview = UpdatePreview(title: generated.title, slides: generated.slides, base: base, revision: revision)
                } catch {
                    show(error)
                }
            }
        }
    }

    // The safe way: a new presentation with the same design; this one stays as it is.
    private func saveUpdateAsCopy(_ preview: UpdatePreview) {
        guard var copy = deck else { return }
        copy.id = UUID()
        copy.title = preview.title
        copy.slides = preview.slides
        copy.sourceRevision = preview.revision
        copy.createdAt = Date()
        store.save(copy)
        Telemetry.log("deck_update_from_map", ["mode": "copy"])
        toast(L("Saved as a new presentation in the Library"))
    }

    // Replaces the slides only if nobody changed them while the new ones were written; Undo brings them back.
    private func replaceWithUpdate(_ preview: UpdatePreview) {
        guard let deck, deck.slides == preview.base else {
            toast(L("The slides changed meanwhile. Save the update as a copy instead."))
            return
        }
        mutate {
            $0.title = preview.title
            $0.slides = preview.slides
            $0.sourceRevision = preview.revision
        }
        index = 0
        Telemetry.log("deck_update_from_map", ["mode": "replace"])
        toast(L("Slides updated from the map"))
    }

    // MARK: - Export

    struct ExportFile: Identifiable {
        let url: URL
        var id: URL { url }
    }

    private func toast(_ text: String) {
        toast = text
        UIAccessibility.post(notification: .announcement, argument: text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { if toast == text { toast = nil } }
    }

    private func show(_ error: Error) {
        Haptics.error()
        if case BackendError.limitReached(let kind) = error { AccountStore.shared.noteLimitReached(kind: kind) }
        if case BackendError.modelLocked = error { return onUpgrade(true) }
        bannerIsLimit = (error as? BackendError)?.suggestsUpgrade ?? false
        banner = (error as? LocalizedError)?.errorDescription ?? L("Something went wrong. Try again.")
    }
}

// The system share sheet for an exported file.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
