import SwiftUI

struct WidgetStudioView: View {
    @EnvironmentObject private var store: ProfileStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedLayout: WidgetEditorLayout
    @State private var showWidgetGuide = false

    init() {
#if DEBUG
        _selectedLayout = State(initialValue: ProcessInfo.processInfo.arguments.contains("--screenshot-circles") ? .circles : .rows)
#else
        _selectedLayout = State(initialValue: .rows)
#endif
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.text("編集するウィジェット", "Widget to edit"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if dynamicTypeSize.isAccessibilitySize {
                    layoutPicker.pickerStyle(.menu)
                } else {
                    layoutPicker.pickerStyle(.segmented)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Form {
                Section {
                    preview
                        .frame(maxWidth: .infinity)
                        .frame(height: 224)
                        .listRowBackground(Color.clear)
                } footer: {
                    Text(selectedLayout.sizes)
                }

                Section {
                    ForEach(Array(selectedMetrics.enumerated()), id: \.offset) { index, metric in
                        WidgetSettingPicker(
                            selectedLayout.positionTitle(index),
                            selection: metricBinding(at: index),
                            selectedValue: metric.title(profile: store.profile)
                        ) {
                            ForEach(MetricKind.allCases) { metric in
                                Text(metric.title(profile: store.profile)).tag(metric)
                            }
                        }
                        .accessibilityIdentifier("widget.metric.\(index)")
                    }
                } header: {
                    Text(L10n.text("表示する時間", "Timelines"))
                } footer: {
                    Text(L10n.text(
                        "活動時間や日付の詳細は「時間」タブで編集できます。",
                        "Edit schedules and dates in the Times tab."
                    ))
                }

                Section {
                    if selectedLayout == .rows {
                        WidgetSettingPicker(
                            L10n.text("表示方法", "Display mode"),
                            selection: Binding(
                                get: { store.profile.widgetDisplayMode },
                                set: { value in store.update { $0.widgetDisplayMode = value } }
                            ),
                            selectedValue: store.profile.widgetDisplayMode.title
                        ) {
                            ForEach(WidgetDisplayMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .accessibilityIdentifier("widget.displayMode")
                    }

                    if selectedLayout == .circles || store.profile.widgetDisplayMode == .progressBars {
                        WidgetSettingPicker(
                            selectedLayout == .circles
                                ? L10n.text("中央の値", "Center value")
                                : L10n.text("バーの値", "Bar value"),
                            selection: valueStyleBinding,
                            selectedValue: valueStyleBinding.wrappedValue.title
                        ) {
                            ForEach(MetricValueStyle.allCases) { style in
                                Text(style.title).tag(style)
                            }
                        }
                        .accessibilityIdentifier("widget.valueStyle")
                    }

                    NavigationLink {
                        WidgetColorSettingsView(layout: selectedLayout)
                    } label: {
                        ViewThatFits(in: .horizontal) {
                            HStack {
                                Text(L10n.text("カラー", "Colors"))
                                Spacer()
                                Text(selectedLayout.colorSummary(profile: store.profile))
                                    .foregroundStyle(.secondary)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text(L10n.text("カラー", "Colors"))
                                Text(selectedLayout.colorSummary(profile: store.profile))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityIdentifier("widget.colors")
                } header: {
                    Text(L10n.text("表示", "Display"))
                }
            }
            // Changing the editor returns to its preview without changing either
            // widget's saved choices or the widget installed on the Home Screen.
            .id(selectedLayout)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(L10n.text("ウィジェット", "Widgets"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showWidgetGuide = true
                } label: {
                    Label(L10n.text("追加・反映方法", "Add and apply settings"), systemImage: "questionmark.circle")
                }
                .accessibilityIdentifier("widget.guide")
            }
        }
        .sheet(isPresented: $showWidgetGuide) {
            WidgetGuideView(layout: selectedLayout)
        }
    }

    private var layoutPicker: some View {
        Picker(L10n.text("編集するウィジェット", "Widget to edit"), selection: $selectedLayout) {
            ForEach(WidgetEditorLayout.allCases) { layout in
                Text(layout.title).tag(layout)
            }
        }
        .labelsHidden()
        .accessibilityIdentifier("widget.layout")
    }

    private var preview: some View {
        WidgetEditorPreview(profile: store.profile, layout: selectedLayout)
    }

    private var selectedMetrics: [MetricKind] {
        selectedLayout == .rows
            ? store.profile.normalizedDashboardMetrics
            : store.profile.circleWidgetSettings.normalizedMetrics
    }

    private func metricBinding(at index: Int) -> Binding<MetricKind> {
        let layout = selectedLayout
        return Binding(
            get: {
                layout == .rows
                    ? store.profile.normalizedDashboardMetrics[index]
                    : store.profile.circleWidgetSettings.normalizedMetrics[index]
            },
            set: { value in
                if layout == .rows {
                    store.setDashboardMetric(value, at: index)
                } else {
                    store.setCircleWidgetMetric(value, at: index)
                }
            }
        )
    }

    private var valueStyleBinding: Binding<MetricValueStyle> {
        let layout = selectedLayout
        return Binding(
            get: {
                layout == .rows
                    ? store.profile.dashboardValueStyle
                    : store.profile.circleWidgetSettings.valueStyle
            },
            set: { value in
                store.update {
                    if layout == .rows {
                        $0.dashboardValueStyle = value
                    } else {
                        $0.circleWidgetSettings.valueStyle = value
                    }
                }
            }
        )
    }
}

private struct WidgetSettingPicker<Selection: Hashable, Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding private var selection: Selection
    private let title: String
    private let selectedValue: String
    private let content: () -> Content

    init(
        _ title: String,
        selection: Binding<Selection>,
        selectedValue: String,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        _selection = selection
        self.selectedValue = selectedValue
        self.content = content
    }

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Menu {
                Picker(title, selection: $selection, content: content)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .foregroundStyle(.primary)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(selectedValue)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.semibold))
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(.tint)
                }
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(title))
            .accessibilityValue(Text(selectedValue))
            .accessibilityAddTraits(.isButton)
        } else {
            Picker(title, selection: $selection, content: content)
        }
    }
}

enum WidgetEditorLayout: String, CaseIterable, Identifiable {
    case rows, circles

    var id: String { rawValue }
    var title: String {
        self == .rows ? L10n.text("3つの行", "Three rows") : L10n.text("4つのサークル", "Four circles")
    }
    var sizes: String {
        self == .rows
            ? L10n.text("ホーム画面：小・中サイズ", "Home Screen: Small and Medium")
            : L10n.text("ホーム画面：小・大サイズ", "Home Screen: Small and Large")
    }

    func positionTitle(_ index: Int) -> String {
        if self == .rows {
            return [L10n.text("上", "Top"), L10n.text("中央", "Middle"), L10n.text("下", "Bottom")][index]
        }
        return [
            L10n.text("左上", "Top left"), L10n.text("右上", "Top right"),
            L10n.text("左下", "Bottom left"), L10n.text("右下", "Bottom right")
        ][index]
    }
}

private struct WidgetGuideView: View {
    @Environment(\.dismiss) private var dismiss
    let layout: WidgetEditorLayout

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(L10n.text("ホーム画面を長押し", "Touch and hold the Home Screen"), systemImage: "1.circle")
                    Label(L10n.text("編集 → ウィジェットを追加", "Choose Edit → Add Widget"), systemImage: "2.circle")
                    Label(L10n.text("DaysYetを検索して種類とサイズを選ぶ", "Search for DaysYet and choose a type and size"), systemImage: "3.circle")
                    Text(layout == .circles
                         ? L10n.text("「4つのサークル」の小・大サイズを選びます。", "Choose Four circles in Small or Large.")
                         : L10n.text("「DaysYet — 3つの時間」の小・中サイズを選びます。", "Choose DaysYet — Three timelines in Small or Medium."))
                } header: {
                    Text(L10n.text("ホーム画面に追加", "Add to the Home Screen"))
                } footer: {
                    Text(L10n.text(
                        "アプリの種類切替は、編集する設定を選びます。ホーム画面に置く種類は追加時に選びます。",
                        "The app's type selector chooses which settings to edit. Choose the type placed on the Home Screen when adding a widget."
                    ))
                }

                Section {
                    Label(L10n.text("ウィジェットを長押し → ウィジェットを編集", "Touch and hold the widget → Edit Widget"), systemImage: "hand.tap")
                    Text(layout == .circles
                         ? L10n.text("4つの時間・中央の値・テーマを「アプリの設定」にすると、この画面で選んだ内容を使います。", "Set the four timelines, center value, and theme to App setting to use your choices in the app.")
                         : L10n.text("「アプリで選んだ3本を使う」をオンにし、表示モード・値・テーマを「アプリの設定」にします。", "Turn on Use the three selected in the app and set the display mode, value, and theme to App setting."))
                    Text(L10n.text("ウィジェットごとに個別の設定を選ぶこともできます。", "You can also choose individual settings for each widget."))
                } header: {
                    Text(L10n.text("追加済みウィジェットに反映", "Apply to existing widgets"))
                } footer: {
                    Text(L10n.text("設定は自動で保存されます。ウィジェットの更新時刻はiOSが調整します。", "Settings save automatically. Widget refresh timing is controlled by iOS."))
                }

                Section {
                    Text(L10n.text("横向きで充電中のスタンバイには、小サイズを追加できます。ウィジェットを長押しして編集します。", "In StandBy while charging in landscape, add a Small widget. Touch and hold it to edit."))
                } header: {
                    Text(L10n.text("スタンバイ", "StandBy"))
                }

                Section {
                    Label(L10n.text("ロック画面を長押し → カスタマイズ", "Touch and hold the Lock Screen → Customize"), systemImage: "1.circle")
                    Label(L10n.text("ウィジェット欄からDaysYetを追加", "Add DaysYet from the widget area"), systemImage: "2.circle")
                    Label(L10n.text("形と表示する1つの時間を選ぶ", "Choose a shape and one timeline"), systemImage: "3.circle")
                } header: {
                    Text(L10n.text("ロック画面", "Lock Screen"))
                } footer: {
                    Text(L10n.text("背景の半透明化、ロック画面の単色表示、スタンバイの夜間の色はiOSが調整します。", "iOS controls translucent backgrounds, monochrome Lock Screen widgets, and StandBy's nighttime colors."))
                }
            }
            .navigationTitle(L10n.text("追加・反映方法", "Add and apply settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("完了", "Done")) { dismiss() }
                }
            }
        }
    }
}
