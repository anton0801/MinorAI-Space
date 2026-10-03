//
//  NodeChatView.swift
//  Minor Ai
//
//  Chat about one idea of a map. Answers can be added to the map as new children.
//

import SwiftUI

struct NodeChatView: View {
    let map: MindMap
    let nodeID: UUID
    let theme: AppTheme
    // A question typed into the map's composer: sent as soon as the chat opens.
    var initialPrompt: String? = nil
    var onAddToMap: ([String]) -> Void
    var onUpgrade: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var messages: [ChatMessage] = []
    @State private var added: Set<UUID> = []
    @State private var draft = ""
    @State private var isSending = false
    @State private var error: BackendError?
    @State private var keepContext = true
    @State private var showConsent = false
    @State private var pendingPrompt: String?
    @FocusState private var focused: Bool

    private var path: [MindNode] { map.root.path(to: nodeID) ?? [map.root] }
    private var node: MindNode { path.last ?? map.root }
    private var branch: BranchColor { map.branchColor(for: nodeID) ?? .mint }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if messages.isEmpty { suggestions }
                        ForEach(messages) { message in
                            bubble(message).id(message.id)
                        }
                        if isSending {
                            HStack(spacing: 5) {
                                ForEach(0..<3, id: \.self) { _ in Circle().fill(theme.placeholderText).frame(width: 7, height: 7) }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .minorSurface(theme)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("typing")
                        }
                    }
                    .padding(16)
                }
                .onChange(of: messages.count) { _ in
                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
                }
            }
            if let error {
                HStack {
                    Text(error.errorDescription ?? "").font(.system(size: 13))
                    Spacer()
                    if error.suggestsUpgrade {
                        Button(AccountStore.shared.effectivePlan == .plus ? "Get PRO" : "Get Minor Plus", action: onUpgrade).font(.system(size: 13, weight: .semibold))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12).fill(MinorColor.danger.opacity(0.25)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(MinorColor.danger.opacity(0.6), lineWidth: 1))
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            if keepContext { contextChip }
            composer
        }
        .foregroundColor(MinorColor.textPrimary)
        .background(theme.background.ignoresSafeArea())
        .onAppear {
            if let initialPrompt, messages.isEmpty { send(initialPrompt) }
        }
        .sheet(isPresented: $showConsent) {
            AIConsentView(
                onAllow: {
                    showConsent = false
                    if let prompt = pendingPrompt { send(prompt) }
                    pendingPrompt = nil
                },
                onDecline: {
                    showConsent = false
                    pendingPrompt = nil
                }
            )
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Button { dismiss() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold))
                    Text(map.title).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                }
                .frame(height: 44)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ask about “\(node.title)”")
                .font(.system(size: 15))
                .foregroundColor(MinorColor.textSecondary)
            ForEach([L("Explain this idea simply"), L("Give 3 real examples"), L("What are the pros and cons?")], id: \.self) { prompt in
                Button { send(prompt) } label: {
                    Text(prompt)
                        .font(.system(size: 14))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .overlay(RoundedRectangle(cornerRadius: 15).stroke(theme.chatStroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func bubble(_ message: ChatMessage) -> some View {
        if message.role == .user {
            Text(message.text)
                .font(.system(size: 16))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 16).fill(MinorColor.accent.opacity(0.18)))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(MinorColor.accent.opacity(0.6), lineWidth: 1))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 40)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text((try? AttributedString(markdown: message.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(message.text))
                    .font(.system(size: 16))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .minorSurface(theme)
                if keepContext {
                    Button {
                        guard !added.contains(message.id) else { return }
                        added.insert(message.id)
                        Haptics.success()
                        onAddToMap(Self.ideas(from: message.text))
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: added.contains(message.id) ? "checkmark" : "plus").font(.system(size: 13, weight: .semibold))
                            Text(added.contains(message.id) ? "Added" : "Add to Map").font(.system(size: 14))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .overlay(RoundedRectangle(cornerRadius: 15).stroke(added.contains(message.id) ? MinorColor.accent : theme.chatStroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 40)
        }
    }

    private var contextChip: some View {
        HStack(spacing: 8) {
            Circle().fill(branch.color).frame(width: 8, height: 8)
            Text(node.title).font(.system(size: 14)).lineLimit(1)
            Button { keepContext = false } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
            }
            .accessibilityLabel("Chat without this idea")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(theme.chatStroke, lineWidth: 1))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("", text: $draft)
                .placeholder(when: draft.isEmpty) { Text("Message").foregroundColor(theme.placeholderText) }
                .font(.system(size: 17))
                .focused($focused)
                .submitLabel(.send)
                .onSubmit { send(draft) }
            Button { send(draft) } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.black)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(MinorColor.sendFill))
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            .accessibilityLabel("Send")
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .frame(height: 60)
        .minorSurface(theme)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }
        guard AIConsent.isGiven else {
            pendingPrompt = trimmed
            showConsent = true
            return
        }
        draft = ""
        error = nil
        messages.append(ChatMessage(role: .user, text: trimmed))
        isSending = true
        // The server reads at most the last 30 messages.
        let history = Array(messages.suffix(30))
        let context = keepContext ? AIService.NodeContext(mapTitle: map.title, path: path.map(\.title)) : nil
        Task {
            do {
                let reply = try await AIService.shared.reply(to: history, model: AIModelCatalog.default, context: context)
                messages.append(ChatMessage(role: .assistant, text: reply))
            } catch let failure as BackendError {
                if case .limitReached(let kind) = failure { AccountStore.shared.noteLimitReached(kind: kind) }
                error = failure
                UIAccessibility.post(notification: .announcement, argument: failure.errorDescription)
            } catch is CancellationError {
            } catch {
                self.error = .server(code: "chat")
            }
            isSending = false
        }
    }

    // Turns a reply into child titles: list items when there are any, otherwise the first sentence.
    static func ideas(from reply: String) -> [String] {
        let items = reply
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .compactMap { line -> String? in
                guard let match = line.range(of: #"^([-*•]|\d+[.)])\s+"#, options: .regularExpression) else { return nil }
                let text = line[match.upperBound...]
                    .replacingOccurrences(of: "**", with: "")
                    .trimmingCharacters(in: .whitespaces)
                let short = (text.components(separatedBy: CharacterSet(charactersIn: ":—–")).first ?? text)
                    .trimmingCharacters(in: .whitespaces)
                return short.isEmpty ? nil : String(short.prefix(80))
            }
        if !items.isEmpty { return Array(items.prefix(6)) }
        let sentence = reply.components(separatedBy: CharacterSet(charactersIn: ".!?\n")).first ?? reply
        return [String(sentence.trimmingCharacters(in: .whitespaces).prefix(80))]
    }
}
