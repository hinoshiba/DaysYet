import SwiftUI

struct WidgetPreview: View {
    let profile: UserProfile
    var compact = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: compact ? 11 : 14) {
                HStack {
                    Text("DAYSYET")
                        .font(.caption2.weight(.black))
                        .tracking(1.2)
                    Spacer()
                    Image(systemName: "circle.dotted")
                        .foregroundStyle(DaysYetTheme.coral)
                }

                ForEach(profile.normalizedDashboardMetrics) { metric in
                    let snapshot = TimeProgressCalculator.snapshot(for: metric, profile: profile, now: context.date)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(snapshot.title)
                                .lineLimit(1)
                            Spacer()
                            Text(snapshot.valueText(style: profile.dashboardValueStyle, compact: compact))
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                                .monospacedDigit()
                        }
                        .font(.caption.weight(.semibold))

                        ProgressBar(
                            fraction: snapshot.remainingFraction,
                            colors: DaysYetTheme.colors(for: metric),
                            height: compact ? 5 : 6
                        )
                    }
                }
            }
            .padding(compact ? 14 : 17)
        }
        .foregroundStyle(.white)
        .background {
            ZStack {
                DaysYetTheme.ink
                RadialGradient(
                    colors: [DaysYetTheme.coral.opacity(0.22), .clear],
                    center: .topTrailing,
                    startRadius: 4,
                    endRadius: 240
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        }
        .shadow(color: DaysYetTheme.ink.opacity(0.18), radius: 18, y: 10)
    }
}
