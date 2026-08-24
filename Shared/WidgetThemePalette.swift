import SwiftUI

/// Semantic colors shared by the app preview and the WidgetKit extension.
/// Keeping the palette here prevents the preview from drifting from the widget.
struct WidgetThemePalette {
    let background: Color
    let foreground: Color
    let secondaryForeground: Color
    let track: Color
    let glow: Color
    let accent: Color
    private let metricGradients: [[Color]]

    func colors(for kind: MetricKind) -> [Color] {
        switch kind {
        case .week: metricGradients[0]
        case .month: metricGradients[1]
        case .year: metricGradients[2]
        case .healthyLife: metricGradients[3]
        case .customLife: metricGradients[4]
        }
    }

    static func palette(for theme: WidgetTheme) -> WidgetThemePalette {
        switch theme {
        case .vividNight:
            return WidgetThemePalette(
                background: Color(red: 0.035, green: 0.047, blue: 0.12),
                foreground: .white,
                secondaryForeground: .white.opacity(0.72),
                track: .white.opacity(0.13),
                glow: Color(red: 1.0, green: 0.39, blue: 0.34),
                accent: Color(red: 1.0, green: 0.39, blue: 0.34),
                metricGradients: [
                    [Color(red: 0.38, green: 0.78, blue: 0.95), Color(red: 0.26, green: 0.56, blue: 0.94)],
                    [Color(red: 1.0, green: 0.39, blue: 0.34), Color(red: 1.0, green: 0.57, blue: 0.32)],
                    [Color(red: 1.0, green: 0.68, blue: 0.16), Color(red: 1.0, green: 0.82, blue: 0.26)],
                    [Color(red: 0.76, green: 0.88, blue: 0.19), Color(red: 0.42, green: 0.78, blue: 0.39)],
                    [Color(red: 0.69, green: 0.48, blue: 0.98), Color(red: 0.95, green: 0.42, blue: 0.76)]
                ]
            )
        case .quietForest:
            return WidgetThemePalette(
                background: Color(red: 0.88, green: 0.91, blue: 0.86),
                foreground: Color(red: 0.12, green: 0.19, blue: 0.15),
                secondaryForeground: Color(red: 0.12, green: 0.19, blue: 0.15).opacity(0.72),
                track: Color(red: 0.12, green: 0.19, blue: 0.15).opacity(0.12),
                glow: Color(red: 0.60, green: 0.72, blue: 0.56),
                accent: Color(red: 0.34, green: 0.52, blue: 0.39),
                metricGradients: [
                    [Color(red: 0.32, green: 0.46, blue: 0.41), Color(red: 0.30, green: 0.46, blue: 0.41)],
                    [Color(red: 0.50, green: 0.41, blue: 0.33), Color(red: 0.55, green: 0.39, blue: 0.32)],
                    [Color(red: 0.45, green: 0.44, blue: 0.28), Color(red: 0.47, green: 0.43, blue: 0.26)],
                    [Color(red: 0.34, green: 0.46, blue: 0.31), Color(red: 0.30, green: 0.47, blue: 0.32)],
                    [Color(red: 0.44, green: 0.42, blue: 0.50), Color(red: 0.46, green: 0.41, blue: 0.54)]
                ]
            )
        case .softDawn:
            return WidgetThemePalette(
                background: Color(red: 0.96, green: 0.89, blue: 0.84),
                foreground: Color(red: 0.25, green: 0.15, blue: 0.16),
                secondaryForeground: Color(red: 0.25, green: 0.15, blue: 0.16).opacity(0.72),
                track: Color(red: 0.25, green: 0.15, blue: 0.16).opacity(0.12),
                glow: Color(red: 0.92, green: 0.62, blue: 0.49),
                accent: Color(red: 0.78, green: 0.39, blue: 0.35),
                metricGradients: [
                    [Color(red: 0.35, green: 0.44, blue: 0.48), Color(red: 0.32, green: 0.45, blue: 0.52)],
                    [Color(red: 0.62, green: 0.36, blue: 0.32), Color(red: 0.66, green: 0.33, blue: 0.33)],
                    [Color(red: 0.56, green: 0.40, blue: 0.26), Color(red: 0.61, green: 0.38, blue: 0.19)],
                    [Color(red: 0.39, green: 0.45, blue: 0.35), Color(red: 0.33, green: 0.46, blue: 0.36)],
                    [Color(red: 0.56, green: 0.37, blue: 0.47), Color(red: 0.58, green: 0.35, blue: 0.52)]
                ]
            )
        case .calmSea:
            return WidgetThemePalette(
                background: Color(red: 0.87, green: 0.93, blue: 0.95),
                foreground: Color(red: 0.10, green: 0.20, blue: 0.25),
                secondaryForeground: Color(red: 0.10, green: 0.20, blue: 0.25).opacity(0.72),
                track: Color(red: 0.10, green: 0.20, blue: 0.25).opacity(0.12),
                glow: Color(red: 0.48, green: 0.71, blue: 0.77),
                accent: Color(red: 0.25, green: 0.53, blue: 0.65),
                metricGradients: [
                    [Color(red: 0.25, green: 0.47, blue: 0.54), Color(red: 0.22, green: 0.47, blue: 0.59)],
                    [Color(red: 0.32, green: 0.46, blue: 0.57), Color(red: 0.31, green: 0.45, blue: 0.62)],
                    [Color(red: 0.35, green: 0.46, blue: 0.49), Color(red: 0.29, green: 0.47, blue: 0.52)],
                    [Color(red: 0.27, green: 0.48, blue: 0.47), Color(red: 0.23, green: 0.48, blue: 0.48)],
                    [Color(red: 0.40, green: 0.43, blue: 0.59), Color(red: 0.41, green: 0.42, blue: 0.64)]
                ]
            )
        }
    }
}

extension WidgetTheme {
    var palette: WidgetThemePalette {
        WidgetThemePalette.palette(for: self)
    }
}
