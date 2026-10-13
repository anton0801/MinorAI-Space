//
//  ChatModelLockUITests.swift
//  Minor AiUITests
//
//  The free plan chats with the light models; a stronger model in the home model menu opens the
//  paywall on the plan that includes it instead of being picked.
//

import XCTest

final class ChatModelLockUITests: XCTestCase {
    private func openMenu() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-didOnboard", "YES", "-appLanguage", "en", "-auditSignedOut", "-demoFree"]
        app.launch()
        let picker = app.buttons["AI model: GPT-6 Luna"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10), "No model picker on the home screen")
        picker.tap()
        return app
    }

    private func row(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
    }

    func testPlusModelOpensPlusPaywall() {
        let app = openMenu()
        let sol = row(app, "GPT-6.1 Sol")
        XCTAssertTrue(sol.waitForExistence(timeout: 10), "No Sol in the model menu")
        sol.tap()
        XCTAssertTrue(app.staticTexts["With Minor Plus"].waitForExistence(timeout: 10), "Sol didn't open the Plus paywall")
        XCTAssertTrue(app.staticTexts["20× more AI than Free"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "paywall-from-sol"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testProModelOpensProPaywall() {
        let app = openMenu()
        let astra = row(app, "GPT-6 Astra")
        XCTAssertTrue(astra.waitForExistence(timeout: 10), "No Astra in the model menu")
        astra.tap()
        XCTAssertTrue(app.staticTexts["With Minor PRO"].waitForExistence(timeout: 10), "Astra didn't open the PRO paywall")
        XCTAssertTrue(app.staticTexts["The strongest AI models"].exists)
    }

    func testLightModelIsPicked() {
        let app = openMenu()
        let haiku = row(app, "Claude Haiku 4.5")
        XCTAssertTrue(haiku.waitForExistence(timeout: 10), "No Haiku in the model menu")
        haiku.tap()
        XCTAssertTrue(app.buttons["AI model: Claude Haiku 4.5"].waitForExistence(timeout: 5) || app.staticTexts["Claude Haiku 4.5"].waitForExistence(timeout: 5), "Haiku wasn't picked")
        XCTAssertFalse(app.staticTexts["Your next big project."].exists, "A light model opened the paywall")
    }
}
