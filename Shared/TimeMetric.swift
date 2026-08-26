import AppIntents
import Foundation

enum MetricKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case week
    case month
    case year
    case healthyLife
    case customLife

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: L10n.text("今週", "This week")
        case .month: L10n.text("今月", "This month")
        case .year: L10n.text("今年", "This year")
        case .healthyLife: L10n.text("健康でいたい年齢", "Healthy-age goal")
        case .customLife: L10n.text("大切な日", "Milestone")
        }
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

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "widget.metric.type")
    static let caseDisplayRepresentations: [WidgetMetricOption: DisplayRepresentation] = [
        .week: "metric.week",
        .month: "metric.month",
        .year: "metric.year",
        .healthyLife: "metric.healthy_age_goal",
        .customLife: "metric.milestone"
    ]

    var metricKind: MetricKind {
        MetricKind(rawValue: rawValue) ?? .month
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

    var id: String { kind.rawValue }
    var remainingText: String { countdown.plainText }
    var percentageText: String { String(format: "%.1f%%", elapsedFraction * 100) }

    var percentageElapsedText: String {
        L10n.text("\(percentageText)経過", "\(percentageText) elapsed")
    }

    func valueText(style: MetricValueStyle, compact: Bool = false) -> String {
        switch style {
        case .remaining:
            compact ? compactRemainingText : remainingText
        case .percentage:
            percentageElapsedText
        case .targetDate:
            targetDateText(compact: compact)
        }
    }

    func targetDateText(compact: Bool = false) -> String {
        let formatted: String
        if compact, kind == .healthyLife || kind == .customLife {
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
        switch style {
        case .remaining:
            "\(percentageElapsedText) · \(targetDateText())"
        case .percentage:
            "\(remainingText) · \(targetDateText())"
        case .targetDate:
            "\(remainingText) · \(percentageElapsedText)"
        }
    }

    var accessibilitySummary: String {
        "\(title)。\(remainingText)。\(percentageElapsedText)。\(targetDateText())。"
    }

    private var compactRemainingText: String {
        if countdown.terminalText != nil {
            switch kind {
            case .healthyLife: return L10n.text("目安超過", "Past target")
            case .customLife: return L10n.text("到達", "Reached")
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
        let interval = dateInterval(for: kind, profile: profile, now: now, calendar: calendar)
        let total = max(interval.end.timeIntervalSince(interval.start), 1)
        let elapsed = max(now.timeIntervalSince(interval.start), 0)
        let fraction = min(max(elapsed / total, 0), 1)

        return MetricSnapshot(
            kind: kind,
            title: kind == .customLife ? nonEmpty(profile.customTargetName, fallback: kind.title) : kind.title,
            context: context(for: kind, profile: profile, target: interval.end, calendar: calendar),
            countdown: countdownPresentation(
                for: kind,
                now: now,
                target: interval.end,
                calendar: calendar
            ),
            elapsedFraction: fraction,
            targetDate: interval.end
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
            return calendar.dateInterval(of: .weekOfYear, for: now) ?? fallbackInterval(now: now)
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
        }
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
        }
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

        if approximateDays >= 730 {
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

    private static func nonEmpty(_ value: String, fallback: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : value
    }

    private static func fallbackInterval(now: Date) -> DateInterval {
        DateInterval(start: now, duration: 60)
    }
}
