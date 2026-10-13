//
//  MapPanelUITests.swift
//  Minor AiUITests
//
//  The selected idea's compact panel (Rename, Add Branch, Note, Task, Discuss with Minor, More
//  Actions): every earlier action is still reachable from More Actions, Cancel on a new branch's
//  name takes the branch away, a branch moves only on Move, a duplicate is a separate copy, a
//  label added in Marks is found by Search, and Sources says where an idea came from.
//

import XCTest

final class MapPanelUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-didOnboard", "YES", "-appLanguage", "en", "-auditSignedOut", "-demoMap", "-demoSelect"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["Add Branch"].waitForExistence(timeout: 10), "The selected idea's panel should show")
        return app
    }

    // Screens kept alive under the map (the assistant) still count for XCUITest's hit test, so
    // buttons are tapped where they are drawn.
    private func press(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), "\(element) should exist")
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func row(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }

    private func any(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func openMore(_ app: XCUIApplication) {
        press(row(app, "More Actions"))
        XCTAssertTrue(app.staticTexts["More Actions"].waitForExistence(timeout: 5), "More Actions should open for this idea")
    }

    // A row further down More Actions: the sheet grows to full height, then scrolls to it.
    private func tapMore(_ app: XCUIApplication, _ title: String) {
        let element = row(app, title)
        XCTAssertTrue(element.waitForExistence(timeout: 5), "\(title) should be in More Actions")
        let screen = app.windows.firstMatch.frame
        let sheet = app.scrollViews.containing(NSPredicate(format: "label BEGINSWITH 'Focus on Branch'")).firstMatch
        // Measured once the sheet has come up.
        Thread.sleep(forTimeInterval: 0.8)
        var tries = 0
        while element.frame.maxY > screen.maxY - 60, tries < 6, sheet.exists {
            sheet.swipeUp()
            tries += 1
        }
        press(element)
    }

    func testPanelShowsTheMainActions() {
        let app = launch()
        for title in ["Rename", "Add Branch", "Note", "Task", "Discuss with Minor", "More Actions"] {
            XCTAssertTrue(row(app, title).exists, "The panel should offer \(title)")
        }
        XCTAssertTrue(any(app, containing: "Launch plan › Pricing").exists || any(app, containing: "Pricing").exists, "The panel names the idea and where it is")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "node-panel"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testMoreActionsKeepEveryIdeaAction() {
        let app = launch()
        openMore(app)
        // As the design: structure, look, sources, the rest, Delete at the bottom.
        for item in ["Move", "Connect to an Idea", "Appearance", "Marks & Labels", "Sources", "Duplicate", "Focus on Branch", "Delete Branch"] {
            XCTAssertTrue(row(app, item).exists, "More Actions should offer \(item)")
        }
        // The rest opens in place.
        tapMore(app, "Contents")
        for item in ["Add Photo", "Show as Callout", "Add Frame"] {
            XCTAssertTrue(row(app, item).waitForExistence(timeout: 3), "Contents should offer \(item)")
        }
        XCTAssertTrue(row(app, "Edit Web Link").exists || row(app, "Add Web Link").exists)
        tapMore(app, "Minor’s Actions")
        for item in ["Expand with AI", "Find Examples", "Questions", "Next Steps", "Create Image with AI"] {
            XCTAssertTrue(row(app, item).waitForExistence(timeout: 3), "Minor’s Actions should offer \(item)")
        }
        tapMore(app, "Order")
        for item in ["Add at the Same Level", "Move Up", "Move Down", "Collapse Branch"] {
            XCTAssertTrue(row(app, item).waitForExistence(timeout: 3), "Order should offer \(item)")
        }
    }

    func testCancelOnANewBranchTakesItAway() {
        let app = launch()
        press(row(app, "Add Branch"))
        XCTAssertTrue(app.alerts["Rename"].waitForExistence(timeout: 5), "The new branch is named right away")
        app.alerts["Rename"].buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Add Branch"].waitForExistence(timeout: 5))
        XCTAssertFalse(any(app, containing: "New idea").exists, "The unnamed branch should be gone")
    }

    func testBranchMovesOnlyOnMove() {
        let app = launch()
        openMore(app)
        tapMore(app, "Move")
        XCTAssertTrue(app.staticTexts["Move Branch"].waitForExistence(timeout: 5), "Move mode should start")
        XCTAssertFalse(app.buttons["Move"].isEnabled, "Nothing to apply before a parent is chosen")
        press(app.buttons["Choose from a List"])
        XCTAssertTrue(app.navigationBars["New Parent"].waitForExistence(timeout: 5))
        let list = app.collectionViews.firstMatch
        XCTAssertFalse(list.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Free · 3 maps'")).firstMatch.exists, "The branch's own ideas aren't offered")
        app.searchFields.firstMatch.tap()
        app.typeText("Channels")
        XCTAssertTrue(list.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Channels'")).firstMatch.waitForExistence(timeout: 5))
        list.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Channels'")).firstMatch.tap()
        XCTAssertTrue(any(app, containing: "Into “Channels”").waitForExistence(timeout: 5), "The chosen parent shows before applying")
        press(app.buttons["Move"])
        XCTAssertTrue(any(app, containing: "Channels › Pricing").waitForExistence(timeout: 5), "Pricing should be under Channels")
        XCTAssertTrue(app.buttons["Undo"].firstMatch.waitForExistence(timeout: 3), "Moving can be undone")
        press(app.buttons["Undo"].firstMatch)
        XCTAssertTrue(any(app, containing: "Launch plan › Pricing").waitForExistence(timeout: 5), "Undo puts the branch back")
    }

    func testConnectionTargetCanBeChosenFromAList() {
        let app = launch()
        openMore(app)
        tapMore(app, "Connect to an Idea")
        press(app.buttons["Choose from a List"])
        XCTAssertTrue(app.navigationBars["Connect To"].waitForExistence(timeout: 5))
        let list = app.collectionViews.firstMatch
        // Found by search, as a long list would be.
        app.searchFields.firstMatch.tap()
        app.typeText("Channels")
        let channels = list.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Channels'")).firstMatch
        XCTAssertTrue(channels.waitForExistence(timeout: 5))
        channels.tap()
        let ok = app.alerts["Connection Label"].waitForExistence(timeout: 5)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "after-pick"
        shot.lifetime = .keepAlways
        add(shot)
        XCTAssertTrue(ok, "The connection is made, its label asked")
        app.alerts["Connection Label"].buttons["Skip"].tap()
    }

    func testDuplicateIsASeparateCopy() {
        let app = launch()
        openMore(app)
        tapMore(app, "Duplicate")
        XCTAssertTrue(any(app, containing: "Pricing copy").waitForExistence(timeout: 5), "The copy is selected")
        XCTAssertTrue(app.staticTexts["Branch duplicated"].waitForExistence(timeout: 3) || app.buttons["Undo"].firstMatch.exists)
    }

    func testTaskOpensItsDetails() {
        let app = launch()
        press(row(app, "Task"))
        XCTAssertTrue(app.buttons["Save Date"].waitForExistence(timeout: 5), "The task's details should open")
        XCTAssertTrue(row(app, "Tomorrow").exists && row(app, "No Date").exists)
    }

    func testLabelFromMarksIsFoundBySearch() {
        let app = launch()
        openMore(app)
        tapMore(app, "Marks & Labels")
        XCTAssertTrue(app.staticTexts["Marks & Task"].waitForExistence(timeout: 5))
        app.buttons["Add Label"].tap()
        app.typeText("Review\n")
        XCTAssertTrue(app.buttons["Remove label Review"].waitForExistence(timeout: 5), "The label should be added")
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Add Branch"].waitForExistence(timeout: 5), "Back to the panel")

        // Search the map for the label.
        press(app.buttons.matching(NSPredicate(format: "label == 'More'")).firstMatch)
        app.buttons["Search"].tap()
        app.typeText("#review")
        XCTAssertTrue(app.staticTexts["1 results"].waitForExistence(timeout: 5), "Search should find the labelled idea")
    }

    func testSourcesTellWhereAnIdeaCameFrom() {
        let app = launch(["-demoSources"])
        openMore(app)
        tapMore(app, "Sources")
        XCTAssertTrue(app.staticTexts["This idea"].waitForExistence(timeout: 5), "Sources of the selected idea")
        let open = app.buttons.matching(NSPredicate(format: "label IN %@", ["Open at This Place", "Open Page", "Open Original", "Open Material"])).firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 3), "The way to the passage it came from")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "sources"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
