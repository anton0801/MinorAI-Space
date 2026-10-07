//
//  PaywallTrialUITests.swift
//  Minor AiUITests
//
//  The paywall shows the yearly plans' free trial above the price, and the terms after it.
//  Prices come from StoreKit/Minor.storekit (selected in the "Minor Ai UI Checks" scheme).
//

import XCTest

final class PaywallTrialUITests: XCTestCase {
    private func paywall(_ language: String) {
        let app = XCUIApplication()
        app.launchArguments = ["-didOnboard", "YES", "-appLanguage", language, "-auditSignedOut", "-demoPaywall"]
        app.launch()
        let trial = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] '3'")).matching(NSPredicate(format: "label CONTAINS[c] 'free' OR label CONTAINS[c] 'бесплатно'")).firstMatch
        XCTAssertTrue(trial.waitForExistence(timeout: 10), "No free trial on the paywall")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "paywall-\(language)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testTrialShownInEnglish() { paywall("en") }
    func testTrialShownInRussian() { paywall("ru") }
}
