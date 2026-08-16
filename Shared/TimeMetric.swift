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

enum MetricValueStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case remaining
    case percentage
    case targetDate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .remaining: L10n.text("残り時間", "Time left")
        case .percentage: L10n.text("割合", "Percent")
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

struct MetricSnapshot: Identifiable, Equatable, Sendable {
    let kind: MetricKind
    let title: String
    let context: String
    let remainingText: String
    let remainingFraction: Double
    let targetDate: Date

    var id: String { kind.rawValue }
    var percentageText: String { String(format: "%.1f%%", remainingFraction * 100) }

    var percentageRemainingText: String {
        L10n.text("残り\(percentageText)", "\(percentageText) left")
    }

    func valueText(style: MetricValueStyle, compact: Bool = false) -> String {
        switch style {
        case .remaining:
            compact ? compactRemainingText : remainingText
        case .percentage:
            percentageRemainingText
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
            "\(percentageRemainingText) · \(targetDateText())"
        case .percentage:
            "\(remainingText) · \(targetDateText())"
        case .targetDate:
            "\(remainingText) · \(percentageRemainingText)"
        }
    }

    var accessibilitySummary: String {
        "\(title)。\(remainingText)。\(percentageRemainingText)。\(targetDateText())。"
    }

    private var compactRemainingText: String {
        remainingText
            .replacingOccurrences(of: "あと ", with: "")
            .replacingOccurrences(of: " left", with: "")
            .replacingOccurrences(of: " ", with: "")
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
        let remaining = max(interval.end.timeIntervalSince(now), 0)
        let fraction = min(max(remaining / total, 0), 1)

        return MetricSnapshot(
            kind: kind,
            title: kind == .customLife ? nonEmpty(profile.customTargetName, fallback: kind.title) : kind.title,
            context: context(for: kind, profile: profile, target: interval.end, calendar: calendar),
            remainingText: remainingText(
                for: kind,
                now: now,
                target: interval.end,
                calendar: calendar
            ),
            remainingFraction: fraction,
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
            let start = min(profile.birthDate, now)
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

    private static func remainingText(
        for kind: MetricKind,
        now: Date,
        target: Date,
        calendar: Calendar
    ) -> String {
        if now >= target {
            switch kind {
            case .healthyLife:
                return L10n.text("設定した目安を超えています", "Beyond your set target")
            case .customLife:
                return L10n.text("ここまで歩みました", "Milestone reached")
            default:
                return L10n.text("次の期間へ更新中", "Updating period")
            }
        }

        let seconds = max(target.timeIntervalSince(now), 0)
        let approximateDays = Int(seconds / (24 * 60 * 60))

        if approximateDays >= 730 {
            let components = calendar.dateComponents([.year, .month], from: now, to: target)
            let years = max(components.year ?? 0, 0)
            let months = max(components.month ?? 0, 0)
            return L10n.text("あと \(years)年 \(months)か月", "\(years)y \(months)mo left")
        }
        if approximateDays > 0 {
            let components = calendar.dateComponents([.day, .hour], from: now, to: target)
            let days = max(components.day ?? 0, 0)
            let hours = max(components.hour ?? 0, 0)
            return L10n.text("あと \(days)日 \(hours)時間", "\(days)d \(hours)h left")
        }
        let components = calendar.dateComponents([.hour, .minute], from: now, to: target)
        let hours = max(components.hour ?? 0, 0)
        let minutes = max(components.minute ?? 0, 0)
        return L10n.text("あと \(hours)時間 \(minutes)分", "\(hours)h \(minutes)m left")
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
