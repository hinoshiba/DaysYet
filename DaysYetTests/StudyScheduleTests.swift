import XCTest
#if os(macOS)
@testable import DaysYetMac
#else
@testable import DaysYet
#endif

final class StudyScheduleTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ day: Int, month: Int = 9, year: Int = 2026, hour: Int = 0,
                      in calendar: Calendar? = nil) throws -> Date {
        try XCTUnwrap((calendar ?? self.calendar).date(from: DateComponents(
            year: year, month: month, day: day, hour: hour
        )))
    }

    private func schedule(weekdays: Set<Int> = [2, 4, 6]) throws -> StudySchedule {
        StudySchedule(startDate: try date(7), endDate: try date(20),
                      activeWeekdays: weekdays, calendar: calendar)
    }

    func testWeekdaysAndCalendarOverridesSelectExactlyTheRequestedDays() throws {
        var schedule = try schedule()
        XCTAssertEqual(schedule.selectedDates(calendar: calendar).map {
            calendar.component(.day, from: $0)
        }, [7, 9, 11, 14, 16, 18])

        schedule.toggleDate(try date(9), calendar: calendar)
        schedule.toggleDate(try date(12), calendar: calendar)
        XCTAssertEqual(schedule.excludedDays, ["2026-09-09"])
        XCTAssertEqual(schedule.addedDays, ["2026-09-12"])
        XCTAssertFalse(schedule.isSelected(try date(9, hour: 12), calendar: calendar))
        XCTAssertTrue(schedule.isSelected(try date(12, hour: 23), calendar: calendar))
        XCTAssertEqual(schedule.selectedDates(calendar: calendar).map {
            calendar.component(.day, from: $0)
        }, [7, 11, 12, 14, 16, 18])

        schedule.toggleDate(try date(9), calendar: calendar)
        schedule.toggleDate(try date(12), calendar: calendar)
        XCTAssertTrue(schedule.excludedDays.isEmpty)
        XCTAssertTrue(schedule.addedDays.isEmpty)
        let original = schedule
        schedule.toggleDate(try date(21), calendar: calendar)
        XCTAssertEqual(schedule, original)
    }

    func testCalendarOnlySelectionWorksWithoutAnyWeekdays() throws {
        var schedule = try schedule(weekdays: [])
        schedule.toggleDate(try date(7), calendar: calendar)
        schedule.toggleDate(try date(20), calendar: calendar)
        XCTAssertEqual(schedule.selectedDates(calendar: calendar), [try date(7), try date(20)])
        XCTAssertFalse(schedule.isSelected(try date(6), calendar: calendar))
        XCTAssertFalse(schedule.isSelected(try date(21), calendar: calendar))
    }

    func testRemainingDaysIncludeTodayAndProgressCountsOnlyElapsedSelectedDays() throws {
        var profile = UserProfile.initial
        profile.studySchedule = try schedule()
        for hour in [0, 12, 23] {
            let snapshot = TimeProgressCalculator.snapshot(
                for: .study, profile: profile, now: try date(9, hour: hour), calendar: calendar
            )
            XCTAssertEqual(snapshot.countdown.components.map(\.value), [5])
            XCTAssertEqual(snapshot.elapsedFraction, 1.0 / 6, accuracy: 0.000_001)
            XCTAssertNil(snapshot.countdown.terminalText)
            XCTAssertEqual(snapshot.targetDate, try date(20))
        }
        let restDay = TimeProgressCalculator.snapshot(
            for: .study, profile: profile, now: try date(10, hour: 12), calendar: calendar
        )
        XCTAssertEqual(restDay.countdown.components.map(\.value), [4])
        XCTAssertEqual(restDay.elapsedFraction, 2.0 / 6, accuracy: 0.000_001)
        XCTAssertFalse(restDay.isOff)
    }

    func testBeforeStartAndAfterLastSelectedDayHaveFiniteExplicitStates() throws {
        var profile = UserProfile.initial
        profile.studySchedule = try schedule()
        let before = TimeProgressCalculator.snapshot(
            for: .study, profile: profile, now: try date(6), calendar: calendar
        )
        XCTAssertEqual(before.countdown.components.map(\.value), [6])
        XCTAssertEqual(before.elapsedFraction, 0)
        let after = TimeProgressCalculator.snapshot(
            for: .study, profile: profile, now: try date(19), calendar: calendar
        )
        XCTAssertEqual(after.elapsedFraction, 1)
        XCTAssertNotNil(after.countdown.terminalText)
        XCTAssertEqual(after.valueText(style: .remaining, compact: true), after.countdown.terminalText)
        XCTAssertFalse(after.remainingText.contains("-"))
    }

    func testEmptySelectionHasAnExplicitStateAndNoDivisionByZero() throws {
        var profile = UserProfile.initial
        profile.studySchedule = try schedule(weekdays: [])
        let snapshot = TimeProgressCalculator.snapshot(
            for: .study, profile: profile, now: try date(9), calendar: calendar
        )
        XCTAssertEqual(snapshot.elapsedFraction, 0)
        XCTAssertTrue(snapshot.elapsedFraction.isFinite)
        XCTAssertTrue(snapshot.countdown.components.isEmpty)
        XCTAssertNotNil(snapshot.countdown.terminalText)
        XCTAssertEqual(snapshot.valueText(style: .remaining, compact: true), snapshot.countdown.terminalText)
    }

    func testInclusiveLastDayRemainsUntilItsLocalMidnight() throws {
        var profile = UserProfile.initial
        profile.studySchedule = StudySchedule(
            startDate: try date(7), endDate: try date(7), activeWeekdays: Set(1...7), calendar: calendar
        )
        let during = TimeProgressCalculator.snapshot(
            for: .study, profile: profile, now: try date(7, hour: 23), calendar: calendar
        )
        XCTAssertEqual(during.countdown.components.map(\.value), [1])
        XCTAssertEqual(during.elapsedFraction, 0)
        let after = TimeProgressCalculator.snapshot(
            for: .study, profile: profile, now: try date(8), calendar: calendar
        )
        XCTAssertEqual(after.elapsedFraction, 1)
        XCTAssertNotNil(after.countdown.terminalText)
        let interval = TimeProgressCalculator.dateInterval(
            for: .study, profile: profile, now: try date(7), calendar: calendar
        )
        XCTAssertEqual(interval.start, try date(7))
        XCTAssertEqual(interval.end, try date(8))
    }

    func testDayCountsAndWidgetMidnightTransitionsSurviveBothDSTChanges() throws {
        var local = calendar
        local.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        for (month, firstDay, lastDay, hours) in [(3, 9, 11, 23.0), (11, 2, 4, 25.0)] {
            var profile = UserProfile.initial
            profile.studySchedule = StudySchedule(
                startDate: try date(firstDay, month: month, year: 2024, in: local),
                endDate: try date(lastDay, month: month, year: 2024, in: local),
                activeWeekdays: Set(1...7), calendar: local
            )
            let changeDay = try date(firstDay + 1, month: month, year: 2024, in: local)
            let nextDay = try date(lastDay, month: month, year: 2024, in: local)
            XCTAssertEqual(nextDay.timeIntervalSince(changeDay), hours * 3_600)
            XCTAssertEqual(profile.studySchedule.selectedDates(calendar: local).count, 3)
            let snapshot = TimeProgressCalculator.snapshot(
                for: .study, profile: profile, now: changeDay.addingTimeInterval(12 * 3_600), calendar: local
            )
            XCTAssertEqual(snapshot.countdown.components.map(\.value), [2])
            XCTAssertEqual(snapshot.elapsedFraction, 1.0 / 3, accuracy: 0.000_001)
            XCTAssertEqual(TimeProgressCalculator.transitionDates(
                for: .study, profile: profile, after: changeDay.addingTimeInterval(-1),
                through: nextDay, calendar: local
            ), [changeDay, nextDay])
        }
    }

    func testSkippedMidnightDoesNotCarryOneAMIntoFollowingStudyDays() throws {
        var local = calendar
        local.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Santiago"))
        let firstDay = try date(5, in: local)
        let skippedMidnight = try date(6, in: local)
        let lastDay = try date(7, in: local)
        var profile = UserProfile.initial
        profile.studySchedule = StudySchedule(
            startDate: firstDay, endDate: lastDay,
            activeWeekdays: Set(1...7), calendar: local
        )

        XCTAssertEqual(local.component(.hour, from: skippedMidnight), 1)
        XCTAssertEqual(profile.studySchedule.selectedDates(calendar: local), [firstDay, skippedMidnight, lastDay])
        let boundaries = TimeProgressCalculator.transitionDates(
            for: .study, profile: profile, after: firstDay,
            through: lastDay, calendar: local
        )
        XCTAssertEqual(boundaries, [skippedMidnight, lastDay])
        XCTAssertEqual(local.component(.hour, from: try XCTUnwrap(boundaries.last)), 0)
        let snapshot = TimeProgressCalculator.snapshot(
            for: .study, profile: profile, now: lastDay, calendar: local
        )
        XCTAssertEqual(snapshot.countdown.components.map(\.value), [1])
        XCTAssertEqual(snapshot.elapsedFraction, 2.0 / 3, accuracy: 0.000_001)

        profile.studySchedule = StudySchedule(
            startDate: firstDay, endDate: skippedMidnight,
            activeWeekdays: Set(1...7), calendar: local
        )
        let interval = TimeProgressCalculator.dateInterval(
            for: .study, profile: profile, now: firstDay, calendar: local
        )
        XCTAssertEqual(interval.end, lastDay)
        XCTAssertEqual(TimeProgressCalculator.transitionDates(
            for: .study, profile: profile, after: firstDay,
            through: lastDay.addingTimeInterval(3_600), calendar: local
        ), [skippedMidnight, lastDay])
    }

    func testCivilDatesAndExceptionsSurviveTravelAndNonGregorianDeviceCalendars() throws {
        var tokyo = calendar
        tokyo.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        var losAngeles = Calendar(identifier: .buddhist)
        losAngeles.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        var schedule = StudySchedule(
            startDate: try date(7, in: tokyo), endDate: try date(20, in: tokyo),
            activeWeekdays: [2, 4, 6], calendar: tokyo
        )
        schedule.toggleDate(try date(9, in: tokyo), calendar: tokyo)
        schedule.toggleDate(try date(12, in: tokyo), calendar: tokyo)
        let decoded = try JSONDecoder().decode(StudySchedule.self, from: JSONEncoder().encode(schedule))
        XCTAssertEqual(decoded, schedule)
        let keys = decoded.selectedDates(calendar: losAngeles).map {
            StudySchedule.dayKey($0, calendar: losAngeles)
        }
        XCTAssertEqual(keys, ["2026-09-07", "2026-09-11", "2026-09-12", "2026-09-14", "2026-09-16", "2026-09-18"])
        XCTAssertEqual(StudySchedule.dayKey(decoded.endDate(in: losAngeles), calendar: losAngeles), "2026-09-20")
    }

    func testLeapDayAndMaximumRangeStayBounded() throws {
        let leap = StudySchedule(
            startDate: try date(28, month: 2, year: 2024), endDate: try date(1, month: 3, year: 2024),
            activeWeekdays: Set(1...7), calendar: calendar
        )
        XCTAssertEqual(leap.selectedDates(calendar: calendar).count, 3)
        let long = StudySchedule(
            startDate: try date(1, month: 1, year: 2024), endDate: try date(1, month: 1, year: 2099),
            activeWeekdays: Set(1...7), calendar: calendar
        )
        XCTAssertEqual(long.selectedDates(calendar: calendar).count, StudySchedule.maximumDayCount)
        XCTAssertEqual(long.endDate(in: calendar), try date(31, month: 12, year: 2024))
        let reversed = StudySchedule(startDate: try date(20), endDate: try date(7), calendar: calendar)
        XCTAssertEqual(reversed.startDate(in: calendar), reversed.endDate(in: calendar))
    }

    func testMalformedPayloadDropsInvalidDaysAndClampsItsRange() throws {
        let data = Data("""
        {"name":"Keep me","startDate":"2024-01-01","endDate":"9999-12-31",
         "activeWeekdays":[0,2,9],"addedDays":["2024-02-30","2024-01-06","2024-01-07","2025-01-06"],
         "excludedDays":["2024-01-07","bogus"]}
        """.utf8)
        let schedule = try JSONDecoder().decode(StudySchedule.self, from: data)
        XCTAssertEqual(schedule.name, "Keep me")
        XCTAssertEqual(schedule.activeWeekdays, [2])
        XCTAssertEqual(schedule.addedDays, ["2024-01-06"])
        XCTAssertEqual(schedule.excludedDays, ["2024-01-07"])
        XCTAssertEqual(schedule.endDate(in: calendar), try date(31, month: 12, year: 2024))
        XCTAssertLessThanOrEqual(schedule.selectedDates(calendar: calendar).count, StudySchedule.maximumDayCount)
        let invalid = try JSONDecoder().decode(StudySchedule.self, from: Data("""
        {"startDate":"2024-02-30","endDate":"x","activeWeekdays":null}
        """.utf8))
        XCTAssertTrue(invalid.startDate.timeIntervalSince1970.isFinite)
        XCTAssertEqual(invalid.startDate(in: calendar), invalid.endDate(in: calendar))
    }

    func testNonFiniteOrExtremeDatesDoNotEnterCalendarCalculations() {
        for seconds in [Double.infinity, -Double.infinity, Double.nan, Double.greatestFiniteMagnitude] {
            let invalid = Date(timeIntervalSinceReferenceDate: seconds)
            let schedule = StudySchedule(startDate: invalid, endDate: invalid, calendar: calendar)
            XCTAssertEqual(StudySchedule.dayKey(schedule.startDate(in: calendar), calendar: calendar), "2001-01-01")
            XCTAssertFalse(schedule.isSelected(invalid, calendar: calendar))
        }
    }

    func testOlderProfilesKeepTheirMetricsAndStudyProfileRoundTrips() throws {
        var profile = UserProfile.initial
        // Whole-second fixtures avoid floating-point rounding of Date.now
        // when the profile's milliseconds-since-1970 JSON format round-trips.
        profile.birthDate = try date(1, month: 1, year: 1990)
        profile.customTargetStartDate = try date(7)
        profile.customTargetDate = try date(20, year: 2029)
        profile.studySchedule = try schedule()
        profile.customTargetName = "Keep the milestone"
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(profile)) as? [String: Any])
        object.removeValue(forKey: "studySchedule")
        let migrated = try decoder.decode(UserProfile.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(migrated.dashboardMetrics, [.week, .month, .year])
        XCTAssertEqual(migrated.customTargetName, profile.customTargetName)
        XCTAssertEqual(migrated.customTargetStartDate, profile.customTargetStartDate)
        XCTAssertEqual(migrated.customTargetDate, profile.customTargetDate)
        XCTAssertFalse(migrated.dashboardMetrics.contains(.study))
        XCTAssertTrue(migrated.studySchedule.selectedDates(calendar: calendar).isEmpty)
        let unconfigured = TimeProgressCalculator.snapshot(
            for: .study, profile: migrated, now: try date(9), calendar: calendar
        )
        XCTAssertEqual(unconfigured.countdown.terminalText, L10n.text("学習日を選択", "Select study days"))
        XCTAssertTrue(unconfigured.countdown.components.isEmpty)

        profile.studySchedule.name = "Exam prep"
        profile.studySchedule.toggleDate(try date(12), calendar: calendar)
        profile.dashboardMetrics = [.study, .week, .month]
        let roundTrip = try decoder.decode(UserProfile.self, from: encoder.encode(profile))
        XCTAssertEqual(roundTrip, profile)
        XCTAssertEqual(MetricKind.study.title(profile: roundTrip), "Exam prep")
    }

    func testStudyIsAvailableInBothWidgetPickers() {
        XCTAssertEqual(WidgetMetricOption.study.metricKind, .study)
        XCTAssertEqual(LockScreenMetricOption.study.resolved(profile: .initial), .study)
        XCTAssertNotNil(WidgetMetricOption.caseDisplayRepresentations[.study])
        XCTAssertNotNil(LockScreenMetricOption.caseDisplayRepresentations[.study])
    }
}
