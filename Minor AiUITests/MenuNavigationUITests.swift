//
//  MenuNavigationUITests.swift
//  Minor AiUITests
//
//  The Menu button on the assistant: it opens and closes quickly without leaving a layer behind
//  or losing the typed message, each place opens and Back returns to the menu, and the
//  assistant's "Create a Map" goes Back straight to the assistant. A conversation goes back to the
//  start screen with its Back button.
//

import XCTest

final class MenuNavigationUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-didOnboard", "YES", "-appLanguage", "en", "-auditSignedOut"] + extra
        app.launch()
        return app
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private var closeMenu: (XCUIApplication) -> XCUIElement { { $0.buttons["Back to Assistant"].firstMatch } }

    // A conversation's Back button returns to the start screen.
    func testChatBackReturnsHome() {
        let app = launch(["-isolatedStore", "uitest-chat-home", "-demoChat"])
        let home = app.buttons["Home"]
        XCTAssertTrue(home.waitForExistence(timeout: 10), "The conversation should show a way back")
        home.tap()
        XCTAssertTrue(app.staticTexts["What shall we think about?"].waitForExistence(timeout: 5), "Back should show the start screen")
        XCTAssertFalse(home.exists)
    }

    // Ten quick round trips: the draft stays, the menu always closes, the field still answers.
    func testOpenCloseKeepsDraft() {
        let app = launch()
        // A multi-line field is a text view.
        let field = app.textViews["Ask Minor"].exists ? app.textViews["Ask Minor"] : app.textFields["Ask Minor"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("Plan a trip")
        // A tap on empty space puts the keyboard away and brings the Menu button back.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
        let menu = app.buttons["Menu"]
        for round in 1...10 {
            XCTAssertTrue(menu.waitForExistence(timeout: 3), "Menu button missing on round \(round)")
            menu.tap()
            XCTAssertTrue(closeMenu(app).waitForExistence(timeout: 3), "The menu didn't open on round \(round)")
            closeMenu(app).tap()
        }
        XCTAssertTrue(menu.waitForExistence(timeout: 3))
        XCTAssertTrue(((field.value as? String) ?? "").contains("Plan a trip"), "The typed message was lost")
        shot(app, "after-10-rounds")
    }

    // Every place in the menu opens and Back returns to the menu.
    func testPlacesOpenAndReturn() {
        let app = launch(["-menu"])
        XCTAssertTrue(closeMenu(app).waitForExistence(timeout: 10))
        shot(app, "menu")
        for (tile, title) in [("New Map", "New Map"), ("Today", "Today"), ("Library", "Library")] {
            // The tile reads "New Map, From a topic or material" (the Library has its own New Map).
            let button = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", tile + ",")).firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 3), "\(tile) missing in the menu")
            button.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), "\(tile) didn't open")
            shot(app, tile)
            app.navigationBars.buttons["Menu"].tap()
            XCTAssertTrue(closeMenu(app).waitForExistence(timeout: 5), "Back from \(tile) didn't return to the menu")
        }
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Templates,'")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Templates"].waitForExistence(timeout: 5), "Templates didn't open")
        shot(app, "Templates")
        app.navigationBars.buttons["Menu"].tap()
        app.buttons.matching(NSPredicate(format: "label == 'Settings'")).allElementsBoundByIndex.first { $0.isHittable }?.tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5), "Settings didn't open")
    }

    // From the assistant, Create a Map opens New Map and Back goes to the assistant, not the menu.
    func testCreateMapFromAssistantReturnsToAssistant() {
        // The quick actions show when there is no project to continue.
        let app = launch(["-noResume"])
        let create = app.buttons["Create a Map"]
        XCTAssertTrue(create.waitForExistence(timeout: 10))
        create.tap()
        XCTAssertTrue(app.navigationBars["New Map"].waitForExistence(timeout: 5), "New Map didn't open")
        app.buttons["Back to Assistant"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Menu"].waitForExistence(timeout: 5), "Back should return to the assistant")
        XCTAssertFalse(app.navigationBars["New Map"].isHittable, "New Map should be gone")
    }
}
