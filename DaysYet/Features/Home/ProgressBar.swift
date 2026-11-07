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

/// Times and widget settings use the name to identify each timeline.
struct MetricTitleValueLabel: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
            Text(value)
                .font(.subheadline.monospacedDigit())
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
    /// Editing opens a Save/Cancel sheet; it is distinct from navigating deeper.
    var showsEditAction = false

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: snapshot.kind.symbolName)
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
                .frame(width: 40)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 10) {
                MetricTitleValueLabel(title: snapshot.title, value: snapshot.valueText(style: valueStyle))

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

            Image(systemName: "square.and.pencil")
                .font(.body)
                .foregroundStyle(.tertiary)
                // Keep progress tracks aligned for read-only months and years.
                .opacity(showsEditAction ? 1 : 0)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(snapshot.accessibilitySummary)
        .accessibilityHint(showsEditAction
            ? L10n.text("時刻や日付を編集します", "Edit this timeline’s schedule or dates")
            : "")
    }
}
