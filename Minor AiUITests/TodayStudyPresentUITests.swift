//
//  TodayStudyPresentUITests.swift
//  Minor AiUITests
//
//  Today: a task opens its details, a tick can be undone, a day without tasks shows what comes
//  next. Study: grades only after the answer, a quiz review without new questions, no generation
//  on switching to Quiz. Export: PowerPoint without Plus opens the subscription and comes back to
//  the same choices; a paid export ends with the file ready. Presenting: the session's place and
//  Next. Creating a map: Stop puts the topic back into the field.
//

import XCTest

final class TodayStudyPresentUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-didOnboard", "YES", "-appLanguage", "en", "-auditSignedOut"] + args
        app.launch()
        return app
    }

    // Screens kept alive underneath still count for XCUITest's hit test: tap where drawn.
    private func press(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), "\(element) should exist")
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func button(_ app: XCUIApplication, startingWith text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", text)).firstMatch
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - Today

    func testTodayTaskOpensDetailsAndTickCanBeUndone() {
        let app = launch(["-demoToday"])
        XCTAssertTrue(app.staticTexts["Overdue"].waitForExistence(timeout: 10))
        press(button(app, startingWith: "iPad in spring"))
        XCTAssertTrue(app.buttons["Save Date"].waitForExistence(timeout: 5), "A tap opens the task's details, not the map")
        XCTAssertTrue(button(app, startingWith: "Open Idea in the Map").exists)
        press(app.buttons["Close"].firstMatch)

        press(app.buttons["Mark “iPad in spring” as done"])
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 3), "Done · Undo")
        shot(app, "today-done")
        press(app.buttons["Undo"])
        XCTAssertTrue(app.buttons["Mark “iPad in spring” as done"].waitForExistence(timeout: 5), "Undo opens the task again")
    }

    func testDayWithoutTasksShowsWhatComesNext() {
        let app = launch(["-demoToday", "-demoTodayClear"])
        XCTAssertTrue(app.staticTexts["No tasks for today"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Coming Up"].exists)
        XCTAssertTrue(app.buttons["Open Maps"].exists)
        press(app.buttons["See the Week"])
        XCTAssertTrue(app.staticTexts["This Week"].waitForExistence(timeout: 5), "The week's tasks show")
    }

    // MARK: - Study

    func testGradesComeOnlyAfterTheAnswer() {
        let app = launch(["-demoMap", "-demoStudy"])
        XCTAssertTrue(app.buttons["Show Answer"].waitForExistence(timeout: 10))
        XCTAssertFalse(button(app, startingWith: "Good,").exists, "No grades before the answer")
        press(app.buttons["Show Answer"])
        for grade in ["Again,", "Hard,", "Good,", "Easy,"] {
            XCTAssertTrue(button(app, startingWith: grade).waitForExistence(timeout: 3), "\(grade) should be offered")
        }
        XCTAssertTrue(button(app, startingWith: "Again, In 10").exists, "When the card comes back, from StudyStore")
        press(button(app, startingWith: "Good,"))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Card 2 of'")).firstMatch.waitForExistence(timeout: 5))
    }

    func testSwitchingToQuizDoesNotStartAGeneration() {
        let app = launch(["-demoMap", "-demoStudy"])
        XCTAssertTrue(app.buttons["Show Answer"].waitForExistence(timeout: 10))
        press(app.buttons["Quiz"])
        XCTAssertTrue(app.buttons["Create Questions"].waitForExistence(timeout: 5), "Questions are made only on request")
        XCTAssertFalse(app.staticTexts["Writing questions about your map…"].exists)
    }

    func testQuizMarksAnswersAndReviewsMistakes() {
        let app = launch(["-demoMap", "-demoStudy", "-demoQuiz"])
        XCTAssertTrue(app.staticTexts["Question 3 of 5"].waitForExistence(timeout: 10))
        XCTAssertTrue(button(app, startingWith: "Only the app name").exists)
        XCTAssertTrue(app.staticTexts["Your answer"].exists && app.staticTexts["Correct answer"].exists, "Said in words, not only by colour")
        shot(app, "quiz-feedback")

        let result = launch(["-demoMap", "-demoStudy", "-demoQuizResult"])
        XCTAssertTrue(result.staticTexts["Quiz Result"].waitForExistence(timeout: 10))
        press(result.buttons["Review the Mistake"])
        XCTAssertTrue(result.staticTexts["Mistake 1 of 1"].waitForExistence(timeout: 5), "Answered questions, no new ones")
        XCTAssertFalse(result.staticTexts["Writing questions about your map…"].exists)
        press(result.buttons["Back to Result"])
        XCTAssertTrue(result.staticTexts["Quiz Result"].waitForExistence(timeout: 5))
    }

    // MARK: - Export and presenting

    func testFreeExportOpensThePlanAndKeepsTheChoices() {
        let app = launch(["-demoDeck", "-demoHiddenSlide", "-demoExportSheet", "-demoFree"])
        XCTAssertTrue(app.buttons["Create PDF"].waitForExistence(timeout: 10), "PDF is ready to make without a plan")
        let toggle = app.switches.firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        toggle.switches.firstMatch.tap()
        XCTAssertEqual(toggle.value as? String, "1")
        press(app.buttons["PowerPoint, requires Plus"])
        XCTAssertTrue(app.buttons["Close"].firstMatch.waitForExistence(timeout: 5), "The subscription opens over the export")
        shot(app, "export-paywall")
        press(app.buttons["Close"].firstMatch)
        XCTAssertTrue(app.buttons["Create PDF"].waitForExistence(timeout: 5), "Back to the same export")
        XCTAssertEqual(app.switches.firstMatch.value as? String, "1", "Hidden slides stay included")
        XCTAssertFalse(app.staticTexts["File Ready"].exists, "Nothing was exported on its own")
    }

    func testPaidExportEndsWithTheFileReady() {
        let app = launch(["-demoDeck", "-demoExportSheet", "-demoPlus"])
        XCTAssertTrue(app.buttons["Create File"].waitForExistence(timeout: 10))
        press(button(app, startingWith: "PDF,"))
        press(app.buttons["Create File"])
        XCTAssertTrue(app.staticTexts["File Ready"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["Save or Share"].exists)
        shot(app, "export-ready")
        press(app.buttons["Another Format"])
        XCTAssertTrue(app.buttons["Create File"].waitForExistence(timeout: 5))
    }

    func testPresenterShowsWhereTheShowIs() {
        let app = launch(["-demoDeck", "-demoPresentDeck", "-demoPresenterView"])
        let header = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Presenter Mode'")).firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        XCTAssertTrue(header.label.contains("3 of"), "Started at the third slide: \(header.label)")
        shot(app, "presenter")
        // Next shows a slide's builds first, then the next slide.
        for _ in 0..<10 where !header.label.contains("4 of") {
            press(app.buttons["presenter.next"])
        }
        XCTAssertTrue(header.label.contains("4 of"), "Next reaches the fourth slide: \(header.label)")
        XCTAssertTrue(app.buttons["presenter.back"].isEnabled)
        press(app.buttons["End Presentation"])
        XCTAssertFalse(header.waitForExistence(timeout: 2))
    }

    // MARK: - Creating a map

    func testStopPutsTheTopicBack() {
        let app = launch(["-demoCreating"])
        XCTAssertTrue(app.staticTexts["Creating the Map"].waitForExistence(timeout: 10))
        press(app.buttons["Stop Creating"])
        XCTAssertTrue(app.staticTexts["Stop creating?"].waitForExistence(timeout: 5))
        press(app.buttons["Stop"])
        let field = app.textFields.matching(NSPredicate(format: "value CONTAINS 'Podcast launch plan'")).firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "The topic is back in New Map's field")
    }

    func testFailureKeepsTheInputAndOffersTryAgain() {
        let app = launch(["-demoCreateFailed"])
        XCTAssertTrue(app.staticTexts["Couldn’t get the result"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Podcast launch plan: preparation, recording and promotion"].exists, "The input stays on screen")
        XCTAssertTrue(app.buttons["Retry"].exists && app.buttons["Change Topic"].exists)
        shot(app, "create-failed")
        press(app.buttons["Change Topic"])
        let field = app.textFields.matching(NSPredicate(format: "value CONTAINS 'Podcast launch plan'")).firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "The topic is back to edit")
    }
}
