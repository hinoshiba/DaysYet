import AppIntents
import SwiftUI
import WidgetKit

struct DaysYetLockScreenConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "widget.lock_screen.configuration.title"
    static let description = IntentDescription("widget.lock_screen.configuration.description")

    @Parameter(title: "widget.lock_screen.configuration.metric", default: .appSelection)
    var metric: LockScreenMetricOption

    init() {
        metric = .appSelection
    }
}

struct DaysYetLockScreenTimelineEntry: TimelineEntry {
    let date: Date
    let configuration: DaysYetLockScreenConfigurationIntent
    let profile: UserProfile
    let metric: MetricKind
}

struct DaysYetLockScreenTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DaysYetLockScreenTimelineEntry {
        makeEntry(date: .now, configuration: DaysYetLockScreenConfigurationIntent(), profile: .initial)
    }

    func snapshot(
        for configuration: DaysYetLockScreenConfigurationIntent,
        in context: Context
    ) async -> DaysYetLockScreenTimelineEntry {
        makeEntry(date: .now, configuration: configuration)
    }

    func timeline(
        for configuration: DaysYetLockScreenConfigurationIntent,
        in context: Context
    ) async -> Timeline<DaysYetLockScreenTimelineEntry> {
        let now = Date.now
        let calendar = Calendar.autoupdatingCurrent
        let profile = ProfileRepository.load()
        let metric = configuration.metric.resolved(profile: profile)
        let refreshDate = calendar.date(byAdding: .hour, value: 2, to: now)
            ?? now.addingTimeInterval(7_200)
        var entryDates = [now]
        entryDates += (1...24).compactMap {
            calendar.date(byAdding: .minute, value: $0 * 5, to: now)
        }

        let boundary = TimeProgressCalculator.dateInterval(
            for: metric,
            profile: profile,
            now: now,
            calendar: calendar
        ).end
        if boundary > now, boundary <= refreshDate {
            entryDates.append(boundary)
        }

        let entries = Set(entryDates)
            .sorted()
            .map { makeEntry(date: $0, configuration: configuration, profile: profile) }
        return Timeline(entries: entries, policy: .after(refreshDate))
    }

    private func makeEntry(
        date: Date,
        configuration: DaysYetLockScreenConfigurationIntent,
        profile: UserProfile = ProfileRepository.load()
    ) -> DaysYetLockScreenTimelineEntry {
        DaysYetLockScreenTimelineEntry(
            date: date,
            configuration: configuration,
            profile: profile,
            metric: configuration.metric.resolved(profile: profile)
        )
    }
}

struct DaysYetLockScreenWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DaysYetLockScreenTimelineEntry

    private var snapshot: MetricSnapshot {
        TimeProgressCalculator.snapshot(
            for: entry.metric,
            profile: entry.profile,
            now: entry.date
        )
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                inlineView
            case .accessoryCircular:
                circularView
            case .accessoryRectangular:
                rectangularView
            default:
                rectangularView
            }
        }
        .containerBackground(for: .widget) {
            Color.clear
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(snapshot.accessibilitySummary)
        .privacySensitive(entry.metric == .healthyLife || entry.metric == .customLife)
    }

    private var inlineView: some View {
        ViewThatFits(in: .horizontal) {
            Label {
                Text("\(snapshot.valueText(style: .remaining, compact: true)) · \(snapshot.title)")
            } icon: {
                Image(systemName: snapshot.kind.symbolName)
            }
            Text(snapshot.valueText(style: .remaining, compact: true))
        }
        .lineLimit(1)
    }

    private var circularView: some View {
        Gauge(value: snapshot.elapsedFraction) {
            Image(systemName: snapshot.kind.symbolName)
        } currentValueLabel: {
            Text(roundedPercentageText)
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .minimumScaleFactor(0.7)
                .monospacedDigit()
        }
        .gaugeStyle(.accessoryCircular)
        .widgetAccentable()
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Label(snapshot.title, systemImage: snapshot.kind.symbolName)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 2)
                Text(roundedPercentageText)
                    .monospacedDigit()
            }
            .font(.system(.caption2, design: .rounded, weight: .semibold))

            Text(snapshot.valueText(style: .remaining, compact: true))
                .font(.system(.headline, design: .rounded, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .allowsTightening(true)
                .monospacedDigit()

            ProgressView(value: snapshot.elapsedFraction)
                .progressViewStyle(.linear)
                .widgetAccentable()
                .accessibilityHidden(true)
        }
    }

    private var roundedPercentageText: String {
        "\(Int((snapshot.elapsedFraction * 100).rounded()))%"
    }
}

struct DaysYetLockScreenWidget: Widget {
    let kind = "com.hinoshiba.daysyet.widget.lock-screen"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: DaysYetLockScreenConfigurationIntent.self,
            provider: DaysYetLockScreenTimelineProvider()
        ) { entry in
            DaysYetLockScreenWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("widget.lock_screen.gallery.title")
        .description("widget.lock_screen.gallery.description")
        .supportedFamilies([.accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}
