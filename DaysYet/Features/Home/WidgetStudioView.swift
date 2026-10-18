import SwiftUI

struct WidgetStudioView: View {
    @EnvironmentObject private var store: ProfileStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showWidgetGuide = false

    var body: some View {
        ZStack {
            DaysYetBackground(theme: store.profile.widgetTheme)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    NavigationLink {
                        CircleWidgetSettingsView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "circle.grid.2x2")
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L10n.text("4つのサークル", "Four circles"))
                                    .font(.headline)
                                Text(L10n.text("4つの時間・中央の値・テーマ", "Timelines, center value, and theme"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("widget.fourCircles")

                    EyebrowLabel(text: L10n.text("3つの行", "Three rows"))

                    WidgetPreview(profile: store.profile)
                        .aspectRatio(2.05, contentMode: .fit)
                        .accessibilityLabel(L10n.text("ウィジェットプレビュー", "Widget preview"))

                    displayModeEditor

                    if store.profile.widgetDisplayMode == .progressBars {
                        valueStyleEditor
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    themeEditor

                    metricEditor

                    Button {
                        showWidgetGuide = true
                    } label: {
                        Label(L10n.text("追加方法を見る", "How to add widgets"), systemImage: "plus.square.on.square")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: 16))

                }
                .padding(20)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showWidgetGuide) {
            WidgetGuideView()
                .presentationDetents([.medium, .large])
        }
    }

    private var displayModeEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            EyebrowLabel(text: L10n.text("表示モード", "Display mode"))
            Picker(
                L10n.text("表示モード", "Display mode"),
                selection: Binding(
                    get: { store.profile.widgetDisplayMode },
                    set: { mode in
                        withAnimation(reduceMotion ? nil : .snappy) {
                            store.update { $0.widgetDisplayMode = mode }
                        }
                    }
                )
            ) {
                ForEach(WidgetDisplayMode.allCases) { mode in
                    Text(mode.shortTitle)
                        .tag(mode)
                        .accessibilityLabel(mode.title)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var themeEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                EyebrowLabel(text: L10n.text("テーマ", "Theme"))
                Text(L10n.text("気分やホーム画面に合う色を選べます。", "Choose colors that feel right at a glance."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: themeColumns, spacing: 12) {
                ForEach(WidgetTheme.allCases) { theme in
                    Button {
                        withAnimation(reduceMotion ? nil : .snappy) {
                            store.update { $0.widgetTheme = theme }
                        }
                    } label: {
                        ThemeChoiceCard(theme: theme, isSelected: store.profile.widgetTheme == theme)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(theme.title)
                    .accessibilityHint(theme.subtitle)
                    .accessibilityAddTraits(store.profile.widgetTheme == theme ? .isSelected : [])
                }
            }
        }
    }

    private var themeColumns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible())]
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            EyebrowLabel(text: L10n.text("DaysYet · ウィジェット", "DaysYet · Widgets"))
            Text(L10n.text("人生のTokenを、\n大切なことへ。", "Life’s tokens.\nMake them count."))
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .tracking(-0.7)
            Text(L10n.text("3つの行、または4つのサークルで残り時間を表示できます。", "See time remaining in three rows or four circles."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var metricEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            EyebrowLabel(text: L10n.text("3つの時間", "Your three timelines"))

            ForEach(Array(store.profile.normalizedDashboardMetrics.enumerated()), id: \.offset) { index, metric in
                Menu {
                    ForEach(MetricKind.allCases) { candidate in
                        Button {
                            withAnimation(reduceMotion ? nil : .snappy) {
                                store.setDashboardMetric(candidate, at: index)
                            }
                        } label: {
                            Label(candidate.title(profile: store.profile), systemImage: candidate.symbolName)
                        }
                    }
                } label: {
                    HStack(spacing: 14) {
                        Text("\(index + 1)")
                            .font(.caption.bold())
                            .frame(width: 28, height: 28)
                            .background(.primary.opacity(0.08), in: Circle())
                        Label(metric.title(profile: store.profile), systemImage: metric.symbolName)
                            .font(.body.weight(.semibold))
                            .lineLimit(2)
                            .truncationMode(.tail)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .padding(15)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text("\(index + 1)本目、\(metric.title(profile: store.profile))", "Bar \(index + 1), \(metric.title(profile: store.profile))"))
            }
        }
    }

    private var valueStyleEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            EyebrowLabel(text: L10n.text("バーの値", "Bar value"))
            Picker(
                L10n.text("バーの値", "Bar value"),
                selection: Binding(
                    get: { store.profile.dashboardValueStyle },
                    set: { style in store.update { $0.dashboardValueStyle = style } }
                )
            ) {
                ForEach(MetricValueStyle.allCases) { style in
                    Text(style.shortTitle).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityHint(L10n.text("3本すべての右側に表示する値を選びます", "Chooses the value shown at the right of all three bars"))

            Text(L10n.text(
                "バーは残り時間を表し、100%から0%へ右端が左に縮みます。ここでは右側に表示する値を選べます。",
                "Bars show time remaining, shrinking from right to left as they count down from 100% to 0%. Choose the value displayed on the right."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

}

struct CircleWidgetSettingsView: View {
    @EnvironmentObject private var store: ProfileStore

    var body: some View {
        Form {
            Section {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    let configuration = DaysYetCircleConfigurationIntent()
                    CircleWidgetGrid(
                        snapshots: configuration.resolvedMetrics(profile: store.profile).map {
                            TimeProgressCalculator.snapshot(for: $0, profile: store.profile, now: context.date)
                        },
                        valueStyle: configuration.resolvedValueStyle(profile: store.profile),
                        theme: configuration.resolvedTheme(profile: store.profile),
                        compact: false,
                        showsContainerBackground: true
                    )
                    .padding(16)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 340)
                    .background(configuration.resolvedTheme(profile: store.profile).palette.background, in: RoundedRectangle(cornerRadius: 24))
                    .frame(maxWidth: .infinity)
                }
                .listRowBackground(Color.clear)
            } header: {
                Text(L10n.text("プレビュー", "Preview"))
            } footer: {
                Text(L10n.text(
                    "ここで選んだ内容は「アプリの設定」を使うサークルウィジェットに反映されます。更新時刻はiOSが調整します。",
                    "These choices apply to circle widgets using App setting. Refresh timing is controlled by iOS."
                ))
            }

            Section {
                ForEach(0..<4) { index in
                    Picker(positionTitle(index), selection: metricBinding(at: index)) {
                        ForEach(MetricKind.allCases) { metric in
                            Text(metric.title(profile: store.profile)).tag(metric)
                        }
                    }
                    .accessibilityIdentifier("circle.metric.\(index)")
                }
            } header: {
                Text(L10n.text("4つの時間", "Four timelines"))
            } footer: {
                Text(L10n.text(
                    "3行表示とは別に保存します。活動時間や日付そのものは「時間」タブで編集できます。",
                    "Saved separately from Three rows. Edit schedules and dates in the Times tab."
                ))
            }

            Section {
                Picker(L10n.text("中央の値", "Center value"), selection: Binding(
                    get: { store.profile.circleWidgetSettings.valueStyle },
                    set: { value in store.update { $0.circleWidgetSettings.valueStyle = value } }
                )) {
                    ForEach(MetricValueStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .accessibilityIdentifier("circle.valueStyle")

                Picker(L10n.text("テーマ", "Theme"), selection: Binding(
                    get: { store.profile.circleWidgetSettings.theme },
                    set: { value in store.update { $0.circleWidgetSettings.theme = value } }
                )) {
                    Text(L10n.text("3行表示と同じ", "Same as Three rows"))
                        .tag(Optional<WidgetTheme>.none)
                    ForEach(WidgetTheme.allCases) { theme in
                        Text(theme.title).tag(Optional(theme))
                    }
                }
                .accessibilityIdentifier("circle.theme")
            } header: {
                Text(L10n.text("表示", "Display"))
            }

            Section {
                Label(L10n.text("ホーム画面を長押しし、編集 → ウィジェットを追加", "Touch and hold the Home Screen, then choose Edit → Add Widget"), systemImage: "1.circle")
                Label(L10n.text("DaysYetを検索し、「4つのサークル」の小・大サイズを追加", "Search for DaysYet and add Four circles in Small or Large"), systemImage: "2.circle")
            } header: {
                Text(L10n.text("ホーム画面に追加", "Add to the Home Screen"))
            } footer: {
                Text(L10n.text(
                    "3つの行とは別のウィジェットです。ホーム画面のウィジェット一覧で「4つのサークル」を選んで追加してください。",
                    "Four circles is a separate widget. Choose it from the Home Screen widget gallery to add it."
                ))
            }

            Section {
                Label(L10n.text("追加したウィジェットを長押し → ウィジェットを編集", "Touch and hold the added widget → Edit Widget"), systemImage: "hand.tap")
                Text(L10n.text(
                    "以前に追加したウィジェットや個別に変更した項目は、その設定を維持します。この画面の設定を使うには、各項目を「アプリの設定」に変更してください。",
                    "Previously added widgets and individually customized fields keep their choices. Set each field to App setting to use the choices on this screen."
                ))
            } header: {
                Text(L10n.text("追加済みウィジェットに反映するには", "Apply to existing widgets"))
            } footer: {
                Text(L10n.text(
                    "新しく追加するサークルウィジェットは、標準でこの画面の設定を使います。ホーム画面やスタンバイで個別の設定に変更することもできます。",
                    "New circle widgets use these settings by default. You can also customize each widget on the Home Screen or in StandBy."
                ))
            }
        }
        .navigationTitle(L10n.text("4つのサークル", "Four circles"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private func metricBinding(at index: Int) -> Binding<MetricKind> {
        Binding(
            get: { store.profile.circleWidgetSettings.normalizedMetrics[index] },
            set: { store.setCircleWidgetMetric($0, at: index) }
        )
    }

    private func positionTitle(_ index: Int) -> String {
        switch index {
        case 0: L10n.text("左上", "Top left")
        case 1: L10n.text("右上", "Top right")
        case 2: L10n.text("左下", "Bottom left")
        default: L10n.text("右下", "Bottom right")
        }
    }
}

private struct ThemeChoiceCard: View {
    let theme: WidgetTheme
    let isSelected: Bool

    private var palette: WidgetThemePalette { theme.palette }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 6) {
                    ForEach(Array(MetricKind.allCases.prefix(3)), id: \.self) { metric in
                        Capsule()
                            .fill(LinearGradient(colors: palette.colors(for: metric), startPoint: .leading, endPoint: .trailing))
                            .frame(height: 5)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(palette.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(palette.accent)
                        .background(.thinMaterial, in: Circle())
                        .padding(7)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(theme.title)
                    .font(.subheadline.weight(.semibold))
                Text(theme.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(isSelected ? palette.accent : .primary.opacity(0.06), lineWidth: isSelected ? 2 : 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
    }
}

private struct WidgetGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 16) {
                        guideHeading(L10n.text("ホーム画面", "Home Screen"), "apps.iphone")
                        guideRow("1", L10n.text("ホーム画面を長押し", "Touch and hold the Home Screen"), "hand.tap")
                        guideRow("2", L10n.text("編集 → ウィジェットを追加", "Choose Edit → Add Widget"), "plus.square")
                        guideRow("3", L10n.text("DaysYetを検索して追加", "Search for DaysYet and add it"), "magnifyingglass")
                        Text(L10n.text(
                            "「4つのサークル」は小・大サイズで追加できます。追加後に長押し → ウィジェットを編集で、左上・右上・左下・右下の時間、値、テーマを選べます。",
                            "Choose Four circles in Small or Large. After adding it, touch and hold → Edit Widget to choose the top-left, top-right, bottom-left, and bottom-right timelines, values, and theme."
                        ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 16) {
                        guideHeading(L10n.text("ロック画面", "Lock Screen"), "lock.rectangle")
                        guideRow("1", L10n.text("ロック画面を長押ししてカスタマイズ", "Touch and hold the Lock Screen, then choose Customize"), "hand.tap")
                        guideRow("2", L10n.text("ロック画面を選び、ウィジェット欄をタップ", "Choose Lock Screen, then tap the widget area"), "rectangle.dashed")
                        guideRow("3", L10n.text("DaysYetの形と表示する時間を選ぶ", "Choose a DaysYet shape and timeline"), "timer")
                    }
                }
                .padding(24)
            }
            .navigationTitle(L10n.text("ウィジェットを追加", "Add Widgets"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("完了", "Done")) { dismiss() }
                }
            }
        }
    }

    private func guideHeading(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.title3.bold())
    }

    private func guideRow(_ number: String, _ title: String, _ symbol: String) -> some View {
        HStack(spacing: 18) {
            Text(number)
                .font(.title3.bold())
                .frame(width: 42, height: 42)
                .background(DaysYetTheme.coral.opacity(0.16), in: Circle())
            Label(title, systemImage: symbol)
                .font(.headline)
        }
    }
}
