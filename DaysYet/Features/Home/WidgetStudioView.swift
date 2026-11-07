import SwiftUI

struct WidgetStudioView: View {
    @EnvironmentObject private var store: ProfileStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @SceneStorage("widget.circle.previewSize") private var circleSize: CircleWidgetSize = .medium
    @State private var editMode: EditMode = .inactive
    let openTimePicker: (WidgetTimeDestination) -> Void

    private var selectedLayout: WidgetLayout { store.profile.widgetLayout }

    var body: some View {
        VStack(spacing: 0) {
            VStack {
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
                if !editMode.isEditing {
                    Section {
                        if selectedLayout == .circles {
                            Group {
                                if dynamicTypeSize.isAccessibilitySize {
                                    circleSizePicker.pickerStyle(.menu)
                                } else {
                                    circleSizePicker.pickerStyle(.segmented)
                                }
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }

                        WidgetThemePicker(
                            selectedTheme: store.profile.widgetTheme,
                            previewSize: themePreviewSize,
                            onSelect: { theme in store.update { $0.widgetTheme = theme } },
                            preview: { preview(for: $0) }
                        )
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    } header: {
                        Text(L10n.text("テーマ", "Theme"))
                    } footer: {
                        Text(selectedLayout == .circles
                             ? L10n.text("見本をタップしてテーマを選びます。小サイズは先頭の4つ、中・大サイズは最大8つを表示します。", "Tap a preview to choose a theme. Small shows the first four; Medium and Large show up to eight.")
                             : L10n.text("見本をタップしてテーマを選びます。", "Tap a preview to choose a theme."))
                    }
                }

                if selectedLayout == .circles {
                    circleSection
                } else {
                    Section {
                        ForEach(Array(selectedMetrics.enumerated()), id: \.offset) { index, metric in
                            NavigationLink(value: AppRoute.widgetTime(.row(index))) {
                                WidgetMetricSettingRow(metric: metric, profile: store.profile, index: index, isCircle: false)
                            }
                            .accessibilityIdentifier("widget.metric.\(index)")
                        }
                    } header: {
                        Text(L10n.text("表示する時間", "Timelines"))
                    } footer: {
                        Text(L10n.text("タップして「時間」の一覧から選びます。", "Tap a row to choose from your Times."))
                    }
                    .listRowBackground(DaysYetTheme.panel)
                }

                if !editMode.isEditing {
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
                        NavigationLink(value: AppRoute.widgetColors) {
                            Text(L10n.text("項目ごとの色", "Timeline colors"))
                        }
                        .accessibilityIdentifier("widget.colors.open")
                    } header: {
                        Text(L10n.text("表示", "Display"))
                    }
                    .listRowBackground(DaysYetTheme.panel)
                }

                AppInfoSection()
            }
            // Keep each layout's metrics while returning to its theme previews.
            .id(selectedLayout)
        }
        .daysYetBackground()
        .navigationTitle(L10n.text("ウィジェット", "Widget"))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.editMode, $editMode)
        .onChange(of: selectedLayout) { _, _ in editMode = .inactive }
        .toolbar {
            if selectedLayout == .circles {
                ToolbarItem(placement: .topBarLeading) {
                    Button(editMode.isEditing ? L10n.text("完了", "Done") : L10n.text("編集", "Edit")) {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    }
                    .accessibilityIdentifier("widget.circle.editList")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editMode = .inactive
                        openTimePicker(.newCircle)
                    } label: {
                        Label(L10n.text("時間から追加", "Add from Times"), systemImage: "plus")
                    }
                    .disabled(selectedMetrics.count >= CircleWidgetSettings.maximumCount)
                    .accessibilityIdentifier("widget.circle.add")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                UsageGuideButton(accessibilityIdentifier: "widget.guide")
            }
        }
    }

    private var circleSection: some View {
        Section {
            ForEach(Array(selectedMetrics.enumerated()), id: \.offset) { index, metric in
                Group {
                    if editMode.isEditing {
                        WidgetMetricSettingRow(metric: metric, profile: store.profile, index: index, canSelectTime: false)
                    } else {
                        NavigationLink(value: AppRoute.widgetTime(.circle(index))) {
                            WidgetMetricSettingRow(metric: metric, profile: store.profile, index: index)
                        }
                    }
                }
                .deleteDisabled(selectedMetrics.count <= 1)
                .accessibilityIdentifier("widget.circle.\(index)")
            }
            .onDelete(perform: store.removeCircleWidgetMetrics)
            .onMove(perform: store.moveCircleWidgetMetrics)
        } header: {
            Text(L10n.text("サークル \(selectedMetrics.count) / 8", "Circles \(selectedMetrics.count) / 8"))
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                if editMode.isEditing {
                    Text(L10n.text("右のハンドルをドラッグして並べ替えます。変更は自動で保存されます。", "Drag the handles on the right to reorder. Changes save automatically."))
                    if selectedMetrics.count <= 1 {
                        Text(L10n.text("サークルは1つ以上必要です。", "Keep at least one circle."))
                    }
                } else {
                    Text(L10n.text(
                        "＋で「時間」から追加、タップで差し替え。「編集」で並べ替え・削除できます。",
                        "Use + to add from Times, or tap to replace. Use Edit to reorder or remove."
                    ))
                }
            }
        }
        .listRowBackground(DaysYetTheme.panel)
    }

    private var circleSizePicker: some View {
        Picker(L10n.text("プレビューのサイズ", "Preview size"), selection: $circleSize) {
            ForEach(CircleWidgetSize.allCases) { size in Text(size.title).tag(size) }
        }
        .accessibilityIdentifier("widget.circle.size")
    }

    private var layoutPicker: some View {
        Picker(L10n.text("表示形式", "Layout"), selection: Binding(
            get: { selectedLayout },
            set: { layout in store.update { $0.widgetLayout = layout } }
        )) {
            ForEach(WidgetLayout.allCases) { layout in
                Text(layout.title).tag(layout)
            }
        }
        .labelsHidden()
        .accessibilityIdentifier("widget.layout")
    }

    @ViewBuilder
    private func preview(for theme: WidgetTheme) -> some View {
        if selectedLayout == .rows {
            WidgetPreview(profile: themedPreviewProfile(theme))
        } else {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                CircleWidgetGrid(
                    snapshots: selectedMetrics.map {
                        TimeProgressCalculator.snapshot(for: $0, profile: store.profile, now: context.date)
                    },
                    valueStyle: store.profile.circleWidgetSettings.valueStyle,
                    theme: theme,
                    size: circleSize,
                    showsContainerBackground: true,
                    customColors: store.profile.resolvedCircleWidgetCustomColors
                )
                .padding(circleSize == .small ? 12 : 16)
                .widgetPreviewSurface(theme: theme)
            }
        }
    }

    private var themePreviewSize: CGSize {
        guard selectedLayout == .circles else { return CGSize(width: 340, height: 166) }
        switch circleSize {
        case .small: return CGSize(width: 176, height: 176)
        case .medium: return CGSize(width: 340, height: 162)
        case .large: return CGSize(width: 340, height: 340)
        }
    }

    private func themedPreviewProfile(_ theme: WidgetTheme) -> UserProfile {
        var profile = store.profile
        profile.widgetTheme = theme
        return profile
    }

    private var selectedMetrics: [MetricKind] {
        selectedLayout == .rows
            ? store.profile.normalizedDashboardMetrics
            : store.profile.circleWidgetSettings.normalizedMetrics
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
