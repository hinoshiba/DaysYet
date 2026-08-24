import SwiftUI

enum DaysYetTheme {
    static let ink = Color(red: 0.035, green: 0.047, blue: 0.12)
    static let paper = Color(red: 0.96, green: 0.95, blue: 0.91)
    static let coral = Color(red: 1.0, green: 0.39, blue: 0.34)
    static let amber = Color(red: 1.0, green: 0.68, blue: 0.16)
    static let lime = Color(red: 0.76, green: 0.88, blue: 0.19)

    static func colors(for kind: MetricKind, theme: WidgetTheme = .vividNight) -> [Color] {
        theme.palette.colors(for: kind)
    }

    static func appBackground(for theme: WidgetTheme, colorScheme: ColorScheme) -> Color {
        switch (theme, colorScheme) {
        case (.vividNight, .dark): ink
        case (.vividNight, _): paper
        case (.quietForest, .dark): Color(red: 0.055, green: 0.10, blue: 0.075)
        case (.quietForest, _): Color(red: 0.94, green: 0.96, blue: 0.92)
        case (.softDawn, .dark): Color(red: 0.13, green: 0.075, blue: 0.085)
        case (.softDawn, _): Color(red: 0.98, green: 0.95, blue: 0.91)
        case (.calmSea, .dark): Color(red: 0.045, green: 0.095, blue: 0.12)
        case (.calmSea, _): Color(red: 0.93, green: 0.97, blue: 0.98)
        }
    }
}

struct DaysYetBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    var theme: WidgetTheme = .vividNight

    var body: some View {
        ZStack {
            DaysYetTheme.appBackground(for: theme, colorScheme: colorScheme)
            RadialGradient(
                colors: [theme.palette.accent.opacity(colorScheme == .dark ? 0.14 : 0.08), .clear],
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
