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
}
