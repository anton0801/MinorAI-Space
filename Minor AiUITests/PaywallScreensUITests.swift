//
//  PaywallScreensUITests.swift
//  Minor AiUITests
//
//  The paywall with prices from StoreKit/Minor.storekit: plan and billing period are chosen
//  separately, and the button, the price line and what is bought follow the choice. Screenshots
//  of each combination are kept for review.
//

import StoreKitTest
import XCTest

final class PaywallScreensUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        // No test purchase left from other runs: free plan, trial available.
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("StoreKit/Minor.storekit")
        try SKTestSession(contentsOf: file).clearTransactions()
    }

    private func launch(_ language: String, pro: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-didOnboard", "YES", "-appLanguage", language, "-auditSignedOut", "-demoFree", "-demoPaywall"] + (pro ? ["-paywallPro"] : [])
        app.launch()
        return app
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func line(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    func testPlanAndPeriodChangeWhatIsBought() {
        let app = launch("en")
        // Yearly is chosen first; the yearly plan comes with the trial set in the StoreKit file.
        XCTAssertTrue(line(app, containing: "$119.99").waitForExistence(timeout: 15), "Plus yearly price from StoreKit")
        XCTAssertTrue(app.buttons["Subscribe to Minor Plus for $119.99/year, 3 days free"].exists || app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Subscribe to Minor Plus for $119.99/year'")).firstMatch.exists)
        shot(app, "plus-yearly")

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Month'")).firstMatch.tap()
        XCTAssertTrue(line(app, containing: "$12.99 a month").waitForExistence(timeout: 5), "The price line follows the month")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Subscribe to Minor Plus for $12.99/month'")).firstMatch.exists)
        shot(app, "plus-monthly")

        app.buttons["Minor PRO"].tap()
        XCTAssertTrue(line(app, containing: "$24.99 a month").waitForExistence(timeout: 5), "PRO keeps the chosen period")
        XCTAssertTrue(app.staticTexts["Up to 600 maps a month"].exists, "PRO shows its own benefits")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Subscribe to Minor PRO for $24.99/month'")).firstMatch.exists)
        shot(app, "pro-monthly")

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Year'")).firstMatch.tap()
        XCTAssertTrue(line(app, containing: "$219.99").waitForExistence(timeout: 5))
        shot(app, "pro-yearly")
    }

    func testComparisonOpensFromABenefit() {
        let app = launch("ru")
        let benefit = app.buttons.matching(NSPredicate(format: "label CONTAINS 'изображений'")).firstMatch
        XCTAssertTrue(benefit.waitForExistence(timeout: 15))
        shot(app, "ru-plus")
        benefit.tap()
        XCTAssertTrue(app.staticTexts["Все возможности и лимиты"].waitForExistence(timeout: 5), "The comparison opens")
        shot(app, "ru-comparison")
    }

    func testProScreenInRussian() {
        let app = launch("ru", pro: true)
        XCTAssertTrue(app.staticTexts["До 600 карт в месяц"].waitForExistence(timeout: 15))
        shot(app, "ru-pro")
    }
}
