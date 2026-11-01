import AppKit

struct MacSystemDockLandingTile: Equatable {
    var frame: NSRect
    var opacity: Double = 1
}

/// Keep each circle independent during the handoff to real Dock slots. A row
/// that is already open must never merge into a single circle on mouse-up.
struct MacSystemDockLandingVisual: Equatable {
    var tiles: [MetricKind: MacSystemDockLandingTile]

    static func start(metrics: [MetricKind], grabbed: MetricKind, visual: MacWidgetDragVisual,
                      layout: MacSystemDockGroupLayout, isOpenPreview: Bool) -> Self {
        Self(tiles: Dictionary(uniqueKeysWithValues: metrics.enumerated().map { index, metric in
            let frame = isOpenPreview ? layout.focus(in: visual.widgetFrame, index: index) : visual.circleFrame
            return (metric, MacSystemDockLandingTile(frame: frame,
                opacity: isOpenPreview || metric == grabbed ? 1 : 0))
        }))
    }

    func interpolated(to target: Self, progress: Double) -> Self {
        let t = min(max(progress, 0), 1)
        if t == 1 { return target }
        let eased = 1 - pow(1 - t, 3)
        return Self(tiles: target.tiles.reduce(into: [:]) { result, pair in
            let (metric, end) = pair
            let start = tiles[metric] ?? MacSystemDockLandingTile(frame: end.frame, opacity: 0)
            result[metric] = MacSystemDockLandingTile(frame: NSRect(
                x: start.frame.minX + (end.frame.minX - start.frame.minX) * eased,
                y: start.frame.minY + (end.frame.minY - start.frame.minY) * eased,
                width: start.frame.width + (end.frame.width - start.frame.width) * eased,
                height: start.frame.height + (end.frame.height - start.frame.height) * eased),
                opacity: start.opacity + (end.opacity - start.opacity) * eased)
        })
    }

    static func destination(metrics: [MetricKind], nativeFrames: [MetricKind: NSRect],
                            target: MacWidgetDropTarget, docking: MacWidgetDocking) -> Self {
        let layout = MacSystemDockGroupLayout(edge: target.edge, count: metrics.count, scale: docking.scale)
        let dockPoint = layout.dockPoint(from: target.frame, screen: docking.screenFrame)
        return Self(tiles: Dictionary(uniqueKeysWithValues: metrics.enumerated().map { index, metric in
            var frame = layout.focus(in: target.frame, index: index)
            if let native = nativeFrames[metric] {
                frame = native
            } else if target.edge == .bottom {
                frame.origin.y = dockPoint.y - frame.height / 2
            } else {
                frame.origin.x = dockPoint.x - frame.width / 2
            }
            return (metric, MacSystemDockLandingTile(frame: frame))
        }))
    }
}
