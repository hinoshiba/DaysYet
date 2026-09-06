import SwiftUI

enum ActivityScheduleEditorText {
    static func title(for kind: MetricKind) -> String {
        kind == .activity
            ? L10n.text("活動時間1", "Activity hours 1")
            : L10n.text("活動時間2", "Activity hours 2")
    }

    static func endTimeTitle(for schedule: ActivitySchedule) -> String {
        schedule.endMinute <= schedule.startMinute
            ? L10n.text("終了時刻（翌日）", "End time (next day)")
            : L10n.text("終了時刻", "End time")
    }

    static func description(for kind: MetricKind, schedule: ActivitySchedule) -> String {
        let purpose = kind == .activity
            ? L10n.text("私用を含めた1日の活動時間として使えます。", "Use this for your full day, including personal activities. ")
            : L10n.text("仕事など、もう1つの活動時間として使えます。", "Use this for work or another activity. ")
        if schedule.activeWeekdays.isEmpty {
            return purpose + L10n.text("すべての曜日がOffのため、活動はお休みです。", "Every weekday is Off, so this activity is paused.")
        }
        let recurrence = L10n.text(
            "Onの曜日に、端末の現地時刻で開始します。",
            "Starts on the weekdays set to On, in local time. "
        )
        if schedule.startMinute == schedule.endMinute {
            return purpose + recurrence + L10n.text(
                "開始と終了が同じ時刻のため、翌日の同時刻までの24時間です。翌日がOffでも、開始した活動は終了まで続きます。",
                "Matching times define a 24-hour period. An activity that has started continues until its end, even if the next day is Off."
            )
        }
        if schedule.endMinute < schedule.startMinute {
            return purpose + recurrence + L10n.text(
                "終了は翌日です。翌日がOffでも、開始した活動は終了まで続きます。",
                "Ends the next day. An activity that has started continues until its end, even if the next day is Off."
            )
        }
        return purpose + recurrence + L10n.text(
            "Offの曜日はお休みです。ラベルは自由に変更できます。",
            "Weekdays set to Off have no activity. You can change either label."
        )
    }
}

struct ActivityWeekdayPicker: View {
    @Binding var activeWeekdays: Set<Int>
    let slotTitle: String
    let identifier: String
    @ScaledMetric(relativeTo: .body) private var minimumDayWidth: CGFloat = 60

    // Calendar weekday values: Sunday is 1. Present the working week together.
    private let weekdays = [2, 3, 4, 5, 6, 7, 1]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("活動する曜日", "Active weekdays"))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumDayWidth), spacing: 8)], spacing: 8) {
                ForEach(weekdays, id: \.self) { weekday in
                    let isActive = activeWeekdays.contains(weekday)
                    Button {
                        if isActive {
                            activeWeekdays.remove(weekday)
                        } else {
                            activeWeekdays.insert(weekday)
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Text(shortName(for: weekday))
                                .font(.subheadline.weight(.semibold))
                            Label(isActive ? "On" : "Off", systemImage: isActive ? "checkmark.circle.fill" : "circle")
                                .font(.caption)
                        }
                        .foregroundStyle(isActive ? Color.accentColor : .secondary)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .padding(.vertical, 3)
                        .background(isActive ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(slotTitle)、\(fullName(for: weekday))")
                    .accessibilityValue(isActive ? "On" : "Off")
                    .accessibilityHint(L10n.text("この曜日の活動をOnまたはOffにします", "Turn activity on this weekday on or off"))
                    .accessibilityAddTraits(isActive ? .isSelected : [])
                    .accessibilityIdentifier("\(identifier).weekday.\(weekday)")
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func shortName(for weekday: Int) -> String {
        let japanese = ["日", "月", "火", "水", "木", "金", "土"]
        let english = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return L10n.isJapanese ? japanese[weekday - 1] : english[weekday - 1]
    }

    private func fullName(for weekday: Int) -> String {
        let japanese = ["日曜日", "月曜日", "火曜日", "水曜日", "木曜日", "金曜日", "土曜日"]
        let english = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return L10n.isJapanese ? japanese[weekday - 1] : english[weekday - 1]
    }
}
