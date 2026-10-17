//
//  LibraryUITests.swift
//  Minor AiUITests
//
//  The Library: the assistant's top button and Menu → Library open the same screen with the right
//  Back; tabs, search and the row menu work; a document opened from it comes back to the same tab,
//  search and place; chats open on the assistant and the chat's top button returns to Chats.
//

import XCTest

final class LibraryUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-didOnboard", "YES", "-appLanguage", "en", "-auditSignedOut", "-noResume", "-demoFree"] + extra
        app.launch()
        return app
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func row(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }

    private func searchField(_ app: XCUIApplication) -> XCUIElement {
        app.textFields.matching(NSPredicate(format: "label BEGINSWITH 'Search'")).firstMatch
    }

    // From the assistant: Back says Assistant and returns there with the typed message kept.
    func testFromAssistantAndBack() {
        let app = launch(["-demoInstall"])
        let field = app.textViews["Ask Minor"].exists ? app.textViews["Ask Minor"] : app.textFields["Ask Minor"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("Plan a trip")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()

        let library = app.buttons["Library"]
        for round in 1...3 {
            XCTAssertTrue(library.waitForExistence(timeout: 3), "Library button missing on round \(round)")
            library.tap()
            XCTAssertTrue(app.staticTexts["Library"].waitForExistence(timeout: 3), "The Library didn't open on round \(round)")
            // It opens on the tab it was left on.
            if round == 1 { app.buttons["Maps"].tap() }
            XCTAssertTrue(row(app, "Launch plan").waitForExistence(timeout: 3))
            if round == 1 { shot(app, "library-from-assistant") }
            let back = app.buttons["Back to Assistant"]
            XCTAssertTrue(back.waitForExistence(timeout: 3))
            XCTAssertTrue(back.label.contains("Assistant"))
            back.tap()
        }
        XCTAssertTrue(library.waitForExistence(timeout: 3))
        XCTAssertTrue(((field.value as? String) ?? "").contains("Plan a trip"), "The typed message was lost")
    }

    // Menu → Library: the same screen, Back says Menu.
    func testFromMenu() {
        let app = launch(["-demoInstall", "-menu"])
        let tile = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Library,'")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 10))
        tile.tap()
        XCTAssertTrue(app.navigationBars.buttons["Menu"].waitForExistence(timeout: 5), "Back should say Menu")
        app.buttons["Maps"].tap()
        XCTAssertTrue(row(app, "Launch plan").waitForExistence(timeout: 5))
        shot(app, "library-from-menu")
        app.navigationBars.buttons["Menu"].tap()
        XCTAssertTrue(tile.waitForExistence(timeout: 5), "Back didn't return to the menu")
    }

    // Tabs, search within a tab, nothing found, clearing.
    func testTabsAndSearch() {
        let app = launch(["-demoInstall", "-sidebarMaps"])
        XCTAssertTrue(row(app, "Launch plan").waitForExistence(timeout: 10))
        let search = searchField(app)
        XCTAssertTrue(search.exists)
        XCTAssertEqual(search.label, "Search maps")

        app.buttons["Slides"].tap()
        XCTAssertEqual(searchField(app).label, "Search presentations")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'slides'")).firstMatch.waitForExistence(timeout: 3), "Presentations should be listed")
        app.buttons["Chats"].tap()
        XCTAssertEqual(searchField(app).label, "Search chats")
        app.buttons["Maps"].tap()

        searchField(app).tap()
        searchField(app).typeText("zzqx")
        XCTAssertTrue(app.staticTexts["Nothing found for “zzqx”"].waitForExistence(timeout: 3))
        shot(app, "nothing-found")
        app.buttons["Clear Search"].firstMatch.tap()
        searchField(app).typeText("Launch")
        XCTAssertTrue(app.staticTexts["Results"].waitForExistence(timeout: 3))
        XCTAssertTrue(row(app, "Launch plan").exists)
    }

    // A map opened from a search comes back to the same tab and search.
    func testOpenMapAndReturn() {
        let app = launch(["-demoInstall", "-sidebarMaps"])
        XCTAssertTrue(row(app, "Launch plan").waitForExistence(timeout: 10))
        searchField(app).tap()
        searchField(app).typeText("Launch")
        row(app, "Launch plan").tap()
        XCTAssertTrue(app.buttons["Edit Together"].waitForExistence(timeout: 8), "The map should open")
        app.buttons["Back"].firstMatch.tap()
        XCTAssertTrue(row(app, "Launch plan").waitForExistence(timeout: 5), "The Library should be under the map")
        XCTAssertEqual(searchField(app).value as? String, "Launch", "The search was lost")
        XCTAssertTrue(app.staticTexts["Results"].exists)
    }

    // Rename and pin from the row's menu.
    func testRowMenu() {
        let app = launch(["-demoInstall", "-sidebarDecks"])
        let more = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'More for Launch plan'")).firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        more.tap()
        app.buttons["Rename"].tap()
        let name = app.alerts.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 30) + "Pitch deck")
        app.alerts.buttons["Save"].tap()
        XCTAssertTrue(row(app, "Pitch deck").waitForExistence(timeout: 3), "The presentation should be renamed")

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'More for Pitch deck'")).firstMatch.tap()
        app.buttons["Pin"].tap()
        XCTAssertTrue(app.staticTexts["Pinned"].waitForExistence(timeout: 3))
        shot(app, "pinned-deck")
        // Back as it was, for the other tests.
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'More for Pitch deck'")).firstMatch.tap()
        app.buttons["Unpin"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'More for Pitch deck'")).firstMatch.tap()
        app.buttons["Rename"].tap()
        let again = app.alerts.textFields.firstMatch
        again.tap()
        again.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 30) + "Launch plan")
        app.alerts.buttons["Save"].tap()
        XCTAssertTrue(row(app, "Launch plan").waitForExistence(timeout: 3))
    }

    // A chat opens on the assistant; the chat's top button brings back the Library on Chats.
    func testChats() {
        let app = launch(["-libraryChats"])
        let chat = row(app, "Plan my study week")
        XCTAssertTrue(chat.waitForExistence(timeout: 10))
        shot(app, "chats")
        chat.tap()
        XCTAssertTrue(app.staticTexts["Here is a plan with three focus blocks a day."].waitForExistence(timeout: 5), "The chat should open")
        // Layers under the chat count in XCUITest's hit test, so the button is tapped where it is:
        // the chat's own one, right of its Back button (the start screen's sits under Back).
        let library = app.buttons.matching(identifier: "Library").allElementsBoundByIndex.max { $0.frame.minX < $1.frame.minX }
        library?.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(row(app, "Plan my study week").waitForExistence(timeout: 5), "The Library should open on Chats")
        XCTAssertEqual(searchField(app).label, "Search chats")
        app.buttons["Back to Assistant"].tap()
        XCTAssertTrue(app.staticTexts["Here is a plan with three focus blocks a day."].waitForExistence(timeout: 5), "Back should return to the chat")
    }

    // 120 maps with long names scroll, and the list doesn't cover Settings at the end.
    func testLongList() {
        let app = launch(["-demoManyMaps", "-sidebarMaps"])
        XCTAssertTrue(app.staticTexts["Library"].waitForExistence(timeout: 10))
        for _ in 0..<12 { app.swipeUp(velocity: .fast) }
        shot(app, "long-list-end")
        XCTAssertTrue(app.buttons["Settings"].isHittable)
    }
}
