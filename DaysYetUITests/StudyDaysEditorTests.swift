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
    func testEditorIsReachableFromTimesAndKeepsChanges() {
        let app = XCUIApplication()
        app.launchArguments = ["--screenshot-mode", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.buttons.matching(identifier: "Times").firstMatch.tap()
        let card = app.buttons["times.metric.study"]
        reveal(card, in: app)
        card.tap()
        let weekday = app.buttons["study.weekday.2"]
        reveal(weekday, in: app)
        weekday.tap()
        let changedValue = weekday.value as? String
        app.buttons["time.editor.save"].tap()
        reveal(card, in: app)
        card.tap()
        reveal(weekday, in: app)
        XCTAssertEqual(weekday.value as? String, changedValue)
    }

    @MainActor
    func testMonthsAndYearsRemainReadOnly() {
        let app = XCUIApplication()
        app.launchArguments = ["--screenshot-mode", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.buttons.matching(identifier: "Times").firstMatch.tap()
        XCTAssertTrue(app.buttons["times.metric.customLife"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["times.metric.week"].exists)
        for metric in ["month", "year"] {
            XCTAssertFalse(app.buttons["times.metric.\(metric)"].exists)
        }
    }

    @MainActor
    func testWeekStartIsEditedFromTimesWithSaveAndCancel() {
        let app = XCUIApplication()
        app.launchArguments = ["--screenshot-mode", "--screenshot-times", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let weekCard = app.buttons["times.metric.week"]
        XCTAssertTrue(weekCard.waitForExistence(timeout: 10))
        weekCard.tap()
        let firstDay = app.buttons["week.startDay"]
        XCTAssertTrue(firstDay.waitForExistence(timeout: 5))
        let originalLabel = firstDay.label
        let originalValue = firstDay.value as? String
        firstDay.tap()
        app.buttons["Monday"].tap()
        app.buttons["time.editor.cancel"].tap()

        weekCard.tap()
        XCTAssertEqual(firstDay.label, originalLabel)
        XCTAssertEqual(firstDay.value as? String, originalValue)
        firstDay.tap()
        app.buttons["Monday"].tap()
        app.buttons["time.editor.save"].tap()
        weekCard.tap()
        XCTAssertTrue(firstDay.label.contains("Monday") || (firstDay.value as? String)?.contains("Monday") == true)
        attachScreenshot(app, name: "week-settings-in-times-en")
        app.buttons["time.editor.cancel"].tap()

        XCTAssertFalse(app.buttons.matching(identifier: "Settings").firstMatch.exists)
        let studyCard = app.buttons["times.metric.study"]
        reveal(studyCard, in: app)
        studyCard.tap()
        let monday = app.buttons["study.weekday.2"]
        let sunday = app.buttons["study.weekday.1"]
        reveal(monday, in: app)
        XCTAssertLessThan(monday.frame.minX, sunday.frame.minX)
        XCTAssertEqual(monday.value as? String, "Not selected")
        XCTAssertEqual(sunday.value as? String, "Not selected")
        app.buttons["time.editor.cancel"].tap()
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
