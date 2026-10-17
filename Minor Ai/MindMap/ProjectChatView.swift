//
//  ProjectChatView.swift
//  Minor Ai
//
//  The Chat tab of a project. The context above the field shows what the assistant sees: the
//  map, and the idea or slide in focus (each can be left out). Proposals for the map show what
//  they add before anything changes.
//

import SwiftUI

struct ProjectChatView: View {
    @ObservedObject var model: ProjectChatModel
    let theme: AppTheme
    let tabs: AnyView
    var branch: UUID?             // the idea selected on the map
    var deck: Deck?               // the presentation on the Slides tab
    var slideID: UUID?
    var onBack: () -> Void
    var onUpgrade: (_ pro: Bool) -> Void
    var onShowOnMap: (UUID?) -> Void
    var onOpenSlides: () -> Void

    @ObservedObject private var store = MapStore.shared
    @ObservedObject private var account = AccountStore.shared
    @State private var keepBranch = true
    @State private var keepSlide = true
    @State private var chatModel: AIModelOption = AIModelCatalog.default
    @State private var confirmClear = false
    @FocusState private var focused: Bool

    private var map: MindMap? { store.map(model.mapID) }

    private var branchNode: MindNode? {
        guard keepBranch, let branch, let map, branch != map.root.id else { return nil }
        return map.root.node(branch)
    }

    private var slide: Slide? {
        guard keepSlide, let deck, let slideID else { return nil }
        return deck.slides.first { $0.id == slideID }
    }

    private var context: ProjectChatModel.Context {
        ProjectChatModel.Context(branch: branchNode?.id, deck: slide == nil ? nil : deck, slide: slide)
    }

    var body: some View {
        VStack(spacing: 0) {
            ProjectHeader(title: map?.title ?? "", status: L("Private chat about this project"), onBack: onBack) {
                Menu {
                    Button(role: .destructive) { confirmClear = true } label: { Label("Clear Chat", systemImage: "trash") }
                        .disabled(model.messages.isEmpty)
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 18)).frame(width: 44, height: 44)
                }
                .accessibilityLabel("More")
            }
            tabs
            messageList
            bottom
        }
        .foregroundColor(MinorColor.textPrimary)
        .background(theme.background.ignoresSafeArea())
        .onChange(of: branch) { _ in keepBranch = true }
        .onChange(of: slideID) { _ in keepSlide = true }
        .onChange(of: account.effectivePlan) { _ in
            if !account.allowsChat(with: chatModel) { chatModel = AIModelCatalog.default }
        }
        .confirmationDialog("Clear this chat?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear Chat", role: .destructive) { model.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The messages are deleted from this iPhone. The map stays as it is.")
        }
        .sheet(isPresented: Binding(get: { model.needsConsent }, set: { if !$0 { model.cancelConsent() } })) {
            AIConsentView(onAllow: { model.resumeAfterConsent() }, onDecline: { model.cancelConsent() })
        }
    }

    // MARK: - Messages

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if model.messages.filter({ !$0.isHidden }).isEmpty {
                        empty
                    }
                    ForEach(model.messages.filter { !$0.isHidden }) { message in
                        row(message).id(message.id)
                    }
                    if model.sending {
                        TypingDots(color: theme.placeholderText)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 16).fill(theme.chatRectangle))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.chatStroke, lineWidth: 1))
                            .accessibilityLabel("Minor is answering")
                            .id("typing")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.messages.count) { _ in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(model.messages.last?.id, anchor: .bottom) }
            }
            .onChange(of: model.sending) { sending in
                if sending { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("typing", anchor: .bottom) } }
            }
            .onAppear { proxy.scrollTo(model.messages.last?.id, anchor: .bottom) }
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "bubble.left.and.text.bubble.right").font(.system(size: 30)).foregroundColor(MinorColor.textSecondary)
            Text("Talk about this project").minorFont(20, .bold, maxScale: 1.3)
            Text("Ask about the map, or ask to change it: Minor shows the changes first, and you decide.")
                .minorFont(15, maxScale: 1.4)
                .foregroundColor(MinorColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                ForEach([L("What is missing from this map?"), L("Summarize the map in five lines"), L("What should I do next?")], id: \.self) { prompt in
                    Button { model.draft = prompt; focused = true } label: {
                        Text(prompt)
                            .minorFont(14, maxScale: 1.4)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(theme.chatRectangle))
                            .overlay(Capsule().stroke(theme.chatStroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 24)
    }

    @ViewBuilder
    private func row(_ message: ChatMessage) -> some View {
        if let action = message.action {
            if action.kind == .mapProposal {
                proposal(message.id, action)
            } else {
                actionCard(message.id, action)
            }
        } else if message.role == .user {
            VStack(alignment: .trailing, spacing: 4) {
                bubble(message.text, user: true)
                if let failed = message.failed {
                    HStack(spacing: 8) {
                        Text(failed).minorFont(12, style: .caption1, maxScale: 1.4).foregroundColor(MinorColor.dangerText)
                        if model.canRetry(message.id) {
                            Button("Retry") { model.retry(message.id, model: chatModel, context: context) }
                                .minorFont(12, .semibold, style: .caption1, maxScale: 1.4)
                                .foregroundColor(MinorColor.accent)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 40)
        } else if let image = message.images?.first.flatMap(UIImage.init(data:)) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 260)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .accessibilityLabel(Text(message.imagePrompt ?? L("Picture")))
        } else {
            bubble(message.text, user: false)
                .padding(.trailing, 40)
        }
    }

    private func bubble(_ text: String, user: Bool) -> some View {
        // Minor answers in Markdown: bold, lists and headings show as such, not as ** and -.
        Group {
            if user { Text(text) } else { MarkdownText(text: text) }
        }
            .minorFont(16, maxScale: 1.4)
            .textSelection(.enabled)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 16).fill(user ? MinorColor.accent.opacity(0.18) : theme.chatRectangle))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(user ? MinorColor.accent.opacity(0.6) : theme.chatStroke, lineWidth: 1))
    }

    // A proposal: what it adds, then Apply / Dismiss; once applied, Show on Map and Undo.
    private func proposal(_ id: UUID, _ action: ChatAction) -> some View {
        let stale = model.isStale(action)
        let added = action.added ?? []
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: action.applied == true ? "checkmark.circle.fill" : "sparkles")
                    .foregroundColor(MinorColor.accent)
                Text(action.applied == true ? (action.undone == true ? "Change undone" : "Applied to the map") : action.dismissed == true ? "Dismissed" : "Suggested by Minor")
                    .minorFont(13, .semibold, style: .footnote, maxScale: 1.3)
                    .foregroundColor(MinorColor.textSecondary)
            }
            Text(action.summary.isEmpty ? L("Changes to the map") : action.summary)
                .minorFont(16, .semibold, maxScale: 1.4)
            if !added.isEmpty && action.dismissed != true {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(added.prefix(6), id: \.self) { title in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "plus.circle.fill").font(.system(size: 14)).foregroundColor(BranchColor.lilac.color)
                            Text(title).minorFont(14, maxScale: 1.4).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if added.count > 6 {
                        Text(L("And \(added.count - 6) more")).minorFont(13, style: .footnote, maxScale: 1.4).foregroundColor(MinorColor.textTertiary)
                    }
                }
            }
            if action.applied != true && action.dismissed != true {
                if model.isViewer {
                    Text("You can view this map, not change it.").minorFont(13, style: .footnote, maxScale: 1.4).foregroundColor(MinorColor.textSecondary)
                } else if stale {
                    Text("The map changed after this answer, so it isn’t applied as it was.")
                        .minorFont(13, style: .footnote, maxScale: 1.4)
                        .foregroundColor(MinorColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        pill(L("Ask Again"), primary: true) { model.recalculate(id, model: chatModel, branch: context.branch) }
                        pill(L("Decline"), primary: false) { model.dismiss(id) }
                    }
                } else {
                    Text("The rest of the map stays as it is.").minorFont(12, style: .caption1, maxScale: 1.4).foregroundColor(MinorColor.textTertiary)
                    HStack(spacing: 8) {
                        pill(L("Apply"), primary: true) { model.apply(id) }
                        pill(L("Decline"), primary: false) { model.dismiss(id) }
                    }
                }
            } else if action.applied == true && action.undone != true {
                HStack(spacing: 8) {
                    pill(L("Show on Map"), primary: false) {
                        let first = action.proposal.flatMap { proposal in action.before.map { before in Self.firstAdded(old: before, new: proposal) } } ?? nil
                        onShowOnMap(first)
                    }
                    if model.canUndo(id) {
                        pill(L("Undo"), primary: false) { model.undo(id) }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(theme.chatRectangle))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(action.applied == true || action.dismissed == true ? theme.chatStroke : MinorColor.accent.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: action.applied == true || action.dismissed == true ? [] : [5, 4])))
        .accessibilityElement(children: .contain)
    }

    private static func firstAdded(old: MindNode, new: MindNode) -> UUID? {
        var known: Set<UUID> = []
        func collect(_ node: MindNode) { known.insert(node.id); node.children.forEach(collect) }
        collect(old)
        func find(_ node: MindNode) -> UUID? {
            if !known.contains(node.id) { return node.id }
            for child in node.children { if let id = find(child) { return id } }
            return nil
        }
        return find(new)
    }

    private func actionCard(_ id: UUID, _ action: ChatAction) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.on.rectangle.angled").foregroundColor(MinorColor.accent)
                Text(action.kind == .deckEdited ? (action.undone == true ? L("Change undone") : L("Presentation updated")) : L("Presentation ready"))
                    .minorFont(15, .semibold, maxScale: 1.3)
            }
            Text(action.summary.isEmpty ? action.mapTitle : "\(action.mapTitle) · \(action.summary)")
                .minorFont(14, maxScale: 1.4)
                .foregroundColor(MinorColor.textSecondary)
            HStack(spacing: 8) {
                if DeckStore.shared.deck(action.mapID) != nil {
                    pill(L("Open in Slides"), primary: true) {
                        model.deckRequest = action.mapID
                        onOpenSlides()
                    }
                }
                if model.canUndo(id) {
                    pill(L("Undo"), primary: false) { model.undo(id) }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(theme.chatRectangle))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.chatStroke, lineWidth: 1))
    }

    private func pill(_ title: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .minorFont(14, .semibold, maxScale: 1.3)
                .foregroundColor(primary ? .black : .white)
                .padding(.horizontal, 16)
                .frame(minHeight: 38)
                .background(Capsule().fill(primary ? MinorColor.sendFill : Color.clear))
                .overlay(Capsule().stroke(primary ? Color.clear : theme.chatStroke, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(PressScale())
    }

    // MARK: - Context and field

    private var bottom: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = model.errorMessage {
                HStack(spacing: 10) {
                    Text(error).minorFont(13, style: .footnote, maxScale: 1.4).frame(maxWidth: .infinity, alignment: .leading)
                    if model.errorSuggestsUpgrade {
                        Button(account.isPaid ? "Get PRO" : "Get Minor Plus") { onUpgrade(account.isPaid) }
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Button { model.errorMessage = nil } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .bold)) }
                        .accessibilityLabel("Dismiss")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12).fill(MinorColor.danger.opacity(0.25)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(MinorColor.danger.opacity(0.6), lineWidth: 1))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    contextChip("point.3.connected.trianglepath.dotted", map?.title ?? "", removable: false) {}
                    if let node = branchNode {
                        contextChip("arrow.turn.down.right", L("Idea: \(node.title)"), removable: true) { keepBranch = false }
                    }
                    if let slide, let deck, let number = deck.slides.firstIndex(where: { $0.id == slide.id }) {
                        contextChip("rectangle.on.rectangle", L("Slide \(number + 1)"), removable: true) { keepSlide = false }
                    }
                    modelMenu
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("What the assistant sees")
            HStack(alignment: .bottom, spacing: 10) {
                TextField("", text: $model.draft, axis: .vertical)
                    .placeholder(when: model.draft.isEmpty, alignment: .topLeading) {
                        Text("Ask about the project or ask to change the map").foregroundColor(theme.placeholderText)
                    }
                    .minorFont(17, maxScale: 1.4)
                    .lineLimit(1...5)
                    .focused($focused)
                    .accessibilityLabel("Message")
                    .padding(.vertical, 6)
                if model.sending {
                    Button { model.stop() } label: {
                        RoundedRectangle(cornerRadius: 3).fill(Color.black).frame(width: 12, height: 12)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(MinorColor.sendFill))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Stop")
                } else {
                    Button { model.send(model.draft, model: chatModel, context: context) } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.black)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(MinorColor.sendFill))
                            .frame(width: 44, height: 44)
                    }
                    .disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
                    .accessibilityLabel("Send")
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 6)
            .padding(.vertical, 4)
            .minorSurface(theme)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    private func contextChip(_ icon: String, _ title: String, removable: Bool, remove: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold))
            Text(title).minorFont(13, maxScale: 1.3).lineLimit(1)
            if removable {
                Button(action: remove) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(width: 24, height: 24)
                }
                .accessibilityLabel(Text("Leave out \(title)"))
            }
        }
        .foregroundColor(MinorColor.textPrimary)
        .padding(.leading, 10)
        .padding(.trailing, removable ? 2 : 10)
        .frame(minHeight: 30)
        .background(Capsule().fill(theme.chatRectangle))
        .overlay(Capsule().stroke(theme.chatStroke, lineWidth: 1))
    }

    // The chat model, with the same plan rules as on the home screen.
    private var modelMenu: some View {
        Menu {
            ForEach(AIModelCatalog.all) { option in
                Button {
                    if account.allowsChat(with: option) { chatModel = option } else { onUpgrade(option.chatPlan == .pro) }
                } label: {
                    if option == chatModel {
                        Label(option.displayName, systemImage: "checkmark")
                    } else if !account.allowsChat(with: option) {
                        Label("\(option.displayName) · \(option.chatPlan == .pro ? "PRO" : "Plus")", systemImage: "lock.fill")
                    } else {
                        Text("\(option.displayName)  ×\(option.usage)")
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(chatModel.displayName).minorFont(13, maxScale: 1.3).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
            }
            .foregroundColor(MinorColor.textSecondary)
            .padding(.horizontal, 10)
            .frame(minHeight: 30)
            .overlay(Capsule().stroke(theme.chatStroke, lineWidth: 1))
        }
        .accessibilityLabel("AI model: \(chatModel.displayName)")
    }
}
