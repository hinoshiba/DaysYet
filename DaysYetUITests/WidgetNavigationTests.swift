import XCTest

final class WidgetNavigationTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testColorsReturnsToTheSelectedLayoutWithoutAnotherThemeSelector() {
        let app = launchEditor(screenshotMode: true)
        let circles = app.segmentedControls["widget.layout"].buttons["Circles"]
        XCTAssertTrue(circles.waitForExistence(timeout: 10))
        circles.tap()
        let colors = app.buttons["widget.colors.open"]
        reveal(colors, in: app)
        colors.tap()
        XCTAssertTrue(app.buttons["widget.colors.week"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["widget.colors.template"].exists)
        app.tabBars.buttons["Times"].tap()
        app.tabBars.buttons["Widget"].tap()
        XCTAssertTrue(app.buttons["widget.colors.week"].exists)
        app.navigationBars["Timeline colors"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(circles.waitForExistence(timeout: 5))
        XCTAssertTrue(circles.isSelected)
        XCTAssertTrue(app.buttons["widget.guide"].isHittable)
        attachScreenshot(app, name: "widget-editor-colors-return")
    }

    @MainActor
    func testJapaneseGuideNamesTheSelectedWidgetAndExplainsReplacement() {
        let app = launchEditor(screenshotMode: true, japanese: true)
        let circles = app.segmentedControls["widget.layout"].buttons["サークル"]
        XCTAssertTrue(circles.waitForExistence(timeout: 10))
        circles.tap()
        let guide = app.buttons["widget.guide"]
        XCTAssertTrue(guide.isHittable)
        guide.tap()

        let sizes = app.staticTexts["「DaysYet」の小・中・大サイズを選びます。サークルは小サイズで先頭4つ、中・大サイズで最大8つを表示します。"]
        reveal(sizes, in: app)
        attachScreenshot(app, name: "widget-guide-japanese")
        app.navigationBars["使い方"].buttons.element(boundBy: 0).tap()
        attachScreenshot(app, name: "widget-editor-japanese-small-preview")
        XCTAssertTrue(circles.isSelected)
    }

    @MainActor
    func testEditorChoiceSurvivesRelaunchAndScreenshotModeDoesNotReplaceIt() {
        let app = launchEditor(screenshotMode: false)
        let picker = app.segmentedControls["widget.layout"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        let initialChoice = picker.buttons["Circles"].isSelected ? "Circles" : "Three rows"
        picker.buttons["Circles"].tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(picker.buttons["Circles"].waitForExistence(timeout: 10))
        XCTAssertTrue(picker.buttons["Circles"].isSelected)

        app.terminate()
        app.launchArguments = arguments(screenshotMode: true, japanese: false)
        app.launch()
        XCTAssertTrue(picker.buttons["Three rows"].waitForExistence(timeout: 10))
        XCTAssertTrue(picker.buttons["Three rows"].isSelected)
        picker.buttons["Circles"].tap()
        picker.buttons["Three rows"].tap()

        app.terminate()
        app.launchArguments = arguments(screenshotMode: true, japanese: false) + ["--screenshot-circles", "--screenshot-colors"]
        app.launch()
        XCTAssertTrue(app.buttons["widget.colors.week"].waitForExistence(timeout: 10))
        app.navigationBars["Timeline colors"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(picker.buttons["Circles"].isSelected)

        app.terminate()
        app.launchArguments = arguments(screenshotMode: false, japanese: false)
        app.launch()
        XCTAssertTrue(picker.buttons["Circles"].waitForExistence(timeout: 10))
        XCTAssertTrue(picker.buttons["Circles"].isSelected)
        picker.buttons[initialChoice].tap()
    }

    @MainActor
    func testDeletingSyntheticDataAlsoResetsTheLayout() {
        let app = launchEditor(screenshotMode: true)
        let picker = app.segmentedControls["widget.layout"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        picker.buttons["Circles"].tap()
        let info = app.buttons["app.info.open"]
        app.tabBars.buttons["Times"].tap()
        reveal(info, in: app)
        info.tap()
        XCTAssertTrue(app.navigationBars["About DaysYet"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Widget"].tap()
        reveal(info, in: app)
        app.buttons["app.info.open"].tap()
        app.buttons["app.info.reset"].tap()
        app.buttons["Delete"].tap()
        let next = app.buttons["Continue"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()
        next.tap()
        app.buttons["Get started"].tap()
        app.tabBars.buttons["Widget"].tap()
        XCTAssertTrue(picker.buttons["Three rows"].waitForExistence(timeout: 10))
        XCTAssertTrue(picker.buttons["Three rows"].isSelected)
        app.tabBars.buttons["Times"].tap()
        XCTAssertTrue(app.buttons["times.guide"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["About DaysYet"].exists)
    }

    @MainActor
    func testTimesLongPressChangesAndResetsOnlyTheSelectedColor() {
        let app = launchEditor(screenshotMode: true)
        app.tabBars.buttons["Times"].tap()
        let week = app.descendants(matching: .any)["times.metric.week"].firstMatch
        XCTAssertTrue(week.waitForExistence(timeout: 10))
        week.press(forDuration: 1)
        let changeColor = app.buttons["times.color.change"]
        XCTAssertTrue(changeColor.waitForExistence(timeout: 5))
        changeColor.tap()
        let picker = app.buttons["times.color.picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertEqual(picker.value as? String, "Palette template")
        attachScreenshot(app, name: "times-color-shortcut")
        picker.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.5)).tap()
        // The system color picker follows the simulator's system language,
        // independently of the app's explicit language.
        let black = app.otherElements.matching(
            NSPredicate(format: "label IN %@", ["ブラック 0", "Black 0"])
        ).firstMatch
        XCTAssertTrue(black.waitForExistence(timeout: 5))
        black.tap()
        app.buttons.matching(NSPredicate(format: "label IN %@", ["閉じる", "Close"])).firstMatch.tap()
        XCTAssertTrue(app.buttons["times.color.reset"].waitForExistence(timeout: 5))
        XCTAssertEqual(picker.value as? String, "#000000")
        attachScreenshot(app, name: "times-color-changed-preview")
        app.navigationBars["Change color"].buttons.element(boundBy: 0).tap()

        let month = app.descendants(matching: .any)["times.metric.month"].firstMatch
        month.press(forDuration: 1)
        changeColor.tap()
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertEqual(picker.value as? String, "Palette template")
        app.navigationBars["Change color"].buttons.element(boundBy: 0).tap()

        week.press(forDuration: 1)
        changeColor.tap()
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertEqual(picker.value as? String, "#000000")
        app.buttons["times.color.reset"].tap()
        XCTAssertEqual(picker.value as? String, "Palette template")
        XCTAssertFalse(app.buttons["times.color.reset"].exists)
        app.navigationBars["Change color"].buttons.element(boundBy: 0).tap()
    }

    @MainActor
    func testJapaneseEditableCardKeepsNormalTapAfterLongPress() {
        let app = launchEditor(screenshotMode: true, japanese: true)
        app.tabBars.buttons["時間"].tap()
        let milestone = app.buttons["times.metric.customLife"]
        reveal(milestone, in: app)
        milestone.press(forDuration: 1)
        let changeColor = app.buttons["times.color.change"]
        XCTAssertTrue(changeColor.waitForExistence(timeout: 5))
        changeColor.tap()
        XCTAssertTrue(app.buttons["times.color.picker"].waitForExistence(timeout: 5))
        attachScreenshot(app, name: "times-color-shortcut-japanese")
        app.navigationBars["色を変更"].buttons.element(boundBy: 0).tap()
        milestone.tap()
        XCTAssertTrue(app.textFields["customLife.name"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLargeTextColorsAndGuideRemainReachable() {
        let app = XCUIApplication()
        app.launchArguments = arguments(screenshotMode: true, japanese: true) + [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()
        let layout = app.buttons["widget.layout"]
        XCTAssertTrue(layout.waitForExistence(timeout: 5))
        layout.tap()
        app.buttons["サークル"].tap()
        let guide = app.buttons["widget.guide"]
        reveal(guide, in: app)
        XCTAssertTrue(guide.isHittable)
        guide.tap()
        XCTAssertTrue(app.navigationBars["使い方"].waitForExistence(timeout: 5))
        attachScreenshot(app, name: "widget-guide-japanese-AX5")
        app.navigationBars["使い方"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(guide.waitForExistence(timeout: 5))
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
        for _ in 0..<18 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }
}
