import XCTest

final class CircleWidgetEditorTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testThemePreviewsStayInSyncAcrossLayouts() {
        let app = XCUIApplication()
        app.launchArguments = ["--screenshot-mode", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let themes = ["vividNight", "quietForest", "softDawn", "calmSea"]
        for theme in themes {
            let choice = app.buttons["widget.theme.\(theme)"]
            XCTAssertTrue(choice.waitForExistence(timeout: 5))
            XCTAssertTrue(choice.isHittable)
        }
        XCTAssertFalse(app.buttons["widget.preview.toggle"].exists)
        app.buttons["widget.theme.quietForest"].tap()
        XCTAssertEqual(app.buttons["widget.theme.quietForest"].value as? String, "Selected")
        attachScreenshot(app, name: "theme-previews-rows-en")

        app.segmentedControls.buttons["Circles"].tap()
        XCTAssertFalse(app.switches["widget.theme.followRows"].exists)
        XCTAssertFalse(app.staticTexts["Use the Three rows theme"].exists)
        XCTAssertEqual(app.buttons["widget.theme.quietForest"].value as? String, "Selected")
        app.buttons["widget.theme.softDawn"].tap()
        XCTAssertEqual(app.buttons["widget.theme.softDawn"].value as? String, "Selected")

        app.segmentedControls.buttons["Three rows"].tap()
        XCTAssertEqual(app.buttons["widget.theme.softDawn"].value as? String, "Selected")
        app.buttons["widget.theme.calmSea"].tap()
        app.segmentedControls.buttons["Circles"].tap()
        XCTAssertEqual(app.buttons["widget.theme.calmSea"].value as? String, "Selected")
        app.buttons["widget.theme.vividNight"].tap()
        attachScreenshot(app, name: "theme-previews-circles-en")
        app.segmentedControls.buttons["Three rows"].tap()
        XCTAssertEqual(app.buttons["widget.theme.vividNight"].value as? String, "Selected")
        app.segmentedControls.buttons["Circles"].tap()
        XCTAssertEqual(app.buttons["widget.theme.vividNight"].value as? String, "Selected")
        app.buttons["widget.theme.vividNight"].tap()
        XCTAssertEqual(app.buttons["widget.theme.vividNight"].value as? String, "Selected")
    }

    @MainActor
    func testAddEightCirclesAndCaptureEveryJapaneseSize() {
        let app = launchCircles(language: "ja", locale: "ja_JP")
        for metric in ["workday", "study", "customLife", "healthyLife"] {
            app.buttons["widget.circle.add"].tap()
            chooseTime(metric, in: app)
        }
        XCTAssertFalse(app.buttons["widget.circle.add"].isEnabled)
        app.segmentedControls["widget.circle.size"].buttons["中・横長"].tap()
        attachScreenshot(app, name: "circle-eight-medium-ja")
        app.segmentedControls["widget.circle.size"].buttons["小"].tap()
        attachScreenshot(app, name: "circle-eight-small-ja")
        app.segmentedControls["widget.circle.size"].buttons["大"].tap()
        attachScreenshot(app, name: "circle-eight-large-ja")
    }

    @MainActor
    func testPickerSelectsTimesWithoutEditingTheirDetails() {
        let app = launchCircles(language: "en", locale: "en_US")
        let first = app.buttons["widget.circle.0"]
        XCTAssertTrue(first.label.contains("This week"))
        app.buttons["widget.circle.add"].tap()
        XCTAssertTrue(app.buttons["widget.time.week"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields.count, 0)
        XCTAssertEqual(app.datePickers.count, 0)
        XCTAssertFalse(app.buttons["time.editor.save"].exists)
        app.buttons["widget.time.cancel"].tap()
        XCTAssertFalse(app.buttons["widget.circle.4"].exists)

        first.tap()
        chooseTime("workday", in: app)
        XCTAssertTrue(first.label.contains("Work hours"))
        first.tap()
        let workChoice = app.buttons["widget.time.workday"]
        reveal(workChoice, in: app)
        XCTAssertEqual(workChoice.value as? String, "Selected")
        app.buttons["widget.time.cancel"].tap()

        app.buttons.matching(identifier: "Times").firstMatch.tap()
        let workCard = app.buttons["times.metric.workday"]
        reveal(workCard, in: app)
        workCard.tap()
        let name = app.textFields["workday.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Night shift")
        app.buttons["time.editor.save"].tap()
        workCard.tap()
        name.tap()
        name.typeText(" cancelled")
        app.buttons["time.editor.cancel"].tap()
        workCard.tap()
        XCTAssertEqual(name.value as? String, "Night shift")
        app.buttons["time.editor.cancel"].tap()

        app.buttons.matching(identifier: "Widget").firstMatch.tap()
        reveal(first, in: app, scrollingUp: false)
        XCTAssertTrue(first.label.contains("Night shift"))
        first.tap()
        reveal(workChoice, in: app)
        XCTAssertTrue(workChoice.label.contains("Night shift"))
        XCTAssertFalse(name.exists)
        attachScreenshot(app, name: "time-picker-custom-name-en")
    }

    @MainActor
    func testReorderingAndKeepingAtLeastOneCircle() {
        let app = launchCircles(language: "en", locale: "en_US")
        app.buttons["widget.circle.editList"].tap()
        let handles = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Reorder"))
        XCTAssertGreaterThanOrEqual(handles.count, 2, app.debugDescription)
        let source = handles.element(boundBy: 1).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let destination = handles.element(boundBy: 0).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            .withOffset(CGVector(dx: 0, dy: -20))
        source.press(forDuration: 0.5, thenDragTo: destination, withVelocity: .slow, thenHoldForDuration: 0.5)
        app.buttons["widget.circle.editList"].tap()
        XCTAssertTrue(app.buttons["widget.circle.0"].label.contains("This month"), app.debugDescription)
        XCTAssertTrue(app.buttons["widget.circle.1"].label.contains("This week"))

        for _ in 0..<3 {
            app.buttons["widget.circle.0"].swipeLeft()
            app.buttons["Delete"].tap()
        }
        XCTAssertTrue(app.buttons["widget.circle.0"].exists)
        XCTAssertFalse(app.buttons["widget.circle.1"].exists)
        app.buttons["widget.circle.editList"].tap()
        let minimumNotice = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Keep at least one circle.")).firstMatch
        XCTAssertTrue(minimumNotice.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Delete")).firstMatch.exists)
        attachScreenshot(app, name: "circle-last-item-en")
    }

    @MainActor
    func testRowsUseThePickerAndLibraryNavigationSwitchesTabs() {
        let app = launchCircles(language: "en", locale: "en_US")
        app.segmentedControls.buttons["Three rows"].tap()
        XCTAssertFalse(app.segmentedControls["widget.circle.size"].exists)
        app.buttons["widget.metric.0"].tap()
        let year = app.buttons["widget.time.year"]
        XCTAssertTrue(year.waitForExistence(timeout: 5))
        XCTAssertTrue(year.label.contains("Swaps with the middle row"))
        XCTAssertEqual(app.textFields.count, 0)
        year.tap()
        XCTAssertTrue(app.buttons["widget.metric.0"].label.contains("This year"))
        XCTAssertTrue(app.buttons["widget.metric.1"].label.contains("This month"))

        app.segmentedControls.buttons["Circles"].tap()
        app.buttons["widget.circle.add"].tap()
        let libraryLink = app.buttons["widget.time.openLibrary"]
        reveal(libraryLink, in: app)
        libraryLink.tap()
        let timesTab = app.buttons.matching(identifier: "Times").firstMatch
        let switchedTabs = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: timesTab)
        XCTAssertEqual(XCTWaiter.wait(for: [switchedTabs], timeout: 5), .completed)
        XCTAssertFalse(app.buttons["widget.time.cancel"].exists)
        XCTAssertFalse(app.buttons["time.editor.save"].exists)

        XCTAssertFalse(app.buttons.matching(identifier: "Settings").firstMatch.exists)
        app.buttons.matching(identifier: "Widget").firstMatch.tap()
        XCTAssertTrue(app.segmentedControls.buttons["Circles"].isSelected)
        XCTAssertFalse(app.buttons["widget.circle.4"].exists)
        attachScreenshot(app, name: "time-picker-circle-list-en")
    }

    @MainActor
    func testStudyContentIsEditedInTimesAndThenSelectedForACircle() {
        let app = launchCircles(language: "en", locale: "en_US")
        app.buttons.matching(identifier: "Times").firstMatch.tap()
        let studyCard = app.buttons["times.metric.study"]
        reveal(studyCard, in: app)
        studyCard.tap()
        let name = app.textFields["study.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Cancelled plan")
        app.buttons["time.editor.cancel"].tap()
        studyCard.tap()
        XCTAssertNotEqual(name.value as? String, "Cancelled plan")
        name.tap()
        name.typeText("Saved plan")
        app.buttons["time.editor.save"].tap()

        app.buttons.matching(identifier: "Widget").firstMatch.tap()
        app.buttons["widget.circle.add"].tap()
        let studyChoice = app.buttons["widget.time.study"]
        reveal(studyChoice, in: app)
        XCTAssertTrue(studyChoice.label.contains("Saved plan"))
        XCTAssertFalse(name.exists)
        studyChoice.tap()
        let added = app.buttons["widget.circle.4"]
        reveal(added, in: app)
        XCTAssertTrue(added.label.contains("Saved plan"))
        XCTAssertFalse(app.buttons["widget.circle.5"].exists)
    }

    @MainActor
    func testJapanesePickerAndEnglishAccessibilityText() {
        let app = launchCircles(language: "ja", locale: "ja_JP")
        app.buttons["widget.theme.softDawn"].tap()
        XCTAssertEqual(app.buttons["widget.theme.softDawn"].value as? String, "選択中")
        attachScreenshot(app, name: "time-picker-circle-list-ja")
        app.buttons["widget.circle.add"].tap()
        XCTAssertTrue(app.buttons["widget.time.week"].waitForExistence(timeout: 5))
        attachScreenshot(app, name: "time-picker-add-ja")
        chooseTime("workday", in: app)
        let added = app.buttons["widget.circle.4"]
        reveal(added, in: app)
        XCTAssertTrue(added.label.contains("勤務時間"))
        app.terminate()

        app.launchArguments = ["--screenshot-mode", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let sea = app.buttons["widget.theme.calmSea"]
        reveal(sea, in: app)
        sea.tap()
        XCTAssertEqual(sea.value as? String, "Selected")
        attachScreenshot(app, name: "theme-previews-large-text-en")
        let layout = app.buttons["widget.layout"]
        XCTAssertTrue(layout.waitForExistence(timeout: 10))
        layout.tap()
        app.buttons["Circles"].tap()
        app.buttons["widget.circle.add"].tap()
        XCTAssertTrue(app.buttons["widget.time.week"].waitForExistence(timeout: 5))
        attachScreenshot(app, name: "time-picker-accessibility-en")
        chooseTime("study", in: app)
        reveal(added, in: app)
        XCTAssertTrue(added.label.contains("Study days"))
    }

    @MainActor
    private func launchCircles(language: String, locale: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--screenshot-mode", "-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        app.launch()
        let circles = app.segmentedControls.buttons[language == "ja" ? "サークル" : "Circles"]
        XCTAssertTrue(circles.waitForExistence(timeout: 10))
        circles.tap()
        return app
    }

    @MainActor
    private func chooseTime(_ metric: String, in app: XCUIApplication) {
        let choice = app.buttons["widget.time.\(metric)"]
        reveal(choice, in: app)
        choice.tap()
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, scrollingUp: Bool = true) {
        for _ in 0..<10 {
            if element.exists && element.isHittable { return }
            if scrollingUp { app.swipeUp() } else { app.swipeDown() }
        }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor
    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
