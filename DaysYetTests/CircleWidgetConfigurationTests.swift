import XCTest
#if os(macOS)
@testable import DaysYetMac
#else
@testable import DaysYet
#endif

final class CircleWidgetConfigurationTests: XCTestCase {
    func testDefaultsHaveFourIndependentMetricsAndPercentageValues() {
        let configuration = DaysYetCircleConfigurationIntent()
        XCTAssertEqual(configuration.resolvedMetrics(profile: .initial), [.week, .month, .year, .activity])
        XCTAssertEqual(configuration.valueStyle.resolved(profileStyle: .remaining), .percentage)
        XCTAssertEqual(configuration.theme, .appSetting)
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
        let configuration = DaysYetCircleConfigurationIntent()
        XCTAssertEqual(configuration.theme.resolved(profileTheme: .calmSea), .calmSea)
        configuration.valueStyle = .appSetting
        XCTAssertEqual(configuration.valueStyle.resolved(profileStyle: .targetDate), .targetDate)
        configuration.theme = .quietForest
        configuration.valueStyle = .remaining
        XCTAssertEqual(configuration.theme.resolved(profileTheme: .calmSea), .quietForest)
        XCTAssertEqual(configuration.valueStyle.resolved(profileStyle: .targetDate), .remaining)
    }
}
