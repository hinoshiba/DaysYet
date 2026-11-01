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
            let spacing: CGFloat = compact ? 8 : 12
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
    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .caption) private var compactValueSize: CGFloat = 16
    @ScaledMetric(relativeTo: .title2) private var largeValueSize: CGFloat = 28
    @ScaledMetric(relativeTo: .caption2) private var compactLabelSize: CGFloat = 11
    @ScaledMetric(relativeTo: .caption) private var largeLabelSize: CGFloat = 13
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
            let isPercentage = !snapshot.isOff && snapshot.hasScheduledTime && valueStyle == .percentage
            let valueLineLimit = compact || snapshot.isOff || isPercentage ? 1 : 2
            let layout = CircleWidgetTextLayout(
                diameter: diameter,
                labelSize: compact ? compactLabelSize : largeLabelSize,
                valueSize: compact ? (isPercentage || snapshot.isOff ? compactValueSize : 11) : largeValueSize,
                valueLineLimit: valueLineLimit,
                isPercentage: isPercentage
            )
            let lineWidth = layout.lineWidth

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
                VStack(spacing: layout.spacing) {
                    Text(compact ? (snapshot.circleTitle ?? snapshot.title) : snapshot.title)
                        .font(.system(size: layout.labelSize, weight: .medium))
                        .foregroundStyle(labelStyle)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: layout.contentWidth, height: layout.labelHeight)
                        .clipped()
                    valueLabel(layout: layout, isPercentage: isPercentage)
                        .lineLimit(valueLineLimit)
                        .truncationMode(.tail)
                        // Percentages share one size budgeted for 100%, so 9%
                        // and 100% never acquire different visual emphasis.
                        .minimumScaleFactor(isPercentage ? 1 : (compact && valueStyle == .targetDate ? 0.85 : min(1, 11 / layout.valueSize)))
                        .frame(width: layout.contentWidth, height: layout.valueHeight)
                        .clipped()
                }
                .multilineTextAlignment(.center)
                .frame(width: layout.contentWidth, height: layout.contentHeight)
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

    private func valueLabel(layout: CircleWidgetTextLayout, isPercentage: Bool) -> Text {
        if isPercentage {
            return Text(RemainingPercentage.compactNumber(for: snapshot.remainingFraction))
                .font(.system(size: layout.valueSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                + Text("%")
                .font(.system(size: layout.symbolSize, weight: .semibold, design: .rounded))
        }
        if compact && valueStyle == .targetDate && !snapshot.isOff && snapshot.hasScheduledTime {
            // Condensed proportional digits keep the complete date legible in the
            // narrow center; rounded monospaced digits need extra width here.
            return Text(valueText)
                .font(.system(size: layout.valueSize, weight: .semibold).width(.condensed))
        }
        return Text(valueText)
            .font(.system(size: layout.valueSize, weight: .bold, design: .rounded))
            .monospacedDigit()
    }

    private var valueText: String {
        if snapshot.isOff { return "Off" }
        if !snapshot.hasScheduledTime { return compact ? "—" : snapshot.remainingText }
        if valueStyle == .percentage {
            return RemainingPercentage.compactText(for: snapshot.remainingFraction)
        }
        if valueStyle == .remaining, snapshot.countdown.terminalText == nil {
            // Small circles show the leading useful unit; the large family and
            // VoiceOver retain the complete duration. Never split 12h into 1/2h.
            if compact {
                let component = snapshot.countdown.components.first(where: { $0.value > 0 })
                    ?? snapshot.countdown.components.last
                return component?.text ?? snapshot.remainingText
            }
            return snapshot.countdown.components.map(\.text).joined(separator: "\n")
        }
        if compact && valueStyle == .targetDate {
            // The selected value style already supplies the "until" context.
            // Keep the date itself intact instead of spending space on a suffix.
            if snapshot.kind.isActivity {
                let formatter = DateFormatter()
                formatter.locale = locale
                formatter.dateFormat = "H:mm"
                return formatter.string(from: snapshot.targetDate)
            }
            return snapshot.targetDate.formatted(
                .dateTime.year(.twoDigits).month(.defaultDigits).day().locale(locale)
            )
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

/// The centered text rectangle stays inside the inner edge of the ring.
/// A single title line prevents language-dependent empty space above the value.
struct CircleWidgetTextLayout {
    let lineWidth: CGFloat
    let labelSize: CGFloat
    let valueSize: CGFloat
    let symbolSize: CGFloat
    let spacing: CGFloat
    let labelHeight: CGFloat
    let valueHeight: CGFloat
    let contentWidth: CGFloat
    let contentHeight: CGFloat

    init(diameter: CGFloat, labelSize requestedLabel: CGFloat, valueSize requestedValue: CGFloat,
         valueLineLimit: Int, isPercentage: Bool) {
        lineWidth = min(7, max(3, diameter * 0.045))
        let innerDiameter = max(0, diameter - 2 * lineWidth - 4)
        labelSize = min(requestedLabel, max(11, innerDiameter * 0.21))
        labelHeight = min(labelSize * 1.3, innerDiameter * 0.4)
        spacing = min(3, max(1, diameter * 0.015))
        let lines = CGFloat(valueLineLimit)
        // Two-line dates/durations need a smaller value style to leave horizontal
        // room for the title and whole quantities in compact circles.
        var candidate = min(requestedValue, max(11, diameter * (valueLineLimit == 1 ? 0.24 : 0.14)))
        // Keep enough height for both lines even for dates and remaining time.
        candidate = min(candidate, max(1, (innerDiameter * 0.9 - labelHeight - spacing) / (1.25 * lines)))
        var height: CGFloat = 0
        var width: CGFloat = 0
        var symbol: CGFloat = 11
        repeat {
            symbol = max(11, candidate * 0.6)
            height = min(innerDiameter, labelHeight + spacing + candidate * 1.25 * lines)
            width = sqrt(max(0, innerDiameter * innerDiameter - height * height))
            // Reserve a conservative width for three monospaced rounded digits
            // and the percent sign, regardless of the current percentage.
            if !isPercentage || candidate * 2.15 + symbol * 1.1 <= width || candidate <= 11 { break }
            candidate = max(11, candidate - 0.25)
        } while true
        valueSize = candidate
        symbolSize = symbol
        valueHeight = max(0, height - labelHeight - spacing)
        contentHeight = height
        contentWidth = width
    }
}
