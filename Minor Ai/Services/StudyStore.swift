//
//  StudyStore.swift
//  Minor Ai
//
//  Spaced repetition for flashcards: each card comes back after an interval that grows when
//  you know it and resets when you don't (a simplified SM-2, as in Anki). Kept on the phone in
//  Application Support/Study.json, by the id of the card's idea.
//

import Foundation

@MainActor
final class StudyStore: ObservableObject {
    static let shared = StudyStore()

    enum Grade: Int, CaseIterable { case again, hard, good, easy }

    struct CardState: Codable, Equatable {
        var ease = 2.5
        var interval = 0.0      // days
        var due = Date()
        var reps = 0
        var lapses = 0
    }

    @Published private(set) var states: [UUID: CardState] = [:]
    private let file: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        file = base.appendingPathComponent("Study.json")
        if let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder.iso.decode([UUID: CardState].self, from: data) {
            states = saved
        }
    }

    func state(_ id: UUID) -> CardState? { states[id] }

    // The next state of a card after an answer. Pure, so it can be shown on the buttons too.
    static func next(_ state: CardState?, _ grade: Grade, now: Date = Date()) -> CardState {
        var card = state ?? CardState()
        switch grade {
        case .again:
            card.reps = 0
            card.lapses += 1
            card.ease = max(1.3, card.ease - 0.2)
            card.interval = 0
            card.due = now.addingTimeInterval(10 * 60)
            return card
        case .hard:
            card.ease = max(1.3, card.ease - 0.15)
            card.interval = max(1, card.interval * 1.2)
        case .good:
            card.interval = card.reps == 0 ? 1 : card.reps == 1 ? 3 : (card.interval * card.ease).rounded()
        case .easy:
            card.interval = card.reps == 0 ? 4 : (card.interval * card.ease * 1.3).rounded()
            card.ease += 0.15
        }
        card.reps += 1
        card.due = now.addingTimeInterval(card.interval * 86_400)
        return card
    }

    func grade(_ id: UUID, _ grade: Grade) {
        states[id] = Self.next(states[id], grade)
        save()
    }

    // Cards already learned and due now: the ones to review.
    func isDue(_ id: UUID, now: Date = Date()) -> Bool {
        guard let state = states[id] else { return false }
        return state.due <= now
    }

    func dueCount(in map: MindMap, now: Date = Date()) -> Int {
        Flashcards.make(from: map).filter { isDue($0.id, now: now) }.count
    }

    // Maps with cards to review now, most first.
    func reviews(in maps: [MindMap], now: Date = Date()) -> [(map: MindMap, count: Int)] {
        maps.map { ($0, dueCount(in: $0, now: now)) }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
    }

    // When the next review is due across all maps, and how many cards by then (for the reminder).
    func nextReview(in maps: [MindMap]) -> (date: Date, count: Int)? {
        let ids = Set(maps.flatMap { Flashcards.make(from: $0).map(\.id) })
        let dues = states.filter { ids.contains($0.key) }.map(\.value.due).sorted()
        guard let first = dues.first else { return nil }
        let day = Calendar.current.startOfDay(for: first)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? first
        return (first, dues.filter { $0 < endOfDay }.count)
    }

    func forgetAll() {
        states = [:]
        try? FileManager.default.removeItem(at: file)
    }

    private func save() {
        guard let data = try? JSONEncoder.iso.encode(states) else { return }
        try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    // "10 min", "1 d", "3 d", "2 wk" for the answer buttons.
    static func label(for card: CardState, now: Date = Date()) -> String {
        let seconds = card.due.timeIntervalSince(now)
        if seconds < 3_600 { return L("\(max(1, Int(seconds / 60))) min") }
        let days = Int((seconds / 86_400).rounded())
        if days < 14 { return L("\(max(1, days)) d") }
        if days < 60 { return L("\(days / 7) wk") }
        return L("\(days / 30) mo")
    }
}

extension JSONEncoder {
    static let iso: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

extension JSONDecoder {
    static let iso: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
