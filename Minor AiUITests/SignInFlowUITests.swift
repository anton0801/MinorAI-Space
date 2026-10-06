//
//  SignInFlowUITests.swift
//  Minor AiUITests
//
//  What App Review does on first launch (iPad, 2026-10-06 report): the splash, onboarding,
//  then the sign-in buttons must answer. Screenshots of every step are kept in the results.
//  Run on an iPad simulator with the "Minor Ai UI Checks" scheme.
//

import XCTest

final class SignInFlowUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    // A first launch as App Review sees it: the splash plays, onboarding is shown. "-onboarding"
    // resets it once at launch ("-didOnboard NO" would pin it for the whole run, so "Not Now"
    // could never close it).
    private func launchFirstTime() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding", "-appLanguage", "en", "-auditSignedOut"]
        // TEST_RUNNER_SPLASH_LEGACY=1 xcodebuild test …: the splash as in build 2.0 (2), to compare.
        if legacy { app.launchArguments.append("-splashLegacy") }
        app.launch()
        return app
    }

    private var legacy: Bool { ProcessInfo.processInfo.environment["SPLASH_LEGACY"] == "1" }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = (legacy ? "legacy-" : "") + name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func openSignIn(_ app: XCUIApplication) {
        let skip = app.buttons["Skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 15), "Onboarding didn't appear")
        sleep(3) // the splash has finished
        shot(app, "1-onboarding")
        skip.tap()
        XCTAssertTrue(app.staticTexts["Welcome Back"].waitForExistence(timeout: 5), "Skip didn't open sign-in")
        shot(app, "2-sign-in")
    }

    func testNotNowClosesSignIn() {
        let app = launchFirstTime()
        openSignIn(app)
        app.buttons["Not Now"].tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: app.staticTexts["Welcome Back"])
        waitForExpectations(timeout: 5)
        shot(app, "3-after-not-now")
    }

    func testSignInButtonAnswers() {
        let app = launchFirstTime()
        openSignIn(app)
        let email = app.textFields["Email"]
        email.tap()
        email.typeText("ui-check@example.com")
        let password = app.secureTextFields["Password"]
        password.tap()
        password.typeText("WrongPassword1")
        shot(app, "3-filled")
        app.buttons.matching(NSPredicate(format: "label == 'Sign In'")).allElementsBoundByIndex.last?.tap()
        // A wrong password must end with a message (or the screen closing), never with nothing.
        let answered = NSPredicate { _, _ in
            !app.staticTexts["Welcome Back"].exists
                || app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'password' OR label CONTAINS[c] 'try again' OR label CONTAINS[c] 'internet'")).count > 0
        }
        expectation(for: answered, evaluatedWith: app)
        waitForExpectations(timeout: 20)
        shot(app, "4-after-sign-in")
        // And Not Now still works after a failed attempt.
        if app.staticTexts["Welcome Back"].exists {
            app.buttons["Not Now"].tap()
            expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.staticTexts["Welcome Back"])
            waitForExpectations(timeout: 5)
            shot(app, "5-after-not-now")
        }
    }
}
