//
//  ProjectMemorySheet.swift
//  Minor Ai
//
//  About the Project: a short summary the person keeps — the goal, decisions made and open
//  questions. Minor can suggest entries from the map, but nothing is added until it's accepted,
//  and an option is never recorded as a decision by itself. Kept on this iPhone and given to the
//  project chat as context; removed or changed entries stop counting right away.
//

import SwiftUI

struct ProjectMemorySheet: View {
    let mapID: UUID
    let theme: AppTheme
    var onDiscuss: (String) -> Void
    var onUpgrade: () -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = ProjectMemoryStore.shared
    @ObservedObject private var maps = MapStore.shared
    @State private var editing: Editing?
    @State private var text = ""
    @State private var suggesting = false
    @State private var error: String?
    @State private var isLimit = false
    @State private var task: Task<Void, Never>?

    struct Editing: Identifiable {
        enum Kind { case goal, decision, question }
        let id = UUID()
        let kind: Kind
        var item: UUID?
    }

    private var memory: ProjectMemory { store.memory(for: mapID) }
    private var map: MindMap? { maps.map(mapID) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                header
                goalCard
                listCard(L("Decisions"), items: memory.decisions, kind: .decision, empty: L("Nothing decided yet."))
                listCard(L("Open questions"), items: memory.questions, kind: .question, empty: L("No open questions."))
                suggestionCard
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle").font(.system(size: 13))
                    Text("Entries are added only when you confirm them. They stay on this iPhone and help the project chat answer.")
                        .minorFont(12, style: .caption1, maxScale: 1.4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundColor(MinorColor.textTertiary)
                .padding(.top, 2)
                Button { dismiss() } label: {
                    Text("Done")
                        .minorFont(16, .semibold, maxScale: 1.3)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white))
                }
                .buttonStyle(PressScale())
                .padding(.top, 2)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 16)
        }
        .foregroundColor(MinorColor.textPrimary)
        .background(MinorColor.editorSheet.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onDisappear { task?.cancel() }
        .alert(editingTitle, isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField(editingPlaceholder, text: $text)
            Button("Save") { commit() }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: map == nil) { gone in if gone { dismiss() } }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("About the Project")
                    .minorFont(24, .bold, style: .title2, maxScale: 1.3)
                    .accessibilityAddTraits(.isHeader)
                if let map {
                    Text(map.title).minorFont(15, maxScale: 1.3).foregroundColor(MinorColor.textSecondary).lineLimit(1)
                }
                Text("You can change this anytime.")
                    .minorFont(12, style: .caption1, maxScale: 1.3)
                    .foregroundColor(MinorColor.textTertiary)
            }
            Spacer(minLength: 8)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white.opacity(0.1)))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close")
        }
        .padding(.bottom, 4)
    }

    private var goalCard: some View {
        card(L("Goal")) {
            HStack(alignment: .center, spacing: 12) {
                if memory.goal.isEmpty {
                    Text("What should this project achieve?")
                        .minorFont(15, maxScale: 1.3)
                        .foregroundColor(MinorColor.textTertiary)
                } else {
                    Text(memory.goal)
                        .minorFont(16, .semibold, maxScale: 1.3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button { edit(.goal, item: nil, text: memory.goal) } label: {
                    Image(systemName: memory.goal.isEmpty ? "plus" : "pencil")
                        .font(.system(size: 15))
                        .frame(width: 34, height: 34)
                        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.08)))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(memory.goal.isEmpty ? "Add Goal" : "Edit Goal")
            }
        }
    }

    private func listCard(_ title: String, items: [ProjectMemory.Item], kind: Editing.Kind, empty: String) -> some View {
        card(title) {
            VStack(alignment: .leading, spacing: 0) {
                if items.isEmpty {
                    Text(empty).minorFont(14, maxScale: 1.3).foregroundColor(MinorColor.textTertiary).padding(.bottom, 6)
                }
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    HStack(alignment: .center, spacing: 12) {
                        if kind == .decision {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.black)
                                .frame(width: 24, height: 24)
                                .background(RoundedRectangle(cornerRadius: 6).fill(MinorColor.accent))
                                .accessibilityHidden(true)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.text).minorFont(14, .medium, maxScale: 1.3).fixedSize(horizontal: false, vertical: true)
                            if item.byMinor {
                                Text("Suggested by Minor, accepted by you")
                                    .minorFont(12, style: .caption1, maxScale: 1.3)
                                    .foregroundColor(MinorColor.textTertiary)
                            }
                        }
                        Spacer(minLength: 8)
                        if kind == .question {
                            Button {
                                dismiss()
                                onDiscuss(item.text)
                            } label: {
                                Label("Discuss", systemImage: "bubble.left")
                                    .minorFont(13, .medium, maxScale: 1.3)
                                    .lineLimit(1)
                                    .fixedSize()
                                    .padding(.horizontal, 10)
                                    .frame(minHeight: 30)
                                    .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1))
                                    .frame(minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        Menu {
                            Button { edit(kind, item: item.id, text: item.text) } label: { Label("Edit", systemImage: "pencil") }
                            if kind == .question {
                                Button { move(item, toDecisions: true) } label: { Label("Mark as Decided", systemImage: "checkmark.circle") }
                            } else {
                                Button { move(item, toDecisions: false) } label: { Label("Reopen as Question", systemImage: "questionmark.circle") }
                            }
                            Button(role: .destructive) { remove(item.id, kind: kind) } label: { Label("Delete", systemImage: "trash") }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 32, height: 32)
                                .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.08)))
                                .frame(width: 40, height: 44)
                        }
                        .accessibilityLabel(L("More for “\(item.text)”"))
                    }
                    .padding(.vertical, 1)
                    if index < items.count - 1 { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
                }
                if items.count < ProjectMemory.itemLimit {
                    Button { edit(kind, item: nil, text: "") } label: {
                        Label(kind == .decision ? L("Add Decision") : L("Add Question"), systemImage: "plus")
                            .minorFont(14, .medium, maxScale: 1.3)
                            .foregroundColor(MinorColor.accent)
                            .frame(minHeight: 36)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var suggestionCard: some View {
        card(L("Suggestions from Minor")) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(memory.suggestions) { suggestion in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(LinearGradient(colors: [BranchColor.lilac.color, BranchColor.sky.color], startPoint: .topLeading, endPoint: .bottomTrailing))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kindName(suggestion.kind))
                                    .minorFont(12, .semibold, style: .caption1, maxScale: 1.3)
                                    .foregroundColor(MinorColor.textTertiary)
                                Text(suggestion.text).minorFont(15, .semibold, maxScale: 1.3).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        HStack(spacing: 8) {
                            Button { accept(suggestion) } label: {
                                Label("Accept", systemImage: "checkmark")
                                    .minorFont(14, .semibold, maxScale: 1.3)
                                    .foregroundColor(.black)
                                    .frame(maxWidth: .infinity, minHeight: 38)
                                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(MinorColor.accent))
                            }
                            .buttonStyle(PressScale())
                            Button { decline(suggestion) } label: {
                                Label("Decline", systemImage: "xmark")
                                    .minorFont(14, .medium, maxScale: 1.3)
                                    .frame(maxWidth: .infinity, minHeight: 38)
                                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.25), lineWidth: 1))
                            }
                            .buttonStyle(PressScale())
                        }
                    }
                    .padding(.bottom, 4)
                }
                if let error {
                    Text(error)
                        .minorFont(14, maxScale: 1.3)
                        .foregroundColor(MinorColor.dangerText)
                        .fixedSize(horizontal: false, vertical: true)
                    if isLimit {
                        Button {
                            dismiss()
                            onUpgrade()
                        } label: {
                            Text(AccountStore.shared.effectivePlan == .plus ? "Get PRO" : "Get Minor Plus")
                                .minorFont(15, .semibold, maxScale: 1.3)
                                .foregroundColor(MinorColor.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if memory.suggestions.isEmpty {
                    Button(action: suggest) {
                        HStack(spacing: 8) {
                            if suggesting {
                                ProgressView().tint(MinorColor.textPrimary)
                                Text("Reading the map…")
                            } else {
                                Image(systemName: "sparkles")
                                Text("Suggest from the Map")
                            }
                        }
                        .minorFont(14, .medium, maxScale: 1.3)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(PressScale())
                    .disabled(suggesting)
                }
            }
        }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .textCase(.uppercase)
                .minorFont(11, .semibold, style: .caption2, maxScale: 1.3)
                .foregroundColor(MinorColor.textTertiary)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func kindName(_ kind: ProjectMemory.Suggestion.Kind) -> String {
        switch kind {
        case .goal: return L("Goal")
        case .decision: return L("Decision")
        case .question: return L("Open question")
        }
    }

    // MARK: - Editing

    private var editingTitle: String {
        switch editing?.kind {
        case .goal?: return L("Goal")
        case .decision?: return editing?.item == nil ? L("Add Decision") : L("Decision")
        case .question?: return editing?.item == nil ? L("Add Question") : L("Open question")
        case nil: return ""
        }
    }

    private var editingPlaceholder: String {
        switch editing?.kind {
        case .goal?: return L("For example: launch the first three episodes")
        case .decision?: return L("For example: one episode a week")
        default: return L("For example: who to invite first?")
        }
    }

    private func edit(_ kind: Editing.Kind, item: UUID?, text: String) {
        self.text = text
        editing = Editing(kind: kind, item: item)
    }

    private func commit() {
        guard let editing else { return }
        let clean = ProjectMemory.clean(text)
        store.update(mapID) { memory in
            switch editing.kind {
            case .goal:
                memory.goal = clean ?? ""
            case .decision, .question:
                var list = editing.kind == .decision ? memory.decisions : memory.questions
                if let id = editing.item, let index = list.firstIndex(where: { $0.id == id }) {
                    if let clean { list[index].text = clean } else { list.remove(at: index) }
                } else if let clean {
                    list.append(ProjectMemory.Item(text: clean))
                }
                if editing.kind == .decision { memory.decisions = list } else { memory.questions = list }
            }
        }
        Haptics.selection()
    }

    private func move(_ item: ProjectMemory.Item, toDecisions: Bool) {
        store.update(mapID) { memory in
            memory.decisions.removeAll { $0.id == item.id }
            memory.questions.removeAll { $0.id == item.id }
            if toDecisions { memory.decisions.append(item) } else { memory.questions.append(item) }
        }
        Haptics.selection()
    }

    private func remove(_ id: UUID, kind: Editing.Kind) {
        store.update(mapID) { memory in
            memory.decisions.removeAll { $0.id == id }
            memory.questions.removeAll { $0.id == id }
        }
    }

    private func accept(_ suggestion: ProjectMemory.Suggestion) {
        Haptics.success()
        store.update(mapID) { memory in
            memory.suggestions.removeAll { $0.id == suggestion.id }
            switch suggestion.kind {
            case .goal: memory.goal = suggestion.text
            case .decision: memory.decisions.append(ProjectMemory.Item(text: suggestion.text, byMinor: true))
            case .question: memory.questions.append(ProjectMemory.Item(text: suggestion.text, byMinor: true))
            }
            // A second goal suggestion can't apply once there is a goal.
            if suggestion.kind == .goal { memory.suggestions.removeAll { $0.kind == .goal } }
        }
    }

    private func decline(_ suggestion: ProjectMemory.Suggestion) {
        store.update(mapID) { $0.suggestions.removeAll { $0.id == suggestion.id } }
    }

    private func suggest() {
        guard let map, !suggesting else { return }
        suggesting = true
        error = nil
        isLimit = false
        let memory = memory
        task = Task {
            defer { suggesting = false }
            do {
                let suggestions = try await MapService.shared.suggestMemory(map, memory: memory)
                try Task.checkCancellation()
                if suggestions.isEmpty {
                    error = L("Nothing new to suggest from the map right now.")
                } else {
                    store.update(mapID) { $0.suggestions = suggestions }
                }
                Telemetry.log("project_memory_suggest", ["count": suggestions.count])
            } catch is CancellationError {
            } catch {
                if case BackendError.limitReached(let kind) = error {
                    AccountStore.shared.noteLimitReached(kind: kind)
                    isLimit = true
                }
                self.error = (error as? LocalizedError)?.errorDescription ?? L("Something went wrong. Try again.")
            }
        }
    }
}
