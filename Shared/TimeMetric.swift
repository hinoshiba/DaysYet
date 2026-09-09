import AppIntents
import Foundation

enum MetricKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case week
    case month
    case year
    case healthyLife
    case customLife
    case activity
    case workday
    case study

    var id: String { rawValue }
    static let activityKinds: [MetricKind] = [.activity, .workday]
    var isActivity: Bool { Self.activityKinds.contains(self) }

    var title: String {
        switch self {
        case .week: L10n.text("今週", "This week")
        case .month: L10n.text("今月", "This month")
        case .year: L10n.text("今年", "This year")
        case .healthyLife: L10n.text("健康でいたい年齢", "Healthy-age goal")
        case .customLife: L10n.text("大切な日", "Milestone")
        case .activity: L10n.text("1日の活動", "Daily activity")
        case .workday: L10n.text("勤務時間", "Work hours")
        case .study: L10n.text("学習日", "Study days")
        }
    }

    func title(profile: UserProfile) -> String {
        let customName: String
        switch self {
        case .activity, .workday: customName = profile.activitySchedule(for: self).name
        case .customLife: customName = profile.customTargetName
        case .study: customName = profile.studySchedule.name
        default: return title
        }
        let trimmed = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? title : trimmed
    }

    var shortTitle: String {
        switch self {
        case .healthyLife: L10n.text("健康目標", "Health goal")
        case .customLife: L10n.text("節目", "Goal")
        default: title
        }
    }

    var symbolName: String {
        switch self {
        case .week: "calendar.day.timeline.leading"
        case .month: "calendar"
        case .year: "sparkles"
        case .healthyLife: "heart.text.clipboard"
        case .customLife: "flag.checkered"
        case .activity: "sun.max"
        case .workday: "briefcase"
        case .study: "book.closed"
        }
    }
}

enum WidgetDisplayMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case countdown
    case countdownWithPercentage
    case progressBars

    var id: String { rawValue }

    var title: String {
        switch self {
        case .countdown: L10n.text("カウントダウン", "Countdown")
        case .countdownWithPercentage: L10n.text("時間＋経過割合＋バー", "Time + elapsed % + bar")
        case .progressBars: L10n.text("プログレスバー", "Progress bars")
        }
    }

    var shortTitle: String {
        switch self {
        case .countdown: L10n.text("時間", "Time")
        case .countdownWithPercentage: L10n.text("時間＋％", "Time + %")
        case .progressBars: L10n.text("バー", "Bars")
        }
    }

    var symbolName: String {
        switch self {
        case .countdown: "timer"
        case .countdownWithPercentage: "percent"
        case .progressBars: "chart.bar.fill"
        }
    }

    var showsLiveCountdown: Bool {
        switch self {
        case .countdown, .countdownWithPercentage: true
        case .progressBars: false
        }
    }
}

enum WidgetTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case vividNight
    case quietForest
    case softDawn
    case calmSea

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vividNight: L10n.text("夜の彩り", "Vivid Night")
        case .quietForest: L10n.text("静かな森", "Quiet Forest")
        case .softDawn: L10n.text("やわらかな朝", "Soft Dawn")
        case .calmSea: L10n.text("凪の海", "Calm Sea")
        }
    }

    var subtitle: String {
        switch self {
        case .vividNight: L10n.text("深い夜に、鮮やかな光", "Bright color against a deep night")
        case .quietForest: L10n.text("セージと木漏れ日の静けさ", "Soft sage and filtered light")
        case .softDawn: L10n.text("朝焼けのような温もり", "The gentle warmth of daybreak")
        case .calmSea: L10n.text("呼吸がほどける青", "Restful, open shades of blue")
        }
    }
}

enum MetricValueStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case remaining
    case percentage
    case targetDate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .remaining: L10n.text("残り時間", "Time left")
        case .percentage: L10n.text("経過割合", "Elapsed percentage")
        case .targetDate: L10n.text("終了日時", "End date")
        }
    }

    var shortTitle: String {
        switch self {
        case .remaining: L10n.text("残り", "Left")
        case .percentage: "%"
        case .targetDate: L10n.text("日時", "Date")
        }
    }
}

enum WidgetMetricOption: String, AppEnum, CaseIterable {
    case week
    case month
    case year
    case healthyLife
    case customLife
    case activity
    case workday
    case study

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "widget.metric.type")
    static let caseDisplayRepresentations: [WidgetMetricOption: DisplayRepresentation] = [
        .week: "metric.week",
        .month: "metric.month",
        .year: "metric.year",
        .healthyLife: "metric.healthy_age_goal",
        .customLife: "metric.milestone",
        .activity: "metric.activity",
        .workday: "metric.workday",
        .study: "metric.study"
    ]

    var metricKind: MetricKind {
        MetricKind(rawValue: rawValue) ?? .month
    }
}

enum LockScreenMetricOption: String, AppEnum, CaseIterable {
    case appSelection
    case week
    case month
    case year
    case healthyLife
    case customLife
    case activity
    case workday
    case study

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "widget.lock_screen.metric.type")
    static let caseDisplayRepresentations: [LockScreenMetricOption: DisplayRepresentation] = [
        .appSelection: "widget.lock_screen.metric.app_selection",
        .week: "metric.week",
        .month: "metric.month",
        .year: "metric.year",
        .healthyLife: "metric.healthy_age_goal",
        .customLife: "metric.milestone",
        .activity: "metric.activity",
        .workday: "metric.workday",
        .study: "metric.study"
    ]

    func resolved(profile: UserProfile) -> MetricKind {
        if !profile.isConfigured, self == .healthyLife || self == .customLife {
            return profile.normalizedDashboardMetrics.first ?? .month
        }

        switch self {
        case .appSelection:
            return profile.normalizedDashboardMetrics.first ?? .month
        case .week:
            return .week
        case .month:
            return .month
        case .year:
            return .year
        case .healthyLife:
            return .healthyLife
        case .customLife:
            return .customLife
        case .activity:
            return .activity
        case .workday:
            return .workday
        case .study:
            return .study
        }
    }
}

enum WidgetValueStyleOption: String, AppEnum, CaseIterable {
    case appSetting
    case remaining
    case percentage
    case targetDate

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "widget.value_style.type")
    static let caseDisplayRepresentations: [WidgetValueStyleOption: DisplayRepresentation] = [
        .appSetting: "widget.value_style.app_setting",
        .remaining: "widget.value_style.remaining",
        .percentage: "widget.value_style.percentage",
        .targetDate: "widget.value_style.target_date"
    ]

    func resolved(profileStyle: MetricValueStyle) -> MetricValueStyle {
        switch self {
        case .appSetting: profileStyle
        case .remaining: .remaining
        case .percentage: .percentage
        case .targetDate: .targetDate
        }
    }
}

enum WidgetDisplayModeOption: String, AppEnum, CaseIterable {
    case appSetting
    case countdown
    case countdownWithPercentage
    case progressBars

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "widget.display_mode.type")
    static let caseDisplayRepresentations: [WidgetDisplayModeOption: DisplayRepresentation] = [
        .appSetting: "widget.option.app_setting",
        .countdown: "widget.display_mode.countdown",
        .countdownWithPercentage: "widget.display_mode.countdown_with_percentage",
        .progressBars: "widget.display_mode.progress_bars"
    ]

    func resolved(profileMode: WidgetDisplayMode) -> WidgetDisplayMode {
        switch self {
        case .appSetting: profileMode
        case .countdown: .countdown
        case .countdownWithPercentage: .countdownWithPercentage
        case .progressBars: .progressBars
        }
    }
}

enum WidgetThemeOption: String, AppEnum, CaseIterable {
    case appSetting
    case vividNight
    case quietForest
    case softDawn
    case calmSea

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "widget.theme.type")
    static let caseDisplayRepresentations: [WidgetThemeOption: DisplayRepresentation] = [
        .appSetting: "widget.option.app_setting",
        .vividNight: "widget.theme.vivid_night",
        .quietForest: "widget.theme.quiet_forest",
        .softDawn: "widget.theme.soft_dawn",
        .calmSea: "widget.theme.calm_sea"
    ]

    func resolved(profileTheme: WidgetTheme) -> WidgetTheme {
        switch self {
        case .appSetting: profileTheme
        case .vividNight: .vividNight
        case .quietForest: .quietForest
        case .softDawn: .softDawn
        case .calmSea: .calmSea
        }
    }
}

struct CountdownComponent: Equatable, Sendable {
    let value: Int
    let unit: String

    var text: String { "\(value)\(unit)" }
}

struct CountdownPresentation: Equatable, Sendable {
    let prefix: String
    let components: [CountdownComponent]
    let suffix: String
    let terminalText: String?

    var plainText: String {
        if let terminalText { return terminalText }
        return ([prefix] + components.map(\.text) + [suffix])
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var compactText: String {
        terminalText ?? components.map(\.text).joined()
    }
}

struct MetricSnapshot: Identifiable, Equatable, Sendable {
    let kind: MetricKind
    let title: String
    let context: String
    let countdown: CountdownPresentation
    let elapsedFraction: Double
    let targetDate: Date
    var isOff: Bool = false

    var id: String { kind.rawValue }
    var remainingText: String { countdown.plainText }
    var percentageText: String { isOff ? "Off" : String(format: "%.1f%%", elapsedFraction * 100) }

    var percentageElapsedText: String {
        isOff ? "Off" : L10n.text("\(percentageText)経過", "\(percentageText) elapsed")
    }

    func valueText(style: MetricValueStyle, compact: Bool = false) -> String {
        if isOff { return "Off" }
        switch style {
        case .remaining:
            return compact ? compactRemainingText : remainingText
        case .percentage:
            return percentageElapsedText
        case .targetDate:
            return targetDateText(compact: compact)
        }
    }

    func targetDateText(compact: Bool = false) -> String {
        if isOff { return "Off" }
        let formatted: String
        if kind == .study {
            formatted = targetDate.formatted(date: .numeric, time: .omitted)
        } else if compact, kind.isActivity {
            formatted = targetDate.formatted(date: .omitted, time: .shortened)
        } else if compact, kind == .healthyLife || kind == .customLife {
            formatted = targetDate.formatted(.dateTime.year(.twoDigits).month(.defaultDigits).day())
        } else if compact {
            formatted = targetDate.formatted(.dateTime.month(.defaultDigits).day())
        } else {
            formatted = targetDate.formatted(date: .numeric, time: .shortened)
        }

        if kind == .healthyLife {
            return L10n.text("目安 \(formatted)", "Target \(formatted)")
        }
        return L10n.text("\(formatted)まで", "Until \(formatted)")
    }

    func secondarySummary(excluding style: MetricValueStyle) -> String {
        if isOff { return context }
        switch style {
        case .remaining:
            return "\(percentageElapsedText) · \(targetDateText())"
        case .percentage:
            return "\(remainingText) · \(targetDateText())"
        case .targetDate:
            return "\(remainingText) · \(percentageElapsedText)"
        }
    }

    var accessibilitySummary: String {
        if isOff { return "\(title)。Off。\(context)。" }
        return "\(title)。\(remainingText)。\(percentageElapsedText)。\(targetDateText())。"
    }

    private var compactRemainingText: String {
        if countdown.terminalText != nil {
            switch kind {
            case .healthyLife: return L10n.text("目安超過", "Past target")
            case .customLife: return L10n.text("到達", "Reached")
            case .activity, .workday, .study: return countdown.terminalText ?? ""
            default: return L10n.text("更新中", "Updating")
            }
        }
        return countdown.compactText
    }
}

enum TimeProgressCalculator {
    static func snapshot(
        for kind: MetricKind,
        profile: UserProfile,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> MetricSnapshot {
        if kind == .study {
            return studySnapshot(profile: profile, now: now, calendar: calendar)
        }
        let scheduledInterval = kind.isActivity
            ? activityInterval(schedule: profile.activitySchedule(for: kind), now: now, calendar: calendar)
            : nil
        let isOff = kind.isActivity && scheduledInterval == nil
        let interval = kind.isActivity
            ? scheduledInterval ?? DateInterval(start: now, duration: 0)
            : dateInterval(for: kind, profile: profile, now: now, calendar: calendar)
        let total = max(interval.end.timeIntervalSince(interval.start), 1)
        let elapsed = max(now.timeIntervalSince(interval.start), 0)
        let fraction = min(max(elapsed / total, 0), 1)
        let beforeActivity = kind.isActivity && now < interval.start
        let afterActivity = kind.isActivity && !isOff && now >= interval.end

        return MetricSnapshot(
            kind: kind,
            title: kind.title(profile: profile),
            context: isOff
                ? offContext(schedule: profile.activitySchedule(for: kind))
                : context(for: kind, profile: profile, target: interval.end, calendar: calendar),
            countdown: isOff ? CountdownPresentation(
                prefix: "", components: [], suffix: "", terminalText: "Off"
            ) : beforeActivity ? CountdownPresentation(
                prefix: "", components: [], suffix: "",
                terminalText: L10n.text("開始前", "Not started")
            ) : countdownPresentation(
                for: kind,
                now: now,
                target: interval.end,
                calendar: calendar
            ),
            elapsedFraction: afterActivity ? 1 : fraction,
            targetDate: interval.end,
            isOff: isOff
        )
    }

    static func dateInterval(
        for kind: MetricKind,
        profile: UserProfile,
        now: Date,
        calendar: Calendar
    ) -> DateInterval {
        switch kind {
        case .week:
            var weekCalendar = calendar
            weekCalendar.firstWeekday = profile.weekStartDay.resolvedWeekday(in: calendar)
            return weekCalendar.dateInterval(of: .weekOfYear, for: now) ?? fallbackInterval(now: now)
        case .month:
            return calendar.dateInterval(of: .month, for: now) ?? fallbackInterval(now: now)
        case .year:
            return calendar.dateInterval(of: .year, for: now) ?? fallbackInterval(now: now)
        case .healthyLife:
            let target = targetDate(from: profile.birthDate, years: profile.healthyLifeYears, calendar: calendar)
            return DateInterval(start: profile.birthDate, end: max(target, profile.birthDate.addingTimeInterval(1)))
        case .customLife:
            let start = profile.customTargetStartDate
            return DateInterval(start: start, end: max(profile.customTargetDate, start.addingTimeInterval(1)))
        case .study:
            let schedule = profile.studySchedule.normalized
            let start = schedule.startDate(in: calendar)
            let end = schedule.endDate(in: calendar)
            let exclusiveEnd = calendar.date(byAdding: .day, value: 1, to: end)
                .map { calendar.startOfDay(for: $0) } ?? end
            return DateInterval(start: start, end: max(exclusiveEnd, start))
        case .activity, .workday:
            return activityInterval(schedule: profile.activitySchedule(for: kind), now: now, calendar: calendar)
                ?? DateInterval(start: now, duration: 0)
        }
    }

    /// Changes that can fall between WidgetKit's regular timeline entries.
    static func transitionDates(
        for kind: MetricKind,
        profile: UserProfile,
        after now: Date,
        through end: Date,
        calendar: Calendar
    ) -> [Date] {
        guard end > now else { return [] }
        if kind == .study {
            let schedule = profile.studySchedule.normalized
            let lastDay = schedule.endDate(in: calendar)
            let lastBoundary = calendar.date(byAdding: .day, value: 1, to: lastDay)
                .map { calendar.startOfDay(for: $0) } ?? lastDay
            var day = max(calendar.startOfDay(for: now), schedule.startDate(in: calendar))
            var boundaries: [Date] = []
            for _ in 0...StudySchedule.maximumDayCount {
                guard day <= end, day <= lastBoundary else { break }
                if day > now { boundaries.append(day) }
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                let nextDay = calendar.startOfDay(for: next)
                guard nextDay > day else { break }
                day = nextDay
            }
            return boundaries
        }
        if !kind.isActivity {
            let boundary = dateInterval(for: kind, profile: profile, now: now, calendar: calendar).end
            return boundary > now && boundary <= end ? [boundary] : []
        }

        let schedule = profile.activitySchedule(for: kind).normalized
        guard !schedule.activeWeekdays.isEmpty else { return [] }
        let today = calendar.startOfDay(for: now)
        var day = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        var dates = Set<Date>()
        while day <= end {
            var boundaries = [day]
            if schedule.activeWeekdays.contains(calendar.component(.weekday, from: day)) {
                let interval = activityInterval(startingOn: day, schedule: schedule, calendar: calendar)
                boundaries += [interval.start, interval.end]
            }
            for date in boundaries where date > now && date <= end {
                dates.insert(date)
            }
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day), nextDay > day else { break }
            day = nextDay
        }
        return dates.sorted()
    }

    private static func studySnapshot(profile: UserProfile, now: Date, calendar: Calendar) -> MetricSnapshot {
        let schedule = profile.studySchedule.normalized
        let selectedDays = schedule.selectedDates(calendar: calendar)
        let today = calendar.startOfDay(for: now)
        let elapsedCount = selectedDays.filter { $0 < today }.count
        let remainingCount = selectedDays.count - elapsedCount
        let presentation: CountdownPresentation
        let context: String
        if selectedDays.isEmpty {
            presentation = CountdownPresentation(
                prefix: "", components: [], suffix: "",
                terminalText: L10n.text("学習日を選択", "Select study days")
            )
            context = L10n.text("カレンダーで日付や曜日を選んでください", "Choose dates or weekdays in the calendar")
        } else if remainingCount == 0 {
            presentation = CountdownPresentation(
                prefix: "", components: [], suffix: "",
                terminalText: L10n.text("予定日が経過", "Scheduled days elapsed")
            )
            context = L10n.text("全\(selectedDays.count)日の予定が経過しました", "All \(selectedDays.count) scheduled days have elapsed")
        } else {
            presentation = CountdownPresentation(
                prefix: L10n.text("あと", ""),
                components: [CountdownComponent(value: remainingCount, unit: L10n.text("日", "d"))],
                suffix: L10n.text("", "left"), terminalText: nil
            )
            context = L10n.text("全\(selectedDays.count)日の予定・今日を含む", "Of \(selectedDays.count) scheduled days · includes today")
        }
        return MetricSnapshot(
            kind: .study,
            title: MetricKind.study.title(profile: profile),
            context: context,
            countdown: presentation,
            elapsedFraction: selectedDays.isEmpty ? 0 : Double(elapsedCount) / Double(selectedDays.count),
            targetDate: schedule.endDate(in: calendar)
        )
    }

    private static func activityInterval(schedule: ActivitySchedule, now: Date, calendar: Calendar) -> DateInterval? {
        let schedule = schedule.normalized
        let today = calendar.startOfDay(for: now)
        let todayIsActive = schedule.activeWeekdays.contains(calendar.component(.weekday, from: today))
        let todayInterval = activityInterval(startingOn: today, schedule: schedule, calendar: calendar)
        if schedule.endMinute <= schedule.startMinute,
           now < todayInterval.start,
           let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
           schedule.activeWeekdays.contains(calendar.component(.weekday, from: yesterday)) {
            let previous = activityInterval(startingOn: yesterday, schedule: schedule, calendar: calendar)
            // An enabled overnight period remains active into an Off weekday.
            // On enabled days retain its completed state until the next start.
            if now < previous.end || todayIsActive { return previous }
        }
        return todayIsActive ? todayInterval : nil
    }

    private static func activityInterval(
        startingOn day: Date,
        schedule: ActivitySchedule,
        calendar: Calendar
    ) -> DateInterval {
        let startMinute = UserProfile.clampedWorkMinute(schedule.startMinute)
        let endMinute = UserProfile.clampedWorkMinute(schedule.endMinute)
        let endDay = endMinute <= startMinute
            ? calendar.date(byAdding: .day, value: 1, to: day) ?? day
            : day
        let start = clockDate(minute: startMinute, on: day, calendar: calendar)
        let end = clockDate(minute: endMinute, on: endDay, calendar: calendar)
        // A skipped clock interval during a DST change can have zero duration.
        // It is complete at that instant, rather than becoming negative.
        return DateInterval(start: start, end: max(end, start))
    }

    private static func clockDate(minute: Int, on day: Date, calendar: Calendar) -> Date {
        calendar.date(
            bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day,
            matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward
        ) ?? calendar.startOfDay(for: day)
    }

    private static func targetDate(from birthDate: Date, years: Double, calendar: Calendar) -> Date {
        let wholeYears = Int(years.rounded(.down))
        let fraction = years - Double(wholeYears)
        let yearDate = calendar.date(byAdding: .year, value: wholeYears, to: birthDate) ?? birthDate
        return calendar.date(byAdding: .day, value: Int((fraction * 365.2425).rounded()), to: yearDate) ?? yearDate
    }

    private static func context(
        for kind: MetricKind,
        profile: UserProfile,
        target: Date,
        calendar: Calendar
    ) -> String {
        switch kind {
        case .week: return L10n.text("次の週まで", "until next week")
        case .month: return L10n.text("来月まで", "until next month")
        case .year: return L10n.text("来年まで", "until next year")
        case .healthyLife:
            return L10n.text("設定した \(formattedAge(profile.healthyLifeYears)) 歳まで", "until age \(formattedAge(profile.healthyLifeYears))")
        case .customLife:
            return target.formatted(.dateTime.year().month(.abbreviated).day())
        case .activity, .workday:
            return L10n.text("活動時間", "Activity hours")
        case .study:
            return L10n.text("選択した学習日", "Selected study days")
        }
    }

    private static func offContext(schedule: ActivitySchedule) -> String {
        schedule.activeWeekdays.isEmpty
            ? L10n.text("すべての曜日がOffです", "All weekdays are Off")
            : L10n.text("今日はOffです", "Today is Off")
    }

    private static func countdownPresentation(
        for kind: MetricKind,
        now: Date,
        target: Date,
        calendar: Calendar
    ) -> CountdownPresentation {
        if now >= target {
            let terminalText: String
            switch kind {
            case .healthyLife:
                terminalText = L10n.text("設定した目安を超えています", "Beyond your set target")
            case .customLife:
                terminalText = L10n.text("ここまで歩みました", "Milestone reached")
            case .activity, .workday:
                terminalText = L10n.text("活動終了", "Finished")
            default:
                terminalText = L10n.text("次の期間へ更新中", "Updating period")
            }
            return CountdownPresentation(prefix: "", components: [], suffix: "", terminalText: terminalText)
        }

        let seconds = max(target.timeIntervalSince(now), 0)
        let approximateDays = Int(seconds / (24 * 60 * 60))
        let prefix = L10n.text("あと", "")
        let suffix = L10n.text("", "left")
        let components: [CountdownComponent]

        if kind.isActivity {
            components = [
                CountdownComponent(value: Int(seconds / 3_600), unit: L10n.text("時間", "h")),
                CountdownComponent(value: Int(seconds / 60) % 60, unit: L10n.text("分", "m"))
            ]
        } else if approximateDays >= 730 {
            let values = calendar.dateComponents([.year, .month], from: now, to: target)
            components = [
                CountdownComponent(value: max(values.year ?? 0, 0), unit: L10n.text("年", "y")),
                CountdownComponent(value: max(values.month ?? 0, 0), unit: L10n.text("か月", "mo"))
            ]
        } else if approximateDays > 0 {
            let values = calendar.dateComponents([.day, .hour], from: now, to: target)
            components = [
                CountdownComponent(value: max(values.day ?? 0, 0), unit: L10n.text("日", "d")),
                CountdownComponent(value: max(values.hour ?? 0, 0), unit: L10n.text("時間", "h"))
            ]
        } else {
            let values = calendar.dateComponents([.hour, .minute], from: now, to: target)
            components = [
                CountdownComponent(value: max(values.hour ?? 0, 0), unit: L10n.text("時間", "h")),
                CountdownComponent(value: max(values.minute ?? 0, 0), unit: L10n.text("分", "m"))
            ]
        }

        return CountdownPresentation(prefix: prefix, components: components, suffix: suffix, terminalText: nil)
    }

    private static func formattedAge(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    private static func fallbackInterval(now: Date) -> DateInterval {
        DateInterval(start: now, duration: 60)
    }
}
