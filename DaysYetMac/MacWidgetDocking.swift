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

/// Each display's geometry is frozen for a press. Only a completed edge drop is saved.
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
        guard contains(point) else { return nil }
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
        return target(on: choice.0, at: point, originalFrame: originalFrame, anchor: anchor)
    }

    func slidingTarget(at point: NSPoint, originalFrame: NSRect, anchor: NSPoint) -> MacWidgetDropTarget? {
        guard edge != .top, edge != systemDockEdge, contains(point) else { return nil }
        return target(on: edge, at: point, originalFrame: originalFrame, anchor: anchor)
    }

    private func contains(_ point: NSPoint) -> Bool {
        point.x.isFinite && point.y.isFinite && screenFrame.width > 0 && screenFrame.height > 0
            && screenFrame.insetBy(dx: -1, dy: -1).contains(point)
    }

    private func target(on candidate: MacWidgetEdge, at point: NSPoint, originalFrame: NSRect,
                        anchor: NSPoint) -> MacWidgetDropTarget {
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

    /// Match the carried ring to the destination before the surrounding rail
    /// opens. The focus includes the native ring's 0.75pt stroke on each side.
    static func attachmentCircleFrame(focus: NSRect, edge: MacWidgetEdge, scale: Double) -> NSRect {
        let center = NSPoint(x: focus.midX, y: focus.midY)
        guard edge != .top else { return circleFrame(center: center, scale: scale) }
        let size = NSSize(width: 44 * focus.width / 33.5, height: 44 * focus.height / 33.5)
        return NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                      width: size.width, height: size.height)
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
    // Give edge arrival and unfolding time to read as separate steps while
    // keeping pickup, pull-away, and pointer following responsive.
    static let attach: TimeInterval = 0.40
    static let unfold: TimeInterval = 0.56
    static let landingPause: Duration = .milliseconds(16)
    static let followResponse: TimeInterval = 0.045

    /// Recover the original smoothstep clock so mouse-up can continue an
    /// unfolding in place without restarting a full-duration ease from rest.
    static func unfoldPhase(coalescence: CGFloat) -> Double {
        let value = min(max(Double(coalescence), 0), 1)
        return 0.5 - sin(asin(min(max(2 * value - 1, -1), 1)) / 3)
    }

    static func unfoldingCoalescence(from initial: CGFloat, elapsed: TimeInterval) -> CGFloat {
        let initial = min(max(initial, 0), 1)
        let phase = min(unfoldPhase(coalescence: initial) + max(elapsed, 0) / unfold, 1)
        let coalescence = CGFloat(1 - phase * phase * (3 - 2 * phase))
        return min(max(coalescence, 0), initial)
    }
}

/// Return at a consistent speed across distances, with brief acceleration and
/// braking. Nearby destinations use a triangular velocity profile instead of
/// stretching a small movement over a fixed minimum duration.
struct MacWidgetReturnFlight {
    private static let cruiseSpeed = 1800.0
    private static let rampDuration: TimeInterval = 0.06
    private static let acceleration = cruiseSpeed / rampDuration

    let duration: TimeInterval
    private let distance: Double
    private let ramp: TimeInterval
    private let speed: Double

    init(from source: NSRect, to destination: NSRect) {
        let distance = Double(hypot(destination.midX - source.midX, destination.midY - source.midY))
        self.distance = distance.isFinite ? distance : 0
        ramp = min(Self.rampDuration, sqrt(self.distance / Self.acceleration))
        speed = Self.acceleration * ramp
        duration = speed > 0 ? self.distance / speed + ramp : 0
    }

    func progress(at elapsed: TimeInterval) -> Double {
        guard distance > 0 else { return 1 }
        guard elapsed > 0 else { return 0 }
        guard elapsed < duration else { return 1 }
        let traveled: Double
        if elapsed < ramp {
            traveled = 0.5 * Self.acceleration * elapsed * elapsed
        } else if elapsed > duration - ramp {
            let remaining = duration - elapsed
            traveled = distance - 0.5 * Self.acceleration * remaining * remaining
        } else {
            traveled = speed * (elapsed - ramp / 2)
        }
        return min(max(traveled / distance, 0), 1)
    }
}

/// Both directions use the same focus: the other parts converge on the grabbed
/// circle, and unfold from that circle only after it reaches its destination.
struct MacWidgetDragVisual: Equatable {
    var widgetFrame: NSRect
    var focusFrame: NSRect
    var circleFrame: NSRect
    var coalescence: CGFloat
    var opacity: Double = 1
    /// Once attached, reveal the final-size rail around its fixed focus instead
    /// of scaling the snapshot and crossfading a second copy of its circle.
    var attachmentEdge: MacWidgetEdge? = nil
    /// Native ring bounds in screen coordinates, used to reveal neighboring
    /// circles whole after the surface has expanded far enough to hold them.
    var attachmentRingFrames: [NSRect] = []
    /// The destination's real silhouette, independent of its fixed-size content.
    var attachmentSurface: CGPath? = nil

    var imageFrame: NSRect {
        if attachmentEdge != nil {
            return widgetFrame.offsetBy(dx: circleFrame.midX - focusFrame.midX,
                                        dy: circleFrame.midY - focusFrame.midY)
        }
        let endScale = min(circleFrame.width / max(widgetFrame.width, widgetFrame.height, 1), 1)
        let scale = 1 + (endScale - 1) * coalescence
        return NSRect(x: circleFrame.midX + (widgetFrame.minX - focusFrame.midX) * scale,
                      y: circleFrame.midY + (widgetFrame.minY - focusFrame.midY) * scale,
                      width: widgetFrame.width * scale, height: widgetFrame.height * scale)
    }

    var imageOpacity: Double { attachmentEdge == nil ? Double(1 - coalescence * coalescence) : 1 }
    var circleOpacity: Double { attachmentEdge == nil ? Double(coalescence * coalescence) : 0 }

    /// The liquid shoulders can briefly extend beyond the resting widget.
    /// Include them when freezing an interrupted attachment for pickup.
    var renderedFrame: NSRect {
        let frame = imageFrame
        guard let edge = attachmentEdge, let surface = attachmentSurface, coalescence > 0 else { return frame }
        let focus = CGRect(x: focusFrame.minX - widgetFrame.minX, y: widgetFrame.maxY - focusFrame.maxY,
                           width: focusFrame.width, height: focusFrame.height)
        let reveal = MacWidgetAttachmentReveal(edge: edge, focusFrame: focus,
            progress: 1 - coalescence, finalSurface: surface)
        let bounds = reveal.path(in: CGRect(origin: .zero, size: frame.size)).boundingRect
        let liquid = NSRect(x: frame.minX + bounds.minX, y: frame.maxY - bounds.maxY,
                            width: bounds.width, height: bounds.height)
        return frame.union(liquid).insetBy(dx: -1, dy: -1)
    }

    func interpolated(to target: Self, progress: Double, spring: Bool = false,
                      flight: MacWidgetReturnFlight? = nil) -> Self {
        let t = min(max(progress, 0), 1)
        if t >= 1 { return target }
        // Ease into the transformation as well as out of it, so collection
        // and unfolding remain visible instead of completing in the first frames.
        let eased = t * t * (3 - 2 * t)
        let travel = flight.map { $0.progress(at: t * $0.duration) }
            ?? (spring && t < 1 ? 1 - exp(-8 * t) * cos(10 * t) : eased)
        let width = circleFrame.width + (target.circleFrame.width - circleFrame.width) * eased
        let height = circleFrame.height + (target.circleFrame.height - circleFrame.height) * eased
        let x = flight == nil ? circleFrame.minX + (target.circleFrame.minX - circleFrame.minX) * travel
            : circleFrame.midX + (target.circleFrame.midX - circleFrame.midX) * travel - width / 2
        let y = flight == nil ? circleFrame.minY + (target.circleFrame.minY - circleFrame.minY) * travel
            : circleFrame.midY + (target.circleFrame.midY - circleFrame.midY) * travel - height / 2
        return Self(widgetFrame: target.widgetFrame, focusFrame: target.focusFrame,
                    circleFrame: NSRect(x: x, y: y, width: width, height: height),
                    coalescence: coalescence + (target.coalescence - coalescence) * eased,
                    opacity: opacity + (target.opacity - opacity) * eased,
                    attachmentEdge: target.attachmentEdge,
                    attachmentRingFrames: target.attachmentRingFrames,
                    attachmentSurface: target.attachmentSurface)
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

/// Grow the visible surface along its wall without transforming the snapshot's
/// rings or labels. Focus coordinates use the image's top-left origin.
struct MacWidgetAttachmentReveal: Shape {
    let edge: MacWidgetEdge
    let focusFrame: CGRect
    var progress: CGFloat
    var finalSurface: CGPath? = nil

    /// Wait until the whole ring and its antialiasing margin fit, then reveal
    /// its glyphs together instead of wiping through half a number or stroke.
    func contentOpacity(for ring: CGRect, in bounds: CGRect) -> Double {
        if abs(ring.midX - focusFrame.midX) < 0.001,
           abs(ring.midY - focusFrame.midY) < 0.001 { return 1 }
        let t = min(max(progress.isFinite ? progress : 0, 0), 1)
        guard t < 1 else { return 1 }
        if finalSurface != nil {
            // The surface briefly overshoots and recovers. Keep content on a
            // later, monotonic clock so an already exposed ring never retreats
            // behind a moving meniscus.
            let phase = CGFloat(MacWidgetDragMotion.unfoldPhase(coalescence: 1 - t))
            let delayed = min(max((phase - 0.42) / 0.56, 0), 1)
            let envelope = Self(edge: edge, focusFrame: focusFrame,
                progress: delayed * delayed * (3 - 2 * delayed))
            let opacity = envelope.contentOpacity(for: ring, in: bounds)
            guard opacity > 0 else { return 0 }
            let padded = ring.offsetBy(dx: bounds.minX, dy: bounds.minY).insetBy(dx: -1, dy: -1)
            let outline = liquidOutline(in: bounds)
            let corners = [CGPoint(x: padded.minX, y: padded.minY), CGPoint(x: padded.maxX, y: padded.minY),
                           CGPoint(x: padded.minX, y: padded.maxY), CGPoint(x: padded.maxX, y: padded.maxY)]
            return corners.allSatisfy({ outline.contains($0) }) ? opacity : 0
        }
        let padded = ring.offsetBy(dx: bounds.minX, dy: bounds.minY).insetBy(dx: -1, dy: -1)
        let corners = [CGPoint(x: padded.minX, y: padded.minY), CGPoint(x: padded.maxX, y: padded.minY),
                       CGPoint(x: padded.minX, y: padded.maxY), CGPoint(x: padded.maxX, y: padded.maxY)]
        var lower: CGFloat = 0
        var upper: CGFloat = 1
        for _ in 0..<10 {
            var candidate = self
            candidate.progress = (lower + upper) / 2
            let outline = candidate.path(in: bounds)
            if corners.allSatisfy({ outline.contains($0) }) { upper = candidate.progress }
            else { lower = candidate.progress }
        }
        let span = min(0.18, 1 - upper)
        guard span > 0 else { return 0 }
        let fade = min(max((t - upper) / span, 0), 1)
        return Double(fade * fade * (3 - 2 * fade))
    }

    func frame(in bounds: CGRect) -> CGRect {
        let t = min(max(progress.isFinite ? progress : 0, 0), 1)
        guard t < 1 else { return bounds }
        let focus = focusFrame.offsetBy(dx: bounds.minX, dy: bounds.minY)
        let padded = focus.insetBy(dx: -5.25 * focus.width / 33.5,
                                  dy: -5.25 * focus.height / 33.5)
        var seed = padded.intersection(bounds)
        guard !seed.isNull else { return .zero }
        switch edge {
        case .left:
            seed = CGRect(x: bounds.minX, y: seed.minY, width: seed.maxX - bounds.minX, height: seed.height)
        case .right:
            seed.size.width = bounds.maxX - seed.minX
        case .top:
            seed = CGRect(x: seed.minX, y: bounds.minY, width: seed.width, height: seed.maxY - bounds.minY)
        case .bottom:
            seed.size.height = bounds.maxY - seed.minY
        }
        return CGRect(x: seed.minX + (bounds.minX - seed.minX) * t,
                      y: seed.minY + (bounds.minY - seed.minY) * t,
                      width: seed.width + (bounds.width - seed.width) * t,
                      height: seed.height + (bounds.height - seed.height) * t)
    }

    func path(in rect: CGRect) -> Path {
        if let finalSurface {
            var offset = CGAffineTransform(translationX: rect.minX, y: rect.minY)
            let final = finalSurface.copy(using: &offset) ?? finalSurface
            guard progress < 1 else { return Path(final) }
            let focus = focusFrame.offsetBy(dx: rect.minX, dy: rect.minY)
            let padded = focus.insetBy(dx: -5.25 * focus.width / 33.5,
                                      dy: -5.25 * focus.height / 33.5)
            let core = edge == .top ? CGPath(rect: padded, transform: nil)
                : CGPath(ellipseIn: padded, transform: nil)
            // The held ring is solid and stationary while the surrounding
            // material stretches. Clip its support to the real final surface.
            return Path(liquidOutline(in: rect).union(core.intersection(final, using: .winding), using: .winding))
        }
        return revealPath(in: rect)
    }

    private func liquidOutline(in rect: CGRect) -> CGPath {
        guard let finalSurface else { return revealPath(in: rect).cgPath }
        let t = min(max(progress.isFinite ? progress : 0, 0), 1)
        let phase = CGFloat(MacWidgetDragMotion.unfoldPhase(coalescence: 1 - t))
        let vertical = edge == .left || edge == .right
        let focusU = vertical ? focusFrame.midY : focusFrame.midX
        let focusLength = vertical ? focusFrame.height : focusFrame.width
        let targetBounds = finalSurface.boundingBoxOfPath
        let lower = vertical ? targetBounds.minY : targetBounds.minX
        let upper = vertical ? targetBounds.maxY : targetBounds.maxX
        let depthLimit = max(vertical ? rect.width : rect.height, 1)
        let seedHalf = max(focusLength * 22 / 33.5, 1)
        let normalRadius = max((vertical ? focusFrame.width : focusFrame.height) * 22 / 33.5, 1)
        let focusDepth: CGFloat
        switch edge {
        case .left: focusDepth = focusFrame.midX
        case .right: focusDepth = rect.width - focusFrame.midX
        case .top: focusDepth = focusFrame.midY
        case .bottom: focusDepth = rect.height - focusFrame.midY
        }
        func eased(_ value: CGFloat) -> CGFloat {
            let p = min(max(value, 0), 1)
            return p * p * (3 - 2 * p)
        }
        // A broad wetting front travels along the wall. Keeping contact close
        // behind the body prevents the shoulders from stretching into horns.
        let bodyTravel = eased(phase / 0.76)
        let recoilPhase = min(max((phase - 0.45) / 0.55, 0), 1)
        let recoil = pow(sin(.pi * recoilPhase), 2)
        let bodyRecoil = 0.035 * recoil
        let contactRecoil = 0.028 * recoil
        let contactTravel = eased(phase / 0.80)
        // Arrive on a small contact patch, then wet the wall as the drop spreads.
        let contactSeedScale = 0.27 + (0.65 - 0.27) * eased(phase / 0.20)
        let energy = pow(sin(.pi * phase), 2)
        let compression = 1 - 0.035 * energy + 0.020 * sin(3 * .pi * phase) * energy
        func deform(_ point: CGPoint) -> CGPoint {
            let u = vertical ? point.y : point.x
            let depth: CGFloat
            switch edge {
            case .left: depth = point.x
            case .right: depth = rect.width - point.x
            case .top: depth = point.y
            case .bottom: depth = rect.height - point.y
            }
            let span = max(u < focusU ? focusU - lower : upper - focusU, 1)
            let seed = min(seedHalf / span, 1)
            let contactSeed = min(seedHalf * contactSeedScale / span, 1)
            let body = seed + (1 - seed) * bodyTravel + bodyRecoil
            let contact = contactSeed + (1 - contactSeed) * contactTravel + contactRecoil
            let spread = contact + (body - contact) * eased(depth / depthLimit)
            let q = abs(u - focusU) / span
            // Distribute tension over a rounded shoulder instead of a narrow
            // bulge followed by a deep notch. The core remains fixed below.
            let lobe = 0.085 * exp(-pow((q - 0.64) / 0.36, 2))
            let neck = 0.018 * exp(-pow((q - 0.26) / 0.32, 2))
            let newU = focusU + (u - focusU) * spread
            var newDepth = max(depth * (compression + (lobe - neck) * energy), 0)
            if edge != .top {
                // Start with the rounded carried drop, not a compressed rail's
                // flat back. Release the cap as the first meniscus stretches.
                let distance = (newU - focusU) / seedHalf
                let cap = focusDepth + normalRadius * sqrt(max(1 - distance * distance, 0))
                let capped = min(newDepth, cap)
                newDepth = capped + (newDepth - capped) * eased(phase / 0.20)
            }
            let local: CGPoint
            switch edge {
            case .left: local = CGPoint(x: newDepth, y: newU)
            case .right: local = CGPoint(x: rect.width - newDepth, y: newU)
            case .top: local = CGPoint(x: newU, y: newDepth)
            case .bottom: local = CGPoint(x: newU, y: rect.height - newDepth)
            }
            return CGPoint(x: local.x + rect.minX, y: local.y + rect.minY)
        }
        let result = CGMutablePath()
        var current = CGPoint.zero
        var start = CGPoint.zero
        func mix(_ a: CGPoint, _ b: CGPoint, _ p: CGFloat) -> CGPoint {
            CGPoint(x: a.x + (b.x - a.x) * p, y: a.y + (b.y - a.y) * p)
        }
        func cubic(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) {
            // Subdivide before deforming so a long straight rail can develop a
            // traveling rounded lobe and a concave neck, not a rigid rectangle.
            var points = (a, b, c, d)
            for index in 0..<12 {
                let split = 1 / CGFloat(12 - index)
                let ab = mix(points.0, points.1, split)
                let bc = mix(points.1, points.2, split)
                let cd = mix(points.2, points.3, split)
                let abc = mix(ab, bc, split)
                let bcd = mix(bc, cd, split)
                let end = mix(abc, bcd, split)
                result.addCurve(to: deform(end), control1: deform(ab), control2: deform(abc))
                points = (end, bcd, cd, points.3)
            }
            current = d
        }
        finalSurface.applyWithBlock { element in
            let points = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint:
                current = points[0]
                start = current
                result.move(to: deform(current))
            case .addLineToPoint:
                cubic(current, mix(current, points[0], 1 / 3), mix(current, points[0], 2 / 3), points[0])
            case .addQuadCurveToPoint:
                cubic(current, mix(current, points[0], 2 / 3), mix(points[1], points[0], 2 / 3), points[1])
            case .addCurveToPoint:
                cubic(current, points[0], points[1], points[2])
            case .closeSubpath:
                result.addLine(to: deform(start))
                result.closeSubpath()
                current = start
            @unknown default: break
            }
        }
        return result
    }

    private func revealPath(in rect: CGRect) -> Path {
        let visible = frame(in: rect)
        guard visible.width > 0, visible.height > 0 else { return Path() }
        if progress >= 1 { return Path(rect) }
        // A camera inset can make the top surface tall while its progress
        // strip stays thin; cap its shoulders to avoid clipping strip ends.
        let cornerHeight = edge == .top ? min(visible.height, focusFrame.height * 44 / 33.5) : visible.height
        let radius = min(visible.width, cornerHeight) / 2 * (1 - min(max(progress, 0), 1))
        // Keep wall-side corners square so the contact remains flush while
        // the rounded inward shoulders advance away from the grabbed circle.
        let topLeft = edge == .right || edge == .bottom ? radius : 0
        let topRight = edge == .left || edge == .bottom ? radius : 0
        let bottomLeft = edge == .right || edge == .top ? radius : 0
        let bottomRight = edge == .left || edge == .top ? radius : 0
        var path = Path()
        path.move(to: CGPoint(x: visible.minX + topLeft, y: visible.minY))
        path.addLine(to: CGPoint(x: visible.maxX - topRight, y: visible.minY))
        path.addQuadCurve(to: CGPoint(x: visible.maxX, y: visible.minY + topRight),
                          control: CGPoint(x: visible.maxX, y: visible.minY))
        path.addLine(to: CGPoint(x: visible.maxX, y: visible.maxY - bottomRight))
        path.addQuadCurve(to: CGPoint(x: visible.maxX - bottomRight, y: visible.maxY),
                          control: CGPoint(x: visible.maxX, y: visible.maxY))
        path.addLine(to: CGPoint(x: visible.minX + bottomLeft, y: visible.maxY))
        path.addQuadCurve(to: CGPoint(x: visible.minX, y: visible.maxY - bottomLeft),
                          control: CGPoint(x: visible.minX, y: visible.maxY))
        path.addLine(to: CGPoint(x: visible.minX, y: visible.minY + topLeft))
        path.addQuadCurve(to: CGPoint(x: visible.minX + topLeft, y: visible.minY),
                          control: CGPoint(x: visible.minX, y: visible.minY))
        path.closeSubpath()
        return path
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
    var canvasFrame: NSRect? = nil

    private var screenFrame: NSRect { canvasFrame ?? docking.screenFrame }

    private func local(_ frame: NSRect) -> CGRect {
        CGRect(x: frame.minX - screenFrame.minX, y: screenFrame.maxY - frame.maxY,
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
            if let widgetImage, visual.coalescence < 1 || visual.attachmentEdge != nil {
                let rect = local(visual.imageFrame)
                Group {
                    if let edge = visual.attachmentEdge, visual.coalescence > 0 {
                        let focus = CGRect(x: visual.focusFrame.minX - visual.widgetFrame.minX,
                                           y: visual.widgetFrame.maxY - visual.focusFrame.maxY,
                                           width: visual.focusFrame.width, height: visual.focusFrame.height)
                        let reveal = MacWidgetAttachmentReveal(edge: edge, focusFrame: focus,
                            progress: 1 - visual.coalescence, finalSurface: visual.attachmentSurface)
                        // The thin top strip can occupy a fractional image row.
                        // Preserve its native RGBA instead of replacing that
                        // antialiased edge with the vector surface's alpha.
                        let fixedTop = CGRect(x: floor(focus.minX) - 2, y: floor(focus.minY) - 2,
                            width: ceil(focus.maxX) - floor(focus.minX) + 4,
                            height: ceil(focus.maxY) - floor(focus.minY) + 4)
                        ZStack(alignment: .topLeading) {
                            if visual.attachmentSurface != nil {
                                reveal.fill(MacWidgetStyle.background)
                            }
                            ZStack(alignment: .topLeading) {
                            Image(nsImage: widgetImage).resizable().interpolation(.high)
                                .frame(width: rect.width, height: rect.height)
                            ForEach(Array(visual.attachmentRingFrames.enumerated()), id: \.offset) { _, frame in
                                let ring = CGRect(x: frame.minX - visual.widgetFrame.minX,
                                                  y: visual.widgetFrame.maxY - frame.maxY,
                                                  width: frame.width, height: frame.height)
                                if abs(ring.midX - focus.midX) >= 0.001 || abs(ring.midY - focus.midY) >= 0.001 {
                                    let cover = ring.insetBy(dx: -1, dy: -1)
                                    Rectangle().fill(MacWidgetStyle.background)
                                        .frame(width: cover.width, height: cover.height)
                                        .opacity(1 - reveal.contentOpacity(for: ring,
                                            in: CGRect(origin: .zero, size: rect.size)))
                                        .offset(x: cover.minX, y: cover.minY)
                                }
                            }
                            }
                            .frame(width: rect.width, height: rect.height, alignment: .topLeading)
                            .mask(visual.attachmentSurface == nil ? AnyShape(reveal) : AnyShape(Rectangle()))
                            .blendMode(visual.attachmentSurface == nil ? .normal : .sourceAtop)
                            if edge == .top, visual.attachmentSurface != nil {
                                Rectangle().fill(.black, style: FillStyle(antialiased: false))
                                    .frame(width: fixedTop.width, height: fixedTop.height)
                                    .offset(x: fixedTop.minX, y: fixedTop.minY)
                                    .blendMode(.destinationOut)
                            }
                        }
                        .frame(width: rect.width, height: rect.height, alignment: .topLeading)
                        .compositingGroup()
                        .overlay(alignment: .topLeading) {
                            if edge == .top, visual.attachmentSurface != nil {
                                Image(nsImage: widgetImage).resizable().interpolation(.high)
                                    .frame(width: rect.width, height: rect.height)
                                    .mask(alignment: .topLeading) {
                                        Rectangle().fill(.white, style: FillStyle(antialiased: false))
                                            .frame(width: fixedTop.width, height: fixedTop.height)
                                            .offset(x: fixedTop.minX, y: fixedTop.minY)
                                    }
                            }
                        }
                    } else {
                        Image(nsImage: widgetImage).resizable().interpolation(.high)
                            .frame(width: rect.width, height: rect.height)
                    }
                }
                .opacity(visual.imageOpacity * visual.opacity)
                .offset(x: rect.minX, y: rect.minY)
            }
            let circle = local(visual.circleFrame)
            ZStack {
                Circle().fill(MacWidgetStyle.background)
                    .shadow(color: .black.opacity(0.28), radius: 8, y: 3)
                Circle().strokeBorder(.white.opacity(0.14), lineWidth: 1)
                MacPercentageRing(fraction: snapshot.remainingFraction, accent: accent, selected: true, isOff: snapshot.isOff)
                    .scaleEffect(x: circle.width / 44, y: circle.height / 44)
            }
            .frame(width: circle.width, height: circle.height)
            .opacity((widgetImage == nil ? 1 : visual.circleOpacity) * visual.opacity)
            .offset(x: circle.minX, y: circle.minY)
            }
        }
        .frame(width: screenFrame.width, height: screenFrame.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
