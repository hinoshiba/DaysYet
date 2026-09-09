import Foundation

/// A finite set of planned study days, not a record of completed sessions.
/// Civil-day keys keep a chosen date on the same date when the device travels.
struct StudySchedule: Codable, Equatable, Sendable {
    static let maximumDayCount = 366

    var name: String
    var activeWeekdays: Set<Int>
    var addedDays: Set<String>
    var excludedDays: Set<String>
    private var startDay: String
    private var endDay: String

    /// DatePicker bridges use the device's current time zone. Storage uses dates
    /// on the Gregorian calendar, independent of that time zone and locale.
    var startDate: Date {
        get { startDate(in: .autoupdatingCurrent) }
        set {
            startDay = Self.dayKey(newValue, calendar: .autoupdatingCurrent)
            self = normalized
        }
    }

    /// The last day is included in the schedule.
    var endDate: Date {
        get { endDate(in: .autoupdatingCurrent) }
        set {
            endDay = Self.dayKey(newValue, calendar: .autoupdatingCurrent)
            self = normalized
        }
    }

    static var initial: StudySchedule {
        let calendar = Self.gregorianCalendar(.autoupdatingCurrent)
        let today = calendar.startOfDay(for: .now)
        return StudySchedule(
            startDate: today,
            endDate: calendar.date(byAdding: .day, value: 27, to: today) ?? today,
            // Older profiles may be read by a widget before the app is opened.
            // A date range alone must not invent a rolling study plan for them.
            activeWeekdays: []
        )
    }

    init(
        name: String = "",
        startDate: Date,
        endDate: Date,
        activeWeekdays: Set<Int> = Set(2...6),
        addedDays: Set<String> = [],
        excludedDays: Set<String> = [],
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.name = name
        self.startDay = Self.dayKey(startDate, calendar: calendar)
        self.endDay = Self.dayKey(endDate, calendar: calendar)
        self.activeWeekdays = activeWeekdays
        self.addedDays = addedDays
        self.excludedDays = excludedDays
        self = normalized
    }

    var normalized: StudySchedule {
        var result = self
        let calendar = Self.utcCalendar
        let start = Self.date(for: startDay, calendar: calendar) ?? Self.fallbackDate
        result.startDay = Self.dayKey(start, calendar: calendar)
        let proposedEnd = Self.date(for: endDay, calendar: calendar) ?? start
        let lastSupportedDate = Self.date(for: "9999-12-31", calendar: calendar)!
        let maximumEnd = min(
            calendar.date(byAdding: .day, value: Self.maximumDayCount - 1, to: start) ?? start,
            lastSupportedDate
        )
        result.endDay = Self.dayKey(min(max(proposedEnd, start), maximumEnd), calendar: calendar)
        result.activeWeekdays.formIntersection(1...7)
        let validKey: (String) -> Bool = {
            $0 >= result.startDay && $0 <= result.endDay && Self.date(for: $0, calendar: calendar) != nil
        }
        result.addedDays = Set(addedDays.filter(validKey))
        result.excludedDays = Set(excludedDays.filter(validKey))
        // A corrupt payload cannot both add and exclude one day; exclusion wins.
        result.addedDays.subtract(result.excludedDays)
        return result
    }

    func startDate(in calendar: Calendar) -> Date {
        Self.date(for: startDay, calendar: Self.gregorianCalendar(calendar)) ?? Self.fallbackDate
    }

    func endDate(in calendar: Calendar) -> Date {
        Self.date(for: endDay, calendar: Self.gregorianCalendar(calendar)) ?? startDate(in: calendar)
    }

    func selectedDates(calendar: Calendar = .autoupdatingCurrent) -> [Date] {
        let schedule = normalized
        let calendar = Self.gregorianCalendar(calendar)
        let end = schedule.endDate(in: calendar)
        var day = schedule.startDate(in: calendar)
        var selected: [Date] = []
        // Bound iteration even for hostile decoded dates or unusual calendars.
        for _ in 0..<Self.maximumDayCount {
            guard day <= end else { break }
            if schedule.contains(day, calendar: calendar) { selected.append(day) }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            // Midnight can be skipped by DST. Return to midnight on the next
            // ordinary day rather than carrying that day's 01:00 forward.
            let nextDay = calendar.startOfDay(for: next)
            guard nextDay > day else { break }
            day = nextDay
        }
        return selected
    }

    func isSelected(_ date: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        normalized.contains(date, calendar: Self.gregorianCalendar(calendar))
    }

    mutating func toggleDate(_ date: Date, calendar: Calendar = .autoupdatingCurrent) {
        guard Self.isSupported(date) else { return }
        self = normalized
        let calendar = Self.gregorianCalendar(calendar)
        let key = Self.dayKey(date, calendar: calendar)
        guard key >= startDay, key <= endDay else { return }
        let selected = contains(date, calendar: calendar)
        let baseline = activeWeekdays.contains(calendar.component(.weekday, from: date))
        addedDays.remove(key)
        excludedDays.remove(key)
        if selected && baseline { excludedDays.insert(key) }
        if !selected && !baseline { addedDays.insert(key) }
    }

    static func dayKey(_ date: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        guard isSupported(date) else { return "2001-01-01" }
        let parts = gregorianCalendar(calendar).dateComponents([.era, .year, .month, .day], from: date)
        guard parts.era == 1, let year = parts.year, (1...9999).contains(year),
              let month = parts.month, let day = parts.day else { return "2001-01-01" }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private func contains(_ date: Date, calendar: Calendar) -> Bool {
        guard Self.isSupported(date) else { return false }
        let key = Self.dayKey(date, calendar: calendar)
        guard key >= startDay, key <= endDay, !excludedDays.contains(key) else { return false }
        return addedDays.contains(key) || activeWeekdays.contains(calendar.component(.weekday, from: date))
    }

    private static func gregorianCalendar(_ calendar: Calendar) -> Calendar {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        gregorian.firstWeekday = calendar.firstWeekday
        return gregorian
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static let fallbackDate = Date(timeIntervalSinceReferenceDate: 0)

    private static func isSupported(_ date: Date) -> Bool {
        let seconds = date.timeIntervalSince1970
        return seconds.isFinite && (-64_000_000_000...253_500_000_000).contains(seconds)
    }

    private static func date(for key: String, calendar: Calendar) -> Date? {
        let bytes = Array(key.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
              bytes.enumerated().allSatisfy({ $0.offset == 4 || $0.offset == 7 || (48...57).contains($0.element) })
        else { return nil }
        let pieces = key.split(separator: "-")
        guard let year = Int(pieces[0]), (1...9999).contains(year),
              let month = Int(pieces[1]), (1...12).contains(month),
              let day = Int(pieces[2]), (1...31).contains(day),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              dayKey(date, calendar: calendar) == key else { return nil }
        return calendar.startOfDay(for: date)
    }

    private enum CodingKeys: String, CodingKey {
        case name, startDate, endDate, activeWeekdays, addedDays, excludedDays
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.initial
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        startDay = (try? container.decode(String.self, forKey: .startDate)) ?? defaults.startDay
        endDay = (try? container.decode(String.self, forKey: .endDate)) ?? defaults.endDay
        activeWeekdays = (try? container.decode(Set<Int>.self, forKey: .activeWeekdays)) ?? defaults.activeWeekdays
        addedDays = (try? container.decode(Set<String>.self, forKey: .addedDays)) ?? []
        excludedDays = (try? container.decode(Set<String>.self, forKey: .excludedDays)) ?? []
        self = normalized
    }

    func encode(to encoder: Encoder) throws {
        let schedule = normalized
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schedule.name, forKey: .name)
        try container.encode(schedule.startDay, forKey: .startDate)
        try container.encode(schedule.endDay, forKey: .endDate)
        try container.encode(schedule.activeWeekdays, forKey: .activeWeekdays)
        try container.encode(schedule.addedDays, forKey: .addedDays)
        try container.encode(schedule.excludedDays, forKey: .excludedDays)
    }
}
