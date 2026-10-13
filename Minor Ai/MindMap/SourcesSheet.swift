//
//  SourcesSheet.swift
//  Minor Ai
//
//  Sources: where the ideas of a map (or of one idea and its branch) come from. Materials are
//  the documents, recordings, links, notes and chats kept with the project; AI Ideas are what Minor
//  suggested, waiting for a decision or kept by the person. Nothing is drawn on the nodes. An idea
//  shows the exact passage it came from only when the AI named one that checks out against the
//  saved material (Citation); then its page, scan line or time opens in the kept original. No page,
//  quote or time is ever made up: otherwise it says the material is linked without an exact place.
//

import SwiftUI

struct SourcesSheet: View {
    enum Tab: Hashable { case materials, ideas }

    let mapID: UUID
    let theme: AppTheme
    let canEdit: Bool
    @State var scope: UUID?            // nil: the whole map
    var selected: UUID?                // the idea selected on the map, offered as a scope
    var onShow: (UUID) -> Void         // closes Sources and selects the idea on the map
    var onAccept: (UUID) -> Void
    var onDismissSuggestion: (UUID) -> Void
    var onAsk: (UUID) -> Void
    var onAddMaterial: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @ObservedObject private var store = MapStore.shared
    @ObservedObject private var materials = ProjectMaterialStore.shared
    @ObservedObject private var account = AccountStore.shared
    @ObservedObject private var network = NetworkMonitor.shared
    @State private var tab: Tab = .materials
    @State private var path: [SourceRoute] = []
    @State private var detent: PresentationDetent = .medium
    @State private var deleting: ProjectMaterial?
    @State private var removingOriginal: ProjectMaterial?
    @State private var attaching: UUID?          // the material an original is being attached to
    @State private var notice: String?
    @State private var offline: URL?

    private var map: MindMap? { store.map(mapID) }
    private var all: [ProjectMaterial] { materials.materials(for: mapID) }
    private var scopeNode: MindNode? { scope.flatMap { map?.root.node($0) } }
    private var isShared: Bool { map?.collab != nil }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    MinorSegments(items: [(Tab.materials, "Materials", nil), (Tab.ideas, "AI Ideas", nil)], selection: $tab, height: 38)
                    if let notice {
                        Label(notice, systemImage: "info.circle")
                            .minorFont(13, maxScale: 1.3)
                            .foregroundColor(MinorColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let map {
                        switch tab {
                        case .materials: materialsTab(map)
                        case .ideas: ideasTab(map)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
            }
            .foregroundColor(MinorColor.textPrimary)
            .background(MinorColor.editorSheet.ignoresSafeArea())
            .navigationTitle(Text("Sources"))
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: SourceRoute.self) { route in
                SourceViewer(mapID: mapID, route: route, theme: theme) { nodeID in
                    onShow(nodeID)
                    dismiss()
                }
            }
        }
        .tint(.white)
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large], selection: $detent)
        // A page, a recording or a text opens at full height.
        .onChange(of: path.isEmpty) { empty in if !empty { detent = .large } }
        .confirmationDialog(deleting.map { L("Remove “\($0.title)” from the project?") } ?? "", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible, presenting: deleting) { item in
            Button("Remove Material", role: .destructive) { materials.remove(item.id, from: mapID) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The ideas made from it stay on the map; they will show that their source isn’t available.")
        }
        .confirmationDialog(removingOriginal.map { L("Remove the original of “\($0.title)”?") } ?? "", isPresented: Binding(get: { removingOriginal != nil }, set: { if !$0 { removingOriginal = nil } }), titleVisibility: .visible, presenting: removingOriginal) { item in
            Button("Remove Original", role: .destructive) { materials.removeOriginal(of: item.id, in: mapID) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Its pages or recording can’t be opened afterwards. The ideas and their quotes stay.")
        }
        .alert(L("No connection. The link opens once you’re online."), isPresented: Binding(get: { offline != nil }, set: { if !$0 { offline = nil } }), presenting: offline) { url in
            Button("Try Again") { open(url) }
            Button("OK", role: .cancel) {}
        }
        .onChange(of: map == nil) { gone in if gone { dismiss() } }
        #if DEBUG
        .onAppear {
            // -demoSourceViewer: opens the first cited passage of the idea in scope.
            guard ProcessInfo.processInfo.arguments.contains("-demoSourceViewer"), let id = scope,
                  let first = materials.citations(of: id, in: mapID).first else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                path.append(SourceRoute(materialID: first.material.id, segmentID: first.citation.segmentIDs.first, nodeID: id))
            }
        }
        #endif
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sources")
                    .minorFont(21, .bold, style: .title2, maxScale: 1.3)
                    .accessibilityAddTraits(.isHeader)
                Menu {
                    Button { scope = nil } label: { Label("Whole Map", systemImage: "point.3.connected.trianglepath.dotted") }
                    if let id = selected ?? scope, let node = map?.root.node(id), id != map?.root.id {
                        Button { scope = id } label: { Label(L("Idea “\(node.title)”"), systemImage: "scope") }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(scopeNode.map { L("Idea “\($0.title)”") } ?? L("Whole map"))
                            .minorFont(14, maxScale: 1.3)
                            .lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(MinorColor.textSecondary)
                }
                .accessibilityLabel(L("Showing: \(scopeNode.map { L("Idea “\($0.title)”") } ?? L("Whole map"))"))
            }
            Spacer(minLength: 8)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(MinorColor.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.white.opacity(0.1)))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close")
        }
    }

    // MARK: - Materials

    @ViewBuilder
    private func materialsTab(_ map: MindMap) -> some View {
        if let node = scopeNode {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle(L("This idea"))
                originCard(node, map: map)
            }
            let below = materialsBelow(node)
            if !below.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle(L("Ideas below it also come from"))
                    ForEach(below, id: \.material.id) { item in
                        materialRow(item.material, ideas: item.count)
                    }
                }
            }
            Button { scope = nil } label: {
                Text("All Project Materials")
                    .minorFont(14, .medium, maxScale: 1.3)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(PressScale())
        } else {
            if all.isEmpty {
                if let source = map.source, source.kind != .topic {
                    legacyRow(source)
                } else {
                    emptyState(L("No materials yet"), L("Documents, links and notes you add to this project appear here, with the ideas that came from them."))
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(all) { material in
                        materialRow(material, ideas: map.root.count(from: .material(material.id)))
                    }
                }
            }
            if canEdit {
                Button(action: onAddMaterial) {
                    Label("Add Material", systemImage: "plus")
                        .minorFont(14, .medium, maxScale: 1.3)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(PressScale())
            }
        }
        footnote("lock", isShared
                 ? L("Your materials and their originals stay on this iPhone. People you share the map with don’t see them.")
                 : L("Your materials and their originals stay on this iPhone. Sharing the map doesn’t share them."))
    }

    // Where one idea came from, said plainly.
    @ViewBuilder
    private func originCard(_ node: MindNode, map: MindMap) -> some View {
        switch node.origin {
        case .material(let id)?:
            if let material = all.first(where: { $0.id == id }) {
                citationCard(material, node: node)
            } else {
                infoCard("questionmark.folder", L("Source isn’t available"), L("The material isn’t on this iPhone: it was removed, or added on another device or by someone you share the map with."))
            }
        case .ai?:
            infoCard("sparkles", L("Suggestion from Minor"), L("An interpretation, not a quote or a checked fact. It’s on the map because it was kept."), action: (L("See AI Ideas"), { tab = .ideas }))
        case .person?:
            infoCard("hand.point.up", isShared ? L("Added by hand") : L("Added by you"), L("Not taken from a material."))
        case .template?:
            infoCard("square.grid.2x2", L("From a template"), L("Part of the template the map started from."))
        case nil:
            infoCard("clock", L("Source not recorded"), L("This idea is from before Minor kept sources. That doesn’t mean it was made by AI."))
        }
    }

    // The material an idea comes from, with each passage it cites and where it is.
    private func citationCard(_ material: ProjectMaterial, node: MindNode) -> some View {
        let citations = material.citations(of: node.id)
        return VStack(alignment: .leading, spacing: 12) {
            materialHeader(material, ideas: nil)
            if citations.isEmpty {
                Label("The material is linked to this idea. The exact passage isn’t given.", systemImage: "link")
                    .minorFont(13, maxScale: 1.3)
                    .foregroundColor(MinorColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                actions(material, segment: nil, node: node)
            }
            ForEach(citations) { citation in
                citationView(citation, material: material, node: node)
            }
            originalNotice(material)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func citationView(_ citation: Citation, material: ProjectMaterial, node: MindNode) -> some View {
        if citation.version != material.version {
            VStack(alignment: .leading, spacing: 6) {
                Label("The passage needs a check: the material was replaced with another version.", systemImage: "exclamationmark.triangle")
                    .minorFont(13, maxScale: 1.3)
                    .foregroundColor(BranchColor.sun.color)
                    .fixedSize(horizontal: false, vertical: true)
                if !citation.excerpt.isEmpty { quote(citation.excerpt, dimmed: true) }
                actions(material, segment: nil, node: node)
            }
        } else if citation.status == .unverified {
            VStack(alignment: .leading, spacing: 6) {
                Label("Minor named a passage this material doesn’t have, so none is shown.", systemImage: "questionmark.circle")
                    .minorFont(13, maxScale: 1.3)
                    .foregroundColor(MinorColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                actions(material, segment: nil, node: node)
            }
        } else {
            let passages = citation.segmentIDs.compactMap { material.segment($0) }.filter { material.fits($0) }
            ForEach(passages) { passage in
                VStack(alignment: .leading, spacing: 6) {
                    if let place = locator(passage, material: material) {
                        Text(place)
                            .minorFont(12, .semibold, style: .caption1, maxScale: 1.3)
                            .foregroundColor(MinorColor.textTertiary)
                    }
                    quote(passage.text, dimmed: false)
                    if passage.isUncertain {
                        Label("Recognized with doubts: check it in the original.", systemImage: "exclamationmark.triangle")
                            .minorFont(12, maxScale: 1.3)
                            .foregroundColor(BranchColor.sun.color)
                    }
                    actions(material, segment: passage, node: node)
                }
            }
        }
    }

    private func quote(_ text: String, dimmed: Bool) -> some View {
        Text("«\(text)»")
            .minorFont(14, maxScale: 1.3)
            .foregroundColor(dimmed ? MinorColor.textTertiary : MinorColor.textSecondary)
            .lineLimit(5)
            .fixedSize(horizontal: false, vertical: true)
    }

    // "Page 4", "Page 4 · page “iv” in print" is shown in the viewer; "2:14–2:28"; "Video · 2:14".
    private func locator(_ passage: SourceSegment, material: ProjectMaterial) -> String? {
        if let page = passage.page {
            return material.kind == .scan ? L("Scan · page \(page + 1)") : L("Page \(page + 1)")
        }
        if let start = passage.start {
            let end = passage.end ?? start
            return end - start >= 1 ? "\(SourceTime.text(start))–\(SourceTime.text(end))" : SourceTime.text(start)
        }
        if material.extractedAt != nil, material.kind == .link {
            return L("Saved text of the page")
        }
        return nil
    }

    // What can be opened from here: the page, the recording at the passage, the video at its time,
    // the saved text; a website or a video opens outside the app.
    @ViewBuilder
    private func actions(_ material: ProjectMaterial, segment: SourceSegment?, node: MindNode?) -> some View {
        let route = SourceRoute(materialID: material.id, segmentID: segment?.id, nodeID: node?.id)
        let original = material.originalStatus == .available ? material.original : nil
        HStack(spacing: 16) {
            if let original, original.isPDF {
                link(segment?.page != nil ? (material.kind == .scan ? L("Open Scan") : L("Open Page")) : L("Open Original"), "doc.richtext") { path.append(route) }
            } else if let original, original.isAudio {
                link(segment?.start != nil ? L("Listen to the Passage") : L("Listen"), "play.circle") { path.append(route) }
            } else if material.text?.isEmpty == false {
                link(segment != nil ? L("Open at This Place") : L("Open Material"), "arrow.up.right") { path.append(route) }
            }
            if let link = material.url {
                if material.kind == .youtube {
                    let at = segment?.start
                    self.link(at.map { L("Video at \(SourceTime.text($0))") } ?? L("Open Video"), "play.rectangle") {
                        if let url = VideoLink.url(link, at: at) { open(url) }
                    }
                } else if let url = URL(string: link) {
                    self.link(L("Open Website"), "safari") { open(url) }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func link(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .minorFont(14, .semibold, maxScale: 1.3)
                .foregroundColor(MinorColor.accent)
                .frame(minHeight: 32)
        }
        .buttonStyle(.plain)
    }

    private func open(_ url: URL) {
        guard network.isOnline else { return offline = url }
        openURL(url)
    }

    // The original's state, when there is something to say or do about it.
    @ViewBuilder
    private func originalNotice(_ material: ProjectMaterial) -> some View {
        switch material.originalStatus {
        case .missing:
            notice("exclamationmark.triangle", L("The original isn’t available on this iPhone. The saved quotes stay."), action: canEdit && material.canAttachOriginal ? (L("Attach Again"), { attach(material) }) : nil)
        case .removed:
            notice("trash", L("The original was removed. The saved quotes stay."), action: canEdit && material.canAttachOriginal ? (L("Attach Original"), { attach(material) }) : nil)
        case .none:
            if material.canAttachOriginal {
                notice("doc.text", L("Only the text is saved."), action: canEdit ? (L("Attach Original"), { attach(material) }) : nil)
            }
        case .available:
            EmptyView()
        }
        if attaching == material.id {
            HStack(spacing: 8) {
                ProgressView().tint(.white)
                Text("Reading the file…").minorFont(13, maxScale: 1.3).foregroundColor(MinorColor.textSecondary)
            }
        }
    }

    private func notice(_ icon: String, _ text: String, action: (String, () -> Void)?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(text, systemImage: icon)
                .minorFont(13, maxScale: 1.3)
                .foregroundColor(MinorColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            if let action {
                link(action.0, "paperclip", action: action.1).disabled(attaching != nil)
            }
        }
    }

    private func materialHeader(_ material: ProjectMaterial, ideas: Int?) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: Self.icon(material.kind))
                .font(.system(size: 22))
                .frame(width: 56, height: 56)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.1), lineWidth: 1))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(material.title)
                    .minorFont(15, .semibold, maxScale: 1.3)
                    .lineLimit(2)
                Text(Self.detail(material, ideas: ideas))
                    .minorFont(13, maxScale: 1.3)
                    .foregroundColor(MinorColor.textTertiary)
                    .lineLimit(2)
                if material.originalStatus == .available {
                    Text(material.original?.isAudio == true ? L("Recording on this iPhone") : L("Original on this iPhone"))
                        .minorFont(12, maxScale: 1.3)
                        .foregroundColor(MinorColor.accent)
                }
            }
            Spacer(minLength: 0)
            if canEdit {
                Menu {
                    if material.canAttachOriginal {
                        Button { attach(material) } label: {
                            Label(material.originalStatus == .available ? L("Attach Another Version") : L("Attach Original"), systemImage: "paperclip")
                        }
                    }
                    if material.originalStatus == .available {
                        Button(role: .destructive) { removingOriginal = material } label: { Label("Remove Original", systemImage: "doc.badge.minus") }
                    }
                    Button(role: .destructive) { deleting = material } label: { Label("Remove Material", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(Text("More for \(material.title)"))
            }
        }
    }

    private func materialRow(_ material: ProjectMaterial, ideas: Int?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            materialHeader(material, ideas: ideas)
            actions(material, segment: nil, node: nil)
            originalNotice(material)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    // Another file for a material: the same content keeps its citations; a different one is a new
    // version, and its earlier citations are shown as needing a check.
    private func attach(_ material: ProjectMaterial) {
        guard attaching == nil else { return }
        let isPaid = account.isPaid
        DocumentPicker.present { url in
            attaching = material.id
            notice = nil
            Task {
                defer { attaching = nil }
                do {
                    let (updated, result) = try await SourceImport.attach(url, to: material, isPaid: isPaid)
                    materials.update(material.id, in: mapID) { $0 = updated }
                    materials.cleanOriginals()
                    notice = result == .sameContent
                        ? L("Original attached.")
                        : L("This file differs from the saved text: it is a new version, and earlier passages are marked for a check.")
                    Haptics.success()
                } catch {
                    notice = (error as? LocalizedError)?.errorDescription ?? Attachments.message(for: error, isPaid: isPaid)
                    if error is Attachments.DocumentError { notice = Attachments.message(for: error, isPaid: isPaid) }
                }
            }
        }
    }

    private func legacyRow(_ source: MapSource) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: Self.icon(source.kind))
                .font(.system(size: 22))
                .frame(width: 56, height: 56)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
            VStack(alignment: .leading, spacing: 4) {
                Text(source.label).minorFont(15, .semibold, maxScale: 1.3).lineLimit(2)
                Text("The map was made from it before Minor kept materials, so its text isn’t saved.")
                    .minorFont(13, maxScale: 1.3)
                    .foregroundColor(MinorColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
    }

    // Materials the ideas under `node` come from (other than the idea's own), most used first.
    private func materialsBelow(_ node: MindNode) -> [(material: ProjectMaterial, count: Int)] {
        var counts: [UUID: Int] = [:]
        func walk(_ item: MindNode) {
            if let id = item.origin?.materialID { counts[id, default: 0] += 1 }
            item.children.forEach(walk)
        }
        node.children.forEach(walk)
        if let own = node.origin?.materialID { counts[own] = nil }
        return all.compactMap { material in counts[material.id].map { (material, $0) } }.sorted { $0.count > $1.count }
    }

    // MARK: - AI Ideas

    @ViewBuilder
    private func ideasTab(_ map: MindMap) -> some View {
        let root = scopeNode ?? map.root
        let ideas = Self.aiIdeas(in: root)
        if ideas.isEmpty {
            emptyState(L("No ideas from Minor here"), L("When Minor suggests ideas (Expand, Improve, the chat), they are listed here, apart from your materials."))
        } else {
            VStack(spacing: 10) {
                ForEach(ideas, id: \.node.id) { item in
                    ideaRow(item.node, path: item.path)
                }
            }
        }
        footnote("info.circle", L("“Suggestion from Minor” is an interpretation, not a quote or a checked fact. Keeping one is your choice."))
    }

    private func ideaRow(_ node: MindNode, path: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                onShow(node.id)
                dismiss()
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(LinearGradient(colors: [BranchColor.lilac.color, BranchColor.sky.color], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        if !path.isEmpty {
                            Text(path.joined(separator: " › "))
                                .minorFont(13, style: .footnote, maxScale: 1.3)
                                .foregroundColor(MinorColor.textTertiary)
                                .lineLimit(1)
                        }
                        Text(node.title).minorFont(14, .medium, maxScale: 1.3).lineLimit(3).multilineTextAlignment(.leading)
                        Text(node.isSuggestion ? L("Waiting for your decision") : L("Kept by you"))
                            .minorFont(13, style: .footnote, maxScale: 1.3)
                            .foregroundColor(node.isSuggestion ? BranchColor.sun.color : MinorColor.textTertiary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundColor(MinorColor.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Shows the idea on the map"))
            if node.isSuggestion && canEdit {
                HStack(spacing: 8) {
                    Button { onAccept(node.id) } label: {
                        Label("Keep", systemImage: "checkmark")
                            .minorFont(14, .semibold, maxScale: 1.3)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(Capsule().fill(MinorColor.accent))
                    }
                    .buttonStyle(PressScale())
                    Button { onDismissSuggestion(node.id) } label: {
                        Label("Decline", systemImage: "xmark")
                            .minorFont(14, .medium, maxScale: 1.3)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(PressScale())
                    Button {
                        onAsk(node.id)
                        dismiss()
                    } label: {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 15))
                            .frame(width: 44, height: 40)
                            .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(PressScale())
                    .accessibilityLabel("Discuss")
                }
                .padding(.leading, 36)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    // Minor's ideas under `root`: those waiting for a decision first, then the kept ones, in map order.
    static func aiIdeas(in root: MindNode) -> [(node: MindNode, path: [String])] {
        var pending: [(MindNode, [String])] = []
        var kept: [(MindNode, [String])] = []
        func walk(_ node: MindNode, path: [String]) {
            for child in node.children {
                if child.isSuggestion {
                    pending.append((child, path + [node.title]))
                    continue   // its children are part of the same suggestion
                }
                if child.origin == .ai { kept.append((child, path + [node.title])) }
                walk(child, path: path + [node.title])
            }
        }
        walk(root, path: [])
        return (pending + kept).map { (node: $0.0, path: Array($0.1.suffix(2))) }
    }

    // MARK: - Pieces

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .textCase(.uppercase)
            .minorFont(12, .semibold, style: .caption1, maxScale: 1.3)
            .foregroundColor(MinorColor.textTertiary)
    }

    private func infoCard(_ icon: String, _ title: String, _ detail: String, action: (String, () -> Void)? = nil) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .frame(width: 56, height: 56)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).minorFont(15, .semibold, maxScale: 1.3)
                Text(detail)
                    .minorFont(13, maxScale: 1.3)
                    .foregroundColor(MinorColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                if let action {
                    Button(action: action.1) {
                        Text(action.0).minorFont(14, .semibold, maxScale: 1.3).foregroundColor(MinorColor.accent)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func emptyState(_ title: String, _ detail: String) -> some View {
        VStack(spacing: 6) {
            Text(title).minorFont(15, .semibold, maxScale: 1.3)
            Text(detail)
                .minorFont(13, maxScale: 1.3)
                .foregroundColor(MinorColor.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func footnote(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).font(.system(size: 15))
            Text(text)
                .minorFont(13, style: .footnote, maxScale: 1.4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundColor(MinorColor.textTertiary)
    }

    static func icon(_ kind: MapSource.Kind) -> String {
        switch kind {
        case .document: return "doc.text"
        case .link: return "link"
        case .youtube: return "play.rectangle"
        case .voice: return "waveform"
        case .chat: return "bubble.left.and.bubble.right"
        case .scan: return "doc.viewfinder"
        case .topic: return "text.cursor"
        }
    }

    static func kindName(_ kind: MapSource.Kind) -> String {
        switch kind {
        case .document: return L("Document")
        case .link: return L("Web page")
        case .youtube: return L("Video")
        case .voice: return L("Voice note")
        case .chat: return L("Chat")
        case .scan: return L("Scan")
        case .topic: return L("Text")
        }
    }

    // "PDF · Pages: 12 · Ideas from it: 9", "Voice note · 4:08", "Web page · read Oct 12".
    static func detail(_ material: ProjectMaterial, ideas: Int?) -> String {
        var parts = [material.original?.isPDF == true && material.kind == .document ? "PDF" : kindName(material.kind)]
        if let pages = material.pages, pages > 1 { parts.append(L("Pages: \(pages)")) }
        if let duration = material.duration, duration > 0 { parts.append(SourceTime.text(duration)) }
        if let date = material.extractedAt {
            parts.append(L("read \(date.formatted(.dateTime.day().month(.abbreviated).locale(AppLanguage.current.locale)))"))
        } else if material.original == nil, let text = material.text, !text.isEmpty {
            parts.append(L("Characters: \(text.count)"))
        }
        if let ideas { parts.append(L("Ideas from it: \(ideas)")) }
        return parts.joined(separator: " · ")
    }
}
