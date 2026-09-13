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

extension UserProfile {
    /// The camera strip has three segments; side rails use every configured circle.
    func macWidgetMetrics(for edge: MacWidgetEdge) -> [MetricKind] {
        edge == .top ? Array(macDashboardMetrics.prefix(3)) : macDashboardMetrics
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
    @Published var magnifiesOnHover: Bool { didSet { defaults.set(magnifiesOnHover, forKey: Key.magnifiesOnHover) } }
    @Published var hoverScale: Double {
        didSet {
            let value = Self.clampedHoverScale(hoverScale)
            if hoverScale != value { hoverScale = value }
            defaults.set(value, forKey: Key.hoverScale)
        }
    }
    @Published var detailScale: Double {
        didSet {
            let value = Self.clampedDetailScale(detailScale)
            if detailScale != value { detailScale = value }
            defaults.set(value, forKey: Key.detailScale)
        }
    }
    @Published private(set) var customColors: [MetricKind: MacWidgetColor]

    private let defaults: UserDefaults
    private enum Key {
        static let visible = "mac-widget-visible"
        static let edge = "mac-widget-edge"
        static let position = "mac-widget-position"
        static let display = "mac-widget-display"
        static let details = "mac-widget-keep-details"
        static let scale = "mac-widget-scale"
        static let magnifiesOnHover = "mac-widget-magnifies-on-hover"
        static let hoverScale = "mac-widget-hover-scale"
        static let detailScale = "mac-widget-detail-scale"
        static let customColors = "mac-widget-custom-colors"
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
        magnifiesOnHover = defaults.bool(forKey: Key.magnifiesOnHover)
        hoverScale = Self.clampedHoverScale(defaults.object(forKey: Key.hoverScale) as? Double ?? 1.35)
        detailScale = Self.clampedDetailScale(defaults.object(forKey: Key.detailScale) as? Double ?? 1)
        customColors = (defaults.dictionary(forKey: Key.customColors) ?? [:]).reduce(into: [:]) { colors, entry in
            guard let kind = MetricKind(rawValue: entry.key), let hex = entry.value as? String,
                  let color = MacWidgetColor(hex: hex) else { return }
            colors[kind] = color
        }
    }

    nonisolated static func clampedHoverScale(_ scale: Double) -> Double {
        scale.isFinite ? min(max(scale, 1.1), 1.8) : 1.35
    }

    nonisolated static func clampedDetailScale(_ scale: Double) -> Double {
        scale.isFinite ? min(max(scale, 1), 1.5) : 1
    }

    func customColor(for kind: MetricKind) -> MacWidgetColor? {
        customColors[kind]
    }

    func setCustomColor(_ color: MacWidgetColor?, for kind: MetricKind) {
        guard customColors[kind] != color else { return }
        customColors[kind] = color
        if customColors.isEmpty {
            defaults.removeObject(forKey: Key.customColors)
        } else {
            defaults.set(Dictionary(uniqueKeysWithValues: customColors.map { ($0.key.rawValue, $0.value.hex) }),
                         forKey: Key.customColors)
        }
    }

    func resetCustomColors() {
        customColors = [:]
        defaults.removeObject(forKey: Key.customColors)
    }

    func reset() {
        isVisible = true
        edge = .right
        verticalPosition = 0.5
        displayID = ""
        keepDetailsOpen = false
        scale = 1
        magnifiesOnHover = false
        hoverScale = 1.35
        detailScale = 1
        resetCustomColors()
        [Key.visible, Key.edge, Key.position, Key.display, Key.details, Key.scale,
         Key.magnifiesOnHover, Key.hoverScale, Key.detailScale].forEach(defaults.removeObject(forKey:))
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

    static func clampedMetricCount(_ count: Int) -> Int {
        min(max(count, 3), MetricKind.allCases.count)
    }

    static func railHeight(for metricCount: Int) -> CGFloat {
        railSize.height + 50 * CGFloat(clampedMetricCount(metricCount) - 3)
    }

    static func ringCenters(for metricCount: Int) -> [CGFloat] {
        (0..<clampedMetricCount(metricCount)).map { 56 + 50 * CGFloat($0) }
    }

    /// Compress all vertical content together when the available display is short.
    static func sideVerticalScale(in size: CGSize, scale: Double, metricCount: Int = 3) -> CGFloat {
        min(clampedScale(scale), max(size.height, 0) / railHeight(for: metricCount))
    }

    static func clampedScale(_ scale: Double) -> Double {
        scale.isFinite ? min(max(scale, 0.8), 1.5) : 1
    }

    static func topClosedHeight(cameraInset: CGFloat, scale: Double = 1) -> CGFloat {
        let inset = cameraInset.isFinite ? max(cameraInset, 0) : 0
        return inset + 8 * clampedScale(scale)
    }

    static func topExpandedHeight(cameraInset: CGFloat, scale: Double, detailScale: Double = 1) -> CGFloat {
        let inset = cameraInset.isFinite ? max(cameraInset, 0) : 0
        let detail = MacWidgetPreferences.clampedDetailScale(detailScale)
        return inset + (22 + 8 * (detail - 1) + 52 * detail) * clampedScale(scale)
    }

    /// Physical coordinates keep the complete header and value below the
    /// widening shoulders, with room above the rounded bottom of the surface.
    static func topDetailFrame(in size: CGSize, cameraInset: CGFloat, scale: Double, detailScale: Double = 1) -> CGRect {
        let factor = clampedScale(scale)
        let detail = MacWidgetPreferences.clampedDetailScale(detailScale)
        let inset = cameraInset.isFinite ? max(cameraInset, 0) : 0
        let width = min(max(size.width - 40 * factor, 0), 240 * factor * detail)
        // Wider details start a little below the widening camera shoulders.
        return CGRect(x: (size.width - width) / 2, y: inset + (16 + 8 * (detail - 1)) * factor,
                      width: width, height: 52 * factor * detail)
    }

    /// Preserve the circle's screen-edge clearance as it grows inward.
    static func inwardShift(for magnification: Double) -> CGFloat {
        16.75 * (min(max(magnification.isFinite ? magnification : 1, 1), 1.8) - 1)
    }

    static func hoverOutset(for hoverScale: Double) -> CGFloat {
        guard hoverScale > 1 else { return 0 }
        let magnification = MacWidgetPreferences.clampedHoverScale(hoverScale)
        return max(23 + inwardShift(for: magnification) + 16.75 * magnification + 2 - 46, 0)
    }

    static func sideExpansion(in size: CGSize, scale: Double, hoverScale: Double = 1, detailScale: Double = 1) -> CGFloat {
        let closed = 46 + hoverOutset(for: hoverScale)
        let travel = 158 + 124 * (MacWidgetPreferences.clampedDetailScale(detailScale) - 1)
        return min(max((size.width / clampedScale(scale) - closed) / travel, 0), 1)
    }

    static func sideDetailCenter(selectedIndex: CGFloat, metricCount: Int, detailScale: Double) -> CGFloat {
        let index = selectedIndex.isFinite ? min(max(selectedIndex, 0), CGFloat(clampedMetricCount(metricCount) - 1)) : 0
        let clearance = 26 * MacWidgetPreferences.clampedDetailScale(detailScale) + 30
        return min(max(56 + 50 * index, clearance), railHeight(for: metricCount) - clearance)
    }

    static func sideRingFrame(in size: CGSize, edge: MacWidgetEdge, index: Int, scale: Double,
                              metricCount: Int = 3, magnification: Double = 1, padding: CGFloat = 0) -> CGRect {
        let factor = clampedScale(scale)
        let vertical = sideVerticalScale(in: size, scale: factor, metricCount: metricCount)
        let magnification = min(max(magnification.isFinite ? magnification : 1, 1), 1.8)
        let depth = 23 + inwardShift(for: magnification)
        let radius = 16.75 * magnification + padding
        let centerX = edge == .right ? size.width - depth * factor : depth * factor
        let centerY = (56 + 50 * CGFloat(index)) * vertical
        return CGRect(x: centerX - radius * factor, y: centerY - radius * vertical,
                      width: 2 * radius * factor, height: 2 * radius * vertical)
    }

    static func sideDetailFrame(in size: CGSize, edge: MacWidgetEdge, selectedIndex: CGFloat, scale: Double,
                                metricCount: Int = 3, hoverScale: Double = 1, detailScale: Double = 1) -> CGRect {
        let factor = clampedScale(scale)
        let verticalScale = sideVerticalScale(in: size, scale: scale, metricCount: metricCount)
        let detail = MacWidgetPreferences.clampedDetailScale(detailScale)
        let depth = 60 + hoverOutset(for: hoverScale)
        let center = sideDetailCenter(selectedIndex: selectedIndex, metricCount: metricCount, detailScale: detail)
        return CGRect(x: edge == .right ? size.width - (depth + 124 * detail) * factor : depth * factor,
                      y: (center - 26 * detail) * verticalScale, width: 124 * detail * factor, height: 52 * detail * verticalScale)
    }

    static func railFrame(in visibleFrame: NSRect, edge: MacWidgetEdge, position: Double) -> NSRect {
        frame(in: visibleFrame, edge: edge, position: position, expanded: false)
    }

    static func frame(in visibleFrame: NSRect, edge: MacWidgetEdge, position: Double, expanded: Bool,
                      scale: Double = 1, screenFrame: NSRect? = nil, topInfo: MacTopNotchInfo? = nil,
                      metricCount: Int = 3, hoverScale: Double = 1, detailScale: Double = 1) -> NSRect {
        let factor = clampedScale(scale)
        let detail = MacWidgetPreferences.clampedDetailScale(detailScale)
        if edge == .top {
            let screen = screenFrame ?? visibleFrame
            let info = topInfo ?? MacTopNotchInfo(centerX: screen.midX)
            let cameraInset = info.cameraInset.isFinite ? min(max(info.cameraInset, 0), screen.height) : 0
            let notchWidth = info.notchWidth.isFinite ? min(max(info.notchWidth, 0), screen.width) : 0
            let center = info.centerX.isFinite ? info.centerX : screen.midX
            let idleWidth = max(174 * factor, notchWidth + 24 * factor)
            let width = min(expanded ? max((40 + 240 * detail) * factor, idleWidth) : idleWidth, screen.width)
            let height = min(expanded ? topExpandedHeight(cameraInset: cameraInset, scale: factor, detailScale: detail)
                                     : topClosedHeight(cameraInset: cameraInset, scale: factor), screen.height)
            return NSRect(x: min(max(center - width / 2, screen.minX), screen.maxX - width),
                          y: screen.maxY - height, width: width, height: height)
        }
        let fraction = position.isFinite ? min(max(position, 0), 1) : 0.5
        let size = expanded ? expandedSize : railSize
        let height = min(railHeight(for: metricCount) * factor, visibleFrame.height)
        let width = min((size.width + hoverOutset(for: hoverScale) + (expanded ? 124 * (detail - 1) : 0)) * factor, visibleFrame.width)
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
    static func sideHoverIndex(at point: CGPoint, in size: CGSize, edge: MacWidgetEdge,
                               scale: Double, metricCount: Int = 3, magnifications: [Int: CGFloat] = [:]) -> Int? {
        guard edge != .top else { return nil }
        let factor = MacWidgetPlacement.clampedScale(scale)
        let verticalScale = MacWidgetPlacement.sideVerticalScale(in: size, scale: scale, metricCount: metricCount)
        let count = MacWidgetPlacement.clampedMetricCount(metricCount)
        let rows = CGRect(x: edge == .right ? size.width - 46 * factor : 0,
                          y: 31 * verticalScale, width: 46 * factor, height: 50 * CGFloat(count) * verticalScale)
        guard verticalScale > 0 else { return nil }
        if rows.contains(point) {
            return min(Int((point.y - rows.minY) / (50 * verticalScale)), count - 1)
        }
        // Fixed rows take priority; the inward overflow keeps its own circle hovered.
        return magnifications.keys.sorted().first { index in
            guard (0..<count).contains(index), let magnification = magnifications[index], magnification > 1 else { return false }
            let frame = MacWidgetPlacement.sideRingFrame(in: size, edge: edge, index: index,
                scale: scale, metricCount: count, magnification: magnification, padding: 2)
            return CGPath(ellipseIn: frame, transform: nil).contains(point)
        }
    }

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
                     topCameraInset: CGFloat = 0, topNotchWidth: CGFloat = 0, metricCount: Int = 3,
                     hoverScale: Double = 1, detailScale: Double = 1, magnifications: [Int: CGFloat] = [:]) -> CGPath {
        let path = CGMutablePath()
        guard size.width > 0, size.height > 0 else { return path }
        let factor = CGFloat(MacWidgetPlacement.clampedScale(scale))
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
        let expansion = MacWidgetPlacement.sideExpansion(in: size, scale: factor, hoverScale: hoverScale, detailScale: detailScale)
        let bodyWidth = max(base, w - MacWidgetPlacement.hoverOutset(for: hoverScale) * (1 - expansion))
        let extensionWidth = max(bodyWidth - base, 0)
        let verticalFactor = min(h / MacWidgetPlacement.railHeight(for: metricCount), 1)
        let shoulder = min(29 * verticalFactor, h / 5)
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
            let center = MacWidgetPlacement.sideDetailCenter(selectedIndex: selectedIndex, metricCount: metricCount, detailScale: detailScale)
            func bodyY(_ y: CGFloat) -> CGFloat { y * verticalFactor }
            let halfHeight = 26 * MacWidgetPreferences.clampedDetailScale(detailScale) + 14
            let top = center - halfHeight * expansion
            let bottom = center + halfHeight * expansion
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
            path.addLine(to: anchored(point(bodyWidth - corner, bodyY(top))))
            path.addCurve(to: anchored(point(bodyWidth, bodyY(top + corner))),
                          control1: anchored(point(bodyWidth - 9 * expansion, bodyY(top))),
                          control2: anchored(point(bodyWidth, bodyY(top + 9 * expansion))))
            path.addLine(to: anchored(point(bodyWidth, bodyY(bottom - corner))))
            path.addCurve(to: anchored(point(bodyWidth - corner, bodyY(bottom))),
                          control1: anchored(point(bodyWidth, bodyY(bottom - 9 * expansion))),
                          control2: anchored(point(bodyWidth - 9 * expansion, bodyY(bottom))))
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
        for (index, magnification) in magnifications where magnification > 1 && (0..<MacWidgetPlacement.clampedMetricCount(metricCount)).contains(index) {
            let frame = MacWidgetPlacement.sideRingFrame(in: size, edge: edge, index: index,
                scale: factor, metricCount: metricCount, magnification: magnification, padding: 2)
            // Match the rail's winding on each edge so overlapping filled paths
            // form one surface instead of cutting holes in each other.
            let direction: CGFloat = edge == .left ? 1 : -1
            let rx = frame.width / 2 * direction
            let ry = frame.height / 2
            let cx = frame.midX
            let cy = frame.midY
            let k: CGFloat = 0.5522847498
            path.move(to: CGPoint(x: cx, y: cy - ry))
            path.addCurve(to: CGPoint(x: cx + rx, y: cy), control1: CGPoint(x: cx + k * rx, y: cy - ry), control2: CGPoint(x: cx + rx, y: cy - k * ry))
            path.addCurve(to: CGPoint(x: cx, y: cy + ry), control1: CGPoint(x: cx + rx, y: cy + k * ry), control2: CGPoint(x: cx + k * rx, y: cy + ry))
            path.addCurve(to: CGPoint(x: cx - rx, y: cy), control1: CGPoint(x: cx - k * rx, y: cy + ry), control2: CGPoint(x: cx - rx, y: cy + k * ry))
            path.addCurve(to: CGPoint(x: cx, y: cy - ry), control1: CGPoint(x: cx - rx, y: cy - k * ry), control2: CGPoint(x: cx - k * rx, y: cy - ry))
            path.closeSubpath()
        }
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
                         scale: Double, topCameraInset: CGFloat = 0, topNotchWidth: CGFloat = 0,
                         metricCount: Int = 3, hoverScale: Double = 1, detailScale: Double = 1,
                         magnifications: [Int: CGFloat] = [:]) -> Bool {
        if edge == .top, point.y < topCameraInset {
            return topCameraHoverFrame(in: size, scale: scale, topCameraInset: topCameraInset,
                                       topNotchWidth: topNotchWidth).contains(point)
        }
        return path(in: size, edge: edge, selectedIndex: selectedIndex, scale: scale,
                    topCameraInset: topCameraInset, topNotchWidth: topNotchWidth, metricCount: metricCount,
                    hoverScale: hoverScale, detailScale: detailScale, magnifications: magnifications).contains(point)
    }
}
