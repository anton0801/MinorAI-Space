//
//  StudyView.swift
//  Minor Ai
//
//  Learn a map: flashcards made from its ideas (on the phone, free), and a quiz Minor writes about
//  it. A card shows an idea; "Show Answer" shows what is under it and its note, then four grades
//  (Again / Hard / Good / Easy, with when the card comes back) schedule it. The quiz starts only on
//  "Create Questions", marks your answer and the right one in words, explains it, links the idea a
//  question is about when Minor named one, and ends with a result whose mistakes can be gone
//  through again without new questions. The session is kept while the app runs, so going to the
//  map and back finds the same card and question.
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
    // The card shows the ideas as words: no task boxes or web addresses.
    static func make(from map: MindMap) -> [Flashcard] {
        var cards: [Flashcard] = []
        func text(_ node: MindNode) -> String { node.icon.map { "\($0) \(node.title)" } ?? node.title }
        func walk(_ node: MindNode, path: [String]) {
            for child in node.children where !child.isSuggestion {
                let back = child.children.filter { !$0.isSuggestion }.map(text)
                if !back.isEmpty || !child.note.isEmpty {
                    cards.append(Flashcard(id: child.id, context: path.suffix(2).joined(separator: " › "), front: text(child), back: back, note: child.note))
                }
                walk(child, path: path + [child.title])
            }
        }
        walk(map.root, path: [map.title])
        return cards
    }
}

// A quiz's answers and where it is: the result and its review come from these, never from new
// questions.
struct QuizProgress: Equatable {
    var questions: [MapService.QuizQuestion] = []
    var current = 0
    var answers: [Int: Int] = [:]          // question → the option picked
    var reviewing: [Int]?                  // the mistakes being gone through again
    var reviewPosition = 0

    var score: Int { questions.indices.filter { answers[$0] == questions[$0].answer }.count }
    var mistakes: [Int] { questions.indices.filter { answers[$0] != nil && answers[$0] != questions[$0].answer } }
    var finished: Bool { !questions.isEmpty && current >= questions.count }

    // An answer counts once: a second tap on the same question changes nothing.
    @discardableResult
    mutating func answer(_ option: Int) -> Bool {
        guard questions.indices.contains(current), answers[current] == nil,
              questions[current].options.indices.contains(option) else { return false }
        answers[current] = option
        return true
    }
}

struct StudyView: View {
    let map: MindMap
    let theme: AppTheme
    var onUpgrade: () -> Void = {}
    var onOpenNode: (UUID) -> Void = { _ in }

    enum Mode: String { case cards, quiz }

    // One session per map while the app runs.
    private struct Session {
        var mode: Mode
        var deck: [Flashcard]
        var index: Int
        var flipped: Bool
        var known: Int
        var again: [Flashcard]
        var practice: Bool
        var quiz: QuizProgress
    }
    @MainActor private static var sessions: [UUID: Session] = [:]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mode: Mode = .cards
    @State private var restored = false

    // Flashcards
    @State private var deck: [Flashcard] = []
    @State private var index = 0
    @State private var flipped = false
    @State private var known = 0
    @State private var again: [Flashcard] = []
    @State private var practice = false      // studying cards that aren't due yet
    @State private var grading = false
    @AccessibilityFocusState private var answerFocused: Bool
    @ObservedObject private var study = StudyStore.shared

    // Quiz
    @State private var quiz = QuizProgress()
    @State private var loadingQuiz = false
    @State private var quizError: QuizError?
    @State private var askConsent = false

    private enum QuizError: Equatable {
        case signIn, consent, limit(String), failed(String)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                // The quiz's result stands alone, as the design shows it.
                if !showsResult {
                    MinorSegments(items: [(Mode.cards, "Flashcards", nil), (Mode.quiz, "Quiz", nil)], selection: $mode)
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                }
                if mode == .cards {
                    cards
                } else {
                    quizView
                }
            }
            .foregroundColor(MinorColor.textPrimary)
            .background(theme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold))
                            Text("Back to Map").minorFont(16, maxScale: 1.2)
                        }
                        .foregroundColor(MinorColor.textPrimary)
                    }
                    .accessibilityLabel("Back to Map")
                }
                ToolbarItem(placement: .principal) {
                    // The quiz's result stands alone, without the title.
                    if !showsResult {
                    VStack(spacing: 1) {
                        Text("Study").minorFont(17, .semibold, maxScale: 1.2)
                        Text(map.title).minorFont(12, maxScale: 1.2).foregroundColor(MinorColor.textTertiary).lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                    }
                }
            }
            .sheet(isPresented: $askConsent) {
                AIConsentView(onAllow: { askConsent = false; loadQuiz() }, onDecline: { askConsent = false })
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            guard !restored else { return }
            restored = true
            if !restore() { restartCards() }
            applyDebugState()
            Telemetry.log("study_start", ["cards": deck.count])
        }
        .onDisappear(perform: keep)
    }

    private var showsResult: Bool {
        mode == .quiz && quiz.finished && quiz.reviewing == nil && !loadingQuiz && quizError == nil
    }

    // MARK: - Session

    private func keep() {
        Self.sessions[map.id] = Session(mode: mode, deck: deck, index: index, flipped: flipped, known: known, again: again, practice: practice, quiz: quiz)
    }

    // The same cards and quiz as when the person left, while the cards' ideas are still there.
    private func restore() -> Bool {
        guard let session = Self.sessions[map.id] else { return false }
        mode = session.mode
        quiz = session.quiz
        let ids = Set(Flashcards.make(from: map).map(\.id))
        guard session.deck.allSatisfy({ ids.contains($0.id) }) else { return false }
        deck = session.deck
        index = session.index
        flipped = session.flipped
        known = session.known
        again = session.again
        practice = session.practice
        return true
    }

    // MARK: - Flashcards

    @ViewBuilder
    private var cards: some View {
        if deck.isEmpty && Flashcards.make(from: map).isEmpty {
            placeholder("rectangle.on.rectangle.angled", L("No cards yet"), L("Cards are made from ideas that have ideas under them or a note. Add some to the map first.")) {
                wideButton(L("Back to Map"), primary: true) { dismiss() }
            }
        } else if deck.isEmpty {
            // Everything learned is scheduled for later.
            placeholder("checkmark.circle", L("All caught up"), study.nextReview(in: [map]).map {
                L("Next review: \($0.date.formatted(.dateTime.day().month(.wide).hour().minute().locale(AppLanguage.current.locale)))")
            } ?? L("No cards are due.")) {
                wideButton(L("Practice Anyway"), primary: false) {
                    practice = true
                    restartCards()
                }
            }
        } else if index >= deck.count {
            placeholder("checkmark.circle", L("You knew \(known) of \(deck.count)"), again.isEmpty ? L("Every card is scheduled for its next review.") : L("\(again.count) cards to repeat")) {
                if !again.isEmpty {
                    wideButton(L("Repeat \(again.count)"), primary: true) {
                        deck = again.shuffled()
                        resetProgress()
                    }
                }
                wideButton(L("Start Over"), primary: again.isEmpty) { restartCards() }
            }
        } else {
            let card = deck[index]
            VStack(spacing: 12) {
                VStack(spacing: 8) {
                    Text(L("Card \(index + 1) of \(deck.count)"))
                        .minorFont(14, maxScale: 1.3)
                        .monospacedDigit()
                        .foregroundColor(MinorColor.textSecondary)
                    // The position, as the words above say ("Card 3 of 12").
                    progressBar(Double(index + 1) / Double(max(1, deck.count)))
                }
                .padding(.horizontal, 20)
                .accessibilityElement(children: .combine)
                ZStack {
                    if flipped {
                        cardBack(card).transition(.opacity)
                    } else {
                        cardFront(card).transition(.opacity)
                    }
                }
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 20)
                if flipped {
                    grades(card)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                        .transition(.opacity)
                } else {
                    VStack(spacing: 10) {
                        Text("Try to recall it first")
                            .minorFont(14, maxScale: 1.3)
                            .foregroundColor(MinorColor.textSecondary)
                        wideButton(L("Show Answer"), primary: true) { flip() }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private func cardFront(_ card: Flashcard) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(card.context)
                .minorFont(14, maxScale: 1.3)
                .foregroundColor(MinorColor.textSecondary)
                .lineLimit(2)
            Text(card.front)
                .minorFont(28, .bold, maxScale: 1.3)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            StudyConnector()
                .frame(width: 100, height: 40)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(theme.chatRectangle))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(theme.chatStroke, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { flip() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text("Shows the answer"))
    }

    // The answer scrolls when it is long; the grades stay below it, never over its last line.
    private func cardBack(_ card: Flashcard) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(card.front)
                    .minorFont(24, .bold, maxScale: 1.3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 10)
                    .accessibilityFocused($answerFocused)
                ForEach(Array(card.back.enumerated()), id: \.offset) { i, line in
                    HStack(alignment: .top, spacing: 12) {
                        Circle().fill(MinorColor.accent).frame(width: 8, height: 8).padding(.top, 7)
                        Text(line).minorFont(17, maxScale: 1.4).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 12)
                    .overlay(alignment: .bottom) {
                        if i < card.back.count - 1 { Rectangle().fill(theme.chatStroke).frame(height: 1) }
                    }
                }
                if !card.note.isEmpty {
                    Text(card.note)
                        .minorFont(15, maxScale: 1.4)
                        .foregroundColor(MinorColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                }
                Rectangle().fill(theme.chatStroke).frame(height: 1).padding(.top, 12)
                Button { leave(to: card.id) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "point.3.connected.trianglepath.dotted").foregroundColor(Color(hex: "#7CC4FF"))
                        Text("Open Idea").minorFont(15, .medium, maxScale: 1.3).foregroundColor(Color(hex: "#7CC4FF"))
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundColor(MinorColor.textTertiary)
                    }
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(theme.chatRectangle))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(theme.chatStroke, lineWidth: 1))
    }

    // Again / Hard / Good / Easy in two rows, with when the card comes back after each.
    private func grades(_ card: Flashcard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How well did you remember?")
                .minorFont(18, .semibold, maxScale: 1.3)
                .accessibilityAddTraits(.isHeader)
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    gradeButton(.again, card: card)
                    gradeButton(.hard, card: card)
                }
                GridRow {
                    gradeButton(.good, card: card)
                    gradeButton(.easy, card: card)
                }
            }
        }
    }

    private func flip() {
        guard !flipped else { return }
        Haptics.selection()
        withAnimation(.easeInOut(duration: 0.18)) { flipped = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { answerFocused = true }
    }

    // How well you knew it decides when the card comes back.
    private func gradeButton(_ grade: StudyStore.Grade, card: Flashcard) -> some View {
        let next = StudyStore.next(study.state(card.id), grade)
        let title: String
        let color: Color
        switch grade {
        case .again: title = L("Again"); color = Color(hex: "#FF6B6B")
        case .hard: title = L("Hard"); color = Color(hex: "#FFB547")
        case .good: title = L("Good"); color = MinorColor.accent
        case .easy: title = L("Easy"); color = Color(hex: "#4D8DFF")
        }
        let when = StudyStore.longLabel(for: next)
        return Button { answer(grade) } label: {
            HStack(spacing: 12) {
                Circle().fill(color).frame(width: 12, height: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).minorFont(17, .semibold, maxScale: 1.3)
                    Text(when).minorFont(13, maxScale: 1.3).foregroundColor(MinorColor.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .foregroundColor(MinorColor.textPrimary)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(RoundedRectangle(cornerRadius: 14).fill(color.opacity(0.1)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.45), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .disabled(grading)
        .accessibilityLabel("\(title), \(when)")
    }

    // Each grade is written once: a second tap while the next card comes changes nothing.
    private func answer(_ grade: StudyStore.Grade) {
        guard !grading, deck.indices.contains(index), flipped else { return }
        grading = true
        let card = deck[index]
        study.grade(card.id, grade)
        if grade == .again { again.append(card) } else { known += 1 }
        Haptics.selection()
        withAnimation(reduceMotion ? .easeInOut(duration: 0.18) : .minorMenu) {
            flipped = false
            index += 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { grading = false }
    }

    // Cards due for review first, then new ones (up to 20 a session); practice takes them all.
    private func restartCards() {
        let all = Flashcards.make(from: map)
        #if DEBUG
        // The App Store preview's sample goes through its cards in the map's order.
        if DemoStory.isOn {
            deck = all
            return resetProgress()
        }
        #endif
        if practice {
            deck = all.shuffled()
        } else {
            let due = all.filter { study.isDue($0.id) }.shuffled()
            let new = all.filter { study.state($0.id) == nil }.shuffled().prefix(20)
            deck = due + new
        }
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
    private var quizView: some View {
        if loadingQuiz {
            VStack(spacing: 14) {
                Spacer()
                ProgressView().tint(.white)
                Text("Writing questions about your map…")
                    .minorFont(15, maxScale: 1.3)
                    .foregroundColor(MinorColor.textSecondary)
                Spacer()
            }
            .accessibilityElement(children: .combine)
        } else if let quizError {
            quizErrorView(quizError)
        } else if let reviewing = quiz.reviewing, quiz.reviewPosition < reviewing.count {
            questionView(reviewing[quiz.reviewPosition], review: true)
        } else if quiz.finished {
            result
        } else if quiz.questions.indices.contains(quiz.current) {
            questionView(quiz.current, review: false)
        } else {
            placeholder("questionmark.bubble", L("Test yourself"), L("Minor writes questions about this map. A new test counts toward your AI limits.")) {
                wideButton(L("Create Questions"), primary: true) { loadQuiz() }
            }
        }
    }

    private func quizErrorView(_ error: QuizError) -> some View {
        let text: String
        switch error {
        case .signIn: text = L("Sign in to take a quiz: Minor writes the questions on the server.")
        case .consent: text = L("Allow AI to take a quiz: the map is sent to write the questions.")
        case .limit(let message), .failed(let message): text = message
        }
        return placeholder("exclamationmark.bubble", L("Couldn’t create the questions"), text) {
            switch error {
            case .signIn:
                wideButton(L("Sign In"), primary: true) {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { AuthGate.shared.require {} }
                }
            case .consent:
                wideButton(L("Allow AI"), primary: true) { askConsent = true }
            case .limit:
                wideButton(AccountStore.shared.isPaid ? L("Get PRO") : L("Get Plus"), primary: true) {
                    dismiss()
                    onUpgrade()
                }
            case .failed:
                wideButton(L("Try Again"), primary: true) { loadQuiz() }
            }
        }
    }

    private func questionView(_ i: Int, review: Bool) -> some View {
        let item = quiz.questions[i]
        let picked = quiz.answers[i]
        let node = item.nodeID.flatMap { map.root.node($0) }
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(review ? L("Mistake \(quiz.reviewPosition + 1) of \(quiz.reviewing?.count ?? 0)") : L("Question \(i + 1) of \(quiz.questions.count)"))
                            .minorFont(14, maxScale: 1.3)
                            .monospacedDigit()
                            .foregroundColor(MinorColor.textSecondary)
                        Spacer()
                        if !review { dashes(current: i) }
                    }
                    if let node {
                        Text(place(of: node.id))
                            .minorFont(13, maxScale: 1.3)
                            .foregroundColor(MinorColor.textSecondary)
                            .lineLimit(2)
                    }
                    Text(item.question)
                        .minorFont(26, .bold, maxScale: 1.3)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    // Before answering every option; after it, your answer and the right one.
                    VStack(spacing: 10) {
                        ForEach(Array(item.options.enumerated()), id: \.offset) { o, option in
                            if picked == nil || o == picked || o == item.answer {
                                optionRow(option, index: o, item: item, picked: picked, review: review)
                                    .transition(.opacity)
                            }
                        }
                    }
                    .animation(reduceMotion ? nil : .minorMenu, value: picked)
                    if picked != nil {
                        Rectangle().fill(theme.chatStroke).frame(height: 1).padding(.top, 6)
                        if !item.why.isEmpty {
                            Text("Why").minorFont(20, .bold, maxScale: 1.3).accessibilityAddTraits(.isHeader)
                            Text(item.why)
                                .minorFont(16, maxScale: 1.4)
                                .foregroundColor(MinorColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Button {
                            if let node { leave(to: node.id) } else { dismiss() }
                        } label: {
                            HStack {
                                Text(node.map { L("Go to the idea “\($0.title)”") } ?? L("Open the Map"))
                                    .minorFont(16, maxScale: 1.3)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundColor(MinorColor.textTertiary)
                            }
                            .frame(minHeight: 48)
                            .overlay(alignment: .bottom) { Rectangle().fill(theme.chatStroke).frame(height: 1) }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 16)
            }
            if picked != nil {
                Group {
                    if review {
                        let last = quiz.reviewPosition + 1 >= (quiz.reviewing?.count ?? 0)
                        wideButton(last ? L("Back to Result") : L("Next Mistake"), primary: true) {
                            withAnimation(.minorMenu) {
                                if last { quiz.reviewing = nil; quiz.reviewPosition = 0 } else { quiz.reviewPosition += 1 }
                            }
                        }
                    } else {
                        wideButton(i + 1 < quiz.questions.count ? L("Next Question") : L("See Result"), primary: true) {
                            withAnimation(.minorMenu) { quiz.current += 1 }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
        }
    }

    // Your answer and the right one, said in words and with a sign, not only by colour.
    private func optionRow(_ option: String, index o: Int, item: MapService.QuizQuestion, picked: Int?, review: Bool) -> some View {
        let isAnswer = o == item.answer
        let isPicked = o == picked
        let shown = picked != nil
        let caption: String? = !shown ? nil : isPicked && isAnswer ? L("Your answer · Correct") : isPicked ? L("Your answer") : isAnswer ? L("Correct answer") : nil
        let tint: Color = !shown ? MinorColor.textSecondary : isAnswer ? MinorColor.accent : isPicked ? Color(hex: "#FF6B6B") : MinorColor.textTertiary
        return Button {
            guard !review, quiz.answer(o) else { return }
            o == item.answer ? Haptics.success() : Haptics.error()
            UIAccessibility.post(notification: .announcement, argument: o == item.answer ? L("Correct answer") : L("Wrong answer"))
        } label: {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    if shown && (isAnswer || isPicked) {
                        Circle().fill(tint)
                        Image(systemName: isAnswer ? "checkmark" : "xmark").font(.system(size: 13, weight: .bold)).foregroundColor(.black)
                    } else {
                        Circle().stroke(tint, lineWidth: 1.5)
                    }
                }
                .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option)
                        .minorFont(17, .medium, maxScale: 1.4)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let caption {
                        Text(caption).minorFont(13, maxScale: 1.3).foregroundColor(MinorColor.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(shown && (isAnswer || isPicked) ? tint.opacity(0.1) : theme.chatRectangle))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(shown && (isAnswer || isPicked) ? tint.opacity(0.55) : theme.chatStroke, lineWidth: 1))
            .opacity(shown && !isAnswer && !isPicked ? 0.55 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Not .disabled: that would dim the marked answers too.
        .allowsHitTesting(!shown && !review)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isPicked ? .isSelected : [])
    }

    // How many were right, what to look at again, a review of the mistakes (no new questions), a
    // new test (new questions, on request) and the way back.
    private var result: some View {
        let total = quiz.questions.count
        let score = quiz.score
        let mistakes = quiz.mistakes
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Quiz Result").minorFont(26, .bold, maxScale: 1.3).accessibilityAddTraits(.isHeader)
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(score)").minorFont(64, .heavy, maxScale: 1.2).foregroundColor(MinorColor.accent)
                        Text(L("of \(total)")).minorFont(56, .bold, maxScale: 1.2)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L("\(score) of \(total) correct"))
                    Text("correct answers").minorFont(17, maxScale: 1.3).foregroundColor(MinorColor.textSecondary).accessibilityHidden(true)
                    HStack(spacing: 10) {
                        progressBar(Double(score) / Double(max(1, total)))
                        Text("\(Int((Double(score) / Double(max(1, total)) * 100).rounded()))%")
                            .minorFont(13, maxScale: 1.2)
                            .monospacedDigit()
                            .foregroundColor(MinorColor.textSecondary)
                    }
                    .accessibilityHidden(true)
                    Text(mistakes.isEmpty ? L("All answers are correct.") : L("\(mistakes.count) questions left to go through."))
                        .minorFont(15, maxScale: 1.3)
                        .foregroundColor(MinorColor.textSecondary)
                    if !mistakes.isEmpty {
                        Text("Worth Repeating").minorFont(22, .bold, maxScale: 1.3).padding(.top, 12).accessibilityAddTraits(.isHeader)
                        ForEach(mistakes, id: \.self) { i in
                            mistakeRow(i, in: mistakes)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            VStack(spacing: 10) {
                if !mistakes.isEmpty {
                    wideButton(mistakes.count == 1 ? L("Review the Mistake") : L("Review the Mistakes"), primary: true) {
                        withAnimation(.minorMenu) {
                            quiz.reviewing = mistakes
                            quiz.reviewPosition = 0
                        }
                    }
                }
                wideButton(L("New Test"), primary: mistakes.isEmpty) { loadQuiz() }
                Button("Return to Map") { dismiss() }
                    .minorFont(16, maxScale: 1.3)
                    .foregroundColor(MinorColor.textSecondary)
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
    }

    private func mistakeRow(_ i: Int, in mistakes: [Int]) -> some View {
        let item = quiz.questions[i]
        let node = item.nodeID.flatMap { map.root.node($0) }
        return Button {
            withAnimation(.minorMenu) {
                quiz.reviewing = mistakes
                quiz.reviewPosition = mistakes.firstIndex(of: i) ?? 0
            }
        } label: {
            HStack(spacing: 12) {
                Group {
                    if let icon = node?.icon {
                        Text(icon).font(.system(size: 20))
                    } else {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(BranchColor.lilac.color)
                    }
                }
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 10).fill(BranchColor.lilac.color.opacity(0.15)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(BranchColor.lilac.color.opacity(0.6), lineWidth: 1))
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(node?.title ?? item.question)
                        .minorFont(16, .medium, maxScale: 1.3)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let node {
                        Text(place(of: node.id)).minorFont(13, maxScale: 1.3).foregroundColor(MinorColor.textSecondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundColor(MinorColor.textTertiary)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(theme.chatRectangle))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.chatStroke, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Shows this question with your answer"))
    }

    // Starts only by an explicit button: switching to Quiz never spends a generation.
    private func loadQuiz() {
        guard AuthService.shared.isSignedIn else { quizError = .signIn; return }
        guard AIConsent.isGiven else { quizError = .consent; return }
        guard !loadingQuiz else { return }
        loadingQuiz = true
        quizError = nil
        let snapshot = map
        Task {
            defer { loadingQuiz = false }
            do {
                let questions = try await MapService.shared.quiz(snapshot)
                Telemetry.log("quiz_start", ["questions": questions.count])
                quiz = QuizProgress(questions: questions)
            } catch {
                if case BackendError.limitReached(let kind) = error { AccountStore.shared.noteLimitReached(kind: kind) }
                let message = (error as? LocalizedError)?.errorDescription ?? L("Something went wrong. Try again.")
                quizError = ((error as? BackendError)?.suggestsUpgrade ?? false) ? .limit(message) : .failed(message)
            }
        }
    }

    // Screenshots without the server: -demoQuiz (a quiz about the demo map, the third question
    // answered wrong), -demoQuizResult (all answered, two wrong), -demoCardBack (the answer shown).
    private func applyDebugState() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-demoCardBack"), !deck.isEmpty { flipped = true }
        guard args.contains("-demoQuiz") || args.contains("-demoQuizResult") else { return }
        mode = .quiz
        let branches = map.root.children
        func idea(_ i: Int) -> UUID? { branches.indices.contains(i) ? branches[i].id : nil }
        let english = AppLanguage.current.locale.language.languageCode?.identifier != "ru"
        func q(_ en: String, _ ru: String, _ options: [(String, String)], _ answer: Int, _ whyEn: String, _ whyRu: String, _ node: UUID?) -> MapService.QuizQuestion {
            MapService.QuizQuestion(question: english ? en : ru, options: options.map { english ? $0.0 : $0.1 }, answer: answer, why: english ? whyEn : whyRu, src: nil, nodeID: node)
        }
        var progress = QuizProgress(questions: [
            q("Who is the app for first?", "Для кого приложение в первую очередь?", [("Students, creators and small teams", "Студенты, авторы и небольшие команды"), ("Large banks", "Крупные банки"), ("Game studios", "Игровые студии"), ("Only researchers", "Только исследователи")], 0, "The audience branch names students, creators and small teams.", "Ветка «Аудитория» называет студентов, авторов и небольшие команды.", idea(0)),
            q("What sets Minor apart?", "Чем выделяется Minor?", [("AI first and simple by design", "ИИ в основе и простой дизайн"), ("The lowest price", "Самая низкая цена"), ("Only offline work", "Только офлайн"), ("A web version", "Веб-версия")], 0, "Positioning puts AI first and keeps the design simple.", "Позиционирование: ИИ в основе и простой дизайн.", idea(1)),
            q("What should be checked before launch?", "Что проверить перед запуском?", [("Only the app name", "Только название приложения"), ("Pricing and the free allowance", "Тарифы и бесплатный лимит"), ("The icon colour", "Цвет иконки"), ("Nothing", "Ничего")], 1, "Pricing decides what people try for free and when they upgrade.", "Тарифы решают, что можно попробовать бесплатно и когда переходить на Plus.", idea(2)),
            q("Which channel brings the first users?", "Какой канал даёт первых пользователей?", [("App Store search", "Поиск в App Store"), ("Billboards", "Билборды"), ("Radio", "Радио"), ("Print", "Печать")], 0, "Channels start with App Store search.", "Каналы начинаются с поиска в App Store.", idea(3)),
            q("What is the main risk?", "Какой главный риск?", [("API costs", "Расходы на API"), ("Too many maps", "Слишком много карт"), ("Dark theme", "Тёмная тема"), ("Fonts", "Шрифты")], 0, "Model costs grow with use.", "Расходы на модели растут вместе с использованием.", idea(5)),
        ])
        progress.answers = [0: 0, 1: 0]
        progress.current = 2
        if args.contains("-demoQuizResult") {
            progress.answers = [0: 0, 1: 0, 2: 0, 3: 0, 4: 0]
            progress.current = 5
        } else {
            progress.answers[2] = 0
        }
        quiz = progress
    }

    // MARK: - Pieces

    private func leave(to id: UUID) {
        keep()
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { onOpenNode(id) }
    }

    private func place(of id: UUID) -> String {
        (map.root.path(to: id) ?? []).suffix(2).map(\.title).joined(separator: " › ")
    }

    private func progressBar(_ value: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(MinorColor.accent).frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: 6)
    }

    private func dashes(current: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(quiz.questions.indices, id: \.self) { i in
                Capsule()
                    .fill(i <= current ? MinorColor.accent : Color.white.opacity(0.18))
                    .frame(width: quiz.questions.count > 8 ? 10 : 18, height: 5)
            }
        }
        .accessibilityHidden(true)
    }

    private func placeholder<Actions: View>(_ icon: String, _ title: String, _ text: String, @ViewBuilder actions: () -> Actions) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 40, weight: .light))
                .foregroundColor(MinorColor.textSecondary)
                .accessibilityHidden(true)
            Text(title)
                .minorFont(22, .bold, maxScale: 1.3)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(text)
                .minorFont(15, maxScale: 1.4)
                .foregroundColor(MinorColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            VStack(spacing: 10) { actions() }
                .padding(.bottom, 8)
        }
        .padding(.horizontal, 24)
    }

    private func wideButton(_ title: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .minorFont(17, .semibold, maxScale: 1.3)
                .foregroundColor(primary ? .black : MinorColor.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(primary ? Color.white : theme.chatRectangle))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(primary ? .clear : theme.chatStroke, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
    }
}

// Three ideas joined by a line: the quiet picture on a card's front.
private struct StudyConnector: View {
    var body: some View {
        Canvas { ctx, size in
            let a = CGPoint(x: 8, y: 8), b = CGPoint(x: size.width / 2, y: size.height - 8), c = CGPoint(x: size.width - 8, y: 4)
            var path = Path()
            path.move(to: a)
            path.addCurve(to: b, control1: CGPoint(x: a.x + 18, y: a.y), control2: CGPoint(x: b.x - 18, y: b.y))
            path.addCurve(to: c, control1: CGPoint(x: b.x + 18, y: b.y), control2: CGPoint(x: c.x - 18, y: c.y))
            ctx.stroke(path, with: .color(MinorColor.accent), lineWidth: 2)
            for p in [a, b, c] {
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)), with: .color(MinorColor.accent))
            }
        }
    }
}
