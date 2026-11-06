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
        profile.widgetTheme = .softDawn
        profile.circleWidgetSettings = CircleWidgetSettings(
            metrics: [.study, .workday, .activity, .customLife], valueStyle: .targetDate
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
        profile.widgetTheme = .softDawn
        XCTAssertEqual(configuration.resolvedTheme(profile: profile), .softDawn)
        configuration.theme = .quietForest
        configuration.valueStyle = .remaining
        XCTAssertEqual(configuration.resolvedTheme(profile: profile), .quietForest)
        XCTAssertEqual(configuration.resolvedValueStyle(profile: profile), .remaining)
    }

    func testExistingExplicitWidgetChoicesRemainIndependentOfNewAppSettings() throws {
        var profile = UserProfile.initial
        profile.isConfigured = true
        profile.widgetTheme = .softDawn
        profile.circleWidgetSettings = CircleWidgetSettings(
            metrics: [.study, .study, .study, .study], valueStyle: .targetDate
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
        profile.widgetTheme = .softDawn
        XCTAssertEqual(configuration.resolvedCustomColors(profile: profile), [.week: rowColor, .month: circleColor])
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
        profile.widgetTheme = .quietForest
        profile.circleWidgetSettings = CircleWidgetSettings(
            metrics: [.study, .study, .workday, .workday], valueStyle: .remaining
        )
        let decoded = try JSONDecoder().decode(UserProfile.self, from: JSONEncoder().encode(profile))
        XCTAssertEqual(decoded, profile)
        XCTAssertEqual(DaysYetCircleConfigurationIntent().resolvedTheme(profile: decoded), .quietForest)
    }

    func testLegacyCircleThemeUsesSharedThemeWithoutChangingCircleContent() throws {
        var profile = UserProfile.initial
        profile.widgetTheme = .calmSea
        profile.circleWidgetSettings = CircleWidgetSettings(
            metrics: [.study, .study, .workday], valueStyle: .remaining
        )
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any])
        var circle = try XCTUnwrap(object["circleWidgetSettings"] as? [String: Any])
        circle["theme"] = WidgetTheme.quietForest.rawValue
        object["circleWidgetSettings"] = circle

        let decoded = try JSONDecoder().decode(UserProfile.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded, profile)
        XCTAssertEqual(DaysYetCircleConfigurationIntent().resolvedTheme(profile: decoded), .calmSea)
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any])
        let savedCircle = try XCTUnwrap(saved["circleWidgetSettings"] as? [String: Any])
        XCTAssertNil(savedCircle["theme"])
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
        XCTAssertEqual(decoded.circleWidgetSettings.normalizedMetrics, [.study, .month, .workday])
        XCTAssertEqual(decoded.circleWidgetSettings.valueStyle, .percentage)
        XCTAssertEqual(DaysYetCircleConfigurationIntent().resolvedTheme(profile: decoded), profile.widgetTheme)
        XCTAssertEqual(decoded.customTargetName, profile.customTargetName)

        object["circleWidgetSettings"] = "invalid"
        decoded = try JSONDecoder().decode(UserProfile.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded, profile)
    }

    func testMetricNormalizationPreservesOneToEightPositionsAndRepeatedSelections() {
        XCTAssertEqual(CircleWidgetSettings(metrics: [.study, .study]).normalizedMetrics, [.study, .study])
        XCTAssertEqual(
            CircleWidgetSettings(metrics: [.study, .study, .workday, .workday, .month]).normalizedMetrics,
            [.study, .study, .workday, .workday, .month]
        )
        XCTAssertEqual(CircleWidgetSettings(metrics: []).normalizedMetrics, CircleWidgetSettings.defaultMetrics)
        XCTAssertEqual(CircleWidgetSettings(metrics: Array(repeating: .study, count: 12)).normalizedMetrics.count, 8)
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
        XCTAssertEqual(saved?.circleWidgetSettings.metrics, [.workday])
    }

    func testEightCirclesRoundTripAndResolveExtraOverrides() throws {
        var profile = UserProfile.initial
        profile.isConfigured = true
        profile.circleWidgetSettings.metrics = [.study, .month, .year, .activity, .workday, .study, .customLife, .healthyLife]
        let decoded = try JSONDecoder().decode(UserProfile.self, from: JSONEncoder().encode(profile))
        XCTAssertEqual(decoded.circleWidgetSettings.metrics, profile.circleWidgetSettings.metrics)

        let configuration = DaysYetCircleConfigurationIntent()
        XCTAssertEqual(configuration.resolvedMetrics(profile: decoded), profile.circleWidgetSettings.metrics)
        XCTAssertEqual(configuration.$count.defaultValue, .appSetting)
        XCTAssertEqual(configuration.$eighthMetric.defaultValue, .appSetting)
        configuration.fifthMetric = .week
        configuration.eighthMetric = .month
        XCTAssertEqual(configuration.resolvedMetrics(profile: decoded), [.study, .month, .year, .activity, .week, .study, .customLife, .month])

        configuration.count = .four
        XCTAssertEqual(configuration.resolvedMetrics(profile: decoded), Array(profile.circleWidgetSettings.metrics.prefix(4)))
        configuration.count = .one
        XCTAssertEqual(configuration.resolvedMetrics(profile: decoded), [.study])
    }

    func testExplicitCountFillsAdditionalSlotsAndProtectsPersonalDefaultsBeforeOnboarding() {
        var profile = UserProfile.initial
        profile.circleWidgetSettings.metrics = [.month]
        let configuration = DaysYetCircleConfigurationIntent()
        configuration.count = .eight
        configuration.eighthMetric = .customLife
        let metrics = configuration.resolvedMetrics(profile: profile)
        XCTAssertEqual(metrics.count, 8)
        XCTAssertEqual(metrics.first, .month)
        XCTAssertFalse(metrics.contains(.healthyLife))
        XCTAssertFalse(metrics.contains(.customLife))

        profile.isConfigured = true
        XCTAssertEqual(configuration.resolvedMetrics(profile: profile).last, .customLife)
    }

    func testFamilyLayoutsKeepAllVisibleCirclesWithinTheirCells() {
        for count in 1...8 {
            for size in CircleWidgetSize.allCases {
                let available = size == .medium ? CGSize(width: 288, height: 126) : CGSize(width: 136, height: 136)
                let layout = CircleWidgetGridLayout(size: size, metricCount: count)
                XCTAssertEqual(layout.count, min(count, size == .small ? 4 : 8))
                XCTAssertGreaterThanOrEqual(layout.columns * layout.rows, layout.count)
                let cell = layout.cellSize(in: available)
                XCTAssertGreaterThan(cell.width, 0)
                XCTAssertGreaterThan(cell.height, 0)
                XCTAssertEqual(cell.width * CGFloat(layout.columns) + layout.spacing * CGFloat(layout.columns - 1), available.width, accuracy: 0.001)
                XCTAssertEqual(cell.height * CGFloat(layout.rows) + layout.spacing * CGFloat(layout.rows - 1), available.height, accuracy: 0.001)
            }
        }
        let wide = CircleWidgetGridLayout(size: .medium, metricCount: 8)
        XCTAssertEqual(wide.columns, 4)
        XCTAssertEqual(wide.rows, 2)
        let original = CircleWidgetGridLayout(size: .small, metricCount: 4)
        XCTAssertEqual(original.columns, 2)
        XCTAssertEqual(original.rows, 2)
    }

    @MainActor
    func testAddReorderAndDeletePersistTheDisplayedOrderAndEnforceLimits() throws {
        var saved: UserProfile?
        var saveCount = 0
        let store = ProfileStore(profile: .initial, appliesLaunchArguments: false) {
            saved = $0
            saveCount += 1
        }
        for metric in [MetricKind.study, .workday, .study, .customLife] {
            store.addCircleWidgetMetric(metric)
        }
        XCTAssertEqual(store.profile.circleWidgetSettings.metrics.count, 8)
        store.addCircleWidgetMetric(.week)
        XCTAssertEqual(saveCount, 4)

        store.moveCircleWidgetMetrics(from: IndexSet(integer: 7), to: 0)
        XCTAssertEqual(store.profile.circleWidgetSettings.metrics, [.customLife, .week, .month, .year, .activity, .study, .workday, .study])
        store.removeCircleWidgetMetrics(at: IndexSet([1, 3, 5]))
        XCTAssertEqual(store.profile.circleWidgetSettings.metrics, [.customLife, .month, .activity, .workday, .study])
        store.removeCircleWidgetMetrics(at: IndexSet(integersIn: 1..<5))
        XCTAssertEqual(store.profile.circleWidgetSettings.metrics, [.customLife])
        let lastSaveCount = saveCount
        store.removeCircleWidgetMetrics(at: IndexSet(integer: 0))
        store.removeCircleWidgetMetrics(at: IndexSet(integer: 10))
        store.moveCircleWidgetMetrics(from: IndexSet(integer: 5), to: 0)
        store.moveCircleWidgetMetrics(from: IndexSet(integer: 0), to: 10)
        XCTAssertEqual(saveCount, lastSaveCount)
        let decoded = try JSONDecoder().decode(UserProfile.self, from: JSONEncoder().encode(XCTUnwrap(saved)))
        XCTAssertEqual(decoded.circleWidgetSettings.metrics, [.customLife])
        XCTAssertEqual(decoded.dashboardMetrics, UserProfile.initial.dashboardMetrics)
    }

    @MainActor
    func testChoosingAnExistingTimeSwapsRowsWithoutChangingItsSettings() {
        var profile = UserProfile.initial
        profile.dashboardMetrics = [.week, .workday, .year]
        profile.workActivity.name = "Configured in Times"
        profile.workActivity.activeWeekdays = [2, 3]
        var saves = 0
        let store = ProfileStore(profile: profile, appliesLaunchArguments: false, saveProfile: { _ in saves += 1 })

        store.setDashboardMetric(.workday, at: 0)
        XCTAssertEqual(store.profile.dashboardMetrics, [.workday, .week, .year])
        XCTAssertEqual(store.profile.workActivity, profile.workActivity)
        XCTAssertEqual(store.profile.circleWidgetSettings, profile.circleWidgetSettings)
        XCTAssertEqual(saves, 1)
        store.setDashboardMetric(.month, at: -1)
        store.setDashboardMetric(.month, at: 99)
        XCTAssertEqual(saves, 1)

        store.addCircleWidgetMetric(.workday)
        store.setCircleWidgetMetric(.study, at: 0)
        XCTAssertEqual(store.profile.workActivity, profile.workActivity)
        XCTAssertEqual(store.profile.studySchedule, profile.studySchedule)
        XCTAssertEqual(store.profile.circleWidgetSettings.metrics, [.study, .month, .year, .activity, .workday])
    }

    @MainActor
    func testLibrarySaveUpdatesOnlyTheChosenSharedTime() {
        let profile = UserProfile.initial
        var draft = profile
        draft.workActivity.name = "Shared time"
        draft.widgetTheme = .calmSea
        draft.circleWidgetSettings.metrics = [.workday]
        let store = ProfileStore(profile: profile, appliesLaunchArguments: false, saveProfile: { _ in })
        store.saveMetricSettings(.workday, from: draft)
        XCTAssertEqual(store.profile.workActivity, draft.workActivity)
        XCTAssertEqual(store.profile.dashboardMetrics, profile.dashboardMetrics)
        XCTAssertEqual(store.profile.circleWidgetSettings, profile.circleWidgetSettings)
        XCTAssertEqual(store.profile.widgetTheme, profile.widgetTheme)
    }

    @MainActor
    func testDraftOnlySavesChosenTimelineSettingsOnCommit() {
        var saveCount = 0
        let store = ProfileStore(profile: .initial, appliesLaunchArguments: false, saveProfile: { _ in saveCount += 1 })
        let draft = ProfileStore(profile: store.profile, appliesLaunchArguments: false, saveProfile: { _ in })
        draft.update {
            $0.workActivity.name = "Night shift"
            $0.workActivity.startMinute = 22 * 60
            $0.workActivity.endMinute = 6 * 60
            $0.workActivity.activeWeekdays = [2, 4]
            $0.dailyActivity.name = "Unselected draft"
            $0.widgetTheme = .softDawn
        }
        XCTAssertEqual(saveCount, 0)
        XCTAssertEqual(store.profile.workActivity, UserProfile.initial.workActivity)
        store.saveMetricSettings(.workday, from: draft.profile)
        XCTAssertEqual(saveCount, 1)
        XCTAssertEqual(store.profile.workActivity, draft.profile.workActivity)
        XCTAssertEqual(store.profile.dailyActivity, UserProfile.initial.dailyActivity)
        XCTAssertEqual(store.profile.widgetTheme, UserProfile.initial.widgetTheme)
        XCTAssertEqual(store.profile.circleWidgetSettings, UserProfile.initial.circleWidgetSettings)
    }

    func testCompactCircleDefaultsDoNotRenameCustomLabelsOrAccessibilityTitles() {
        var profile = UserProfile.initial
        profile.dailyActivity.name = ""
        XCTAssertEqual(MetricKind.activity.circleTitle(profile: profile), L10n.text("活動", "Activity"))
        XCTAssertEqual(MetricKind.healthyLife.circleTitle(profile: profile), L10n.text("健康目標", "Health goal"))
        let custom = "家族と過ごす大切な時間 📚 International"
        profile.dailyActivity.name = custom
        profile.workActivity.name = custom
        profile.studySchedule.name = custom
        profile.customTargetName = custom
        for kind in [MetricKind.activity, .workday, .study, .customLife] {
            let snapshot = TimeProgressCalculator.snapshot(for: kind, profile: profile)
            XCTAssertEqual(snapshot.circleTitle, custom)
            XCTAssertEqual(snapshot.title, custom)
            XCTAssertTrue(snapshot.accessibilitySummary.hasPrefix(custom))
        }
        profile.dailyActivity.name = "  \n "
        XCTAssertEqual(MetricKind.activity.circleTitle(profile: profile), L10n.text("活動", "Activity"))
    }

    func testCircleTextFramesStayInsideTheRingAcrossSupportedSizes() {
        for diameter in stride(from: 56.0, through: 180.0, by: 1) {
            for textScale in [1.0, 2.0, 3.0] {
                for lines in [1, 2] {
                    let layout = CircleWidgetTextLayout(
                        diameter: diameter,
                        labelSize: 11 * textScale,
                        valueSize: 16 * textScale,
                        valueLineLimit: lines,
                        isPercentage: lines == 1
                    )
                    let safeDiameter = diameter - 2 * layout.lineWidth - 4
                    XCTAssertLessThanOrEqual(
                        hypot(layout.contentWidth, layout.contentHeight), safeDiameter + 0.001
                    )
                    XCTAssertGreaterThan(layout.contentWidth, 0)
                    XCTAssertGreaterThan(layout.valueHeight, 0)
                    XCTAssertGreaterThanOrEqual(layout.labelSize, 11)
                    XCTAssertEqual(layout.labelHeight + layout.spacing + layout.valueHeight, layout.contentHeight, accuracy: 0.001)
                }
            }
        }
    }

}
