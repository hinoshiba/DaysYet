import AppKit
import SwiftUI

/// Read the space reserved by macOS, without changing Dock preferences or
/// requiring Accessibility access. A Dock click also locates an auto-hidden Dock.
enum MacSystemDockLocation {
    static func configuredEdge(orientation: String?) -> MacWidgetEdge? {
        guard let orientation, let edge = MacWidgetEdge(rawValue: orientation), edge != .top else { return nil }
        return edge
    }

    static func reservedEdge(screen: NSRect, visible: NSRect) -> MacWidgetEdge? {
        let insets: [(MacWidgetEdge, CGFloat)] = [
            (.left, visible.minX - screen.minX),
            (.right, screen.maxX - visible.maxX),
            (.bottom, visible.minY - screen.minY)
        ]
        return insets.filter { $0.1 > 2 }.max { $0.1 < $1.1 }?.0
    }

    static func clickedEdge(at point: NSPoint, screen: NSRect) -> MacWidgetEdge {
        let distances: [(MacWidgetEdge, CGFloat)] = [
            (.left, abs(point.x - screen.minX)),
            (.right, abs(screen.maxX - point.x)),
            (.bottom, abs(point.y - screen.minY))
        ]
        return distances.min { $0.1 < $1.1 }?.0 ?? .bottom
    }

    @MainActor
    static func resolve(on screen: NSScreen, dockClick: NSPoint? = nil,
                        fallback: MacWidgetEdge = .bottom) -> MacWidgetEdge {
        if let edge = reservedEdge(screen: screen.frame, visible: screen.visibleFrame) { return edge }
        if let dockClick { return clickedEdge(at: dockClick, screen: screen.frame) }
        for other in NSScreen.screens {
            if let edge = reservedEdge(screen: other.frame, visible: other.visibleFrame) { return edge }
        }
        // Auto-hidden Docks reserve no screen space. Read only their orientation
        // when macOS makes it available; keep observed geometry as the fallback.
        let orientation = CFPreferencesCopyAppValue("orientation" as CFString, "com.apple.dock" as CFString) as? String
        if let edge = configuredEdge(orientation: orientation) { return edge }
        return fallback
    }
}

/// One shared layout drives the expanded group, its drag image and hit testing.
struct MacSystemDockGroupLayout {
    let edge: MacWidgetEdge
    let count: Int
    var scale: Double = 1

    var factor: CGFloat { min(MacWidgetPlacement.clampedScale(scale), 1.15) }
    var isVertical: Bool { edge == .left || edge == .right }
    var size: NSSize {
        let length = CGFloat(MacWidgetPlacement.clampedMetricCount(count)) * 72
        return isVertical ? NSSize(width: 96 * factor, height: (length + 40) * factor)
            : NSSize(width: (length + 24) * factor, height: 100 * factor)
    }

    /// SwiftUI coordinates, measured from the top left.
    func ring(at index: Int) -> NSRect {
        NSRect(x: (isVertical ? 24 : 24 + 72 * CGFloat(index)) * factor,
               y: (isVertical ? 12 + 72 * CGFloat(index) : 12) * factor,
               width: 48 * factor, height: 48 * factor)
    }

    func index(at point: NSPoint) -> Int? {
        (0..<MacWidgetPlacement.clampedMetricCount(count)).first {
            let ring = ring(at: $0)
            return NSRect(x: ring.minX - 10 * factor, y: ring.minY - 6 * factor,
                          width: ring.width + 20 * factor, height: ring.height + 24 * factor).contains(point)
        }
    }

    func focus(in frame: NSRect, index: Int) -> NSRect {
        let ring = ring(at: index)
        return NSRect(x: frame.minX + ring.minX, y: frame.maxY - ring.maxY,
                      width: ring.width, height: ring.height)
    }

    func frame(near point: NSPoint, screen: NSRect, visible: NSRect) -> NSRect {
        let size = size
        var origin: NSPoint
        switch edge {
        case .left:
            origin = NSPoint(x: max(visible.minX + 8, screen.minX + 88), y: point.y - size.height / 2)
        case .right:
            origin = NSPoint(x: min(visible.maxX - 8, screen.maxX - 88) - size.width, y: point.y - size.height / 2)
        case .bottom, .top:
            origin = NSPoint(x: point.x - size.width / 2, y: max(visible.minY + 8, screen.minY + 88))
        }
        origin.x = min(max(origin.x, visible.minX + 8), max(visible.minX + 8, visible.maxX - size.width - 8))
        origin.y = min(max(origin.y, visible.minY + 8), max(visible.minY + 8, visible.maxY - size.height - 8))
        return NSRect(origin: origin, size: size)
    }

    func dockPoint(from frame: NSRect, screen: NSRect) -> NSPoint {
        switch edge {
        case .left: NSPoint(x: screen.minX + 28, y: frame.midY)
        case .right: NSPoint(x: screen.maxX - 28, y: frame.midY)
        case .bottom, .top: NSPoint(x: frame.midX, y: screen.minY + 28)
        }
    }
}

struct MacSystemDockGroupView: View {
    @ObservedObject var store: ProfileStore
    @ObservedObject var preferences: MacWidgetPreferences
    let edge: MacWidgetEdge
    var landing = false
    var openSettings: () -> Void = {}
    var returnToEdge: () -> Void = {}

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let metrics = store.profile.macDashboardMetrics
            let layout = MacSystemDockGroupLayout(edge: edge, count: metrics.count, scale: preferences.scale)
            ZStack(alignment: .topLeading) {
                if !landing {
                    RoundedRectangle(cornerRadius: 22 * layout.factor)
                        .fill(Color(red: 0.12, green: 0.13, blue: 0.15).opacity(0.97))
                        .overlay(RoundedRectangle(cornerRadius: 22 * layout.factor).strokeBorder(.white.opacity(0.15)))
                }
                ForEach(Array(metrics.enumerated()), id: \.element) { index, kind in
                    let snapshot = TimeProgressCalculator.snapshot(for: kind, profile: store.profile, now: context.date)
                    let ring = layout.ring(at: index)
                    if landing {
                        MacSystemDockTileView(presentation: MacSystemDockPresentation(snapshot: snapshot,
                            accent: MacWidgetStyle.accent(for: kind, theme: store.profile.widgetTheme,
                                                         customColors: preferences.customColors)))
                            .scaleEffect(ring.width / 128)
                            .frame(width: ring.width, height: ring.height)
                            .offset(x: ring.minX, y: ring.minY)
                    } else {
                        VStack(spacing: 5 * layout.factor) {
                            ZStack {
                                Circle().fill(.black.opacity(0.78))
                                MacPercentageRing(fraction: snapshot.remainingFraction,
                                    accent: MacWidgetStyle.accent(for: kind, theme: store.profile.widgetTheme,
                                                                 customColors: preferences.customColors),
                                    selected: true, isOff: snapshot.isOff)
                                    .scaleEffect(1.2 * layout.factor)
                            }
                            .frame(width: ring.width, height: ring.height)
                            Text(kind.shortTitle)
                                .font(.system(size: 10 * layout.factor, weight: .medium))
                                .foregroundStyle(.white.opacity(0.75))
                                .lineLimit(1)
                        }
                        .frame(width: 68 * layout.factor)
                        .offset(x: ring.midX - 34 * layout.factor, y: ring.minY)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(snapshot.accessibilitySummary)
                        .accessibilityHint(L10n.text("ドラッグしてグループを移動", "Drag to move the group"))
                    }
                }
                if !landing {
                    Text(L10n.text("つかんで移動", "Drag to move"))
                        .font(.system(size: 10 * layout.factor))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(width: layout.size.width, height: 18 * layout.factor)
                        .offset(y: layout.size.height - 24 * layout.factor)
                }
            }
            .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
            .contextMenu {
                Button(L10n.text("DaysYetの設定…", "DaysYet Settings…"), action: openSettings)
                Button(L10n.text("画面の端に戻す", "Return to screen edge"), action: returnToEdge)
            }
        }
    }
}
