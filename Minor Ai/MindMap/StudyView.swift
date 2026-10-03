//
//  StudyView.swift
//  Minor Ai
//
//  Learn a map: flashcards made from its ideas (on the phone, free), and a quiz the AI writes
//  about it. Flashcards show an idea; the back shows what is under it and its note.
//

import SwiftUI

struct Flashcard: Identifiable, Equatable {
    let id: UUID
    let context: String      // where the idea sits: "Map › Branch"
    let front: String
    let back: [String]       // the ideas below it
    let note: String
}

enum Flashcards {
    // One card for every idea that has something under it or a note (the topic itself excluded).
    static func make(from map: MindMap) -> [Flashcard] {
        var cards: [Flashcard] = []
        func walk(_ node: MindNode, path: [String]) {
            for child in node.children where !child.isSuggestion {
                let back = child.children.filter { !$0.isSuggestion }.map { MindMap.outlineText($0) }
                if !back.isEmpty || !child.note.isEmpty {
                    cards.append(Flashcard(id: child.id, context: path.joined(separator: " › "), front: MindMap.outlineText(child), back: back, note: child.note))
                }
                walk(child, path: path + [child.title])
            }
        }
        walk(map.root, path: [map.title])
        return cards
    }
}

struct StudyView: View {
    let map: MindMap
    let theme: AppTheme
    var onUpgrade: () -> Void = {}

    enum Mode: String { case cards, quiz }

    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .cards

    // Flashcards
    @State private var deck: [Flashcard] = []
    @State private var index = 0
    @State private var flipped = false
    @State private var known = 0
    @State private var again: [Flashcard] = []

    // Quiz
    @State private var questions: [MapService.QuizQuestion] = []
    @State private var question = 0
    @State private var picked: Int?
    @State private var score = 0
    @State private var loadingQuiz = false
    @State private var quizError: String?
    @State private var quizIsLimit = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("Mode", selection: $mode) {
                    Text("Flashcards").tag(Mode.cards)
                    Text("AI Quiz").tag(Mode.quiz)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.top, 8)

                if mode == .cards {
                    cards
                } else {
                    quiz
                }
            }
            .foregroundColor(MinorColor.textPrimary)
            .background(theme.background.ignoresSafeArea())
            .navigationTitle(map.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundColor(MinorColor.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { restartCards() }
        .onChange(of: mode) { newMode in
            if newMode == .quiz, questions.isEmpty, !loadingQuiz { loadQuiz() }
        }
    }

    // MARK: - Flashcards

    @ViewBuilder
    private var cards: some View {
        if deck.isEmpty {
            placeholder("rectangle.on.rectangle.angled", L("No cards yet"), L("Cards are made from ideas that have ideas under them or a note. Expand the map first."))
        } else if index >= deck.count {
            VStack(spacing: 16) {
                Spacer()
                Text("🎉").font(.system(size: 54))
                Text(L("You knew \(known) of \(deck.count)"))
                    .font(.system(size: 22, weight: .bold))
                if !again.isEmpty {
                    Text(L("\(again.count) cards to repeat"))
                        .font(.system(size: 15))
                        .foregroundColor(MinorColor.textSecondary)
                }
                Spacer()
                HStack(spacing: 10) {
                    if !again.isEmpty {
                        wideButton(L("Repeat \(again.count)"), primary: true) {
                            deck = again.shuffled()
                            resetProgress()
                        }
                    }
                    wideButton(L("Start Over"), primary: again.isEmpty) { restartCards() }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        } else {
            let card = deck[index]
            VStack(spacing: 14) {
                ProgressView(value: Double(index), total: Double(deck.count))
                    .tint(MinorColor.accent)
                    .padding(.horizontal, 20)
                Text(L("Card \(index + 1) of \(deck.count)"))
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundColor(MinorColor.textTertiary)
                cardFace(card)
                    .padding(.horizontal, 20)
                    .onTapGesture { flip() }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(flipped ? "" : L("Shows the answer"))
                if flipped {
                    HStack(spacing: 10) {
                        wideButton(L("Again"), primary: false) { answer(knew: false) }
                        wideButton(L("Got It"), primary: true) { answer(knew: true) }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    .transition(.opacity)
                } else {
                    wideButton(L("Show Answer"), primary: true) { flip() }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                }
            }
        }
    }

    private func cardFace(_ card: Flashcard) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22)
                .fill(theme.chatRectangle)
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(flipped ? MinorColor.accent.opacity(0.6) : theme.chatStroke, lineWidth: 1))
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(card.context)
                        .font(.system(size: 13))
                        .foregroundColor(MinorColor.textTertiary)
                    Text(card.front)
                        .font(.system(size: 24, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    if flipped {
                        Divider().overlay(theme.chatStroke)
                        ForEach(Array(card.back.enumerated()), id: \.offset) { _, line in
                            HStack(alignment: .top, spacing: 8) {
                                Circle().fill(MinorColor.accent).frame(width: 6, height: 6).padding(.top, 8)
                                Text(line).font(.system(size: 17)).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        if !card.note.isEmpty {
                            Text(card.note)
                                .font(.system(size: 15))
                                .foregroundColor(MinorColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        Text("What is under this idea? Think, then tap.")
                            .font(.system(size: 15))
                            .foregroundColor(MinorColor.textSecondary)
                    }
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxHeight: .infinity)
        .rotation3DEffect(.degrees(flipped ? 360 : 0), axis: (x: 0, y: 1, z: 0))
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: flipped)
    }

    private func flip() {
        Haptics.selection()
        withAnimation { flipped.toggle() }
    }

    private func answer(knew: Bool) {
        if knew { known += 1 } else { again.append(deck[index]) }
        Haptics.selection()
        flipped = false
        withAnimation(.minorMenu) { index += 1 }
    }

    private func restartCards() {
        deck = Flashcards.make(from: map).shuffled()
        resetProgress()
    }

    private func resetProgress() {
        index = 0
        known = 0
        again = []
        flipped = false
    }

    // MARK: - Quiz

    @ViewBuilder
    private var quiz: some View {
        if loadingQuiz {
            VStack(spacing: 14) {
                Spacer()
                ProgressView().tint(.white)
                Text("Writing questions about your map…")
                    .font(.system(size: 15))
                    .foregroundColor(MinorColor.textSecondary)
                Spacer()
            }
        } else if let quizError {
            VStack(spacing: 14) {
                Spacer()
                Text(quizError)
                    .font(.system(size: 15))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                if quizIsLimit {
                    wideButton(AccountStore.shared.isPaid ? "Get PRO" : "Get Minor Plus", primary: true) {
                        dismiss()
                        onUpgrade()
                    }
                    .padding(.horizontal, 40)
                } else {
                    wideButton(L("Try Again"), primary: true) { loadQuiz() }
                        .padding(.horizontal, 40)
                }
                Spacer()
            }
        } else if question >= questions.count, !questions.isEmpty {
            VStack(spacing: 16) {
                Spacer()
                Text(score * 10 >= questions.count * 8 ? "🏆" : score * 2 >= questions.count ? "👏" : "📚").font(.system(size: 54))
                Text(L("\(score) of \(questions.count) correct"))
                    .font(.system(size: 22, weight: .bold))
                Spacer()
                HStack(spacing: 10) {
                    wideButton(L("Retake"), primary: false) {
                        question = 0
                        score = 0
                        picked = nil
                    }
                    wideButton(L("New Questions"), primary: true) { loadQuiz() }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        } else if questions.indices.contains(question) {
            let item = questions[question]
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ProgressView(value: Double(question), total: Double(questions.count))
                        .tint(MinorColor.accent)
                    Text(L("Question \(question + 1) of \(questions.count)"))
                        .font(.system(size: 13).monospacedDigit())
                        .foregroundColor(MinorColor.textTertiary)
                    Text(item.question)
                        .font(.system(size: 21, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(item.options.enumerated()), id: \.offset) { i, option in
                        Button { choose(i, for: item) } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: optionIcon(i, item))
                                    .font(.system(size: 18))
                                    .foregroundColor(optionColor(i, item))
                                Text(option)
                                    .font(.system(size: 16))
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(theme.chatRectangle))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(picked == nil ? theme.chatStroke : optionColor(i, item).opacity(0.8), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(picked != nil)
                    }
                    if picked != nil {
                        if !item.why.isEmpty {
                            Text(item.why)
                                .font(.system(size: 15))
                                .foregroundColor(MinorColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        wideButton(question + 1 < questions.count ? L("Next Question") : L("See Result"), primary: true) {
                            picked = nil
                            withAnimation(.minorMenu) { question += 1 }
                        }
                    }
                }
                .padding(20)
            }
        }
    }

    private func optionIcon(_ i: Int, _ item: MapService.QuizQuestion) -> String {
        guard let picked else { return "circle" }
        if i == item.answer { return "checkmark.circle.fill" }
        return i == picked ? "xmark.circle.fill" : "circle"
    }

    private func optionColor(_ i: Int, _ item: MapService.QuizQuestion) -> Color {
        guard let picked else { return MinorColor.textSecondary }
        if i == item.answer { return MinorColor.accent }
        return i == picked ? MinorColor.dangerText : MinorColor.textTertiary
    }

    private func choose(_ i: Int, for item: MapService.QuizQuestion) {
        picked = i
        if i == item.answer {
            score += 1
            Haptics.success()
        } else {
            Haptics.error()
        }
    }

    private func loadQuiz() {
        guard AuthService.shared.isSignedIn, AIConsent.isGiven else {
            quizError = L("Sign in and allow AI in Settings to take a quiz.")
            return
        }
        loadingQuiz = true
        quizError = nil
        quizIsLimit = false
        let snapshot = map
        Task {
            defer { loadingQuiz = false }
            do {
                questions = try await MapService.shared.quiz(snapshot)
                question = 0
                score = 0
                picked = nil
            } catch {
                if case BackendError.limitReached(let kind) = error { AccountStore.shared.noteLimitReached(kind: kind) }
                quizIsLimit = (error as? BackendError)?.suggestsUpgrade ?? false
                quizError = (error as? LocalizedError)?.errorDescription ?? L("Something went wrong. Try again.")
            }
        }
    }

    // MARK: - Pieces

    private func placeholder(_ icon: String, _ title: String, _ text: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: icon).font(.system(size: 40)).foregroundColor(MinorColor.textTertiary)
            Text(title).font(.system(size: 18, weight: .semibold))
            Text(text)
                .font(.system(size: 15))
                .foregroundColor(MinorColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            Spacer()
        }
    }

    private func wideButton(_ title: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(primary ? .black : MinorColor.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Capsule().fill(primary ? MinorColor.accent : theme.chatRectangle))
                .overlay(Capsule().stroke(primary ? .clear : theme.chatStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
