import SwiftUI

struct WidgetColorSettingsView: View {
    @EnvironmentObject private var store: ProfileStore
    let layout: WidgetEditorLayout

    private var theme: WidgetTheme {
        layout == .rows ? store.profile.widgetTheme : (store.profile.circleWidgetSettings.theme ?? store.profile.widgetTheme)
    }
    private var ownColors: [MetricKind: WidgetColor] {
        layout == .rows ? store.profile.widgetCustomColors : store.profile.circleWidgetSettings.customColors
    }
    private var resolvedColors: [MetricKind: WidgetColor] {
        layout == .rows ? store.profile.widgetCustomColors : store.profile.resolvedCircleWidgetCustomColors
    }
    private var metrics: [MetricKind] {
        let selected = layout == .rows
            ? store.profile.normalizedDashboardMetrics
            : store.profile.circleWidgetSettings.normalizedMetrics
        var seen = Set<MetricKind>()
        return selected.filter { seen.insert($0).inserted }
    }

    var body: some View {
        Form {
            Section {
                WidgetEditorPreview(profile: store.profile, layout: layout)
                    .frame(maxWidth: .infinity)
                    .frame(height: layout == .circles ? 186 : 224)
                    .listRowBackground(Color.clear)
            }

            Section {
                Menu {
                    if layout == .circles {
                        Button {
                            applyTemplate(nil)
                        } label: {
                            templateLabel(nil)
                        }
                    }
                    ForEach(WidgetTheme.allCases) { template in
                        Button {
                            applyTemplate(template)
                        } label: {
                            templateLabel(template)
                        }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(layout.paletteTitle(profile: store.profile))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption.weight(.semibold))
                        }
                        HStack(spacing: 8) {
                            ForEach(metrics) { metric in
                                Capsule()
                                    .fill(LinearGradient(
                                        colors: theme.palette.colors(for: metric, customColors: resolvedColors),
                                        startPoint: .leading, endPoint: .trailing
                                    ))
                                    .frame(height: 12)
                            }
                        }
                        .accessibilityHidden(true)
                    }
                    .multilineTextAlignment(.leading)
                    .padding(.vertical, 4)
                }
                .accessibilityLabel(L10n.text("配色テンプレート", "Palette template"))
                .accessibilityValue(layout.paletteTitle(profile: store.profile))
                .accessibilityIdentifier("widget.colors.template")
            } header: {
                Text(L10n.text("配色テンプレート", "Palette template"))
            } footer: {
                Text(L10n.text(
                    "テンプレートを選ぶと、このウィジェットの個別の色をリセットします。",
                    "Choosing a template resets this widget's custom colors."
                ))
            }

            Section {
                ForEach(metrics) { metric in
                    HStack(spacing: 12) {
                        ColorPicker(selection: colorBinding(for: metric), supportsOpacity: false) {
                            Text(metric.title(profile: store.profile))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityIdentifier("widget.colors.\(metric.rawValue)")
                        if ownColors[metric] != nil {
                            Button {
                                setColor(nil, for: metric)
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(L10n.text(
                                "\(metric.title(profile: store.profile))の色をリセット",
                                "Reset color for \(metric.title(profile: store.profile))"
                            ))
                        }
                    }
                }
                if !ownColors.isEmpty {
                    Button(L10n.text("個別の色をすべてリセット", "Reset all custom colors")) {
                        store.update {
                            if layout == .rows {
                                $0.widgetCustomColors = [:]
                            } else {
                                $0.circleWidgetSettings.customColors = [:]
                            }
                        }
                    }
                    .accessibilityIdentifier("widget.colors.reset")
                }
            } header: {
                Text(L10n.text("項目ごとの色", "Timeline colors"))
            } footer: {
                Text(layout == .rows && store.profile.widgetDisplayMode == .countdown
                     ? L10n.text("個別の色は、バーを含む表示方法で反映されます。", "Timeline colors appear in display modes that include bars.")
                     : L10n.text("色をタップすると、パレットから選んだり、自由に調整したりできます。", "Tap a color to choose from the palette or adjust it freely."))
            }
        }
        .navigationTitle(L10n.text("色と配色", "Colors & palette"))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func templateLabel(_ template: WidgetTheme?) -> some View {
        let selected = layout == .rows ? store.profile.widgetTheme : store.profile.circleWidgetSettings.theme
        let title = template?.title ?? L10n.text("3つの時間と同じ", "Same as Three timelines")
        if selected == template {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    private func applyTemplate(_ template: WidgetTheme?) {
        store.update {
            if layout == .rows, let template {
                $0.widgetTheme = template
                $0.widgetCustomColors = [:]
            } else if layout == .circles {
                $0.circleWidgetSettings.theme = template
                $0.circleWidgetSettings.customColors = [:]
            }
        }
    }

    private func colorBinding(for metric: MetricKind) -> Binding<Color> {
        Binding(
            get: { resolvedColors[metric]?.color ?? theme.palette.colors(for: metric)[0] },
            set: { color in
                guard let storedColor = WidgetColor(color: color) else { return }
                setColor(storedColor, for: metric)
            }
        )
    }

    private func setColor(_ color: WidgetColor?, for metric: MetricKind) {
        store.update {
            if layout == .rows {
                $0.widgetCustomColors[metric] = color
            } else {
                $0.circleWidgetSettings.customColors[metric] = color
            }
        }
    }
}

/// A shortcut to the same per-timeline color used by Times and Three timelines.
/// Circle palettes keep their existing inheritance and explicit overrides.
struct TimelineColorSettingsView: View {
    @EnvironmentObject private var store: ProfileStore
    @Environment(\.dismiss) private var dismiss
    let metric: MetricKind

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        MetricCard(
                            snapshot: TimeProgressCalculator.snapshot(
                                for: metric, profile: store.profile, now: context.date
                            ),
                            valueStyle: store.profile.dashboardValueStyle,
                            theme: store.profile.widgetTheme,
                            customColors: store.profile.widgetCustomColors
                        )
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("times.color.preview")
                }

                Section {
                    ColorPicker(
                        L10n.text("色", "Color"),
                        selection: colorBinding,
                        supportsOpacity: false
                    )
                    .accessibilityValue(
                        store.profile.widgetCustomColors[metric]?.hex
                            ?? L10n.text("配色テンプレート", "Palette template")
                    )
                    .accessibilityIdentifier("times.color.picker")

                    if store.profile.widgetCustomColors[metric] != nil {
                        Button(L10n.text("配色テンプレートに戻す", "Use palette color")) {
                            store.update { $0.widgetCustomColors[metric] = nil }
                        }
                        .accessibilityIdentifier("times.color.reset")
                    }
                } header: {
                    Text(metric.title(profile: store.profile))
                } footer: {
                    Text(L10n.text(
                        "「時間」と「3つの時間」の色です。サークルは「3つの時間と同じ」の場合に引き継ぎ、個別色はそのままです。",
                        "Used in Times and Three timelines. Four circles inherits this color when set to Same as Three timelines, keeping any color set for that timeline."
                    ))
                }
            }
            .navigationTitle(L10n.text("色を変更", "Change color"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("完了", "Done")) { dismiss() }
                        .accessibilityIdentifier("times.color.done")
                }
            }
        }
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: {
                store.profile.widgetCustomColors[metric]?.color
                    ?? store.profile.widgetTheme.palette.colors(for: metric)[0]
            },
            set: { color in
                guard let storedColor = WidgetColor(color: color) else { return }
                store.update { $0.widgetCustomColors[metric] = storedColor }
            }
        )
    }
}

struct WidgetEditorPreview: View {
    let profile: UserProfile
    let layout: WidgetEditorLayout

    var body: some View {
        if layout == .rows {
            WidgetPreview(profile: profile)
                .aspectRatio(2.05, contentMode: .fit)
                .frame(maxWidth: 360)
        } else {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let configuration = DaysYetCircleConfigurationIntent()
                CircleWidgetGrid(
                    snapshots: configuration.resolvedMetrics(profile: profile).map {
                        TimeProgressCalculator.snapshot(for: $0, profile: profile, now: context.date)
                    },
                    valueStyle: configuration.resolvedValueStyle(profile: profile),
                    theme: configuration.resolvedTheme(profile: profile),
                    compact: true,
                    showsContainerBackground: true,
                    customColors: configuration.resolvedCustomColors(profile: profile)
                )
                .padding(16)
                .frame(width: 170, height: 170)
                .background(configuration.resolvedTheme(profile: profile).palette.background,
                            in: RoundedRectangle(cornerRadius: 24))
            }
        }
    }
}

extension WidgetEditorLayout {
    func paletteTitle(profile: UserProfile) -> String {
        if self == .rows { return profile.widgetTheme.title }
        return profile.circleWidgetSettings.theme?.title ?? L10n.text("3つの時間と同じ", "Same as Three timelines")
    }

    func colorSummary(profile: UserProfile) -> String {
        let colors = self == .rows ? profile.widgetCustomColors : profile.circleWidgetSettings.customColors
        let title = paletteTitle(profile: profile)
        return colors.isEmpty ? title : title + L10n.text("・カスタム", " · Custom")
    }
}
