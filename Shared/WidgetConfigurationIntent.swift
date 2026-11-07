import AppIntents
import WidgetKit

struct DaysYetConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "widget.configuration.title"
    static let description = IntentDescription("widget.configuration.description")

    @Parameter(title: "widget.configuration.follows_app", default: true)
    var followsAppSelection: Bool

    @Parameter(title: "widget.configuration.first_metric", default: .month)
    var firstMetric: WidgetMetricOption

    @Parameter(title: "widget.configuration.second_metric", default: .year)
    var secondMetric: WidgetMetricOption

    @Parameter(title: "widget.configuration.third_metric", default: .healthyLife)
    var thirdMetric: WidgetMetricOption

    @Parameter(title: "widget.configuration.value_style", default: .appSetting)
    var valueStyle: WidgetValueStyleOption

    @Parameter(title: "widget.configuration.display_mode", default: .appSetting)
    var displayMode: WidgetDisplayModeOption

    @Parameter(title: "widget.configuration.theme", default: .appSetting)
    var theme: WidgetThemeOption

    init() {
        followsAppSelection = true
        firstMetric = .month
        secondMetric = .year
        thirdMetric = .healthyLife
        valueStyle = .appSetting
        displayMode = .appSetting
        theme = .appSetting
    }

    func resolvedLayout(profile: UserProfile) -> WidgetLayout {
        // Preserve existing widgets with a custom three-row selection.
        followsAppSelection ? profile.widgetLayout : .rows
    }

    func resolvedMetrics(profile: UserProfile) -> [MetricKind] {
        let requested: [MetricKind]
        if resolvedLayout(profile: profile) == .circles {
            requested = profile.circleWidgetSettings.normalizedMetrics
        } else if followsAppSelection {
            requested = profile.normalizedDashboardMetrics
        } else {
            requested = [
                firstMetric.resolved(appMetric: profile.normalizedDashboardMetrics[0]),
                secondMetric.resolved(appMetric: profile.normalizedDashboardMetrics[1]),
                thirdMetric.resolved(appMetric: profile.normalizedDashboardMetrics[2])
            ]
        }
        guard !profile.isConfigured else { return requested }

        // Personal reference points require onboarding; keep the slot count and order.
        var used = Set(requested.filter { $0 != .healthyLife && $0 != .customLife })
        return requested.map { metric in
            guard metric == .healthyLife || metric == .customLife else { return metric }
            let replacement = [MetricKind.week, .month, .year, .activity, .workday, .study]
                .first { !used.contains($0) } ?? .week
            used.insert(replacement)
            return replacement
        }
    }

    func resolvedValueStyle(profile: UserProfile) -> MetricValueStyle {
        valueStyle.resolved(profileStyle: resolvedLayout(profile: profile) == .circles
                            ? profile.circleWidgetSettings.valueStyle : profile.dashboardValueStyle)
    }

    func resolvedTheme(profile: UserProfile) -> WidgetTheme {
        theme.resolved(profileTheme: profile.widgetTheme)
    }
}
