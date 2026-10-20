import XCTest

final class WidgetNavigationTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSettingsReturnsFromColorsToTheSelectedLayout() {
        let app = launchEditor(screenshotMode: true)
        let circles = app.segmentedControls["widget.layout"].buttons["Four circles"]
        XCTAssertTrue(circles.waitForExistence(timeout: 10))
        circles.tap()
        let colors = app.buttons["widget.colors"]
        reveal(colors, in: app)
        colors.tap()
        XCTAssertTrue(app.buttons["widget.colors.template"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Settings"].tap()
        app.buttons["settings.widgets"].tap()

        XCTAssertTrue(circles.waitForExistence(timeout: 5))
        XCTAssertTrue(circles.isSelected)
        XCTAssertTrue(app.buttons["widget.guide"].isHittable)
        XCTAssertFalse(app.buttons["widget.colors.template"].exists)
        attachScreenshot(app, name: "widget-editor-english-small-preview")
    }

    @MainActor
    func testJapaneseGuideNamesTheSelectedWidgetAndExplainsReplacement() {
        let app = launchEditor(screenshotMode: true, japanese: true)
        let circles = app.segmentedControls["widget.layout"].buttons["4つのサークル"]
        XCTAssertTrue(circles.waitForExistence(timeout: 10))
        circles.tap()
        let guide = app.buttons["widget.guide"]
        XCTAssertTrue(guide.isHittable)
        guide.tap()

        XCTAssertTrue(app.staticTexts["「4つのサークル」の小・大サイズを選んで追加します。"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["新しいウィジェットの表示を確認したら、不要になった方を長押しして削除できます。"].exists)
        attachScreenshot(app, name: "widget-guide-japanese")
        app.buttons["完了"].tap()
        attachScreenshot(app, name: "widget-editor-japanese-small-preview")
        XCTAssertTrue(circles.isSelected)
    }

    @MainActor
    func testEditorChoiceSurvivesRelaunchAndScreenshotModeDoesNotReplaceIt() {
        let app = launchEditor(screenshotMode: false)
        let picker = app.segmentedControls["widget.layout"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        let initialChoice = picker.buttons["Four circles"].isSelected ? "Four circles" : "Three timelines"
        picker.buttons["Four circles"].tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(picker.buttons["Four circles"].waitForExistence(timeout: 10))
        XCTAssertTrue(picker.buttons["Four circles"].isSelected)

        app.terminate()
        app.launchArguments = arguments(screenshotMode: true, japanese: false)
        app.launch()
        XCTAssertTrue(picker.buttons["Three timelines"].waitForExistence(timeout: 10))
        XCTAssertTrue(picker.buttons["Three timelines"].isSelected)
        picker.buttons["Four circles"].tap()
        picker.buttons["Three timelines"].tap()

        app.terminate()
        app.launchArguments = arguments(screenshotMode: false, japanese: false)
        app.launch()
        XCTAssertTrue(picker.buttons["Four circles"].waitForExistence(timeout: 10))
        XCTAssertTrue(picker.buttons["Four circles"].isSelected)
        picker.buttons[initialChoice].tap()
    }

    @MainActor
    func testDeletingAllDataAlsoResetsTheRememberedEditor() {
        let app = launchEditor(screenshotMode: false)
        let picker = app.segmentedControls["widget.layout"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        picker.buttons["Four circles"].tap()
        app.tabBars.buttons["Settings"].tap()
        let reset = app.buttons["Delete all data"]
        reveal(reset, in: app)
        reset.tap()
        app.buttons["Delete"].tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(picker.buttons["Three timelines"].waitForExistence(timeout: 10))
        XCTAssertTrue(picker.buttons["Three timelines"].isSelected)
    }

    @MainActor
    func testLargeTextSettingsAndGuideRemainReachable() {
        let app = XCUIApplication()
        app.launchArguments = arguments(screenshotMode: true, japanese: true) + [
            "--screenshot-settings", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()
        let settings = app.buttons["settings.widgets"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        attachScreenshot(app, name: "widget-settings-japanese-AX5")
        settings.tap()
        let layout = app.buttons["widget.layout"]
        XCTAssertTrue(layout.waitForExistence(timeout: 5))
        layout.tap()
        app.buttons["4つのサークル"].tap()
        let guide = app.buttons["widget.guide"]
        reveal(guide, in: app)
        XCTAssertTrue(guide.isHittable)
        guide.tap()
        XCTAssertTrue(app.navigationBars["追加・切り替え方法"].waitForExistence(timeout: 5))
        attachScreenshot(app, name: "widget-guide-japanese-AX5")
    }

    @MainActor
    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func launchEditor(screenshotMode: Bool, japanese: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments(screenshotMode: screenshotMode, japanese: japanese)
        app.launch()
        return app
    }

    private func arguments(screenshotMode: Bool, japanese: Bool) -> [String] {
        [
            screenshotMode ? "--screenshot-mode" : "--skip-onboarding",
            "-AppleLanguages", japanese ? "(ja)" : "(en)",
            "-AppleLocale", japanese ? "ja_JP" : "en_US"
        ]
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }
}
