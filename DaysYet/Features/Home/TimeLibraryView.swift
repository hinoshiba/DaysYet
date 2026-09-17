import SwiftUI

extension MetricKind {
    /// Settings this time keeps to itself, reachable by tapping its card.
    /// Shared settings, such as the week start that also orders the study-day
    /// weekdays, stay on the Settings tab instead.
    var hasOwnSettings: Bool {
        switch self {
        case .week, .month, .year: false
        case .healthyLife, .customLife, .activity, .workday, .study: true
        }
    }
}

struct TimeLibraryView: View {
    @EnvironmentObject private var store: ProfileStore

    var body: some View {
        ZStack {
            DaysYetBackground(theme: store.profile.widgetTheme)
            TimelineView(.periodic(from: .now, by: 60)) { context in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            EyebrowLabel(text: L10n.text("時間の一覧", "Time library"))
                            Text(L10n.text("いまを、いくつもの\n距離から見る。", "See time across\ndifferent horizons."))
                                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                                .tracking(-0.7)
                            Text(L10n.text(
                                "カードをタップすると、その時間だけの設定を開けます。ウィジェットに置く3本は、ウィジェットタブで選べます。",
                                "Tap a card to edit that time’s own settings. Choose the three shown in your widget from the Widget tab."
                            ))
                            .foregroundStyle(.secondary)
                        }
                        .padding(.bottom, 8)

                        ForEach(MetricKind.allCases) { metric in
                            MetricLibraryRow(
                                snapshot: TimeProgressCalculator.snapshot(
                                    for: metric,
                                    profile: store.profile,
                                    now: context.date
                                ),
                                valueStyle: store.profile.dashboardValueStyle,
                                theme: store.profile.widgetTheme
                            )
                        }

                    }
                    .padding(20)
                    .padding(.bottom, 24)
                }
            }
        }
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct MetricLibraryRow: View {
    let snapshot: MetricSnapshot
    let valueStyle: MetricValueStyle
    let theme: WidgetTheme

    var body: some View {
        if snapshot.kind.hasOwnSettings {
            NavigationLink {
                MetricSettingsView(kind: snapshot.kind)
            } label: {
                MetricCard(
                    snapshot: snapshot,
                    valueStyle: valueStyle,
                    theme: theme,
                    showsSettingsAffordance: true
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("times.metric.\(snapshot.kind.rawValue)")
        } else {
            MetricCard(snapshot: snapshot, valueStyle: valueStyle, theme: theme)
        }
    }
}

/// The settings that belong to a single time, opened from its card in Times.
struct MetricSettingsView: View {
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
                    weekStartDay: store.profile.weekStartDay
                )
            case .activity, .workday:
                Form { activityHoursSection(for: kind) }
            case .healthyLife:
                Form { healthyLifeSection }
            case .customLife:
                Form { milestoneSection }
            case .week, .month, .year:
                Form { sharedSettingsNotice }
            }
        }
        .navigationTitle(kind.title(profile: store.profile))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    private var sharedSettingsNotice: some View {
        Section {
            Label(
                L10n.text(
                    "この時間に固有の設定はありません。週の始まりなど、複数の時間に関わる設定は設定タブにあります。",
                    "This time has no settings of its own. Settings shared by several times, such as the week start, live on the Settings tab."
                ),
                systemImage: "info.circle"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
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
