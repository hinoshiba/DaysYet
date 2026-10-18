import SwiftUI

struct ProgressBar: View {
    let fraction: Double
    let colors: [Color]
    var height: CGFloat = 8
    var trackColor: Color = .primary.opacity(0.09)

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width * min(max(fraction, 0), 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(trackColor)
                if width > 0 {
                    Capsule()
                        .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                        .frame(width: width)
                        .shadow(color: (colors.last ?? .clear).opacity(0.22), radius: 5)
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

struct MetricCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let snapshot: MetricSnapshot
    let valueStyle: MetricValueStyle
    var theme: WidgetTheme = .vividNight
    /// Shown when tapping the card opens the settings this time keeps to itself.
    var showsSettingsAffordance = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        title
                        Spacer(minLength: 8)
                        settingsAffordance
                    }
                    value
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    title
                    Spacer(minLength: 12)
                    value.layoutPriority(1)
                    settingsAffordance
                }
            }

            ProgressBar(
                fraction: snapshot.remainingFraction,
                colors: DaysYetTheme.colors(for: snapshot.kind, theme: theme)
            )

            Text(snapshot.secondarySummary(excluding: valueStyle))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
                .monospacedDigit()
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(snapshot.accessibilitySummary)
        .accessibilityHint(showsSettingsAffordance
            ? L10n.text("この時間の設定を開きます", "Opens this timer’s settings")
            : "")
    }

    private var title: some View {
        Label(snapshot.title, systemImage: snapshot.kind.symbolName)
            .font(.headline)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var value: some View {
        Text(snapshot.valueText(style: valueStyle))
            .font(.system(.subheadline, design: .rounded, weight: .bold))
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.72)
            .fixedSize(horizontal: false, vertical: true)
            .monospacedDigit()
    }

    @ViewBuilder
    private var settingsAffordance: some View {
        if showsSettingsAffordance {
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        }
    }
}
