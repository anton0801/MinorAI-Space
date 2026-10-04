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

    @ObservedObject private var store = DeckStore.shared
    @State private var index = 0
    @State private var history: [Deck] = []
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
    @State private var confirmRebuild = false
    @State private var exportURL: URL?
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotos = false
    // Design.
    @ObservedObject private var account = AccountStore.shared
    @State private var editingElements = false
    @State private var selectedElement: UUID?
    @State private var inspecting: SlideElement?
    @State private var showLookEditor = false
    @State private var lookStart: DeckLook?
    @State private var showBrand = false
    @State private var showSlideDesign = false
    @State private var designPrompt: DesignPromptMode?
    @State private var savingTemplate = false
    @State private var templateName = ""
    @State private var elementPhotoItem: PhotosPickerItem?
    @State private var showElementPhotos = false
    @FocusState private var commandFocused: Bool

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

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()
            if let deck {
                VStack(spacing: 14) {
                    header(deck)
                    stage(deck)
                    slideActions
                    filmstrip(deck)
                    notesCard
                    Spacer(minLength: 0)
                    if let banner { bannerView(banner) }
                    composer
                }
                .padding(.bottom, 8)
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
                    .onAppear(perform: onClose)
            }
        }
        .foregroundColor(MinorColor.textPrimary)
        .animation(.minorMenu, value: toast)
        .animation(.minorMenu, value: banner)
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
                ThemePicker(deck: deck, theme: theme, isPaid: isPaid, onPick: { choice in
                    switch choice {
                    case .builtIn(let ready): mutate { $0.theme = ready.rawValue; $0.look = nil }
                    case .look(let look): mutate { $0.look = look }
                    }
                }, onCreate: {
                    showThemes = false
                    plus { after { lookStart = nil; showLookEditor = true } }
                }, onDescribe: {
                    showThemes = false
                    plus { after { designPrompt = DesignPromptMode(mode: .style) } }
                })
                .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $showLookEditor) {
            if let deck {
                LookEditor(deck: deck, slideIndex: index, theme: theme, start: lookStart) { look in mutate { $0.look = look } }
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
        .sheet(item: Binding(get: { exportURL.map(ExportFile.init) }, set: { exportURL = $0?.url })) { file in
            ShareSheet(items: [file.url])
        }
        .fullScreenCover(isPresented: $presenting) {
            if let deck { DeckPresenterView(deck: deck, start: index) }
        }
        .onChange(of: index) { _ in selectedElement = nil }
        // Slides can change from elsewhere (sync, the chat's AI edit): keep the index valid.
        .onChange(of: deck?.slides.count ?? 0) { count in
            if index >= count { index = max(count - 1, 0) }
        }
        #if DEBUG
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-demoThemes") { showThemes = true }
            if args.contains("-demoOwnStyle") { showLookEditor = true }
            if args.contains("-demoBrand") { showBrand = true }
            if args.contains("-demoElements") { index = 3; editingElements = true; selectedElement = deck?.slides[3].elements.first?.id }
        }
        #endif
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
                onClose()
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Build the slides again from the map? The current slides go to Undo.", isPresented: $confirmRebuild, titleVisibility: .visible) {
            Button("Rebuild from Map") { rebuildFromMap() }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Header and stage

    private func header(_ deck: Deck) -> some View {
        HStack(spacing: 0) {
            Button(action: onClose) {
                Image(systemName: "house.fill").font(.system(size: 18)).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Home")
            if !history.isEmpty {
                Button(action: undo) {
                    Image(systemName: "arrow.uturn.backward").font(.system(size: 17)).frame(width: 40, height: 44)
                }
                .accessibilityLabel("Undo")
            }
            Spacer(minLength: 8)
            VStack(spacing: 0) {
                Text(deck.title).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                Text(L("\(deck.slides.count) slides")).font(.system(size: 12)).foregroundColor(MinorColor.textTertiary)
            }
            .onTapGesture {
                renameText = deck.title
                renaming = true
            }
            Spacer(minLength: 8)
            Button { presenting = true } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.black)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(MinorColor.accent))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Present")
            Menu {
                Button { showThemes = true } label: { Label("Theme", systemImage: "paintpalette") }
                Button { plus { showBrand = true } } label: { Label(isPaid ? "Brand" : "Brand · Plus", systemImage: "seal") }
                Button { plus { templateName = deck.title; savingTemplate = true } } label: { Label(isPaid ? "Save as Template" : "Save as Template · Plus", systemImage: "square.on.square") }
                Button { renameText = deck.title; renaming = true } label: { Label("Rename", systemImage: "pencil") }
                Section {
                    Button { export(.pdf) } label: { Label("Export PDF", systemImage: "doc.richtext") }
                    Button { plus { export(.pptx) } } label: { Label(isPaid ? "Export PowerPoint" : "Export PowerPoint · Plus", systemImage: "rectangle.on.rectangle") }
                }
                if let map = deck.sourceMapID, MapStore.shared.map(map) != nil {
                    Section {
                        Button { onOpenMap(map) } label: { Label("Open Source Map", systemImage: "point.3.connected.trianglepath.dotted") }
                        Button { confirmRebuild = true } label: { Label("Rebuild from Map", systemImage: "arrow.triangle.2.circlepath") }
                    }
                }
                Button(role: .destructive) { confirmDelete = true } label: { Label("Delete Presentation", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 18)).frame(width: 44, height: 44)
            }
            .accessibilityLabel("More")
        }
        .padding(.horizontal, 6)
        .disabled(isApplying)
    }

    @ViewBuilder
    private func stage(_ deck: Deck) -> some View {
        if editingElements, deck.slides.indices.contains(index) {
            SlideElementEditor(deck: deck, index: index, selection: $selectedElement, onChange: { elements in
                mutate { $0.slides[index].elements = elements }
            }, onEdit: { inspecting = $0 })
            .disabled(isApplying)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(MinorColor.accent.opacity(0.7), lineWidth: 1.5))
            .padding(.horizontal, 16)
            .frame(height: (UIScreen.main.bounds.width - 32) * 9 / 16 + 8)
        } else {
            pager(deck)
        }
    }

    private func pager(_ deck: Deck) -> some View {
        TabView(selection: $index) {
            ForEach(Array(deck.slides.enumerated()), id: \.element.id) { i, slide in
                SlideCanvas(slide: slide, deck: deck, index: i)
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
                    .onTapGesture { showInspector = true }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(L("Edits the slide"))
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: (UIScreen.main.bounds.width - 32) * 9 / 16 + 8)
        .overlay(alignment: .bottomTrailing) {
            Text("\(index + 1) / \(deck.slides.count)")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.black.opacity(0.55)))
                .foregroundColor(.white)
                .padding(.trailing, 26)
                .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private var slideActions: some View {
        if editingElements { elementBar } else { slideChips }
    }

    private var slideChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                action("pencil", L("Edit")) { showInspector = true }
                action("square.on.circle", L("Elements")) {
                    selectedElement = nil
                    withAnimation(.minorMenu) { editingElements = true }
                }
                action("wand.and.stars", L("Design")) { showSlideDesign = true }
                action("square.grid.2x2", L("Layout")) { showLayouts = true }
                action("sparkles", L("Rewrite with AI")) { showRewrite = true }
                Menu {
                    Button { drawImage() } label: { Label("Create Image with AI", systemImage: "wand.and.stars") }
                    Button { showPhotos = true } label: { Label("Add Photo", systemImage: "photo") }
                    if slide?.image != nil {
                        Button(role: .destructive) { mutate { $0.slides[index].image = nil } } label: { Label("Remove Image", systemImage: "photo.badge.minus") }
                    }
                } label: { actionLabel("photo", L("Picture")) }
                action("text.bubble", L("Notes")) { showNotes = true }
                action("paintpalette", L("Theme")) { showThemes = true }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
        .disabled(isApplying)
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
                LazyHStack(spacing: 10) {
                    ForEach(Array(deck.slides.enumerated()), id: \.element.id) { i, slide in
                        Button {
                            withAnimation(.minorMenu) { index = i }
                        } label: {
                            SlideCanvas(slide: slide, deck: deck, index: i)
                                .frame(width: 112)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(i == index ? MinorColor.accent : theme.chatStroke, lineWidth: i == index ? 2 : 1))
                                .overlay(alignment: .topLeading) {
                                    Text("\(i + 1)")
                                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                                        .foregroundColor(.white)
                                        .padding(4)
                                        .background(Circle().fill(Color.black.opacity(0.55)))
                                        .padding(4)
                                }
                        }
                        .buttonStyle(.plain)
                        .id(slide.id)
                        .contextMenu {
                            Button { duplicateSlide(i) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                            if i > 0 { Button { moveSlide(i, by: -1) } label: { Label("Move Left", systemImage: "arrow.left") } }
                            if i < deck.slides.count - 1 { Button { moveSlide(i, by: 1) } label: { Label("Move Right", systemImage: "arrow.right") } }
                            if deck.slides.count > 1 {
                                Button(role: .destructive) { deleteSlide(i) } label: { Label("Delete Slide", systemImage: "trash") }
                            }
                        }
                        .accessibilityLabel(L("Slide \(i + 1)"))
                    }
                    Button { showAddSlide = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 63, height: 63)
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.chatStroke, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add Slide")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .onChange(of: index) { i in
                guard deck.slides.indices.contains(i) else { return }
                withAnimation { proxy.scrollTo(deck.slides[i].id, anchor: .center) }
            }
        }
        // While AI rewrites the presentation, its result would replace changes made meanwhile.
        .disabled(isApplying)
    }

    // What the speaker says on this slide; tap to edit.
    private var notesCard: some View {
        Button { showNotes = true } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Speaker Notes", systemImage: "text.bubble")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(MinorColor.textTertiary)
                    Spacer()
                    Image(systemName: "pencil").font(.system(size: 12)).foregroundColor(MinorColor.textTertiary)
                }
                Text(slide?.notes.isEmpty == false ? slide!.notes : L("Add what you want to say on this slide."))
                    .font(.system(size: 15))
                    .foregroundColor(slide?.notes.isEmpty == false ? MinorColor.textSecondary : MinorColor.textTertiary)
                    .lineLimit(5)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(theme.chatRectangle))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.chatStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
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
            TextField("", text: $command)
                .placeholder(when: command.isEmpty) {
                    Text(isApplying ? "Changing the presentation…" : "Change this presentation").foregroundColor(theme.placeholderText)
                }
                .font(.system(size: 17))
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
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .frame(height: 60)
        .minorSurface(theme)
        .padding(.horizontal, 16)
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
            history.append(base)
            if history.count > 30 { history.removeFirst() }
        }
        store.save(copy)
        index = min(index, max(copy.slides.count - 1, 0))
    }

    private func undo() {
        guard let previous = history.popLast() else { return }
        Haptics.impact(.light)
        store.save(previous)
        index = min(index, max(previous.slides.count - 1, 0))
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

    private func deleteSlide(_ i: Int) {
        guard let count = deck?.slides.count, count > 1, i < count else { return }
        mutate { $0.slides.remove(at: i) }
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

    private func rebuildFromMap() {
        guard let deck, let mapID = deck.sourceMapID, let map = MapStore.shared.map(mapID) else { return }
        withAI {
            isApplying = true
            Task {
                defer { isApplying = false }
                do {
                    let generated = try await DeckService.shared.generate(.map(map), slides: max(deck.slides.count, 6), quality: AccountStore.shared.allowedMapModelID)
                    mutate { $0.title = generated.title; $0.slides = generated.slides }
                    index = 0
                    toast(L("Slides rebuilt from the map"))
                } catch {
                    show(error)
                }
            }
        }
    }

    // MARK: - Export

    enum ExportKind { case pdf, pptx }

    struct ExportFile: Identifiable {
        let url: URL
        var id: URL { url }
    }

    private func export(_ kind: ExportKind) {
        guard let deck else { return }
        do {
            exportURL = kind == .pdf ? try DeckExport.pdf(deck) : try DeckExport.pptx(deck)
        } catch {
            banner = L("Couldn’t export. Try again.")
            bannerIsLimit = false
        }
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
