import XCTest
#if os(macOS)
@testable import DaysYetMac
#else
@testable import DaysYet
#endif

final class WidgetColorProfileTests: XCTestCase {
    func testLegacyProfilesReceiveEmptyColorsWithoutChangingOtherSettings() throws {
        var profile = UserProfile.initial
        profile.widgetTheme = .calmSea
        profile.dashboardMetrics = [.workday, .study, .customLife]
        profile.circleWidgetSettings = CircleWidgetSettings(
            metrics: [.study, .study, .week, .year], valueStyle: .targetDate, theme: .quietForest
        )
        var object = try encodedObject(profile)
        object.removeValue(forKey: "widgetCustomColors")
        var circle = try XCTUnwrap(object["circleWidgetSettings"] as? [String: Any])
        circle.removeValue(forKey: "customColors")
        object["circleWidgetSettings"] = circle

        XCTAssertEqual(try decode(object), profile)
        object.removeValue(forKey: "circleWidgetSettings")
        let older = try decode(object)
        XCTAssertTrue(older.widgetCustomColors.isEmpty)
        XCTAssertEqual(older.circleWidgetSettings, CircleWidgetSettings())
        XCTAssertEqual(older.widgetTheme, profile.widgetTheme)
        XCTAssertEqual(older.dashboardMetrics, profile.dashboardMetrics)
    }

    func testBothColorMapsRoundTripAsIndependentRawMetricHexObjects() throws {
        let row = try XCTUnwrap(WidgetColor(hex: "12abEF"))
        let circle = try XCTUnwrap(WidgetColor(hex: "#AABBCC"))
        var profile = UserProfile.initial
        profile.widgetCustomColors = [.week: row, .study: circle]
        profile.circleWidgetSettings.customColors = [.week: circle]
        let object = try encodedObject(profile)
        XCTAssertEqual(object["widgetCustomColors"] as? [String: String], ["week": "#12ABEF", "study": "#AABBCC"])
        let encodedCircle = try XCTUnwrap(object["circleWidgetSettings"] as? [String: Any])
        XCTAssertEqual(encodedCircle["customColors"] as? [String: String], ["week": "#AABBCC"])
        XCTAssertEqual(try decode(object), profile)
    }

    func testInvalidColorEntriesAndUnknownMetricsDoNotDiscardValidColors() throws {
        var profile = UserProfile.initial
        profile.customTargetName = "Preserved milestone"
        var object = try encodedObject(profile)
        let mixed: [String: Any] = [
            "week": "12abEF", "workday": "#445566", "month": "invalid", "year": 123,
            "study": NSNull(), "activity": ["hex": "#112233"], "futureMetric": "#FFFFFF", "": "#000000"
        ]
        object["widgetCustomColors"] = mixed
        var circle = try XCTUnwrap(object["circleWidgetSettings"] as? [String: Any])
        circle["customColors"] = mixed
        object["circleWidgetSettings"] = circle
        let restored = try decode(object)
        let expected: [MetricKind: WidgetColor] = [
            .week: try XCTUnwrap(WidgetColor(hex: "#12ABEF")),
            .workday: try XCTUnwrap(WidgetColor(hex: "#445566"))
        ]
        XCTAssertEqual(restored.widgetCustomColors, expected)
        XCTAssertEqual(restored.circleWidgetSettings.customColors, expected)
        XCTAssertEqual(restored.customTargetName, profile.customTargetName)
        XCTAssertEqual(restored.circleWidgetSettings.metrics, profile.circleWidgetSettings.metrics)
    }

    func testMalformedColorMapsFallBackIndependentlyWithoutLosingCircleSettings() throws {
        var profile = UserProfile.initial
        profile.circleWidgetSettings.valueStyle = .targetDate
        profile.circleWidgetSettings.theme = .softDawn
        for malformed in ["#123456", ["#123456"], 123, NSNull()] as [Any] {
            var object = try encodedObject(profile)
            object["widgetCustomColors"] = malformed
            var circle = try XCTUnwrap(object["circleWidgetSettings"] as? [String: Any])
            circle["customColors"] = malformed
            object["circleWidgetSettings"] = circle
            XCTAssertEqual(try decode(object), profile)
        }
    }

    func testFollowingRowThemeInheritsColorsAndCircleOverridesWinWithoutMutatingRows() throws {
        let rowWeek = try XCTUnwrap(WidgetColor(hex: "#112233"))
        let rowMonth = try XCTUnwrap(WidgetColor(hex: "#445566"))
        let circleWeek = try XCTUnwrap(WidgetColor(hex: "#AABBCC"))
        var profile = UserProfile.initial
        profile.widgetCustomColors = [.week: rowWeek, .month: rowMonth]
        profile.circleWidgetSettings.customColors = [.week: circleWeek]
        XCTAssertEqual(profile.resolvedCircleWidgetCustomColors, [.week: circleWeek, .month: rowMonth])
        XCTAssertEqual(profile.widgetCustomColors, [.week: rowWeek, .month: rowMonth])
        XCTAssertEqual(profile.circleWidgetSettings.customColors, [.week: circleWeek])

        profile.circleWidgetSettings.customColors[.week] = nil
        XCTAssertEqual(profile.resolvedCircleWidgetCustomColors, profile.widgetCustomColors)
        profile.widgetCustomColors[.month] = nil
        XCTAssertEqual(profile.resolvedCircleWidgetCustomColors, [.week: rowWeek])
    }

    func testExplicitCircleThemeExcludesRowColorsEvenWhenThemeValuesMatch() throws {
        let rowColor = try XCTUnwrap(WidgetColor(hex: "#112233"))
        let circleColor = try XCTUnwrap(WidgetColor(hex: "#AABBCC"))
        var profile = UserProfile.initial
        profile.widgetCustomColors = [.week: rowColor]
        profile.circleWidgetSettings = CircleWidgetSettings(theme: profile.widgetTheme, customColors: [.month: circleColor])
        XCTAssertEqual(profile.resolvedCircleWidgetCustomColors, [.month: circleColor])

        profile.widgetCustomColors[.year] = rowColor
        XCTAssertEqual(profile.resolvedCircleWidgetCustomColors, [.month: circleColor])
        profile.circleWidgetSettings.theme = nil
        XCTAssertEqual(profile.resolvedCircleWidgetCustomColors, [.week: rowColor, .year: rowColor, .month: circleColor])
        XCTAssertEqual(try decode(encodedObject(profile)), profile)
    }

    private func encodedObject(_ profile: UserProfile) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any])
    }

    private func decode(_ object: [String: Any]) throws -> UserProfile {
        try JSONDecoder().decode(UserProfile.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
