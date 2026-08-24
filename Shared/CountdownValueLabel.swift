import SwiftUI

/// A shared countdown label that keeps the app preview and WidgetKit output
/// typographically identical. Numeric values are intentionally 1.5–2x the
/// unit labels so the date magnitude is readable at a glance.
struct CountdownValueLabel: View {
    let snapshot: MetricSnapshot
    let compact: Bool
    var condensed = false
    var tight = false
    var combined = false
    @ScaledMetric(relativeTo: .body) private var compactUnitSize: CGFloat = 14
    @ScaledMetric(relativeTo: .body) private var condensedUnitSize: CGFloat = 12
    @ScaledMetric(relativeTo: .body) private var tightUnitSize: CGFloat = 11
    @ScaledMetric(relativeTo: .body) private var combinedUnitSize: CGFloat = 15
    @ScaledMetric(relativeTo: .body) private var regularUnitSize: CGFloat = 16

    var body: some View {
        Group {
            if snapshot.countdown.terminalText != nil {
                Text(snapshot.valueText(style: .remaining, compact: compact))
                    .font(.system(compact ? .headline : .title3, design: .rounded, weight: .bold))
            } else {
                Text(formattedValue)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.68)
        .allowsTightening(true)
        .monospacedDigit()
        .layoutPriority(1)
    }

    private var formattedValue: AttributedString {
        var result = AttributedString()
        if !compact, !snapshot.countdown.prefix.isEmpty {
            append(snapshot.countdown.prefix + " ", font: unitFont, to: &result)
        }

        for (index, component) in snapshot.countdown.components.enumerated() {
            if index > 0, !compact {
                append(" ", font: unitFont, to: &result)
            }
            append(String(component.value), font: numberFont, to: &result)
            append(component.unit, font: unitFont, to: &result)
        }

        if !compact, !snapshot.countdown.suffix.isEmpty {
            append(" " + snapshot.countdown.suffix, font: unitFont, to: &result)
        }
        return result
    }

    private func append(_ value: String, font: Font, to result: inout AttributedString) {
        var segment = AttributedString(value)
        segment.font = font
        result.append(segment)
    }

    private var unitSize: CGFloat {
        if compact {
            if tight { return tightUnitSize }
            return condensed ? condensedUnitSize : compactUnitSize
        }
        return combined ? combinedUnitSize : regularUnitSize
    }

    private var numberFont: Font {
        .system(size: unitSize * (compact ? 1.86 : 2), weight: .bold, design: .rounded)
    }

    private var unitFont: Font {
        .system(size: unitSize, weight: .semibold, design: .rounded)
    }
}
