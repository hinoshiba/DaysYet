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

    private var dailyWorkProfile: UserProfile {
        var profile = UserProfile.initial
        profile.workActivity.activeWeekdays = Set(1...7)
        return profile
    }

    private func snapshot(_ profile: UserProfile? = nil, at now: Date) -> MetricSnapshot {
        TimeProgressCalculator.snapshot(for: .workday, profile: profile ?? dailyWorkProfile, now: now, calendar: calendar)
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
        // An explicitly enabled Saturday still supports the existing daily schedule.
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
        var profile = dailyWorkProfile
        profile.workStartMinute = 10 * 60 + 17
        profile.workEndMinute = 10 * 60 + 19
        let active = snapshot(profile, at: try date(5, 10, 18))
        XCTAssertEqual(active.elapsedFraction, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(active.countdown.components.map(\.value), [0, 1])
        XCTAssertEqual(active.targetDate, try date(5, 10, 19))
    }

    func testOvernightShiftKeepsSameIntervalAcrossMidnight() throws {
        var profile = dailyWorkProfile
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
        var profile = dailyWorkProfile
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
        var profile = dailyWorkProfile
        profile.workStartMinute = 16 * 60
        profile.workEndMinute = 0
        let completed = snapshot(profile, at: try date(6, 0))
        XCTAssertEqual(completed.elapsedFraction, 1)
        XCTAssertEqual(completed.targetDate, try date(6, 0))
    }

    func testEqualClockTimesRepresentContinuousDailyPeriod() throws {
        var profile = dailyWorkProfile
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
        var profile = dailyWorkProfile
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
        var profile = dailyWorkProfile
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
            for: .workday, profile: dailyWorkProfile, after: try date(5, 8), through: try date(6, 10), calendar: calendar
        )
        XCTAssertEqual(transitions, [try date(5, 9), try date(5, 18), try date(6, 0), try date(6, 9)])
        let exactWindow = TimeProgressCalculator.transitionDates(
            for: .workday, profile: dailyWorkProfile, after: try date(5, 9), through: try date(5, 18), calendar: calendar
        )
        XCTAssertEqual(exactWindow, [try date(5, 18)])
    }

    func testOvernightTransitionsIncludePreviousShiftEnd() throws {
        var profile = dailyWorkProfile
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
        var profile = dailyWorkProfile
        profile.workStartMinute = 22 * 60 + 15
        profile.workEndMinute = 6 * 60 + 45
        profile.customTargetName = "Keep milestone"
        profile.dashboardMetrics = [.workday, .customLife, .year]
        let decoded = try JSONDecoder().decode(UserProfile.self, from: JSONEncoder().encode(profile))
        XCTAssertEqual(decoded, profile)
        XCTAssertEqual(decoded.normalizedDashboardMetrics, [.workday, .customLife, .year])
    }

    func testLegacyProfileGainsWorkDefaultsWithoutLosingMilestone() throws {
        var profile = dailyWorkProfile
        profile.customTargetName = "Existing milestone"
        let data = try JSONEncoder().encode(profile)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "dailyActivity")
        object.removeValue(forKey: "workActivity")
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
        object.removeValue(forKey: "dailyActivity")
        object.removeValue(forKey: "workActivity")
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

    func testNewProfilesHaveIndependentDailyAndWeekdayWorkDefaults() throws {
        let profile = UserProfile.initial
        XCTAssertEqual(profile.dailyActivity, ActivitySchedule(startMinute: 420, endMinute: 1_380))
        XCTAssertEqual(profile.workActivity, ActivitySchedule(startMinute: 540, endMinute: 1_080, activeWeekdays: Set(2...6)))
        let saturday = try date(5, 12)
        XCTAssertFalse(TimeProgressCalculator.snapshot(for: .activity, profile: profile, now: saturday, calendar: calendar).isOff)
        XCTAssertTrue(snapshot(profile, at: saturday).isOff)
        XCTAssertFalse(snapshot(profile, at: try date(7, 12)).isOff)
    }

    func testChangingOneScheduleKeepsOtherScheduleAndSelections() throws {
        var profile = UserProfile.initial
        let originalWork = profile.workActivity
        let originalMetrics = profile.dashboardMetrics
        profile.updateActivitySchedule(for: .activity) {
            $0.name = "Family and hobbies"
            $0.startMinute = 8 * 60 + 15
            $0.endMinute = 21 * 60 + 45
            $0.activeWeekdays = [1, 3, 5, 7]
        }
        XCTAssertEqual(profile.workActivity, originalWork)
        XCTAssertEqual(profile.dashboardMetrics, originalMetrics)
        let updatedDaily = profile.dailyActivity
        profile.updateActivitySchedule(for: .workday) {
            $0.name = "Studio"
            $0.startMinute = 10 * 60
            $0.activeWeekdays = [2, 4, 6]
        }
        XCTAssertEqual(profile.dailyActivity, updatedDaily)
        XCTAssertEqual(profile.activitySchedule(for: .activity), updatedDaily)
        XCTAssertEqual(profile.activitySchedule(for: .workday).name, "Studio")
        let beforeInvalidKind = profile
        profile.updateActivitySchedule(for: .month) { $0.name = "Should not apply" }
        XCTAssertEqual(profile, beforeInvalidKind)
    }

    func testScheduleLabelsUseTrimmedCustomNamesAndLocalizedFallbacks() throws {
        var profile = UserProfile.initial
        for kind in MetricKind.activityKinds + [.customLife] {
            for name in ["", "  \n\t"] {
                if kind.isActivity {
                    profile.updateActivitySchedule(for: kind) { $0.name = name }
                } else {
                    profile.customTargetName = name
                }
                XCTAssertEqual(kind.title(profile: profile), kind.title)
            }
            if kind.isActivity {
                profile.updateActivitySchedule(for: kind) { $0.name = "  My own label \n" }
            } else {
                profile.customTargetName = "  My own label \n"
            }
            XCTAssertEqual(kind.title(profile: profile), "My own label")
            XCTAssertEqual(TimeProgressCalculator.snapshot(
                for: kind, profile: profile, now: try date(7, 12), calendar: calendar
            ).title, "My own label")
        }
    }

    func testEachWeekdayCanBeEnabledIndependentlyForEitherSchedule() throws {
        for kind in MetricKind.activityKinds {
            for weekday in 1...7 {
                var profile = UserProfile.initial
                profile.updateActivitySchedule(for: kind) { $0.activeWeekdays = [weekday] }
                for day in 6...12 {
                    let now = try date(day, 12)
                    let value = TimeProgressCalculator.snapshot(for: kind, profile: profile, now: now, calendar: calendar)
                    XCTAssertEqual(value.isOff, calendar.component(.weekday, from: now) != weekday)
                }
            }
        }
    }

    func testOffHasNoCountdownPercentageOrTargetInAnyPresentation() throws {
        let now = try date(5, 12)
        let result = snapshot(.initial, at: now)
        XCTAssertTrue(result.isOff)
        XCTAssertEqual(result.remainingText, "Off")
        XCTAssertEqual(result.percentageText, "Off")
        XCTAssertEqual(result.percentageElapsedText, "Off")
        XCTAssertEqual(result.elapsedFraction, 0)
        XCTAssertEqual(result.targetDate, now)
        XCTAssertTrue(result.countdown.components.isEmpty)
        for style in MetricValueStyle.allCases {
            for compact in [false, true] {
                XCTAssertEqual(result.valueText(style: style, compact: compact), "Off")
                XCTAssertEqual(result.targetDateText(compact: compact), "Off")
            }
            XCTAssertEqual(result.secondarySummary(excluding: style), result.context)
        }
        XCTAssertEqual(result.accessibilitySummary, "\(result.title)。Off。\(result.context)。")
        XCTAssertFalse(result.accessibilitySummary.contains("%"))
    }

    func testAllOffHasNoScheduledTargetOrTransitions() throws {
        for kind in MetricKind.activityKinds {
            var profile = UserProfile.initial
            profile.updateActivitySchedule(for: kind) { $0.activeWeekdays = [] }
            for day in 6...12 {
                let now = try date(day, 12)
                let result = TimeProgressCalculator.snapshot(for: kind, profile: profile, now: now, calendar: calendar)
                XCTAssertTrue(result.isOff)
                XCTAssertEqual(result.context, L10n.text("すべての曜日がOffです", "All weekdays are Off"))
                XCTAssertEqual(result.targetDate, now)
            }
            XCTAssertEqual(TimeProgressCalculator.transitionDates(
                for: kind, profile: profile, after: try date(6, 0), through: try date(20, 0), calendar: calendar
            ), [])
        }
    }

    func testOvernightEnabledStartContinuesIntoOffDayThenTurnsOffAtEnd() throws {
        for kind in MetricKind.activityKinds {
            var profile = UserProfile.initial
            profile.updateActivitySchedule(for: kind) {
                $0.startMinute = 22 * 60
                $0.endMinute = 6 * 60
                $0.activeWeekdays = [7]
            }
            for now in [try date(5, 23), try date(6, 0), try date(6, 5, 59)] {
                let result = TimeProgressCalculator.snapshot(for: kind, profile: profile, now: now, calendar: calendar)
                XCTAssertFalse(result.isOff)
                XCTAssertNil(result.countdown.terminalText)
                XCTAssertEqual(result.targetDate, try date(6, 6))
            }
            for now in [try date(6, 6), try date(6, 22)] {
                XCTAssertTrue(TimeProgressCalculator.snapshot(for: kind, profile: profile, now: now, calendar: calendar).isOff)
            }
            XCTAssertEqual(TimeProgressCalculator.transitionDates(
                for: kind, profile: profile, after: try date(6, 5), through: try date(6, 23), calendar: calendar
            ), [try date(6, 6)])
        }
    }

    func testOvernightStartAfterOffDayShowsNotStartedInsteadOfYesterdayFinished() throws {
        var profile = UserProfile.initial
        profile.workActivity = ActivitySchedule(startMinute: 22 * 60, endMinute: 6 * 60, activeWeekdays: [2])
        for now in [try date(7, 0), try date(7, 12), try date(7, 21, 59)] {
            let result = snapshot(profile, at: now)
            XCTAssertFalse(result.isOff)
            XCTAssertEqual(result.elapsedFraction, 0)
            XCTAssertEqual(result.countdown.terminalText, L10n.text("開始前", "Not started"))
            XCTAssertEqual(result.targetDate, try date(8, 6))
        }
        let start = snapshot(profile, at: try date(7, 22))
        XCTAssertNil(start.countdown.terminalText)
        XCTAssertEqual(start.countdown.components.map(\.value), [8, 0])
    }

    func testFullDayActivityStopsAtEndOnFollowingOffDay() throws {
        var profile = UserProfile.initial
        profile.dailyActivity = ActivitySchedule(startMinute: 9 * 60, endMinute: 9 * 60, activeWeekdays: [7])
        let active = TimeProgressCalculator.snapshot(for: .activity, profile: profile, now: try date(6, 8, 59), calendar: calendar)
        let off = TimeProgressCalculator.snapshot(for: .activity, profile: profile, now: try date(6, 9), calendar: calendar)
        XCTAssertFalse(active.isOff)
        XCTAssertEqual(active.countdown.components.map(\.value), [0, 1])
        XCTAssertTrue(off.isOff)
    }

    func testTransitionsIncludeOffBoundariesWithoutOffDayStartOrEnd() throws {
        XCTAssertEqual(TimeProgressCalculator.transitionDates(
            for: .workday, profile: .initial, after: try date(4, 17), through: try date(7, 10), calendar: calendar
        ), [try date(4, 18), try date(5, 0), try date(6, 0), try date(7, 0), try date(7, 9)])
    }

    func testOvernightOffBoundaryUsesCalendarDaysAcrossDaylightSavingChanges() throws {
        var local = calendar
        local.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        var profile = UserProfile.initial
        profile.dailyActivity = ActivitySchedule(startMinute: 22 * 60, endMinute: 6 * 60, activeWeekdays: [7])
        for (month, day, durationHours) in [(3, 10, 7), (11, 3, 9)] {
            let morning = try XCTUnwrap(local.date(from: DateComponents(year: 2024, month: month, day: day, hour: 4)))
            let end = try XCTUnwrap(local.date(from: DateComponents(year: 2024, month: month, day: day, hour: 6)))
            let active = TimeProgressCalculator.snapshot(for: .activity, profile: profile, now: morning, calendar: local)
            let interval = TimeProgressCalculator.dateInterval(for: .activity, profile: profile, now: morning, calendar: local)
            XCTAssertFalse(active.isOff)
            XCTAssertEqual(interval.duration, Double(durationHours * 3_600), accuracy: 0.001)
            XCTAssertEqual(active.targetDate, end)
            XCTAssertTrue(TimeProgressCalculator.snapshot(for: .activity, profile: profile, now: end, calendar: local).isOff)
            XCTAssertEqual(TimeProgressCalculator.transitionDates(
                for: .activity, profile: profile, after: morning, through: end, calendar: local
            ), [end])
        }
    }

    func testTwoSchedulesPersistCustomLabelsWeekdaysAndSelections() throws {
        var profile = UserProfile.initial
        profile.dailyActivity = ActivitySchedule(name: "Living", startMinute: 450, endMinute: 1_410, activeWeekdays: [1, 4, 7])
        profile.workActivity = ActivitySchedule(name: "Creating", startMinute: 1_320, endMinute: 360, activeWeekdays: [])
        profile.dashboardMetrics = [.activity, .workday, .customLife]
        profile.weekStartDay = .friday
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let result = try decoder.decode(UserProfile.self, from: encoder.encode(profile))
        XCTAssertEqual(result.dailyActivity, profile.dailyActivity)
        XCTAssertEqual(result.workActivity, profile.workActivity)
        XCTAssertEqual(result.normalizedDashboardMetrics, profile.dashboardMetrics)
        XCTAssertEqual(result.weekStartDay, .friday)
    }

    func testLegacyWorkProfileKeepsClockValuesWeekendBehaviorAndWidgetIdentity() throws {
        var profile = dailyWorkProfile
        profile.workStartMinute = 21 * 60 + 17
        profile.workEndMinute = 5 * 60 + 43
        profile.dashboardMetrics = [.workday, .year, .customLife]
        profile.customTargetName = "Preserved milestone"
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any])
        object.removeValue(forKey: "dailyActivity")
        object.removeValue(forKey: "workActivity")
        let migrated = try JSONDecoder().decode(UserProfile.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(migrated, profile)
        XCTAssertEqual(migrated.workActivity.activeWeekdays, Set(1...7))
        XCTAssertFalse(snapshot(migrated, at: try date(5, 23)).isOff)
        XCTAssertEqual(try JSONDecoder().decode(UserProfile.self, from: JSONEncoder().encode(migrated)), migrated)
        XCTAssertEqual(WidgetMetricOption(rawValue: "workday")?.metricKind, .workday)
        XCTAssertEqual(LockScreenMetricOption(rawValue: "workday")?.resolved(profile: migrated), .workday)
    }

    func testMalformedSchedulesPreserveValidFieldsAndOtherSettings() throws {
        var profile = UserProfile.initial
        profile.customTargetName = "Preserved"
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any])
        object["dailyActivity"] = ["name": "Daily label", "startMinute": -3, "endMinute": 2_000, "activeWeekdays": [0, 1, 3, 8]]
        object["workActivity"] = ["name": 12, "startMinute": "bad", "endMinute": 1_001, "activeWeekdays": []] as [String: Any]
        object["dashboardMetrics"] = ["activity", "futureMetric", "workday", "year"]
        object["dashboardValueStyle"] = "futureStyle"
        let decoded = try JSONDecoder().decode(UserProfile.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.dailyActivity, ActivitySchedule(name: "Daily label", startMinute: 0, endMinute: 1_439, activeWeekdays: [1, 3]))
        XCTAssertEqual(decoded.workActivity, ActivitySchedule(startMinute: 540, endMinute: 1_001, activeWeekdays: []))
        XCTAssertEqual(decoded.customTargetName, profile.customTargetName)
        XCTAssertEqual(decoded.normalizedDashboardMetrics, [.activity, .workday, .year])
        XCTAssertEqual(decoded.dashboardValueStyle, .remaining)
        object["dailyActivity"] = "invalid"
        object["workActivity"] = NSNull()
        let defaults = try JSONDecoder().decode(UserProfile.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(defaults.dailyActivity, .daily)
        XCTAssertEqual(defaults.workActivity.startMinute, profile.workStartMinute)
        XCTAssertEqual(defaults.customTargetName, profile.customTargetName)
    }

    func testBothActivitiesAvailableForWidgetsWithoutPersonalSetup() {
        XCTAssertEqual(MetricKind.activityKinds, [.activity, .workday])
        for kind in MetricKind.activityKinds {
            XCTAssertTrue(kind.isActivity)
            let option = WidgetMetricOption(rawValue: kind.rawValue)
            let lockOption = LockScreenMetricOption(rawValue: kind.rawValue)
            XCTAssertEqual(option?.metricKind, kind)
            XCTAssertEqual(lockOption?.resolved(profile: .initial), kind)
            XCTAssertNotNil(option.flatMap { WidgetMetricOption.caseDisplayRepresentations[$0] })
            XCTAssertNotNil(lockOption.flatMap { LockScreenMetricOption.caseDisplayRepresentations[$0] })
        }
        XCTAssertEqual(Set(WidgetMetricOption.allCases.map(\.metricKind)), Set(MetricKind.allCases))
    }
}
