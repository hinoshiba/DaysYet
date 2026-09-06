import AppKit

/// Separates clicks from a captured drag without consulting windows or user defaults.
struct MacWidgetPointerInteraction {
    struct Placement: Equatable {
        let frame: NSRect
        let position: Double
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
        var crossedThreshold = false
    }

    static let dragThreshold: CGFloat = 5
    private var press: Press?
    private var previousClick: (point: NSPoint, timestamp: TimeInterval)?
    var isPressed: Bool { press != nil }

    /// Quartz and AppKit share global point units, but opposite vertical axes.
    static func appKitPoint(fromQuartz point: CGPoint, primaryScreenMaxY: CGFloat) -> NSPoint {
        NSPoint(x: point.x, y: primaryScreenMaxY - point.y)
    }

    /// A nil bound allows clicks on the top widget, but never moves it.
    mutating func begin(at point: NSPoint, frame: NSRect, bounds: NSRect?, position: Double,
                        clickCount: Int, timestamp: TimeInterval) {
        press = Press(point: point, frame: frame, bounds: bounds, position: position,
                      clickCount: clickCount, timestamp: timestamp)
    }

    mutating func update(at point: NSPoint) -> Placement? {
        guard var press, point.x.isFinite, point.y.isFinite else { return nil }
        let dx = point.x - press.point.x
        let dy = point.y - press.point.y
        if hypot(dx, dy) >= Self.dragThreshold { press.crossedThreshold = true }
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
