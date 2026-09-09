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

struct ActivitySchedule: Codable, Equatable, Sendable {
    /// Empty names use the metric's localized default label.
    var name: String
    /// Wall-clock minutes in the device's current time zone.
    var startMinute: Int
    var endMinute: Int
    /// Foundation weekday numbers; overnight activity belongs to its start day.
    var activeWeekdays: Set<Int>

    static let daily = ActivitySchedule(startMinute: 7 * 60, endMinute: 23 * 60)
    static let work = ActivitySchedule(startMinute: 9 * 60, endMinute: 18 * 60, activeWeekdays: Set(2...6))

    init(name: String = "", startMinute: Int, endMinute: Int, activeWeekdays: Set<Int> = Set(1...7)) {
        self.name = name
        self.startMinute = UserProfile.clampedWorkMinute(startMinute)
        self.endMinute = UserProfile.clampedWorkMinute(endMinute)
        self.activeWeekdays = activeWeekdays.intersection(1...7)
    }

    private enum CodingKeys: String, CodingKey {
        case name, startMinute, endMinute, activeWeekdays
    }

    init(from decoder: Decoder) throws {
        try self.init(from: decoder, defaults: .daily)
    }

    init(from decoder: Decoder, defaults: ActivitySchedule) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            name: (try? container.decode(String.self, forKey: .name)) ?? defaults.name,
            startMinute: (try? container.decode(Int.self, forKey: .startMinute)) ?? defaults.startMinute,
            endMinute: (try? container.decode(Int.self, forKey: .endMinute)) ?? defaults.endMinute,
            activeWeekdays: (try? container.decode(Set<Int>.self, forKey: .activeWeekdays)) ?? defaults.activeWeekdays
        )
    }

    var normalized: ActivitySchedule {
        ActivitySchedule(name: name, startMinute: startMinute, endMinute: endMinute, activeWeekdays: activeWeekdays)
    }
}

struct UserProfile: Codable, Equatable, Sendable {
    var birthDate: Date
    var healthyLifeYears: Double
    var customTargetName: String
    var customTargetStartDate: Date
    var customTargetDate: Date
    var dailyActivity: ActivitySchedule
    var workActivity: ActivitySchedule
    var weekStartDay: WeekStartDay
    var dashboardMetrics: [MetricKind]
    var widgetDisplayMode: WidgetDisplayMode
    var dashboardValueStyle: MetricValueStyle
    var widgetTheme: WidgetTheme
    var isConfigured: Bool

    // Preserve existing editor and migration call sites while storing one schedule.
    var workStartMinute: Int {
        get { workActivity.startMinute }
        set { workActivity.startMinute = Self.clampedWorkMinute(newValue) }
    }

    var workEndMinute: Int {
        get { workActivity.endMinute }
        set { workActivity.endMinute = Self.clampedWorkMinute(newValue) }
    }

    func activitySchedule(for kind: MetricKind) -> ActivitySchedule {
        kind == .workday ? workActivity : dailyActivity
    }

    mutating func updateActivitySchedule(for kind: MetricKind, _ mutation: (inout ActivitySchedule) -> Void) {
        guard kind.isActivity else { return }
        var schedule = activitySchedule(for: kind)
        mutation(&schedule)
        if kind == .workday {
            workActivity = schedule.normalized
        } else {
            dailyActivity = schedule.normalized
        }
    }

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
        case dailyActivity
        case workActivity
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
        weekStartDay: WeekStartDay = .system,
        dailyActivity: ActivitySchedule = .daily,
        workActivity: ActivitySchedule? = nil
    ) {
        self.birthDate = birthDate
        self.healthyLifeYears = healthyLifeYears
        self.customTargetName = customTargetName
        self.customTargetStartDate = customTargetStartDate
        self.customTargetDate = customTargetDate
        self.dailyActivity = dailyActivity.normalized
        self.workActivity = workActivity?.normalized ?? ActivitySchedule(
            startMinute: workStartMinute, endMinute: workEndMinute, activeWeekdays: ActivitySchedule.work.activeWeekdays
        )
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
        // Profiles from the daily-only work-hours feature must retain their
        // original clocks and enabled weekends. Only new installs default to weekdays.
        let legacyWork = ActivitySchedule(
            startMinute: (try? container.decode(Int.self, forKey: .workStartMinute)) ?? 9 * 60,
            endMinute: (try? container.decode(Int.self, forKey: .workEndMinute)) ?? 18 * 60
        )
        dailyActivity = (try? ActivitySchedule(from: container.superDecoder(forKey: .dailyActivity), defaults: .daily)) ?? .daily
        workActivity = (try? ActivitySchedule(from: container.superDecoder(forKey: .workActivity), defaults: .work)) ?? legacyWork
        // Keep the existing device-calendar behavior for older profiles and
        // ignore unrecognized future values without losing other preferences.
        weekStartDay = (try? container.decode(WeekStartDay.self, forKey: .weekStartDay)) ?? .system
        // Older profiles used the birth date as the implicit milestone origin.
        // Preserve that progress when introducing an explicit start date.
        customTargetStartDate = try container.decodeIfPresent(Date.self, forKey: .customTargetStartDate) ?? birthDate
        dashboardMetrics = (try? container.decode([String].self, forKey: .dashboardMetrics))?
            .compactMap(MetricKind.init(rawValue:)) ?? [.week, .month, .year]
        widgetDisplayMode = (try? container.decode(WidgetDisplayMode.self, forKey: .widgetDisplayMode)) ?? .progressBars
        dashboardValueStyle = (try? container.decode(MetricValueStyle.self, forKey: .dashboardValueStyle)) ?? .remaining
        widgetTheme = (try? container.decode(WidgetTheme.self, forKey: .widgetTheme)) ?? .vividNight
        isConfigured = try container.decode(Bool.self, forKey: .isConfigured)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(birthDate, forKey: .birthDate)
        try container.encode(healthyLifeYears, forKey: .healthyLifeYears)
        try container.encode(customTargetName, forKey: .customTargetName)
        try container.encode(customTargetStartDate, forKey: .customTargetStartDate)
        try container.encode(customTargetDate, forKey: .customTargetDate)
        try container.encode(dailyActivity.normalized, forKey: .dailyActivity)
        try container.encode(workActivity.normalized, forKey: .workActivity)
        // Keep clock fields readable by an older app/extension sharing this store.
        try container.encode(workStartMinute, forKey: .workStartMinute)
        try container.encode(workEndMinute, forKey: .workEndMinute)
        try container.encode(weekStartDay, forKey: .weekStartDay)
        try container.encode(dashboardMetrics, forKey: .dashboardMetrics)
        try container.encode(widgetDisplayMode, forKey: .widgetDisplayMode)
        try container.encode(dashboardValueStyle, forKey: .dashboardValueStyle)
        try container.encode(widgetTheme, forKey: .widgetTheme)
        try container.encode(isConfigured, forKey: .isConfigured)
    }

    var normalizedDashboardMetrics: [MetricKind] {
        Array(macDashboardMetrics.prefix(3))
    }

    /// macOS can show every chosen timeline; iOS keeps its three-slot layout.
    var macDashboardMetrics: [MetricKind] {
        var unique = dashboardMetrics.reduce(into: [MetricKind]()) { result, metric in
            if !result.contains(metric) { result.append(metric) }
        }
        for metric in MetricKind.allCases where unique.count < 3 && !unique.contains(metric) {
            unique.append(metric)
        }
        return unique
    }

    static func clampedWorkMinute(_ minute: Int) -> Int {
        min(max(minute, 0), 24 * 60 - 1)
    }
}
