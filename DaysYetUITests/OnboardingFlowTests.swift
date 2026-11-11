import XCTest

final class OnboardingFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testJapaneseExplanationSkipAndLaterSetup() {
        let app = launchOnboarding(language: "ja", locale: "ja_JP")
        app.buttons["onboarding.continue"].tap()
        let reason = app.staticTexts["onboarding.birthDateReason"]
        let birthDate = app.datePickers["onboarding.birthDate"]
        XCTAssertTrue(reason.waitForExistence(timeout: 5))
        XCTAssertTrue(reason.label.contains("目標年齢までの残り時間"))
        XCTAssertLessThan(reason.frame.maxY, birthDate.frame.minY)
        XCTAssertFalse(app.textFields["節目の名前"].exists)
        XCTAssertFalse(app.staticTexts["大切な日（任意）"].exists)
        XCTAssertTrue(app.buttons["onboarding.skip"].isHittable)
        attachScreenshot(app, name: "onboarding-reason-ja")

        let livePreview = app.descendants(matching: .any).matching(identifier: "onboarding.healthyLifePreview").firstMatch
        XCTAssertTrue(livePreview.exists)
        let originalPreview = livePreview.label
        app.sliders["onboarding.healthyLifeYears"].adjust(toNormalizedSliderPosition: 0.75)
        XCTAssertNotEqual(livePreview.label, originalPreview)
        XCTAssertTrue(livePreview.label.contains("%"))
        attachScreenshot(app, name: "onboarding-live-preview-updated-ja")

        app.buttons["onboarding.skip"].tap()
        XCTAssertTrue(app.staticTexts["onboarding.previewDescription"].label.contains("健康目標は、あとから"))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "今週。")).firstMatch.exists)
        attachScreenshot(app, name: "onboarding-deferred-preview-ja")
        app.buttons["onboarding.continue"].tap()
        XCTAssertTrue(app.buttons["widget.guide"].waitForExistence(timeout: 5))
        app.buttons.matching(identifier: "時間").firstMatch.tap()

        let health = app.buttons["times.metric.healthyLife"]
        reveal(health, in: app)
        XCTAssertTrue(health.label.contains("未設定"))
        attachScreenshot(app, name: "onboarding-deferred-times-ja")
        health.tap()
        app.sliders["healthyLife.years"].adjust(toNormalizedSliderPosition: 0.6)
        app.buttons["time.editor.cancel"].tap()
        XCTAssertTrue(health.label.contains("未設定"))
        health.tap()
        app.sliders["healthyLife.years"].adjust(toNormalizedSliderPosition: 0.7)
        app.buttons["time.editor.save"].tap()
        XCTAssertTrue(health.waitForExistence(timeout: 5))
        XCTAssertFalse(health.label.contains("未設定"))

        let target = app.buttons["times.metric.customLife"]
        reveal(target, in: app)
        XCTAssertTrue(target.label.hasPrefix("目標日まで"))
        target.tap()
        XCTAssertTrue(app.navigationBars["目標日まで"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["試験・旅行・締め切りなど、指定した日までの残り時間を表示します。"].exists)
        attachScreenshot(app, name: "target-date-editor-ja")
    }

    @MainActor
    func testReturningFromSkippedPreviewCanCompleteHealthyGoalInEnglish() {
        let app = launchOnboarding(language: "en", locale: "en_US")
        app.buttons["onboarding.continue"].tap()
        XCTAssertTrue(app.staticTexts["onboarding.birthDateReason"].waitForExistence(timeout: 5))
        attachScreenshot(app, name: "onboarding-reason-en")
        app.buttons["onboarding.skip"].tap()
        XCTAssertTrue(app.staticTexts["onboarding.previewDescription"].label.contains("Set your healthy-age goal later"))
        app.buttons["onboarding.back"].tap()
        let livePreview = app.descendants(matching: .any).matching(identifier: "onboarding.healthyLifePreview").firstMatch
        XCTAssertFalse(livePreview.label.contains("Not set"))
        let originalPreview = livePreview.label
        app.sliders["onboarding.healthyLifeYears"].adjust(toNormalizedSliderPosition: 0.5)
        XCTAssertNotEqual(livePreview.label, originalPreview)
        app.buttons["onboarding.continue"].tap()
        XCTAssertTrue(app.staticTexts["onboarding.previewDescription"].label.contains("Change your times anytime"))
        attachScreenshot(app, name: "onboarding-configured-preview-en")
        app.buttons["onboarding.continue"].tap()
        XCTAssertTrue(app.buttons["widget.guide"].waitForExistence(timeout: 5))
        app.buttons.matching(identifier: "Times").firstMatch.tap()
        let health = app.buttons["times.metric.healthyLife"]
        reveal(health, in: app)
        XCTAssertFalse(health.label.contains("Not set"))
        XCTAssertTrue(health.label.contains("%"))
    }

    @MainActor
    func testLargeTextKeepsSkipAvailableAndBirthDateReachable() {
        let app = launchOnboarding(language: "ja", locale: "ja_JP", largeText: true)
        app.buttons["onboarding.continue"].tap()
        XCTAssertTrue(app.staticTexts["onboarding.birthDateReason"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["onboarding.skip"].isHittable)
        attachScreenshot(app, name: "onboarding-reason-large-text-ja")
        let birthDate = app.datePickers["onboarding.birthDate"]
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<20 {
            if birthDate.isHittable && birthDate.frame.minY >= scroll.frame.minY
                && birthDate.frame.maxY <= scroll.frame.maxY { break }
            // A full flick can skip the entire field at the largest text size.
            let startY = birthDate.frame.minY < scroll.frame.minY ? 0.25 : 0.75
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
                .press(forDuration: 0.1, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        }
        XCTAssertTrue(birthDate.isHittable)
        XCTAssertGreaterThanOrEqual(birthDate.frame.minY, scroll.frame.minY)
        XCTAssertLessThanOrEqual(birthDate.frame.maxY, scroll.frame.maxY)
        XCTAssertTrue(app.buttons["onboarding.skip"].isHittable)
        attachScreenshot(app, name: "onboarding-fields-large-text-ja")
        app.buttons["onboarding.skip"].tap()
        app.buttons["onboarding.continue"].tap()
        XCTAssertTrue(app.buttons["widget.guide"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func launchOnboarding(language: String, locale: String, largeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--screenshot-mode", "--screenshot-onboarding", "-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.continue"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor
    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        // SwiftUI can still be fading the previous step after its accessibility
        // elements have disappeared. Capture the settled screen for visual QA.
        Thread.sleep(forTimeInterval: 0.7)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
