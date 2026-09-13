import XCTest
#if os(macOS)
@testable import DaysYetMac
#else
@testable import DaysYet
#endif

final class TimeProgressCalculatorTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    func testMonthUsesExclusiveStartOfNextMonth() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2024, month: 2, day: 15, hour: 12)))
        let interval = TimeProgressCalculator.dateInterval(
            for: .month,
            profile: .initial,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(calendar.component(.day, from: interval.end), 1)
        XCTAssertEqual(calendar.component(.month, from: interval.end), 3)
        XCTAssertEqual(interval.duration, 29 * 24 * 60 * 60, accuracy: 0.5)
    }

    func testYearHasHalfRemainingAtLeapYearMidpoint() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2024, month: 7, day: 2)))
        let snapshot = TimeProgressCalculator.snapshot(
            for: .year,
            profile: .initial,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.elapsedFraction, 0.5, accuracy: 0.002)
        XCTAssertEqual(snapshot.remainingFraction, 0.5, accuracy: 0.002)
    }

    func testPastHealthyTargetClampsRemainingFractionToZero() throws {
        var profile = UserProfile.initial
        profile.birthDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 1900, month: 1, day: 1)))
        profile.healthyLifeYears = 50
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 15)))

        let snapshot = TimeProgressCalculator.snapshot(
            for: .healthyLife,
            profile: profile,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.elapsedFraction, 1)
        XCTAssertEqual(snapshot.remainingFraction, 0)
        XCTAssertEqual(snapshot.percentageText, "0.0%")
        XCTAssertFalse(snapshot.remainingText.contains("-"))
    }

    func testHealthyTargetHasNothingRemainingAtConfiguredAge() throws {
        var profile = UserProfile.initial
        profile.birthDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 1950, month: 1, day: 1)))
        profile.healthyLifeYears = 75
        let target = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 1, day: 1)))

        let snapshot = TimeProgressCalculator.snapshot(
            for: .healthyLife,
            profile: profile,
            now: target,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.elapsedFraction, 1)
        XCTAssertEqual(snapshot.remainingFraction, 0)
        XCTAssertEqual(snapshot.percentageText, "0.0%")
    }

    func testHealthyTargetCountsDownFromFullAtBirth() throws {
        var profile = UserProfile.initial
        let birthDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2000, month: 1, day: 1)))
        profile.birthDate = birthDate
        profile.healthyLifeYears = 80
        let interval = TimeProgressCalculator.dateInterval(
            for: .healthyLife, profile: profile, now: birthDate, calendar: calendar
        )

        for (now, expected, percentage) in [
            (birthDate.addingTimeInterval(-1), 1.0, "100.0%"),
            (birthDate, 1.0, "100.0%"),
            (birthDate.addingTimeInterval(interval.duration * 0.25), 0.75, "75.0%"),
            (interval.end, 0.0, "0.0%"),
            (interval.end.addingTimeInterval(1), 0.0, "0.0%")
        ] {
            let snapshot = TimeProgressCalculator.snapshot(
                for: .healthyLife, profile: profile, now: now, calendar: calendar
            )
            XCTAssertEqual(snapshot.remainingFraction, expected, accuracy: 0.000_001)
            XCTAssertEqual(snapshot.percentageText, percentage)
        }
    }

    func testCalendarPeriodsCountDownAndRefillAtTheirNextBoundary() throws {
        var profile = UserProfile.initial
        profile.weekStartDay = .monday
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 9)))

        for kind in [MetricKind.week, .month, .year] {
            let interval = TimeProgressCalculator.dateInterval(
                for: kind, profile: profile, now: now, calendar: calendar
            )
            let start = TimeProgressCalculator.snapshot(
                for: kind, profile: profile, now: interval.start, calendar: calendar
            )
            let quarterElapsed = TimeProgressCalculator.snapshot(
                for: kind, profile: profile,
                now: interval.start.addingTimeInterval(interval.duration * 0.25), calendar: calendar
            )
            let beforeEnd = TimeProgressCalculator.snapshot(
                for: kind, profile: profile, now: interval.end.addingTimeInterval(-1), calendar: calendar
            )
            let nextPeriod = TimeProgressCalculator.snapshot(
                for: kind, profile: profile, now: interval.end, calendar: calendar
            )

            XCTAssertEqual(start.remainingFraction, 1, kind.rawValue)
            XCTAssertEqual(start.percentageText, "100.0%", kind.rawValue)
            XCTAssertEqual(quarterElapsed.remainingFraction, 0.75, accuracy: 0.000_001, kind.rawValue)
            XCTAssertEqual(quarterElapsed.percentageText, "75.0%", kind.rawValue)
            XCTAssertGreaterThan(beforeEnd.remainingFraction, 0, kind.rawValue)
            XCTAssertLessThan(beforeEnd.remainingFraction, 0.001, kind.rawValue)
            XCTAssertEqual(beforeEnd.targetDate, interval.end, kind.rawValue)
            XCTAssertEqual(nextPeriod.remainingFraction, 1, kind.rawValue)
            XCTAssertEqual(nextPeriod.percentageText, "100.0%", kind.rawValue)
            XCTAssertGreaterThan(nextPeriod.targetDate, interval.end, kind.rawValue)
        }
    }

    func testDashboardAlwaysReturnsThreeUniqueMetrics() {
        var profile = UserProfile.initial
        profile.dashboardMetrics = [.month, .month]

        XCTAssertEqual(profile.normalizedDashboardMetrics.count, 3)
        XCTAssertEqual(Set(profile.normalizedDashboardMetrics).count, 3)
        XCTAssertEqual(profile.normalizedDashboardMetrics.first, .month)
    }

    func testUnconfiguredProfileDoesNotAssumeALifeTarget() {
        let profile = UserProfile.initial

        XCTAssertFalse(profile.isConfigured)
        XCTAssertEqual(profile.normalizedDashboardMetrics, [.week, .month, .year])
        XCTAssertLessThan(profile.customTargetStartDate, profile.customTargetDate)
        XCTAssertEqual(profile.widgetDisplayMode, .progressBars)
        XCTAssertEqual(profile.dashboardValueStyle, .remaining)
        XCTAssertEqual(profile.widgetTheme, .vividNight)
    }

    func testLegacyProfileWithoutValueStyleMigratesToRemaining() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let encoded = try encoder.encode(UserProfile.initial)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "dashboardValueStyle")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let decoded = try decoder.decode(UserProfile.self, from: legacyData)

        XCTAssertEqual(decoded.dashboardValueStyle, .remaining)
    }

    func testLegacyProfileWithoutMilestoneStartModeOrThemeUsesCompatibleDefaults() throws {
        var profile = UserProfile.initial
        profile.birthDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 1990, month: 6, day: 15)))
        profile.customTargetStartDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 1, day: 1)))
        profile.widgetDisplayMode = .countdown
        profile.widgetTheme = .calmSea

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let encoded = try encoder.encode(profile)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "customTargetStartDate")
        object.removeValue(forKey: "widgetDisplayMode")
        object.removeValue(forKey: "widgetTheme")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let decoded = try decoder.decode(UserProfile.self, from: legacyData)

        XCTAssertEqual(decoded.customTargetStartDate, profile.birthDate)
        XCTAssertEqual(decoded.widgetDisplayMode, .progressBars)
        XCTAssertEqual(decoded.widgetTheme, .vividNight)
    }

    func testProfileRoundTripPreservesMilestoneStartModeAndTheme() throws {
        var profile = UserProfile.initial
        profile.customTargetStartDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 3)))
        profile.customTargetDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2029, month: 5, day: 6)))
        profile.widgetDisplayMode = .countdown
        profile.widgetTheme = .softDawn

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let decoded = try decoder.decode(UserProfile.self, from: encoder.encode(profile))

        XCTAssertEqual(decoded, profile)
    }

    func testCountdownWithPercentageModeRoundTrip() throws {
        var profile = UserProfile.initial
        profile.customTargetStartDate = try XCTUnwrap(calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 25)
        ))
        profile.customTargetDate = try XCTUnwrap(calendar.date(
            from: DateComponents(year: 2027, month: 8, day: 25)
        ))
        profile.widgetDisplayMode = .countdownWithPercentage

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let decoded = try decoder.decode(UserProfile.self, from: encoder.encode(profile))

        XCTAssertEqual(decoded, profile)
        XCTAssertEqual(decoded.widgetDisplayMode, .countdownWithPercentage)
    }

    func testUnknownModeAndThemeValuesFallBackWithoutDiscardingProfile() throws {
        var profile = UserProfile.initial
        profile.customTargetName = "Keep me"

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let encoded = try encoder.encode(profile)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["widgetDisplayMode"] = "futureMode"
        object["widgetTheme"] = "futureTheme"
        let data = try JSONSerialization.data(withJSONObject: object)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let decoded = try decoder.decode(UserProfile.self, from: data)

        XCTAssertEqual(decoded.customTargetName, "Keep me")
        XCTAssertEqual(decoded.widgetDisplayMode, .progressBars)
        XCTAssertEqual(decoded.widgetTheme, .vividNight)
    }

    func testSnapshotPercentageAndAccessibilityDescribeTheRemainingAmount() throws {
        // September has 30 days, so 7.5 elapsed days leave exactly 75%.
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 8, hour: 12)))
        let snapshot = TimeProgressCalculator.snapshot(
            for: .month,
            profile: .initial,
            now: now,
            calendar: calendar
        )

        let remainingPercentage = L10n.text("残り75.0%", "75.0% left")
        XCTAssertEqual(snapshot.percentageText, "75.0%")
        XCTAssertEqual(snapshot.percentageRemainingText, remainingPercentage)
        XCTAssertEqual(snapshot.valueText(style: .percentage), remainingPercentage)
        XCTAssertEqual(snapshot.valueText(style: .percentage, compact: true), remainingPercentage)
        XCTAssertFalse(snapshot.valueText(style: .remaining).isEmpty)
        XCTAssertFalse(snapshot.valueText(style: .targetDate).isEmpty)
        XCTAssertTrue(snapshot.accessibilitySummary.contains(remainingPercentage))
        XCTAssertTrue(snapshot.secondarySummary(excluding: .remaining).contains(remainingPercentage))
        XCTAssertTrue(snapshot.secondarySummary(excluding: .targetDate).contains(remainingPercentage))
    }

    func testCompactPercentageDoesNotLoseOneAtAnExactRemainingPercentage() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 28)))
        let snapshot = TimeProgressCalculator.snapshot(
            for: .month, profile: .initial, now: now, calendar: calendar
        )

        XCTAssertEqual(snapshot.remainingFraction, 0.1, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.percentageText, "10.0%")
        XCTAssertEqual(RemainingPercentage.compactNumber(for: snapshot.remainingFraction), "10")
        XCTAssertEqual(RemainingPercentage.compactText(for: snapshot.remainingFraction), "10%")
    }

    func testHealthyGoalKeepsPositiveTinyBalanceDistinctFromDepletedBalance() throws {
        var profile = UserProfile.initial
        profile.birthDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2000, month: 1, day: 1)))
        profile.healthyLifeYears = 75
        let target = try XCTUnwrap(calendar.date(from: DateComponents(year: 2075, month: 1, day: 1)))
        let tenDaysBeforeTarget = try XCTUnwrap(calendar.date(byAdding: .day, value: -10, to: target))
        let before = TimeProgressCalculator.snapshot(
            for: .healthyLife, profile: profile, now: tenDaysBeforeTarget, calendar: calendar
        )
        let atTarget = TimeProgressCalculator.snapshot(
            for: .healthyLife, profile: profile, now: target, calendar: calendar
        )

        XCTAssertGreaterThan(before.remainingFraction, 0)
        XCTAssertEqual(before.percentageText, "<0.1%")
        XCTAssertEqual(RemainingPercentage.compactText(for: before.remainingFraction), "<1%")
        XCTAssertTrue(before.accessibilitySummary.contains(L10n.text("残り<0.1%", "<0.1% left")))
        XCTAssertEqual(atTarget.percentageText, "0.0%")
        XCTAssertEqual(RemainingPercentage.compactText(for: atTarget.remainingFraction), "0%")
    }

    func testRemainingPercentagePrecisionThresholdsAndRounding() {
        for (fraction, detailed, compact) in [
            (0.0, "0.0%", "0%"),
            (0.000_999, "<0.1%", "<1%"),
            (0.001, "0.1%", "<1%"),
            (0.009_99, "1.0%", "<1%"),
            (0.01, "1.0%", "1%"),
            (0.256, "25.6%", "26%"),
            (1.0, "100.0%", "100%")
        ] {
            XCTAssertEqual(RemainingPercentage.text(for: fraction), detailed)
            XCTAssertEqual(RemainingPercentage.compactText(for: fraction), compact)
        }
    }

    func testExistingPercentageAndProgressBarSettingsKeepTheirSavedValuesAndShowRemaining() throws {
        var profile = UserProfile.initial
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))
        profile.customTargetStartDate = start
        profile.customTargetDate = start.addingTimeInterval(4 * 24 * 60 * 60)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any])
        object["dashboardValueStyle"] = "percentage"
        object["widgetDisplayMode"] = "progressBars"
        let decoded = try JSONDecoder().decode(UserProfile.self, from: JSONSerialization.data(withJSONObject: object))
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any])
        let snapshot = TimeProgressCalculator.snapshot(
            for: .customLife, profile: decoded, now: start.addingTimeInterval(24 * 60 * 60), calendar: calendar
        )

        XCTAssertEqual(decoded.dashboardValueStyle, .percentage)
        XCTAssertEqual(decoded.widgetDisplayMode, .progressBars)
        XCTAssertEqual(encoded["dashboardValueStyle"] as? String, "percentage")
        XCTAssertEqual(encoded["widgetDisplayMode"] as? String, "progressBars")
        XCTAssertEqual(snapshot.percentageText, "75.0%")
        XCTAssertEqual(snapshot.valueText(style: decoded.dashboardValueStyle), snapshot.percentageRemainingText)
    }

    func testCountdownPresentationKeepsNumbersSeparateFromUnitLabels() throws {
        var profile = UserProfile.initial
        let now = try XCTUnwrap(calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 15, hour: 12)
        ))
        profile.customTargetStartDate = try XCTUnwrap(calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 1)
        ))
        profile.customTargetDate = try XCTUnwrap(calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 20, hour: 15)
        ))

        let snapshot = TimeProgressCalculator.snapshot(
            for: .customLife,
            profile: profile,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.countdown.components.map(\.value), [5, 3])
        XCTAssertTrue(snapshot.countdown.components.allSatisfy { !$0.unit.isEmpty })
        XCTAssertNil(snapshot.countdown.terminalText)
        XCTAssertTrue(snapshot.remainingText.contains("5"))
        XCTAssertTrue(snapshot.remainingText.contains("3"))
    }

    func testWidgetValueStyleOverrideResolution() {
        XCTAssertEqual(WidgetValueStyleOption.appSetting.resolved(profileStyle: .targetDate), .targetDate)
        XCTAssertEqual(WidgetValueStyleOption.remaining.resolved(profileStyle: .targetDate), .remaining)
        XCTAssertEqual(WidgetValueStyleOption.percentage.resolved(profileStyle: .remaining), .percentage)
        XCTAssertEqual(WidgetValueStyleOption.targetDate.resolved(profileStyle: .percentage), .targetDate)
    }

    func testLockScreenMetricUsesFirstAppSelectionOrExplicitOverride() {
        var profile = UserProfile.initial
        profile.isConfigured = true
        profile.dashboardMetrics = [.year, .week, .month]

        XCTAssertEqual(LockScreenMetricOption.appSelection.resolved(profile: profile), .year)
        XCTAssertEqual(LockScreenMetricOption.week.resolved(profile: profile), .week)
        XCTAssertEqual(LockScreenMetricOption.month.resolved(profile: profile), .month)
        XCTAssertEqual(LockScreenMetricOption.year.resolved(profile: profile), .year)
        XCTAssertEqual(LockScreenMetricOption.healthyLife.resolved(profile: profile), .healthyLife)
        XCTAssertEqual(LockScreenMetricOption.customLife.resolved(profile: profile), .customLife)
    }

    func testLockScreenMetricDoesNotExposePlaceholderPersonalTargetsBeforeOnboarding() {
        let profile = UserProfile.initial

        XCTAssertEqual(LockScreenMetricOption.healthyLife.resolved(profile: profile), .week)
        XCTAssertEqual(LockScreenMetricOption.customLife.resolved(profile: profile), .week)
    }

    func testWidgetDisplayModeOverrideResolution() {
        XCTAssertEqual(WidgetDisplayModeOption.appSetting.resolved(profileMode: .countdown), .countdown)
        XCTAssertEqual(
            WidgetDisplayModeOption.appSetting.resolved(profileMode: .countdownWithPercentage),
            .countdownWithPercentage
        )
        XCTAssertEqual(WidgetDisplayModeOption.countdown.resolved(profileMode: .progressBars), .countdown)
        XCTAssertEqual(
            WidgetDisplayModeOption.countdownWithPercentage.resolved(profileMode: .progressBars),
            .countdownWithPercentage
        )
        XCTAssertEqual(WidgetDisplayModeOption.progressBars.resolved(profileMode: .countdown), .progressBars)
    }

    func testDisplayModesThatShowLiveCountdownAreIdentified() {
        XCTAssertTrue(WidgetDisplayMode.countdown.showsLiveCountdown)
        XCTAssertTrue(WidgetDisplayMode.countdownWithPercentage.showsLiveCountdown)
        XCTAssertFalse(WidgetDisplayMode.progressBars.showsLiveCountdown)
    }

    func testWidgetThemeOverrideResolution() {
        XCTAssertEqual(WidgetThemeOption.appSetting.resolved(profileTheme: .quietForest), .quietForest)
        XCTAssertEqual(WidgetThemeOption.vividNight.resolved(profileTheme: .calmSea), .vividNight)
        XCTAssertEqual(WidgetThemeOption.quietForest.resolved(profileTheme: .vividNight), .quietForest)
        XCTAssertEqual(WidgetThemeOption.softDawn.resolved(profileTheme: .vividNight), .softDawn)
        XCTAssertEqual(WidgetThemeOption.calmSea.resolved(profileTheme: .vividNight), .calmSea)
    }

    func testCustomTargetPreservesAbsoluteTime() throws {
        var profile = UserProfile.initial
        profile.birthDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2000, month: 1, day: 1)))
        profile.customTargetStartDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))
        profile.customTargetDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2030, month: 4, day: 3, hour: 17, minute: 45)))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 15)))

        let snapshot = TimeProgressCalculator.snapshot(
            for: .customLife,
            profile: profile,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.targetDate, profile.customTargetDate)
        XCTAssertTrue(snapshot.valueText(style: .targetDate).contains("45"))
    }

    func testCustomTargetUsesConfiguredStartAndClampsAcrossItsInterval() throws {
        var profile = UserProfile.initial
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))
        let quarterElapsed = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 3, hour: 12)))
        let target = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 11)))
        let beforeStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 12, day: 31)))
        let afterTarget = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 12)))
        profile.customTargetStartDate = start
        profile.customTargetDate = target

        let interval = TimeProgressCalculator.dateInterval(
            for: .customLife,
            profile: profile,
            now: quarterElapsed,
            calendar: calendar
        )
        let beforeSnapshot = TimeProgressCalculator.snapshot(
            for: .customLife,
            profile: profile,
            now: beforeStart,
            calendar: calendar
        )
        let startSnapshot = TimeProgressCalculator.snapshot(
            for: .customLife,
            profile: profile,
            now: start,
            calendar: calendar
        )
        let quarterElapsedSnapshot = TimeProgressCalculator.snapshot(
            for: .customLife,
            profile: profile,
            now: quarterElapsed,
            calendar: calendar
        )
        let targetSnapshot = TimeProgressCalculator.snapshot(
            for: .customLife,
            profile: profile,
            now: target,
            calendar: calendar
        )
        let afterSnapshot = TimeProgressCalculator.snapshot(
            for: .customLife,
            profile: profile,
            now: afterTarget,
            calendar: calendar
        )

        XCTAssertEqual(interval.start, start)
        XCTAssertEqual(interval.end, target)
        XCTAssertEqual(beforeSnapshot.elapsedFraction, 0)
        XCTAssertEqual(beforeSnapshot.remainingFraction, 1)
        XCTAssertEqual(startSnapshot.remainingFraction, 1)
        XCTAssertEqual(startSnapshot.percentageText, "100.0%")
        XCTAssertEqual(quarterElapsedSnapshot.elapsedFraction, 0.25, accuracy: 0.000_001)
        XCTAssertEqual(quarterElapsedSnapshot.remainingFraction, 0.75, accuracy: 0.000_001)
        XCTAssertEqual(quarterElapsedSnapshot.percentageText, "75.0%")
        XCTAssertEqual(targetSnapshot.remainingFraction, 0)
        XCTAssertEqual(targetSnapshot.percentageText, "0.0%")
        XCTAssertEqual(afterSnapshot.elapsedFraction, 1)
        XCTAssertEqual(afterSnapshot.remainingFraction, 0)
    }

    func testCustomTargetWithStartAtOrAfterTargetRemainsFinite() throws {
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 10)))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))

        for target in [start, start.addingTimeInterval(-24 * 60 * 60)] {
            var profile = UserProfile.initial
            profile.customTargetStartDate = start
            profile.customTargetDate = target

            let interval = TimeProgressCalculator.dateInterval(
                for: .customLife,
                profile: profile,
                now: now,
                calendar: calendar
            )
            let snapshot = TimeProgressCalculator.snapshot(
                for: .customLife,
                profile: profile,
                now: now,
                calendar: calendar
            )

            XCTAssertEqual(interval.start, start)
            XCTAssertEqual(interval.duration, 1, accuracy: 0.000_001)
            XCTAssertTrue(snapshot.elapsedFraction.isFinite)
            XCTAssertEqual(snapshot.elapsedFraction, 0)
            XCTAssertTrue(snapshot.remainingFraction.isFinite)
            XCTAssertEqual(snapshot.remainingFraction, 1)
        }
    }

    func testMonthBoundaryRemainsCalendarCorrectAcrossDST() throws {
        var newYorkCalendar = Calendar(identifier: .gregorian)
        newYorkCalendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let now = try XCTUnwrap(newYorkCalendar.date(from: DateComponents(year: 2024, month: 3, day: 15, hour: 12)))

        let interval = TimeProgressCalculator.dateInterval(
            for: .month,
            profile: .initial,
            now: now,
            calendar: newYorkCalendar
        )

        let endComponents = newYorkCalendar.dateComponents([.year, .month, .day, .hour, .minute], from: interval.end)
        XCTAssertEqual(endComponents.year, 2024)
        XCTAssertEqual(endComponents.month, 4)
        XCTAssertEqual(endComponents.day, 1)
        XCTAssertEqual(endComponents.hour, 0)
        XCTAssertEqual(endComponents.minute, 0)
        XCTAssertEqual(interval.duration, (31 * 24 - 1) * 60 * 60, accuracy: 0.5)
    }

    func testCustomTargetClampsAfterCompletion() throws {
        var profile = UserProfile.initial
        profile.birthDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2000, month: 1, day: 1)))
        profile.customTargetStartDate = profile.birthDate
        profile.customTargetDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2020, month: 1, day: 1)))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))

        let snapshot = TimeProgressCalculator.snapshot(
            for: .customLife,
            profile: profile,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.elapsedFraction, 1)
        XCTAssertEqual(snapshot.remainingFraction, 0)
        XCTAssertFalse(snapshot.remainingText.contains("-"))
    }
}
