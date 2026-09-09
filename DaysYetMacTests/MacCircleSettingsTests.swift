import XCTest
@testable import DaysYetMac

final class MacCircleSettingsTests: XCTestCase {
    func testDefaultAndIncompleteProfilesKeepAtLeastThreeUniqueCircles() {
        XCTAssertEqual(UserProfile.initial.macDashboardMetrics, [.week, .month, .year])

        var profile = UserProfile.initial
        profile.dashboardMetrics = []
        XCTAssertEqual(profile.macDashboardMetrics, [.week, .month, .year])
        profile.dashboardMetrics = [.workday, .workday, .month]
        XCTAssertEqual(profile.macDashboardMetrics, [.workday, .month, .week])
    }

    func testMacKeepsAllUniqueCirclesWhileIOSProjectionKeepsTheFirstThree() {
        var profile = UserProfile.initial
        profile.dashboardMetrics = [.workday, .month, .activity, .year, .month, .healthyLife, .customLife, .week]
        let expected: [MetricKind] = [.workday, .month, .activity, .year, .healthyLife, .customLife, .week]
        XCTAssertEqual(profile.macDashboardMetrics, expected)
        XCTAssertEqual(profile.normalizedDashboardMetrics, Array(expected.prefix(3)))
        XCTAssertEqual(profile.macWidgetMetrics(for: .left), expected)
        XCTAssertEqual(profile.macWidgetMetrics(for: .right), expected)
        XCTAssertEqual(profile.macWidgetMetrics(for: .top), Array(expected.prefix(3)))
    }

    func testDecodingAdditionalCirclesIgnoresUnknownKindsAndPreservesOrder() throws {
        let encoded = try JSONEncoder().encode(UserProfile.initial)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["dashboardMetrics"] = ["workday", "unknownFutureKind", "month", "activity", "year", "month"]
        let decoded = try JSONDecoder().decode(UserProfile.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.macDashboardMetrics, [.workday, .month, .activity, .year])
        XCTAssertEqual(decoded.normalizedDashboardMetrics, [.workday, .month, .activity])

        object.removeValue(forKey: "dashboardMetrics")
        let legacy = try JSONDecoder().decode(UserProfile.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(legacy.macDashboardMetrics, [.week, .month, .year])
    }

    @MainActor
    func testAppearanceUpdatesPersistAdditionalCirclesThroughARoundTrip() throws {
        var profile = UserProfile.initial
        profile.dashboardMetrics = [.workday, .month, .year, .activity, .customLife]
        var savedProfile: UserProfile?
        let store = ProfileStore(profile: profile, saveProfile: { savedProfile = $0 })

        store.update { $0.widgetDisplayMode = .countdown }

        let saved = try XCTUnwrap(savedProfile)
        XCTAssertEqual(saved.dashboardMetrics, profile.dashboardMetrics)
        let restored = try JSONDecoder().decode(UserProfile.self, from: JSONEncoder().encode(saved))
        XCTAssertEqual(restored.macDashboardMetrics, profile.dashboardMetrics)
        XCTAssertEqual(restored.widgetDisplayMode, .countdown)
    }

    @MainActor
    func testAddingAndRemovingCirclesEnforcesTheAvailableKindsAndMinimum() {
        var savedProfiles: [UserProfile] = []
        let store = ProfileStore(profile: .initial, saveProfile: { savedProfiles.append($0) })

        for _ in 3..<MetricKind.allCases.count {
            store.addMacDashboardMetric()
        }
        XCTAssertEqual(store.profile.dashboardMetrics, MetricKind.allCases)
        XCTAssertEqual(savedProfiles.count, MetricKind.allCases.count - 3)

        store.addMacDashboardMetric()
        store.removeMacDashboardMetric(at: -1)
        store.removeMacDashboardMetric(at: MetricKind.allCases.count)
        XCTAssertEqual(savedProfiles.count, MetricKind.allCases.count - 3)

        store.removeMacDashboardMetric(at: 1)
        XCTAssertEqual(store.profile.dashboardMetrics, MetricKind.allCases.filter { $0 != .month })
        while store.profile.macDashboardMetrics.count > 3 {
            store.removeMacDashboardMetric(at: store.profile.macDashboardMetrics.count - 1)
        }
        let finalMetrics = store.profile.macDashboardMetrics
        let finalSaveCount = savedProfiles.count
        store.removeMacDashboardMetric(at: 0)
        XCTAssertEqual(store.profile.macDashboardMetrics, finalMetrics)
        XCTAssertEqual(finalMetrics.count, 3)
        XCTAssertEqual(savedProfiles.count, finalSaveCount)
    }

    @MainActor
    func testSelectingAnExistingCircleAfterTheThirdSlotSwapsItsPosition() {
        var profile = UserProfile.initial
        profile.dashboardMetrics = [.week, .month, .year, .activity, .workday]
        var savedProfiles: [UserProfile] = []
        let store = ProfileStore(profile: profile, saveProfile: { savedProfiles.append($0) })

        store.setDashboardMetric(.week, at: 4)
        XCTAssertEqual(store.profile.dashboardMetrics, [.workday, .month, .year, .activity, .week])
        XCTAssertEqual(store.profile.macWidgetMetrics(for: .top), [.workday, .month, .year])
        store.setDashboardMetric(.healthyLife, at: 3)
        XCTAssertEqual(store.profile.dashboardMetrics, [.workday, .month, .year, .healthyLife, .week])

        store.setDashboardMetric(.customLife, at: 5)
        store.setDashboardMetric(.customLife, at: -1)
        XCTAssertEqual(savedProfiles.count, 2)
        XCTAssertEqual(savedProfiles.last?.dashboardMetrics, store.profile.dashboardMetrics)
    }
}
