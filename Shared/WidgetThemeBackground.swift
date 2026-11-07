import SwiftUI

/// One surface for both layouts, in previews and WidgetKit containers.
struct WidgetThemeBackground: View {
    @Environment(\.colorSchemeContrast) private var contrast
    let theme: WidgetTheme

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                theme.palette.background
                if contrast != .increased {
                    RadialGradient(
                        colors: [theme.palette.glow.opacity(0.22), .clear],
                        center: .topTrailing,
                        startRadius: 0,
                        endRadius: max(geometry.size.width, geometry.size.height) * 0.75
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
