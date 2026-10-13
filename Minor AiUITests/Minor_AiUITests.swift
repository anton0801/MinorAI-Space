//
//  Minor_AiUITests.swift
//  Minor AiUITests
//
//  Created by Stefano  on 2/3/25.
//

import XCTest

final class Minor_AiUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    // Tapping a presentation in the Library's Slides tab opens it.
    @MainActor
    func testOpenPresentationFromSidebar() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-sidebarDecks", "-didOnboard", "YES", "-appLanguage", "en"]
        app.launch()

        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Launch plan'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8), "The presentation should be listed in the Library")
        row.tap()

        XCTAssertTrue(app.buttons["Present"].waitForExistence(timeout: 5), "The presentation editor should open")
    }

    // Variants: where the Library is opened from and where the row is tapped.
    @MainActor
    func testOpenFromMapScreen() throws { try open(extra: ["-mindMode"], dx: 0.6) }

    @MainActor
    func testOpenByThumbnail() throws { try open(extra: [], dx: 0.12) }

    // The first-launch pages: each one shows, the last starts the app and offers Sign In.
    @MainActor
    func testOnboardingPages() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-onboarding", "-appLanguage", "ru", "-auditSignedOut"]
        app.launch()
        for page in 1...3 {
            sleep(page == 1 ? 5 : 3)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "Onboarding \(page)"
            shot.lifetime = .keepAlways
            add(shot)
            if page < 3 {
                let next = app.buttons["Продолжить"]
                XCTAssertTrue(next.waitForExistence(timeout: 3))
                next.tap()
            }
        }
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS 'Войти'")).firstMatch.exists, "The last page should offer Sign In")
        app.buttons["Начать"].tap()
        XCTAssertTrue(app.buttons["Меню"].waitForExistence(timeout: 5), "Начать should open the assistant")
    }

    // The presentation designer: elements, an element's settings, slide design, themes, own style.
    @MainActor
    func testLimitsAndInviteScreens() throws {
        for (flag, title) in [("-demoUsage", "Limits"), ("-demoInvite", "Invite")] {
            let app = XCUIApplication()
            app.launchArguments += [flag, "-didOnboard", "YES", "-appLanguage", "ru"]
            app.launch()
            func shot(_ name: String) {
                let a = XCTAttachment(screenshot: app.screenshot())
                a.name = name
                a.lifetime = .keepAlways
                add(a)
            }
            XCTAssertTrue(app.buttons["Готово"].waitForExistence(timeout: 8))
            sleep(1)
            shot("\(title) 1")
            func scroll() {
                // From the screen's edge, so the drag never starts on a button.
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.85))
                    .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.35)))
                sleep(1)
            }
            scroll()
            shot("\(title) 2")
            scroll()
            shot("\(title) 3")
            app.terminate()
        }
    }

    func testDesignScreens() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-demoDesign", "-demoPlus", "-didOnboard", "YES", "-appLanguage", "ru"]
        app.launch()
        func shot(_ name: String) {
            let a = XCTAttachment(screenshot: app.screenshot())
            a.name = name
            a.lifetime = .keepAlways
            add(a)
        }
        XCTAssertTrue(app.buttons["Слайд 4"].waitForExistence(timeout: 8))
        app.buttons["Слайд 4"].tap()
        sleep(1)
        app.buttons["Элементы"].firstMatch.tap()
        sleep(1)
        let chart = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Диаграмма:'")).firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 4))
        chart.tap()
        sleep(1)
        shot("Design 1 elements")
        chart.tap()
        sleep(2)
        shot("Design 2 inspector")
        app.buttons["Отмена"].firstMatch.tap()
        sleep(1)
        app.buttons["Готово"].firstMatch.tap()
        sleep(1)
        // The Design tab's "Background and Motion" opens the slide's own design.
        app.buttons["Фон и анимация"].firstMatch.tap()
        sleep(2)
        shot("Design 3 slide design")
        app.buttons["Отмена"].firstMatch.tap()
        sleep(1)
    }

    // The element chips with "Plus" tags on the free plan, scrolled into view.
    @MainActor
    func testElementChips() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-demoDesign", "-demoElements", "-didOnboard", "YES", "-appLanguage", "ru"]
        app.launch()
        let text = app.buttons["Текст"].firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 8))
        text.swipeLeft()
        sleep(1)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Chips scrolled"
        shot.lifetime = .keepAlways
        add(shot)
    }

    // For comparison: a map in the Maps tab.
    @MainActor
    func testOpenMapFromSidebar() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-sidebarMaps", "-didOnboard", "YES", "-appLanguage", "en"]
        app.launch()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Launch plan'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.tap()
        XCTAssertTrue(app.buttons["Edit Together"].waitForExistence(timeout: 5), "The map should open")
    }

    @MainActor
    func testOpenByEmptySpace() throws { try open(extra: [], dx: 0.85) }

    // In the editor, tapping a slide in the filmstrip shows it.
    @MainActor
    func testFilmstripSelectsSlide() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-demoDeck", "-didOnboard", "YES", "-appLanguage", "en"]
        app.launch()
        let third = app.buttons["Slide 3"]
        XCTAssertTrue(third.waitForExistence(timeout: 8))
        third.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.7)).tap()
        let shown = app.otherElements.matching(NSPredicate(format: "label BEGINSWITH 'Slide 3:'")).firstMatch
        XCTAssertTrue(shown.waitForExistence(timeout: 3) && shown.isHittable, "The third slide should be on the stage")
    }

    @MainActor
    private func open(extra: [String], dx: CGFloat) throws {
        let app = XCUIApplication()
        app.launchArguments += extra + ["-sidebarDecks", "-didOnboard", "YES", "-appLanguage", "en"]
        app.launch()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Launch plan'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: 0.5)).tap()
        let opened = app.buttons["Present"].waitForExistence(timeout: 5)
        if !opened { print("SCREEN:\n" + app.debugDescription) }
        XCTAssertTrue(opened, "The presentation editor should open")
    }
}
