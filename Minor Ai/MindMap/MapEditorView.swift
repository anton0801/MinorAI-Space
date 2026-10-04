//
//  MapEditorView.swift
//  Minor Ai
//
//  The map editor (DesignSystem → Mind Map screens → Editor): tree, balanced or list layout,
//  node action bar, node card, search, focus, drag and drop, undo, and a command field that
//  lets AI change the map.
//

import PhotosUI
import SwiftUI

struct MapEditorView: View {
    let theme: AppTheme
    var onClose: () -> Void
    var onUpgrade: (_ pro: Bool) -> Void

    @ObservedObject private var store = MapStore.shared
    private let mapID: UUID
    @State private var map: MindMap
    @State private var layout: MapLayout
    @State private var viewport = CanvasViewport()
    @State private var selection: UUID?
    @State private var generating: Set<UUID> = []
    @State private var flashed: Set<UUID> = []
    @State private var mode: Mode
    @State private var command = ""
    @State private var isApplying = false
    @State private var banner: Banner?
    @State private var toast: Toast?
    @State private var history: [Snapshot] = []
    // Connections and frames (see MapExtras).
    @State private var linkingFrom: UUID?
    @State private var linkMenu: MapLink?
    @State private var linkLabelTarget: UUID?
    @State private var linkLabelText = ""
    @State private var frameTarget: UUID?
    @State private var frameText = ""
    @State private var dueTarget: UUID?
    @State private var showStudy = false
    @State private var showHistory = false
    @State private var showCollab = false
    @ObservedObject private var collab = CollabService.shared
    // Presentation: slide 0 shows the whole map, then one main branch per slide.
    @State private var presenting = false
    @State private var slide = 0

    // What undo restores: the tree and the connections between its ideas.
    struct Snapshot: Equatable {
        let root: MindNode
        let links: [MapLink]
    }
    // Counts undoable actions and never goes down (history is capped, so its length can't identify one).
    @State private var actionCount = 0
    @State private var renameTarget: UUID?
    @State private var renameText = ""
    @State private var isRenaming = false
    @State private var styleNodeID: UUID?
    @State private var showDesign = false
    @State private var showExport = false
    @State private var chatNodeID: UUID?
    @State private var cardNodeID: UUID?
    @State private var pendingDelete: UUID?
    @State private var confirmDeleteMap = false
    @State private var isSearching = false
    @State private var query = ""
    @State private var focusID: UUID?
    @State private var showConsent = false
    @State private var afterConsent: (() -> Void)?
    @State private var afterCard: (() -> Void)?
    @State private var chatPrompt: String?
    @State private var lastSelection: UUID?
    @State private var photoTarget: UUID?
    @State private var showNodePhotos = false
    @State private var photoItem: PhotosPickerItem?
    @State private var iconTarget: UUID?
    @State private var linkTarget: UUID?
    @State private var linkText = ""
    @State private var viewer: ViewerItem?
    @State private var imageBatch: ImageBatch?

    struct ImageBatch: Identifiable {
        let id = UUID()
        let nodes: [UUID]
        var hint = ""
    }
    @FocusState private var commandFocused: Bool
    @FocusState private var searchFocused: Bool

    enum Mode: String { case tree, balanced, list }

    struct Banner: Equatable {
        let text: String
        let isLimit: Bool
    }

    struct Toast: Equatable {
        let id = UUID()
        let text: String
        // Number of the action the toast is about, so its Undo undoes exactly that action.
        let action: Int?
    }

    var onCreateDeck: (UUID) -> Void = { _ in }

    init(mapID: UUID, theme: AppTheme, onClose: @escaping () -> Void, onUpgrade: @escaping (_ pro: Bool) -> Void, onCreateDeck: @escaping (UUID) -> Void = { _ in }) {
        self.theme = theme
        self.onClose = onClose
        self.onUpgrade = onUpgrade
        self.onCreateDeck = onCreateDeck
        self.mapID = mapID
        let map = MapStore.shared.map(mapID) ?? MindMap(root: MindNode(title: L("New Map")))
        // VoiceOver users start in the outline, which reads in order; they can still switch.
        let mode = UIAccessibility.isVoiceOverRunning ? .list : Mode(rawValue: map.layout ?? "") ?? .tree
        _map = State(initialValue: map)
        _mode = State(initialValue: mode)
        _layout = State(initialValue: MapLayout(map: map, balanced: mode == .balanced))
    }

    private var selectedNode: MindNode? { selection.flatMap { map.root.node($0) } }
    private var selectedLevel: Int { selection.flatMap { map.root.path(to: $0)?.count }.map { $0 - 1 } ?? 0 }
    private var chromeInsets: EdgeInsets { EdgeInsets(top: 110, leading: 16, bottom: 170, trailing: 16) }

    // MARK: - Search and focus

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var matches: Set<UUID> {
        guard isSearching, !trimmedQuery.isEmpty else { return [] }
        return Self.ids(in: map.root) { node in
            node.title.range(of: trimmedQuery, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                || node.note.range(of: trimmedQuery, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    // The map as shown: branches that hide a search match open up without changing the saved map.
    private func displayMap(for matches: Set<UUID>) -> MindMap {
        var display = map
        // While presenting, the branch on screen is shown fully open.
        if presenting, let id = currentSlideBranch, let branch = display.root.node(id) {
            display.root.update(id) { $0 = branch.expandedAll }
        }
        guard !matches.isEmpty else { return display }
        for id in matches {
            for ancestor in (map.root.path(to: id) ?? []).dropLast() {
                display.root.update(ancestor.id) { $0.isCollapsed = false }
            }
        }
        return display
    }

    private var dimmed: Set<UUID> {
        if presenting, let id = currentSlideBranch {
            return Set(layout.nodes.map(\.id)).subtracting(layout.subtree(id)).subtracting([map.root.id])
        }
        if isSearching, !trimmedQuery.isEmpty {
            return Set(layout.nodes.map(\.id)).subtracting(matches).subtracting([map.root.id])
        }
        if let focusID {
            let keep = layout.subtree(focusID).union((map.root.path(to: focusID) ?? []).map(\.id))
            return Set(layout.nodes.map(\.id)).subtracting(keep)
        }
        return []
    }

    // In List mode a search shows only the matches and the ideas above them.
    private var outlineVisible: Set<UUID>? {
        guard isSearching, !trimmedQuery.isEmpty else { return nil }
        return Set(matches.flatMap { (map.root.path(to: $0) ?? []).map(\.id) })
    }

    private func relayout(animated: Bool = true) {
        let new = MapLayout(map: displayMap(for: matches), balanced: mode == .balanced)
        if animated {
            withAnimation(.minorNode) { layout = new }
        } else {
            layout = new
        }
    }

    // MARK: - Body

    var body: some View {
        tasksModifiers(modifiers3(modifiers2(modifiers1(core))))
    }

    // Due dates, and selecting the task a reminder or the Today screen pointed at.
    private func tasksModifiers<Content: View>(_ content: Content) -> some View {
        content
            .sheet(isPresented: $showCollab) {
                CollabSheet(mapID: mapID, theme: theme) { onUpgrade(false) }
                    .presentationDetents([.medium, .large])
            }
            .onAppear { collab.watch(mapID) }
            .onDisappear { collab.unwatch(mapID) }
            .onChange(of: store.map(mapID)?.collab != nil) { shared in if shared { collab.watch(mapID) } }
            .sheet(isPresented: $showHistory) {
                VersionHistoryView(mapID: mapID, theme: theme) {
                    history = []
                    showToast(L("Version restored"), canUndo: false)
                }
            }
            .fullScreenCover(isPresented: $showStudy) {
                StudyView(map: map, theme: theme, onUpgrade: { onUpgrade(false) })
            }
            .sheet(item: Binding(get: { dueTarget.map(IdentifiedID.init) }, set: { dueTarget = $0?.id })) { item in
                if let node = map.root.node(item.id) {
                    DueDateSheet(title: node.title, current: node.due, theme: theme, onSave: { date in
                        mutate { $0.root.update(item.id) { node in
                            node.due = date
                            node.isTask = true
                            node.isDone = false
                        } }
                        Reminders.shared.requestPermission()
                    }, onRemove: {
                        mutate { $0.root.update(item.id) { $0.due = nil } }
                    })
                    .presentationDetents([.large])
                }
            }
            .onReceive(GenerationCenter.shared.$studyRequest) { id in
                guard let id, id == mapID else { return }
                GenerationCenter.shared.studyRequest = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showStudy = true }
            }
            .onReceive(GenerationCenter.shared.$focusNode) { id in
                guard let id, map.root.node(id) != nil else { return }
                GenerationCenter.shared.focusNode = nil
                // Open the branches above it, then select it (which also brings it into view).
                mutate(animated: false, undoable: false, personal: true) { map in
                    for ancestor in (map.root.path(to: id) ?? []).dropLast() {
                        map.root.update(ancestor.id) { $0.isCollapsed = false }
                    }
                }
                if mode == .list { mode = .tree }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { selection = id }
            }
    }

    private var core: some View {
        ZStack {
            Group {
                if mode == .list {
                    MapOutlineView(map: map, theme: theme, selection: $selection, visible: outlineVisible, highlighted: matches)
                } else {
                    MapCanvasView(
                        layout: layout,
                        theme: theme,
                        viewport: $viewport,
                        selection: $selection,
                        generating: generating,
                        dimmed: dimmed,
                        highlighted: flashed.union(matches),
                        chromeInsets: chromeInsets,
                        onDoubleTapNode: { startRename($0) },
                        onToggleCollapse: { toggleCollapse($0) },
                        onExpand: { expand($0) },
                        onMove: { move($0, under: $1) },
                        mapStyle: map.mapStyle,
                        onToggleDone: { toggleDone($0) },
                        lineStyle: map.lineStyle,
                        lineWeight: map.lineWeightValue,
                        background: map.canvasBackground,
                        links: map.links,
                        onLinkTap: { linkMenu = $0 }
                    )
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(!isApplying)

            VStack {
                Spacer()
                Rectangle()
                    .fill(theme.blur)
                    .frame(height: 120)
                    .blur(radius: 50)
                    .opacity(0.5)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            if presenting {
                presentationControls
            } else {
            VStack(spacing: 0) {
                topBar
                if let focusID, let node = map.root.node(focusID) {
                    focusChip(node)
                        .padding(.top, 4)
                }
                if let from = linkingFrom, let node = map.root.node(from) {
                    linkingChip(node)
                        .padding(.top, 4)
                }
                Spacer()
                bottomArea
            }
            }
        }
        .background(theme.background.ignoresSafeArea())
        #if DEBUG
        .onAppear(perform: applyDebugState)
        #endif
        .onChange(of: selection) { id in
            if let id, linkingFrom != nil { finishLinking(to: id) }
            if let previous = lastSelection, previous != id { clearAIMark(previous) }
            lastSelection = id
            if let id, !presenting { reveal(id) }
        }
        .onReceive(store.$maps) { maps in
            // A result that landed while this editor was closed, or a change made elsewhere.
            // Content or design changed elsewhere (an AI result, another device, a person editing with us).
            guard let stored = maps.first(where: { $0.id == mapID }) else {
                // Deleted on another device (or by the owner of a shared map): close instead of
                // letting edits go nowhere.
                onClose()
                return
            }
            guard stored.root != map.root || stored.links != map.links || stored.collab != map.collab
                    || stored.style != map.style || stored.palette != map.palette || stored.lines != map.lines
                    || stored.lineWeight != map.lineWeight || stored.canvas != map.canvas
            else { return }
            // Undo would put back a whole snapshot and wipe what came from elsewhere.
            if stored.root != map.root || stored.links != map.links {
                history.removeAll()
                toast = nil
            }
            map = stored
            sanitize()
            relayout(animated: false)
        }
        .onDisappear {
            if let id = selection { clearAIMark(id) }
        }
        .onChange(of: query) { _ in relayout() }
        .onChange(of: isSearching) { _ in relayout() }
    }

    private func modifiers1<Content: View>(_ content: Content) -> some View {
        content
        .onChange(of: mode) { newMode in
            map.layout = newMode.rawValue
            store.update(mapID, touch: false) { $0.layout = newMode.rawValue }
            relayout(animated: false)
            viewport = .opening(layout, in: UIScreen.main.bounds.size, insets: chromeInsets)
        }
        .photosPicker(isPresented: $showNodePhotos, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { item in
            guard let item, let id = photoTarget else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { setPhoto(data, for: id) }
                photoItem = nil
                photoTarget = nil
            }
        }
        .sheet(item: Binding(get: { iconTarget.map(IdentifiedID.init) }, set: { iconTarget = $0?.id })) { item in
            IconPickerView(current: map.root.node(item.id)?.icon) { icon in
                mutate { $0.root.update(item.id) { $0.icon = icon } }
                iconTarget = nil
            }
        }
        .alert("Link", isPresented: Binding(get: { linkTarget != nil }, set: { if !$0 { linkTarget = nil } })) {
            TextField("https://", text: $linkText)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Save") { commitLink() }
            if let id = linkTarget, map.root.node(id)?.link != nil {
                Button("Remove Link", role: .destructive) { mutate { $0.root.update(id) { $0.link = nil } } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The web page this idea points to.")
        }
        .fullScreenCover(item: $viewer) { item in ImageViewer(item: item) }
        .sheet(item: Binding(get: { styleNodeID.map(IdentifiedID.init) }, set: { styleNodeID = $0?.id })) { item in
            if let node = map.root.node(item.id) {
                NodeStyleSheet(
                    node: node,
                    isRoot: node.id == map.root.id,
                    effectiveColor: map.branchColor(for: node.id),
                    theme: theme,
                    onLook: { branch, change in applyLook(item.id, wholeBranch: branch, change) },
                    onColor: { color, branch in setColor(item.id, color, wholeBranch: branch) },
                    onPaste: { branch in pasteStyle(item.id, wholeBranch: branch) },
                    onReset: { branch in resetStyle(item.id, wholeBranch: branch) }
                )
                .presentationDetents([.medium, .large])
                .mapVisibleBehindSheet()
            }
        }
    }

    private func modifiers2<Content: View>(_ content: Content) -> some View {
        content
        .sheet(isPresented: $showDesign) {
            MapDesignSheet(
                map: map,
                theme: theme,
                onStyle: { setStyle($0) },
                onPalette: { value in setDesign { $0.palette = value == .vivid ? nil : value.rawValue } },
                onLines: { value in setDesign { $0.lines = value == .curved ? nil : value.rawValue } },
                onWeight: { value in setDesign { $0.lineWeight = value == .regular ? nil : value.rawValue } },
                onBackground: { value in setDesign { $0.canvas = value == .dots ? nil : value.rawValue } },
                onResetIdeas: resetAllStyles
            )
            .presentationDetents([.medium, .large])
            .mapVisibleBehindSheet()
        }
        .confirmationDialog(
            imageBatch.map { L("Create \($0.nodes.count) images?") } ?? "",
            isPresented: Binding(get: { imageBatch != nil }, set: { if !$0 { imageBatch = nil } }),
            titleVisibility: .visible,
            presenting: imageBatch
        ) { batch in
            Button(L("Create \(batch.nodes.count) Images")) { generateImages(batch.nodes, hint: batch.hint) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("One picture for each of these ideas. Each uses one of your monthly AI images.")
        }
        .confirmationDialog(
            linkMenu.map { $0.label.isEmpty ? L("Connection") : $0.label } ?? "",
            isPresented: Binding(get: { linkMenu != nil }, set: { if !$0 { linkMenu = nil } }),
            titleVisibility: .visible,
            presenting: linkMenu
        ) { link in
            Button(link.label.isEmpty ? L("Add Label") : L("Edit Label")) {
                linkLabelText = link.label
                linkLabelTarget = link.id
            }
            Button(L("Delete Connection"), role: .destructive) { deleteLink(link.id) }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Connection Label", isPresented: Binding(get: { linkLabelTarget != nil }, set: { if !$0 { linkLabelTarget = nil } })) {
            TextField("For example: depends on", text: $linkLabelText)
            Button("Save") { commitLinkLabel() }
            Button("Skip", role: .cancel) {}
        } message: {
            Text("A few words on the arrow, or leave it empty.")
        }
        .alert("Frame", isPresented: Binding(get: { frameTarget != nil }, set: { if !$0 { frameTarget = nil } })) {
            TextField("Frame label", text: $frameText)
            Button("Save") { commitFrame() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A frame groups this idea and everything below it.")
        }
        .alert("Rename", isPresented: $isRenaming) {
            TextField("New idea", text: $renameText)
            Button("Save") { commitRename() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(deleteNodeTitle, isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible, presenting: pendingDelete) { id in
            Button("Delete Node", role: .destructive) { deleteNode(id) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func modifiers3<Content: View>(_ content: Content) -> some View {
        content
        .confirmationDialog("Delete “\(map.title)”? This can’t be undone.", isPresented: $confirmDeleteMap, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                store.delete(map.id)
                onClose()
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showExport) {
            ExportSheetView(map: map, layout: MapLayout(map: map.fullyExpanded, balanced: mode == .balanced), theme: theme, onUpgrade: { pro in
                showExport = false
                onUpgrade(pro)
            })
        }
        .sheet(item: Binding(get: { cardNodeID.map(IdentifiedID.init) }, set: { cardNodeID = $0?.id }), onDismiss: {
            // Alerts, dialogs and the chat open only after the card is gone.
            let action = afterCard
            afterCard = nil
            action?()
        }) { item in
            NodeCardView(
                map: map,
                nodeID: item.id,
                theme: theme,
                onRename: { afterCard = { startRename(item.id) } },
                onSaveNote: { note in mutate { $0.root.update(item.id) { $0.note = note } } },
                onExpand: { hint in afterCard = { expand(item.id, hint: hint) } },
                onAsk: { afterCard = { AuthGate.shared.require { chatNodeID = item.id } } },
                onDelete: { afterCard = { requestDelete(item.id) } },
                onOpenImage: { afterCard = { openImage(item.id) } },
                onAddPhoto: { afterCard = { photoTarget = item.id; showNodePhotos = true } },
                onGenerateImage: { afterCard = { generateImage(for: item.id) } },
                onUpgrade: {
                    afterCard = { onUpgrade(false) }
                    cardNodeID = nil
                },
                readOnly: isViewer
            )
        }
        .sheet(isPresented: $showConsent, onDismiss: { afterConsent = nil }) {
            AIConsentView(
                onAllow: {
                    showConsent = false
                    let action = afterConsent
                    afterConsent = nil
                    action?()
                },
                onDecline: { showConsent = false }
            )
        }
        .fullScreenCover(item: Binding(get: { chatNodeID.map(IdentifiedID.init) }, set: { chatNodeID = $0?.id })) { item in
            NodeChatView(map: map, nodeID: item.id, theme: theme, initialPrompt: chatPrompt, onAddToMap: { titles in
                addChildren(titles, to: item.id)
            }, onUpgrade: {
                chatNodeID = nil
                onUpgrade(false)
            })
            .onDisappear { chatPrompt = nil }
        }
    }

    #if DEBUG
    // Launch arguments for screenshots: -demoSearch <text>, -demoFocus, -demoCard, -demoSelect.
    private func applyDebugState() {
        let args = ProcessInfo.processInfo.arguments
        let pricing = map.root.children.first { $0.link == "https://minorai.site/#pricing" }?.id
        if let i = args.firstIndex(of: "-demoSearch"), args.indices.contains(i + 1) {
            isSearching = true
            query = args[i + 1]
        }
        if args.contains("-demoFocus") { focusID = pricing }
        if args.contains("-demoSelect") { selection = pricing }
        if args.contains("-demoCard") { cardNodeID = pricing }
        if args.contains("-demoStudy") { showStudy = true }
        if args.contains("-demoCollab") { showCollab = true }
        if args.contains("-demoPresent") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                startPresentation()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { showSlide(5) }
            }
        }
        if args.contains("-demoFit") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                viewport = .fit(layout.size, in: UIScreen.main.bounds.size, insets: chromeInsets)
            }
        }
    }
    #endif

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 0) {
            Button(action: onClose) {
                Image(systemName: "house.fill")
                    .font(.system(size: 18))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Home")
            if !history.isEmpty && !isSearching && !isViewer {
                Button(action: undo) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 17))
                        .frame(width: 40, height: 44)
                }
                .accessibilityLabel("Undo")
                .transition(.opacity)
            }
            Spacer(minLength: 8)
            if isSearching {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 15)).foregroundColor(MinorColor.textTertiary)
                    TextField("", text: $query)
                        .placeholder(when: query.isEmpty) { Text("Search this map").foregroundColor(theme.placeholderText) }
                        .font(.system(size: 16))
                        .focused($searchFocused)
                        .submitLabel(.search)
                    if !trimmedQuery.isEmpty {
                        Text(matches.isEmpty ? "No results" : "\(matches.count)")
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                            .foregroundColor(MinorColor.textTertiary)
                            .accessibilityLabel(matches.isEmpty ? "No results" : "\(matches.count) results")
                    }
                    Button {
                        query = ""
                        isSearching = false
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(MinorColor.textTertiary)
                    }
                    .accessibilityLabel("Close search")
                }
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(RoundedRectangle(cornerRadius: 10).fill(theme.chatRectangle))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.chatStroke, lineWidth: 1))
            } else {
                VStack(spacing: 0) {
                    Text(map.title)
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(1)
                    Text(store.failedSaves.contains(mapID) ? "\(map.nodeCount) nodes · Not saved" : store.map(mapID)?.collab != nil ? (collab.busy.contains(mapID) ? "\(map.nodeCount) nodes · Syncing" : "\(map.nodeCount) nodes · Shared") : "\(map.nodeCount) nodes · Saved")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundColor(store.failedSaves.contains(mapID) ? MinorColor.dangerText : MinorColor.textTertiary)
                }
                Spacer(minLength: 8)
                Button { showExport = true } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Export Map")
                Menu {
                    if !isViewer {
                        Button { startRename(map.root.id) } label: { Label("Rename", systemImage: "pencil") }
                    }
                    Button {
                        isSearching = true
                        searchFocused = true
                    } label: { Label("Search", systemImage: "magnifyingglass") }
                    Picker("Layout", selection: $mode) {
                        Label("Tree", systemImage: "arrow.triangle.branch").tag(Mode.tree)
                        Label("Balanced", systemImage: "circle.grid.cross").tag(Mode.balanced)
                        Label("List", systemImage: "list.bullet").tag(Mode.list)
                    }
                    if !isViewer {
                        Button { showDesign = true } label: { Label("Map Design", systemImage: "paintpalette") }
                        Button { improveMap() } label: { Label("Improve with AI", systemImage: "wand.and.stars") }
                    }
                    Button { showStudy = true } label: { Label("Study", systemImage: "graduationcap") }
                    Button { onCreateDeck(mapID) } label: { Label("Create Presentation", systemImage: "rectangle.on.rectangle.angled") }
                    Button { showCollab = true } label: { Label("Edit Together", systemImage: "person.2") }
                    if !isViewer {
                        Button { showHistory = true } label: { Label("Version History", systemImage: "clock.arrow.circlepath") }
                    }
                    if !map.root.children.isEmpty {
                        Button { startPresentation() } label: { Label("Present", systemImage: "play.rectangle") }
                    }
                    if !history.isEmpty {
                        Button(action: undo) { Label("Undo", systemImage: "arrow.uturn.backward") }
                    }
                    Button { store.togglePin(mapID); map.isPinned.toggle() } label: {
                        Label(map.isPinned ? "Unpin" : "Pin", systemImage: map.isPinned ? "pin.slash" : "pin")
                    }
                    Button { duplicateMap() } label: {
                        Label("Duplicate", systemImage: "plus.square.on.square")
                    }
                    Button(role: .destructive) { confirmDeleteMap = true } label: { Label("Delete Map", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("More")
            }
        }
        .foregroundColor(MinorColor.textPrimary)
        .padding(.horizontal, 6)
        .frame(height: 44)
        // While AI changes the map, only Home stays available.
        .disabled(isApplying)
        .overlay(alignment: .leading) {
            if isApplying {
                Button(action: onClose) { Color.clear.frame(width: 50, height: 44).contentShape(Rectangle()) }
                    .accessibilityLabel("Home")
            }
        }
        .animation(.minorMenu, value: isSearching)
        .animation(.minorMenu, value: history.isEmpty)
    }

    private func linkingChip(_ node: MindNode) -> some View {
        Button {
            withAnimation(.minorMenu) { linkingFrom = nil }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.turn.up.right.diamond").font(.system(size: 14))
                Text("Tap the idea to connect with “\(node.title)”").font(.system(size: 14)).lineLimit(1)
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
            }
            .foregroundColor(.black)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(MinorColor.accent))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cancel connecting")
    }

    private func focusChip(_ node: MindNode) -> some View {
        Button {
            withAnimation(.minorMenu) { focusID = nil }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "scope").font(.system(size: 14))
                Text("Focus: \(node.title)").font(.system(size: 14)).lineLimit(1)
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
            }
            .foregroundColor(MinorColor.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(theme.chatRectangle))
            .overlay(Capsule().stroke(theme.chatStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Leave focus on \(node.title)")
    }

    // MARK: - Bottom area

    private var bottomArea: some View {
        VStack(spacing: 10) {
            if let banner {
                HStack(spacing: 10) {
                    Text(banner.text)
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if banner.isLimit {
                        Button(AccountStore.shared.effectivePlan == .plus ? "Get PRO" : "Get Minor Plus") { onUpgrade(false) }
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Button { self.banner = nil } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .bold)) }
                        .accessibilityLabel("Dismiss")
                }
                .foregroundColor(MinorColor.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12).fill(MinorColor.danger.opacity(0.25)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(MinorColor.danger.opacity(0.6), lineWidth: 1))
                .transition(.opacity)
            }
            if let toast {
                HStack(spacing: 12) {
                    Text(toast.text).font(.system(size: 15))
                    if let action = toast.action, action == actionCount, !history.isEmpty {
                        Button("Undo") { undo() }.font(.system(size: 15, weight: .semibold))
                    }
                }
                .foregroundColor(MinorColor.textPrimary)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background(Capsule().fill(theme.chatRectangle))
                .overlay(Capsule().stroke(theme.chatStroke, lineWidth: 1))
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if isViewer {
                HStack(spacing: 8) {
                    Label("View only", systemImage: "eye")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(MinorColor.textSecondary)
                        .padding(.horizontal, 16)
                        .frame(height: 40)
                        .background(Capsule().fill(theme.chatRectangle))
                        .overlay(Capsule().stroke(theme.chatStroke, lineWidth: 1))
                        .accessibilityLabel(L("View only: the owner can make you an editor"))
                    // A viewer still reads an idea's note, link and picture.
                    if let node = selectedNode, !node.isSuggestion {
                        Button { cardNodeID = node.id } label: {
                            Label("Details", systemImage: "text.alignleft")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.black)
                                .padding(.horizontal, 16)
                                .frame(height: 40)
                                .background(Capsule().fill(MinorColor.accent))
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: selectedNode?.id)
            } else {
            Group {
                if let node = selectedNode, node.isSuggestion {
                    suggestionActions(for: node)
                } else if let node = selectedNode {
                    actionBar(for: node)
                } else if map.root.suggestionCount > 0 {
                    suggestionBar
                } else {
                    toolChips
                }
            }
            .transition(.opacity.combined(with: .offset(y: 8)))
            .disabled(isApplying)
            .opacity(isApplying ? 0.5 : 1)

            composer
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .animation(.minorMenu, value: selection)
        .animation(.minorMenu, value: banner)
        .animation(.minorMenu, value: toast)
    }

    private var toolChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("Node", "plus") { addChild(to: map.root.id) }
                chip("Improve", "wand.and.stars") { improveMap() }
                chip(mode == .list ? "Map" : "List", mode == .list ? "arrow.triangle.branch" : "list.bullet") {
                    withAnimation(.minorSheet) { mode = mode == .list ? .tree : .list }
                }
                if mode != .list {
                    chip("Fit", "arrow.up.left.and.arrow.down.right") {
                        withAnimation(.minorFit) {
                            viewport = .fit(layout.size, in: UIScreen.main.bounds.size, insets: chromeInsets)
                        }
                    }
                }
                chip("Search", "magnifyingglass") {
                    isSearching = true
                    searchFocused = true
                }
                chip("Design", "paintpalette") { showDesign = true }
                chip("Study", "graduationcap") { showStudy = true }
                chip("Slides", "rectangle.on.rectangle.angled") { onCreateDeck(mapID) }
                if !map.root.children.isEmpty {
                    chip("Present", "play.rectangle") { startPresentation() }
                }
                chip("Export", "square.and.arrow.up") { showExport = true }
            }
        }
    }

    // Improve Map's ideas wait here until the person keeps or drops them.
    private var suggestionBar: some View {
        let count = map.root.suggestionCount
        return HStack(spacing: 8) {
            Image(systemName: "lightbulb.fill").foregroundColor(MinorColor.accent)
            Text(L("Suggestions: \(count)"))
                .font(.system(size: 15, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Button { dismissAllSuggestions() } label: {
                Text("Dismiss All")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(MinorColor.textPrimary)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .overlay(Capsule().stroke(theme.chatStroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
            Button { acceptAllSuggestions() } label: {
                Text("Accept All")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(Capsule().fill(MinorColor.accent))
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(height: 48)
        .background(Capsule().fill(theme.chatRectangle))
        .overlay(Capsule().stroke(theme.chatStroke, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private func suggestionActions(for node: MindNode) -> some View {
        HStack(spacing: 6) {
            Button { acceptSuggestion(node.id) } label: {
                Label("Accept", systemImage: "checkmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(Capsule().fill(MinorColor.accent))
            }
            .buttonStyle(.plain)
            Button { dismissSuggestion(node.id) } label: {
                Label("Dismiss", systemImage: "xmark")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(MinorColor.textPrimary)
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .overlay(Capsule().stroke(theme.chatStroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
            barButton("pencil", "Edit") { startRename(node.id) }
            Spacer(minLength: 0)
            Text(L("\(map.root.suggestionCount) left"))
                .font(.system(size: 13).monospacedDigit())
                .foregroundColor(MinorColor.textTertiary)
                .padding(.trailing, 10)
        }
        .padding(4)
        .background(Capsule().fill(theme.chatRectangle))
        .overlay(Capsule().stroke(theme.chatStroke, lineWidth: 1))
    }

    private func chip(_ title: LocalizedStringKey, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 15))
                Text(title).font(.system(size: 14))
            }
            .foregroundColor(MinorColor.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(theme.chatStroke, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func actionBar(for node: MindNode) -> some View {
        let isRoot = node.id == map.root.id
        let siblings = map.root.parent(of: node.id)?.children ?? []
        let index = siblings.firstIndex { $0.id == node.id } ?? 0
        return HStack(spacing: 4) {
            Button {
                isRoot ? expandAll() : expand(node.id)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.system(size: 15, weight: .semibold))
                    Text(isRoot ? "Expand All" : "Expand").font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(Capsule().fill(MinorColor.sendFill))
            }
            .disabled(generating.contains(node.id))
            barButton("bubble.left", "Ask") { AuthGate.shared.require { chatNodeID = node.id } }
            barButton("pencil", "Edit") { startRename(node.id) }
            barButton("paintbrush", "Style") { styleNodeID = node.id }
            if isRoot {
                barButton("text.alignleft", "Details") { cardNodeID = node.id }
            } else {
                if !node.children.isEmpty {
                    barButton(node.isCollapsed ? "plus.circle" : "minus.circle", node.isCollapsed ? "Expand Branch" : "Collapse") {
                        toggleCollapse(node.id)
                    }
                }
            }
            Rectangle().fill(theme.chatStroke).frame(width: 1, height: 24)
            Menu {
                Button { cardNodeID = node.id } label: { Label("Details & Note", systemImage: "text.alignleft") }
                Button { addChild(to: node.id) } label: { Label("Add Child", systemImage: "arrow.turn.down.right") }
                Section {
                    Button { iconTarget = node.id } label: {
                        Label(node.icon == nil ? "Add Icon" : "Change Icon", systemImage: "face.smiling")
                    }
                    if !isRoot {
                        Button { toggleTask(node.id) } label: {
                            Label(node.isTask ? "Remove Checkbox" : "Make It a Task", systemImage: "checkmark.circle")
                        }
                    }
                    if !isRoot {
                        Button { dueTarget = node.id } label: {
                            Label(node.due == nil ? "Add Due Date" : "Due \(DueLabel.text(for: node.due!))", systemImage: "calendar")
                        }
                    }
                    Menu {
                        Picker("Priority", selection: Binding(get: { node.priority ?? 0 }, set: { setPriority(node.id, $0) })) {
                            Text("None").tag(0)
                            Text("1 · High").tag(1)
                            Text("2 · Medium").tag(2)
                            Text("3 · Low").tag(3)
                        }
                    } label: { Label("Priority", systemImage: "flag") }
                    Button { startLinkEdit(node.id) } label: {
                        Label(node.link == nil ? "Add Link" : "Edit Link", systemImage: "link")
                    }
                    if !isRoot {
                        Button { toggleCallout(node.id) } label: {
                            Label(node.isCallout ? "Show as Idea" : "Show as Callout", systemImage: "quote.opening")
                        }
                    }
                }
                Section {
                    Button { photoTarget = node.id; showNodePhotos = true } label: {
                        Label(node.image == nil ? "Add Photo" : "Replace Photo", systemImage: "photo")
                    }
                    Button { generateImage(for: node.id) } label: { Label("Create Image with AI", systemImage: "wand.and.stars") }
                    if node.image != nil {
                        Button(role: .destructive) { removeImage(node.id) } label: { Label("Remove Image", systemImage: "photo.badge.minus") }
                    }
                }
                Section {
                    Button { startLinking(from: node.id) } label: {
                        Label("Connect to Another Idea", systemImage: "arrow.triangle.turn.up.right.diamond")
                    }
                    if !isRoot {
                        Button { startFrameEdit(node.id) } label: {
                            Label(node.frame == nil ? "Add Frame" : "Edit Frame", systemImage: "rectangle.dashed")
                        }
                        if node.frame != nil {
                            Button(role: .destructive) { mutate { $0.root.update(node.id) { $0.frame = nil } } } label: {
                                Label("Remove Frame", systemImage: "rectangle.slash")
                            }
                        }
                    }
                }
                if !isRoot {
                    Button { addSibling(of: node.id) } label: { Label("Add Sibling", systemImage: "plus") }
                    Button { withAnimation(.minorMenu) { focusID = node.id } } label: { Label("Focus on Branch", systemImage: "scope") }
                    if index > 0 {
                        Button { reorder(node.id, by: -1) } label: { Label("Move Up", systemImage: "arrow.up") }
                    }
                    if index < siblings.count - 1 {
                        Button { reorder(node.id, by: 1) } label: { Label("Move Down", systemImage: "arrow.down") }
                    }
                    Button(role: .destructive) { requestDelete(node.id) } label: { Label("Delete Node", systemImage: "trash") }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20))
                    .foregroundColor(MinorColor.textPrimary)
                    .frame(width: 40, height: 40)
            }
            .accessibilityLabel("More")
        }
        .padding(4)
        .background(Capsule().fill(theme.chatRectangle))
        .overlay(Capsule().stroke(theme.chatStroke, lineWidth: 1))
    }

    private func barButton(_ icon: String, _ label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 19))
                .foregroundColor(MinorColor.textPrimary)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("", text: $command)
                .placeholder(when: command.isEmpty) {
                    Text(isApplying ? "Changing the map…" : "Change this map, or ask a question").foregroundColor(theme.placeholderText)
                }
                .foregroundColor(MinorColor.textPrimary)
                .font(.system(size: 17))
                .focused($commandFocused)
                .submitLabel(.send)
                .onSubmit(applyCommand)
                .disabled(isApplying)
            Button(action: applyCommand) {
                Group {
                    if isApplying {
                        ProgressView().tint(.black)
                    } else {
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
    }

    // MARK: - Mutations

    // Every change starts from the stored map, so results that arrive late (AI expand, edits)
    // build on the newest version, and nothing is written for a map that was deleted.
    // A viewer of a shared map: they can fold branches on their phone but not change the map.
    private var isViewer: Bool { store.map(mapID)?.collab?.role == .viewer }

    private func blockedForViewer() -> Bool {
        guard isViewer else { return false }
        Haptics.error()
        showToast(L("View only: the owner can make you an editor"), canUndo: false)
        return true
    }

    private func mutate(animated: Bool = true, undoable: Bool = true, personal: Bool = false, _ change: (inout MindMap) -> Void) {
        if !personal && blockedForViewer() { return }
        guard let base = store.map(mapID) else { return }
        var copy = base
        change(&copy)
        copy.dropBrokenLinks()
        guard copy.root != base.root || copy.links != base.links else { return }
        if undoable {
            history.append(Snapshot(root: base.root, links: base.links))
            if history.count > 40 { history.removeFirst() }
            actionCount += 1
        }
        // Local state first, so the store's change notification finds nothing new to adopt.
        if animated {
            withAnimation(.minorNode) {
                map.root = copy.root
                map.links = copy.links
            }
        } else {
            map.root = copy.root
            map.links = copy.links
        }
        let links = copy.links
        store.update(mapID) {
            $0.root = copy.root
            $0.links = links
        }
        sanitize()
        relayout(animated: animated)
    }

    private func undo() {
        if blockedForViewer() { return }
        guard !isApplying, let snapshot = history.popLast(), store.map(mapID) != nil else { return }
        actionCount += 1
        Haptics.impact(.light)
        toast = nil
        withAnimation(.minorNode) {
            map.root = snapshot.root
            map.links = snapshot.links
        }
        store.update(mapID) {
            $0.root = snapshot.root
            $0.links = snapshot.links
        }
        sanitize()
        relayout()
    }

    // MARK: - Presentation

    private var slideBranches: [UUID] { map.root.children.filter { !$0.isSuggestion }.map(\.id) }

    private var currentSlideBranch: UUID? {
        slide > 0 && slide <= slideBranches.count ? slideBranches[slide - 1] : nil
    }

    private var slideInsets: EdgeInsets { EdgeInsets(top: 130, leading: 20, bottom: 150, trailing: 20) }

    private func startPresentation() {
        if mode == .list { mode = .tree }
        selection = nil
        focusID = nil
        isSearching = false
        presenting = true
        showSlide(0)
    }

    private func endPresentation() {
        presenting = false
        selection = nil
        relayout()
        withAnimation(.minorFit) {
            viewport = .fit(layout.size, in: UIScreen.main.bounds.size, insets: chromeInsets)
        }
    }

    private func showSlide(_ index: Int) {
        slide = min(max(index, 0), slideBranches.count)
        relayout()
        let screen = UIScreen.main.bounds.size
        guard let id = currentSlideBranch else {
            selection = nil
            withAnimation(.minorFit) { viewport = .fit(layout.size, in: screen, insets: slideInsets) }
            return
        }
        // The camera moves to the branch; the light runs through it.
        let rect = layout.branch(of: id).map(\.node.frame).reduce(layout.node(id)?.frame ?? .zero) { $0.union($1) }
        withAnimation(.spring(response: 0.8, dampingFraction: 0.9)) {
            viewport = .fit(rect: rect, in: screen, insets: slideInsets, maxScale: 1.6)
        }
        selection = id
        Haptics.selection()
    }

    private var presentationControls: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { endPresentation() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(theme.chatRectangle))
                        .overlay(Circle().stroke(theme.chatStroke, lineWidth: 1))
                }
                .accessibilityLabel("End Presentation")
                VStack(alignment: .leading, spacing: 2) {
                    Text(currentSlideBranch.flatMap { map.root.node($0) }.map(MindMap.outlineText) ?? map.title)
                        .font(.system(size: 20, weight: .bold))
                        .lineLimit(2)
                    Text(L("\(slide + 1) of \(slideBranches.count + 1)"))
                        .font(.system(size: 13).monospacedDigit())
                        .foregroundColor(MinorColor.textTertiary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 24)
            .background(
                LinearGradient(colors: [theme.background, theme.background.opacity(0.85), theme.background.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea(edges: .top)
            )
            Spacer()
            HStack(spacing: 12) {
                Button { showSlide(slide - 1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 64, height: 54)
                        .background(Capsule().fill(theme.chatRectangle))
                        .overlay(Capsule().stroke(theme.chatStroke, lineWidth: 1))
                }
                .disabled(slide == 0)
                .opacity(slide == 0 ? 0.4 : 1)
                .accessibilityLabel("Previous")
                Button {
                    slide >= slideBranches.count ? endPresentation() : showSlide(slide + 1)
                } label: {
                    Text(slide >= slideBranches.count ? L("Finish") : slide == 0 ? L("Start") : L("Next"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Capsule().fill(MinorColor.accent))
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .foregroundColor(MinorColor.textPrimary)
        .gesture(DragGesture(minimumDistance: 40).onEnded { value in
            guard abs(value.translation.width) > abs(value.translation.height) else { return }
            value.translation.width < 0 ? showSlide(slide + 1) : showSlide(slide - 1)
        }, including: .subviews)
    }

    // MARK: - Connections and frames

    private func startLinking(from id: UUID) {
        linkingFrom = id
        selection = nil
        Haptics.selection()
        UIAccessibility.post(notification: .announcement, argument: L("Tap the idea to connect"))
    }

    private func finishLinking(to id: UUID) {
        guard let from = linkingFrom else { return }
        linkingFrom = nil
        guard from != id, map.root.node(from) != nil else { return }
        if let existing = map.links.first(where: { Set([$0.from, $0.to]) == Set([from, id]) }) {
            linkMenu = existing
            return
        }
        let link = MapLink(from: from, to: id)
        mutate { $0.links.append(link) }
        Haptics.success()
        linkLabelText = ""
        linkLabelTarget = link.id
    }

    private func commitLinkLabel() {
        guard let id = linkLabelTarget else { return }
        let text = String(linkLabelText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        mutate {
            guard let index = $0.links.firstIndex(where: { $0.id == id }) else { return }
            $0.links[index].label = text
        }
    }

    private func deleteLink(_ id: UUID) {
        mutate { $0.links.removeAll { $0.id == id } }
        showToast(L("Connection removed"), canUndo: true)
    }

    private func startFrameEdit(_ id: UUID) {
        frameText = map.root.node(id)?.frame ?? ""
        frameTarget = id
    }

    private func commitFrame() {
        guard let id = frameTarget else { return }
        let text = String(frameText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        mutate { $0.root.update(id) { $0.frame = text } }
    }

    // Drops references to ideas that no longer exist (after undo, delete or an AI edit).
    private func sanitize() {
        if let id = selection, map.root.node(id) == nil { selection = nil }
        if let id = focusID, map.root.node(id) == nil { focusID = nil }
        if let id = cardNodeID, map.root.node(id) == nil { cardNodeID = nil }
        if let id = chatNodeID, map.root.node(id) == nil { chatNodeID = nil }
        if let id = pendingDelete, map.root.node(id) == nil { pendingDelete = nil }
        if let id = renameTarget, map.root.node(id) == nil { renameTarget = nil; isRenaming = false }
    }

    // The sparkle on AI ideas goes away once the person has looked at them. Not an edit:
    // no undo step and no new "updated" date.
    private func clearAIMark(_ id: UUID) {
        guard map.root.node(id)?.isAIAdded == true else { return }
        map.root.update(id) { $0.isAIAdded = false }
        store.update(mapID, touch: false) { $0.root.update(id) { $0.isAIAdded = false } }
        relayout(animated: false)
    }

    // MARK: - Node details

    private func toggleDone(_ id: UUID) {
        Haptics.selection()
        mutate { $0.root.update(id) { $0.isDone.toggle() } }
    }

    private func toggleTask(_ id: UUID) {
        mutate { $0.root.update(id) { node in
            node.isTask.toggle()
            if !node.isTask { node.isDone = false }
        } }
    }

    private func setPriority(_ id: UUID, _ value: Int) {
        mutate { $0.root.update(id) { $0.priority = value == 0 ? nil : value } }
    }

    private func toggleCallout(_ id: UUID) {
        mutate { $0.root.update(id) { $0.isCallout.toggle() } }
    }

    private func setStyle(_ style: MapStyle) {
        map.style = style == .classic ? nil : style.rawValue
        store.update(mapID, touch: false) { $0.style = map.style }
    }

    // Map Design: palette, lines and background belong to the map, not to undo history.
    private func setDesign(_ change: (inout MindMap) -> Void) {
        change(&map)
        let design = map
        store.update(mapID, touch: false) {
            $0.palette = design.palette
            $0.lines = design.lines
            $0.lineWeight = design.lineWeight
            $0.canvas = design.canvas
        }
        relayout()
    }

    // Style panel: a change to one idea, or to it and every idea below it.
    private func applyLook(_ id: UUID, wholeBranch: Bool, _ change: @escaping (inout NodeLook) -> Void) {
        func apply(_ node: inout MindNode) {
            var look = node.look ?? NodeLook()
            change(&look)
            node.look = look.isDefault ? nil : look
            if wholeBranch { for index in node.children.indices { apply(&node.children[index]) } }
        }
        mutate { $0.root.update(id) { apply(&$0) } }
    }

    // A color carries on to the ideas below; for the whole branch their own colors are cleared.
    private func setColor(_ id: UUID, _ color: BranchColor?, wholeBranch: Bool) {
        func clear(_ node: inout MindNode) {
            node.color = nil
            for index in node.children.indices { clear(&node.children[index]) }
        }
        mutate {
            $0.root.update(id) { node in
                node.color = color
                if wholeBranch { for index in node.children.indices { clear(&node.children[index]) } }
            }
        }
    }

    private func pasteStyle(_ id: UUID, wholeBranch: Bool) {
        guard let copied = StyleClipboard.copied else { return }
        func apply(_ node: inout MindNode) {
            node.look = copied.look
            if wholeBranch { for index in node.children.indices { apply(&node.children[index]) } }
        }
        mutate {
            $0.root.update(id) { node in
                apply(&node)
                if let color = copied.color { node.color = color }
            }
        }
        Haptics.success()
    }

    private func resetStyle(_ id: UUID, wholeBranch: Bool) {
        func reset(_ node: inout MindNode) {
            node.look = nil
            if wholeBranch {
                for index in node.children.indices {
                    node.children[index].color = nil
                    reset(&node.children[index])
                }
            }
        }
        mutate { $0.root.update(id) { reset(&$0) } }
    }

    private func resetAllStyles() {
        func reset(_ node: inout MindNode, level: Int) {
            node.look = nil
            if level > 1 || level == 0 { node.color = nil }
            for index in node.children.indices { reset(&node.children[index], level: level + 1) }
        }
        mutate { reset(&$0.root, level: 0) }
        showToast(L("Styles reset"), canUndo: true)
    }

    private func startLinkEdit(_ id: UUID) {
        linkText = map.root.node(id)?.link ?? ""
        linkTarget = id
    }

    private func commitLink() {
        guard let id = linkTarget else { return }
        var text = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if !text.lowercased().hasPrefix("http") { text = "https://" + text }
        guard let url = URL(string: text), url.host != nil else {
            showToast(L("That doesn’t look like a web address."), canUndo: false)
            return
        }
        mutate { $0.root.update(id) { $0.link = url.absoluteString } }
    }

    private func setPhoto(_ data: Data, for id: UUID) {
        guard let picture = store.storeImage(data, isAI: false) else {
            return showToast(L("Couldn’t add this photo."), canUndo: false)
        }
        mutate { $0.root.update(id) { $0.image = picture } }
        flash([id])
    }

    private func removeImage(_ id: UUID) {
        mutate { $0.root.update(id) { $0.image = nil } }
        showToast(L("Image removed"), canUndo: true)
    }

    // An AI picture for an idea, drawn from the map's topic and the idea's path (plus an optional hint).
    private func generateImage(for id: UUID, hint: String = "") {
        guard AuthService.shared.isSignedIn, AIConsent.isGiven else { return withConsent { generateImage(for: id, hint: hint) } }
        Task { _ = await createImage(for: id, hint: hint) }
    }

    // Pictures the AI picked ideas for: one right away, several after the person sees the count.
    private func illustrate(_ titles: [String], hint: String, fallback: UUID?) {
        var ids = Self.nodes(titled: titles, in: map.root)
        if ids.isEmpty { ids = [fallback.flatMap { map.root.node($0) == nil ? nil : $0 } ?? map.root.id] }
        if ids.count == 1 {
            generateImage(for: ids[0], hint: hint)
        } else {
            imageBatch = ImageBatch(nodes: Array(ids.prefix(8)), hint: hint)
        }
    }

    static func nodes(titled titles: [String], in root: MindNode) -> [UUID] {
        root.ids(titled: titles)
    }

    // Pictures for several ideas, one after another (image models allow few requests a minute).
    // Stops at the first failure, such as the monthly image limit.
    private func generateImages(_ ids: [UUID], hint: String = "") {
        guard AuthService.shared.isSignedIn, AIConsent.isGiven else { return withConsent { generateImages(ids, hint: hint) } }
        Task {
            for id in ids {
                guard await createImage(for: id, hint: hint) else { break }
            }
        }
    }

    // Returns false when it failed (the error is shown).
    private func createImage(for id: UUID, hint: String) async -> Bool {
        guard !generating.contains(id), let path = map.root.path(to: id) else { return true }
        generating.insert(id)
        defer { generating.remove(id) }
        let context = AIService.NodeContext(mapTitle: map.title, path: path.map(\.title))
        do {
            let data = try await AIService.shared.generateImage(prompt: hint, context: context)
            guard store.map(mapID)?.root.node(id) != nil, let picture = store.storeImage(data, isAI: true) else { return true }
            mutate { $0.root.update(id) { $0.image = picture } }
            flash([id])
            Haptics.success()
            return true
        } catch is CancellationError {
            return false
        } catch {
            show(error)
            return false
        }
    }

    // Opens a node's picture full screen; AI pictures can be reported (and are then removed).
    func openImage(_ id: UUID) {
        guard let picture = map.root.node(id)?.image, let image = store.image(picture.id) else { return }
        let path = map.root.path(to: id)?.map(\.title).joined(separator: " > ") ?? ""
        let viewOnly = isViewer
        viewer = ViewerItem(image: image, isAI: picture.isAI, onReport: picture.isAI ? {
            // A viewer's report goes for review; the picture can't be removed from a map they only view.
            if !viewOnly { mutate(undoable: false) { $0.root.update(id) { $0.image = nil } } }
            Task { try? await AIService.shared.report(kind: "image", content: path, reason: "reported on a map") }
        } : nil)
    }

    private func toggleCollapse(_ id: UUID) {
        Haptics.impact(.light)
        mutate(undoable: false, personal: true) { $0.root.update(id) { $0.isCollapsed.toggle() } }
    }

    private func startRename(_ id: UUID) {
        if blockedForViewer() { return }
        guard let node = map.root.node(id) else { return }
        renameTarget = id
        renameText = node.title
        isRenaming = true
    }

    private func commitRename() {
        let text = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = renameTarget, !text.isEmpty else { return }
        mutate { $0.root.update(id) { $0.title = String(text.prefix(80)) } }
    }

    private func addChild(to id: UUID) {
        let child = MindNode(title: L("New idea"))
        mutate {
            $0.root.update(id) { node in
                node.isCollapsed = false
                node.children.append(child)
            }
        }
        selection = child.id
        startRename(child.id)
        renameText = ""
    }

    private func addSibling(of id: UUID) {
        guard let parent = map.root.parent(of: id) else { return }
        let sibling = MindNode(title: L("New idea"))
        mutate {
            $0.root.update(parent.id) { node in
                let index = node.children.firstIndex { $0.id == id }.map { $0 + 1 } ?? node.children.count
                node.children.insert(sibling, at: index)
            }
        }
        selection = sibling.id
        startRename(sibling.id)
        renameText = ""
    }

    private func reorder(_ id: UUID, by offset: Int) {
        guard let parent = map.root.parent(of: id) else { return }
        mutate {
            $0.root.update(parent.id) { node in
                guard let index = node.children.firstIndex(where: { $0.id == id }) else { return }
                let target = index + offset
                guard node.children.indices.contains(target) else { return }
                node.children.swapAt(index, target)
            }
        }
    }

    // Drag and drop: the node (with its branch) becomes the last child of `parentID`.
    private func move(_ id: UUID, under parentID: UUID) {
        guard !isApplying, id != map.root.id, id != parentID,
              map.root.node(parentID) != nil,
              let moving = map.root.node(id), moving.node(parentID) == nil,
              map.root.parent(of: id)?.id != parentID
        else { return }
        mutate {
            guard var moved = $0.root.remove(id) else { return }
            if parentID != $0.root.id { moved.color = nil }
            $0.root.update(parentID) { node in
                node.isCollapsed = false
                node.children.append(moved)
            }
        }
        flash([id])
        showToast(L("Moved"), canUndo: true)
    }

    private var deleteNodeTitle: String {
        let count = pendingDelete.flatMap { map.root.node($0) }.map { $0.count - 1 } ?? 0
        return L("Delete this node and its \(count) \(count == 1 ? "child" : "children")?")
    }

    private func requestDelete(_ id: UUID) {
        guard let node = map.root.node(id) else { return }
        if node.children.isEmpty {
            deleteNode(id)
        } else {
            pendingDelete = id
        }
    }

    private func deleteNode(_ id: UUID) {
        selection = nil
        pendingDelete = nil
        if focusID == id || (focusID.map { map.root.node(id)?.node($0) != nil } ?? false) { focusID = nil }
        mutate { $0.root.remove(id) }
        showToast(L("Node deleted"), canUndo: true)
    }

    private func addChildren(_ titles: [String], to id: UUID) {
        let nodes = titles.map { MindNode(title: String($0.prefix(80)), isAIAdded: true) }
        guard !nodes.isEmpty else { return }
        mutate {
            $0.root.update(id) { node in
                node.isCollapsed = false
                node.children += nodes
            }
        }
        flash(Set(nodes.map(\.id)))
    }

    // Keeps the selected node above the bottom panel and below the top bar, with the ideas below
    // it in view too when the whole branch fits on screen.
    private func reveal(_ id: UUID) {
        guard mode != .list, let node = layout.node(id) else { return }
        let screen = UIScreen.main.bounds.size
        let visible = CGRect(x: 16, y: 120, width: screen.width - 32, height: screen.height - 120 - 190)
        let branch = layout.branch(of: id).map(\.node.frame).reduce(node.frame) { $0.union($1) }
        let target = branch.width * viewport.scale <= visible.width && branch.height * viewport.scale <= visible.height ? branch : node.frame
        let frame = CGRect(
            x: viewport.offset.width + target.minX * viewport.scale,
            y: viewport.offset.height + target.minY * viewport.scale,
            width: target.width * viewport.scale,
            height: target.height * viewport.scale
        )
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        if frame.maxY > visible.maxY { dy = visible.maxY - frame.maxY }
        if frame.minY < visible.minY { dy = visible.minY - frame.minY }
        if frame.maxX > visible.maxX { dx = visible.maxX - frame.maxX }
        if frame.minX < visible.minX { dx = visible.minX - frame.minX }
        guard dx != 0 || dy != 0 else { return }
        withAnimation(.minorFit) {
            viewport.offset.width += dx
            viewport.offset.height += dy
        }
    }

    // MARK: - AI

    // AI needs an account (asked for first) and the one-time consent.
    private func withConsent(_ action: @escaping () -> Void) {
        guard AuthService.shared.isSignedIn else {
            return AuthGate.shared.require { withConsent(action) }
        }
        if AIConsent.isGiven {
            action()
        } else {
            afterConsent = action
            showConsent = true
        }
    }

    private func expand(_ id: UUID, hint: ExpandHint = .more) {
        if blockedForViewer() { return }
        guard AuthService.shared.isSignedIn, AIConsent.isGiven else { return withConsent { expand(id, hint: hint) } }
        guard !generating.contains(id), let node = map.root.node(id) else { return }
        if node.isCollapsed { toggleCollapse(id) }
        generating.insert(id)
        let snapshot = map
        Task {
            do {
                let found = try await MapService.shared.expand(snapshot, node: id, hint: hint)
                generating.remove(id)
                // Skip ideas the node already got meanwhile (another expand or a manual add).
                let existing = Set((store.map(mapID)?.root.node(id)?.children ?? []).map { $0.title.lowercased() })
                let children = found.filter { !existing.contains($0.title.lowercased()) }
                guard !children.isEmpty, store.map(mapID)?.root.node(id) != nil else { return }
                mutate {
                    $0.root.update(id) { node in
                        node.isCollapsed = false
                        node.children += children
                    }
                }
                flash(Set(children.map(\.id)))
                Haptics.success()
            } catch is CancellationError {
                generating.remove(id)
            } catch {
                generating.remove(id)
                show(error)
            }
        }
    }

    // Expands every main branch (or the root itself while it has none), asking for consent once.
    private func expandAll() {
        guard AuthService.shared.isSignedIn, AIConsent.isGiven else { return withConsent(expandAll) }
        if map.root.children.isEmpty {
            expand(map.root.id)
        } else {
            for branch in map.root.children { expand(branch.id) }
        }
    }

    private func applyCommand() {
        if blockedForViewer() { return }
        let text = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isApplying else { return }
        // The AI reads the command in whatever wording: a change to the map, pictures for some
        // ideas, or a question for the chat about the map.
        guard AuthService.shared.isSignedIn, AIConsent.isGiven else { return withConsent(applyCommand) }
        // The command rewrites the map from a snapshot; ideas still being added would be lost.
        guard generating.isEmpty else {
            showToast(L("Wait until the new ideas are added"), canUndo: false)
            return
        }
        commandFocused = false
        command = ""
        isApplying = true
        let snapshot = map
        let selected = selection
        Task {
            defer { isApplying = false }
            do {
                let result = try await MapService.shared.edit(snapshot, command: text, selected: selected.flatMap { snapshot.root.node($0)?.title })
                let edited: APINode
                switch result {
                case .map(let tree):
                    edited = tree
                case .images(let titles, let prompt):
                    return illustrate(titles, hint: prompt, fallback: selected)
                case .question:
                    let node = selected.flatMap { map.root.node($0) == nil ? nil : $0 } ?? map.root.id
                    chatPrompt = text
                    chatNodeID = node
                    return
                }
                guard let current = store.map(mapID) else { return }
                let root = current.root.merged(with: edited)
                guard root != current.root else {
                    showToast(L("Nothing to change"), canUndo: false)
                    return
                }
                let oldIDs = Self.ids(in: current.root) { _ in true }
                mutate { $0.root = root }
                flash(Self.ids(in: root) { !oldIDs.contains($0.id) })
                showToast(L("Map updated"), canUndo: true)
                Haptics.success()
            } catch is CancellationError {
                command = text
            } catch {
                command = text
                show(error)
            }
        }
    }

    // A copy is a new map: it counts toward the month's maps like a template.
    private func duplicateMap() {
        guard AuthService.shared.isSignedIn else { return AuthGate.shared.require { duplicateMap() } }
        if AccountStore.shared.isOverFreeLimit { return onUpgrade(false) }
        Task {
            do {
                try await MapService.shared.countNewMap()
                AccountStore.shared.noteMapCreated()
                _ = store.duplicate(mapID)
                showToast(L("Duplicated"), canUndo: false)
            } catch BackendError.limitReached(let kind) {
                AccountStore.shared.noteLimitReached(kind: kind)
                onUpgrade(false)
            } catch {
                show(error)
            }
        }
    }

    // MARK: - Suggestions

    // Improve Map: the AI proposes what is missing; its ideas appear as suggestions to keep or drop.
    private func improveMap() {
        if blockedForViewer() { return }
        guard !isApplying else { return }
        guard AuthService.shared.isSignedIn, AIConsent.isGiven else { return withConsent(improveMap) }
        guard generating.isEmpty else {
            showToast(L("Wait until the new ideas are added"), canUndo: false)
            return
        }
        selection = nil
        isApplying = true
        let snapshot = map
        Task {
            defer { isApplying = false }
            do {
                let tree = try await MapService.shared.improve(snapshot)
                guard let current = store.map(mapID) else { return }
                let (root, added) = current.root.grafting(additionsFrom: tree)
                guard added > 0 else {
                    showToast(L("The map already looks complete"), canUndo: false)
                    return
                }
                let oldIDs = Set(MindNode.allIDs(in: current.root))
                mutate { $0.root = root }
                flash(Self.ids(in: root) { !oldIDs.contains($0.id) })
                Haptics.success()
                UIAccessibility.post(notification: .announcement, argument: L("Suggestions: \(added)"))
            } catch is CancellationError {
            } catch {
                show(error)
            }
        }
    }

    private func acceptSuggestion(_ id: UUID) {
        Haptics.selection()
        mutate { $0.root.accept(id) }
        selection = nextSuggestion(after: id)
    }

    private func dismissSuggestion(_ id: UUID) {
        Haptics.impact(.light)
        let next = nextSuggestion(after: id)
        mutate { $0.root.remove(id) }
        selection = next
    }

    // The next suggestion in map order, so they can be gone through one by one.
    private func nextSuggestion(after id: UUID) -> UUID? {
        var order: [MindNode] = []
        func walk(_ node: MindNode) { order.append(node); node.children.forEach(walk) }
        walk(map.root)
        let start = order.firstIndex { $0.id == id } ?? 0
        let after = order[(start + 1)...].first { $0.isSuggestion && $0.id != id && map.root.node(id)?.node($0.id) == nil }
        return (after ?? order.first { $0.isSuggestion && $0.id != id && map.root.node(id)?.node($0.id) == nil })?.id
    }

    private func acceptAllSuggestions() {
        let count = map.root.suggestionCount
        mutate { $0.root.acceptAll() }
        showToast(L("Added \(count) ideas"), canUndo: true)
        Haptics.success()
    }

    private func dismissAllSuggestions() {
        mutate { $0.root.dismissAll() }
        showToast(L("Suggestions dismissed"), canUndo: true)
    }

    private func flash(_ ids: Set<UUID>) {
        flashed.formUnion(ids)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeOut(duration: 0.4)) { flashed.subtract(ids) }
        }
    }

    private func showToast(_ text: String, canUndo: Bool) {
        let new = Toast(text: text, action: canUndo ? actionCount : nil)
        UIAccessibility.post(notification: .announcement, argument: text)
        toast = new
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if toast == new { toast = nil }
        }
    }

    private func show(_ error: Error) {
        Haptics.error()
        if case BackendError.limitReached(let kind) = error { AccountStore.shared.noteLimitReached(kind: kind) }
        if case BackendError.modelLocked = error { return onUpgrade(true) }
        let isLimit = (error as? BackendError)?.suggestsUpgrade ?? false
        let text = (error as? LocalizedError)?.errorDescription ?? L("Something went wrong. Try again.")
        banner = Banner(text: text, isLimit: isLimit)
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    static func ids(in node: MindNode, where match: (MindNode) -> Bool) -> Set<UUID> {
        var result: Set<UUID> = match(node) ? [node.id] : []
        for child in node.children { result.formUnion(ids(in: child, where: match)) }
        return result
    }
}

struct IdentifiedID: Identifiable {
    let id: UUID
}

// List layout: the same map as an indented outline, for quick reading and VoiceOver.
struct MapOutlineView: View {
    let map: MindMap
    let theme: AppTheme
    @Binding var selection: UUID?
    var visible: Set<UUID>? = nil
    var highlighted: Set<UUID> = []

    private func shows(_ node: MindNode) -> Bool { visible?.contains(node.id) ?? true }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(map.title)
                    .font(.system(size: 22, weight: .bold))
                    .padding(.bottom, 6)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(map.root.children.enumerated()), id: \.element.id) { index, branch in
                    let color = branch.color ?? BranchColor.forBranch(at: index)
                    if shows(branch) {
                        VStack(alignment: .leading, spacing: 6) {
                            row(branch, level: 1, color: color)
                            ForEach(flatten(branch.children, level: 2).filter { shows($0.0) }, id: \.0.id) { node, level in
                                row(node, level: level, color: color)
                            }
                        }
                        .padding(.bottom, 8)
                    }
                }
                if visible?.isEmpty == true {
                    Text("No ideas match your search.")
                        .font(.system(size: 15))
                        .foregroundColor(MinorColor.textSecondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 110)
            .padding(.bottom, 200)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundColor(MinorColor.textPrimary)
        .background(theme.background)
    }

    // Icon, checkbox and title as one line of the outline.
    static func rowTitle(_ node: MindNode) -> String {
        var text = node.title
        if let icon = node.icon { text = "\(icon) \(text)" }
        if node.isTask { text = (node.isDone ? "☑︎ " : "☐ ") + text }
        if node.isSuggestion { text = "💡 " + text }
        return text
    }

    private func flatten(_ nodes: [MindNode], level: Int) -> [(MindNode, Int)] {
        nodes.flatMap { [($0, level)] + flatten($0.children, level: level + 1) }
    }

    @ViewBuilder
    private func row(_ node: MindNode, level: Int, color: BranchColor) -> some View {
        let isSelected = selection == node.id
        Button {
            Haptics.selection()
            selection = node.id
        } label: {
            if level == 1 {
                Text(Self.rowTitle(node))
                    .font(.system(size: 16, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(theme.chatRectangle).overlay(RoundedRectangle(cornerRadius: 12).fill(color.tint)))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected || highlighted.contains(node.id) ? Color.white : color.line, lineWidth: isSelected ? 1.5 : 1))
            } else {
                HStack(spacing: 10) {
                    Rectangle().fill(color.line).frame(width: 1.5)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.rowTitle(node))
                            .font(.system(size: 15))
                            .multilineTextAlignment(.leading)
                        if !node.note.isEmpty {
                            Text(node.note)
                                .font(.system(size: 13))
                                .foregroundColor(MinorColor.textSecondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .padding(.leading, CGFloat(level - 2) * 20 + 14)
                .background(isSelected || highlighted.contains(node.id) ? theme.chatRectangle : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(node.title), level \(level)\(node.note.isEmpty ? "" : L(", has note"))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
