import Foundation

struct UserProfile: Codable, Equatable, Sendable {
    var birthDate: Date
    var healthyLifeYears: Double
    var customTargetName: String
    var customTargetDate: Date
    var dashboardMetrics: [MetricKind]
    var dashboardValueStyle: MetricValueStyle
    var isConfigured: Bool

    static var initial: UserProfile {
        let calendar = Calendar(identifier: .gregorian)
        let birthDate = calendar.date(from: DateComponents(year: 1990, month: 1, day: 1)) ?? .now
        let customTargetDate = calendar.date(byAdding: .year, value: 3, to: .now) ?? .now

        return UserProfile(
            birthDate: birthDate,
            healthyLifeYears: 75,
            // Keep the built-in default language-neutral. The UI and snapshots
            // supply a localized fallback until the user enters a custom name.
            customTargetName: "",
            customTargetDate: customTargetDate,
            dashboardMetrics: [.week, .month, .year],
            dashboardValueStyle: .remaining,
            isConfigured: false
        )
    }

    private enum CodingKeys: String, CodingKey {
        case birthDate
        case healthyLifeYears
        case customTargetName
        case customTargetDate
        case dashboardMetrics
        case dashboardValueStyle
        case isConfigured
    }

    init(
        birthDate: Date,
        healthyLifeYears: Double,
        customTargetName: String,
        customTargetDate: Date,
        dashboardMetrics: [MetricKind],
        dashboardValueStyle: MetricValueStyle,
        isConfigured: Bool
    ) {
        self.birthDate = birthDate
        self.healthyLifeYears = healthyLifeYears
        self.customTargetName = customTargetName
        self.customTargetDate = customTargetDate
        self.dashboardMetrics = dashboardMetrics
        self.dashboardValueStyle = dashboardValueStyle
        self.isConfigured = isConfigured
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        birthDate = try container.decode(Date.self, forKey: .birthDate)
        healthyLifeYears = try container.decode(Double.self, forKey: .healthyLifeYears)
        customTargetName = try container.decode(String.self, forKey: .customTargetName)
        customTargetDate = try container.decode(Date.self, forKey: .customTargetDate)
        dashboardMetrics = try container.decode([MetricKind].self, forKey: .dashboardMetrics)
        dashboardValueStyle = try container.decodeIfPresent(MetricValueStyle.self, forKey: .dashboardValueStyle) ?? .remaining
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
