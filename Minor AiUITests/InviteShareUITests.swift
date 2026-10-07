//
//  InviteShareUITests.swift
//  Minor AiUITests
//
//  "Share Invite" in Invite Friends must open the system share sheet (on iOS 26 it did nothing).
//

import XCTest

final class InviteShareUITests: XCTestCase {
    func testShareInviteOpensShareSheet() {
        let app = XCUIApplication()
        app.launchArguments = ["-didOnboard", "YES", "-appLanguage", "en", "-auditSignedOut", "-demoInvite"]
        app.launch()
        let share = app.buttons["Share Invite"]
        XCTAssertTrue(share.waitForExistence(timeout: 10), "Invite Friends didn't open")
        share.tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 8), "The share sheet didn't open")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "share-sheet"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // As people reach it: Invite Friends as a sheet over another sheet (Limits, or Settings).
    func testShareInviteFromLimitsOpensShareSheet() {
        let app = XCUIApplication()
        app.launchArguments = ["-didOnboard", "YES", "-appLanguage", "en", "-auditSignedOut", "-demoUsage"]
        app.launch()
        let invite = app.buttons["Invite Friends and Get Plus"]
        XCTAssertTrue(invite.waitForExistence(timeout: 10), "Limits didn't open")
        invite.tap()
        let share = app.buttons["Share Invite"]
        XCTAssertTrue(share.waitForExistence(timeout: 10), "Invite Friends didn't open")
        share.tap()
        let opened = app.otherElements["ActivityListView"].waitForExistence(timeout: 8)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "share-sheet-from-limits"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertTrue(opened, "The share sheet didn't open")
    }
}
