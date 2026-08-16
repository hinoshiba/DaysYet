import AppIntents
import SwiftUI
import WidgetKit

struct DaysYetTimelineEntry: TimelineEntry {
    let date: Date
    let configuration: DaysYetConfigurationIntent
    let profile: UserProfile
    let metrics: [MetricKind]
    let valueStyle: MetricValueStyle
}

struct DaysYetTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DaysYetTimelineEntry {
        let profile = UserProfile.initial
        return DaysYetTimelineEntry(
            date: .now,
            configuration: DaysYetConfigurationIntent(),
            profile: profile,
            metrics: [.week, .month, .year],
            valueStyle: .remaining
        )
    }

    func snapshot(for configuration: DaysYetConfigurationIntent, in context: Context) async -> DaysYetTimelineEntry {
        makeEntry(date: .now, configuration: configuration)
    }

    func timeline(for configuration: DaysYetConfigurationIntent, in context: Context) async -> Timeline<DaysYetTimelineEntry> {
        let now = Date.now
        let entries = (0..<8).compactMap { offset -> DaysYetTimelineEntry? in
            guard let date = Calendar.autoupdatingCurrent.date(byAdding: .minute, value: offset * 15, to: now) else {
                return nil
            }
            return makeEntry(date: date, configuration: configuration)
        }
        let refreshDate = Calendar.autoupdatingCurrent.date(byAdding: .hour, value: 2, to: now) ?? now.addingTimeInterval(7_200)
        return Timeline(entries: entries, policy: .after(refreshDate))
    }

    private func makeEntry(date: Date, configuration: DaysYetConfigurationIntent) -> DaysYetTimelineEntry {
        let profile = ProfileRepository.load()
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
            valueStyle: configuration.valueStyle.resolved(profileStyle: profile.dashboardValueStyle)
        )
    }
}

struct DaysYetWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: DaysYetTimelineEntry

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 9 : 12) {
            if family != .systemSmall {
                HStack(spacing: 6) {
                    Text("DAYSYET")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .tracking(1.1)
                    Spacer()
                    Image(systemName: "circle.dotted")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(renderingMode == .fullColor ? WidgetPalette.coral : .primary)
                }
            }

            ForEach(Array(entry.metrics.prefix(3).enumerated()), id: \.offset) { _, metric in
                let snapshot = TimeProgressCalculator.snapshot(
                    for: metric,
                    profile: entry.profile,
                    now: entry.date
                )
                WidgetMetricBar(
                    snapshot: snapshot,
                    valueStyle: entry.valueStyle,
                    compact: family == .systemSmall
                )
            }
        }
        .foregroundStyle(.white)
        .containerBackground(for: .widget) {
            ZStack {
                WidgetPalette.ink
                RadialGradient(
                    colors: [WidgetPalette.coral.opacity(0.25), .clear],
                    center: .topTrailing,
                    startRadius: 1,
                    endRadius: 230
                )
            }
        }
    }
}

private struct WidgetMetricBar: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let snapshot: MetricSnapshot
    let valueStyle: MetricValueStyle
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(compact ? snapshot.kind.shortTitle : snapshot.title)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(snapshot.valueText(style: valueStyle, compact: compact))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .monospacedDigit()
            }
            .font(.system(size: compact ? 11 : 12, weight: .semibold, design: .rounded))

            GeometryReader { geometry in
                let width = max(geometry.size.width * snapshot.remainingFraction, 4)
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.13))
                    Capsule()
                        .fill(barStyle)
                        .frame(width: width)
                }
            }
            .frame(height: compact ? 4 : 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(snapshot.accessibilitySummary)
    }

    private var barStyle: AnyShapeStyle {
        if renderingMode == .fullColor {
            let colors = WidgetPalette.colors(for: snapshot.kind)
            return AnyShapeStyle(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
        }
        return AnyShapeStyle(Color.primary)
    }
}

private enum WidgetPalette {
    static let ink = Color(red: 0.035, green: 0.047, blue: 0.12)
    static let coral = Color(red: 1.0, green: 0.39, blue: 0.34)
    static let amber = Color(red: 1.0, green: 0.68, blue: 0.16)
    static let lime = Color(red: 0.76, green: 0.88, blue: 0.19)

    static func colors(for kind: MetricKind) -> [Color] {
        switch kind {
        case .week: [Color.cyan, Color.blue]
        case .month: [coral, Color.orange]
        case .year: [amber, Color.yellow]
        case .healthyLife: [lime, Color.green]
        case .customLife: [Color.purple, Color.pink]
        }
    }
}

struct DaysYetWidget: Widget {
    let kind = "daysyet.hinoshiba.com.widget.progress"

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
