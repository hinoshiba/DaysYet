import AppKit
import SwiftUI

struct MacSettingsView: View {
    @ObservedObject var store: ProfileStore
    @ObservedObject var preferences: MacWidgetPreferences
    @ObservedObject var controller: MacWidgetController

    @State private var showResetConfirmation = false
    @State private var selectedDocument: MacLegalDocument?

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                widgetSettings
                    .tabItem { Label(L10n.text("ウィジェット", "Widget"), systemImage: "rectangle.righthalf.inset.filled") }
                timelineSettings
                    .tabItem { Label(L10n.text("時間", "Timelines"), systemImage: "calendar.badge.clock") }
                privacySettings
                    .tabItem { Label(L10n.text("プライバシーと情報", "Privacy & About"), systemImage: "hand.raised") }
            }
            .padding(12)

            HStack {
                Spacer()
                Button(L10n.text("DaysYetを終了", "Quit DaysYet")) {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .frame(minWidth: 680, idealWidth: 760, minHeight: 560, idealHeight: 620)
        .sheet(item: $selectedDocument) { document in
            MacLegalDocumentView(document: document)
        }
        .alert(
            L10n.text("このMacのデータをすべて消去しますか？", "Delete all data on this Mac?"),
            isPresented: $showResetConfirmation
        ) {
            Button(L10n.text("キャンセル", "Cancel"), role: .cancel) {}
            Button(L10n.text("すべて消去", "Delete All"), role: .destructive) {
                store.reset()
                controller.resetPreferences()
            }
        } message: {
            Text(L10n.text(
                "入力した日付、目標、表示設定、ウィジェットの位置を初期設定に戻します。この操作は取り消せません。",
                "Your dates, goals, appearance, and widget position will return to their defaults. This cannot be undone."
            ))
        }
    }

    private var widgetSettings: some View {
        HStack(spacing: 0) {
            previewSidebar
                .frame(width: 224)
            Divider()
            Form {
                Section {
                    Toggle(L10n.text("画面の端に表示", "Show at the screen edge"), isOn: visibilityBinding)
                    if !preferences.isVisible {
                        Text(L10n.text(
                            "非表示にした場合は、DaysYetをもう一度起動して設定を開けます。",
                            "When the widget is hidden, open DaysYet again to access settings."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Toggle(L10n.text("詳細を開いたままにする", "Keep details open"), isOn: $preferences.keepDetailsOpen)
                    widgetSizeControl
                } header: {
                    Text(L10n.text("常駐表示", "Resident widget"))
                } footer: {
                    Text(L10n.text(
                        "ポインタを重ねると、同じ黒い面が広がってコンパクトな詳細を表示します。左右では、選んだサークルの高さに詳細がなめらかに移動します。ダブルクリックで設定を開きます。",
                        "Hover to reveal compact details within the same black surface. At either side, details glide to the height of the selected circle. Double-click to open settings."
                    ))
                }

                Section(L10n.text("位置", "Position")) {
                    Picker(L10n.text("画面の端", "Screen edge"), selection: $preferences.edge) {
                        ForEach(MacWidgetEdge.allCases) { edge in
                            Text(edge.title).tag(edge)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker(L10n.text("ディスプレイ", "Display"), selection: $preferences.displayID) {
                        Text(L10n.text("自動（メイン画面）", "Automatic (main display)")).tag("")
                        ForEach(controller.displays) { display in
                            Text(display.name).tag(display.id)
                        }
                        if !preferences.displayID.isEmpty,
                           !controller.displays.contains(where: { $0.id == preferences.displayID }) {
                            Text(L10n.text("未接続のディスプレイ", "Disconnected display"))
                                .tag(preferences.displayID)
                        }
                    }

                    if preferences.edge == .top {
                        Text(L10n.text(
                            "カメラの切り欠きの下に、サイズに合わせた厚みの進捗バーを表示します。バーのすぐ上でも項目を選べます。ノッチにポインタを重ねると詳細が開きます。切り欠きのない画面では、上端の中央に表示します。",
                            "A progress strip sits below the camera notch, with thickness controlled by the widget size. You can select a timeline just above its bar, too. Hover over the notch to open details. Displays without a notch use the top center."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(L10n.text("上下の位置", "Vertical position"))
                                Spacer()
                                Button(L10n.text("中央に戻す", "Center")) { controller.recenter() }
                                    .controlSize(.small)
                            }
                            Slider(value: $preferences.verticalPosition, in: 0...1) {
                                Text(L10n.text("上下の位置", "Vertical position"))
                            } minimumValueLabel: {
                                Text(L10n.text("上", "Top")).font(.caption)
                            } maximumValueLabel: {
                                Text(L10n.text("下", "Bottom")).font(.caption)
                            }
                            .labelsHidden()
                            .accessibilityLabel(L10n.text("上下の位置", "Vertical position"))
                            .accessibilityValue(L10n.text(
                                "上から\(Int(preferences.verticalPosition * 100))パーセント",
                                "\(Int(preferences.verticalPosition * 100)) percent from top"
                            ))
                            Text(L10n.text(
                                "ウィジェット本体を上下にドラッグして移動できます。移動した位置は自動で保存されます。",
                                "Drag the widget up or down to move it. Its position is saved automatically."
                            ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                Section(L10n.text("表示", "Appearance")) {
                    Picker(L10n.text("詳細の表示モード", "Detail display mode"), selection: binding(\.widgetDisplayMode)) {
                        ForEach(WidgetDisplayMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)

                    if store.profile.widgetDisplayMode == .progressBars {
                        Picker(L10n.text("バーの値", "Bar value"), selection: binding(\.dashboardValueStyle)) {
                            ForEach(MetricValueStyle.allCases) { style in
                                Text(style.title).tag(style)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        Text(L10n.text("テーマ", "Theme"))
                        HStack(spacing: 8) {
                            ForEach(WidgetTheme.allCases) { theme in
                                themeButton(theme)
                            }
                        }
                        Text(store.profile.widgetTheme.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            .formStyle(.grouped)
        }
    }

    private var widgetSizeControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.text("ウィジェットのサイズ", "Widget size"))
                Spacer()
                Text("\(Int((preferences.scale * 100).rounded()))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Button(L10n.text("標準に戻す", "Reset Size")) { preferences.scale = 1 }
                    .controlSize(.small)
                    .disabled(abs(preferences.scale - 1) < 0.001)
                    .help(L10n.text("サイズを100%に戻します", "Reset widget size to 100%"))
            }
            Slider(value: $preferences.scale, in: 0.8...1.5, step: 0.1) {
                Text(L10n.text("ウィジェットのサイズ", "Widget size"))
            } minimumValueLabel: {
                Text("80%").font(.caption)
            } maximumValueLabel: {
                Text("150%").font(.caption)
            }
            .labelsHidden()
            .accessibilityLabel(L10n.text("ウィジェットのサイズ", "Widget size"))
            .accessibilityValue("\(Int((preferences.scale * 100).rounded()))%")
            Text(preferences.edge == .top ? L10n.text(
                "横幅・バーの厚み・詳細の文字サイズが一緒に変わります。カメラの切り欠き自体の高さは変わりません。",
                "Width, bar thickness, and detail text scale together. The camera notch height stays unchanged."
            ) : L10n.text(
                "サークルと文字が一緒に拡大・縮小されます。",
                "Circles and text scale together."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            if preferences.edge == .top {
                let thickness = (8 * preferences.scale).formatted(.number.precision(.fractionLength(1)))
                Text(L10n.text(
                    "カメラ下の厚み \(thickness) pt",
                    "Thickness below camera: \(thickness) pt"
                ))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var previewSidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("DaysYet")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                Text(L10n.text("時間を、そっと視界に。", "Time, quietly in view."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            MacPlacementPreview(profile: store.profile, edge: preferences.edge, position: preferences.verticalPosition, scale: preferences.scale)
                .frame(height: 150)
                .accessibilityLabel(L10n.text("画面の端に表示するウィジェットのプレビュー", "Preview of the widget at the screen edge"))

            Text(L10n.text(
                "今週、今月、今年。\n3つの時間を、デスクトップの端に。",
                "Your week, month, and year.\nThree timelines at the edge of your desktop."
            ))
            .font(.callout)
            .lineSpacing(3)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Button {
                controller.showWidget()
            } label: {
                Label(
                    L10n.text("ウィジェットを表示", "Show Widget"),
                    systemImage: preferences.edge == .top ? "rectangle.topthird.inset.filled"
                        : preferences.edge == .left ? "sidebar.left" : "sidebar.right"
                )
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer(minLength: 10)

            Label(L10n.text("アカウント不要・端末内に保存", "No account. Stored on this Mac."), systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var timelineSettings: some View {
        Form {
            Section {
                ForEach(0..<3, id: \.self) { index in
                    Picker(
                        L10n.text("\(index + 1)つ目の時間", "Timeline \(index + 1)"),
                        selection: Binding(
                            get: { store.profile.normalizedDashboardMetrics[index] },
                            set: { store.setDashboardMetric($0, at: index) }
                        )
                    ) {
                        ForEach(MetricKind.allCases) { metric in
                            Label(metric.title, systemImage: metric.symbolName).tag(metric)
                        }
                    }
                }
            } header: {
                Text(L10n.text("表示する3つの時間", "Your three timelines"))
            } footer: {
                Text(L10n.text(
                    "すでに表示中の時間を選ぶと、順番を入れ替えます。今週・今月・今年は日付の入力なしで使えます。",
                    "Selecting a timeline already in use swaps its position. Week, month, and year work without entering any dates."
                ))
            }

            weekStartSection

            workHoursSection

            Section {
                DatePicker(
                    L10n.text("生年月日", "Birth date"),
                    selection: personalBinding(\.birthDate),
                    in: ...Date.now,
                    displayedComponents: .date
                )
                Stepper(value: personalBinding(\.healthyLifeYears), in: 50...110, step: 1) {
                    LabeledContent(
                        L10n.text("健康でいたい年齢", "Healthy-age goal"),
                        value: L10n.text("\(Int(store.profile.healthyLifeYears))歳", "Age \(Int(store.profile.healthyLifeYears))")
                    )
                }
            } header: {
                Text(L10n.text("健康目標（任意）", "Healthy-age goal (optional)"))
            } footer: {
                Text(L10n.text(
                    "ご自身で決める計画上の目標です。健康状態や寿命の予測ではありません。",
                    "A personal planning marker you choose. It does not predict health or lifespan."
                ))
            }

            Section {
                TextField(L10n.text("名前", "Name"), text: personalBinding(\.customTargetName), prompt: Text(L10n.text("大切な日", "A milestone")))
                DatePicker(
                    L10n.text("起算日", "Start date"),
                    selection: milestoneStartBinding,
                    displayedComponents: .date
                )
                DatePicker(
                    L10n.text("目標日時", "Target date"),
                    selection: personalBinding(\.customTargetDate),
                    in: minimumMilestoneTarget...,
                    displayedComponents: [.date, .hourAndMinute]
                )
            } header: {
                Text(L10n.text("大切な日（任意）", "Milestone (optional)"))
            } footer: {
                Text(L10n.text(
                    "起算日の午前0時から目標日時までの経過を表示します。設定は自動で保存されます。",
                    "Progress runs from midnight on the start date to the target time. Changes save automatically."
                ))
            }
        }
        .formStyle(.grouped)
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
            MacWorkTimeEditor(
                title: L10n.text("開始時刻", "Start time"),
                minute: binding(\.workStartMinute)
            )
            MacWorkTimeEditor(
                title: store.profile.workEndMinute <= store.profile.workStartMinute
                    ? L10n.text("終了時刻（翌日）", "End time (next day)")
                    : L10n.text("終了時刻", "End time"),
                minute: binding(\.workEndMinute)
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

    private var privacySettings: some View {
        Form {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.text("あなたの時間は、このMacに。", "Your time stays on this Mac."))
                            .font(.headline)
                        Text(L10n.text(
                            "日付・目標・勤務時間・表示設定はこのMac内に保存します。外部への送信、追跡、分析、広告は行いません。iPhoneやiPadとの同期も行いません。",
                            "Dates, goals, work hours, and display preferences are saved on this Mac. No data transmission, tracking, analytics, or ads. There is no sync with iPhone or iPad."
                        ))
                        .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "hand.raised.fill")
                        .foregroundStyle(.green)
                }
                Link(L10n.text("公開プライバシーポリシー", "Public privacy policy"), destination: MacProjectLinks.privacy)
                Button(L10n.text("このMacのデータをすべて消去…", "Delete all data on this Mac…"), role: .destructive) {
                    showResetConfirmation = true
                }
            } header: {
                Text(L10n.text("プライバシー", "Privacy"))
            }

            Section(L10n.text("このアプリについて", "About DaysYet")) {
                LabeledContent(L10n.text("バージョン", "Version"), value: appVersion)
                Link(L10n.text("Webサイト", "Website"), destination: MacProjectLinks.website)
                Link(L10n.text("サポート", "Support"), destination: MacProjectLinks.support)
                Link(L10n.text("ソースコード", "Source code"), destination: MacProjectLinks.source)
            }

            Section {
                ForEach(MacLegalDocument.all) { document in
                    Button {
                        selectedDocument = document
                    } label: {
                        HStack {
                            Text(document.title)
                            Spacer()
                            Image(systemName: "doc.text")
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text(L10n.text("ライセンスと出典", "Licenses & sources"))
            } footer: {
                Text(L10n.text("同梱文書はオフラインでも読めます。", "Bundled documents are available offline."))
            }
        }
        .formStyle(.grouped)
    }

    private var visibilityBinding: Binding<Bool> {
        Binding(
            get: { preferences.isVisible },
            set: { $0 ? controller.showWidget() : controller.hideWidget() }
        )
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<UserProfile, Value>) -> Binding<Value> {
        Binding(get: { store.profile[keyPath: keyPath] }, set: { newValue in
            store.update { $0[keyPath: keyPath] = newValue }
        })
    }

    private func personalBinding<Value>(_ keyPath: WritableKeyPath<UserProfile, Value>) -> Binding<Value> {
        Binding(get: { store.profile[keyPath: keyPath] }, set: { newValue in
            store.update {
                $0[keyPath: keyPath] = newValue
                $0.isConfigured = true
            }
        })
    }

    private var minimumMilestoneTarget: Date {
        store.profile.customTargetStartDate.addingTimeInterval(60)
    }

    private var milestoneStartBinding: Binding<Date> {
        Binding(get: { store.profile.customTargetStartDate }, set: { newValue in
            store.update { profile in
                profile.customTargetStartDate = Calendar.autoupdatingCurrent.startOfDay(for: newValue)
                let minimum = profile.customTargetStartDate.addingTimeInterval(60)
                if profile.customTargetDate < minimum {
                    profile.customTargetDate = Calendar.autoupdatingCurrent.date(
                        byAdding: .year, value: 1, to: profile.customTargetStartDate
                    ) ?? minimum
                }
                profile.isConfigured = true
            }
        })
    }

    private func themeButton(_ theme: WidgetTheme) -> some View {
        let isSelected = store.profile.widgetTheme == theme
        return Button {
            store.update { $0.widgetTheme = theme }
        } label: {
            HStack(spacing: 6) {
                ForEach(Array(MetricKind.allCases.prefix(3))) { metric in
                    ZStack {
                        Circle().stroke(.white.opacity(0.17), lineWidth: 1.5)
                        Circle()
                            .trim(from: 0, to: 0.72)
                            .stroke(MacWidgetStyle.accent(for: metric, theme: theme), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 11, height: 11)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background(MacWidgetStyle.background, in: RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(isSelected ? Color.accentColor : .primary.opacity(0.12), lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .help(theme.title)
        .accessibilityLabel(theme.title)
        .accessibilityHint(L10n.text(
            "黒いウィジェットに、\(theme.title)のアクセントカラー",
            "\(theme.title) accent colors on a black widget"
        ))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }
}

/// Keeps NSDatePicker's hidden date intact when its clock rolls past midnight.
/// Only wall-clock minutes belong to the saved, repeating work schedule.
struct MacWorkTimeEditorState {
    private(set) var date: Date

    init(minute: Int, calendar: Calendar) {
        let minute = UserProfile.clampedWorkMinute(minute)
        date = calendar.date(from: DateComponents(
            year: 2001, month: 1, day: 15, hour: minute / 60, minute: minute % 60
        )) ?? calendar.startOfDay(for: .now)
    }

    mutating func accept(_ value: Date, calendar: Calendar) -> Int {
        date = value
        return clockMinute(in: calendar)
    }

    mutating func synchronize(minute: Int, calendar: Calendar) {
        let minute = UserProfile.clampedWorkMinute(minute)
        // The store echoes every edit. Rebuilding its date here would undo a
        // step from 23:00 into the next day while the native field is editing.
        guard clockMinute(in: calendar) != minute else { return }
        date = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: date,
                             matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward) ?? date
    }

    private func clockMinute(in calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}

private struct MacWorkTimeEditor: View {
    let title: String
    @Binding var minute: Int
    @State private var editor: MacWorkTimeEditorState
    @Environment(\.timeZone) private var timeZone

    init(title: String, minute: Binding<Int>) {
        self.title = title
        _minute = minute
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        _editor = State(initialValue: MacWorkTimeEditorState(minute: minute.wrappedValue, calendar: calendar))
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    var body: some View {
        DatePicker(title, selection: Binding(
            get: { editor.date },
            set: { value in minute = editor.accept(value, calendar: calendar) }
        ), displayedComponents: .hourAndMinute)
        .environment(\.calendar, calendar)
        .onChange(of: minute, initial: true) { _, value in
            editor.synchronize(minute: value, calendar: calendar)
        }
        .onChange(of: timeZone) { _, _ in
            editor.synchronize(minute: minute, calendar: calendar)
        }
    }
}

private struct MacPlacementPreview: View {
    let profile: UserProfile
    let edge: MacWidgetEdge
    let position: Double
    let scale: Double

    var body: some View {
        GeometryReader { geometry in
            // Keep space for the largest setting while showing the relative size.
            let previewScale = 0.75 * min(max(scale, 0.8), 1.5)
            let widgetWidth = 27 * previewScale
            let widgetHeight = 104 * previewScale
            ZStack(alignment: .topLeading) {
                LinearGradient(
                    colors: [Color(red: 0.24, green: 0.29, blue: 0.42), Color(red: 0.08, green: 0.11, blue: 0.20)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                Circle()
                    .fill(MacWidgetStyle.accent(for: .month, theme: profile.widgetTheme).opacity(0.22))
                    .frame(width: 160, height: 160)
                    .blur(radius: 30)
                    .offset(x: -70, y: 20)
                HStack(spacing: 3) {
                    Image(systemName: "apple.logo")
                    Text("DaysYet").fontWeight(.semibold)
                    Spacer()
                    Image(systemName: "wifi")
                }
                .font(.system(size: 5))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 7)
                .frame(height: 11)
                .background(.white.opacity(0.08))

                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(0..<6, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.white.opacity(index == 2 ? 0.8 : 0.25))
                            .frame(width: 10, height: 10)
                    }
                }
                .padding(5)
                .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 6))
                .frame(maxWidth: .infinity)
                .offset(y: geometry.size.height - 25)

                if edge == .top {
                    let topWidth = max(36, 64 * previewScale)
                    // Use 3/8 of the native 32-point camera and 8-point strip.
                    let cameraHeight = 12.0
                    let extraThickness = 3 * min(max(scale, 0.8), 1.5)
                    let lineThickness = 0.75 * min(max(scale, 0.8), 1.5)
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0, bottomLeadingRadius: 3,
                        bottomTrailingRadius: 3, topTrailingRadius: 0
                    )
                        .fill(MacWidgetStyle.background)
                        .frame(width: topWidth, height: cameraHeight + extraThickness)
                        .overlay(alignment: .topLeading) {
                            HStack(spacing: 2) {
                                ForEach(profile.normalizedDashboardMetrics) { kind in
                                    let snapshot = TimeProgressCalculator.snapshot(for: kind, profile: profile)
                                    GeometryReader { track in
                                        Capsule().fill(.white.opacity(0.16))
                                            .overlay(alignment: .leading) {
                                                Capsule()
                                                    .fill(MacWidgetStyle.accent(for: kind, theme: profile.widgetTheme))
                                                    .frame(width: track.size.width * snapshot.elapsedFraction)
                                            }
                                    }
                                }
                            }
                            .frame(width: topWidth - 10, height: lineThickness)
                            .offset(x: 5, y: cameraHeight + (extraThickness - lineThickness) / 2)
                        }
                        .offset(x: (geometry.size.width - topWidth) / 2)
                } else {
                    VStack(spacing: 7) {
                        ForEach(profile.normalizedDashboardMetrics) { kind in
                            previewMetric(kind)
                        }
                    }
                    .frame(width: 27, height: 104)
                    .background(MacWidgetStyle.background, in: MacEdgeNotchShape(edge: edge))
                    .scaleEffect(previewScale, anchor: .topLeading)
                    .frame(width: widgetWidth, height: widgetHeight, alignment: .topLeading)
                    .offset(
                        x: edge == .right ? geometry.size.width - widgetWidth : 0,
                        y: 14 + max(geometry.size.height - 28 - widgetHeight, 0) * min(max(position, 0), 1)
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.15), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .ignore)
    }

    private func previewMetric(_ kind: MetricKind) -> some View {
        let snapshot = TimeProgressCalculator.snapshot(for: kind, profile: profile)
        let accent = MacWidgetStyle.accent(for: kind, theme: profile.widgetTheme)
        return MacPercentageRing(fraction: snapshot.elapsedFraction, accent: accent)
            .scaleEffect(0.5625)
            .frame(width: 18, height: 18)
    }
}

private enum MacProjectLinks {
    static let source = URL(string: "https://github.com/hinoshiba/DaysYet")!
    static let website = URL(string: "https://daysyet.hinoshiba.com/\(L10n.isJapanese ? "" : "en/")")!
    static let privacy = URL(string: "#privacy", relativeTo: website)!.absoluteURL
    static let support = URL(string: "#support", relativeTo: website)!.absoluteURL
}

private struct MacLegalDocument: Identifiable {
    let title: String
    let resource: String
    let fileExtension: String?

    var id: String { resource }

    static var all: [MacLegalDocument] {
        [
            MacLegalDocument(title: "Apache License 2.0", resource: "LICENSE", fileExtension: nil),
            MacLegalDocument(title: "NOTICE", resource: "NOTICE", fileExtension: nil),
            MacLegalDocument(title: L10n.text("第三者ライセンス台帳", "Third-party notices"), resource: "THIRD_PARTY_NOTICES", fileExtension: "md"),
            MacLegalDocument(title: L10n.text("素材の権利台帳", "Asset license register"), resource: "ASSET_LICENSES", fileExtension: "md"),
            MacLegalDocument(title: L10n.text("データ出典台帳", "Data source register"), resource: "DATA_SOURCES", fileExtension: "md")
        ]
    }
}

private struct MacLegalDocumentView: View {
    @Environment(\.dismiss) private var dismiss
    let document: MacLegalDocument

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(document.title).font(.headline)
                Spacer()
                Button(L10n.text("完了", "Done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
            Divider()
            ScrollView {
                Text(contents)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
        }
        .frame(width: 620, height: 480)
    }

    private var contents: String {
        guard let url = Bundle.main.url(forResource: document.resource, withExtension: document.fileExtension),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return L10n.text("文書を読み込めませんでした。", "The document could not be loaded.")
        }
        return text
    }
}
