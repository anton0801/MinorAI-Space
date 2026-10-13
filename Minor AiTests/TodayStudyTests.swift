//
//  TodayStudyTests.swift
//  Minor AiTests
//
//  Today: a task just ticked stays where it was for a moment, then goes; "Coming Up" is the
//  nearest open task after today; Completed leaves out today's. The quiz: an answer counts once,
//  the result and the review of mistakes come from the answers given (no new questions), and a
//  question links only an idea the map has.
//

import Foundation
import Testing
@testable import Minor_Ai

@MainActor
struct TodayStudyTests {
    private let calendar = Calendar.current
    private var now: Date { calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Date())! }

    private func map(_ setup: (inout MindMap, [UUID]) -> Void) -> MindMap {
        var map = MindMap(root: MindNode(title: "Plan", children: (1...5).map { MindNode(title: "Task \($0)") }))
        setup(&map, map.root.children.map(\.id))
        return map
    }

    @Test func aTickedTaskStaysInPlaceForAMoment() {
        let base = map { map, ids in
            map.root.update(ids[0]) { $0.isTask = true; $0.isDone = true; $0.due = calendar.date(byAdding: .day, value: -2, to: now) }
            map.root.update(ids[1]) { $0.isTask = true; $0.due = calendar.date(byAdding: .day, value: -1, to: now) }
        }
        let tasks = TaskAgenda.tasks(in: [base])
        let ticked = tasks.first { $0.title == "Task 1" }!.id
        let settling = TaskAgenda.sections(tasks, now: now, keep: [ticked])
        #expect(settling.first?.kind == .overdue)
        #expect(settling.first?.tasks.map(\.title) == ["Task 1", "Task 2"], "kept where it was, by its date")
        let settled = TaskAgenda.sections(tasks, now: now)
        #expect(settled.first?.tasks.map(\.title) == ["Task 2"], "then it leaves Overdue")
    }

    @Test func comingUpIsTheNearestOpenTaskAfterToday() {
        let plan = map { map, ids in
            map.root.update(ids[0]) { $0.isTask = true; $0.due = calendar.date(byAdding: .day, value: 5, to: now) }
            map.root.update(ids[1]) { $0.isTask = true; $0.isDone = true; $0.due = calendar.date(byAdding: .day, value: 1, to: now) }
            map.root.update(ids[2]) { $0.isTask = true; $0.due = calendar.date(byAdding: .day, value: 2, to: now) }
            map.root.update(ids[3]) { $0.isTask = true; $0.due = now }
            map.root.update(ids[4]) { $0.isTask = true }
        }
        let tasks = TaskAgenda.tasks(in: [plan])
        #expect(TaskAgenda.next(tasks, now: now)?.title == "Task 3", "not a done one, not today's, not one without a date")
    }

    @Test func completedLeavesOutTodaysTasks() {
        let plan = map { map, ids in
            map.root.update(ids[0]) { $0.isTask = true; $0.isDone = true; $0.due = now }
            map.root.update(ids[1]) { $0.isTask = true; $0.isDone = true; $0.due = calendar.date(byAdding: .day, value: -3, to: now) }
            map.root.update(ids[2]) { $0.isTask = true; $0.isDone = true }
            map.root.update(ids[3]) { $0.isTask = true; $0.isDone = true; $0.due = calendar.date(byAdding: .day, value: -1, to: now) }
        }
        let done = TaskAgenda.completed(TaskAgenda.tasks(in: [plan]), now: now)
        #expect(done.map(\.title) == ["Task 4", "Task 2", "Task 3"], "latest due first; today's stay in Today")
    }

    private func question(_ answer: Int, nodeID: UUID? = nil) -> MapService.QuizQuestion {
        MapService.QuizQuestion(question: "Q\(answer)", options: ["a", "b", "c"], answer: answer, why: "", src: nil, nodeID: nodeID)
    }

    @Test func anAnswerCountsOnce() {
        var quiz = QuizProgress(questions: [question(0), question(1), question(2)])
        let first = quiz.answer(2)
        let again = quiz.answer(0)
        #expect(first)
        #expect(!again, "a second tap on the same question changes nothing")
        #expect(quiz.answers[0] == 2 && quiz.score == 0)
        quiz.current = 1
        let second = quiz.answer(1)
        quiz.current = 2
        let missing = quiz.answer(7)
        let third = quiz.answer(0)
        #expect(second && third)
        #expect(!missing, "an option that isn't there")
        quiz.current = 3
        #expect(quiz.finished && quiz.score == 1)
        #expect(quiz.mistakes == [0, 2], "the review goes through these, no new questions")
    }

    @Test func aQuestionLinksOnlyAnIdeaTheMapHas() throws {
        let json = #"{"question": "Why?", "options": ["a", "b"], "answer": 1, "why": "Because.", "src": "n2", "nodeID": "00000000-0000-0000-0000-000000000001"}"#
        let decoded = try JSONDecoder().decode(MapService.QuizQuestion.self, from: Data(json.utf8))
        #expect(decoded.src == "n2")
        #expect(decoded.nodeID == nil, "the idea comes from the app's refs, never from the reply")
        let plan = MindMap(root: MindNode(title: "Plan", children: [MindNode(title: "A"), MindNode(title: "B")]))
        let (tree, refs) = MapRefs.make(plan.root)
        #expect(refs["n2"] == plan.root.children[0].id && tree.ref == "n1")
    }

    @Test func gradeLabelsRoundToTheMinute() {
        let again = StudyStore.next(nil, .again, now: Date())
        #expect(StudyStore.label(for: again).contains("10"), "Again comes back in 10 minutes, not 9")
    }
}
