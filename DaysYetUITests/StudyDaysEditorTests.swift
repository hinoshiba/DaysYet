import XCTest

final class StudyDaysEditorTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCalendarOverridesWeekdaysAndCapturesJapaneseUI() throws {
        let app = launchEditor(language: "ja", locale: "ja_JP")
        let weekday = app.buttons["study.weekday.2"]
        reveal(weekday, in: app)
        let originalWeekday = weekday.value as? String
        weekday.tap()
        XCTAssertNotEqual(weekday.value as? String, originalWeekday)
        weekday.tap()
        XCTAssertEqual(weekday.value as? String, originalWeekday)

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        let day = app.buttons["study.calendar.day.\(formatter.string(from: .now))-12"]
        reveal(day, in: app)
        let originalDay = day.value as? String
        day.tap()
        XCTAssertNotEqual(day.value as? String, originalDay)
        day.tap()
        XCTAssertEqual(day.value as? String, originalDay)
        day.tap() // Show an individual date addition alongside the weekday pattern.
        app.swipeUp()
        attachScreenshot(app, name: "study-days-ios-ja-calendar")
        app.swipeDown()
        app.swipeDown()
        attachScreenshot(app, name: "study-days-ios-ja-overview")
    }

    @MainActor
    func testEditorIsReachableFromSettingsAndKeepsChanges() {
        let app = XCUIApplication()
        app.launchArguments = ["--screenshot-mode", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.tabBars.buttons["Settings"].tap()
        app.buttons["settings.editTimes"].tap()
        app.buttons["study.openEditor"].tap()
        let weekday = app.buttons["study.weekday.2"]
        reveal(weekday, in: app)
        weekday.tap()
        let changedValue = weekday.value as? String
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["study.openEditor"].tap()
        reveal(weekday, in: app)
        XCTAssertEqual(weekday.value as? String, changedValue)
    }

    @MainActor
    func testEnglishCalendarAndLargeText() {
        let app = launchEditor(language: "en", locale: "en_US")
        let day = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "study.calendar.day.")).firstMatch
        reveal(day, in: app)
        app.swipeUp()
        attachScreenshot(app, name: "study-days-ios-en-calendar")
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let weekday = app.buttons["study.weekday.2"]
        reveal(weekday, in: app)
        XCTAssertTrue(weekday.isHittable)
        let oldValue = weekday.value as? String
        weekday.tap()
        XCTAssertNotEqual(weekday.value as? String, oldValue)
        attachScreenshot(app, name: "study-days-ios-en-large-text")
    }

    @MainActor
    private func launchEditor(language: String, locale: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--screenshot-mode", "--screenshot-study-days", "-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        app.launch()
        XCTAssertTrue(app.textFields["study.name"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
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
