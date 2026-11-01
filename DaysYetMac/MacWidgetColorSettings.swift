import SwiftUI

struct MacWidgetColorSettings: View {
    @ObservedObject var store: ProfileStore
    @ObservedObject var preferences: MacWidgetPreferences

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.text("配色テンプレート", "Color templates"))
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(WidgetTheme.allCases) { theme in
                        templateButton(theme)
                    }
                }
                Text(preferences.customColors.isEmpty ? store.profile.widgetTheme.title : L10n.text(
                    "\(store.profile.widgetTheme.title)・カスタム",
                    "\(store.profile.widgetTheme.title) · Custom"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)

            ForEach(store.profile.macWidgetMetrics(for: preferences.edge)) { kind in
                colorRow(kind)
            }

            if !preferences.customColors.isEmpty {
                Button(L10n.text("すべてテンプレートの色に戻す", "Reset all colors to template")) {
                    preferences.resetCustomColors()
                }
                .controlSize(.small)
            }
        } header: {
            Text(L10n.text("カラー", "Colors"))
        } footer: {
            Text(L10n.text(
                "色をクリックすると、表示中の項目ごとに好きな色を選べます。変更はすぐに反映・保存されます。テンプレートを選ぶと、すべての項目の色が切り替わります。",
                "Click a color to customize each visible timeline. Changes appear and save immediately. Selecting a template replaces all timeline colors."
            ))
        }
    }

    private func templateButton(_ theme: WidgetTheme) -> some View {
        let isSelected = store.profile.widgetTheme == theme && preferences.customColors.isEmpty
        return Button {
            preferences.resetCustomColors()
            store.update { $0.widgetTheme = theme }
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    ForEach(Array(store.profile.macDashboardMetrics.prefix(3))) { kind in
                        Circle()
                            .trim(from: 0, to: 0.75)
                            .stroke(MacWidgetStyle.accent(for: kind, theme: theme),
                                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 17, height: 17)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white)
                        .opacity(isSelected ? 1 : 0)
                }
                Text(theme.title)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MacWidgetStyle.background, in: RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(isSelected ? Color.accentColor : .primary.opacity(0.12),
                                  lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.title)
        .accessibilityHint(L10n.text("すべての項目にこの配色を適用します", "Apply these colors to all timelines"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func colorRow(_ kind: MetricKind) -> some View {
        let title = kind.title(profile: store.profile)
        let color = resolvedColor(for: kind)
        return HStack(spacing: 8) {
            ColorPicker(selection: Binding(
                get: { resolvedColor(for: kind) },
                set: { newValue in
                    guard let value = MacWidgetColor(color: newValue) else { return }
                    preferences.setCustomColor(value, for: kind)
                }
            ), supportsOpacity: false) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .lineLimit(2)
                    if let value = MacWidgetColor(color: color) {
                        Text(value.hex)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityLabel(L10n.text("\(title)の色", "Color for \(title)"))
            Button {
                preferences.setCustomColor(nil, for: kind)
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.borderless)
            .disabled(preferences.customColor(for: kind) == nil)
            .help(L10n.text("テンプレートの色に戻す", "Reset to template color"))
            .accessibilityLabel(L10n.text("\(title)の色を戻す", "Reset color for \(title)"))
        }
        .padding(.vertical, 2)
    }

    private func resolvedColor(for kind: MetricKind) -> Color {
        MacWidgetStyle.accent(for: kind, theme: store.profile.widgetTheme, customColors: preferences.customColors)
    }
}
