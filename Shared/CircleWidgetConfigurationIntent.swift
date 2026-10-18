import AppIntents
import WidgetKit

/// The circle widget has its own four slots; the app dashboard keeps three.
struct DaysYetCircleConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "widget.circle.configuration.title"
    static let description = IntentDescription("widget.circle.configuration.description")

    @Parameter(title: "widget.circle.configuration.first_metric", default: .appSetting)
    var firstMetric: WidgetMetricOption

    @Parameter(title: "widget.circle.configuration.second_metric", default: .appSetting)
    var secondMetric: WidgetMetricOption

    @Parameter(title: "widget.circle.configuration.third_metric", default: .appSetting)
    var thirdMetric: WidgetMetricOption

    @Parameter(title: "widget.circle.configuration.fourth_metric", default: .appSetting)
    var fourthMetric: WidgetMetricOption

    @Parameter(title: "widget.circle.configuration.value_style", default: .appSetting)
    var valueStyle: WidgetValueStyleOption

    @Parameter(title: "widget.configuration.theme", default: .appSetting)
    var theme: WidgetThemeOption

    init() {
        firstMetric = .appSetting
        secondMetric = .appSetting
        thirdMetric = .appSetting
        fourthMetric = .appSetting
        valueStyle = .appSetting
        theme = .appSetting
    }

    func resolvedMetrics(profile: UserProfile) -> [MetricKind] {
        let appMetrics = profile.circleWidgetSettings.normalizedMetrics
        let requested = [firstMetric, secondMetric, thirdMetric, fourthMetric].enumerated().map { index, option in
            option.resolved(appMetric: appMetrics[index])
        }
        guard !profile.isConfigured else { return requested }

        // Before onboarding, avoid displaying a sample birth date or milestone.
        // Keep all four positions, including repeated explicitly selected metrics.
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
        valueStyle.resolved(profileStyle: profile.circleWidgetSettings.valueStyle)
    }

    func resolvedTheme(profile: UserProfile) -> WidgetTheme {
        theme.resolved(profileTheme: profile.circleWidgetSettings.theme ?? profile.widgetTheme)
    }

    func resolvedCustomColors(profile: UserProfile) -> [MetricKind: WidgetColor] {
        // An explicitly selected widget template keeps its original colors.
        theme == .appSetting ? profile.resolvedCircleWidgetCustomColors : [:]
    }
}
