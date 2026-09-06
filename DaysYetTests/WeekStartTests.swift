import XCTest
#if os(macOS)
@testable import DaysYetMac
#else
@testable import DaysYet
#endif

final class WeekStartTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 1
        return calendar
    }

    private func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute)))
    }

    func testAllSevenWeekdaysUseMostRecentLocalMidnight() throws {
        let now = try date(9, 12) // Wednesday
        let starts: [(WeekStartDay, Int)] = [
            (.sunday, 6), (.monday, 7), (.tuesday, 8), (.wednesday, 9),
            (.thursday, 3), (.friday, 4), (.saturday, 5)
        ]
        for (weekday, day) in starts {
            var profile = UserProfile.initial
            profile.weekStartDay = weekday
            let interval = TimeProgressCalculator.dateInterval(for: .week, profile: profile, now: now, calendar: calendar)
            XCTAssertEqual(interval.start, try date(day), weekday.title)
            XCTAssertEqual(interval.end, try date(day + 7), weekday.title)
            XCTAssertEqual(interval.duration, 7 * 24 * 60 * 60, accuracy: 0.001)
        }
    }

    func testChangingWeekdayChangesBothCountdownAndElapsedProgress() throws {
        let now = try date(9, 12)
        for (weekday, elapsedDays, remaining) in [
            (WeekStartDay.saturday, 4.5, [2, 12]),
            (.sunday, 3.5, [3, 12]),
            (.monday, 2.5, [4, 12])
        ] {
            var profile = UserProfile.initial
            profile.weekStartDay = weekday
            let result = TimeProgressCalculator.snapshot(for: .week, profile: profile, now: now, calendar: calendar)
            XCTAssertEqual(result.elapsedFraction, elapsedDays / 7, accuracy: 0.000_001)
            XCTAssertEqual(result.countdown.components.map(\.value), remaining)
            XCTAssertNil(result.countdown.terminalText)
        }
    }

    func testWeekResetsExactlyAtChosenWeekdayMidnight() throws {
        var profile = UserProfile.initial
        profile.weekStartDay = .monday
        let boundary = try date(7)
        let before = TimeProgressCalculator.snapshot(
            for: .week, profile: profile, now: boundary.addingTimeInterval(-1), calendar: calendar
        )
        let atBoundary = TimeProgressCalculator.snapshot(for: .week, profile: profile, now: boundary, calendar: calendar)
        XCTAssertEqual(before.targetDate, boundary)
        XCTAssertGreaterThan(before.elapsedFraction, 0.999)
        XCTAssertEqual(atBoundary.elapsedFraction, 0)
        XCTAssertEqual(atBoundary.targetDate, try date(14))
        XCTAssertEqual(atBoundary.countdown.components.map(\.value), [7, 0])
    }

    func testDeviceSettingRetainsPassedCalendarFirstWeekday() throws {
        let now = try date(9, 12)
        let profile = UserProfile.initial
        XCTAssertEqual(profile.weekStartDay, .system)
        for firstWeekday in [1, 2, 7] {
            var local = calendar
            local.firstWeekday = firstWeekday
            let result = TimeProgressCalculator.dateInterval(for: .week, profile: profile, now: now, calendar: local)
            XCTAssertEqual(result, local.dateInterval(of: .weekOfYear, for: now))
            XCTAssertEqual(profile.weekStartDay.resolvedWeekday(in: local), firstWeekday)
        }
    }

    func testExplicitWeekdayOverridesDeviceSettingWithoutMutatingCalendar() throws {
        var local = calendar
        local.firstWeekday = 7
        var profile = UserProfile.initial
        profile.weekStartDay = .monday
        let result = TimeProgressCalculator.dateInterval(for: .week, profile: profile, now: try date(9, 12), calendar: local)
        XCTAssertEqual(result.start, try date(7))
        XCTAssertEqual(local.firstWeekday, 7)
    }

    func testWeekCrossesYearBoundaryRegardlessOfWeekNumberRules() throws {
        var profile = UserProfile.initial
        profile.weekStartDay = .monday
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2024, month: 12, day: 31, hour: 12)))
        let expectedStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2024, month: 12, day: 30)))
        let expectedEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 1, day: 6)))
        for minimumDays in [1, 4, 7] {
            var local = calendar
            local.minimumDaysInFirstWeek = minimumDays
            let result = TimeProgressCalculator.dateInterval(for: .week, profile: profile, now: now, calendar: local)
            XCTAssertEqual(result.start, expectedStart)
            XCTAssertEqual(result.end, expectedEnd)
        }
    }

    func testWeekUsesCalendarDaysAcrossDaylightSavingChanges() throws {
        var local = calendar
        local.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        var profile = UserProfile.initial
        profile.weekStartDay = .sunday
        for (month, currentDay, firstDay, hours) in [(3, 13, 10, 167), (11, 6, 3, 169)] {
            let now = try XCTUnwrap(local.date(from: DateComponents(year: 2024, month: month, day: currentDay, hour: 12)))
            let result = TimeProgressCalculator.dateInterval(for: .week, profile: profile, now: now, calendar: local)
            XCTAssertEqual(local.component(.day, from: result.start), firstDay)
            XCTAssertEqual(local.component(.day, from: result.end), firstDay + 7)
            XCTAssertEqual(local.component(.hour, from: result.start), 0)
            XCTAssertEqual(local.component(.hour, from: result.end), 0)
            XCTAssertEqual(result.duration, Double(hours * 3_600), accuracy: 0.001)
        }
    }

    func testChosenMidnightFollowsDeviceTimeZone() throws {
        var tokyo = calendar
        tokyo.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        var profile = UserProfile.initial
        profile.weekStartDay = .saturday
        let now = try XCTUnwrap(tokyo.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 1)))
        let result = TimeProgressCalculator.dateInterval(for: .week, profile: profile, now: now, calendar: tokyo)
        XCTAssertEqual(result.start, try date(4, 15))
        XCTAssertEqual(result.end, try date(11, 15))
    }

    func testWidgetTransitionUsesSelectedWeekBoundary() throws {
        var profile = UserProfile.initial
        profile.weekStartDay = .saturday
        let after = try date(11, 23, 59)
        let through = try date(12, 0, 2)
        XCTAssertEqual(TimeProgressCalculator.transitionDates(
            for: .week, profile: profile, after: after, through: through, calendar: calendar
        ), [try date(12)])
        profile.weekStartDay = .monday
        XCTAssertTrue(TimeProgressCalculator.transitionDates(
            for: .week, profile: profile, after: after, through: through, calendar: calendar
        ).isEmpty)
    }

    func testWeekSettingDoesNotChangeOtherMetricPeriods() throws {
        var original = UserProfile.initial
        original.weekStartDay = .sunday
        var changed = original
        changed.weekStartDay = .saturday
        let now = try date(9, 12)
        for metric in MetricKind.allCases where metric != .week {
            XCTAssertEqual(
                TimeProgressCalculator.snapshot(for: metric, profile: original, now: now, calendar: calendar),
                TimeProgressCalculator.snapshot(for: metric, profile: changed, now: now, calendar: calendar)
            )
        }
    }

    func testWeekSettingPersistsAlongsideWorkHoursAndMilestone() throws {
        var profile = UserProfile.initial
        profile.weekStartDay = .saturday
        profile.workStartMinute = 22 * 60
        profile.workEndMinute = 6 * 60
        profile.customTargetName = "Keep existing milestone"
        profile.dashboardMetrics = [.workday, .week, .customLife]
        let decoded = try JSONDecoder().decode(UserProfile.self, from: JSONEncoder().encode(profile))
        XCTAssertEqual(decoded, profile)
    }

    func testLegacyOrInvalidWeekSettingPreservesOtherProfileData() throws {
        var profile = UserProfile.initial
        profile.customTargetName = "Keep existing milestone"
        profile.workStartMinute = 8 * 60 + 30
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any])
        object.removeValue(forKey: "weekStartDay")
        let legacy = try JSONDecoder().decode(UserProfile.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(legacy, profile)
        for invalid in [8, -1, "futureSetting", NSNull()] as [Any] {
            object["weekStartDay"] = invalid
            let decoded = try JSONDecoder().decode(UserProfile.self, from: JSONSerialization.data(withJSONObject: object))
            XCTAssertEqual(decoded, profile)
        }
    }
}
