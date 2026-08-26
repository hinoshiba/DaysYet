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
                        Label(L10n.text("追加方法を見る", "How to add the widget"), systemImage: "plus.square.on.square")
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
            EyebrowLabel(text: L10n.text("DaysYet · 3つの時間", "DaysYet · Three timelines"))
            Text(L10n.text("時間を、積み重ねる。\n今日を選ぶ。", "Every day adds up.\nChoose today."))
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .tracking(-0.7)
            Text(L10n.text("選んだ内容はウィジェットに反映されます。更新時刻はiOSが調整します。", "Your choices appear in the widget; refresh timing is controlled by iOS."))
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
                            Label(candidate.title, systemImage: candidate.symbolName)
                        }
                    }
                } label: {
                    HStack(spacing: 14) {
                        Text("\(index + 1)")
                            .font(.caption.bold())
                            .frame(width: 28, height: 28)
                            .background(.primary.opacity(0.08), in: Circle())
                        Label(metric.title, systemImage: metric.symbolName)
                            .font(.body.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .padding(15)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text("\(index + 1)本目、\(metric.title)", "Bar \(index + 1), \(metric.title)"))
            }
        }
    }

    private var valueStyleEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            EyebrowLabel(text: L10n.text("バーの値", "Progress bar value"))
            Picker(
                L10n.text("バーの値", "Progress bar value"),
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
                "バーは経過時間を左から表示します。ここでは右側の値だけを選べます。",
                "Bars always show elapsed time from left to right; this only changes the value on the right."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
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
            VStack(alignment: .leading, spacing: 24) {
                guideRow("1", L10n.text("ホーム画面を長押し", "Touch and hold the Home Screen"), "hand.tap")
                guideRow("2", L10n.text("編集 → ウィジェットを追加", "Choose Edit → Add Widget"), "plus.square")
                guideRow("3", L10n.text("DaysYetを検索して追加", "Search for DaysYet and add it"), "magnifyingglass")
                Spacer()
            }
            .padding(24)
            .navigationTitle(L10n.text("ウィジェットを追加", "Add the Widget"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("完了", "Done")) { dismiss() }
                }
            }
        }
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
