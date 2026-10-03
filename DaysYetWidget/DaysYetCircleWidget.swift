import AppIntents
import SwiftUI
import WidgetKit

struct DaysYetCircleTimelineEntry: TimelineEntry {
    let date: Date
    let profile: UserProfile
    let metrics: [MetricKind]
    let valueStyle: MetricValueStyle
    let theme: WidgetTheme
}

struct DaysYetCircleTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DaysYetCircleTimelineEntry {
        makeEntry(date: .now, configuration: DaysYetCircleConfigurationIntent(), profile: .initial)
    }

    func snapshot(for configuration: DaysYetCircleConfigurationIntent, in context: Context) async -> DaysYetCircleTimelineEntry {
        makeEntry(date: .now, configuration: configuration)
    }

    func timeline(for configuration: DaysYetCircleConfigurationIntent, in context: Context) async -> Timeline<DaysYetCircleTimelineEntry> {
        let now = Date.now
        let calendar = Calendar.autoupdatingCurrent
        let profile = ProfileRepository.load()
        let firstEntry = makeEntry(date: now, configuration: configuration, profile: profile)
        let refreshDate = calendar.date(byAdding: .hour, value: 2, to: now)
            ?? now.addingTimeInterval(7_200)
        var entryDates = [now, refreshDate]

        if firstEntry.valueStyle == .remaining {
            let nextMinute = calendar.dateInterval(of: .minute, for: now)?.end
                ?? now.addingTimeInterval(60)
            entryDates += (0..<120).compactMap {
                calendar.date(byAdding: .minute, value: $0, to: nextMinute)
            }
        } else {
            entryDates += (1..<24).compactMap {
                calendar.date(byAdding: .minute, value: $0 * 5, to: now)
            }
        }

        // Scheduled starts/ends and midnight resets also apply to the fourth slot.
        for metric in firstEntry.metrics {
            entryDates += TimeProgressCalculator.transitionDates(
                for: metric, profile: profile, after: now, through: refreshDate, calendar: calendar
            )
        }

        let entries = Set(entryDates).sorted().map {
            makeEntry(date: $0, configuration: configuration, profile: profile)
        }
        return Timeline(entries: entries, policy: .after(refreshDate))
    }

    private func makeEntry(
        date: Date,
        configuration: DaysYetCircleConfigurationIntent,
        profile: UserProfile = ProfileRepository.load()
    ) -> DaysYetCircleTimelineEntry {
        DaysYetCircleTimelineEntry(
            date: date,
            profile: profile,
            metrics: configuration.resolvedMetrics(profile: profile),
            valueStyle: configuration.valueStyle.resolved(profileStyle: profile.dashboardValueStyle),
            theme: configuration.theme.resolved(profileTheme: profile.widgetTheme)
        )
    }
}

struct DaysYetCircleWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DaysYetCircleTimelineEntry

    var body: some View {
        CircleWidgetGrid(
            snapshots: entry.metrics.map {
                TimeProgressCalculator.snapshot(for: $0, profile: entry.profile, now: entry.date)
            },
            valueStyle: entry.valueStyle,
            theme: entry.theme,
            compact: family == .systemSmall
        )
        .containerBackground(for: .widget) {
            entry.theme.palette.background
        }
    }
}

struct DaysYetCircleWidget: Widget {
    let kind = "com.hinoshiba.daysyet.widget.circles"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: DaysYetCircleConfigurationIntent.self,
            provider: DaysYetCircleTimelineProvider()
        ) { entry in
            DaysYetCircleWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("widget.circle.gallery.title")
        .description("widget.circle.gallery.description")
        .supportedFamilies([.systemSmall, .systemLarge])
    }
}
