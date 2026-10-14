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

    private func startSlides(_ app: XCUIApplication) -> XCUIElement {
        app.launchArguments = ["-didOnboard", "YES", "-appLanguage", "en", "-auditSignedOut", "-demoMap", "-demoGenerate", "-demoPlus"]
        app.launch()
        XCTAssertTrue(app.buttons["Chat"].firstMatch.waitForExistence(timeout: 10))
        tab(app, "Slides")
        let create = app.buttons["Create Presentation"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        // The map stays alive under Slides, but out of reach: VoiceOver and taps see only this tab.
        XCTAssertFalse(app.buttons["Add Branch"].exists || app.buttons["Present"].exists, "The hidden map's controls should not be reachable")
        create.tap()
        XCTAssertTrue(app.staticTexts["Writing your slides…"].waitForExistence(timeout: 3), "The slides being written should show")
        return create
    }

    // The path that crashed 3.0.0 on iPhones: slides made from the project, then the new
    // presentation opening right away.
    func testCreatedSlidesAreShownBeingWrittenThenOpen() {
        let app = XCUIApplication()
        _ = startSlides(app)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "writing-slides"
        shot.lifetime = .keepAlways
        add(shot)
        XCTAssertTrue(app.buttons["Present"].waitForExistence(timeout: 15), "The new presentation should open")
        XCTAssertTrue(app.staticTexts["Speaker Notes"].exists, "with its editor")
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testStoppingTheSlidesLeavesNothingBehind() {
        let app = XCUIApplication()
        let create = startSlides(app)
        app.buttons["Stop"].tap()
        XCTAssertTrue(create.waitForExistence(timeout: 5), "Back to the start, ready to create again")
        XCTAssertFalse(app.staticTexts["Writing your slides…"].exists)
        let present = app.buttons["Present"]
        XCTAssertFalse(present.waitForExistence(timeout: 4), "No presentation should be made: \(present.debugDescription)")
    }
}
