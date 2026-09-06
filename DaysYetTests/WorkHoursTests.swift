import XCTest
#if os(macOS)
@testable import DaysYetMac
#else
@testable import DaysYet
#endif

final class WorkHoursTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute)))
    }

    private func snapshot(_ profile: UserProfile = .initial, at now: Date) -> MetricSnapshot {
        TimeProgressCalculator.snapshot(for: .workday, profile: profile, now: now, calendar: calendar)
    }

    func testDayShiftBeforeStartHasNoMisleadingCountdownToEnd() throws {
        let before = snapshot(at: try date(5, 8, 59))
        XCTAssertEqual(before.elapsedFraction, 0)
        XCTAssertNotNil(before.countdown.terminalText)
        XCTAssertTrue(before.countdown.components.isEmpty)
        XCTAssertEqual(before.valueText(style: .remaining, compact: true), before.countdown.terminalText)
        XCTAssertEqual(before.targetDate, try date(5, 18))
    }

    func testDayShiftStartsAtExactMinuteAndCountsDownOnWeekend() throws {
        // September 5 is a Saturday: the schedule intentionally repeats daily.
        let start = snapshot(at: try date(5, 9))
        XCTAssertEqual(start.elapsedFraction, 0)
        XCTAssertNil(start.countdown.terminalText)
        XCTAssertEqual(start.countdown.components.map(\.value), [9, 0])

        let midpoint = snapshot(at: try date(5, 13, 30))
        XCTAssertEqual(midpoint.elapsedFraction, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(midpoint.countdown.components.map(\.value), [4, 30])
    }

    func testDayShiftEndsAtExactMinuteAndResetsOnNextDate() throws {
        let atEnd = snapshot(at: try date(5, 18))
        let afterEnd = snapshot(at: try date(5, 23, 59))
        let nextDay = snapshot(at: try date(6, 0))

        XCTAssertEqual(atEnd.elapsedFraction, 1)
        XCTAssertNotNil(atEnd.countdown.terminalText)
        XCTAssertEqual(afterEnd.countdown.terminalText, atEnd.countdown.terminalText)
        XCTAssertEqual(afterEnd.elapsedFraction, 1)
        XCTAssertEqual(nextDay.elapsedFraction, 0)
        XCTAssertNotEqual(nextDay.countdown.terminalText, atEnd.countdown.terminalText)
        XCTAssertEqual(nextDay.targetDate, try date(6, 18))
    }

    func testArbitraryMinutePrecisionAndShortShift() throws {
        var profile = UserProfile.initial
        profile.workStartMinute = 10 * 60 + 17
        profile.workEndMinute = 10 * 60 + 19
        let active = snapshot(profile, at: try date(5, 10, 18))
        XCTAssertEqual(active.elapsedFraction, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(active.countdown.components.map(\.value), [0, 1])
        XCTAssertEqual(active.targetDate, try date(5, 10, 19))
    }

    func testOvernightShiftKeepsSameIntervalAcrossMidnight() throws {
        var profile = UserProfile.initial
        profile.workStartMinute = 22 * 60
        profile.workEndMinute = 6 * 60
        let evening = snapshot(profile, at: try date(5, 23))
        let morning = snapshot(profile, at: try date(6, 2))

        XCTAssertEqual(evening.targetDate, try date(6, 6))
        XCTAssertEqual(morning.targetDate, evening.targetDate)
        XCTAssertEqual(evening.elapsedFraction, 1.0 / 8.0, accuracy: 0.000_001)
        XCTAssertEqual(morning.elapsedFraction, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(morning.countdown.components.map(\.value), [4, 0])
    }

    func testOvernightShiftStaysCompleteUntilNextStart() throws {
        var profile = UserProfile.initial
        profile.workStartMinute = 22 * 60
        profile.workEndMinute = 6 * 60
        for now in [try date(6, 6), try date(6, 21, 59)] {
            let completed = snapshot(profile, at: now)
            XCTAssertEqual(completed.elapsedFraction, 1)
            XCTAssertNotNil(completed.countdown.terminalText)
            XCTAssertEqual(completed.targetDate, try date(6, 6))
        }
        let nextStart = snapshot(profile, at: try date(6, 22))
        XCTAssertEqual(nextStart.elapsedFraction, 0)
        XCTAssertNil(nextStart.countdown.terminalText)
        XCTAssertEqual(nextStart.targetDate, try date(7, 6))
    }

    func testMidnightEndCompletesPreviousShiftInsteadOfJumpingAhead() throws {
        var profile = UserProfile.initial
        profile.workStartMinute = 16 * 60
        profile.workEndMinute = 0
        let completed = snapshot(profile, at: try date(6, 0))
        XCTAssertEqual(completed.elapsedFraction, 1)
        XCTAssertEqual(completed.targetDate, try date(6, 0))
    }

    func testEqualClockTimesRepresentContinuousDailyPeriod() throws {
        var profile = UserProfile.initial
        profile.workStartMinute = 9 * 60
        profile.workEndMinute = 9 * 60
        let beforeReset = snapshot(profile, at: try date(6, 8, 59))
        let atReset = snapshot(profile, at: try date(6, 9))
        XCTAssertNil(beforeReset.countdown.terminalText)
        XCTAssertEqual(beforeReset.countdown.components.map(\.value), [0, 1])
        XCTAssertEqual(beforeReset.targetDate, try date(6, 9))
        XCTAssertEqual(atReset.elapsedFraction, 0)
        XCTAssertNil(atReset.countdown.terminalText)
        XCTAssertEqual(atReset.countdown.components.map(\.value), [24, 0])
        XCTAssertEqual(atReset.targetDate, try date(7, 9))
    }

    func testDaylightSavingShiftUsesLocalClockAndActualElapsedDuration() throws {
        var local = calendar
        local.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        var profile = UserProfile.initial
        profile.workStartMinute = 22 * 60
        profile.workEndMinute = 6 * 60
        for (month, day, durationHours) in [(3, 10, 7), (11, 3, 9)] {
            let now = try XCTUnwrap(local.date(from: DateComponents(year: 2024, month: month, day: day, hour: 4)))
            let interval = TimeProgressCalculator.dateInterval(for: .workday, profile: profile, now: now, calendar: local)
            XCTAssertEqual(local.component(.hour, from: interval.start), 22)
            XCTAssertEqual(local.component(.hour, from: interval.end), 6)
            XCTAssertEqual(interval.duration, Double(durationHours * 3_600), accuracy: 0.001)
        }
    }

    func testSkippedDSTClockIntervalIsFiniteAndComplete() throws {
        var local = calendar
        local.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        var profile = UserProfile.initial
        profile.workStartMinute = 2 * 60 + 30
        profile.workEndMinute = 3 * 60
        let now = try XCTUnwrap(local.date(from: DateComponents(year: 2024, month: 3, day: 10, hour: 3)))
        let result = TimeProgressCalculator.snapshot(for: .workday, profile: profile, now: now, calendar: local)
        XCTAssertTrue(result.elapsedFraction.isFinite)
        XCTAssertEqual(result.elapsedFraction, 1)
        XCTAssertNotNil(result.countdown.terminalText)
    }

    func testTransitionDatesIncludeStartEndAndNextMidnight() throws {
        let transitions = TimeProgressCalculator.transitionDates(
            for: .workday, profile: .initial, after: try date(5, 8), through: try date(6, 10), calendar: calendar
        )
        XCTAssertEqual(transitions, [try date(5, 9), try date(5, 18), try date(6, 0), try date(6, 9)])
        let exactWindow = TimeProgressCalculator.transitionDates(
            for: .workday, profile: .initial, after: try date(5, 9), through: try date(5, 18), calendar: calendar
        )
        XCTAssertEqual(exactWindow, [try date(5, 18)])
    }

    func testOvernightTransitionsIncludePreviousShiftEnd() throws {
        var profile = UserProfile.initial
        profile.workStartMinute = 22 * 60
        profile.workEndMinute = 6 * 60
        XCTAssertEqual(TimeProgressCalculator.transitionDates(
            for: .workday, profile: profile, after: try date(6, 5), through: try date(6, 7), calendar: calendar
        ), [try date(6, 6)])
        XCTAssertEqual(TimeProgressCalculator.transitionDates(
            for: .workday, profile: profile, after: try date(6, 21), through: try date(7, 0), calendar: calendar
        ), [try date(6, 22), try date(7, 0)])
    }

    func testWorkSettingsRoundTripWithoutChangingOtherSelections() throws {
        var profile = UserProfile.initial
        profile.workStartMinute = 22 * 60 + 15
        profile.workEndMinute = 6 * 60 + 45
        profile.customTargetName = "Keep milestone"
        profile.dashboardMetrics = [.workday, .customLife, .year]
        let decoded = try JSONDecoder().decode(UserProfile.self, from: JSONEncoder().encode(profile))
        XCTAssertEqual(decoded, profile)
        XCTAssertEqual(decoded.normalizedDashboardMetrics, [.workday, .customLife, .year])
    }

    func testLegacyProfileGainsWorkDefaultsWithoutLosingMilestone() throws {
        var profile = UserProfile.initial
        profile.customTargetName = "Existing milestone"
        let data = try JSONEncoder().encode(profile)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "workStartMinute")
        object.removeValue(forKey: "workEndMinute")
        let decoded = try JSONDecoder().decode(UserProfile.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded, profile)
        XCTAssertEqual(decoded.workStartMinute, 540)
        XCTAssertEqual(decoded.workEndMinute, 1_080)
        XCTAssertEqual(decoded.dashboardMetrics, [.week, .month, .year])
    }

    func testInvalidSavedClockMinutesDoNotDiscardProfile() throws {
        var profile = UserProfile.initial
        profile.customTargetName = "Preserve me"
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any])
        object["workStartMinute"] = -3
        object["workEndMinute"] = 2_000
        let clamped = try JSONDecoder().decode(UserProfile.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(clamped.workStartMinute, 0)
        XCTAssertEqual(clamped.workEndMinute, 1_439)
        XCTAssertEqual(clamped.customTargetName, profile.customTargetName)
        object["workStartMinute"] = "invalid"
        object["workEndMinute"] = NSNull()
        let defaults = try JSONDecoder().decode(UserProfile.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(defaults.workStartMinute, 540)
        XCTAssertEqual(defaults.workEndMinute, 1_080)
        XCTAssertEqual(defaults.customTargetName, profile.customTargetName)
    }

    func testWorkMetricAvailableWithoutPersonalTargetSetup() {
        XCTAssertEqual(WidgetMetricOption.workday.metricKind, .workday)
        XCTAssertEqual(LockScreenMetricOption.workday.resolved(profile: .initial), .workday)
        var profile = UserProfile.initial
        profile.dashboardMetrics = [.workday, .week, .month]
        XCTAssertEqual(LockScreenMetricOption.appSelection.resolved(profile: profile), .workday)
    }
}
