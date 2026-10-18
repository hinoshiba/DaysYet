import XCTest
#if os(macOS)
@testable import DaysYetMac
#else
@testable import DaysYet
#endif

final class CircleWidgetConfigurationTests: XCTestCase {
    func testDefaultsFollowTheDedicatedAppSettings() {
        let configuration = DaysYetCircleConfigurationIntent()
        XCTAssertEqual(configuration.resolvedMetrics(profile: .initial), [.week, .month, .year, .activity])
        XCTAssertEqual(configuration.resolvedValueStyle(profile: .initial), .percentage)
        XCTAssertEqual(configuration.firstMetric, .appSetting)
        XCTAssertEqual(configuration.$firstMetric.defaultValue, .appSetting)
        XCTAssertEqual(configuration.$secondMetric.defaultValue, .appSetting)
        XCTAssertEqual(configuration.$thirdMetric.defaultValue, .appSetting)
        XCTAssertEqual(configuration.$fourthMetric.defaultValue, .appSetting)
        XCTAssertEqual(configuration.$valueStyle.defaultValue, .appSetting)
        XCTAssertEqual(configuration.theme, .appSetting)

        var profile = UserProfile.initial
        profile.isConfigured = true
        profile.circleWidgetSettings = CircleWidgetSettings(
            metrics: [.study, .workday, .activity, .customLife], valueStyle: .targetDate, theme: .softDawn
        )
        XCTAssertEqual(configuration.resolvedMetrics(profile: profile), profile.circleWidgetSettings.metrics)
        XCTAssertEqual(configuration.resolvedValueStyle(profile: profile), .targetDate)
        XCTAssertEqual(configuration.resolvedTheme(profile: profile), .softDawn)
    }

    func testEachSlotCanBeChangedWithoutFollowingTheThreeDashboardMetrics() {
        var profile = UserProfile.initial
        profile.isConfigured = true
        profile.dashboardMetrics = [.year, .year, .year]
        let configuration = DaysYetCircleConfigurationIntent()
        configuration.firstMetric = .study
        configuration.secondMetric = .customLife
        configuration.thirdMetric = .healthyLife
        configuration.fourthMetric = .workday

        XCTAssertEqual(configuration.resolvedMetrics(profile: profile), [.study, .customLife, .healthyLife, .workday])
        XCTAssertEqual(profile.dashboardMetrics, [.year, .year, .year])
    }

    func testBeforeOnboardingPersonalMetricsAreReplacedWithoutDroppingSlots() {
        let configuration = DaysYetCircleConfigurationIntent()
        configuration.firstMetric = .healthyLife
        configuration.secondMetric = .customLife
        configuration.thirdMetric = .year
        configuration.fourthMetric = .activity

        XCTAssertEqual(configuration.resolvedMetrics(profile: .initial), [.week, .month, .year, .activity])
    }

    func testFourthPersonalMetricUsesAnotherAvailablePeriodBeforeOnboarding() {
        let configuration = DaysYetCircleConfigurationIntent()
        configuration.fourthMetric = .customLife

        XCTAssertEqual(configuration.resolvedMetrics(profile: .initial), [.week, .month, .year, .activity])
    }

    func testRepeatedSelectionsKeepTheirPosition() {
        let configuration = DaysYetCircleConfigurationIntent()
        configuration.firstMetric = .study
        configuration.secondMetric = .study
        configuration.thirdMetric = .workday
        configuration.fourthMetric = .workday

        XCTAssertEqual(configuration.resolvedMetrics(profile: .initial), [.study, .study, .workday, .workday])
    }

    func testThemeAndOptionalValueStyleFollowAppOrOverrideIt() {
        var profile = UserProfile.initial
        profile.widgetTheme = .calmSea
        profile.circleWidgetSettings.valueStyle = .targetDate
        let configuration = DaysYetCircleConfigurationIntent()
        XCTAssertEqual(configuration.resolvedTheme(profile: profile), .calmSea)
        XCTAssertEqual(configuration.resolvedValueStyle(profile: profile), .targetDate)
        profile.circleWidgetSettings.theme = .softDawn
        XCTAssertEqual(configuration.resolvedTheme(profile: profile), .softDawn)
        configuration.theme = .quietForest
        configuration.valueStyle = .remaining
        XCTAssertEqual(configuration.resolvedTheme(profile: profile), .quietForest)
        XCTAssertEqual(configuration.resolvedValueStyle(profile: profile), .remaining)
    }

    func testExistingExplicitWidgetChoicesRemainIndependentOfNewAppSettings() throws {
        var profile = UserProfile.initial
        profile.isConfigured = true
        profile.circleWidgetSettings = CircleWidgetSettings(
            metrics: [.study, .study, .study, .study], valueStyle: .targetDate, theme: .softDawn
        )
        let configuration = DaysYetCircleConfigurationIntent()
        // Existing widget parameters retain their names, enum types, and raw values.
        configuration.firstMetric = try XCTUnwrap(WidgetMetricOption(rawValue: "week"))
        configuration.secondMetric = try XCTUnwrap(WidgetMetricOption(rawValue: "month"))
        configuration.thirdMetric = try XCTUnwrap(WidgetMetricOption(rawValue: "year"))
        configuration.fourthMetric = try XCTUnwrap(WidgetMetricOption(rawValue: "activity"))
        configuration.valueStyle = try XCTUnwrap(WidgetValueStyleOption(rawValue: "percentage"))
        configuration.theme = try XCTUnwrap(WidgetThemeOption(rawValue: "quietForest"))
        XCTAssertEqual(configuration.resolvedMetrics(profile: profile), [.week, .month, .year, .activity])
        XCTAssertEqual(configuration.resolvedValueStyle(profile: profile), .percentage)
        XCTAssertEqual(configuration.resolvedTheme(profile: profile), .quietForest)

        configuration.thirdMetric = .appSetting
        XCTAssertEqual(configuration.resolvedMetrics(profile: profile), [.week, .month, .study, .activity])
    }

    func testCustomColorsFollowAppSettingsWithoutChangingExplicitWidgetTemplates() throws {
        var profile = UserProfile.initial
        let rowColor = try XCTUnwrap(WidgetColor(hex: "#1278FE"))
        let circleColor = try XCTUnwrap(WidgetColor(hex: "#A04BCD"))
        profile.widgetCustomColors = [.week: rowColor]
        profile.circleWidgetSettings.customColors = [.month: circleColor]
        let configuration = DaysYetCircleConfigurationIntent()
        XCTAssertEqual(configuration.resolvedCustomColors(profile: profile), [.week: rowColor, .month: circleColor])

        for option in WidgetThemeOption.allCases where option != .appSetting {
            configuration.theme = option
            XCTAssertTrue(configuration.resolvedCustomColors(profile: profile).isEmpty)
        }

        configuration.theme = .appSetting
        profile.circleWidgetSettings.theme = .softDawn
        XCTAssertEqual(configuration.resolvedCustomColors(profile: profile), [.month: circleColor])
        XCTAssertEqual(profile.widgetCustomColors, [.week: rowColor])
    }

    func testCustomPaletteColorChangesOnlyItsTimelineAndKeepsTemplateGradients() throws {
        let custom = try XCTUnwrap(WidgetColor(hex: "#12ABEF"))
        for theme in WidgetTheme.allCases {
            let palette = theme.palette
            XCTAssertEqual(palette.colors(for: .week, customColors: [.week: custom]), [custom.color, custom.color])
            for kind in MetricKind.allCases where kind != .week {
                XCTAssertEqual(palette.colors(for: kind, customColors: [.week: custom]), palette.colors(for: kind))
            }
            XCTAssertEqual(palette.colors(for: .week, customColors: [:]), palette.colors(for: .week))
        }
    }

    func testDedicatedSettingsRoundTripWithRepeatedMetricsAndThemeInheritance() throws {
        var profile = UserProfile.initial
        profile.circleWidgetSettings = CircleWidgetSettings(
            metrics: [.study, .study, .workday, .workday], valueStyle: .remaining, theme: .quietForest
        )
        var decoded = try JSONDecoder().decode(UserProfile.self, from: JSONEncoder().encode(profile))
        XCTAssertEqual(decoded, profile)

        profile.circleWidgetSettings.theme = nil
        decoded = try JSONDecoder().decode(UserProfile.self, from: JSONEncoder().encode(profile))
        XCTAssertEqual(decoded.circleWidgetSettings, profile.circleWidgetSettings)
        XCTAssertNil(decoded.circleWidgetSettings.theme)
    }

    func testOlderProfilesReceiveCircleDefaultsWithoutChangingTheirDashboard() throws {
        var profile = UserProfile.initial
        profile.dashboardMetrics = [.workday, .study, .customLife]
        profile.dashboardValueStyle = .targetDate
        profile.widgetTheme = .calmSea
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any])
        object.removeValue(forKey: "circleWidgetSettings")
        let migrated = try JSONDecoder().decode(UserProfile.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(migrated, profile)
        XCTAssertEqual(migrated.circleWidgetSettings, CircleWidgetSettings())
        XCTAssertEqual(DaysYetCircleConfigurationIntent().resolvedTheme(profile: migrated), .calmSea)
    }

    func testMalformedCircleSettingsKeepValidSlotsAndOtherProfilePreferences() throws {
        var profile = UserProfile.initial
        profile.customTargetName = "Preserved milestone"
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any])
        object["circleWidgetSettings"] = [
            "metrics": ["study", "futureMetric", "workday"],
            "valueStyle": "futureStyle", "theme": "futureTheme"
        ] as [String: Any]
        var decoded = try JSONDecoder().decode(UserProfile.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.circleWidgetSettings.normalizedMetrics, [.study, .month, .workday, .activity])
        XCTAssertEqual(decoded.circleWidgetSettings.valueStyle, .percentage)
        XCTAssertNil(decoded.circleWidgetSettings.theme)
        XCTAssertEqual(decoded.customTargetName, profile.customTargetName)

        object["circleWidgetSettings"] = "invalid"
        decoded = try JSONDecoder().decode(UserProfile.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded, profile)
    }

    func testMetricNormalizationAlwaysKeepsFourPositionsAndRepeatedSelections() {
        XCTAssertEqual(CircleWidgetSettings(metrics: [.study, .study]).normalizedMetrics, [.study, .study, .year, .activity])
        XCTAssertEqual(
            CircleWidgetSettings(metrics: [.study, .study, .workday, .workday, .month]).normalizedMetrics,
            [.study, .study, .workday, .workday]
        )
    }

    @MainActor
    func testEditingTheFourSlotsPersistsWithoutChangingTheThreeDashboardSlots() {
        var profile = UserProfile.initial
        profile.dashboardMetrics = [.month, .year, .workday]
        var saved: UserProfile?
        let store = ProfileStore(profile: profile, saveProfile: { saved = $0 })
        store.setCircleWidgetMetric(.study, at: 3)
        store.setCircleWidgetMetric(.study, at: 0)
        XCTAssertEqual(store.profile.circleWidgetSettings.metrics, [.study, .month, .year, .study])
        XCTAssertEqual(store.profile.dashboardMetrics, profile.dashboardMetrics)
        XCTAssertEqual(saved?.circleWidgetSettings, store.profile.circleWidgetSettings)
        XCTAssertEqual(saved?.dashboardMetrics, profile.dashboardMetrics)

        store.setCircleWidgetMetric(.healthyLife, at: 4)
        XCTAssertEqual(store.profile.circleWidgetSettings.metrics, [.study, .month, .year, .study])
        store.update { $0.circleWidgetSettings.metrics = [.workday] }
        XCTAssertEqual(saved?.circleWidgetSettings.metrics, [.workday, .month, .year, .activity])
    }
}
