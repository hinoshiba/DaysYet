import SwiftUI

enum DaysYetTheme {
    static let ink = Color(red: 0.035, green: 0.047, blue: 0.12)
    static let paper = Color(red: 0.96, green: 0.95, blue: 0.91)
    static let coral = Color(red: 1.0, green: 0.39, blue: 0.34)
    static let amber = Color(red: 1.0, green: 0.68, blue: 0.16)
    static let lime = Color(red: 0.76, green: 0.88, blue: 0.19)

    static func colors(for kind: MetricKind) -> [Color] {
        switch kind {
        case .week: [Color(red: 0.38, green: 0.78, blue: 0.95), Color(red: 0.26, green: 0.56, blue: 0.94)]
        case .month: [coral, Color(red: 1.0, green: 0.57, blue: 0.32)]
        case .year: [amber, Color(red: 1.0, green: 0.82, blue: 0.26)]
        case .healthyLife: [lime, Color(red: 0.42, green: 0.78, blue: 0.39)]
        case .customLife: [Color(red: 0.69, green: 0.48, blue: 0.98), Color(red: 0.95, green: 0.42, blue: 0.76)]
        }
    }
}

struct DaysYetBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            (colorScheme == .dark ? DaysYetTheme.ink : DaysYetTheme.paper)
            RadialGradient(
                colors: [DaysYetTheme.coral.opacity(colorScheme == .dark ? 0.14 : 0.08), .clear],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 430
            )
        }
        .ignoresSafeArea()
    }
}

struct EyebrowLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(1.5)
            .foregroundStyle(.secondary)
    }
}
