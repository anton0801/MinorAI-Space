//
//  AddMaterialSheet.swift
//  Minor Ai
//
//  Add Material to an existing project: a file, a scan, a link or pasted text. Minor reads it and
//  proposes new ideas under the ideas they belong to; the map changes only when the person adds
//  them. The material can also just be saved, without changing the map. A failed attempt keeps the
//  material, and trying again never adds it twice. A file or scan is kept as the material's original
//  (when that fails, the text still is, and the sheet says so); new ideas cite its passages.
//

import PhotosUI
import SwiftUI

struct AddMaterialSheet: View {
    let mapID: UUID
    let theme: AppTheme
    var onApply: (_ material: ProjectMaterial, _ additions: [MaterialAddition]) -> Void
    var onSaveOnly: (_ material: ProjectMaterial) -> Void
    var onUpgrade: () -> Void

    private enum Stage: Equatable { case pick, ready, reading, preview, failed }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var maps = MapStore.shared
    @ObservedObject private var account = AccountStore.shared
    @State private var stage: Stage = .pick
    @State private var input: MapInput?
    @State private var material: ProjectMaterial?
    @State private var draftKey: String?      // the text its draft is held under, until saved or dropped
    @State private var saved = false
    @State private var keepText = true
    @State private var additions: [MaterialAddition] = []
    @State private var chosen: Set<UUID> = []
    @State private var truncated = false
    @State private var message: String?
    @State private var isLimit = false
    @State private var loadingFile = false
    @State private var task: Task<Void, Never>?
    // Pickers
    @State private var showScanChoice = false
    @State private var showScanner = false
    @State private var showPhotos = false
    @State private var photos: [PhotosPickerItem] = []
    @State private var askLink = false
    @State private var link = ""
    @State private var pasting = false
    @State private var pasted = ""
    @FocusState private var pasteFocused: Bool

    private var map: MindMap? { maps.map(mapID) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if let material {
                    materialCard(material)
                } else if pasting {
                    pasteField
                } else {
                    sourcePicker
                }
                if let message, stage != .preview {
                    notice(message)
                }
                switch stage {
                case .pick: EmptyView()
                case .ready: readyActions
                case .reading: reading
                case .preview: preview
                case .failed: readyActions
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .foregroundColor(MinorColor.textPrimary)
        .background(MinorColor.editorSheet.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onDisappear {
            task?.cancel()
            releaseDraft()
        }
        #if DEBUG
        .onAppear {
            // -demoAddMaterial: a document read and its suggested additions, without a network.
            guard ProcessInfo.processInfo.arguments.contains("-demoAddMaterial"), material == nil, let map else { return }
            let ru = AppLanguage.current.locale.identifier.hasPrefix("ru")
            material = ProjectMaterial(kind: .document, title: ru ? "Исследование рынка.pdf" : "Market research.pdf", text: String(repeating: "x", count: 18_400), pages: 6)
            func addition(_ parent: Int, _ title: String, _ inside: [String] = []) -> MaterialAddition {
                let branch = map.root.children[parent]
                return MaterialAddition(parentID: branch.id, parentPath: [map.root.title, branch.title], node: MindNode(title: title, children: inside.map { MindNode(title: $0) }))
            }
            additions = [
                addition(0, ru ? "Преподаватели" : "Teachers"),
                addition(2, ru ? "Семейный тариф" : "Family plan", ru ? ["До 5 человек"] : ["Up to 5 people"]),
                addition(3, ru ? "Партнёрства с вузами" : "University partnerships"),
            ]
            chosen = Set(additions.prefix(2).map(\.id))
            stage = .preview
        }
        #endif
        .confirmationDialog("Scan", isPresented: $showScanChoice, titleVisibility: .hidden) {
            if DocumentScanner.isAvailable { Button("Scan with Camera") { showScanner = true } }
            Button("Choose Photos") { showPhotos = true }
            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScanner { pages in
                showScanner = false
                readScans(pages)
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showPhotos, selection: $photos, maxSelectionCount: 10, matching: .images)
        .onChange(of: photos) { items in
            guard !items.isEmpty else { return }
            loadingFile = true
            Task {
                var pages: [UIImage] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = await Task.detached(priority: .userInitiated, operation: { Attachments.downsampled(data, maxPixels: 2_500) }).value {
                        pages.append(image)
                    }
                }
                photos = []
                readScans(pages)
            }
        }
        .alert("Link", isPresented: $askLink) {
            TextField("https://", text: $link)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Add") { useLink() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A web page or a YouTube video.")
        }
        .onChange(of: map == nil) { gone in if gone { dismiss() } }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Add Material")
                    .minorFont(24, .bold, style: .title2, maxScale: 1.3)
                    .accessibilityAddTraits(.isHeader)
                if let map {
                    HStack(spacing: 8) {
                        StructurePreview(kind: .tree).scaleEffect(0.8).frame(width: 30, height: 24)
                        Text(L("Into “\(map.title)”"))
                            .minorFont(14, maxScale: 1.3)
                            .foregroundColor(MinorColor.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 8)
            Button {
                task?.cancel()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.white.opacity(0.1)))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close")
        }
    }

    private var sourcePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What to add")
                .minorFont(15, .semibold, maxScale: 1.3)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                tile("doc.text", L("File"), L("PDF, TXT, RTF")) {
                    DocumentPicker.present { url in importDocument(url) }
                }
                tile("doc.viewfinder", L("Scan"), L("Camera or photos")) { showScanChoice = true }
                tile("link", L("Link"), L("Web page or video")) {
                    link = ""
                    askLink = true
                }
                tile("text.alignleft", L("Text"), L("Paste or type")) {
                    pasting = true
                    pasteFocused = true
                }
            }
            if loadingFile {
                HStack(spacing: 8) {
                    ProgressView().tint(MinorColor.textPrimary)
                    Text("Reading…").minorFont(14, maxScale: 1.3).foregroundColor(MinorColor.textSecondary)
                }
            }
        }
    }

    private func tile(_ icon: String, _ title: String, _ detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon).font(.system(size: 22))
                Text(title).minorFont(14, .semibold, maxScale: 1.3)
                Text(detail).minorFont(13, maxScale: 1.3).foregroundColor(MinorColor.textTertiary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(PressScale())
        .disabled(loadingFile)
    }

    private var pasteField: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                if pasted.isEmpty {
                    Text("Paste notes, an article or a transcript")
                        .minorFont(14, maxScale: 1.3)
                        .foregroundColor(theme.placeholderText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                }
                TextEditor(text: $pasted)
                    .focused($pasteFocused)
                    .scrollContentBackground(.hidden)
                    .minorFont(14, maxScale: 1.3)
                    .padding(10)
                    .frame(minHeight: 160)
            }
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12), lineWidth: 1))
            HStack(spacing: 10) {
                Button("Cancel") {
                    pasting = false
                    pasted = ""
                }
                .minorFont(14, maxScale: 1.3)
                .foregroundColor(MinorColor.textSecondary)
                Spacer()
                Button {
                    let text = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                    pasteFocused = false
                    let input = MapInput.text(text, source: MapSource(kind: .document, label: L("Pasted text")))
                    if let draft = SourceDrafts.shared.prepare(for: input) {
                        draftKey = text
                        use(input, ProjectMaterial(kind: .document, title: L("Pasted text"), draft: draft))
                    }
                    pasting = false
                } label: {
                    Text("Use This Text")
                        .minorFont(14, .semibold, maxScale: 1.3)
                        .foregroundColor(.black)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white))
                }
                .buttonStyle(PressScale())
                .disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).count < 40)
                .opacity(pasted.trimmingCharacters(in: .whitespacesAndNewlines).count < 40 ? 0.5 : 1)
            }
        }
    }

    private func materialCard(_ material: ProjectMaterial) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: SourcesSheet.icon(material.kind))
                .font(.system(size: 22))
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
            VStack(alignment: .leading, spacing: 3) {
                Text(material.title).minorFont(15, .semibold, maxScale: 1.3).lineLimit(2)
                Text(SourcesSheet.detail(material, ideas: nil))
                    .minorFont(13, maxScale: 1.3)
                    .foregroundColor(MinorColor.textTertiary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if stage != .reading {
                Button {
                    task?.cancel()
                    releaseDraft()
                    reset()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Remove Material")
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private var keepToggle: some View {
        VStack(alignment: .leading, spacing: 4) {
            if material?.text != nil {
                Toggle(isOn: $keepText) {
                    Text("Keep its text in Materials").minorFont(14, maxScale: 1.3)
                }
                .tint(MinorColor.accent)
                Text(keepText
                     ? L("You can reread it later in Sources. It stays on this iPhone.")
                     : L("Only the name is kept, so the text can’t be opened later."))
                    .minorFont(13, style: .footnote, maxScale: 1.4)
                    .foregroundColor(MinorColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var readyActions: some View {
        VStack(spacing: 12) {
            keepToggle
            Button(action: analyze) {
                Label("Find What It Adds", systemImage: "sparkles")
                    .minorFont(15, .semibold, maxScale: 1.3)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white))
            }
            .buttonStyle(PressScale())
            Button(action: saveOnly) {
                Text("Save Material Only")
                    .minorFont(14, maxScale: 1.3)
                    .foregroundColor(MinorColor.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            if isLimit {
                Button {
                    dismiss()
                    onUpgrade()
                } label: {
                    Text(account.effectivePlan == .plus ? "Get PRO" : "Get Minor Plus")
                        .minorFont(14, .semibold, maxScale: 1.3)
                        .foregroundColor(MinorColor.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var reading: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                ProgressView().tint(MinorColor.textPrimary)
                Text("Minor is reading the material and comparing it with the map…")
                    .minorFont(14, maxScale: 1.3)
                    .foregroundColor(MinorColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Cancel") {
                task?.cancel()
                stage = .ready
            }
            .minorFont(14, maxScale: 1.3)
            .foregroundColor(MinorColor.textSecondary)
        }
    }

    @ViewBuilder
    private var preview: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Suggested Changes").minorFont(16, .bold, maxScale: 1.3)
            Text(additions.isEmpty ? L("The map already has what this material says.") : L("Check them before adding. Nothing changes until you do."))
                .minorFont(13, maxScale: 1.3)
                .foregroundColor(MinorColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            if truncated {
                Text("A long material: Minor read its beginning.")
                    .minorFont(13, style: .footnote, maxScale: 1.3)
                    .foregroundColor(BranchColor.sun.color)
            }
        }
        if !additions.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(additions.enumerated()), id: \.element.id) { index, addition in
                    additionRow(addition)
                    if index < additions.count - 1 {
                        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1).padding(.leading, 62)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
        }
        keepToggle
        VStack(spacing: 10) {
            if !additions.isEmpty {
                Button {
                    guard let material = finalMaterial else { return }
                    saved = true
                    onApply(material, additions.filter { chosen.contains($0.id) })
                    dismiss()
                } label: {
                    Text(chosen.isEmpty ? L("Choose Ideas to Add") : L("Add to Project: \(chosenIdeas)"))
                        .minorFont(15, .semibold, maxScale: 1.3)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white))
                }
                .buttonStyle(PressScale())
                .disabled(chosen.isEmpty)
                .opacity(chosen.isEmpty ? 0.5 : 1)
            }
            Button(action: saveOnly) {
                Text("Save Material Only")
                    .minorFont(14, maxScale: 1.3)
                    .foregroundColor(MinorColor.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
        }
    }

    // Ideas the chosen additions bring, counting the ones inside them.
    private var chosenIdeas: Int {
        additions.filter { chosen.contains($0.id) }.reduce(0) { $0 + $1.node.count }
    }

    private func additionRow(_ addition: MaterialAddition) -> some View {
        let isChosen = chosen.contains(addition.id)
        return Button {
            Haptics.selection()
            if isChosen { chosen.remove(addition.id) } else { chosen.insert(addition.id) }
        } label: {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle().fill(isChosen ? MinorColor.accent : Color.clear)
                    Circle().stroke(isChosen ? Color.clear : MinorColor.textTertiary, lineWidth: 1.5)
                    Image(systemName: isChosen ? "plus" : "minus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(isChosen ? .black : MinorColor.textTertiary)
                }
                .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(addition.parentPath.suffix(2).joined(separator: " › "))
                        .minorFont(13, style: .footnote, maxScale: 1.3)
                        .foregroundColor(MinorColor.textTertiary)
                        .lineLimit(1)
                    Text(addition.node.title)
                        .minorFont(15, .semibold, maxScale: 1.3)
                        .foregroundColor(isChosen ? MinorColor.textPrimary : MinorColor.textTertiary)
                        .strikethrough(!isChosen, color: MinorColor.textTertiary)
                        .multilineTextAlignment(.leading)
                    if addition.node.count > 1 {
                        Text(L("Ideas inside: \(addition.node.count - 1)"))
                            .minorFont(13, style: .footnote, maxScale: 1.3)
                            .foregroundColor(MinorColor.textTertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(addition.node.title), \(L("under")) \(addition.parentPath.last ?? "")"))
        .accessibilityValue(isChosen ? L("Will be added") : L("Not added"))
        .accessibilityAddTraits(.isButton)
    }

    private func notice(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle").font(.system(size: 15))
            Text(text)
                .minorFont(13, maxScale: 1.3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundColor(MinorColor.dangerText)
    }

    // MARK: - Reading the material

    // Without its text, nothing of the material's content is kept: no passages, no original.
    private var finalMaterial: ProjectMaterial? {
        guard var material else { return nil }
        if !keepText {
            material.text = nil
            material.segments = nil
            material.original = nil
        }
        return material
    }

    // The draft's original is held only while the sheet decides; once saved or dropped it goes
    // (a material that keeps it holds it from then on).
    private func releaseDraft() {
        guard let key = draftKey else { return }
        draftKey = nil
        SourceDrafts.shared.take(for: key)
        if !saved || !keepText { ProjectMaterialStore.shared.cleanOriginals() }
    }

    private func reset() {
        stage = .pick
        input = nil
        material = nil
        additions = []
        chosen = []
        message = nil
        isLimit = false
        truncated = false
    }

    private func use(_ input: MapInput, _ material: ProjectMaterial) {
        self.input = input
        self.material = material
        message = nil
        isLimit = false
        stage = .ready
    }

    private func importDocument(_ url: URL) {
        let isPaid = account.isPaid
        loadingFile = true
        Task {
            defer { loadingFile = false }
            do {
                let document = try await Attachments.loadDocument(at: url, maxPages: isPaid ? 300 : 10)
                // Kept as the original while the picked copy can still be read.
                let draft = await Task.detached(priority: .userInitiated) {
                    SourceImport.document(at: url, text: document.text, pages: document.pages)
                }.value
                SourceDrafts.shared.put(draft, for: document.text)
                draftKey = document.text
                use(.text(document.text, source: MapSource(kind: .document, label: document.name)),
                    ProjectMaterial(kind: .document, title: document.name, draft: draft))
                message = draft.originalError
            } catch {
                let tooLong: Bool
                if case Attachments.DocumentError.tooLong = error { tooLong = true } else { tooLong = false }
                message = Attachments.message(for: error, isPaid: isPaid)
                isLimit = tooLong && !isPaid
            }
        }
    }

    private func readScans(_ pages: [UIImage]) {
        guard !pages.isEmpty else {
            loadingFile = false
            return
        }
        loadingFile = true
        Task {
            let label = pages.count == 1 ? L("Scan") : L("Scan · \(pages.count) pages")
            let draft = await SourceImport.scan(pages, name: L("Scan"))
            loadingFile = false
            guard let draft else {
                message = L("No text found in these pictures. Try a sharper photo with more light.")
                return
            }
            SourceDrafts.shared.put(draft, for: draft.text)
            draftKey = draft.text
            use(.text(draft.text, source: MapSource(kind: .scan, label: label)), ProjectMaterial(kind: .scan, title: label, draft: draft))
            message = draft.originalError
        }
    }

    private func useLink() {
        let raw = link.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = raw.lowercased().hasPrefix("http") ? raw : "https://" + raw
        guard let url = CreateMapView.link(in: text) else {
            message = L("That doesn’t look like a link. Check it and try again.")
            return
        }
        let value = url.absoluteString
        if CreateMapView.isYouTube(url) {
            use(.youtube(value), ProjectMaterial(kind: .youtube, title: value, url: value))
        } else {
            use(.link(value), ProjectMaterial(kind: .link, title: url.host ?? value, url: value))
        }
    }

    private func analyze() {
        guard let input, let map else { return }
        stage = .reading
        message = nil
        isLimit = false
        task = Task {
            do {
                let (tree, wasTruncated, fetched) = try await MapService.shared.addMaterial(map, input: input, segments: material?.segments)
                try Task.checkCancellation()
                // A page or a video: what the server read becomes the material's text and passages.
                if let fetched { material?.adopt(fetched) }
                // Compared with the map as it is now, in case it changed while Minor was reading.
                let current = maps.map(mapID) ?? map
                additions = current.root.additions(from: tree)
                chosen = Set(additions.map(\.id))
                truncated = wasTruncated
                stage = .preview
                Telemetry.log("material_analyzed", ["kind": material?.kind.rawValue ?? "", "added": additions.count])
            } catch is CancellationError {
            } catch {
                stage = .failed
                if case BackendError.limitReached(let kind) = error {
                    AccountStore.shared.noteLimitReached(kind: kind)
                    isLimit = true
                }
                if case BackendError.planRequired = error { isLimit = true }
                message = (error as? LocalizedError)?.errorDescription ?? L("Something went wrong. Try again.")
            }
        }
    }

    private func saveOnly() {
        guard let material = finalMaterial else { return }
        task?.cancel()
        saved = true
        onSaveOnly(material)
        dismiss()
    }
}
