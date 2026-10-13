//
//  DiagramUITests.swift
//  Minor AiUITests
//
//  Editing a diagram on its slide: a tap opens its panel with the box selected; a step added from
//  the panel is one change that Undo takes back and Redo brings again; a connection is made from
//  two lists and a duplicate is refused; changing the kind asks first; dragging a box arranges by hand.
//

import XCTest

final class DiagramUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-didOnboard", "YES", "-appLanguage", "en", "-auditSignedOut", "-demoDiagrams", "0"]
        app.launch()
        return app
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // The slide on the stage: the diagram's stage while editing, otherwise the pager's slide.
    private func stage(_ app: XCUIApplication) -> XCUIElement {
        let editing = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Slide 1: diagram'")).firstMatch
        return editing.exists ? editing : app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Slide 1:'")).firstMatch
    }

    // A tap on the first box ("Idea", top left of a two-by-two process) opens the panel.
    private func openPanel(_ app: XCUIApplication) {
        let slide = stage(app)
        XCTAssertTrue(slide.waitForExistence(timeout: 10))
        slide.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.42)).tap()
        XCTAssertTrue(app.staticTexts["Diagram"].waitForExistence(timeout: 5), "The diagram's panel should open")
    }

    // The panel's Done (the keyboard may show its own).
    private func done(_ app: XCUIApplication) {
        app.buttons.matching(NSPredicate(format: "label == 'Done'")).allElementsBoundByIndex.first { $0.isHittable }?.tap()
    }

    private var stepFields: (XCUIApplication) -> XCUIElementQuery { { $0.textFields.matching(NSPredicate(format: "label BEGINSWITH 'Name of step'")) } }

    func testAddStepUndoRedo() {
        let app = launch()
        openPanel(app)
        XCTAssertEqual(stepFields(app).count, 4)
        app.buttons["Add Step"].tap()
        XCTAssertTrue(stepFields(app).element(boundBy: 4).waitForExistence(timeout: 3))
        XCTAssertEqual(stepFields(app).count, 5)
        shot(app, "step-added")
        done(app)
        let undo = app.buttons["Undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        undo.tap()
        openPanel(app)
        XCTAssertEqual(stepFields(app).count, 4, "Undo should take the step back")
        done(app)
        XCTAssertTrue(app.buttons["Redo"].waitForExistence(timeout: 3))
        app.buttons["Redo"].tap()
        openPanel(app)
        XCTAssertEqual(stepFields(app).count, 5, "Redo should bring it again")
    }

    func testConnectionAndKind() {
        let app = launch()
        openPanel(app)
        app.buttons["Links"].tap()
        let rows = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'More for connection'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 3))
        XCTAssertEqual(rows.count, 3)
        app.buttons["Add Connection"].tap()
        // From the selected first step to the second: they are already connected.
        app.buttons["Connect"].tap()
        XCTAssertTrue(app.staticTexts["These steps are already connected."].waitForExistence(timeout: 3))
        app.buttons["To"].tap()
        app.buttons["Publishing"].tap()
        app.buttons["Connect"].tap()
        XCTAssertTrue(rows.element(boundBy: 3).waitForExistence(timeout: 3))
        XCTAssertEqual(rows.count, 4)
        shot(app, "connection-added")
        app.buttons["Style"].tap()
        app.buttons["Cycle"].tap()
        let change = app.buttons["Change to Cycle"]
        XCTAssertTrue(change.waitForExistence(timeout: 3), "Changing the kind should ask first")
        change.tap()
        XCTAssertTrue(app.staticTexts["Cycle"].waitForExistence(timeout: 3))
        shot(app, "cycle")
    }

    func testDragArrangesByHand() {
        let app = launch()
        openPanel(app)
        let slide = stage(app)
        let from = slide.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.42))
        let to = slide.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
        from.press(forDuration: 0.2, thenDragTo: to)
        app.buttons["Links"].tap()
        XCTAssertTrue(app.staticTexts["By hand"].waitForExistence(timeout: 3), "A dragged box arranges the diagram by hand")
        shot(app, "dragged")
    }
}
