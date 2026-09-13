import AppKit
import SwiftUI

/// Template accents and optional colors chosen for individual timelines.
enum MacWidgetStyle {
    // Match the physical camera cutout instead of outlining it in dark gray.
    static let background = Color.black
    static let foreground = Color.white.opacity(0.93)
    static let secondary = Color.white.opacity(0.60)

    static func accent(for kind: MetricKind, theme: WidgetTheme,
                       customColors: [MetricKind: MacWidgetColor] = [:]) -> Color {
        if let custom = customColors[kind] { return custom.color }
        return switch theme {
        case .vividNight:
            switch kind {
            case .week: Color(red: 0.92, green: 0.52, blue: 0.37)
            case .month: Color(red: 0.48, green: 0.72, blue: 0.58)
            case .year: Color(red: 0.85, green: 0.81, blue: 0.40)
            case .healthyLife: Color(red: 0.60, green: 0.77, blue: 0.46)
            case .customLife: Color(red: 0.72, green: 0.60, blue: 0.87)
            case .activity: Color(red: 0.94, green: 0.65, blue: 0.37)
            case .workday: Color(red: 0.39, green: 0.74, blue: 0.82)
            case .study: Color(red: 0.55, green: 0.65, blue: 0.96)
            }
        case .quietForest:
            Color(red: kind == .month ? 0.68 : 0.52, green: 0.74, blue: 0.57)
        case .softDawn:
            Color(red: 0.93, green: kind == .year ? 0.72 : 0.59, blue: 0.55)
        case .calmSea:
            Color(red: 0.48, green: kind == .month ? 0.66 : 0.76, blue: 0.87)
        }
    }
}

/// A scalable closed silhouette for the miniature placement preview.
struct MacEdgeNotchShape: Shape {
    var edge: MacWidgetEdge

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        if edge == .top {
            let shoulder = min(w * 0.10, h * 0.22)
            let corner = min(w * 0.13, h * 0.26)
            var path = Path()
            path.move(to: CGPoint(x: 0, y: 0))
            path.addCurve(to: CGPoint(x: shoulder, y: shoulder),
                          control1: CGPoint(x: shoulder * 0.7, y: 0),
                          control2: CGPoint(x: shoulder, y: shoulder * 0.3))
            path.addLine(to: CGPoint(x: shoulder, y: h - corner))
            path.addQuadCurve(to: CGPoint(x: shoulder + corner, y: h), control: CGPoint(x: shoulder, y: h))
            path.addLine(to: CGPoint(x: w - shoulder - corner, y: h))
            path.addQuadCurve(to: CGPoint(x: w - shoulder, y: h - corner), control: CGPoint(x: w - shoulder, y: h))
            path.addLine(to: CGPoint(x: w - shoulder, y: shoulder))
            path.addCurve(to: CGPoint(x: w, y: 0),
                          control1: CGPoint(x: w - shoulder, y: shoulder * 0.3),
                          control2: CGPoint(x: w - shoulder * 0.7, y: 0))
            path.closeSubpath()
            return path.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY))
        }
        let shoulder = min(29.0, h / 5)
        var path = Path()
        path.move(to: CGPoint(x: w, y: 0))
        let neck = max(w - 29, w * 0.37)
        path.addCurve(to: CGPoint(x: neck, y: shoulder * 0.64),
                      control1: CGPoint(x: w, y: shoulder * 0.52),
                      control2: CGPoint(x: w - 12, y: shoulder * 0.64))
        path.addLine(to: CGPoint(x: 17, y: shoulder * 0.64))
        path.addCurve(to: CGPoint(x: 0, y: shoulder * 1.40),
                      control1: CGPoint(x: 4, y: shoulder * 0.64),
                      control2: CGPoint(x: 0, y: shoulder * 0.93))
        path.addLine(to: CGPoint(x: 0, y: h - shoulder * 1.40))
        path.addCurve(to: CGPoint(x: 17, y: h - shoulder * 0.64),
                      control1: CGPoint(x: 4, y: h - shoulder * 0.93),
                      control2: CGPoint(x: 4, y: h - shoulder * 0.64))
        path.addLine(to: CGPoint(x: neck, y: h - shoulder * 0.64))
        path.addCurve(to: CGPoint(x: w, y: h),
                      control1: CGPoint(x: w - 12, y: h - shoulder * 0.64),
                      control2: CGPoint(x: w, y: h - shoulder * 0.52))
        path.closeSubpath()
        if edge == .left {
            path = path.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: w, ty: 0))
        }
        return path.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY))
    }
}

/// Top placement keeps the physical camera fixed while scaling the progress strip.
/// Side details and their surface follow the selected circular meter.
struct MacDesktopWidgetView: View {
    @ObservedObject var store: ProfileStore
    @ObservedObject var preferences: MacWidgetPreferences
    @ObservedObject var controller: MacWidgetController

    var body: some View {
        GeometryReader { geometry in
            let scale = MacWidgetPlacement.clampedScale(preferences.scale)
            let surface = Path(MacWidgetSurface.path(
                in: geometry.size, edge: preferences.edge, selectedIndex: controller.selectionPosition,
                scale: scale, topCameraInset: controller.topInfo.cameraInset,
                topNotchWidth: controller.topInfo.notchWidth, metricCount: controller.activeMetrics.count
            ))
            ZStack(alignment: .topLeading) {
                surface.fill(MacWidgetStyle.background)
                if preferences.edge == .top {
                    topContent(in: geometry.size, scale: scale)
                } else {
                    let width = geometry.size.width / scale
                    let height = MacWidgetPlacement.railHeight(for: controller.activeMetrics.count)
                    let verticalScale = MacWidgetPlacement.sideVerticalScale(in: geometry.size,
                        scale: scale, metricCount: controller.activeMetrics.count)
                    sideContent(width: width, height: height)
                        .frame(width: width, height: height)
                        .scaleEffect(x: scale, y: verticalScale, anchor: .topLeading)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .clipShape(surface)
            .contentShape(surface)
            .accessibilityAction(named: Text(L10n.text("設定を開く", "Open settings"))) {
                controller.showSettings()
            }
        }
        .onHover { controller.hoverChanged($0) }
        .onExitCommand { controller.closeDetails() }
    }

    private func topContent(in size: CGSize, scale: Double) -> some View {
        let inset = controller.topInfo.cameraInset
        let closed = MacWidgetPlacement.topClosedHeight(cameraInset: inset, scale: scale)
        let expanded = MacWidgetPlacement.topExpandedHeight(cameraInset: inset, scale: scale)
        let progress = min(max((size.height - closed) / max(expanded - closed, 1), 0), 1)
        let reveal = min(max((progress - 0.35) / 0.55, 0), 1)
        let strip = MacWidgetSurface.topProgressFrame(in: size, scale: scale,
            topCameraInset: inset, topNotchWidth: controller.topInfo.notchWidth)
        let detail = MacWidgetPlacement.topDetailFrame(in: size, cameraInset: inset, scale: scale)
        return ZStack(alignment: .topLeading) {
            MacTopProgressBarView(store: store, preferences: preferences, controller: controller)
                .frame(width: strip.width, height: strip.height)
                .offset(x: strip.minX, y: strip.minY)
            detailContent(width: detail.width / scale)
                .scaleEffect(scale, anchor: .topLeading)
                .offset(x: detail.minX, y: detail.minY)
                .opacity(reveal)
                .accessibilityHidden(!controller.isExpanded)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func sideContent(width: CGFloat, height: CGFloat) -> some View {
        let expansion = min(max((width - 46) / 158, 0), 1)
        let reveal = min(max((expansion - 0.42) / 0.50, 0), 1)
        let detail = MacWidgetPlacement.sideDetailFrame(in: CGSize(width: width, height: height),
            edge: preferences.edge, selectedIndex: controller.selectionPosition, scale: 1,
            metricCount: controller.activeMetrics.count)
        return ZStack(alignment: .topLeading) {
            detailContent(width: detail.width)
                .offset(x: detail.minX, y: detail.minY)
                .opacity(reveal)
                .accessibilityHidden(!controller.isExpanded)
            MacTimeRailView(store: store, preferences: preferences, controller: controller)
                .frame(width: 46, height: height)
                .offset(x: preferences.edge == .right ? width - 46 : 0)
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }

    private func detailContent(width: CGFloat) -> some View {
        MacTimeDetailView(store: store, preferences: preferences, controller: controller)
            .frame(width: width, height: 52)
            .contentShape(Rectangle())
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { controller.showSettings() }
            .accessibilityHint(L10n.text("ダブルクリックで設定を開きます", "Double-click to open settings"))
    }
}

/// Three horizontal progress segments live just below the camera cutout.
/// Proximity hover is managed by the controller without intercepting clicks
/// in the transparent area below this deliberately narrow surface.
struct MacTopProgressBarView: View {
    @ObservedObject var store: ProfileStore
    @ObservedObject var preferences: MacWidgetPreferences
    @ObservedObject var controller: MacWidgetController

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.periodic(from: .now, by: 60)) { context in
                HStack(spacing: 0) {
                    ForEach(store.profile.macWidgetMetrics(for: .top)) { kind in
                        let snapshot = TimeProgressCalculator.snapshot(for: kind, profile: store.profile, now: context.date)
                        let selected = controller.isExpanded && controller.selectedMetric == kind
                        let width = max(geometry.size.width / 3 - 4, 0)
                        let thickness = min(2 * MacWidgetPlacement.clampedScale(preferences.scale), geometry.size.height)
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.16))
                            Capsule()
                                .fill(MacWidgetStyle.accent(for: kind, theme: store.profile.widgetTheme,
                                    customColors: preferences.customColors)
                                    .opacity(selected ? 1 : 0.86))
                                .frame(width: width * snapshot.elapsedFraction)
                        }
                        .frame(width: width, height: thickness)
                        .frame(width: geometry.size.width / 3, height: geometry.size.height)
                        .contentShape(Rectangle())
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(snapshot.accessibilitySummary)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { controller.showSettings() }
                        .accessibilityHint(L10n.text("ダブルクリックで設定を開きます", "Double-click to open settings"))
                        .help(L10n.text("ダブルクリックで設定を開きます", "Double-click to open settings"))
                    }
                }
            }
        }
    }
}

struct MacPercentageRing: View {
    static let hoverScale: CGFloat = 1.35

    let fraction: Double
    let accent: Color
    var selected = false
    var subdued = false
    var isOff = false

    var body: some View {
        ZStack {
            ZStack {
                Circle().stroke(.white.opacity(0.10), lineWidth: 1.5)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .opacity(selected ? 1 : (subdued ? 0.68 : 0.80))
            HStack(alignment: .firstTextBaseline, spacing: 0.5) {
                if isOff {
                    Text("Off")
                        .font(.system(size: 9, weight: .medium))
                } else {
                    Text("\(Int((fraction * 100).rounded(.down)))")
                        .font(.system(size: 10, weight: .semibold))
                        .monospacedDigit()
                    Text("%")
                        .font(.system(size: 7, weight: .medium))
                }
            }
            .foregroundStyle(selected ? MacWidgetStyle.foreground : Color.white.opacity(0.76))
        }
        .frame(width: 32, height: 32)
    }
}

struct MacTimeRailView: View {
    @ObservedObject var store: ProfileStore
    @ObservedObject var preferences: MacWidgetPreferences
    @ObservedObject var controller: MacWidgetController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(spacing: 0) {
                ForEach(controller.activeMetrics) { kind in
                    railMetric(TimeProgressCalculator.snapshot(for: kind, profile: store.profile, now: context.date))
                }
            }
            .padding(.vertical, 31)
        }
    }

    private func railMetric(_ snapshot: MetricSnapshot) -> some View {
        let selected = controller.isExpanded && controller.selectedMetric == snapshot.kind
        let hovered = controller.hoveredMetric == snapshot.kind
        let accent = MacWidgetStyle.accent(for: snapshot.kind, theme: store.profile.widgetTheme,
                                          customColors: preferences.customColors)
        return MacPercentageRing(fraction: snapshot.elapsedFraction, accent: accent,
                                 selected: selected, subdued: controller.isExpanded && !selected, isOff: snapshot.isOff)
        .scaleEffect(hovered ? MacPercentageRing.hoverScale : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hovered)
        // Keep the target fixed while the ring grows, so adjacent rows do not
        // shift or repeatedly enter and exit hover during the animation.
        .frame(width: 46, height: 50)
        .contentShape(Rectangle())
        .onHover { controller.metricHoverChanged(snapshot.kind, hovering: $0) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(snapshot.accessibilitySummary)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { controller.showSettings() }
        .accessibilityHint(L10n.text("ダブルクリックで設定を開きます", "Double-click to open settings"))
        .help(L10n.text("ダブルクリックで設定を開きます", "Double-click to open settings"))
    }
}

struct MacTimeDetailView: View {
    @ObservedObject var store: ProfileStore
    @ObservedObject var preferences: MacWidgetPreferences
    @ObservedObject var controller: MacWidgetController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let metrics = controller.activeMetrics
            let kind = controller.selectedMetric.flatMap { metrics.contains($0) ? $0 : nil } ?? metrics[0]
            let snapshot = TimeProgressCalculator.snapshot(for: kind, profile: store.profile, now: context.date)
            ZStack {
                detail(snapshot)
                    .id(kind)
                    .transition(.opacity)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.12), value: kind)
        }
    }

    private func detail(_ snapshot: MetricSnapshot) -> some View {
        let top = preferences.edge == .top
        let scale = MacWidgetPlacement.clampedScale(preferences.scale)
        let mode = store.profile.widgetDisplayMode
        let showsBar = mode != .countdown
        let showsPercentage = mode == .countdownWithPercentage && !snapshot.isOff
        let accent = MacWidgetStyle.accent(for: snapshot.kind, theme: store.profile.widgetTheme,
                                          customColors: preferences.customColors)
        return VStack(alignment: top ? .center : .leading, spacing: showsBar ? 2 : 5) {
            HStack(spacing: 5) {
                Text(snapshot.title)
                    .font(.system(size: max(11.5, 10 / scale), weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if preferences.keepDetailsOpen {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(MacWidgetStyle.secondary)
                        .accessibilityLabel(L10n.text("固定中", "Kept open"))
                }
                if showsPercentage {
                    Spacer(minLength: 2)
                    Text(snapshot.percentageText)
                        .font(.system(size: max(10, 10 / scale), weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(MacWidgetStyle.secondary)
                        .fixedSize()
                        .layoutPriority(1)
                }
            }
            .foregroundStyle(accent.opacity(0.9))
            if mode.showsLiveCountdown || store.profile.dashboardValueStyle == .remaining {
                if let terminal = snapshot.countdown.terminalText {
                    Text(terminal)
                        .font(.system(size: showsBar ? max(12.5, 10 / scale) : (top ? 18 : 14.5), weight: .medium))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(countdownValue(snapshot))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .monospacedDigit()
                }
            } else {
                Text(snapshot.valueText(style: store.profile.dashboardValueStyle, compact: true))
                    .font(.system(size: top ? 23 : 21, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            if showsBar && !snapshot.isOff {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.16))
                        Capsule()
                            .fill(accent)
                            .frame(width: geometry.size.width * snapshot.elapsedFraction)
                    }
                }
                .frame(height: 3)
                .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: top ? .center : .leading)
        .foregroundStyle(MacWidgetStyle.foreground)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(snapshot.accessibilitySummary)
        .help(snapshot.accessibilitySummary)
    }

    private func countdownValue(_ snapshot: MetricSnapshot) -> AttributedString {
        var value = AttributedString()
        let top = preferences.edge == .top
        let scale = MacWidgetPlacement.clampedScale(preferences.scale)
        let showsBar = store.profile.widgetDisplayMode != .countdown
        let unitFont = Font.system(size: max(11, 10 / scale), weight: .regular)
        // A compact value is enough here; the full remaining-time phrase is
        // retained in accessibility and help text.
        for (index, component) in snapshot.countdown.components.enumerated() {
            if index > 0 { value.append(AttributedString(" ")) }
            var number = AttributedString(String(component.value))
            number.font = .system(size: showsBar ? (top ? 24 : 22) : (top ? 26 : 24), weight: .medium)
            value.append(number)
            var unit = AttributedString(component.unit)
            unit.font = unitFont
            unit.foregroundColor = MacWidgetStyle.secondary
            value.append(unit)
        }
        return value
    }
}
