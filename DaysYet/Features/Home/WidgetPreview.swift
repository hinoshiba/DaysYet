import SwiftUI

struct WidgetPreview: View {
    let profile: UserProfile
    var compact = false

    private var palette: WidgetThemePalette { profile.widgetTheme.palette }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(spacing: 0) {
                ForEach(profile.normalizedDashboardMetrics) { metric in
                    let snapshot = TimeProgressCalculator.snapshot(for: metric, profile: profile, now: context.date)
                    WidgetPreviewMetricRow(
                        snapshot: snapshot,
                        mode: profile.widgetDisplayMode,
                        valueStyle: profile.dashboardValueStyle,
                        theme: profile.widgetTheme,
                        compact: compact
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
            .padding(.horizontal, compact ? 14 : 17)
            .padding(.vertical, compact ? 10 : 12)
        }
        .foregroundStyle(palette.foreground)
        .background {
            ZStack {
                palette.background
                RadialGradient(
                    colors: [palette.glow.opacity(0.22), .clear],
                    center: .topTrailing,
                    startRadius: 4,
                    endRadius: 240
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(palette.foreground.opacity(0.1), lineWidth: 1)
        }
        .shadow(color: palette.glow.opacity(0.16), radius: 18, y: 10)
    }
}

private struct WidgetPreviewMetricRow: View {
    @ScaledMetric(relativeTo: .caption2) private var tightCaptionSize: CGFloat = 10
    let snapshot: MetricSnapshot
    let mode: WidgetDisplayMode
    let valueStyle: MetricValueStyle
    let theme: WidgetTheme
    let compact: Bool

    private var palette: WidgetThemePalette { theme.palette }

    var body: some View {
        Group {
            switch mode {
            case .countdown:
                countdown
            case .countdownWithPercentage:
                countdownWithPercentage
            case .progressBars:
                progressBar
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(snapshot.accessibilitySummary)
    }

    @ViewBuilder
    private var countdownWithPercentage: some View {
        if compact {
            ViewThatFits(in: .vertical) {
                compactCountdownWithPercentage(condensed: false, tight: false, barHeight: 3)
                compactCountdownWithPercentage(condensed: true, tight: false, barHeight: 2)
                compactCountdownWithPercentage(condensed: true, tight: true, barHeight: 2)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 0) {
                        countdownTitle()
                        percentageBadge()
                    }
                    Spacer(minLength: 4)
                    CountdownValueLabel(snapshot: snapshot, compact: false, combined: true)
                }
                combinedProgressBar(height: 3)
            }
        }
    }

    @ViewBuilder
    private var countdown: some View {
        if compact {
            ViewThatFits(in: .vertical) {
                compactCountdown(condensed: false)
                compactCountdown(condensed: true)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                countdownTitle()
                Spacer(minLength: 4)
                countdownValue
            }
        }
    }

    private func countdownTitle(tight: Bool = false) -> some View {
        Text(snapshot.title)
            .font(
                tight
                    ? .system(size: tightCaptionSize, weight: .semibold, design: .rounded)
                    : .system(compact ? .caption2 : .caption, design: .rounded, weight: .semibold)
            )
            .foregroundStyle(palette.secondaryForeground)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
    }

    private var countdownValue: some View {
        CountdownValueLabel(snapshot: snapshot, compact: compact)
    }

    private func compactCountdown(condensed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            countdownTitle()
            CountdownValueLabel(snapshot: snapshot, compact: true, condensed: condensed)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compactCountdownWithPercentage(
        condensed: Bool,
        tight: Bool,
        barHeight: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                countdownTitle(tight: tight)
                Spacer(minLength: 2)
                percentageBadge(tight: tight)
            }
            CountdownValueLabel(snapshot: snapshot, compact: true, condensed: condensed, tight: tight)
            combinedProgressBar(height: barHeight)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func percentageBadge(tight: Bool = false) -> some View {
        Text(snapshot.percentageText)
            .font(
                tight
                    ? .system(size: tightCaptionSize, weight: .bold, design: .rounded)
                    : .system(compact ? .caption2 : .caption, design: .rounded, weight: .bold)
            )
            .monospacedDigit()
            .foregroundStyle(palette.foreground)
            .padding(.horizontal, tight ? 4 : (compact ? 5 : 7))
            .padding(.vertical, compact ? 0 : 2)
            .background(palette.accent.opacity(0.18), in: Capsule())
    }

    private func combinedProgressBar(height: CGFloat) -> some View {
        ProgressBar(
            fraction: snapshot.elapsedFraction,
            colors: palette.colors(for: snapshot.kind),
            height: height,
            trackColor: palette.track
        )
    }

    private var progressBar: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(snapshot.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Spacer(minLength: 4)
                Text(snapshot.valueText(style: valueStyle, compact: compact))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .monospacedDigit()
                    .layoutPriority(1)
            }
            .font(.system(.caption, design: .rounded, weight: .semibold))

            ProgressBar(
                fraction: snapshot.elapsedFraction,
                colors: palette.colors(for: snapshot.kind),
                height: compact ? 5 : 6,
                trackColor: palette.track
            )
        }
    }
}
