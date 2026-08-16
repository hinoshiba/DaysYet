import SwiftUI

struct WidgetStudioView: View {
    @EnvironmentObject private var store: ProfileStore
    @State private var showWidgetGuide = false

    var body: some View {
        ZStack {
            DaysYetBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    WidgetPreview(profile: store.profile)
                        .aspectRatio(2.05, contentMode: .fit)
                        .accessibilityLabel(L10n.text("ウィジェットプレビュー", "Widget preview"))

                    valueStyleEditor

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

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            EyebrowLabel(text: L10n.text("DaysYet · 3つの時間", "DaysYet · Three timelines"))
            Text(L10n.text("時間は、まだある。\n今日を選ぶ。", "There is time yet.\nChoose today."))
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
                            withAnimation(.snappy) {
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
            EyebrowLabel(text: L10n.text("値の表示", "Value display"))
            Picker(
                L10n.text("値の表示", "Value display"),
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
        }
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
