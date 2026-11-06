import AppIntents
import WidgetKit

/// Circle timelines and value style are independent; the app theme is shared.
struct DaysYetCircleConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "widget.circle.configuration.title"
    static let description = IntentDescription("widget.circle.configuration.description")

    @Parameter(title: "widget.circle.configuration.count", default: .appSetting)
    var count: CircleWidgetCountOption

    @Parameter(title: "widget.circle.configuration.first_metric", default: .appSetting)
    var firstMetric: WidgetMetricOption

    @Parameter(title: "widget.circle.configuration.second_metric", default: .appSetting)
    var secondMetric: WidgetMetricOption

    @Parameter(title: "widget.circle.configuration.third_metric", default: .appSetting)
    var thirdMetric: WidgetMetricOption

    @Parameter(title: "widget.circle.configuration.fourth_metric", default: .appSetting)
    var fourthMetric: WidgetMetricOption

    @Parameter(title: "widget.circle.configuration.fifth_metric", default: .appSetting)
    var fifthMetric: WidgetMetricOption

    @Parameter(title: "widget.circle.configuration.sixth_metric", default: .appSetting)
    var sixthMetric: WidgetMetricOption

    @Parameter(title: "widget.circle.configuration.seventh_metric", default: .appSetting)
    var seventhMetric: WidgetMetricOption

    @Parameter(title: "widget.circle.configuration.eighth_metric", default: .appSetting)
    var eighthMetric: WidgetMetricOption

    @Parameter(title: "widget.circle.configuration.value_style", default: .appSetting)
    var valueStyle: WidgetValueStyleOption

    @Parameter(title: "widget.configuration.theme", default: .appSetting)
    var theme: WidgetThemeOption

    init() {
        count = .appSetting
        firstMetric = .appSetting
        secondMetric = .appSetting
        thirdMetric = .appSetting
        fourthMetric = .appSetting
        fifthMetric = .appSetting
        sixthMetric = .appSetting
        seventhMetric = .appSetting
        eighthMetric = .appSetting
        valueStyle = .appSetting
        theme = .appSetting
    }

    func resolvedMetrics(profile: UserProfile) -> [MetricKind] {
        let appMetrics = profile.circleWidgetSettings.normalizedMetrics
        let options = [firstMetric, secondMetric, thirdMetric, fourthMetric,
                       fifthMetric, sixthMetric, seventhMetric, eighthMetric]
        let requested = options.prefix(count.resolved(appCount: appMetrics.count)).enumerated().map { index, option in
            option.resolved(appMetric: appMetrics.indices.contains(index)
                            ? appMetrics[index] : CircleWidgetSettings.slotDefaults[index])
        }
        guard !profile.isConfigured else { return requested }

        // Before onboarding, avoid displaying a sample birth date or milestone.
        // Keep every position, including repeated explicitly selected metrics.
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
        theme.resolved(profileTheme: profile.widgetTheme)
    }

    func resolvedCustomColors(profile: UserProfile) -> [MetricKind: WidgetColor] {
        // An explicitly selected widget template keeps its original colors.
        theme == .appSetting ? profile.resolvedCircleWidgetCustomColors : [:]
    }
}

enum CircleWidgetCountOption: String, AppEnum {
    case appSetting, one, two, three, four, five, six, seven, eight

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "widget.circle.configuration.count"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .appSetting: "widget.option.app_setting",
        .one: "1", .two: "2", .three: "3", .four: "4",
        .five: "5", .six: "6", .seven: "7", .eight: "8"
    ]

    func resolved(appCount: Int) -> Int {
        let explicitCounts: [Self: Int] = [.one: 1, .two: 2, .three: 3, .four: 4,
                                         .five: 5, .six: 6, .seven: 7, .eight: 8]
        return min(max(explicitCounts[self] ?? appCount, 1), CircleWidgetSettings.maximumCount)
    }
}
