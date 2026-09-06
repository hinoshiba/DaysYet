import SwiftUI

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
                            Text(L10n.text("ウィジェットに置く3本は、ウィジェットタブで選べます。", "Choose the three shown in your widget from the Widget tab."))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.bottom, 8)

                        NavigationLink {
                            ProfileEditorView()
                        } label: {
                            Label(L10n.text("時間の基準を編集", "Edit time reference points"), systemImage: "pencil")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.roundedRectangle(radius: 16))

                        ForEach(MetricKind.allCases) { metric in
                            MetricCard(
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

struct ProfileEditorView: View {
    @EnvironmentObject private var store: ProfileStore

    var body: some View {
        Form {
            weekStartSection

            workHoursSection

            Section(L10n.text("人生の基準", "Life reference points")) {
                DatePicker(
                    L10n.text("生年月日", "Birth date"),
                    selection: binding(\.birthDate),
                    in: earliestBirthDate ... Date.now,
                    displayedComponents: .date
                )

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L10n.text("健康でいたい年齢", "Healthy-age goal"))
                        Spacer()
                        Text("\(Int(store.profile.healthyLifeYears))")
                            .monospacedDigit()
                    }
                    Slider(value: binding(\.healthyLifeYears), in: 50...110, step: 1)
                }
            }

            Section {
                TextField(L10n.text("名前", "Name"), text: binding(\.customTargetName))
                DatePicker(
                    L10n.text("起算日", "Start date"),
                    selection: milestoneStartDateBinding,
                    in: earliestMilestoneDate ... latestStartDate,
                    displayedComponents: .date
                )
                DatePicker(
                    L10n.text("目標日時", "Target date and time"),
                    selection: binding(\.customTargetDate),
                    in: minimumTargetDate ... latestTargetDate,
                    displayedComponents: [.date, .hourAndMinute]
                )
            } header: {
                Text(L10n.text("大切な日", "Milestone"))
            } footer: {
                Text(L10n.text(
                    "起算日を0%として、目標日時に100%となる経過割合を計算します。",
                    "Progress starts at 0% on the start date and reaches 100% at the target."
                ))
            }

            Section {
                Label(
                    L10n.text("「健康でいたい年齢」のバーは、ご自身で決める計画上の目標です。医学的な診断、健康状態、実際の寿命を示すものではありません。", "The healthy-age bar is a personal planning marker. It is not medical advice and does not predict health or lifespan."),
                    systemImage: "info.circle"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(L10n.text("時間を編集", "Edit Times"))
    }

    private var weekStartSection: some View {
        let weekday = store.profile.weekStartDay.resolvedTitle()
        return Section {
            Picker(L10n.text("開始曜日", "First day"), selection: binding(\.weekStartDay)) {
                ForEach(WeekStartDay.allCases) { day in
                    Text(day.title).tag(day)
                }
            }
        } header: {
            Text(L10n.text("週の始まり", "Week starts on"))
        } footer: {
            Text(L10n.text(
                "\(weekday)の午前0時から、翌週の\(weekday)の午前0時までを「今週」として表示します。",
                "“This week” runs from midnight on \(weekday) to midnight on the following \(weekday)."
            ))
        }
    }

    private var workHoursSection: some View {
        Section {
            DatePicker(
                L10n.text("開始時刻", "Start time"),
                selection: workTimeBinding(\.workStartMinute),
                displayedComponents: .hourAndMinute
            )
            DatePicker(
                store.profile.workEndMinute <= store.profile.workStartMinute
                    ? L10n.text("終了時刻（翌日）", "End time (next day)")
                    : L10n.text("終了時刻", "End time"),
                selection: workTimeBinding(\.workEndMinute),
                displayedComponents: .hourAndMinute
            )
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let snapshot = TimeProgressCalculator.snapshot(for: .workday, profile: store.profile, now: context.date)
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent(L10n.text("現在", "Now"), value: snapshot.remainingText)
                    ProgressView(value: snapshot.elapsedFraction)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(snapshot.accessibilitySummary)
            }
        } header: {
            Text(L10n.text("勤務時間", "Work hours"))
        } footer: {
            Text(workHoursDescription)
        }
    }

    private var workHoursDescription: String {
        let recurrence = L10n.text("毎日、端末の現地時刻で繰り返します。", "Repeats every day in local time. ")
        if store.profile.workEndMinute == store.profile.workStartMinute {
            return recurrence + L10n.text(
                "開始と終了が同じ時刻のため、翌日の同時刻までの24時間として扱います。",
                "Matching start and end times define a 24-hour period, ending at the same time the next day."
            )
        }
        if store.profile.workEndMinute < store.profile.workStartMinute {
            return recurrence + L10n.text(
                "終了は翌日です。勤務終了後は、次の開始時刻まで「勤務終了」と表示します。",
                "The end time is on the next day. After work ends, “Work finished” appears until the next start."
            )
        }
        return recurrence + L10n.text(
            "開始前は「開始前」、終了後は「勤務終了」と表示します。",
            "“Not started” appears before the start time and “Work finished” after the end time."
        )
    }

    private func workTimeBinding(_ keyPath: WritableKeyPath<UserProfile, Int>) -> Binding<Date> {
        // Use a fixed local date so the visual picker and accessibility value
        // describe the same clock time without depending on today's DST changes.
        Binding(
            get: {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = .autoupdatingCurrent
                let minute = store.profile[keyPath: keyPath]
                return calendar.date(from: DateComponents(
                    year: 2001, month: 1, day: 15, hour: minute / 60, minute: minute % 60
                )) ?? .now
            },
            set: { value in
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = .autoupdatingCurrent
                let components = calendar.dateComponents([.hour, .minute], from: value)
                let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
                store.update { $0[keyPath: keyPath] = minute }
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
