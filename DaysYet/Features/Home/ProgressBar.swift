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

/// Widget placement rows emphasize the value shown by the widget.
struct MetricValueLabel: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title2.weight(.regular).monospacedDigit())
                .foregroundStyle(.primary)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct MetricSummaryRow: View {
    let snapshot: MetricSnapshot
    let valueStyle: MetricValueStyle
    var theme: WidgetTheme = .vividNight
    var customColors: [MetricKind: WidgetColor] = [:]
    /// Only times with editable content show a disclosure indicator.
    var showsSettingsAffordance = false

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: snapshot.kind.symbolName)
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
                .frame(width: 40)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(snapshot.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(snapshot.valueText(style: valueStyle))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

                ProgressBar(
                    fraction: snapshot.remainingFraction,
                    colors: theme.palette.colors(for: snapshot.kind, customColors: customColors),
                    height: 6
                )

                Text(snapshot.secondarySummary(excluding: valueStyle))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .monospacedDigit()
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                // Keep progress tracks aligned for read-only months and years.
                .opacity(showsSettingsAffordance ? 1 : 0)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(snapshot.accessibilitySummary)
        .accessibilityHint(showsSettingsAffordance
            ? L10n.text("この時間の設定を開きます", "Opens this timer’s settings")
            : "")
    }
}
