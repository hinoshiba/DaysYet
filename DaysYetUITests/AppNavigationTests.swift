import XCTest

final class AppNavigationTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAboutReplacesSettingsAndReturnsToTimes() {
        let app = launchTimes(language: "en", locale: "en_US")
        XCTAssertTrue(app.buttons.matching(identifier: "Widget").firstMatch.exists)
        XCTAssertTrue(app.buttons.matching(identifier: "Times").firstMatch.isSelected)
        XCTAssertFalse(app.buttons.matching(identifier: "Settings").firstMatch.exists)

        app.buttons["app.info.open"].tap()
        XCTAssertTrue(app.buttons["app.info.done"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Version"].exists)
        XCTAssertFalse(app.buttons["settings.widgets"].exists)
        attachScreenshot(app, name: "app-info-en")

        app.buttons["app.info.privacy"].tap()
        let privacy = app.navigationBars["Privacy"]
        XCTAssertTrue(privacy.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "info button at the top right of Times")).firstMatch.exists)
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
        app.buttons["app.info.done"].tap()
        XCTAssertTrue(app.buttons["app.info.open"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(identifier: "Times").firstMatch.isSelected)
        XCTAssertTrue(app.buttons["times.metric.week"].exists)

        app.buttons.matching(identifier: "Widget").firstMatch.tap()
        XCTAssertTrue(app.buttons["widget.guide"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["app.info.done"].exists)
        attachScreenshot(app, name: "two-tabs-widget-en")
        app.buttons["widget.guide"].tap()
        let guidePrivacy = app.buttons["app.info.privacy"]
        reveal(guidePrivacy, in: app)
        attachScreenshot(app, name: "widget-guide-legal-links-en")
        guidePrivacy.tap()
        XCTAssertTrue(privacy.waitForExistence(timeout: 5))
        let publicPolicy = app.descendants(matching: .any).matching(identifier: "app.info.privacy.public").firstMatch
        reveal(publicPolicy, in: app)
        XCTAssertTrue(publicPolicy.isHittable)
        privacy.buttons.element(boundBy: 0).tap()
        let guideLicense = app.buttons["app.info.license"]
        reveal(guideLicense, in: app)
        guideLicense.tap()
        XCTAssertTrue(app.staticTexts["Apache License 2.0"].waitForExistence(timeout: 5))
        app.navigationBars["License"].buttons.element(boundBy: 0).tap()
        app.buttons["widget.guide.done"].tap()
        XCTAssertTrue(app.buttons["widget.guide"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(identifier: "Widget").firstMatch.isSelected)
        app.buttons.matching(identifier: "Times").firstMatch.tap()
        XCTAssertTrue(app.buttons["app.info.open"].waitForExistence(timeout: 5))
        attachScreenshot(app, name: "two-tabs-times-en")
    }

    @MainActor
    func testResetFromAboutReturnsToOnboarding() {
        // Screenshot mode uses a synthetic profile and never resets persisted data.
        let app = launchTimes(language: "en", locale: "en_US")
        app.buttons["app.info.open"].tap()
        app.buttons["app.info.reset"].tap()
        app.buttons["Delete"].tap()
        let next = app.buttons["Continue"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()
        next.tap()
        app.buttons["Get started"].tap()
        XCTAssertTrue(app.buttons["app.info.open"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["app.info.done"].exists)
        XCTAssertTrue(app.buttons["times.metric.week"].exists)
    }

    @MainActor
    func testJapaneseAboutWithLargeText() {
        let app = launchTimes(language: "ja", locale: "ja_JP", largeText: true)
        let info = app.buttons["app.info.open"]
        XCTAssertEqual(info.label, "このアプリについて")
        XCTAssertTrue(info.isHittable)
        attachScreenshot(app, name: "two-tabs-times-large-text-ja")
        info.tap()
        let privacy = app.buttons["app.info.privacy"]
        for _ in 0..<8 {
            if privacy.exists && privacy.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(privacy.isHittable)
        attachScreenshot(app, name: "app-info-large-text-ja")
        privacy.tap()
        let privacyNavigation = app.navigationBars["プライバシー"]
        XCTAssertTrue(privacyNavigation.waitForExistence(timeout: 5))
        privacyNavigation.buttons.element(boundBy: 0).tap()
        app.buttons["app.info.done"].tap()
        XCTAssertTrue(info.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(identifier: "時間").firstMatch.isSelected)
        XCTAssertFalse(app.buttons.matching(identifier: "設定").firstMatch.exists)

        app.buttons.matching(identifier: "ウィジェット").firstMatch.tap()
        app.buttons["widget.guide"].tap()
        reveal(privacy, in: app)
        attachScreenshot(app, name: "widget-guide-legal-links-large-text-ja")
        privacy.tap()
        XCTAssertTrue(privacyNavigation.waitForExistence(timeout: 5))
        let publicPolicy = app.descendants(matching: .any).matching(identifier: "app.info.privacy.public").firstMatch
        reveal(publicPolicy, in: app)
        XCTAssertTrue(publicPolicy.isHittable)
        privacyNavigation.buttons.element(boundBy: 0).tap()
        app.buttons["widget.guide.done"].tap()
        XCTAssertTrue(app.buttons["widget.guide"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(identifier: "ウィジェット").firstMatch.isSelected)
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
        XCTAssertTrue(app.buttons["app.info.open"].waitForExistence(timeout: 10))
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
