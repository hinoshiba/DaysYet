import AppIntents
import WidgetKit

/// The circle widget has its own four slots; the app dashboard keeps three.
struct DaysYetCircleConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "widget.circle.configuration.title"
    static let description = IntentDescription("widget.circle.configuration.description")

    @Parameter(title: "widget.circle.configuration.first_metric", default: .week)
    var firstMetric: WidgetMetricOption

    @Parameter(title: "widget.circle.configuration.second_metric", default: .month)
    var secondMetric: WidgetMetricOption

    @Parameter(title: "widget.circle.configuration.third_metric", default: .year)
    var thirdMetric: WidgetMetricOption

    @Parameter(title: "widget.circle.configuration.fourth_metric", default: .activity)
    var fourthMetric: WidgetMetricOption

    @Parameter(title: "widget.configuration.value_style", default: .percentage)
    var valueStyle: WidgetValueStyleOption

    @Parameter(title: "widget.configuration.theme", default: .appSetting)
    var theme: WidgetThemeOption

    init() {
        firstMetric = .week
        secondMetric = .month
        thirdMetric = .year
        fourthMetric = .activity
        valueStyle = .percentage
        theme = .appSetting
    }

    func resolvedMetrics(profile: UserProfile) -> [MetricKind] {
        let requested = [firstMetric, secondMetric, thirdMetric, fourthMetric].map(\.metricKind)
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
}
