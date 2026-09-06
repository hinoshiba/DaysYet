import XCTest
@testable import DaysYetMac

final class MacWorkTimeEditorTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    func testHourStepsKeepTheNextDayThroughStoreUpdates() throws {
        var editor = MacWorkTimeEditorState(minute: 23 * 60, calendar: calendar)
        let original = editor.date
        for (step, expectedMinute) in [(1, 0), (2, 60), (3, 120)] {
            let input = try XCTUnwrap(calendar.date(byAdding: .hour, value: step, to: original))
            let savedMinute = editor.accept(input, calendar: calendar)
            XCTAssertEqual(savedMinute, expectedMinute)

            // ProfileStore publishes after each step, including the step that
            // changes the End time label to End time (next day).
            editor.synchronize(minute: savedMinute, calendar: calendar)
            XCTAssertEqual(editor.date, input)
            XCTAssertEqual(calendar.component(.day, from: editor.date), 16)
        }
    }

    func testReverseHourStepsKeepThePreviousDayThroughStoreUpdates() throws {
        var editor = MacWorkTimeEditorState(minute: 0, calendar: calendar)
        let original = editor.date
        for (step, expectedMinute) in [(-1, 23 * 60), (-2, 22 * 60), (-3, 21 * 60)] {
            let input = try XCTUnwrap(calendar.date(byAdding: .hour, value: step, to: original))
            let savedMinute = editor.accept(input, calendar: calendar)
            XCTAssertEqual(savedMinute, expectedMinute)
            editor.synchronize(minute: savedMinute, calendar: calendar)
            XCTAssertEqual(editor.date, input)
            XCTAssertEqual(calendar.component(.day, from: editor.date), 14)
        }
    }

    func testMinuteStepsAcrossMidnightCanImmediatelyReverse() throws {
        var editor = MacWorkTimeEditorState(minute: 23 * 60 + 59, calendar: calendar)
        let original = editor.date
        for (offset, expectedMinute) in [(1, 0), (2, 1), (1, 0), (0, 1_439)] {
            let input = try XCTUnwrap(calendar.date(byAdding: .minute, value: offset, to: original))
            let savedMinute = editor.accept(input, calendar: calendar)
            XCTAssertEqual(savedMinute, expectedMinute)
            editor.synchronize(minute: savedMinute, calendar: calendar)
            XCTAssertEqual(editor.date, input)
        }
    }

    func testExternalChangesAndResetUpdateTimeWithoutReplacingTheEditingDay() throws {
        var editor = MacWorkTimeEditorState(minute: 23 * 60, calendar: calendar)
        let nextDay = try XCTUnwrap(calendar.date(byAdding: .hour, value: 2, to: editor.date))
        XCTAssertEqual(editor.accept(nextDay, calendar: calendar), 60)

        // An external update and the default work time both take effect on
        // the editor's current date, so subsequent steps remain continuous.
        for minute in [18 * 60 + 30, 9 * 60] {
            editor.synchronize(minute: minute, calendar: calendar)
            XCTAssertEqual(calendar.component(.day, from: editor.date), 16)
            XCTAssertEqual(calendar.component(.hour, from: editor.date), minute / 60)
            XCTAssertEqual(calendar.component(.minute, from: editor.date), minute % 60)
        }
        let input = try XCTUnwrap(calendar.date(byAdding: .hour, value: 1, to: editor.date))
        XCTAssertEqual(editor.accept(input, calendar: calendar), 10 * 60)
        editor.synchronize(minute: 10 * 60, calendar: calendar)
        XCTAssertEqual(editor.date, input)
    }
}
