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

    func testYearFractionAtLeapYearMidpoint() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2024, month: 7, day: 2)))
        let snapshot = TimeProgressCalculator.snapshot(
            for: .year,
            profile: .initial,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.remainingFraction, 0.5, accuracy: 0.002)
    }

    func testPastHealthyTargetClampsToZero() throws {
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

        XCTAssertEqual(snapshot.remainingFraction, 0)
        XCTAssertFalse(snapshot.remainingText.contains("-"))
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
        XCTAssertEqual(profile.dashboardValueStyle, .remaining)
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

    func testSnapshotSupportsPercentageRemainingAndEndDateValues() throws {
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

    func testWidgetValueStyleOverrideResolution() {
        XCTAssertEqual(WidgetValueStyleOption.appSetting.resolved(profileStyle: .targetDate), .targetDate)
        XCTAssertEqual(WidgetValueStyleOption.remaining.resolved(profileStyle: .targetDate), .remaining)
        XCTAssertEqual(WidgetValueStyleOption.percentage.resolved(profileStyle: .remaining), .percentage)
        XCTAssertEqual(WidgetValueStyleOption.targetDate.resolved(profileStyle: .percentage), .targetDate)
    }

    func testCustomTargetPreservesAbsoluteTime() throws {
        var profile = UserProfile.initial
        profile.birthDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2000, month: 1, day: 1)))
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
        profile.customTargetDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2020, month: 1, day: 1)))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))

        let snapshot = TimeProgressCalculator.snapshot(
            for: .customLife,
            profile: profile,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.remainingFraction, 0)
        XCTAssertFalse(snapshot.remainingText.contains("-"))
    }
}
