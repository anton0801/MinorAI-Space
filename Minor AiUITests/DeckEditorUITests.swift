//
//  DeckEditorUITests.swift
//  Minor AiUITests
//
//  The slides editor: All Slides hides a slide (and keeps one visible), the export sheet leaves
//  hidden slides out, and tapping the slide's title selects it and opens the Text panel.
//

import XCTest

final class DeckEditorUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-didOnboard", "YES", "-appLanguage", "en", "-auditSignedOut", "-demoDeck"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["Present"].waitForExistence(timeout: 10), "The presentation editor should open")
        return app
    }

    // Layers kept alive underneath count for XCUITest's hit test, so buttons are tapped where drawn.
    private func press(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), "\(element) should exist")
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    func testAllSlidesHidesASlideAndExportLeavesItOut() {
        let app = launch()
        press(app.buttons["All Slides"].firstMatch)
        XCTAssertTrue(app.staticTexts["Drag a slide to change the order"].waitForExistence(timeout: 5))
        // The slide on screen (the first) is selected: hide it.
        press(app.buttons["Hide"].firstMatch)
        XCTAssertTrue(app.staticTexts["Slide hidden: skipped when presenting"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Show"].firstMatch.exists, "The hidden slide can be shown again")
        app.buttons["Done"].firstMatch.tap()

        press(app.buttons["Export"].firstMatch)
        let count = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '10 slides'")).firstMatch
        XCTAssertTrue(count.waitForExistence(timeout: 5), "The hidden slide is left out of the file")
        XCTAssertTrue(app.switches.firstMatch.exists, "Hidden slides can be included")
    }

    func testTappingTheTitleSelectsItForTheTextPanel() {
        let app = launch()
        // The cover's title sits in the upper left part of the slide.
        let slide = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Slide 1:'")).firstMatch
        XCTAssertTrue(slide.waitForExistence(timeout: 5))
        slide.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.42)).tap()
        XCTAssertTrue(app.staticTexts["The title of this slide"].waitForExistence(timeout: 5), "The selected text opens its panel")
        press(app.buttons["Bigger"])
        XCTAssertTrue(app.staticTexts["Size 110 percent"].waitForExistence(timeout: 5), "The title grows")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "text-panel"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
