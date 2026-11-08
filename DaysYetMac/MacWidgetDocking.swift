import AppKit
import SwiftUI

extension MacWidgetPlacement {
    static let dockHeight: CGFloat = 46
    static let dockCirclePadding: CGFloat = dockHeight / 2 - 16.75

    static func dockRailWidth(for metricCount: Int) -> CGFloat { railHeight(for: metricCount) }

    static func dockWidth(for metricCount: Int, detailScale: Double = 1) -> CGFloat {
        // Reserve the popup width even while closed so circles stay in place
        // throughout expansion. Transparent shoulders pass through clicks.
        max(dockRailWidth(for: metricCount), 40 + 240 * MacWidgetPreferences.clampedDetailScale(detailScale))
    }

    static func dockExpandedHeight(detailScale: Double, hoverScale: Double = 1) -> CGFloat {
        let detail = topDetailFrame(in: .zero, cameraInset: 0, scale: 1, detailScale: detailScale)
        // The circle band has equal padding above and below its ring. Only
        // reserve the extra diameter used by the configured magnification.
        return detail.maxY + dockHeight + 2 * inwardShift(for: hoverScale)
    }

    static func dockScale(in size: CGSize, scale: Double, metricCount: Int, detailScale: Double = 1) -> CGFloat {
        min(clampedScale(scale), size.width / dockWidth(for: metricCount, detailScale: detailScale), size.height / dockHeight)
    }

    static func dockExpansion(in size: CGSize, scale: Double, metricCount: Int, detailScale: Double,
                              hoverScale: Double = 1) -> CGFloat {
        let factor = dockScale(in: size, scale: scale, metricCount: metricCount, detailScale: detailScale)
        guard factor > 0 else { return 0 }
        return min(max((size.height / factor - dockHeight)
            / (dockExpandedHeight(detailScale: detailScale, hoverScale: hoverScale) - dockHeight), 0), 1)
    }

    static func dockRingFrame(in size: CGSize, index: CGFloat, scale: Double, metricCount: Int,
                              magnification: Double = 1, padding: CGFloat = 0, detailScale: Double = 1) -> CGRect {
        let factor = dockScale(in: size, scale: scale, metricCount: metricCount, detailScale: detailScale)
        let magnification = min(max(magnification, 1), 1.8)
        let centerX = (size.width - dockRailWidth(for: metricCount) * factor) / 2 + (56 + 50 * index) * factor
        let centerY = size.height - (23 + inwardShift(for: magnification)) * factor
        let radius = (16.75 * magnification + padding) * factor
        return CGRect(x: centerX - radius, y: centerY - radius, width: radius * 2, height: radius * 2)
    }

    static func dockDetailFrame(in size: CGSize, selectedIndex: CGFloat, scale: Double,
                                metricCount: Int, detailScale: Double) -> CGRect {
        let factor = dockScale(in: size, scale: scale, metricCount: metricCount, detailScale: detailScale)
        guard factor > 0 else { return .zero }
        let top = topDetailFrame(in: CGSize(width: size.width / factor, height: size.height / factor),
            cameraInset: 0, scale: 1, detailScale: detailScale)
        return CGRect(x: top.minX * factor, y: top.minY * factor,
                      width: top.width * factor, height: top.height * factor)
    }
}

extension MacWidgetSurface {
    static func dockHoverIndex(at point: CGPoint, in size: CGSize, scale: Double, metricCount: Int,
                               magnifications: [Int: CGFloat], detailScale: Double = 1) -> Int? {
        let count = MacWidgetPlacement.clampedMetricCount(metricCount)
        for index in 0..<count {
            let ring = MacWidgetPlacement.dockRingFrame(in: size, index: CGFloat(index), scale: scale,
                metricCount: count, magnification: magnifications[index] ?? 1, padding: 4, detailScale: detailScale)
            if ring.contains(point) { return index }
        }
        return nil
    }

    static func dockPath(in size: CGSize, selectedIndex: CGFloat, scale: Double, metricCount: Int,
                         detailScale: Double, magnifications: [Int: CGFloat], expansion: CGFloat?,
                         hoverScale: Double = 1) -> CGPath {
        let path = CGMutablePath()
        let factor = MacWidgetPlacement.dockScale(in: size, scale: scale, metricCount: metricCount, detailScale: detailScale)
        guard factor > 0 else { return path }
        let progress = min(max(expansion ?? MacWidgetPlacement.dockExpansion(in: size, scale: scale,
            metricCount: metricCount, detailScale: detailScale, hoverScale: hoverScale), 0), 1)
        let railWidth = MacWidgetPlacement.dockRailWidth(for: metricCount)
        let width = railWidth + (size.width / factor - railWidth) * progress
        let height = expansion == nil ? size.height / factor
            : MacWidgetPlacement.dockHeight + (size.height / factor - MacWidgetPlacement.dockHeight) * progress
        // Finish widening before the detail's bottom edge. With a compact
        // circle band, the top panel's old camera depth would clip its bar.
        let stemHeight = min(MacWidgetPlacement.dockHeight,
            MacWidgetPlacement.dockHeight - 24 + 2 * MacWidgetPlacement.inwardShift(for: hoverScale))
        // Reuse the top panel's connected shoulders and broad detail surface,
        // reflected about the screen edge. There is no floating pill or stem.
        let top = Self.path(in: CGSize(width: width, height: height), edge: .top, selectedIndex: selectedIndex,
            scale: 1, topCameraInset: 16 + (stemHeight - 16) * progress,
            topNotchWidth: railWidth - 24)
        let reflection = CGAffineTransform(a: factor, b: 0, c: 0, d: -factor,
            tx: (size.width - width * factor) / 2, ty: size.height)
        let surface = CGMutablePath()
        surface.addPath(top)
        for (index, magnification) in magnifications where magnification > 1 {
            let ring = MacWidgetPlacement.dockRingFrame(in: size, index: CGFloat(index), scale: scale,
                metricCount: metricCount, magnification: magnification, padding: 3, detailScale: detailScale)
            // Reflect every subpath together to preserve winding where the
            // enlarged circle overlaps the connected surface.
            surface.addEllipse(in: ring.applying(reflection.inverted()))
        }
        path.addPath(surface, transform: reflection)
        return path
    }
}

struct MacWidgetDropTarget: Equatable {
    let edge: MacWidgetEdge
    let position: Double
    let frame: NSRect
    var isSystemDock = false
}

/// Screen geometry is frozen for a press. Only a completed edge drop is saved.
struct MacWidgetDocking {
    let edge: MacWidgetEdge
    let screenFrame: NSRect
    let visibleFrame: NSRect
    var topInfo = MacTopNotchInfo()
    var scale: Double = 1
    var metricCount = 3
    var detailScale: Double = 1
    var systemDockEdge: MacWidgetEdge? = nil
    var sourceDockDepth: CGFloat = 0

    static let releaseDistance: CGFloat = 32
    static let snapFraction: CGFloat = 0.25
    static let attachmentDiameterMultiplier: CGFloat = 1.5
    static let attachmentReleaseGap: CGFloat = 20

    func distance(to edge: MacWidgetEdge, from point: NSPoint) -> CGFloat {
        switch edge {
        case .left: max(point.x - screenFrame.minX, 0)
        case .right: max(screenFrame.maxX - point.x, 0)
        case .top: max(screenFrame.maxY - point.y, 0)
        case .bottom: max(point.y - screenFrame.minY, 0)
        }
    }

    func target(at point: NSPoint, previous: MacWidgetEdge?, originalFrame: NSRect,
                anchor: NSPoint) -> MacWidgetDropTarget? {
        guard point.x.isFinite, point.y.isFinite,
              screenFrame.width > 0, screenFrame.height > 0,
              screenFrame.insetBy(dx: -1, dy: -1).contains(point) else { return nil }
        // Use the physical display for the zones; the Dock and menu bar only
        // affect where the widget is laid out after choosing an edge.
        let distances = MacWidgetEdge.allCases.compactMap { edge -> (MacWidgetEdge, CGFloat)? in
            let distance = distance(to: edge, from: point)
            let span = edge == .left || edge == .right ? screenFrame.width : screenFrame.height
            return distance <= span * Self.snapFraction ? (edge, distance) : nil
        }
        guard let nearest = distances.min(by: { $0.1 < $1.1 }) else { return nil }
        // At a corner, the nearer edge wins immediately. Keep history only
        // for an exact tie so it cannot override the user's closer edge.
        let choice = distances.first { $0.0 == previous && abs($0.1 - nearest.1) < 0.0001 } ?? nearest
        let candidate = choice.0
        if candidate == systemDockEdge {
            let layout = MacSystemDockGroupLayout(edge: candidate, count: metricCount, scale: scale)
            return MacWidgetDropTarget(edge: candidate, position: 0.5,
                frame: layout.frame(near: point, screen: screenFrame, visible: visibleFrame), isSystemDock: true)
        }
        let base = frame(edge: candidate, position: 0.5)
        let fraction: CGFloat
        if candidate == .bottom {
            let anchorFraction = edge == candidate ? (anchor.x - originalFrame.minX) / max(originalFrame.width, 1) : 0.5
            let travel = visibleFrame.width - base.width
            fraction = travel > 0 ? (point.x - base.width * anchorFraction - visibleFrame.minX) / travel : 0.5
        } else {
            let anchorFraction = edge == candidate ? (originalFrame.maxY - anchor.y) / max(originalFrame.height, 1) : 0.5
            let travel = visibleFrame.height - base.height
            fraction = travel > 0 ? (visibleFrame.maxY - point.y - base.height * anchorFraction) / travel : 0.5
        }
        let position = Double(min(max(fraction, 0), 1))
        return MacWidgetDropTarget(edge: candidate, position: position, frame: frame(edge: candidate, position: position))
    }

    func attachment(at point: NSPoint, target: MacWidgetDropTarget?, previous: MacWidgetEdge?) -> MacWidgetDropTarget? {
        guard let target else { return nil }
        // A slightly larger hit circle pulls the visible circle toward the
        // edge before contact. Keep the existing pull-away distance.
        let radius = MacWidgetDragGeometry.circleDiameter(scale: scale) / 2
        let reach = target.edge == previous ? radius + Self.attachmentReleaseGap
            : radius * Self.attachmentDiameterMultiplier
        // Screen-coordinate subtraction can round fractional contact points.
        // Both native Dock tiles and an ordinary rail can be inset from the
        // physical edge. Contact follows the visible landing surface, while
        // target selection above still uses the full display's quarter zones.
        let boundary = target.isSystemDock ? visibleFrame : target.frame
        let inset: CGFloat
        switch target.edge {
        case .bottom: inset = boundary.minY - screenFrame.minY
        case .left: inset = boundary.minX - screenFrame.minX
        case .right: inset = screenFrame.maxX - boundary.maxX
        case .top: inset = 0
        }
        let dockDepth = target.isSystemDock ? max(inset, sourceDockDepth) : inset
        return distance(to: target.edge, from: point) <= max(dockDepth, 0) + reach + 0.0001 ? target : nil
    }

    func frame(edge: MacWidgetEdge, position: Double) -> NSRect {
        MacWidgetPlacement.frame(in: visibleFrame, edge: edge, position: position, expanded: false,
            scale: scale, screenFrame: screenFrame, topInfo: topInfo,
            metricCount: metricCount, detailScale: detailScale)
    }
}

/// The original pressed metric, captured before hover is cleared for dragging.
struct MacWidgetDragOrigin {
    let metric: MetricKind
    let widgetFrame: NSRect
    let focusFrame: NSRect
    let pointer: NSPoint
    var isSystemDock = false
    var isNativeDock = false
}

enum MacWidgetDragGeometry {
    static func circleDiameter(scale: Double) -> CGFloat {
        40 * min(MacWidgetPlacement.clampedScale(scale), 1.15)
    }

    static func circleFrame(center: NSPoint, scale: Double) -> NSRect {
        let diameter = circleDiameter(scale: scale)
        return NSRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
    }

    /// A metric's visible ring (or top segment), in AppKit screen coordinates.
    static func focusFrame(in frame: NSRect, edge: MacWidgetEdge, index: Int, scale: Double,
                           metricCount: Int, topInfo: MacTopNotchInfo, magnification: Double = 1, detailScale: Double = 1) -> NSRect {
        let local: CGRect
        switch edge {
        case .top:
            let strip = MacWidgetSurface.topProgressFrame(in: frame.size, scale: scale,
                topCameraInset: topInfo.cameraInset, topNotchWidth: topInfo.notchWidth)
            local = CGRect(x: strip.minX + strip.width / 3 * CGFloat(min(index, 2)), y: strip.minY,
                           width: strip.width / 3, height: strip.height)
        case .bottom:
            local = MacWidgetPlacement.dockRingFrame(in: frame.size, index: CGFloat(index), scale: scale,
                metricCount: metricCount, magnification: magnification, detailScale: detailScale)
        case .left, .right:
            local = MacWidgetPlacement.sideRingFrame(in: frame.size, edge: edge, index: index, scale: scale,
                metricCount: metricCount, magnification: magnification)
        }
        return NSRect(x: frame.minX + local.minX, y: frame.maxY - local.maxY, width: local.width, height: local.height)
    }
}

enum MacWidgetDragMotion {
    static let lift: TimeInterval = 0.28
    static let collect: TimeInterval = 0.16
    static let attach: TimeInterval = 0.20
    static let travel: TimeInterval = 0.34
    static let unfold: TimeInterval = 0.28
    static let landingPause: Duration = .milliseconds(55)
    static let followResponse: TimeInterval = 0.045
}

/// Both directions use the same focus: the other parts converge on the grabbed
/// circle, and unfold from that circle only after it reaches its destination.
struct MacWidgetDragVisual: Equatable {
    var widgetFrame: NSRect
    var focusFrame: NSRect
    var circleFrame: NSRect
    var coalescence: CGFloat
    var opacity: Double = 1

    var imageFrame: NSRect {
        let endScale = min(circleFrame.width / max(widgetFrame.width, widgetFrame.height, 1), 1)
        let scale = 1 + (endScale - 1) * coalescence
        return NSRect(x: circleFrame.midX + (widgetFrame.minX - focusFrame.midX) * scale,
                      y: circleFrame.midY + (widgetFrame.minY - focusFrame.midY) * scale,
                      width: widgetFrame.width * scale, height: widgetFrame.height * scale)
    }

    var imageOpacity: Double { Double(1 - coalescence * coalescence) }
    var circleOpacity: Double { Double(coalescence * coalescence) }

    func interpolated(to target: Self, progress: Double, spring: Bool = false) -> Self {
        let t = min(max(progress, 0), 1)
        if t >= 1 { return target }
        // Ease into the transformation as well as out of it, so collection
        // and unfolding remain visible instead of completing in the first frames.
        let eased = t * t * (3 - 2 * t)
        let travel = spring && t < 1 ? 1 - exp(-8 * t) * cos(10 * t) : eased
        return Self(widgetFrame: target.widgetFrame, focusFrame: target.focusFrame,
                    circleFrame: NSRect(x: circleFrame.minX + (target.circleFrame.minX - circleFrame.minX) * travel,
                                        y: circleFrame.minY + (target.circleFrame.minY - circleFrame.minY) * travel,
                                        width: circleFrame.width + (target.circleFrame.width - circleFrame.width) * eased,
                                        height: circleFrame.height + (target.circleFrame.height - circleFrame.height) * eased),
                    coalescence: coalescence + (target.coalescence - coalescence) * eased,
                    opacity: opacity + (target.opacity - opacity) * eased)
    }

    /// A short, frame-rate-independent visual lag. Hit testing and the saved
    /// destination continue to use the actual pointer, including on mouse-up.
    func following(_ target: Self, elapsed: TimeInterval) -> Self {
        let dx = target.circleFrame.midX - circleFrame.midX
        let dy = target.circleFrame.midY - circleFrame.midY
        guard hypot(dx, dy) > 0.25 else { return target }
        let remaining = exp(-max(elapsed, 0) / MacWidgetDragMotion.followResponse)
        var result = target
        result.circleFrame = target.circleFrame.offsetBy(dx: -dx * remaining, dy: -dy * remaining)
        return result
    }
}

/// Only this noninteractive overlay moves. The original panel keeps its mouse
/// capture while hidden, so the complete rail can never follow the pointer.
struct MacWidgetDragOverlay: View {
    let docking: MacWidgetDocking
    let visual: MacWidgetDragVisual
    let widgetImage: NSImage?
    let snapshot: MetricSnapshot
    let accent: Color
    var dockLanding: MacSystemDockLandingVisual? = nil
    var dockPresentations: [MetricKind: MacSystemDockPresentation] = [:]

    private func local(_ frame: NSRect) -> CGRect {
        CGRect(x: frame.minX - docking.screenFrame.minX, y: docking.screenFrame.maxY - frame.maxY,
               width: frame.width, height: frame.height)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let dockLanding {
                ForEach(MetricKind.allCases, id: \.self) { metric in
                    if let tile = dockLanding.tiles[metric], let presentation = dockPresentations[metric] {
                        let rect = local(tile.frame)
                        MacSystemDockTileView(presentation: presentation)
                            .scaleEffect(x: rect.width / 128, y: rect.height / 128)
                            .frame(width: rect.width, height: rect.height)
                            .opacity(tile.opacity)
                            .offset(x: rect.minX, y: rect.minY)
                    }
                }
            } else {
            if let widgetImage, visual.coalescence < 1 {
                let rect = local(visual.imageFrame)
                Image(nsImage: widgetImage).resizable().interpolation(.high)
                    .frame(width: rect.width, height: rect.height)
                    .opacity(visual.imageOpacity * visual.opacity)
                    .offset(x: rect.minX, y: rect.minY)
            }
            let circle = local(visual.circleFrame)
            ZStack {
                Circle().fill(MacWidgetStyle.background)
                    .shadow(color: .black.opacity(0.28), radius: 8, y: 3)
                Circle().strokeBorder(.white.opacity(0.14), lineWidth: 1)
                MacPercentageRing(fraction: snapshot.remainingFraction, accent: accent, selected: true, isOff: snapshot.isOff)
                    .scaleEffect(circle.width / 44)
            }
            .frame(width: circle.width, height: circle.height)
            .opacity((widgetImage == nil ? 1 : visual.circleOpacity) * visual.opacity)
            .offset(x: circle.minX, y: circle.minY)
            }
        }
        .frame(width: docking.screenFrame.width, height: docking.screenFrame.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
