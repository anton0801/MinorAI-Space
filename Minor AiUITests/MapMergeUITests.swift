//
//  MapMergeUITests.swift
//  Minor AiUITests
//
//  Update from Map on a presentation linked to its map: the changes and the conflict are listed,
//  applying changes only what was chosen, and one Undo takes the whole update back.
//

import XCTest

final class MapMergeUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testApplyAndUndo() {
        let app = XCUIApplication()
        app.launchArguments = ["-didOnboard", "YES", "-appLanguage", "en", "-auditSignedOut", "-demoMerge"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Update from Map"].waitForExistence(timeout: 10), "The comparison should open")
        XCTAssertTrue(app.staticTexts["Text conflicts"].exists)
        XCTAssertTrue(app.staticTexts["4 suggestions · 1 conflict"].exists)
        // Leave out the new slide; keep my text in the conflict (the default).
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'New slide'")).firstMatch.tap()
        let apply = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Apply Selected'")).firstMatch
        XCTAssertEqual(apply.label, "Apply Selected (3)")
        shot(app, "merge")
        apply.tap()
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 5))
        // Slide 3 says the new price now; still 5 slides (the new one was left out).
        XCTAssertTrue(app.buttons["All Slides"].exists)
        XCTAssertEqual(app.buttons["All Slides"].value as? String, "Slide 1 of 5")
        let pricing = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Plus · $9.99'")).firstMatch
        XCTAssertTrue(pricing.waitForExistence(timeout: 3), "The changed bullet should be on the slide")
        app.buttons["Undo"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Plus · $12.99'")).firstMatch.waitForExistence(timeout: 3), "Undo should take the update back")
    }
}
