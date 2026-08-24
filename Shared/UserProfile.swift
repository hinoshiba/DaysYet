import Foundation

struct UserProfile: Codable, Equatable, Sendable {
    var birthDate: Date
    var healthyLifeYears: Double
    var customTargetName: String
    var customTargetStartDate: Date
    var customTargetDate: Date
    var dashboardMetrics: [MetricKind]
    var widgetDisplayMode: WidgetDisplayMode
    var dashboardValueStyle: MetricValueStyle
    var widgetTheme: WidgetTheme
    var isConfigured: Bool

    static var initial: UserProfile {
        let calendar = Calendar(identifier: .gregorian)
        let birthDate = calendar.date(from: DateComponents(year: 1990, month: 1, day: 1)) ?? .now
        let now = Date.now
        let milestoneStartDate = Calendar.autoupdatingCurrent.startOfDay(for: now)
        let customTargetDate = calendar.date(byAdding: .year, value: 3, to: now) ?? now

        return UserProfile(
            birthDate: birthDate,
            healthyLifeYears: 75,
            // Keep the built-in default language-neutral. The UI and snapshots
            // supply a localized fallback until the user enters a custom name.
            customTargetName: "",
            customTargetStartDate: milestoneStartDate,
            customTargetDate: customTargetDate,
            dashboardMetrics: [.week, .month, .year],
            widgetDisplayMode: .progressBars,
            dashboardValueStyle: .remaining,
            widgetTheme: .vividNight,
            isConfigured: false
        )
    }

    private enum CodingKeys: String, CodingKey {
        case birthDate
        case healthyLifeYears
        case customTargetName
        case customTargetStartDate
        case customTargetDate
        case dashboardMetrics
        case widgetDisplayMode
        case dashboardValueStyle
        case widgetTheme
        case isConfigured
    }

    init(
        birthDate: Date,
        healthyLifeYears: Double,
        customTargetName: String,
        customTargetStartDate: Date,
        customTargetDate: Date,
        dashboardMetrics: [MetricKind],
        widgetDisplayMode: WidgetDisplayMode,
        dashboardValueStyle: MetricValueStyle,
        widgetTheme: WidgetTheme,
        isConfigured: Bool
    ) {
        self.birthDate = birthDate
        self.healthyLifeYears = healthyLifeYears
        self.customTargetName = customTargetName
        self.customTargetStartDate = customTargetStartDate
        self.customTargetDate = customTargetDate
        self.dashboardMetrics = dashboardMetrics
        self.widgetDisplayMode = widgetDisplayMode
        self.dashboardValueStyle = dashboardValueStyle
        self.widgetTheme = widgetTheme
        self.isConfigured = isConfigured
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        birthDate = try container.decode(Date.self, forKey: .birthDate)
        healthyLifeYears = try container.decode(Double.self, forKey: .healthyLifeYears)
        customTargetName = try container.decode(String.self, forKey: .customTargetName)
        customTargetDate = try container.decode(Date.self, forKey: .customTargetDate)
        // Older profiles used the birth date as the implicit milestone origin.
        // Preserve that progress when introducing an explicit start date.
        customTargetStartDate = try container.decodeIfPresent(Date.self, forKey: .customTargetStartDate) ?? birthDate
        dashboardMetrics = try container.decode([MetricKind].self, forKey: .dashboardMetrics)
        widgetDisplayMode = (try? container.decode(WidgetDisplayMode.self, forKey: .widgetDisplayMode)) ?? .progressBars
        dashboardValueStyle = try container.decodeIfPresent(MetricValueStyle.self, forKey: .dashboardValueStyle) ?? .remaining
        widgetTheme = (try? container.decode(WidgetTheme.self, forKey: .widgetTheme)) ?? .vividNight
        isConfigured = try container.decode(Bool.self, forKey: .isConfigured)
    }

    var normalizedDashboardMetrics: [MetricKind] {
        var unique = dashboardMetrics.reduce(into: [MetricKind]()) { result, metric in
            if !result.contains(metric) { result.append(metric) }
        }
        for metric in MetricKind.allCases where unique.count < 3 && !unique.contains(metric) {
            unique.append(metric)
        }
        return Array(unique.prefix(3))
    }
}
