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
    /// Draw a closed landing preview without changing or saving preferences.
    var previewEdge: MacWidgetEdge? = nil
    var previewTopInfo: MacTopNotchInfo? = nil

    private var edge: MacWidgetEdge { previewEdge ?? preferences.edge }
    private var metrics: [MetricKind] { store.profile.macWidgetMetrics(for: edge) }
    private var notchInfo: MacTopNotchInfo { previewTopInfo ?? controller.topInfo }
    private var isExpanded: Bool { previewEdge == nil && controller.isExpanded }
    private var hoverScale: Double { previewEdge == nil ? controller.hoverScaleLimit : 1 }
    private var hoverExpansion: CGFloat? { previewEdge == nil ? controller.sideHoverExpansion : 0 }
    private var magnifications: [MetricKind: CGFloat] { previewEdge == nil ? controller.hoverMagnifications : [:] }
    private var indexedMagnifications: [Int: CGFloat] { previewEdge == nil ? controller.indexedMagnifications : [:] }

    var body: some View {
        GeometryReader { geometry in
            let scale = MacWidgetPlacement.clampedScale(preferences.scale)
            let surface = Path(MacWidgetSurface.path(
                in: geometry.size, edge: edge, selectedIndex: controller.selectionPosition,
                scale: scale, topCameraInset: notchInfo.cameraInset,
                topNotchWidth: notchInfo.notchWidth, metricCount: metrics.count,
                hoverScale: hoverScale, detailScale: preferences.detailScale,
                magnifications: indexedMagnifications, sideExpansion: hoverExpansion
            ))
            ZStack(alignment: .topLeading) {
                surface.fill(MacWidgetStyle.background)
                if edge == .top {
                    topContent(in: geometry.size, scale: scale)
                } else if edge == .bottom {
                    dockContent(in: geometry.size, scale: scale)
                } else {
                    let width = geometry.size.width / scale
                    let height = MacWidgetPlacement.railHeight(for: metrics.count)
                    let verticalScale = MacWidgetPlacement.sideVerticalScale(in: geometry.size,
                        scale: scale, metricCount: metrics.count)
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
        .onExitCommand { controller.closeDetails() }
    }

    private func dockContent(in size: CGSize, scale: Double) -> some View {
        let count = metrics.count
        let factor = MacWidgetPlacement.dockScale(in: size, scale: scale, metricCount: count, detailScale: preferences.detailScale)
        let expansion = hoverExpansion ?? MacWidgetPlacement.dockExpansion(
            in: size, scale: scale, metricCount: count, detailScale: preferences.detailScale, hoverScale: hoverScale)
        let detail = MacWidgetPlacement.dockDetailFrame(in: size, selectedIndex: controller.selectionPosition,
            scale: scale, metricCount: count, detailScale: preferences.detailScale)
        let visibleHeight = (MacWidgetPlacement.dockHeight
            + (MacWidgetPlacement.dockExpandedHeight(detailScale: preferences.detailScale, hoverScale: hoverScale)
                - MacWidgetPlacement.dockHeight) * expansion) * factor
        let largestCircle = magnifications.values.max() ?? 1
        let circleDepth = (23 + MacWidgetPlacement.inwardShift(for: largestCircle) + 16.75 * largestCircle) * factor
        let clearance = max((visibleHeight - detail.maxY - circleDepth)
            / max(MacWidgetPlacement.dockCirclePadding * factor, 0.001), 0)
        let reveal = min(max((expansion - 0.35) / 0.55, 0), clearance, 1)
        return ZStack(alignment: .topLeading) {
            detailContent(width: detail.width / max(factor * preferences.detailScale, 0.001))
                .scaleEffect(factor * preferences.detailScale, anchor: .topLeading)
                .offset(x: detail.minX, y: detail.minY + max(size.height - visibleHeight, 0))
                .opacity(reveal)
                .accessibilityHidden(!isExpanded)
            TimelineView(.periodic(from: .now, by: 60)) { context in
                ZStack(alignment: .topLeading) {
                    ForEach(Array(metrics.enumerated()), id: \.element) { index, kind in
                        let snapshot = TimeProgressCalculator.snapshot(for: kind, profile: store.profile, now: context.date)
                        let magnification = magnifications[kind] ?? 1
                        let ring = MacWidgetPlacement.dockRingFrame(in: size, index: CGFloat(index), scale: scale,
                            metricCount: count, magnification: magnification, detailScale: preferences.detailScale)
                        MacPercentageRing(fraction: snapshot.remainingFraction,
                            accent: MacWidgetStyle.accent(for: kind, theme: store.profile.widgetTheme, customColors: preferences.customColors),
                            selected: isExpanded && controller.selectedMetric == kind,
                            subdued: isExpanded && controller.selectedMetric != kind,
                            isOff: snapshot.isOff, requiresSetup: snapshot.requiresSetup)
                            .scaleEffect(factor * magnification)
                            .frame(width: ring.width, height: ring.height)
                            .position(x: ring.midX, y: ring.midY)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(snapshot.accessibilitySummary)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { controller.showSettings() }
                            .help(L10n.text("ドラッグで配置を変更・ダブルクリックで設定", "Drag to move · Double-click for settings"))
                    }
                }
                .frame(width: size.width, height: size.height, alignment: .topLeading)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func topContent(in size: CGSize, scale: Double) -> some View {
        let inset = notchInfo.cameraInset
        let closed = MacWidgetPlacement.topClosedHeight(cameraInset: inset, scale: scale)
        let expanded = MacWidgetPlacement.topExpandedHeight(cameraInset: inset, scale: scale, detailScale: preferences.detailScale)
        let progress = min(max((size.height - closed) / max(expanded - closed, 1), 0), 1)
        let reveal = min(max((progress - 0.35) / 0.55, 0), 1)
        let strip = MacWidgetSurface.topProgressFrame(in: size, scale: scale,
            topCameraInset: inset, topNotchWidth: notchInfo.notchWidth)
        let detailScale = preferences.detailScale
        let detail = MacWidgetPlacement.topDetailFrame(in: size, cameraInset: inset, scale: scale, detailScale: detailScale)
        return ZStack(alignment: .topLeading) {
            MacTopProgressBarView(store: store, preferences: preferences, controller: controller, closedPreview: previewEdge != nil)
                .frame(width: strip.width, height: strip.height)
                .offset(x: strip.minX, y: strip.minY)
            detailContent(width: detail.width / (scale * detailScale))
                .scaleEffect(scale * detailScale, anchor: .topLeading)
                .offset(x: detail.minX, y: detail.minY)
                .opacity(reveal)
                .accessibilityHidden(!isExpanded)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func sideContent(width: CGFloat, height: CGFloat) -> some View {
        let expansion = hoverExpansion ?? MacWidgetPlacement.sideExpansion(
            in: CGSize(width: width, height: height), scale: 1,
            hoverScale: hoverScale, detailScale: preferences.detailScale)
        let reveal = hoverScale > 1 ? expansion : min(max((expansion - 0.42) / 0.50, 0), 1)
        let detail = MacWidgetPlacement.sideDetailFrame(in: CGSize(width: width, height: height),
            edge: edge, selectedIndex: controller.selectionPosition, scale: 1,
            metricCount: metrics.count, hoverScale: hoverScale, detailScale: preferences.detailScale)
        let contentProgress = hoverScale > 1 ? expansion : 1
        // Grow the complete text and its padding with the surface so neither
        // edge reveals clipped fragments before the circle finishes growing.
        let inset = (14 + MacWidgetPlacement.hoverOutset(for: hoverScale)) * (1 - contentProgress)
        let detailX = edge == .right
            ? detail.maxX + inset - detail.width * contentProgress
            : detail.minX - inset
        return ZStack(alignment: .topLeading) {
            detailContent(width: detail.width / preferences.detailScale)
                .scaleEffect(preferences.detailScale * contentProgress, anchor: .topLeading)
                .offset(x: detailX, y: detail.midY - detail.height * contentProgress / 2)
                .opacity(reveal)
                .accessibilityHidden(!isExpanded)
            MacTimeRailView(store: store, preferences: preferences, controller: controller, previewEdge: previewEdge)
                .frame(width: 46, height: height)
                .offset(x: edge == .right ? width - 46 : 0)
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
    var closedPreview = false

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.periodic(from: .now, by: 60)) { context in
                HStack(spacing: 0) {
                    ForEach(store.profile.macWidgetMetrics(for: .top)) { kind in
                        let snapshot = TimeProgressCalculator.snapshot(for: kind, profile: store.profile, now: context.date)
                        let selected = !closedPreview && controller.isExpanded && controller.selectedMetric == kind
                        let width = max(geometry.size.width / 3 - 4, 0)
                        let thickness = min(2 * MacWidgetPlacement.clampedScale(preferences.scale), geometry.size.height)
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.16))
                            if snapshot.remainingFraction > 0 {
                                Capsule()
                                    .fill(MacWidgetStyle.accent(for: kind, theme: store.profile.widgetTheme,
                                        customColors: preferences.customColors)
                                        .opacity(selected ? 1 : 0.86))
                                    .frame(width: width * snapshot.remainingFraction)
                            }
                        }
                        .frame(width: width, height: thickness)
                        .frame(width: geometry.size.width / 3, height: geometry.size.height)
                        .contentShape(Rectangle())
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(snapshot.accessibilitySummary)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { controller.showSettings() }
                        .accessibilityHint(L10n.text("ダブルクリックで設定を開きます", "Double-click to open settings"))
                        .help(L10n.text("ドラッグで配置を変更・ダブルクリックで設定", "Drag to move · Double-click for settings"))
                    }
                }
            }
        }
    }
}

struct MacPercentageRing: View {
    /// The unconsumed portion, from 1 at the start to 0 at the target.
    let fraction: Double
    let accent: Color
    var selected = false
    var subdued = false
    var isOff = false
    var requiresSetup = false

    var body: some View {
        ZStack {
            ZStack {
                Circle().stroke(.white.opacity(0.10), lineWidth: 1.5)
                if fraction > 0 {
                    Circle()
                        .trim(from: 1 - fraction, to: 1)
                        .stroke(accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
            }
            .opacity(selected ? 1 : (subdued ? 0.68 : 0.80))
            HStack(alignment: .firstTextBaseline, spacing: 0.5) {
                if requiresSetup {
                    Text("—")
                        .font(.system(size: 10, weight: .medium))
                } else if isOff {
                    Text("Off")
                        .font(.system(size: 9, weight: .medium))
                } else {
                    Text(RemainingPercentage.compactNumber(for: fraction))
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
    var previewEdge: MacWidgetEdge? = nil

    private var edge: MacWidgetEdge { previewEdge ?? preferences.edge }
    private var metrics: [MetricKind] { store.profile.macWidgetMetrics(for: edge) }
    private var isExpanded: Bool { previewEdge == nil && controller.isExpanded }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(spacing: 0) {
                ForEach(metrics) { kind in
                    railMetric(TimeProgressCalculator.snapshot(for: kind, profile: store.profile, now: context.date))
                }
            }
            .padding(.vertical, 31)
        }
    }

    private func railMetric(_ snapshot: MetricSnapshot) -> some View {
        let selected = isExpanded && controller.selectedMetric == snapshot.kind
        let magnification = previewEdge == nil ? controller.hoverMagnifications[snapshot.kind] ?? 1 : 1
        let shift = MacWidgetPlacement.inwardShift(for: magnification) * (edge == .right ? -1 : 1)
        let accent = MacWidgetStyle.accent(for: snapshot.kind, theme: store.profile.widgetTheme,
                                          customColors: preferences.customColors)
        return MacPercentageRing(fraction: snapshot.remainingFraction, accent: accent,
                                 selected: selected, subdued: isExpanded && !selected,
                                 isOff: snapshot.isOff, requiresSetup: snapshot.requiresSetup)
        .scaleEffect(magnification)
        .offset(x: shift)
        // Keep the target fixed while the ring grows, so adjacent rows do not
        // shift or repeatedly enter and exit hover during the animation.
        .frame(width: 46, height: 50)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(snapshot.accessibilitySummary)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { controller.showSettings() }
        .accessibilityHint(L10n.text("ダブルクリックで設定を開きます", "Double-click to open settings"))
        .help(L10n.text("ドラッグで配置を変更・ダブルクリックで設定", "Drag to move · Double-click for settings"))
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
        let top = preferences.edge == .top || preferences.edge == .bottom
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
                        if snapshot.remainingFraction > 0 {
                            Capsule()
                                .fill(accent)
                                .frame(width: geometry.size.width * snapshot.remainingFraction)
                        }
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
        let top = preferences.edge == .top || preferences.edge == .bottom
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
