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
                            Label(L10n.text("人生の基準を編集", "Edit life reference points"), systemImage: "pencil")
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
