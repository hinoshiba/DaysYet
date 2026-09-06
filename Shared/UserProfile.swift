import Foundation

enum WeekStartDay: Int, Codable, CaseIterable, Identifiable, Sendable {
    case system = 0
    // Foundation Calendar numbers weekdays from Sunday (1) to Saturday (7).
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .system: L10n.text("端末の設定に合わせる", "Use device setting")
        case .sunday: L10n.text("日曜日", "Sunday")
        case .monday: L10n.text("月曜日", "Monday")
        case .tuesday: L10n.text("火曜日", "Tuesday")
        case .wednesday: L10n.text("水曜日", "Wednesday")
        case .thursday: L10n.text("木曜日", "Thursday")
        case .friday: L10n.text("金曜日", "Friday")
        case .saturday: L10n.text("土曜日", "Saturday")
        }
    }

    func resolvedWeekday(in calendar: Calendar) -> Int {
        self == .system ? calendar.firstWeekday : rawValue
    }

    func resolvedTitle(in calendar: Calendar = .autoupdatingCurrent) -> String {
        (WeekStartDay(rawValue: resolvedWeekday(in: calendar)) ?? .sunday).title
    }
}

struct UserProfile: Codable, Equatable, Sendable {
    var birthDate: Date
    var healthyLifeYears: Double
    var customTargetName: String
    var customTargetStartDate: Date
    var customTargetDate: Date
    /// Wall-clock minutes in the device's current time zone, repeated daily.
    var workStartMinute: Int
    var workEndMinute: Int
    var weekStartDay: WeekStartDay
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
        case workStartMinute
        case workEndMinute
        case weekStartDay
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
        isConfigured: Bool,
        workStartMinute: Int = 9 * 60,
        workEndMinute: Int = 18 * 60,
        weekStartDay: WeekStartDay = .system
    ) {
        self.birthDate = birthDate
        self.healthyLifeYears = healthyLifeYears
        self.customTargetName = customTargetName
        self.customTargetStartDate = customTargetStartDate
        self.customTargetDate = customTargetDate
        self.workStartMinute = Self.clampedWorkMinute(workStartMinute)
        self.workEndMinute = Self.clampedWorkMinute(workEndMinute)
        self.weekStartDay = weekStartDay
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
        workStartMinute = Self.clampedWorkMinute(
            (try? container.decode(Int.self, forKey: .workStartMinute)) ?? 9 * 60
        )
        workEndMinute = Self.clampedWorkMinute(
            (try? container.decode(Int.self, forKey: .workEndMinute)) ?? 18 * 60
        )
        // Keep the existing device-calendar behavior for older profiles and
        // ignore unrecognized future values without losing other preferences.
        weekStartDay = (try? container.decode(WeekStartDay.self, forKey: .weekStartDay)) ?? .system
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

    static func clampedWorkMinute(_ minute: Int) -> Int {
        min(max(minute, 0), 24 * 60 - 1)
    }
}
