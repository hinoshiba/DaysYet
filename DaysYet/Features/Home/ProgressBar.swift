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
    let snapshot: MetricSnapshot
    let valueStyle: MetricValueStyle
    var theme: WidgetTheme = .vividNight

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Label(snapshot.title, systemImage: snapshot.kind.symbolName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 12)
                Text(snapshot.valueText(style: valueStyle))
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .monospacedDigit()
                    .layoutPriority(1)
            }

            ProgressBar(
                fraction: snapshot.elapsedFraction,
                colors: DaysYetTheme.colors(for: snapshot.kind, theme: theme)
            )

            Text(snapshot.secondarySummary(excluding: valueStyle))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .monospacedDigit()
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.primary.opacity(0.06), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(snapshot.accessibilitySummary)
    }
}
