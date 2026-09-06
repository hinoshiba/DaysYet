import AppKit
import Combine

enum MacWidgetEdge: String, CaseIterable, Identifiable {
    case left, right, top
    var id: String { rawValue }
    var title: String {
        switch self {
        case .left: L10n.text("左", "Left")
        case .right: L10n.text("右", "Right")
        case .top: L10n.text("上・カメラ", "Top / camera")
        }
    }
}

struct MacDisplay: Identifiable {
    let id: String
    let name: String
}

@MainActor
final class MacWidgetPreferences: ObservableObject {
    @Published var isVisible: Bool { didSet { defaults.set(isVisible, forKey: Key.visible) } }
    @Published var edge: MacWidgetEdge { didSet { defaults.set(edge.rawValue, forKey: Key.edge) } }
    /// A proportion of the available travel: zero is the top, one the bottom.
    @Published var verticalPosition: Double { didSet { defaults.set(verticalPosition, forKey: Key.position) } }
    @Published var displayID: String { didSet { defaults.set(displayID, forKey: Key.display) } }
    @Published var keepDetailsOpen: Bool { didSet { defaults.set(keepDetailsOpen, forKey: Key.details) } }
    @Published var scale: Double { didSet { defaults.set(scale, forKey: Key.scale) } }

    private let defaults: UserDefaults
    private enum Key {
        static let visible = "mac-widget-visible"
        static let edge = "mac-widget-edge"
        static let position = "mac-widget-position"
        static let display = "mac-widget-display"
        static let details = "mac-widget-keep-details"
        static let scale = "mac-widget-scale"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isVisible = defaults.object(forKey: Key.visible) as? Bool ?? true
        edge = MacWidgetEdge(rawValue: defaults.string(forKey: Key.edge) ?? "") ?? .right
        let position = defaults.object(forKey: Key.position) as? Double ?? 0.5
        verticalPosition = position.isFinite ? min(max(position, 0), 1) : 0.5
        displayID = defaults.string(forKey: Key.display) ?? ""
        keepDetailsOpen = defaults.bool(forKey: Key.details)
        scale = MacWidgetPlacement.clampedScale(defaults.object(forKey: Key.scale) as? Double ?? 1)
    }

    func reset() {
        isVisible = true
        edge = .right
        verticalPosition = 0.5
        displayID = ""
        keepDetailsOpen = false
        scale = 1
        [Key.visible, Key.edge, Key.position, Key.display, Key.details, Key.scale].forEach(defaults.removeObject(forKey:))
    }
}

/// Camera measurements use physical screen points, independently of widget scale.
struct MacTopNotchInfo: Equatable {
    var cameraInset: CGFloat = 0
    var notchWidth: CGFloat = 0
    var centerX: CGFloat = 0

    static func resolve(screenFrame: NSRect, topInset: CGFloat, leftArea: NSRect, rightArea: NSRect) -> Self {
        let inset = topInset.isFinite ? min(max(topInset, 0), screenFrame.height) : 0
        var result = Self(cameraInset: inset, centerX: screenFrame.midX)
        let left = leftArea.intersection(screenFrame)
        let right = rightArea.intersection(screenFrame)
        if inset > 0, !left.isNull, !right.isNull, left.width > 0, right.width > 0,
           right.minX > left.maxX {
            result.notchWidth = right.minX - left.maxX
            result.centerX = (right.minX + left.maxX) / 2
        }
        return result
    }
}

/// Side placement respects the Dock; top placement attaches to the physical edge.
enum MacWidgetPlacement {
    static let railSize = NSSize(width: 46, height: 212)
    static let detailSize = NSSize(width: 124, height: 52)
    static let expandedSize = NSSize(width: 204, height: 212)
    static let ringCenters: [CGFloat] = [56, 106, 156]

    static func clampedScale(_ scale: Double) -> Double {
        scale.isFinite ? min(max(scale, 0.8), 1.5) : 1
    }

    static func topClosedHeight(cameraInset: CGFloat, scale: Double = 1) -> CGFloat {
        let inset = cameraInset.isFinite ? max(cameraInset, 0) : 0
        return inset + 8 * clampedScale(scale)
    }

    static func topExpandedHeight(cameraInset: CGFloat, scale: Double) -> CGFloat {
        let inset = cameraInset.isFinite ? max(cameraInset, 0) : 0
        return inset + 74 * clampedScale(scale)
    }

    /// Physical coordinates keep the complete header and value below the
    /// widening shoulders, with room above the rounded bottom of the surface.
    static func topDetailFrame(in size: CGSize, cameraInset: CGFloat, scale: Double) -> CGRect {
        let factor = clampedScale(scale)
        let inset = cameraInset.isFinite ? max(cameraInset, 0) : 0
        let width = min(max(size.width - 40 * factor, 0), 240 * factor)
        return CGRect(x: (size.width - width) / 2, y: inset + 16 * factor,
                      width: width, height: 52 * factor)
    }

    static func sideDetailFrame(in size: CGSize, edge: MacWidgetEdge, selectedIndex: CGFloat, scale: Double) -> CGRect {
        let factor = clampedScale(scale)
        let index = selectedIndex.isFinite ? min(max(selectedIndex, 0), 2) : 0
        return CGRect(x: edge == .right ? size.width - 184 * factor : 60 * factor,
                      y: (30 + 50 * index) * factor, width: 124 * factor, height: 52 * factor)
    }

    static func railFrame(in visibleFrame: NSRect, edge: MacWidgetEdge, position: Double) -> NSRect {
        frame(in: visibleFrame, edge: edge, position: position, expanded: false)
    }

    static func frame(in visibleFrame: NSRect, edge: MacWidgetEdge, position: Double, expanded: Bool,
                      scale: Double = 1, screenFrame: NSRect? = nil, topInfo: MacTopNotchInfo? = nil) -> NSRect {
        let factor = clampedScale(scale)
        if edge == .top {
            let screen = screenFrame ?? visibleFrame
            let info = topInfo ?? MacTopNotchInfo(centerX: screen.midX)
            let cameraInset = info.cameraInset.isFinite ? min(max(info.cameraInset, 0), screen.height) : 0
            let notchWidth = info.notchWidth.isFinite ? min(max(info.notchWidth, 0), screen.width) : 0
            let center = info.centerX.isFinite ? info.centerX : screen.midX
            let idleWidth = max(174 * factor, notchWidth + 24 * factor)
            let width = min(expanded ? max(280 * factor, idleWidth) : idleWidth, screen.width)
            let height = min(expanded ? topExpandedHeight(cameraInset: cameraInset, scale: factor)
                                     : topClosedHeight(cameraInset: cameraInset, scale: factor), screen.height)
            return NSRect(x: min(max(center - width / 2, screen.minX), screen.maxX - width),
                          y: screen.maxY - height, width: width, height: height)
        }
        let fraction = position.isFinite ? min(max(position, 0), 1) : 0.5
        let size = expanded ? expandedSize : railSize
        let height = min(size.height * factor, visibleFrame.height)
        let width = min(size.width * factor, visibleFrame.width)
        return NSRect(
            x: edge == .right ? visibleFrame.maxX - width : visibleFrame.minX,
            y: visibleFrame.maxY - height - (visibleFrame.height - height) * fraction,
            width: width,
            height: height
        )
    }

}

/// One contour drives rendering and pointer acceptance. Coordinates start at the
/// window's top left, matching SwiftUI rather than AppKit's bottom-left origin.
enum MacWidgetSurface {
    /// The physical camera remains a hover target for the current metric when
    /// the pointer is outside the enlarged segment targets just above the bars.
    static func topCameraHoverFrame(in size: CGSize, scale: Double, topCameraInset: CGFloat,
                                    topNotchWidth: CGFloat) -> CGRect {
        guard topCameraInset.isFinite, topCameraInset > 0,
              size.width.isFinite, size.width > 0, size.height.isFinite, size.height > 0 else { return .null }
        let factor = MacWidgetPlacement.clampedScale(scale)
        let knownWidth = topNotchWidth.isFinite ? max(topNotchWidth, 0) : 0
        let capWidth = min(size.width, 174 * factor)
        let shoulder = min(12 * factor, size.width / 5, capWidth / 4)
        let width = knownWidth > 0 ? min(knownWidth, size.width) : max(capWidth - 2 * shoulder, 0)
        return CGRect(x: (size.width - width) / 2, y: 0, width: width, height: min(topCameraInset, size.height))
    }

    /// The scaled progress band stays below the physical camera as details open.
    static func topProgressFrame(in size: CGSize, scale: Double, topCameraInset: CGFloat,
                                 topNotchWidth: CGFloat) -> CGRect {
        let factor = MacWidgetPlacement.clampedScale(scale)
        let inset = topCameraInset.isFinite ? max(topCameraInset, 0) : 0
        let notchWidth = topNotchWidth.isFinite ? max(topNotchWidth, 0) : 0
        let idleWidth = max(174 * factor, notchWidth + 24 * factor)
        let availableWidth = max(min(size.width, idleWidth) - 40 * factor, 0)
        let width = min(notchWidth > 0 ? max(notchWidth - 24, 0) : 150 * factor, availableWidth)
        return CGRect(x: (size.width - width) / 2, y: inset, width: width, height: 8 * factor)
    }

    /// The bottom of the camera area also selects the segment directly below
    /// it. A closed widget additionally opens from just beneath the thin band.
    /// These hover margins do not enlarge the surface that accepts clicks.
    static func topHoverIndex(at point: CGPoint, in size: CGSize, scale: Double,
                              topCameraInset: CGFloat, topNotchWidth: CGFloat, proximity: Bool) -> Int? {
        var region = topProgressFrame(in: size, scale: scale, topCameraInset: topCameraInset,
                                      topNotchWidth: topNotchWidth)
        let reachAbove = min(region.minY, 16)
        region.origin.y -= reachAbove
        region.size.height += reachAbove
        if proximity {
            region.size.height += 8
        }
        guard region.width > 0, region.height > 0, region.contains(point) else { return nil }
        return min(Int((point.x - region.minX) / region.width * 3), 2)
    }

    static func path(in size: CGSize, edge: MacWidgetEdge, selectedIndex: CGFloat, scale: Double,
                     topCameraInset: CGFloat = 0, topNotchWidth: CGFloat = 0) -> CGPath {
        let path = CGMutablePath()
        guard size.width > 0, size.height > 0 else { return path }
        let factor = MacWidgetPlacement.clampedScale(scale)
        if edge == .top {
            let inset = topCameraInset.isFinite ? min(max(topCameraInset, 0), size.height) : 0
            let notchWidth = topNotchWidth.isFinite ? max(topNotchWidth, 0) : 0
            let capWidth = min(size.width, max(174 * factor, notchWidth + 24 * factor))
            // The camera stem stays identical in the thin and expanded states.
            let shoulder = min(12 * factor, size.width / 5, capWidth / 4)
            let bottomRadius = min(18 * factor, (size.height - inset) / 2, (size.width - 2 * shoulder) / 2)
            let stemLeft = (size.width - capWidth) / 2
            let stemRight = stemLeft + capWidth
            let transition = min(24 * factor, (size.height - inset) / 2)
            path.move(to: CGPoint(x: stemLeft, y: 0))
            path.addLine(to: CGPoint(x: stemRight, y: 0))
            path.addCurve(to: CGPoint(x: stemRight - shoulder, y: inset),
                          control1: CGPoint(x: stemRight - shoulder, y: 0),
                          control2: CGPoint(x: stemRight - shoulder, y: inset / 2))
            path.addCurve(to: CGPoint(x: size.width - shoulder, y: inset + transition),
                          control1: CGPoint(x: stemRight - shoulder, y: inset + transition * 0.7),
                          control2: CGPoint(x: size.width - shoulder, y: inset + transition * 0.1))
            path.addLine(to: CGPoint(x: size.width - shoulder, y: size.height - bottomRadius))
            path.addQuadCurve(to: CGPoint(x: size.width - shoulder - bottomRadius, y: size.height),
                              control: CGPoint(x: size.width - shoulder, y: size.height))
            path.addLine(to: CGPoint(x: shoulder + bottomRadius, y: size.height))
            path.addQuadCurve(to: CGPoint(x: shoulder, y: size.height - bottomRadius),
                              control: CGPoint(x: shoulder, y: size.height))
            path.addLine(to: CGPoint(x: shoulder, y: inset + transition))
            path.addCurve(to: CGPoint(x: stemLeft + shoulder, y: inset),
                          control1: CGPoint(x: shoulder, y: inset + transition * 0.1),
                          control2: CGPoint(x: stemLeft + shoulder, y: inset + transition * 0.7))
            path.addCurve(to: CGPoint(x: stemLeft, y: 0),
                          control1: CGPoint(x: stemLeft + shoulder, y: inset / 2),
                          control2: CGPoint(x: stemLeft + shoulder, y: 0))
            path.closeSubpath()
            return path
        }
        let w = size.width / factor
        let h = size.height / factor
        let base = min(MacWidgetPlacement.railSize.width, w)
        let extensionWidth = max(w - base, 0)
        let expansion = min(extensionWidth / 158, 1)
        let shoulder = min(29, h / 5)
        let neck = max(base - 29, base * 0.37)
        func point(_ depth: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: depth, y: y) }
        func anchored(_ point: CGPoint) -> CGPoint {
            CGPoint(x: (edge == .right ? w - point.x : point.x) * factor, y: point.y * factor)
        }
        let rail = [
            SideCurve(point(0, 0), point(0, shoulder * 0.52), point(min(12, base), shoulder * 0.64), point(base - neck, shoulder * 0.64)),
            SideCurve(point(max(base - 17, 0), shoulder * 0.64), point(max(base - 4, 0), shoulder * 0.64), point(base, shoulder * 0.93), point(base, shoulder * 1.4)),
            SideCurve(point(base, shoulder * 1.4), point(base, h / 2), point(base, h / 2), point(base, h - shoulder * 1.4)),
            SideCurve(point(base, h - shoulder * 1.4), point(base, h - shoulder * 0.93), point(max(base - 4, 0), h - shoulder * 0.64), point(max(base - 17, 0), h - shoulder * 0.64)),
            SideCurve(point(base - neck, h - shoulder * 0.64), point(min(12, base), h - shoulder * 0.64), point(0, h - shoulder * 0.52), point(0, h))
        ]
        func railPosition(at y: CGFloat) -> (point: CGPoint, tangent: CGPoint) {
            let curve = rail.first(where: { $0.end.y >= y }) ?? rail[rail.count - 1]
            return curve.position(at: curve.parameter(atY: y))
        }
        func appendRail(from lower: CGFloat, through upper: CGFloat) {
            for curve in rail where curve.end.y > lower && curve.start.y < upper {
                let lowerT = curve.parameter(atY: max(lower, curve.start.y))
                let upperT = curve.parameter(atY: min(upper, curve.end.y))
                let segment = curve.portion(from: lowerT, through: upperT)
                path.addLine(to: anchored(segment.start))
                path.addCurve(to: anchored(segment.end), control1: anchored(segment.control1), control2: anchored(segment.control2))
            }
        }
        path.move(to: anchored(point(0, 0)))
        if extensionWidth > 0 {
            let index = selectedIndex.isFinite ? min(max(selectedIndex, 0), 2) : 0
            let center = 56 + 50 * index
            let verticalFactor = h / 212
            func bodyY(_ y: CGFloat) -> CGFloat { y * verticalFactor }
            let top = center - 40 * expansion
            let bottom = center + 40 * expansion
            let join = 14 * expansion
            let corner = 26 * expansion
            let topCut = bodyY(top - join)
            let bottomCut = bodyY(bottom + join)
            let upper = railPosition(at: topCut)
            let lower = railPosition(at: bottomCut)
            let upperDepth = railPosition(at: bodyY(top)).point.x + join
            let lowerDepth = railPosition(at: bodyY(bottom)).point.x + join

            // Split the original rail at each join. Every segment then travels
            // downward, even when the selected row overlaps an end shoulder.
            appendRail(from: 0, through: topCut)
            let upperControl2 = point(upperDepth - 9 * expansion, bodyY(top))
            let upperControl1 = SideCurve.tangentControl(from: upper.point, direction: upper.tangent,
                length: 9 * expansion * min(verticalFactor, 1), maxHorizontal: upperControl2.x - upper.point.x)
            path.addCurve(to: anchored(point(upperDepth, bodyY(top))),
                          control1: anchored(upperControl1), control2: anchored(upperControl2))
            path.addLine(to: anchored(point(w - corner, bodyY(top))))
            path.addCurve(to: anchored(point(w, bodyY(top + corner))),
                          control1: anchored(point(w - 9 * expansion, bodyY(top))),
                          control2: anchored(point(w, bodyY(top + 9 * expansion))))
            path.addLine(to: anchored(point(w, bodyY(bottom - corner))))
            path.addCurve(to: anchored(point(w - corner, bodyY(bottom))),
                          control1: anchored(point(w, bodyY(bottom - 9 * expansion))),
                          control2: anchored(point(w - 9 * expansion, bodyY(bottom))))
            path.addLine(to: anchored(point(lowerDepth, bodyY(bottom))))
            let lowerControl1 = point(lowerDepth - 9 * expansion, bodyY(bottom))
            let lowerControl2 = SideCurve.tangentControl(from: lower.point,
                direction: point(-lower.tangent.x, -lower.tangent.y),
                length: 9 * expansion * min(verticalFactor, 1), maxHorizontal: lowerControl1.x - lower.point.x)
            path.addCurve(to: anchored(lower.point), control1: anchored(lowerControl1), control2: anchored(lowerControl2))
            appendRail(from: bottomCut, through: h)
        } else {
            appendRail(from: 0, through: h)
        }
        path.closeSubpath()
        return path
    }

    private struct SideCurve {
        let start: CGPoint
        let control1: CGPoint
        let control2: CGPoint
        let end: CGPoint

        init(_ start: CGPoint, _ control1: CGPoint, _ control2: CGPoint, _ end: CGPoint) {
            self.start = start; self.control1 = control1; self.control2 = control2; self.end = end
        }

        private func split(at t: CGFloat) -> (left: Self, right: Self) {
            func mix(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
                CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            }
            let a = mix(start, control1), b = mix(control1, control2), c = mix(control2, end)
            let d = mix(a, b), e = mix(b, c), p = mix(d, e)
            return (Self(start, a, d, p), Self(p, e, c, end))
        }

        func position(at t: CGFloat) -> (point: CGPoint, tangent: CGPoint) {
            let pieces = split(at: t)
            let p = pieces.left.end
            let tangent = t < 1 ? CGPoint(x: pieces.right.control1.x - p.x, y: pieces.right.control1.y - p.y)
                                : CGPoint(x: p.x - pieces.left.control2.x, y: p.y - pieces.left.control2.y)
            return (p, tangent)
        }

        func parameter(atY y: CGFloat) -> CGFloat {
            if y <= start.y { return 0 }
            if y >= end.y { return 1 }
            var lower: CGFloat = 0, upper: CGFloat = 1
            for _ in 0..<36 {
                let middle = (lower + upper) / 2
                if position(at: middle).point.y < y { lower = middle } else { upper = middle }
            }
            return (lower + upper) / 2
        }

        func portion(from lower: CGFloat, through upper: CGFloat) -> Self {
            let prefix = split(at: upper).left
            return lower > 0 && upper > 0 ? prefix.split(at: lower / upper).right : prefix
        }

        static func tangentControl(from start: CGPoint, direction: CGPoint, length: CGFloat, maxHorizontal: CGFloat) -> CGPoint {
            let magnitude = hypot(direction.x, direction.y)
            guard magnitude > 0 else { return start }
            let unit = CGPoint(x: direction.x / magnitude, y: direction.y / magnitude)
            let distance = unit.x > 0 ? min(length, max(maxHorizontal, 0) / unit.x) : length
            return CGPoint(x: start.x + unit.x * distance, y: start.y + unit.y * distance)
        }
    }

    static func contains(_ point: CGPoint, in size: CGSize, edge: MacWidgetEdge, selectedIndex: CGFloat,
                         scale: Double, topCameraInset: CGFloat = 0, topNotchWidth: CGFloat = 0) -> Bool {
        if edge == .top, point.y < topCameraInset {
            return topCameraHoverFrame(in: size, scale: scale, topCameraInset: topCameraInset,
                                       topNotchWidth: topNotchWidth).contains(point)
        }
        return path(in: size, edge: edge, selectedIndex: selectedIndex, scale: scale,
                    topCameraInset: topCameraInset, topNotchWidth: topNotchWidth).contains(point)
    }
}
