import SwiftUI
import WidgetKit

/// Shared with the app target so the actual widget layout can be rendered in QA.
struct CircleWidgetGrid: View {
    let snapshots: [MetricSnapshot]
    let valueStyle: MetricValueStyle
    let theme: WidgetTheme
    let compact: Bool

    var body: some View {
        GeometryReader { geometry in
            let spacing: CGFloat = compact ? 4 : 12
            let cellWidth = max(0, (geometry.size.width - spacing) / 2)
            let cellHeight = max(0, (geometry.size.height - spacing) / 2)

            VStack(spacing: spacing) {
                ForEach(0..<2) { row in
                    HStack(spacing: spacing) {
                        ForEach(0..<2) { column in
                            let index = row * 2 + column
                            if snapshots.indices.contains(index) {
                                CircleWidgetMetric(
                                    snapshot: snapshots[index],
                                    valueStyle: valueStyle,
                                    theme: theme,
                                    compact: compact
                                )
                                .frame(width: cellWidth, height: cellHeight)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct CircleWidgetMetric: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    @ScaledMetric(relativeTo: .caption2) private var compactValueSize: CGFloat = 11
    @ScaledMetric(relativeTo: .title3) private var largeValueSize: CGFloat = 20
    @ScaledMetric(relativeTo: .caption2) private var compactLabelSize: CGFloat = 11
    @ScaledMetric(relativeTo: .caption) private var largeLabelSize: CGFloat = 12
    let snapshot: MetricSnapshot
    let valueStyle: MetricValueStyle
    let theme: WidgetTheme
    let compact: Bool

    private var palette: WidgetThemePalette { theme.palette }

    var body: some View {
        GeometryReader { geometry in
            let labelHeight = min(compact ? 16.0 : 36.0, geometry.size.height * 0.25)
            let spacing: CGFloat = compact ? 2 : 6
            let diameter = max(0, min(geometry.size.width, geometry.size.height - labelHeight - spacing))
            let lineWidth: CGFloat = compact ? 4 : 7

            VStack(spacing: spacing) {
                ZStack {
                    Circle()
                        .inset(by: lineWidth / 2)
                        .stroke(trackStyle, lineWidth: lineWidth)
                    if snapshot.remainingFraction > 0 {
                        Circle()
                            .inset(by: lineWidth / 2)
                            .trim(from: 1 - snapshot.remainingFraction, to: 1)
                            .stroke(ringStyle, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .widgetAccentable()
                    }
                    Text(valueText)
                        .font(.system(
                            size: min(compact ? compactValueSize : largeValueSize, diameter * 0.3),
                            weight: .bold,
                            design: .rounded
                        ))
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                        .lineLimit(valueStyle == .percentage && snapshot.hasScheduledTime ? 1 : 2)
                        .minimumScaleFactor(0.5)
                        .allowsTightening(true)
                        .padding(lineWidth + (compact ? 2 : 6))
                }
                .frame(width: diameter, height: diameter)

                Text(snapshot.title)
                    .font(.system(
                        size: min(compact ? compactLabelSize : largeLabelSize, labelHeight * (compact ? 0.75 : 0.38)),
                        weight: .semibold,
                        design: .rounded
                    ))
                    .foregroundStyle(labelStyle)
                    .multilineTextAlignment(.center)
                    .lineLimit(compact ? 1 : 2)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)
                    .frame(height: labelHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(renderingMode == .fullColor ? AnyShapeStyle(palette.foreground) : AnyShapeStyle(Color.primary))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(snapshot.accessibilitySummary)
        .privacySensitive(snapshot.kind == .healthyLife || snapshot.kind == .customLife)
    }

    private var valueText: String {
        if snapshot.isOff { return "Off" }
        if !snapshot.hasScheduledTime { return snapshot.remainingText }
        if valueStyle == .percentage {
            return RemainingPercentage.compactText(for: snapshot.remainingFraction)
        }
        // A circle's center is narrower than a row, including in the Large family.
        // The complete date and remaining time are still in its VoiceOver summary.
        return snapshot.valueText(style: valueStyle, compact: true)
    }

    private var labelStyle: AnyShapeStyle {
        renderingMode == .fullColor
            ? AnyShapeStyle(palette.secondaryForeground)
            : AnyShapeStyle(HierarchicalShapeStyle.secondary)
    }

    private var trackStyle: AnyShapeStyle {
        renderingMode == .fullColor
            ? AnyShapeStyle(palette.track)
            : AnyShapeStyle(Color.primary.opacity(0.14))
    }

    private var ringStyle: AnyShapeStyle {
        if renderingMode == .fullColor {
            return AnyShapeStyle(AngularGradient(colors: palette.colors(for: snapshot.kind), center: .center))
        }
        return AnyShapeStyle(Color.primary)
    }
}
