import SwiftUI
import WidgetKit

enum CircleWidgetSize: String, CaseIterable, Identifiable {
    case small, medium, large

    var id: String { rawValue }
    var title: String {
        switch self {
        case .small: L10n.text("小", "Small")
        case .medium: L10n.text("中・横長", "Medium")
        case .large: L10n.text("大", "Large")
        }
    }

    var capacity: Int { self == .small ? 4 : CircleWidgetSettings.maximumCount }

    init(family: WidgetFamily) {
        switch family {
        case .systemMedium: self = .medium
        case .systemLarge: self = .large
        default: self = .small
        }
    }
}

struct CircleWidgetGridLayout {
    let count: Int
    let columns: Int
    let rows: Int
    let compact: Bool
    var spacing: CGFloat { compact ? 4 : 12 }

    init(size: CircleWidgetSize, metricCount: Int) {
        count = min(max(metricCount, 0), size.capacity)
        switch size {
        case .small: columns = min(max(count, 1), 2)
        case .medium: columns = count <= 4 ? max(count, 1) : (count + 1) / 2
        case .large: columns = count <= 4 ? min(max(count, 1), 2) : 3
        }
        rows = max(1, (count + columns - 1) / columns)
        compact = size == .small || (size == .medium && count > 4)
    }

    func cellSize(in available: CGSize) -> CGSize {
        CGSize(
            width: max(0, (available.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)),
            height: max(0, (available.height - spacing * CGFloat(rows - 1)) / CGFloat(rows))
        )
    }
}

/// Shared with the app target so the actual widget layout can be rendered in QA.
struct CircleWidgetGrid: View {
    @Environment(\.showsWidgetContainerBackground) private var widgetShowsContainerBackground
    let snapshots: [MetricSnapshot]
    let valueStyle: MetricValueStyle
    let theme: WidgetTheme
    let size: CircleWidgetSize
    /// App previews draw their own background; widgets use the host's environment.
    var showsContainerBackground: Bool? = nil

    var body: some View {
        GeometryReader { geometry in
            let layout = CircleWidgetGridLayout(size: size, metricCount: snapshots.count)
            let cell = layout.cellSize(in: geometry.size)

            VStack(spacing: layout.spacing) {
                ForEach(0..<layout.rows, id: \.self) { row in
                    HStack(spacing: layout.spacing) {
                        ForEach(0..<layout.columns, id: \.self) { column in
                            let index = row * layout.columns + column
                            if index < layout.count {
                                CircleWidgetMetric(
                                    snapshot: snapshots[index],
                                    valueStyle: valueStyle,
                                    theme: theme,
                                    compact: layout.compact,
                                    showsContainerBackground: showsContainerBackground ?? widgetShowsContainerBackground
                                )
                                .frame(width: cell.width, height: cell.height)
                            } else {
                                Color.clear.frame(width: cell.width, height: cell.height)
                                    .accessibilityHidden(true)
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
    let showsContainerBackground: Bool

    private var palette: WidgetThemePalette { theme.palette }
    private var usesThemeForeground: Bool {
        renderingMode == .fullColor && showsContainerBackground
    }

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
            return AnyShapeStyle(AngularGradient(colors: palette.colors(for: snapshot.kind), center: .center))
        }
        return AnyShapeStyle(Color.primary)
    }
}
