//
//  ProjectTabsUITests.swift
//  Minor AiUITests
//
//  A map opens as a project with Map, Slides and Chat. Switching tabs keeps what was typed in
//  the chat, and Slides never starts making a presentation by itself.
//

import XCTest

final class ProjectTabsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    // Each tab draws the tab switch, so only the one on screen is tapped.
    private func tab(_ app: XCUIApplication, _ title: String) {
        let visible = app.buttons.matching(NSPredicate(format: "label == %@", title)).allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(visible, "No visible \(title) tab")
        visible?.tap()
    }

    func testTabsKeepTheChatDraftAndSlidesWaitForCreate() {
        let app = XCUIApplication()
        app.launchArguments = ["-didOnboard", "YES", "-appLanguage", "en", "-auditSignedOut", "-demoMap"]
        app.launch()
        XCTAssertTrue(app.buttons["Chat"].firstMatch.waitForExistence(timeout: 10), "The project tabs should show over the map")
        tab(app, "Chat")

        let field = app.textViews["Message"].exists ? app.textViews["Message"] : app.textFields["Message"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("What is missing")

        tab(app, "Map")
        XCTAssertTrue(app.buttons["Edit Together"].waitForExistence(timeout: 5), "The map should be back")
        tab(app, "Slides")
        XCTAssertTrue(app.buttons["Create Presentation"].waitForExistence(timeout: 5), "Slides should offer to create, not start creating")
        XCTAssertFalse(app.staticTexts["Writing slides… Tap to stop"].exists, "Nothing should start by itself")

        tab(app, "Chat")
        XCTAssertTrue(((field.value as? String) ?? "").contains("What is missing"), "The draft was lost switching tabs")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "project-chat"
        shot.lifetime = .keepAlways
        add(shot)

        app.buttons.matching(NSPredicate(format: "label == 'Back'")).allElementsBoundByIndex.first { $0.isHittable }?.tap()
        XCTAssertTrue(app.buttons["Menu"].waitForExistence(timeout: 5), "Back should return to the assistant")
    }
}
