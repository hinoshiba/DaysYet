import XCTest
@testable import DaysYet

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

    func testYearElapsedFractionAtLeapYearMidpoint() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2024, month: 7, day: 2)))
        let snapshot = TimeProgressCalculator.snapshot(
            for: .year,
            profile: .initial,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.elapsedFraction, 0.5, accuracy: 0.002)
    }

    func testPastHealthyTargetClampsElapsedProgressToOne() throws {
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
        XCTAssertFalse(snapshot.remainingText.contains("-"))
    }

    func testHealthyTargetIsFullyElapsedAtConfiguredAge() throws {
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
        XCTAssertEqual(snapshot.percentageText, "100.0%")
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

    func testSnapshotSupportsElapsedPercentageRemainingTimeAndEndDateValues() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 15, hour: 12)))
        let snapshot = TimeProgressCalculator.snapshot(
            for: .month,
            profile: .initial,
            now: now,
            calendar: calendar
        )

        XCTAssertTrue(snapshot.valueText(style: .percentage).contains("%"))
        XCTAssertNotEqual(snapshot.valueText(style: .percentage), snapshot.percentageText)
        XCTAssertFalse(snapshot.valueText(style: .remaining).isEmpty)
        XCTAssertFalse(snapshot.valueText(style: .targetDate).isEmpty)
        XCTAssertTrue(snapshot.accessibilitySummary.contains(snapshot.percentageText))
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
        let midpoint = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 6)))
        let target = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 11)))
        let beforeStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 12, day: 31)))
        let afterTarget = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 12)))
        profile.customTargetStartDate = start
        profile.customTargetDate = target

        let interval = TimeProgressCalculator.dateInterval(
            for: .customLife,
            profile: profile,
            now: midpoint,
            calendar: calendar
        )
        let beforeSnapshot = TimeProgressCalculator.snapshot(
            for: .customLife,
            profile: profile,
            now: beforeStart,
            calendar: calendar
        )
        let midpointSnapshot = TimeProgressCalculator.snapshot(
            for: .customLife,
            profile: profile,
            now: midpoint,
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
        XCTAssertEqual(midpointSnapshot.elapsedFraction, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(afterSnapshot.elapsedFraction, 1)
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
        XCTAssertFalse(snapshot.remainingText.contains("-"))
    }
}
