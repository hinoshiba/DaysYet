import XCTest

final class AppNavigationTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testBothTabsOpenTheSameGuideAndBottomAboutReturnsToItsTab() {
        let app = launchTimes(language: "en", locale: "en_US")
        XCTAssertFalse(app.buttons.matching(identifier: "Settings").firstMatch.exists)

        for tab in ["Times", "Widget"] {
            app.buttons.matching(identifier: tab).firstMatch.tap()
            let guide = app.buttons[tab == "Times" ? "times.guide" : "widget.guide"]
            XCTAssertEqual(guide.label, "How to use")
            guide.tap()
            XCTAssertTrue(app.navigationBars["How to use"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["Edit your times"].exists)
            XCTAssertTrue(app.staticTexts["Arrange your widget"].exists)
            XCTAssertFalse(app.buttons["app.info.privacy"].exists)
            attachScreenshot(app, name: "shared-guide-\(tab)-en")
            app.buttons["app.guide.done"].tap()
            XCTAssertTrue(guide.waitForExistence(timeout: 5))

            let info = app.buttons["app.info.open"]
            reveal(info, in: app)
            attachScreenshot(app, name: "bottom-about-\(tab)-en")
            info.tap()
            let about = app.navigationBars["About DaysYet"]
            XCTAssertTrue(about.waitForExistence(timeout: 5))
            XCTAssertTrue(about.buttons.element(boundBy: 0).isHittable)
            XCTAssertFalse(app.buttons["app.info.done"].exists)
            XCTAssertTrue(app.staticTexts["Version"].exists)
            attachScreenshot(app, name: "app-info-from-\(tab)-en")

            app.buttons["app.info.privacy"].tap()
            let privacy = app.navigationBars["Privacy"]
            XCTAssertTrue(privacy.waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "at the bottom of either Widget or Times")).firstMatch.exists)
            let publicPolicy = app.descendants(matching: .any).matching(identifier: "app.info.privacy.public").firstMatch
            reveal(publicPolicy, in: app)
            privacy.buttons.element(boundBy: 0).tap()

            app.buttons["app.info.license"].tap()
            XCTAssertTrue(app.staticTexts["Apache License 2.0"].waitForExistence(timeout: 5))
            app.navigationBars["License"].buttons.element(boundBy: 0).tap()

            app.buttons["app.info.reset"].tap()
            let delete = app.buttons["Delete"]
            XCTAssertTrue(delete.waitForExistence(timeout: 5))
            let cancel = app.buttons["Cancel"]
            if cancel.exists {
                cancel.tap()
            } else {
                // iPad dismisses a confirmation popover by tapping outside it.
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).tap()
            }
            XCTAssertFalse(delete.exists)
            about.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(info.waitForExistence(timeout: 5))
            XCTAssertTrue(info.isHittable)
            XCTAssertTrue(app.buttons.matching(identifier: tab).firstMatch.isSelected)

            // Native push navigation also supports the standard edge-swipe back.
            info.tap()
            XCTAssertTrue(about.waitForExistence(timeout: 5))
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
                .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
            XCTAssertTrue(info.waitForExistence(timeout: 5))
            XCTAssertTrue(info.isHittable)
        }
    }

    @MainActor
    func testResetFromAboutReturnsToOnboarding() {
        // Screenshot mode uses a synthetic profile and never resets persisted data.
        let app = launchTimes(language: "en", locale: "en_US")
        let info = app.buttons["app.info.open"]
        reveal(info, in: app)
        info.tap()
        app.buttons["app.info.reset"].tap()
        app.buttons["Delete"].tap()
        let next = app.buttons["Continue"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()
        next.tap()
        app.buttons["Get started"].tap()
        XCTAssertTrue(app.buttons["times.guide"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["About DaysYet"].exists)
        XCTAssertTrue(app.buttons.matching(identifier: "Times").firstMatch.isSelected)
    }

    @MainActor
    func testJapaneseGuideAndBottomAboutWithLargeText() {
        let app = launchTimes(language: "ja", locale: "ja_JP", largeText: true)
        for tab in ["時間", "ウィジェット"] {
            app.buttons.matching(identifier: tab).firstMatch.tap()
            if tab == "ウィジェット" {
                app.buttons["widget.layout"].tap()
                app.buttons["サークル"].tap()
            }
            let guide = app.buttons[tab == "時間" ? "times.guide" : "widget.guide"]
            XCTAssertEqual(guide.label, "使い方")
            XCTAssertTrue(guide.isHittable)
            guide.tap()
            XCTAssertTrue(app.navigationBars["使い方"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["時間を編集"].exists)
            attachScreenshot(app, name: "shared-guide-\(tab)-large-text-ja")
            app.buttons["app.guide.done"].tap()

            let info = app.buttons["app.info.open"]
            reveal(info, in: app)
            XCTAssertEqual(info.label, "このアプリについて")
            attachScreenshot(app, name: "bottom-about-\(tab)-large-text-ja")
            info.tap()
            let privacy = app.buttons["app.info.privacy"]
            reveal(privacy, in: app)
            attachScreenshot(app, name: "app-info-from-\(tab)-large-text-ja")
            privacy.tap()
            let privacyNavigation = app.navigationBars["プライバシー"]
            XCTAssertTrue(privacyNavigation.waitForExistence(timeout: 5))
            let publicPolicy = app.descendants(matching: .any).matching(identifier: "app.info.privacy.public").firstMatch
            reveal(publicPolicy, in: app)
            privacyNavigation.buttons.element(boundBy: 0).tap()
            app.navigationBars["このアプリについて"].buttons.element(boundBy: 0).tap()
            XCTAssertTrue(info.waitForExistence(timeout: 5))
            XCTAssertTrue(info.isHittable)
            XCTAssertTrue(app.buttons.matching(identifier: tab).firstMatch.isSelected)
            XCTAssertFalse(app.buttons.matching(identifier: "設定").firstMatch.exists)
        }
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<18 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor
    private func launchTimes(language: String, locale: String, largeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--screenshot-mode", "--screenshot-times", "-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        XCTAssertTrue(app.buttons["times.guide"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
