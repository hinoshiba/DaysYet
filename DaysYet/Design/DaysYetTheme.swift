import SwiftUI

enum DaysYetTheme {
    static let ink = Color(red: 0.035, green: 0.047, blue: 0.12)
    static let paper = Color(red: 247.0 / 255, green: 243.0 / 255, blue: 234.0 / 255)
    static let paperShade = Color(red: 0.94, green: 0.91, blue: 0.86)
    static let inkShade = Color(red: 21.0 / 255, green: 22.0 / 255, blue: 38.0 / 255)
    static let coral = Color(red: 1.0, green: 0.39, blue: 0.34)
    static let amber = Color(red: 1.0, green: 0.68, blue: 0.16)
    static let lime = Color(red: 0.76, green: 0.88, blue: 0.19)

    // App surfaces and controls stay consistent across widget themes.
    // Named colors adapt to light, dark, and increased-contrast appearances.
    static let panel = Color("PanelColor")
    static let onAccent = Color("OnAccentColor")

    static func colors(for kind: MetricKind, theme: WidgetTheme = .vividNight) -> [Color] {
        theme.palette.colors(for: kind)
    }
}

struct DaysYetBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        GeometryReader { geometry in
            let isDark = colorScheme == .dark
            let radius = max(geometry.size.width, geometry.size.height) * 0.75
            ZStack {
                LinearGradient(
                    colors: isDark ? [DaysYetTheme.ink, DaysYetTheme.inkShade]
                        : [DaysYetTheme.paper, DaysYetTheme.paperShade],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                if contrast != .increased {
                    RadialGradient(
                        colors: [DaysYetTheme.coral.opacity(isDark ? 0.12 : 0.11), .clear],
                        center: .topTrailing,
                        startRadius: 0,
                        endRadius: radius
                    )
                    RadialGradient(
                        colors: [DaysYetTheme.amber.opacity(isDark ? 0.05 : 0.06), .clear],
                        center: UnitPoint(x: 0, y: 0.6),
                        startRadius: 0,
                        endRadius: radius * 0.7
                    )
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Keep the app's paper-and-coral surface consistent while widget themes change.
    func daysYetBackground() -> some View {
        scrollContentBackground(.hidden)
            .background { DaysYetBackground() }
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
