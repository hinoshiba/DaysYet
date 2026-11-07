import XCTest
#if os(macOS)
@testable import DaysYetMac
#else
@testable import DaysYet
#endif

final class WidgetLayoutConfigurationTests: XCTestCase {
    func testDefaultWidgetFollowsBothLayoutsWithoutLosingTheirSelections() {
        let configuration = DaysYetConfigurationIntent()
        var profile = UserProfile.initial
        profile.isConfigured = true
        profile.dashboardMetrics = [.workday, .study, .year]
        profile.dashboardValueStyle = .targetDate
        profile.circleWidgetSettings = CircleWidgetSettings(
            metrics: [.month, .activity, .study, .week, .year, .customLife, .workday, .study],
            valueStyle: .percentage
        )

        for layout in [WidgetLayout.rows, .circles, .rows] {
            profile.widgetLayout = layout
            XCTAssertEqual(configuration.resolvedLayout(profile: profile), layout)
            XCTAssertEqual(configuration.resolvedMetrics(profile: profile), layout == .rows
                           ? profile.normalizedDashboardMetrics : profile.circleWidgetSettings.metrics)
            XCTAssertEqual(configuration.resolvedValueStyle(profile: profile), layout == .rows ? .targetDate : .percentage)
        }
    }

    func testExistingCustomRowsStayFixedWhenTheAppChoosesCircles() {
        let configuration = DaysYetConfigurationIntent()
        configuration.followsAppSelection = false
        configuration.firstMetric = .workday
        configuration.secondMetric = .study
        configuration.thirdMetric = .month
        var profile = UserProfile.initial
        profile.widgetLayout = .circles
        profile.dashboardValueStyle = .targetDate

        XCTAssertEqual(configuration.resolvedLayout(profile: profile), .rows)
        XCTAssertEqual(configuration.resolvedMetrics(profile: profile), [.workday, .study, .month])
        XCTAssertEqual(configuration.resolvedValueStyle(profile: profile), .targetDate)
    }

    func testWidgetValueAndThemeOverridesSurviveLayoutChanges() {
        let configuration = DaysYetConfigurationIntent()
        configuration.valueStyle = .remaining
        configuration.theme = .quietForest
        var profile = UserProfile.initial
        profile.widgetTheme = .softDawn
        profile.dashboardValueStyle = .targetDate
        for layout in WidgetLayout.allCases {
            profile.widgetLayout = layout
            XCTAssertEqual(configuration.resolvedValueStyle(profile: profile), .remaining)
            XCTAssertEqual(configuration.resolvedTheme(profile: profile), .quietForest)
        }
        configuration.theme = .appSetting
        XCTAssertEqual(configuration.resolvedTheme(profile: profile), .softDawn)
    }

    func testUnconfiguredPersonalMetricsAreSafeInEitherLayout() {
        let configuration = DaysYetConfigurationIntent()
        var profile = UserProfile.initial
        profile.dashboardMetrics = [.healthyLife, .customLife, .year]
        profile.circleWidgetSettings.metrics = [.healthyLife, .customLife, .study, .study, .workday]
        for layout in WidgetLayout.allCases {
            profile.widgetLayout = layout
            let metrics = configuration.resolvedMetrics(profile: profile)
            XCTAssertEqual(metrics.count, layout == .rows ? 3 : 5)
            XCTAssertFalse(metrics.contains(.healthyLife))
            XCTAssertFalse(metrics.contains(.customLife))
        }
        XCTAssertEqual(Array(configuration.resolvedMetrics(profile: profile).suffix(3)), [.study, .study, .workday])
    }

    func testMissingOrInvalidLayoutKeepsExistingProfileAndDefaultsToRows() throws {
        var profile = UserProfile.initial
        profile.isConfigured = true
        profile.widgetTheme = .calmSea
        profile.dashboardMetrics = [.study, .workday, .year]
        profile.circleWidgetSettings.metrics = [.study, .study, .month, .workday, .activity]
        let encoded = try JSONEncoder().encode(profile)
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let invalidValues: [Any?] = [nil, "future-layout", 17]
        for value in invalidValues {
            var object = original
            object["widgetLayout"] = value
            let decoded = try JSONDecoder().decode(UserProfile.self, from: JSONSerialization.data(withJSONObject: object))
            XCTAssertEqual(decoded, profile)
            XCTAssertEqual(decoded.widgetLayout, .rows)
        }
    }

    @MainActor
    func testLayoutSelectionSavesAndSurvivesProfileReload() throws {
        var saved: Data?
        var initial = UserProfile.initial
        initial.circleWidgetSettings.metrics = [.activity, .workday, .study, .month, .year]
        let store = ProfileStore(profile: initial, appliesLaunchArguments: false) {
            saved = try? JSONEncoder().encode($0)
        }
        for layout in [WidgetLayout.circles, .rows, .circles] {
            store.update { $0.widgetLayout = layout }
            let restored = try JSONDecoder().decode(UserProfile.self, from: XCTUnwrap(saved))
            XCTAssertEqual(restored.widgetLayout, layout)
            XCTAssertEqual(restored.circleWidgetSettings, initial.circleWidgetSettings)
            XCTAssertEqual(restored.dashboardMetrics, initial.dashboardMetrics)
        }
    }
}
