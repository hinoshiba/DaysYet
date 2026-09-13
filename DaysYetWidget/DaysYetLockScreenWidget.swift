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

        entryDates += TimeProgressCalculator.transitionDates(
            for: metric,
            profile: profile,
            after: now,
            through: refreshDate,
            calendar: calendar
        )

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
        ZStack {
            Circle()
                .stroke(.primary.opacity(0.2), lineWidth: 4)
            if snapshot.remainingFraction > 0 {
                Circle()
                    .trim(from: 1 - snapshot.remainingFraction, to: 1)
                    .stroke(.primary, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 1) {
                Image(systemName: snapshot.kind.symbolName)
                    .font(.caption2)
                Text(roundedPercentageText)
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .minimumScaleFactor(0.7)
                    .monospacedDigit()
            }
            .padding(6)
        }
        .padding(2)
        .widgetAccentable()
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Label(snapshot.title, systemImage: snapshot.kind.symbolName)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 2)
                if !snapshot.isOff {
                    Text(roundedPercentageText)
                        .monospacedDigit()
                }
            }
            .font(.system(.caption2, design: .rounded, weight: .semibold))

            Text(snapshot.valueText(style: .remaining, compact: true))
                .font(.system(.headline, design: .rounded, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .allowsTightening(true)
                .monospacedDigit()

            ProgressView(value: snapshot.remainingFraction)
                .progressViewStyle(.linear)
                .widgetAccentable()
                .accessibilityHidden(true)
        }
    }

    private var roundedPercentageText: String {
        snapshot.isOff ? "Off" : RemainingPercentage.compactText(for: snapshot.remainingFraction)
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
