//
//  NextStepsSheet.swift
//  Minor Ai
//
//  Next Steps for an idea: Minor suggests at most three small actions; the person picks which
//  become tasks on the map. Nothing gets a due date unless the person sets one, and a step that
//  is already an idea in the branch makes that idea a task instead of adding a copy.
//

import SwiftUI

struct NextStepsSheet: View {
    struct Choice: Identifiable, Equatable {
        let id = UUID()
        var title: String
        var detail: String
        var due: Date?
        var existing: UUID?        // an idea in the branch with this title
        var chosen = true
    }

    let map: MindMap
    let nodeID: UUID
    let theme: AppTheme
    var onAdd: (_ choices: [Choice]) -> Void
    var onAsk: () -> Void
    var onUpgrade: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var choices: [Choice] = []
    @State private var loading = true
    @State private var error: String?
    @State private var isLimit = false
    @State private var dueTarget: UUID?
    @State private var task: Task<Void, Never>?

    private var node: MindNode? { map.root.node(nodeID) }
    private var chosenCount: Int { choices.filter(\.chosen).count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                header
                if loading {
                    loadingRows
                } else if let error {
                    errorView(error)
                } else {
                    Text("Choose what to add to tasks.")
                        .minorFont(14, maxScale: 1.3)
                        .foregroundColor(MinorColor.textSecondary)
                    VStack(spacing: 6) {
                        ForEach($choices) { $choice in row($choice) }
                    }
                    Text("Tasks appear on the map, without a due date unless you set one.")
                        .minorFont(11, style: .caption2, maxScale: 1.4)
                        .foregroundColor(MinorColor.textTertiary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                    Button {
                        onAdd(choices.filter(\.chosen))
                        dismiss()
                    } label: {
                        Text(chosenCount == 0 ? L("Choose a Step") : L("Add Tasks: \(chosenCount)"))
                            .minorFont(16, .semibold, maxScale: 1.3)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white))
                    }
                    .buttonStyle(PressScale())
                    .disabled(chosenCount == 0)
                    .opacity(chosenCount == 0 ? 0.5 : 1)
                }
                Button {
                    task?.cancel()
                    dismiss()
                    onAsk()
                } label: {
                    Label("Discuss with Minor", systemImage: "bubble.left")
                        .minorFont(15, .medium, maxScale: 1.3)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.04)))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
                }
                .buttonStyle(PressScale())
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 16)
        }
        .foregroundColor(MinorColor.textPrimary)
        .background(MinorColor.editorSheet.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-demoNextSteps") {
                let ru = AppLanguage.current.locale.identifier.hasPrefix("ru")
                choices = [
                    Choice(title: ru ? "Сравнить цены конкурентов" : "Compare competitors’ prices", detail: ru ? "Чтобы проверить Plus за $12.99" : "To check Plus at $12.99"),
                    Choice(title: ru ? "Написать текст для страницы тарифов" : "Write the pricing page copy", detail: ""),
                    Choice(title: ru ? "Спросить 5 студентов о скидке" : "Ask 5 students about a discount", detail: ru ? "Нужна ли отдельная цена" : "Whether a separate price is needed", chosen: false),
                ]
                loading = false
                return
            }
            #endif
            if choices.isEmpty && task == nil { load() }
        }
        .onDisappear { task?.cancel() }
        .sheet(item: Binding(get: { dueTarget.map(IdentifiedID.init) }, set: { dueTarget = $0?.id })) { item in
            if let index = choices.firstIndex(where: { $0.id == item.id }) {
                DueDateSheet(title: choices[index].title, current: choices[index].due, theme: theme, onSave: { date in
                    choices[index].due = date
                    choices[index].chosen = true
                }, onRemove: { choices[index].due = nil })
                .presentationDetents([.large])
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Next Steps")
                    .minorFont(21, .bold, style: .title3, maxScale: 1.3)
                    .accessibilityAddTraits(.isHeader)
                if let node {
                    Text(node.id == map.root.id ? L("For the whole map") : L("From the branch “\(node.title)”"))
                        .minorFont(13, maxScale: 1.3)
                        .foregroundColor(MinorColor.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Button {
                task?.cancel()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white.opacity(0.1)))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close")
        }
    }

    private func row(_ choice: Binding<Choice>) -> some View {
        let value = choice.wrappedValue
        return HStack(alignment: .center, spacing: 8) {
            Button {
                Haptics.selection()
                choice.wrappedValue.chosen.toggle()
            } label: {
                ZStack {
                    Circle().stroke(value.chosen ? Color.clear : MinorColor.textTertiary, lineWidth: 1.5)
                    if value.chosen {
                        Circle().fill(MinorColor.accent)
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundColor(.black)
                    }
                }
                .frame(width: 24, height: 24)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(value.title))
            .accessibilityValue(value.chosen ? L("Will be added") : L("Not added"))
            .accessibilityAddTraits(.isButton)
            VStack(alignment: .leading, spacing: 3) {
                Text(value.title)
                    .minorFont(15, .semibold, maxScale: 1.3)
                    .fixedSize(horizontal: false, vertical: true)
                if !value.detail.isEmpty {
                    Text(value.detail)
                        .minorFont(12, maxScale: 1.3)
                        .foregroundColor(MinorColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if value.existing != nil {
                    Label("Already on the map: it will become a task", systemImage: "arrow.triangle.2.circlepath")
                        .minorFont(13, style: .footnote, maxScale: 1.3)
                        .foregroundColor(BranchColor.sky.color)
                }
                Button { dueTarget = value.id } label: {
                    Label(value.due.map { NodeMarksSheet.dueText($0) } ?? L("No due date"), systemImage: "calendar")
                        .minorFont(12, maxScale: 1.3)
                        .foregroundColor(value.due == nil ? MinorColor.textTertiary : MinorColor.accent)
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Sets a due date"))
            }
            .padding(.vertical, 10)
            Spacer(minLength: 0)
            // The due date opens from here too, as on a task.
            Button { dueTarget = value.id } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MinorColor.textTertiary)
                    .frame(width: 32, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
        }
        .padding(.leading, 2)
        .padding(.trailing, 6)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private var loadingRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ProgressView().tint(MinorColor.textPrimary)
                Text("Minor is thinking about small next actions…")
                    .minorFont(15, maxScale: 1.3)
                    .foregroundColor(MinorColor.textSecondary)
            }
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 18)
                    .fill(theme.chatRectangle)
                    .frame(height: 84)
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.06), lineWidth: 1))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .minorFont(15, maxScale: 1.3)
                .foregroundColor(MinorColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if isLimit {
                Button {
                    dismiss()
                    onUpgrade()
                } label: {
                    Text(AccountStore.shared.effectivePlan == .plus ? "Get PRO" : "Get Minor Plus")
                        .minorFont(16, .semibold, maxScale: 1.3)
                        .foregroundColor(.black)
                        .padding(.horizontal, 22)
                        .frame(minHeight: 46)
                        .background(Capsule().fill(MinorColor.accent))
                }
                .buttonStyle(PressScale())
            } else {
                Button("Try Again", action: load)
                    .minorFont(16, .semibold, maxScale: 1.3)
                    .foregroundColor(MinorColor.accent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private func load() {
        loading = true
        error = nil
        isLimit = false
        let map = map
        let nodeID = nodeID
        let goal = ProjectMemoryStore.shared.memory(for: map.id).goal
        task = Task {
            do {
                let steps = try await MapService.shared.nextSteps(map, node: nodeID, goal: goal)
                try Task.checkCancellation()
                let branch = map.root.node(nodeID)
                choices = steps.map { step in
                    let existing = branch.flatMap { root in
                        MapEditorView.ids(in: root) { $0.id != root.id && $0.title.caseInsensitiveCompare(step.title) == .orderedSame }.first
                    }
                    return Choice(title: step.title, detail: step.detail, existing: existing)
                }
                loading = false
                if choices.isEmpty { error = L("Minor couldn’t suggest steps for this idea. Try again.") }
                Telemetry.log("next_steps", ["count": choices.count])
            } catch is CancellationError {
            } catch {
                loading = false
                if case BackendError.limitReached(let kind) = error {
                    AccountStore.shared.noteLimitReached(kind: kind)
                    isLimit = true
                }
                if case BackendError.modelLocked = error { isLimit = true }
                self.error = (error as? LocalizedError)?.errorDescription ?? L("Something went wrong. Try again.")
            }
        }
    }
}
