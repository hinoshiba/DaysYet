import SwiftUI
import WidgetKit

/// Shared with the app target so the actual widget layout can be rendered in QA.
struct CircleWidgetGrid: View {
    @Environment(\.showsWidgetContainerBackground) private var widgetShowsContainerBackground
    let snapshots: [MetricSnapshot]
    let valueStyle: MetricValueStyle
    let theme: WidgetTheme
    let compact: Bool
    /// App previews draw their own background; widgets use the host's environment.
    var showsContainerBackground: Bool? = nil
    var customColors: [MetricKind: WidgetColor] = [:]

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
                                    compact: compact,
                                    showsContainerBackground: showsContainerBackground ?? widgetShowsContainerBackground,
                                    customColors: customColors
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
    @ScaledMetric(relativeTo: .caption) private var compactValueSize: CGFloat = 14
    @ScaledMetric(relativeTo: .title2) private var largeValueSize: CGFloat = 24
    @ScaledMetric(relativeTo: .caption2) private var compactLabelSize: CGFloat = 9
    @ScaledMetric(relativeTo: .caption) private var largeLabelSize: CGFloat = 12
    let snapshot: MetricSnapshot
    let valueStyle: MetricValueStyle
    let theme: WidgetTheme
    let compact: Bool
    let showsContainerBackground: Bool
    let customColors: [MetricKind: WidgetColor]

    private var palette: WidgetThemePalette { theme.palette }
    private var usesThemeForeground: Bool {
        renderingMode == .fullColor && showsContainerBackground
    }

    var body: some View {
        GeometryReader { geometry in
            let diameter = max(0, min(geometry.size.width, geometry.size.height))
            let lineWidth: CGFloat = compact ? 4 : 7
            // An inscribed square keeps even two-line values inside the ring.
            let contentSize = max(0, (diameter - lineWidth * 2) / sqrt(2))
            let labelSize = min(compact ? compactLabelSize : largeLabelSize, diameter * 0.15)
            // Reserve the same title space in every circle so wrapping does not
            // shift the percentage relative to its neighbors.
            let labelHeight = min(labelSize * (compact ? 1.25 : 2.4), contentSize * (compact ? 0.3 : 0.42))
            let spacing = min(compact ? 1.0 : 3.0, contentSize * 0.05)
            let valueSize = min(compact ? compactValueSize : largeValueSize, diameter * 0.24)
            let valueLineLimit = snapshot.isOff || (valueStyle == .percentage && snapshot.hasScheduledTime) ? 1 : 2
            let valueHeight = max(0, min(valueSize * CGFloat(valueLineLimit) * 1.3, contentSize - labelHeight - spacing))

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
                VStack(spacing: spacing) {
                    Text(snapshot.title)
                        .font(.system(
                            size: labelSize,
                            weight: .semibold,
                            design: .rounded
                        ))
                        .foregroundStyle(labelStyle)
                        .lineLimit(compact ? 1 : 2)
                        .truncationMode(.tail)
                        .minimumScaleFactor(0.7)
                        .allowsTightening(true)
                        .frame(width: contentSize, height: labelHeight, alignment: .bottom)
                        .clipped()
                    Text(valueText)
                        .font(.system(
                            size: valueSize,
                            weight: .bold,
                            design: .rounded
                        ))
                        .monospacedDigit()
                        .lineLimit(valueLineLimit)
                        .truncationMode(.tail)
                        .minimumScaleFactor(0.5)
                        .allowsTightening(true)
                        .frame(width: contentSize, height: valueHeight)
                        .clipped()
                }
                .multilineTextAlignment(.center)
                .frame(width: contentSize, height: contentSize)
                .clipped()
            }
            .frame(width: diameter, height: diameter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(usesThemeForeground ? AnyShapeStyle(palette.foreground) : AnyShapeStyle(Color.primary))
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
        usesThemeForeground
            ? AnyShapeStyle(palette.secondaryForeground)
            : AnyShapeStyle(HierarchicalShapeStyle.secondary)
    }

    private var trackStyle: AnyShapeStyle {
        usesThemeForeground
            ? AnyShapeStyle(palette.track)
            : AnyShapeStyle(Color.primary.opacity(0.14))
    }

    private var ringStyle: AnyShapeStyle {
        if renderingMode == .fullColor {
            return AnyShapeStyle(AngularGradient(
                colors: palette.colors(for: snapshot.kind, customColors: customColors), center: .center
            ))
        }
        return AnyShapeStyle(Color.primary)
    }
}
