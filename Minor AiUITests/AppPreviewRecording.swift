//
//  AppPreviewRecording.swift
//  Minor AiUITests
//
//  Drives the app through the App Store preview's story while the host records the simulator:
//  a map from a topic, the idea's panel, slides and presenting, Today, Study. Runs only when the
//  recording script sets TEST_RUNNER_PREVIEW_RECORD=1 (and PREVIEW_LANG=ru|en). Each scene and
//  tap is logged as "PREVIEW|…" with the time, so the edit can cut scenes and draw the taps.
//

import XCTest

final class AppPreviewRecording: XCTestCase {
    private var lang = "ru"
    private var app = XCUIApplication()

    override func setUpWithError() throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["PREVIEW_RECORD"] == "1", "Only for recording the App Store preview")
        lang = env["PREVIEW_LANG"] ?? "ru"
        continueAfterFailure = true
    }

    private func t(_ en: String, _ ru: String) -> String { lang == "ru" ? ru : en }

    private func launch(_ args: [String]) {
        app = XCUIApplication()
        // As a Plus user: the free limit card would take the topic field's place.
        // As a Plus user (the free limit card would take the topic field's place), with its own
        // empty store: only the sample data shows, nothing on the simulator is read or changed.
        app.launchArguments = ["-didOnboard", "YES", "-appLanguage", lang, "-auditSignedOut", "-noResume", "-demoPlus",
                               "-isolatedStore", "preview-\(lang)", "-demoStory", "-noSync"] + args
        app.launch()
    }

    private func mark(_ scene: String) {
        print("PREVIEW|mark|\(scene)|\(Date().timeIntervalSince1970)")
    }

    private func hold(_ seconds: Double) { Thread.sleep(forTimeInterval: seconds) }

    // Taps where the element is drawn and logs the point (0…1 of the screen) for the edit.
    private func tap(_ element: XCUIElement, wait: Double = 8) {
        guard element.waitForExistence(timeout: wait) else {
            print("PREVIEW|miss|\(element)")
            return
        }
        let frame = element.frame, screen = app.windows.firstMatch.frame
        let x = frame.midX / screen.width, y = frame.midY / screen.height
        print("PREVIEW|tap|\(x)|\(y)|\(Date().timeIntervalSince1970)")
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
    }

    private func button(_ text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", text)).firstMatch
    }

    private func containing(_ text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    func testRecordPreview() {
        // 1. The launch splash, then a map from a topic: Menu → New Map → the topic → Creating → the map.
        mark("splash")
        launch(["-demoGenerate", "-splash"])
        hold(1.0)
        mark("home")
        hold(0.8)
        tap(app.buttons[t("Menu", "Меню")].firstMatch)
        hold(1.1)
        mark("menu")
        tap(button(t("New Map", "Новая карта")))
        hold(1.0)
        mark("newmap")
        // The app types the sample topic itself (no keyboard in the shot).
        hold(2.9)
        tap(app.buttons[t("Build Map", "Построить карту")].firstMatch)
        mark("creating")
        hold(4.6)
        mark("map")
        hold(1.2)

        // 2. The idea's panel.
        tap(containing(t("Calvin cycle", "Цикл Кальвина")))
        hold(1.4)
        mark("panel")
        hold(1.6)

        // 4. Slides: a few of them, then presenting.
        launch(["-demoDeck", "-demoPresenterView"])
        hold(3.0)
        mark("deck")
        hold(0.8)
        for x in [0.28, 0.44, 0.60, 0.76] {
            let point = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.width * x, dy: app.frame.height * 0.462))
            print("PREVIEW|tap|\(x)|0.462|\(Date().timeIntervalSince1970)")
            point.tap()
            hold(1.0)
        }
        mark("slides")
        tap(app.buttons[t("Present", "Презентация")].firstMatch)
        hold(1.2)
        mark("present")
        hold(1.2)
        tap(app.buttons["presenter.next"])
        hold(1.0)
        tap(app.buttons["presenter.next"])
        hold(1.4)

        // 5. Today: a task done, with Undo.
        launch(["-demoToday"])
        hold(3.0)
        mark("today")
        hold(1.2)
        tap(app.buttons[t("Mark “Review the light reactions” as done", "Отметить «Повторить световую фазу» выполненной")])
        hold(2.4)

        // 6. Study: the card, the answer, a grade.
        launch(["-demoMap", "-demoStudy"])
        hold(3.2)
        mark("study")
        hold(1.2)
        tap(app.buttons[t("Show Answer", "Показать ответ")])
        hold(1.8)
        tap(button(t("Good,", "Хорошо,")))
        hold(1.6)
        mark("end")
    }
}
