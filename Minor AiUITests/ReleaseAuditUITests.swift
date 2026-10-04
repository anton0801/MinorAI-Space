//
//  ReleaseAuditUITests.swift
//  Minor AiUITests
//
//  Pre-release checks on a simulator: random taps, swipes and typing from many starting screens
//  (a "monkey" that behaves like a curious first-time user), odd deep links, going to the
//  background and back, every main screen on each plan, and huge text sizes. A crash relaunches
//  the app and is reported with the last actions; screenshots are kept for review.
//

import XCTest

final class ReleaseAuditUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    // MARK: - Monkey

    // Seeded, so a crash can be replayed with the same seed.
    private struct Random {
        var state: UInt64
        mutating func next() -> UInt64 {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return state
        }
        mutating func unit() -> CGFloat { CGFloat(next() % 10_000) / 10_000 }
        mutating func pick<T>(_ items: [T]) -> T { items[Int(next() % UInt64(items.count))] }
    }

    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private let words = ["Привет", "Photosynthesis", "🙂🚀", "", "   ", String(repeating: "Long text ", count: 40),
                         "<b>&amp;\"'</b>", "123456", "minorai://map/x", "Ünïcödé ✓"]

    // Answers a system alert (notifications, microphone…) so the run can go on.
    private func dismissSystemAlerts() {
        let alert = springboard.alerts.firstMatch
        guard alert.exists else { return }
        for title in ["Open", "Открыть", "Allow", "Разрешить", "OK", "Don’t Allow", "Не разрешать", "Cancel", "Отмена"] where alert.buttons[title].exists {
            alert.buttons[title].tap()
            return
        }
        alert.buttons.element(boundBy: max(alert.buttons.count - 1, 0)).tap()
    }

    private func monkey(_ name: String, _ args: [String], actions: Int = 90, seed: UInt64) {
        let app = XCUIApplication()
        app.launchArguments = args + ["-didOnboard", "YES", "-auditSignedOut"]
        app.launch()
        var random = Random(state: seed)
        var log: [String] = []
        var crashes = 0

        func note(_ text: String) {
            log.append(text)
            if log.count > 25 { log.removeFirst() }
        }

        for step in 0..<actions {
            switch app.state {
            case .notRunning:
                crashes += 1
                let report = XCTAttachment(string: "\(name) seed \(seed) step \(step)\n" + log.joined(separator: "\n"))
                report.name = "CRASH \(name) #\(crashes)"
                report.lifetime = .keepAlways
                add(report)
                XCTFail("\(name): the app stopped running at step \(step). Last actions:\n" + log.suffix(8).joined(separator: "\n"))
                app.launch()
            case .runningBackground, .runningBackgroundSuspended:
                note("re-activate")
                app.activate()
            default:
                break
            }
            dismissSystemAlerts()

            let roll = random.next() % 100
            let window = app.windows.firstMatch
            switch roll {
            case 0..<40:
                // A few tries at a random button that can be tapped (checking all of them is slow).
                let all = app.descendants(matching: .button)
                let count = all.count
                guard count > 0 else { continue }
                for _ in 0..<3 {
                    let button = all.element(boundBy: Int(random.next() % UInt64(count)))
                    guard onScreen(button, app) else { continue }
                    note("tap button \"\(button.label)\"")
                    button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                    break
                }
            case 40..<65:
                let x = random.unit(), y = 0.08 + random.unit() * 0.88
                note("tap \(Int(x * 100))%,\(Int(y * 100))%")
                window.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()
            case 65..<77:
                let direction = random.next() % 4
                note("swipe \(["up", "down", "left", "right"][Int(direction)])")
                switch direction {
                case 0: window.swipeUp()
                case 1: window.swipeDown()
                case 2: window.swipeLeft()
                default: window.swipeRight()
                }
            case 77..<85:
                let fields = (app.textFields.allElementsBoundByIndex + app.textViews.allElementsBoundByIndex + app.secureTextFields.allElementsBoundByIndex).filter { onScreen($0, app) }
                guard let field = fields.isEmpty ? nil : random.pick(fields) else { continue }
                let text = random.pick(words)
                note("type \(text.prefix(20)) into \(field.label)")
                field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                guard app.keyboards.count > 0, !text.isEmpty else { continue }
                app.typeText(text)
                if random.next() % 2 == 0 { app.typeText("\n") }
            case 85..<89:
                let x = random.unit(), y = 0.15 + random.unit() * 0.75
                note("long press \(Int(x * 100))%,\(Int(y * 100))%")
                window.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).press(forDuration: 1.0)
            case 89..<94:
                let escapes = ["Done", "Готово", "Cancel", "Отмена", "Close", "Закрыть", "Back", "Назад"]
                if let title = escapes.first(where: { onScreen(app.buttons[$0].firstMatch, app) }) {
                    note("escape \(title)")
                    app.buttons[title].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                } else {
                    note("swipe down to close")
                    window.swipeDown(velocity: .fast)
                }
            case 94..<97:
                note("home and back")
                XCUIDevice.shared.press(.home)
                sleep(1)
                app.activate()
            default:
                note("pinch")
                // Zooming in needs a positive velocity, zooming out a negative one.
                let zoomIn = random.next() % 2 == 0
                window.pinch(withScale: zoomIn ? 1.8 : 0.5, velocity: zoomIn ? 1 : -1)
            }
        }
        let end = XCTAttachment(screenshot: app.screenshot())
        end.name = "\(name) end"
        end.lifetime = .keepAlways
        add(end)
        XCTAssertEqual(crashes, 0, "\(name): crashes")
        app.terminate()
    }

    func testMonkeyHome() { monkey("Home", ["-appLanguage", "ru"], seed: 11) }
    func testMonkeyHomePlus() { monkey("Home Plus", ["-appLanguage", "en", "-demoPlus"], seed: 12) }
    func testMonkeyMap() { monkey("Map", ["-demoMap", "-appLanguage", "ru"], seed: 13) }
    func testMonkeyMapPro() { monkey("Map PRO", ["-demoMap", "-demoShapes", "-demoPro", "-appLanguage", "en"], seed: 14) }
    func testMonkeyDeck() { monkey("Deck", ["-demoDesign", "-appLanguage", "ru"], seed: 15) }
    func testMonkeyDeckPlus() { monkey("Deck Plus", ["-demoDesign", "-demoPlus", "-appLanguage", "en"], seed: 16) }
    func testMonkeySidebar() { monkey("Sidebar", ["-sidebarMaps", "-appLanguage", "ru"], seed: 17) }
    func testMonkeyToday() { monkey("Today", ["-mindMode", "-demoToday", "-appLanguage", "ru"], seed: 18) }

    // MARK: - Deep links and life cycle

    func testOddDeepLinks() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-didOnboard", "YES", "-appLanguage", "ru", "-auditSignedOut"]
        app.launch()
        let links = [
            "minorai://map/notauuid", "minorai://map/", "minorai://map/00000000-0000-0000-0000-000000000000",
            "minorai://task/00000000-0000-0000-0000-000000000000", "minorai://task/x/y/z", "minorai://join/",
            "minorai://join/%27%22%3C%3E", "minorai://invite/", "minorai://invite/%27%22%3C%3E", "minorai://invite/abcdefgh",
            "minorai://usage", "minorai://today", "minorai://", "minorai://unknown/path?x=1", "minorai://invite/K7M2Q9XA",
        ]
        for link in links {
            app.open(URL(string: link)!)
            sleep(1)
            dismissSystemAlerts()
            sleep(2)
            XCTAssertEqual(app.state, .runningForeground, "The app should survive \(link)")
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "Link \(link)"
            shot.lifetime = .keepAlways
            add(shot)
            for title in ["Готово", "Отмена", "Done", "Cancel"] where onScreen(app.buttons[title].firstMatch, app) {
                app.buttons[title].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
            if app.state != .runningForeground { app.launch() }
        }
    }

    // MARK: - Screens on every plan and text size

    private let screens: [(String, [String])] = [
        ("Home", []), ("Paywall", ["-demoPaywall"]), ("Sign in", ["-demoSignIn"]), ("Map", ["-demoMap"]),
        ("Deck", ["-demoDesign"]), ("New deck", ["-demoNewDeck"]), ("Templates", ["-mindMode", "-demoTemplates"]),
        ("Today", ["-mindMode", "-demoToday"]), ("Study", ["-demoStudy"]), ("Limits", ["-demoUsage"]),
        ("Invite", ["-demoInvite"]), ("Collab", ["-demoCollab"]), ("Chat", ["-demoAgent"]),
    ]

    private func shoot(_ prefix: String, extra: [String]) {
        for (name, args) in screens {
            let app = XCUIApplication()
            app.launchArguments = args + extra + ["-didOnboard", "YES", "-auditSignedOut"]
            app.launch()
            sleep(4)
            dismissSystemAlerts()
            XCTAssertEqual(app.state, .runningForeground, "\(prefix) \(name) should open")
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "\(prefix) \(name)"
            shot.lifetime = .keepAlways
            add(shot)
            app.terminate()
        }
    }

    func testScreensFree() { shoot("Free", extra: ["-appLanguage", "ru"]) }
    func testScreensPlus() { shoot("Plus", extra: ["-appLanguage", "ru", "-demoPlus"]) }
    func testScreensPro() { shoot("PRO", extra: ["-appLanguage", "en", "-demoPro"]) }
    func testScreensHugeText() {
        shoot("XXXL", extra: ["-appLanguage", "ru", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
    }
}

// On screen and big enough to tap. `isHittable` can itself fail the test for odd elements, so the
// frame is checked instead and the element is tapped at its center.
private func onScreen(_ element: XCUIElement, _ app: XCUIApplication) -> Bool {
    guard element.exists else { return false }
    let frame = element.frame
    let screen = app.windows.firstMatch.frame
    guard frame.width > 4, frame.height > 4, !screen.isEmpty else { return false }
    return screen.insetBy(dx: 1, dy: 1).contains(CGPoint(x: frame.midX, y: frame.midY))
}
