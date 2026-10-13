//
//  CollabUITests.swift
//  Minor AiUITests
//
//  Sharing a map, without a server (demo flags): the invite panel asks for the role before any
//  link exists, the people panel gives the owner roles, removal, turning off links and stopping
//  sharing (not deleting), and an opened invite shows what it gives before anyone joins.
//

import XCTest

final class CollabUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-didOnboard", "YES", "-appLanguage", "en", "-auditSignedOut"] + extra
        app.launch()
        return app
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testInvitePicksTheRoleBeforeALink() {
        let app = launch(["-demoMap", "-demoCollab", "-demoPlus"])
        XCTAssertTrue(app.staticTexts["Invite to Map"].waitForExistence(timeout: 10))
        let viewer = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Viewer'")).firstMatch
        XCTAssertTrue(viewer.exists)
        viewer.tap()
        XCTAssertTrue(viewer.isSelected, "The chosen role is marked")
        XCTAssertTrue(app.staticTexts["Only this map is shared"].exists)
        // Signed out: the link waits for sign-in, nothing is created by opening the panel.
        app.buttons["Sign In to Invite"].tap()
        XCTAssertTrue(app.staticTexts["Welcome Back"].waitForExistence(timeout: 5), "Sign-in opens over the panel")
        shot(app, "invite-sign-in")
    }

    func testOwnerManagesPeopleAndLinks() {
        let app = launch(["-demoMap", "-demoCollab", "-demoMembers", "-demoPlus"])
        XCTAssertTrue(app.staticTexts["People on the Map"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Role of anna@example.com"].exists, "The owner can change a role")
        XCTAssertTrue(app.buttons["Turn Off Links"].exists)
        let stop = app.buttons["Stop Working Together"]
        XCTAssertTrue(stop.exists, "Stopping sharing is its own action")
        shot(app, "members")
        stop.tap()
        XCTAssertTrue(app.staticTexts["Stop working together on this map?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'The map stays with you'")).firstMatch.exists, "Says the map isn’t deleted")
        app.buttons["Cancel"].tap()
        app.buttons["Role of anna@example.com"].tap()
        XCTAssertTrue(app.buttons["Remove from Map"].waitForExistence(timeout: 5))
        shot(app, "role-menu")
    }

    func testInvitationShowsWhatItGivesBeforeJoining() {
        let app = launch(["-demoJoin", "ok"])
        XCTAssertTrue(app.staticTexts["Map Invitation"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Podcast Launch"].exists)
        XCTAssertTrue(app.staticTexts["Anna invites you"].exists)
        XCTAssertTrue(app.buttons["Join"].exists)
        shot(app, "join")
        // Signed out: joining asks to sign in first.
        app.buttons["Join"].tap()
        XCTAssertTrue(app.staticTexts["Welcome Back"].waitForExistence(timeout: 5))
    }

    func testNotNowChangesNothing() {
        let app = launch(["-demoJoin", "ok"])
        let notNow = app.buttons["Not Now"]
        XCTAssertTrue(notNow.waitForExistence(timeout: 10))
        notNow.tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: app.staticTexts["Map Invitation"])
        waitForExpectations(timeout: 5)
    }

    func testInvitationStates() {
        for (kind, text) in [("invalid", "This link no longer works"), ("full", "This map is full"), ("member", "You’re already on this map")] {
            let app = launch(["-demoJoin", kind])
            XCTAssertTrue(app.staticTexts[text].waitForExistence(timeout: 10), "\(kind) state")
            shot(app, "join-\(kind)")
            app.terminate()
        }
    }
}
