//
//  PaywallPurchaseUITests.swift
//  Minor AiUITests
//
//  Buying through the local StoreKit test environment (no real money): a purchase that goes
//  through closes the paywall, one waiting for approval says so without giving the plan, and a
//  failed one explains it and keeps the choice. Every test starts and ends with no purchases.
//

import StoreKitTest
import XCTest

final class PaywallPurchaseUITests: XCTestCase {
    private var session: SKTestSession!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("StoreKit/Minor.storekit")
        session = try SKTestSession(contentsOf: file)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
    }

    override func tearDownWithError() throws {
        session.clearTransactions()
        session.askToBuyEnabled = false
        session.failTransactionsEnabled = false
    }

    private func openPaywall() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-didOnboard", "YES", "-appLanguage", "en", "-auditSignedOut", "-demoPaywall"]
        app.launch()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '$119.99'")).firstMatch.waitForExistence(timeout: 15), "Prices from StoreKit")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Month'")).firstMatch.tap()
        return app
    }

    private var buy: (XCUIApplication) -> XCUIElement {
        { $0.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Subscribe to Minor Plus for $12.99/month'")).firstMatch }
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testPurchaseClosesThePaywall() {
        let app = openPaywall()
        buy(app).tap()
        let title = app.staticTexts["Your next big project."]
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: title)
        waitForExpectations(timeout: 15)
        XCTAssertEqual(session.allTransactions().count, 1, "Exactly one purchase")
    }

    func testPurchaseWaitingForApprovalIsSaidPlainly() {
        session.askToBuyEnabled = true
        let app = openPaywall()
        buy(app).tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Waiting for approval'")).firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Your next big project."].exists, "The paywall stays; no plan yet")
        shot(app, "pending")
    }

    func testFailedPurchaseKeepsTheChoice() {
        session.failTransactionsEnabled = true
        session.failureError = .unknown
        let app = openPaywall()
        buy(app).tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'didn’t go through' OR label CONTAINS 'isn’t available'")).firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(buy(app).exists, "Monthly Plus is still chosen")
        shot(app, "failed")
    }

    func testRestoreWithNothingToRestoreSaysSo() {
        let app = openPaywall()
        app.buttons["Restore Purchases"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["No active subscription was found for this Apple ID."].waitForExistence(timeout: 20))
    }

    func testRestoreBringsBackAPurchase() throws {
        // A Plus purchase made earlier on this Apple ID.
        try session.buyProduct(productIdentifier: "com.minorailifegroup.MinorAI.plusMonthlyPlan")
        let app = XCUIApplication()
        app.launchArguments = ["-didOnboard", "YES", "-appLanguage", "en", "-auditSignedOut", "-demoPaywall"]
        app.launch()
        let restore = app.buttons["Restore Purchases"].firstMatch
        XCTAssertTrue(restore.waitForExistence(timeout: 15))
        restore.tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: app.staticTexts["Your next big project."])
        waitForExpectations(timeout: 20)
    }
}
