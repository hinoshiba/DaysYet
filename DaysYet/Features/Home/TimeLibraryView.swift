import SwiftUI

extension MetricKind {
    /// Times with editable content are opened from their rows.
    var hasEditableSettings: Bool {
        switch self {
        case .month, .year: false
        case .week, .healthyLife, .customLife, .activity, .workday, .study: true
        }
    }
}

struct TimeLibraryView: View {
    @EnvironmentObject private var store: ProfileStore
    let openColorSettings: (MetricKind) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Form {
                Section {
                    ForEach(MetricKind.allCases) { metric in
                        MetricLibraryRow(
                            snapshot: TimeProgressCalculator.snapshot(
                                for: metric,
                                profile: store.profile,
                                now: context.date
                            ),
                            valueStyle: store.profile.dashboardValueStyle,
                            theme: store.profile.widgetTheme,
                            customColors: store.profile.widgetCustomColors,
                            editColor: { openColorSettings(metric) }
                        )
                    }
                } header: {
                    Text(L10n.text("時間の一覧", "Time library"))
                } footer: {
                    Text(L10n.text(
                        "時刻・日付など、時間の内容を編集できます。長押しで色を変更します。ウィジェットに表示する時間は「ウィジェット」タブで選びます。",
                        "Edit schedules, dates, and other details here. Touch and hold to change a color. Choose which times to display in the Widget tab."
                    ))
                }
                .listRowBackground(DaysYetTheme.panel)

                AppInfoSection()
            }
        }
        .daysYetBackground()
        .navigationTitle(L10n.text("時間", "Times"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                UsageGuideLink(accessibilityIdentifier: "times.guide")
            }
        }
    }
}

private struct MetricLibraryRow: View {
    let snapshot: MetricSnapshot
    let valueStyle: MetricValueStyle
    let theme: WidgetTheme
    let customColors: [MetricKind: WidgetColor]
    let editColor: () -> Void
    @State private var showsEditor = false

    var body: some View {
        Group {
            if snapshot.kind.hasEditableSettings {
                Button {
                    showsEditor = true
                } label: {
                    MetricSummaryRow(
                        snapshot: snapshot,
                        valueStyle: valueStyle,
                        theme: theme,
                        customColors: customColors,
                        showsEditAction: true
                    )
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showsEditor) {
                    MetricSettingsView(kind: snapshot.kind)
                }
            } else {
                MetricSummaryRow(snapshot: snapshot, valueStyle: valueStyle, theme: theme, customColors: customColors)
            }
        }
        .contextMenu {
            Button(action: editColor) {
                Label(L10n.text("色を変更", "Change color"), systemImage: "paintpalette")
            }
            .accessibilityIdentifier("times.color.change")
        }
        .accessibilityAction(named: Text(L10n.text("色を変更", "Change color"))) { editColor() }
        .accessibilityIdentifier("times.metric.\(snapshot.kind.rawValue)")
    }
}

/// The settings that belong to a single time, opened from its row in Times.
struct MetricSettingsView: View {
    @EnvironmentObject private var store: ProfileStore
    let kind: MetricKind

    var body: some View {
        TimeEditor(profile: store.profile, metric: kind) { draft in
            store.saveMetricSettings(kind, from: draft)
        }
    }
}

/// Fields only: the presenting editor owns the draft and its Save/Cancel actions.
struct MetricSettingsContent: View {
    @EnvironmentObject private var store: ProfileStore
    let kind: MetricKind

    var body: some View {
        Group {
            switch kind {
            case .study:
                StudyScheduleEditor(
                    schedule: Binding(
                        get: { store.profile.studySchedule },
                        set: { value in store.update { $0.studySchedule = value } }
                    ),
                    weekStartDay: store.profile.weekStartDay,
                    panelBackground: DaysYetTheme.panel,
                    selectedDayForeground: DaysYetTheme.onAccent
                )
            default:
                Form { MetricSettingsFormContent(kind: kind) }
            }
        }
        .daysYetBackground()
        .navigationTitle(kind.title(profile: store.profile))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}

/// Uses the same app surface as the editor and updates only its draft.
private struct WeekStartPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: WeekStartDay

    var body: some View {
        List {
            Section {
                ForEach(WeekStartDay.allCases) { day in
                    Button {
                        selection = day
                        dismiss()
                    } label: {
                        HStack {
                            Text(day.title)
                                .foregroundStyle(.primary)
                            Spacer()
                            if selection == day {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                                    .accessibilityHidden(true)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == day ? .isSelected : [])
                }
            }
            .listRowBackground(DaysYetTheme.panel)
        }
        .daysYetBackground()
        .navigationTitle(L10n.text("開始曜日", "First day"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Editable fields for a time in the library.
struct MetricSettingsFormContent: View {
    @EnvironmentObject private var store: ProfileStore
    let kind: MetricKind

    var body: some View {
        switch kind {
        case .activity, .workday: activityHoursSection(for: kind).listRowBackground(DaysYetTheme.panel)
        case .healthyLife: healthyLifeSection.listRowBackground(DaysYetTheme.panel)
        case .customLife: milestoneSection.listRowBackground(DaysYetTheme.panel)
        case .week: weekStartSection.listRowBackground(DaysYetTheme.panel)
        case .month, .year, .study: EmptyView()
        }
    }

    private var weekStartSection: some View {
        let weekday = store.profile.weekStartDay.resolvedTitle()
        return Section {
            NavigationLink {
                WeekStartPicker(selection: binding(\.weekStartDay))
            } label: {
                LabeledContent(L10n.text("開始曜日", "First day"), value: store.profile.weekStartDay.title)
            }
            .accessibilityIdentifier("week.startDay")
        } header: {
            Text(L10n.text("週の始まり", "Week starts on"))
        } footer: {
            Text(L10n.text(
                "\(weekday)の午前0時から、翌週の\(weekday)の午前0時までを「今週」として表示します。学習カレンダーの曜日の並びにも反映されますが、選んだ学習日は変わりません。",
                "“This week” runs from midnight on \(weekday) to midnight on the following \(weekday). This also changes the weekday order in Study days, without changing your selected dates."
            ))
        }
    }

    private var healthyLifeSection: some View {
        Section {
            DatePicker(
                L10n.text("生年月日", "Birth date"),
                selection: binding(\.birthDate),
                in: earliestBirthDate ... Date.now,
                displayedComponents: .date
            )
            .accessibilityIdentifier("healthyLife.birthDate")

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L10n.text("健康でいたい年齢", "Healthy-age goal"))
                    Spacer()
                    Text("\(Int(store.profile.healthyLifeYears))")
                        .monospacedDigit()
                }
                Slider(value: binding(\.healthyLifeYears), in: 50...110, step: 1)
                    .accessibilityIdentifier("healthyLife.years")
            }
        } header: {
            Text(L10n.text("人生の基準", "Life reference points"))
        } footer: {
            Text(L10n.text(
                "「健康でいたい年齢」は、ご自身で決める計画上の目標です。医学的な診断、健康状態、実際の寿命を示すものではありません。",
                "The healthy-age goal is a personal planning marker. It is not medical advice and does not predict health or lifespan."
            ))
        }
    }

    private var milestoneSection: some View {
        Section {
            TextField(L10n.text("名前", "Name"), text: binding(\.customTargetName))
                .accessibilityIdentifier("customLife.name")
            DatePicker(
                L10n.text("起算日", "Start date"),
                selection: milestoneStartDateBinding,
                in: earliestMilestoneDate ... latestStartDate,
                displayedComponents: .date
            )
            .accessibilityIdentifier("customLife.startDate")
            DatePicker(
                L10n.text("目標日時", "Target date and time"),
                selection: binding(\.customTargetDate),
                in: minimumTargetDate ... latestTargetDate,
                displayedComponents: [.date, .hourAndMinute]
            )
            .accessibilityIdentifier("customLife.targetDate")
        } header: {
            Text(L10n.text("大切な日", "Milestone"))
        } footer: {
            Text(L10n.text(
                "起算日を100%として、目標日時に0%となる残りの割合を計算します。",
                "The remaining percentage starts at 100% on the start date and reaches 0% at the target."
            ))
        }
    }

    private func activityHoursSection(for kind: MetricKind) -> some View {
        let schedule = store.profile.activitySchedule(for: kind)
        let slotTitle = ActivityScheduleEditorText.title(for: kind)
        return Section {
            TextField(
                L10n.text("ラベル", "Label"),
                text: activityBinding(for: kind, \.name),
                prompt: Text(kind.title)
            )
            .accessibilityLabel("\(slotTitle)、\(L10n.text("ラベル", "Label"))")
            .accessibilityIdentifier("\(kind.rawValue).name")
            DatePicker(
                L10n.text("開始時刻", "Start time"),
                selection: activityTimeBinding(for: kind, \.startMinute),
                displayedComponents: .hourAndMinute
            )
            .accessibilityLabel("\(slotTitle)、\(L10n.text("開始時刻", "Start time"))")
            .accessibilityIdentifier("\(kind.rawValue).startTime")
            DatePicker(
                ActivityScheduleEditorText.endTimeTitle(for: schedule),
                selection: activityTimeBinding(for: kind, \.endMinute),
                displayedComponents: .hourAndMinute
            )
            .accessibilityLabel("\(slotTitle)、\(ActivityScheduleEditorText.endTimeTitle(for: schedule))")
            .accessibilityIdentifier("\(kind.rawValue).endTime")
            ActivityWeekdayPicker(
                activeWeekdays: activityBinding(for: kind, \.activeWeekdays),
                slotTitle: slotTitle,
                identifier: kind.rawValue
            )
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let snapshot = TimeProgressCalculator.snapshot(for: kind, profile: store.profile, now: context.date)
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent(L10n.text("現在", "Now"), value: snapshot.remainingText)
                    if !snapshot.isOff {
                        ProgressView(value: snapshot.remainingFraction)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(snapshot.accessibilitySummary)
            }
        } header: {
            Text(slotTitle)
        } footer: {
            Text(ActivityScheduleEditorText.description(for: kind, schedule: schedule))
        }
    }

    private func activityBinding<Value>(
        for kind: MetricKind,
        _ keyPath: WritableKeyPath<ActivitySchedule, Value>
    ) -> Binding<Value> {
        Binding(
            get: { store.profile.activitySchedule(for: kind)[keyPath: keyPath] },
            set: { value in
                store.update { profile in
                    profile.updateActivitySchedule(for: kind) { $0[keyPath: keyPath] = value }
                }
            }
        )
    }

    private func activityTimeBinding(
        for kind: MetricKind,
        _ keyPath: WritableKeyPath<ActivitySchedule, Int>
    ) -> Binding<Date> {
        // Use a fixed local date so the visual picker and accessibility value
        // describe the same clock time without depending on today's DST changes.
        let minute = activityBinding(for: kind, keyPath)
        return Binding(
            get: {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = .autoupdatingCurrent
                let value = minute.wrappedValue
                return calendar.date(from: DateComponents(
                    year: 2001, month: 1, day: 15, hour: value / 60, minute: value % 60
                )) ?? .now
            },
            set: { value in
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = .autoupdatingCurrent
                let components = calendar.dateComponents([.hour, .minute], from: value)
                minute.wrappedValue = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            }
        )
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<UserProfile, Value>) -> Binding<Value> {
        Binding(
            get: { store.profile[keyPath: keyPath] },
            set: { value in store.update { $0[keyPath: keyPath] = value } }
        )
    }

    private var earliestBirthDate: Date {
        Calendar.current.date(from: DateComponents(year: 1900, month: 1, day: 1)) ?? .distantPast
    }

    private var earliestMilestoneDate: Date { earliestBirthDate }

    private var latestStartDate: Date {
        latestTargetDate.addingTimeInterval(-60)
    }

    private var minimumTargetDate: Date {
        store.profile.customTargetStartDate.addingTimeInterval(60)
    }

    private var milestoneStartDateBinding: Binding<Date> {
        Binding(
            get: { store.profile.customTargetStartDate },
            set: { newValue in
                store.update { profile in
                    let startDate = Calendar.autoupdatingCurrent.startOfDay(for: newValue)
                    profile.customTargetStartDate = startDate
                    let minimumTarget = startDate.addingTimeInterval(60)
                    if profile.customTargetDate < minimumTarget {
                        let suggestedTarget = Calendar.current.date(byAdding: .year, value: 1, to: startDate)
                            ?? minimumTarget
                        profile.customTargetDate = min(suggestedTarget, latestTargetDate)
                    }
                }
            }
        )
    }

    private var latestTargetDate: Date {
        Calendar.current.date(byAdding: .year, value: 100, to: .now) ?? .distantFuture
    }
}
