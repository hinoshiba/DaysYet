import AppIntents
import SwiftUI
import WidgetKit

struct DaysYetTimelineEntry: TimelineEntry {
    let date: Date
    let configuration: DaysYetConfigurationIntent
    let profile: UserProfile
    let metrics: [MetricKind]
    let displayMode: WidgetDisplayMode
    let valueStyle: MetricValueStyle
    let theme: WidgetTheme
}

struct DaysYetTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DaysYetTimelineEntry {
        let profile = UserProfile.initial
        return DaysYetTimelineEntry(
            date: .now,
            configuration: DaysYetConfigurationIntent(),
            profile: profile,
            metrics: [.week, .month, .year],
            displayMode: .progressBars,
            valueStyle: .remaining,
            theme: .vividNight
        )
    }

    func snapshot(for configuration: DaysYetConfigurationIntent, in context: Context) async -> DaysYetTimelineEntry {
        makeEntry(date: .now, configuration: configuration)
    }

    func timeline(for configuration: DaysYetConfigurationIntent, in context: Context) async -> Timeline<DaysYetTimelineEntry> {
        let now = Date.now
        let calendar = Calendar.autoupdatingCurrent
        let profile = ProfileRepository.load()
        let firstEntry = makeEntry(date: now, configuration: configuration, profile: profile)
        let refreshDate = calendar.date(byAdding: .hour, value: 2, to: now)
            ?? now.addingTimeInterval(7_200)
        var entryDates = [now, refreshDate]

        if firstEntry.displayMode.showsLiveCountdown {
            // Remaining values expose minutes, so keep them aligned to the
            // clock without asking WidgetKit to reload the whole timeline.
            let nextMinute = calendar.dateInterval(of: .minute, for: now)?.end
                ?? now.addingTimeInterval(60)
            entryDates += (0..<120).compactMap {
                calendar.date(byAdding: .minute, value: $0, to: nextMinute)
            }
        } else {
            entryDates += (1..<8).compactMap {
                calendar.date(byAdding: .minute, value: $0 * 15, to: now)
            }
        }

        // Period and milestone boundaries must never keep showing a stale
        // "remaining" state, even when they fall between regular entries.
        for metric in firstEntry.metrics {
            let boundary = TimeProgressCalculator.dateInterval(
                for: metric,
                profile: profile,
                now: now,
                calendar: calendar
            ).end
            if boundary > now, boundary <= refreshDate {
                entryDates.append(boundary)
            }
        }

        let entries = Set(entryDates)
            .sorted()
            .map { makeEntry(date: $0, configuration: configuration, profile: profile) }
        return Timeline(entries: entries, policy: .after(refreshDate))
    }

    private func makeEntry(
        date: Date,
        configuration: DaysYetConfigurationIntent,
        profile: UserProfile = ProfileRepository.load()
    ) -> DaysYetTimelineEntry {
        let metrics: [MetricKind]
        if !profile.isConfigured {
            metrics = [.week, .month, .year]
        } else if configuration.followsAppSelection {
            metrics = profile.normalizedDashboardMetrics
        } else {
            metrics = [
                configuration.firstMetric.metricKind,
                configuration.secondMetric.metricKind,
                configuration.thirdMetric.metricKind
            ]
        }
        return DaysYetTimelineEntry(
            date: date,
            configuration: configuration,
            profile: profile,
            metrics: metrics,
            displayMode: configuration.displayMode.resolved(profileMode: profile.widgetDisplayMode),
            valueStyle: configuration.valueStyle.resolved(profileStyle: profile.dashboardValueStyle),
            theme: configuration.theme.resolved(profileTheme: profile.widgetTheme)
        )
    }
}

struct DaysYetWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: DaysYetTimelineEntry

    private var palette: WidgetThemePalette { entry.theme.palette }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(entry.metrics.prefix(3).enumerated()), id: \.offset) { _, metric in
                let snapshot = TimeProgressCalculator.snapshot(
                    for: metric,
                    profile: entry.profile,
                    now: entry.date
                )
                WidgetMetricRow(
                    snapshot: snapshot,
                    mode: entry.displayMode,
                    valueStyle: entry.valueStyle,
                    theme: entry.theme,
                    compact: family == .systemSmall
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .foregroundStyle(renderingMode == .fullColor ? AnyShapeStyle(palette.foreground) : AnyShapeStyle(Color.primary))
        .containerBackground(for: .widget) {
            ZStack {
                palette.background
                RadialGradient(
                    colors: [palette.glow.opacity(0.22), .clear],
                    center: .topTrailing,
                    startRadius: 1,
                    endRadius: 230
                )
            }
        }
    }
}

private struct WidgetMetricRow: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
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
                metricProgressBar(height: 3)
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
            .foregroundStyle(
                renderingMode == .fullColor
                    ? AnyShapeStyle(palette.secondaryForeground)
                    : AnyShapeStyle(HierarchicalShapeStyle.secondary)
            )
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
            metricProgressBar(height: barHeight)
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
            .foregroundStyle(
                renderingMode == .fullColor
                    ? AnyShapeStyle(palette.foreground)
                    : AnyShapeStyle(Color.primary)
            )
            .padding(.horizontal, tight ? 4 : (compact ? 5 : 7))
            .padding(.vertical, compact ? 0 : 2)
            .background(badgeBackground, in: Capsule())
    }

    private var badgeBackground: AnyShapeStyle {
        if renderingMode == .fullColor {
            return AnyShapeStyle(palette.accent.opacity(0.18))
        }
        return AnyShapeStyle(Color.primary.opacity(0.14))
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

            metricProgressBar(height: compact ? 4 : 6)
        }
    }

    private func metricProgressBar(height: CGFloat) -> some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width * snapshot.remainingFraction, height)
            ZStack(alignment: .leading) {
                Capsule().fill(trackStyle)
                Capsule()
                    .fill(barStyle)
                    .frame(width: width)
                    .widgetAccentable()
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private var trackStyle: AnyShapeStyle {
        if renderingMode == .fullColor {
            return AnyShapeStyle(palette.track)
        }
        return AnyShapeStyle(Color.primary.opacity(0.14))
    }

    private var barStyle: AnyShapeStyle {
        if renderingMode == .fullColor {
            return AnyShapeStyle(
                LinearGradient(colors: palette.colors(for: snapshot.kind), startPoint: .leading, endPoint: .trailing)
            )
        }
        return AnyShapeStyle(Color.primary)
    }
}

struct DaysYetWidget: Widget {
    let kind = "com.hinoshiba.daysyet.widget.progress"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: DaysYetConfigurationIntent.self,
            provider: DaysYetTimelineProvider()
        ) { entry in
            DaysYetWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("widget.gallery.title")
        .description("widget.gallery.description")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
