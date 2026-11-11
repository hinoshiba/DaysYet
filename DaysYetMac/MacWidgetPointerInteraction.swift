import AppKit

/// Separates clicks from a captured drag without consulting windows or user defaults.
struct MacWidgetPointerInteraction {
    struct Placement: Equatable {
        let frame: NSRect
        let position: Double
        var edge: MacWidgetEdge? = nil
        var target: MacWidgetDropTarget? = nil
        var attachment: MacWidgetDropTarget? = nil
        var tension: CGFloat = 0
        var isDetached = false
        var pointer: NSPoint? = nil
        var isSlidingAlongEdge = false
    }

    enum Completion: Equatable {
        case none
        case openSettings
        case drag(Placement)
    }

    private struct Press {
        let point: NSPoint
        let frame: NSRect
        let bounds: NSRect?
        let position: Double
        let clickCount: Int
        let timestamp: TimeInterval
        let docking: MacWidgetDocking?
        var crossedThreshold = false
        var detached = false
        var target: MacWidgetDropTarget?
        var attachment: MacWidgetDropTarget?
        var isSlidingAlongEdge = false
    }

    static let dragThreshold: CGFloat = 5
    private var press: Press?
    private var previousClick: (point: NSPoint, timestamp: TimeInterval)?
    var isPressed: Bool { press != nil }
    var isDragging: Bool { press?.crossedThreshold == true }
    var originalFrame: NSRect? { press?.frame }
    var docking: MacWidgetDocking? { press?.docking }

    /// Quartz and AppKit share global point units, but opposite vertical axes.
    static func appKitPoint(fromQuartz point: CGPoint, primaryScreenMaxY: CGFloat) -> NSPoint {
        NSPoint(x: point.x, y: primaryScreenMaxY - point.y)
    }

    /// Docking captures a complete screen; bounds alone retain single-edge
    /// sliding. With neither available, a press can only become a click.
    mutating func begin(at point: NSPoint, frame: NSRect, bounds: NSRect?, position: Double,
                        clickCount: Int, timestamp: TimeInterval, docking: MacWidgetDocking? = nil) {
        press = Press(point: point, frame: frame, bounds: bounds, position: position,
                      clickCount: clickCount, timestamp: timestamp, docking: docking)
    }

    mutating func update(at point: NSPoint) -> Placement? {
        guard var press, point.x.isFinite, point.y.isFinite else { return nil }
        let dx = point.x - press.point.x
        let dy = point.y - press.point.y
        if hypot(dx, dy) >= Self.dragThreshold { press.crossedThreshold = true }
        if let docking = press.docking, press.crossedThreshold {
            let distance = hypot(dx, dy)
            let normal = docking.edge == .left || docking.edge == .right ? abs(dx) : abs(dy)
            let tangent = docking.edge == .left || docking.edge == .right ? abs(dy) : abs(dx)
            // Preserve the starting edge during tangential movement, even
            // near a corner or beyond a snap zone because of a Dock inset.
            // Choose the nearest physical edge only after pulling away.
            if !press.detached, normal < MacWidgetDocking.releaseDistance,
               press.isSlidingAlongEdge || tangent > normal,
               let candidate = docking.slidingTarget(at: point, originalFrame: press.frame, anchor: press.point) {
                press.isSlidingAlongEdge = true
                press.target = candidate
                press.attachment = candidate
                self.press = press
                return Placement(frame: candidate.frame, position: candidate.position, edge: candidate.edge,
                    target: candidate, attachment: candidate, pointer: point, isSlidingAlongEdge: true)
            }
            press.isSlidingAlongEdge = false
            press.detached = press.detached || distance >= MacWidgetDocking.releaseDistance
            if press.detached {
                press.target = docking.target(at: point, previous: press.target?.edge,
                    originalFrame: press.frame, anchor: press.point)
                press.attachment = docking.attachment(at: point, target: press.target, previous: press.attachment?.edge)
            }
            self.press = press
            let resistance: CGFloat = press.detached ? 1 : 0.32
            return Placement(frame: press.frame.offsetBy(dx: dx * resistance, dy: dy * resistance),
                position: press.position, edge: docking.edge, target: press.target, attachment: press.attachment,
                tension: min(distance / MacWidgetDocking.releaseDistance, 1), isDetached: press.detached, pointer: point)
        }
        self.press = press
        guard press.crossedThreshold, let bounds = press.bounds else { return nil }
        var frame = press.frame
        let travel = max(bounds.height - frame.height, 0)
        frame.origin.y = min(max(press.frame.minY + dy, bounds.minY), bounds.minY + travel)
        // Preserve the saved fraction if the widget fills a very short display.
        // There is no meaningful inverse position until that display grows.
        let position = travel > 0 ? Double((bounds.maxY - frame.height - frame.minY) / travel) : press.position
        return Placement(frame: frame, position: min(max(position, 0), 1))
    }

    mutating func finish(at point: NSPoint, doubleClickInterval: TimeInterval) -> Completion {
        let placement = update(at: point)
        guard let press else { return .none }
        self.press = nil
        if press.crossedThreshold {
            previousClick = nil
            if let docking = press.docking {
                let target = press.target
                return .drag(Placement(frame: target?.frame ?? press.frame, position: target?.position ?? press.position,
                                       edge: target?.edge ?? docking.edge, target: target, attachment: press.attachment,
                                       isSlidingAlongEdge: press.isSlidingAlongEdge))
            }
            return placement.map(Completion.drag) ?? .none
        }
        // AppKit can report clickCount == 2 immediately after a drag. Require
        // an actual completed click on this panel before opening settings.
        if press.clickCount >= 2, let previousClick,
           press.timestamp >= previousClick.timestamp,
           press.timestamp - previousClick.timestamp <= doubleClickInterval,
           hypot(press.point.x - previousClick.point.x, press.point.y - previousClick.point.y) < Self.dragThreshold {
            self.previousClick = nil
            return .openSettings
        }
        previousClick = (press.point, press.timestamp)
        return .none
    }

    mutating func cancel() {
        press = nil
        previousClick = nil
    }
}
