import XCTest
#if os(macOS)
@testable import DaysYetMac
#else
@testable import DaysYet
#endif

final class OnboardingTests: XCTestCase {
    @MainActor
    func testDeferringSetupPersistsWithoutSavingDraftValuesOrChangingTargetDate() throws {
        var original = UserProfile.initial
        original.customTargetName = "Trip"
        var saved: UserProfile?
        let store = ProfileStore(profile: original, appliesLaunchArguments: false, saveProfile: { saved = $0 })

        store.completeOnboarding(birthDate: nil, healthyLifeYears: 100)

        let restored = try JSONDecoder().decode(UserProfile.self, from: JSONEncoder().encode(XCTUnwrap(saved)))
        XCTAssertTrue(restored.isConfigured)
        XCTAssertFalse(restored.isHealthyLifeConfigured)
        XCTAssertEqual(restored.dashboardMetrics, [.week, .month, .year])
        XCTAssertEqual(restored.birthDate, original.birthDate)
        XCTAssertEqual(restored.healthyLifeYears, original.healthyLifeYears)
        XCTAssertEqual(restored.customTargetName, original.customTargetName)
        XCTAssertEqual(restored.customTargetStartDate, original.customTargetStartDate)
        XCTAssertEqual(restored.customTargetDate, original.customTargetDate)
        XCTAssertTrue(TimeProgressCalculator.snapshot(for: .healthyLife, profile: restored).requiresSetup)
    }

    @MainActor
    func testEnteringBirthDateCompletesSetupAndIncludesHealthyGoal() throws {
        let store = ProfileStore(profile: .initial, appliesLaunchArguments: false, saveProfile: { _ in })
        let birthDate = Date(timeIntervalSince1970: 631_152_000)
        store.completeOnboarding(birthDate: birthDate, healthyLifeYears: 85)

        XCTAssertTrue(store.profile.isConfigured)
        XCTAssertTrue(store.profile.isHealthyLifeConfigured)
        XCTAssertEqual(store.profile.birthDate, birthDate)
        XCTAssertEqual(store.profile.healthyLifeYears, 85)
        XCTAssertEqual(store.profile.dashboardMetrics, [.month, .year, .healthyLife])
        let snapshot = TimeProgressCalculator.snapshot(for: .healthyLife, profile: store.profile, now: birthDate)
        XCTAssertFalse(snapshot.requiresSetup)
        XCTAssertEqual(snapshot.remainingFraction, 1)
    }

    @MainActor
    func testLaterEditorOnlyEnablesHealthyGoalWhenSavedAndKeepsWidgetSelection() {
        let store = ProfileStore(profile: .initial, appliesLaunchArguments: false, saveProfile: { _ in })
        store.completeOnboarding(birthDate: nil, healthyLifeYears: 75)
        var draft = store.profile
        draft.birthDate = Date(timeIntervalSince1970: 946_684_800)
        draft.healthyLifeYears = 90
        draft.customTargetName = "Unrelated edit"

        XCTAssertFalse(store.profile.isHealthyLifeConfigured)
        store.saveMetricSettings(.week, from: draft)
        XCTAssertFalse(store.profile.isHealthyLifeConfigured)
        store.saveMetricSettings(.healthyLife, from: draft)

        XCTAssertTrue(store.profile.isHealthyLifeConfigured)
        XCTAssertEqual(store.profile.birthDate, draft.birthDate)
        XCTAssertEqual(store.profile.healthyLifeYears, draft.healthyLifeYears)
        XCTAssertEqual(store.profile.dashboardMetrics, [.week, .month, .year])
        XCTAssertEqual(store.profile.customTargetName, "")
        XCTAssertFalse(TimeProgressCalculator.snapshot(for: .healthyLife, profile: store.profile).requiresSetup)
    }

    func testUnconfiguredHealthyGoalDoesNotExposeSampleCountdownPercentageOrDate() {
        var profile = UserProfile.initial
        profile.isConfigured = true
        let snapshot = TimeProgressCalculator.snapshot(for: .healthyLife, profile: profile)
        let notSet = L10n.text("未設定", "Not set")

        XCTAssertTrue(snapshot.requiresSetup)
        XCTAssertFalse(snapshot.hasScheduledTime)
        XCTAssertEqual(snapshot.remainingFraction, 0)
        XCTAssertEqual(snapshot.percentageText, "—")
        XCTAssertEqual(snapshot.percentageRemainingText, notSet)
        XCTAssertEqual(snapshot.targetDateText(), notSet)
        XCTAssertTrue(snapshot.countdown.components.isEmpty)
        for style in MetricValueStyle.allCases {
            for compact in [false, true] {
                XCTAssertEqual(snapshot.valueText(style: style, compact: compact), notSet)
            }
            XCTAssertEqual(snapshot.secondarySummary(excluding: style), snapshot.context)
        }
        XCTAssertTrue(snapshot.accessibilitySummary.contains(notSet))
        XCTAssertFalse(snapshot.accessibilitySummary.contains("%"))
    }

    func testLegacyProfilesKeepTheirExistingHealthyGoalSetupState() throws {
        for wasConfigured in [false, true] {
            var profile = UserProfile.initial
            profile.isConfigured = wasConfigured
            profile.birthDate = Date(timeIntervalSince1970: 946_684_800)
            profile.healthyLifeYears = 83
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any])
            object.removeValue(forKey: "isHealthyLifeConfigured")
            let restored = try JSONDecoder().decode(UserProfile.self, from: JSONSerialization.data(withJSONObject: object))

            XCTAssertEqual(restored.isHealthyLifeConfigured, wasConfigured)
            XCTAssertEqual(restored.birthDate, profile.birthDate)
            XCTAssertEqual(restored.healthyLifeYears, profile.healthyLifeYears)
        }
    }

    func testExplicitWidgetSelectionsAfterDeferringShowSetupUntilBirthDateIsSaved() {
        var profile = UserProfile.initial
        profile.isConfigured = true
        let rows = DaysYetConfigurationIntent()
        rows.followsAppSelection = false
        rows.thirdMetric = .healthyLife
        let circles = DaysYetCircleConfigurationIntent()
        circles.firstMetric = .healthyLife

        let metrics = [rows.resolvedMetrics(profile: profile)[2], circles.resolvedMetrics(profile: profile)[0],
                       LockScreenMetricOption.healthyLife.resolved(profile: profile)]
        for metric in metrics {
            XCTAssertEqual(metric, .healthyLife)
            XCTAssertTrue(TimeProgressCalculator.snapshot(for: metric, profile: profile).requiresSetup)
        }
        profile.isHealthyLifeConfigured = true
        for metric in metrics {
            XCTAssertFalse(TimeProgressCalculator.snapshot(for: metric, profile: profile).requiresSetup)
        }
    }
}
