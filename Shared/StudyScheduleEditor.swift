import SwiftUI

/// The same calendar interaction is used by the iOS and macOS editors.
/// This view owns its Form; the presenting view supplies navigation and dismissal.
struct StudyScheduleEditor: View {
    @Binding var schedule: StudySchedule
    let weekStartDay: WeekStartDay

    @State private var visibleMonth = Date.now
    @ScaledMetric(relativeTo: .body) private var daySize: CGFloat = 44

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .autoupdatingCurrent
        calendar.timeZone = .autoupdatingCurrent
        calendar.firstWeekday = weekStartDay.resolvedWeekday(in: .autoupdatingCurrent)
        return calendar
    }

    private var weekdays: [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    private var periodStart: Date { schedule.startDate(in: calendar) }
    private var periodEnd: Date { schedule.endDate(in: calendar) }
    private var selectedDates: [Date] { schedule.selectedDates(calendar: calendar) }
    private var minimumGridWidth: CGFloat { daySize * 7 + 12 }

    var body: some View {
        Group {
#if os(macOS)
            macEditor
#else
            Form {
                planSection
                weekdaySection
                calendarSection
            }
            .formStyle(.grouped)
#endif
        }
        .environment(\.calendar, calendar)
        .onAppear {
            let today = calendar.startOfDay(for: .now)
            visibleMonth = monthStart(for: min(max(today, periodStart), periodEnd))
        }
        .onChange(of: schedule.startDate) { _, _ in
            visibleMonth = monthStart(for: periodStart)
        }
        .onChange(of: schedule.endDate) { _, _ in
            clampVisibleMonth()
        }
    }

#if os(macOS)
    private var macEditor: some View {
        HStack(alignment: .top, spacing: 0) {
            Form {
                planSection
                Section {
                    summary
                } header: {
                    Text(L10n.text("選んだ学習日", "Your study days"))
                } footer: {
                    Text(progressHelp)
                }
            }
            .formStyle(.grouped)
            .frame(width: 270)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.text("曜日から選ぶ", "Choose weekdays"))
                        .font(.headline)
                    weekdayPicker
                    Text(weekdayHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Divider()
                    monthNavigation
                    calendarGrid
                    Text(dateSelectionHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
            }
        }
    }
#endif

    private var planSection: some View {
        Section {
            TextField(L10n.text("名前（例：資格試験の準備）", "Name (e.g. Exam preparation)"), text: $schedule.name)
                .labelsHidden()
                .accessibilityLabel(L10n.text("学習プランの名前", "Study plan name"))
                .accessibilityIdentifier("study.name")

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    startDatePicker
                    Spacer(minLength: 0)
                    endDatePicker
                }
                VStack(alignment: .leading, spacing: 8) {
                    startDatePicker
                    endDatePicker
                }
            }
            .padding(.vertical, 2)

            durationPicker
        } header: {
            Text(L10n.text("学習プラン", "Study plan"))
        } footer: {
            Text(L10n.text("開始日と終了日を含む、最長1年のプランです。", "Includes both dates. Plan up to one year at a time."))
        }
    }

    private var durationPicker: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                durationLabel
                Spacer(minLength: 0)
                durationButtons
            }
            VStack(alignment: .leading, spacing: 8) {
                durationLabel
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { durationButtons }
                    VStack(alignment: .leading, spacing: 8) { durationButtons }
                }
            }
        }
    }

    private var durationLabel: some View {
        Text(L10n.text("期間", "Duration"))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize()
    }

    @ViewBuilder private var durationButtons: some View {
        durationButton(days: 14, title: L10n.text("2週間", "2 weeks"))
        durationButton(days: 28, title: L10n.text("4週間", "4 weeks"))
    }

    private var startDatePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.text("開始日", "Start date"))
                .font(.caption)
                .foregroundStyle(.secondary)
            DatePicker(L10n.text("開始日", "Start date"), selection: startDateBinding, displayedComponents: .date)
                .datePickerStyle(.compact)
                .labelsHidden()
                .fixedSize()
                .frame(minHeight: 44, alignment: .leading)
                .accessibilityIdentifier("study.startDate")
        }
    }

    private var endDatePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.text("終了日", "End date"))
                .font(.caption)
                .foregroundStyle(.secondary)
            DatePicker(
                L10n.text("終了日", "End date"),
                selection: endDateBinding,
                in: periodStart...maximumEndDate,
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .fixedSize()
            .frame(minHeight: 44, alignment: .leading)
            .accessibilityIdentifier("study.endDate")
        }
    }

    private func durationButton(days: Int, title: String) -> some View {
        let isCurrentDuration = calendar.dateComponents([.day], from: periodStart, to: periodEnd).day == days - 1
        return Button {
            schedule.endDate = calendar.date(byAdding: .day, value: days - 1, to: periodStart) ?? periodStart
        } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(isCurrentDuration ? Color.accentColor : .primary)
                .padding(.horizontal, 13)
                .frame(minHeight: 44)
                .background(
                    isCurrentDuration ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.text("開始日から\(days)日間", "\(days) days from the start date"))
        .accessibilityAddTraits(isCurrentDuration ? .isSelected : [])
        .accessibilityIdentifier("study.range.\(days)")
    }

    private var weekdaySection: some View {
        Section {
            weekdayPicker
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
        } header: {
            Text(L10n.text("曜日から選ぶ", "Choose weekdays"))
        } footer: {
            Text(weekdayHelp)
        }
    }

    private var weekdayPicker: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                HStack(spacing: 2) {
                    ForEach(weekdays, id: \.self) { weekday in
                        weekdayButton(weekday)
                    }
                }
                .frame(width: max(geometry.size.width, minimumGridWidth))
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        }
        .frame(height: daySize + 8)
    }

    private func weekdayButton(_ weekday: Int) -> some View {
        let selected = schedule.activeWeekdays.contains(weekday)
        return Button {
            var updated = schedule
            if selected {
                updated.activeWeekdays.remove(weekday)
            } else {
                updated.activeWeekdays.insert(weekday)
            }
            updated.addedDays.removeAll()
            updated.excludedDays.removeAll()
            schedule = updated.normalized
        } label: {
            VStack(spacing: 3) {
                Text(shortWeekdayName(weekday))
                    .font(.subheadline.weight(.semibold))
                Image(systemName: selected ? "checkmark" : "minus")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(selected ? Color.accentColor : .secondary)
            .frame(maxWidth: .infinity, minHeight: daySize + 8)
            .background(
                selected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(fullWeekdayName(weekday))
        .accessibilityValue(selectionValue(selected))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(L10n.text("この曜日をまとめて選び、日付の個別調整をリセットします", "Change this weekday throughout the plan and reset individual date edits"))
        .accessibilityIdentifier("study.weekday.\(weekday)")
    }

    private var calendarSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                summary
                Divider()
                monthNavigation
                calendarGrid
            }
            .listRowInsets(EdgeInsets(top: 14, leading: 8, bottom: 12, trailing: 8))
        } header: {
            Text(L10n.text("日付で調整", "Fine-tune dates"))
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(dateSelectionHelp)
                Text(progressHelp)
            }
        }
    }

    private var calendarGrid: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                monthGrid
                    .frame(width: max(geometry.size.width, minimumGridWidth))
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        }
        .frame(height: 24 + CGFloat(monthRowCount) * (daySize + 2))
    }

    private var summary: some View {
        let count = selectedDates.count
        let includesToday = schedule.isSelected(.now, calendar: calendar)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(count)")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.accentColor)
                Text(L10n.text("日を選択", count == 1 ? "day selected" : "days selected"))
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: 0)
            }
            Text(count == 0
                 ? L10n.text("曜日か日付を選んで、プランを始めましょう。", "Choose weekdays or dates to start your plan.")
                 : includesToday
                    ? L10n.text("今日は学習日です", "Today is a study day")
                    : L10n.text("今日は学習日に含まれていません", "Today is not a selected study day"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("study.summary")
    }

    private var monthNavigation: some View {
        HStack {
            Text(monthTitle)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("study.calendar.month")
            Spacer(minLength: 4)
            monthButton(offset: -1, symbol: "chevron.left", title: L10n.text("前の月", "Previous month"), identifier: "previousMonth")
            monthButton(offset: 1, symbol: "chevron.right", title: L10n.text("次の月", "Next month"), identifier: "nextMonth")
        }
        .padding(.leading, 6)
    }

    private func monthButton(offset: Int, symbol: String, title: String, identifier: String) -> some View {
        let destination = monthStart(for: calendar.date(byAdding: .month, value: offset, to: monthStart(for: visibleMonth)) ?? visibleMonth)
        let allowed = destination >= monthStart(for: periodStart) && destination <= monthStart(for: periodEnd)
        return Button {
            visibleMonth = destination
        } label: {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(allowed ? Color.accentColor : Color.secondary.opacity(0.35))
        .disabled(!allowed)
        .accessibilityLabel(title)
        .accessibilityIdentifier("study.calendar.\(identifier)")
    }

    private var monthGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: daySize), spacing: 2), count: 7), spacing: 2) {
            ForEach(weekdays, id: \.self) { weekday in
                Text(shortWeekdayName(weekday))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(height: 22)
                    .accessibilityHidden(true)
            }
            ForEach(0..<(monthRowCount * 7), id: \.self) { index in
                if let date = dateForCell(index) {
                    dateButton(date)
                } else {
                    Color.clear.frame(height: daySize)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private func dateButton(_ date: Date) -> some View {
        let selected = schedule.isSelected(date, calendar: calendar)
        let inRange = date >= periodStart && date <= periodEnd
        let isToday = calendar.isDateInToday(date)
        return Button {
            schedule.toggleDate(date, calendar: calendar)
        } label: {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 11)
                    .fill(selected ? Color.accentColor : Color.clear)
                VStack(spacing: 2) {
                    Text("\(calendar.component(.day, from: date))")
                        .font(.body.weight(selected || isToday ? .semibold : .regular))
                        .monospacedDigit()
                        .underline(isToday, pattern: .solid, color: selected ? .white : .primary)
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .opacity(selected ? 1 : 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(selected ? Color.white : inRange ? .primary : Color.secondary.opacity(0.35))
            }
            .frame(height: daySize)
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .disabled(!inRange)
        .accessibilityLabel(dateAccessibilityLabel(date, isToday: isToday))
        .accessibilityValue(inRange ? selectionValue(selected) : L10n.text("期間外", "Outside the plan"))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("study.calendar.day.\(StudySchedule.dayKey(date, calendar: calendar))")
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: L10n.isJapanese ? "ja_JP" : "en_US")
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("yMMMM")
        return formatter.string(from: visibleMonth)
    }

    private var leadingBlankDays: Int {
        let weekday = calendar.component(.weekday, from: monthStart(for: visibleMonth))
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    private var monthDayCount: Int {
        calendar.range(of: .day, in: .month, for: visibleMonth)?.count ?? 0
    }

    private var monthRowCount: Int { (leadingBlankDays + monthDayCount + 6) / 7 }

    private func dateForCell(_ index: Int) -> Date? {
        let offset = index - leadingBlankDays
        guard (0..<monthDayCount).contains(offset) else { return nil }
        return calendar.date(byAdding: .day, value: offset, to: monthStart(for: visibleMonth))
            .map { calendar.startOfDay(for: $0) }
    }

    private func monthStart(for date: Date) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    private func clampVisibleMonth() {
        visibleMonth = min(max(monthStart(for: visibleMonth), monthStart(for: periodStart)), monthStart(for: periodEnd))
    }

    private var maximumEndDate: Date {
        calendar.date(byAdding: .day, value: StudySchedule.maximumDayCount - 1, to: periodStart) ?? periodStart
    }

    private var startDateBinding: Binding<Date> {
        Binding(get: { periodStart }, set: { schedule.startDate = calendar.startOfDay(for: $0) })
    }

    private var endDateBinding: Binding<Date> {
        Binding(get: { periodEnd }, set: { schedule.endDate = calendar.startOfDay(for: $0) })
    }

    private func selectionValue(_ selected: Bool) -> String {
        selected ? L10n.text("選択済み", "Selected") : L10n.text("未選択", "Not selected")
    }

    private var weekdayHelp: String {
        L10n.text(
            "曜日を変えると日付の個別調整はリセットされます。曜日を選ばず、日付だけでも指定できます。",
            "Changing weekdays resets individual date edits. You can also leave weekdays off and pick dates below."
        )
    }

    private var dateSelectionHelp: String {
#if os(macOS)
        L10n.text("日付をクリックして追加・除外。下線は今日です。", "Click a date to add or remove it. Today is underlined.")
#else
        L10n.text("日付をタップして追加・除外。下線は今日です。", "Tap a date to add or remove it. Today is underlined.")
#endif
    }

    private var progressHelp: String {
        L10n.text(
            "残り日数には今日を含みます。進捗は選んだ日が過ぎた割合で、学習の完了記録ではありません。",
            "Remaining days include today. Progress measures selected days that have passed, not completed study sessions."
        )
    }

    private func shortWeekdayName(_ weekday: Int) -> String {
        let japanese = ["日", "月", "火", "水", "木", "金", "土"]
        let english = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return L10n.isJapanese ? japanese[weekday - 1] : english[weekday - 1]
    }

    private func fullWeekdayName(_ weekday: Int) -> String {
        let japanese = ["日曜日", "月曜日", "火曜日", "水曜日", "木曜日", "金曜日", "土曜日"]
        let english = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return L10n.isJapanese ? japanese[weekday - 1] : english[weekday - 1]
    }

    private func dateAccessibilityLabel(_ date: Date, isToday: Bool) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: L10n.isJapanese ? "ja_JP" : "en_US")
        formatter.dateStyle = .full
        return formatter.string(from: date) + (isToday ? L10n.text("、今日", ", today") : "")
    }
}
