//
//  EveryButtonUITests.swift
//  Minor AiUITests
//
//  Every button of the node panel, Today, the task, Study, presenting, export and Creating the Map
//  does what it says: the rest of what TodayStudyPresentUITests and MapPanelUITests don't press.
//

import XCTest

final class EveryButtonUITests: XCTestCase {
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

    private func button(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", text)).firstMatch
    }

    private func any(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    // MARK: - Node panel

    func testPanelButtons() {
        let app = launch(["-demoMap", "-demoSelect"])
        XCTAssertTrue(app.buttons["Add Branch"].waitForExistence(timeout: 10))

        // Rename keeps the idea, changes its name.
        press(app.buttons["Rename"])
        let alert = app.alerts["Rename"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let field = alert.textFields.firstMatch
        field.tap()
        field.press(forDuration: 1.0)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) { app.menuItems["Select All"].tap() }
        app.typeText("Plans")
        alert.buttons["Save"].tap()
        XCTAssertTrue(any(app, "Plans").waitForExistence(timeout: 5), "The new name shows in the panel")

        // Note opens the idea's card.
        press(button(app, "Note"))
        XCTAssertTrue(app.staticTexts["Delete Node"].waitForExistence(timeout: 5) || app.buttons["Delete Node"].waitForExistence(timeout: 1), "The note's card opens")
        press(app.buttons["Close"].firstMatch)
        XCTAssertTrue(app.buttons["Add Branch"].waitForExistence(timeout: 5))

        // A long press on Add Branch also adds at the same level.
        app.buttons["Add Branch"].press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Add at the Same Level"].waitForExistence(timeout: 5), "Add at the same level beside Add Branch")
        app.buttons["Add at the Same Level"].tap()
        XCTAssertTrue(app.alerts["Rename"].waitForExistence(timeout: 5), "The new idea is named at once")
        app.alerts["Rename"].buttons["Cancel"].tap()

        // × closes the panel.
        XCTAssertTrue(app.buttons["Close Panel"].firstMatch.waitForExistence(timeout: 5))
        press(app.buttons["Close Panel"].firstMatch)
        XCTAssertFalse(app.buttons["Add Branch"].waitForExistence(timeout: 2), "The panel closes")
    }

    func testDiscussOpensTheProjectChat() {
        let app = launch(["-demoMap", "-demoSelect"])
        press(button(app, "Discuss with Minor"))
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 5) || app.textFields.firstMatch.waitForExistence(timeout: 1), "The project's chat opens with its field")
        // Nothing is sent on its own: the chat waits with the idea as its context.
        XCTAssertFalse(app.staticTexts["Writing…"].exists)
    }

    func testDeleteFromMoreAsksAndCanBeUndone() {
        let app = launch(["-demoMap", "-demoSelect"])
        press(button(app, "More Actions"))
        let delete = button(app, "Delete Branch")
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        let sheet = app.scrollViews.containing(NSPredicate(format: "label BEGINSWITH 'Focus on Branch'")).firstMatch
        for _ in 0..<4 where delete.frame.maxY > app.windows.firstMatch.frame.maxY - 60 { sheet.swipeUp() }
        press(delete)
        // Pricing has ideas under it: the count is said before deleting.
        let confirm = app.buttons["Delete Node"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Deleting a branch asks first")
        confirm.tap()
        XCTAssertTrue(app.buttons["Undo"].firstMatch.waitForExistence(timeout: 5))
        press(app.buttons["Undo"].firstMatch)
        XCTAssertTrue(any(app, "Pricing").waitForExistence(timeout: 5), "Undo brings the branch back")
    }

    func testViewerSeesOnlyWhatCanBeRead() {
        let app = launch(["-demoViewer", "-demoSelect"])
        XCTAssertTrue(button(app, "More Actions").waitForExistence(timeout: 10), "The idea's panel shows for a viewer too")
        XCTAssertFalse(app.buttons["Add Branch"].exists, "Nothing that would change the map")
        XCTAssertFalse(app.buttons["Rename"].exists)
        press(button(app, "More Actions"))
        XCTAssertTrue(app.staticTexts["This map is shared with you to view."].waitForExistence(timeout: 5))
        XCTAssertFalse(button(app, "Delete Branch").exists)
        XCTAssertFalse(button(app, "Move").exists)
    }

    // MARK: - Today

    func testTodayButtons() {
        let app = launch(["-demoToday"])
        XCTAssertTrue(app.staticTexts["Overdue"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["1 of 3 tasks for today done"].exists, "Only today's tasks are counted")
        XCTAssertTrue(app.staticTexts["Today"].exists && app.staticTexts["This Week"].exists)

        // Filter → Show Completed.
        let filter = app.buttons["today.filter"].firstMatch
        XCTAssertTrue(filter.waitForExistence(timeout: 5))
        let frame = filter.frame
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
        XCTAssertTrue(app.buttons["Show Completed"].waitForExistence(timeout: 3) || app.switches["Show Completed"].waitForExistence(timeout: 1))
        (app.buttons["Show Completed"].exists ? app.buttons["Show Completed"] : app.switches["Show Completed"]).tap()
        XCTAssertTrue(app.staticTexts["Completed"].waitForExistence(timeout: 5))

        // A task: Tomorrow → Save Date moves it out of Overdue.
        press(button(app, "iPad in spring"))
        XCTAssertTrue(app.buttons["Save Date"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Save Date"].isEnabled, "Nothing to save before a change")
        press(button(app, "Tomorrow"))
        XCTAssertTrue(app.buttons["Save Date"].isEnabled)
        press(app.buttons["Save Date"])
        // The reminder says how things really are (here: notifications not asked yet).
        XCTAssertTrue(any(app, "Reminders aren’t allowed yet").waitForExistence(timeout: 5) || any(app, "The reminder is set").exists || any(app, "Notifications are off").exists)
        press(app.buttons["Close"].firstMatch)
        XCTAssertFalse(any(app, "Yesterday · Launch plan").waitForExistence(timeout: 2), "No longer overdue")

        // Open Idea in the Map from the task.
        press(button(app, "Launch in January"))
        press(button(app, "Open Idea in the Map"))
        XCTAssertTrue(app.buttons["Add Branch"].waitForExistence(timeout: 8), "The map opens with the task's idea selected")
        XCTAssertTrue(any(app, "Launch in January").exists)
    }

    func testTodayOpenMapsGoesToTheLibrary() {
        let app = launch(["-demoToday", "-demoTodayNone"])
        XCTAssertTrue(app.staticTexts["No tasks yet"].waitForExistence(timeout: 10))
        press(app.buttons["Open Maps"])
        XCTAssertTrue(app.staticTexts["Library"].waitForExistence(timeout: 5), "Open Maps shows the maps")
    }

    // MARK: - Study

    func testCardOpensItsIdeaAndTheSessionIsKept() {
        let app = launch(["-demoMap", "-demoStudy"])
        press(app.buttons["Show Answer"])
        press(button(app, "Good,"))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Card 2 of'")).firstMatch.waitForExistence(timeout: 5))
        press(app.buttons["Show Answer"])
        press(app.buttons["Open Idea"])
        XCTAssertTrue(app.buttons["Add Branch"].waitForExistence(timeout: 8), "The card's idea is selected on the map")

        // Back to Study (the map's More menu): the same card.
        press(app.buttons["Close Panel"].firstMatch)
        press(app.buttons.matching(NSPredicate(format: "label == 'More'")).firstMatch)
        let item = app.collectionViews.buttons["Study"]
        if item.waitForExistence(timeout: 3) { item.tap() } else { app.buttons["Study"].firstMatch.tap() }
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Card 2 of'")).firstMatch.waitForExistence(timeout: 5), "Study goes on where it was")
    }

    func testQuizSignedOutSaysToSignIn() {
        let app = launch(["-demoMap", "-demoStudy"])
        press(app.buttons["Quiz"])
        press(app.buttons["Create Questions"])
        XCTAssertTrue(app.staticTexts["Couldn’t create the questions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Sign In"].exists, "The action that fits: sign in, not a useless Retry")
        press(app.buttons["Back to Map"])
        XCTAssertFalse(app.buttons["Sign In"].waitForExistence(timeout: 2))
    }

    func testQuizNextQuestionAndResultButtons() {
        let app = launch(["-demoMap", "-demoStudy", "-demoQuiz"])
        XCTAssertTrue(app.staticTexts["Question 3 of 5"].waitForExistence(timeout: 10))
        press(button(app, "Go to the idea"))
        XCTAssertTrue(app.buttons["Add Branch"].waitForExistence(timeout: 8), "The question's idea opens on the map")

        let result = launch(["-demoMap", "-demoStudy", "-demoQuizResult"])
        XCTAssertTrue(result.staticTexts["Quiz Result"].waitForExistence(timeout: 10))
        XCTAssertFalse(result.buttons["Flashcards"].exists, "The result stands alone")
        press(result.buttons.matching(NSPredicate(format: "label CONTAINS 'Pricing'")).firstMatch)
        XCTAssertTrue(result.staticTexts["Mistake 1 of 1"].waitForExistence(timeout: 5), "A mistake opens its question")
        press(result.buttons["Back to Result"])
        press(result.buttons["Return to Map"])
        XCTAssertFalse(result.staticTexts["Quiz Result"].waitForExistence(timeout: 2))
    }

    // MARK: - Presenting and export

    func testPresenterButtons() {
        let app = launch(["-demoDeck", "-demoPresentDeck", "-demoPresenterView"])
        let header = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Presenter Mode'")).firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        XCTAssertTrue(header.label.contains("00:"), "The session's time: \(header.label)")
        press(app.buttons["presenter.back"])
        XCTAssertTrue(header.label.contains("2 of") || header.label.contains("3 of"), "Back goes a step back: \(header.label)")
        press(app.buttons["Full Screen"])
        XCTAssertTrue(app.buttons["Presenter View"].waitForExistence(timeout: 5), "The slide alone, full screen")
        press(app.buttons["Presenter View"])
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        press(app.buttons["End Presentation"])
        XCTAssertFalse(header.waitForExistence(timeout: 2))
    }

    func testExportReadyShareAndAnotherFormat() {
        let app = launch(["-demoDeck", "-demoExportSheet", "-demoPlus", "-demoExportReady"])
        XCTAssertTrue(app.staticTexts["File Ready"].waitForExistence(timeout: 30))
        press(app.buttons["Save or Share"])
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 8), "The system share sheet opens")
        // Closed without choosing anything: the ready file stays.
        app.otherElements["ActivityListView"].swipeDown(velocity: .fast)
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: app.otherElements["ActivityListView"])
        waitForExpectations(timeout: 8)
        XCTAssertTrue(app.staticTexts["File Ready"].waitForExistence(timeout: 5), "Closing the share sheet keeps the ready file")
        press(app.buttons["Another Format"])
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "another-format"
        shot.lifetime = .keepAlways
        add(shot)
        XCTAssertTrue(app.buttons["Create File"].waitForExistence(timeout: 5), "Back to the choices")
        press(app.buttons["Close"].firstMatch)
        XCTAssertFalse(app.buttons["Create File"].waitForExistence(timeout: 2))
    }

    // MARK: - Creating a map

    func testKeepCreatingAndBuildInBackground() {
        let app = launch(["-demoCreating", "-demoStopAsk"])
        XCTAssertTrue(app.staticTexts["Stop creating?"].waitForExistence(timeout: 10))
        press(app.buttons["Keep Creating"])
        XCTAssertFalse(app.staticTexts["Stop creating?"].waitForExistence(timeout: 2), "Keep Creating only closes the question")
        XCTAssertTrue(any(app, "Creating the Map").exists, "The same job goes on")
        press(app.buttons["Stop Creating"])
        press(app.buttons["Build in Background"])
        XCTAssertFalse(any(app, "Creating the Map").waitForExistence(timeout: 3), "The screen closes, the map is made meanwhile")
    }

    func testRetryKeepsTheSameJob() {
        let app = launch(["-demoCreateFailed"])
        XCTAssertTrue(app.buttons["Retry"].waitForExistence(timeout: 10))
        press(app.buttons["Retry"])
        // Signed out, the same job comes back with the reason that fits (sign in), not a second job.
        XCTAssertTrue(app.buttons["Sign In"].waitForExistence(timeout: 15) || any(app, "Creating the Map").exists)
    }
}
