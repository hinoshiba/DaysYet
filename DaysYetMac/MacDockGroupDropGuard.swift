import AppKit

/// Quartz screen coordinates. This describes DaysYet's verified native slots,
/// not arbitrary windows underneath the pointer.
struct MacDockGroupDropRegion: Equatable {
    let edge: MacWidgetEdge
    let screen: CGRect
    let slots: [CGRect]
    let bounds: CGRect

    init?(edge: MacWidgetEdge, screen: CGRect, slots: [CGRect]) {
        guard edge != .top, (2...8).contains(slots.count), Self.valid(screen),
              slots.allSatisfy({ Self.valid($0) && $0.width >= 8 && $0.height >= 8
                  && $0.width <= 512 && $0.height <= 512 && screen.insetBy(dx: -1, dy: -1).contains($0) }) else { return nil }
        self.edge = edge
        self.screen = screen
        self.slots = slots
        bounds = slots.dropFirst().reduce(slots[0]) { $0.union($1) }
        // Only a strip at the actual Dock edge can redirect a Dock drag.
        let depth = edge == .bottom ? screen.maxY - bounds.minY
            : edge == .left ? bounds.maxX - screen.minX : screen.maxX - bounds.minX
        guard depth > 0, depth <= 520 else { return nil }
    }

    var isHorizontal: Bool { edge == .bottom }
    func axis(_ point: CGPoint) -> CGFloat { isHorizontal ? point.x : point.y }
    var lower: CGFloat { isHorizontal ? bounds.minX : bounds.minY }
    var upper: CGFloat { isHorizontal ? bounds.maxX : bounds.maxY }

    func contains(_ point: CGPoint) -> Bool {
        guard point.x.isFinite, point.y.isFinite, screen.contains(point), axis(point) >= lower, axis(point) <= upper else { return false }
        switch edge {
        case .bottom: return point.y >= bounds.minY - 2
        case .left: return point.x <= bounds.maxX + 2
        case .right: return point.x >= bounds.minX - 2
        case .top: return false
        }
    }

    func outside(_ point: CGPoint, before: Bool) -> CGPoint? {
        let minimum = isHorizontal ? screen.minX : screen.minY
        let maximum = isHorizontal ? screen.maxX : screen.maxY
        let candidate = before ? max(minimum + 1, lower - 4) : min(maximum - 1, upper + 4)
        guard before ? candidate < lower : candidate > upper else { return nil }
        return isHorizontal ? CGPoint(x: candidate, y: point.y) : CGPoint(x: point.x, y: candidate)
    }

    private static func valid(_ rect: CGRect) -> Bool {
        [rect.minX, rect.minY, rect.maxX, rect.maxY].allSatisfy(\.isFinite) && rect.width > 0 && rect.height > 0
    }
}

/// Pure routing policy; it never posts or drops an event. A Dock-owned drag
/// can choose either outside edge of the group, but not a gap inside it.
struct MacDockGroupDropRouting {
    enum Event { case down, dragged, up }
    private struct Press {
        let origin: CGPoint
        let began: TimeInterval
        var moved = false
        var before: Bool?
    }
    private var press: Press?
    private var region: MacDockGroupDropRegion?
    private var updatedAt: TimeInterval = 0
    var isTracking: Bool { press != nil }

    mutating func update(_ region: MacDockGroupDropRegion?, now: TimeInterval) {
        if self.region?.edge != region?.edge || self.region?.screen != region?.screen { press = nil }
        self.region = region
        updatedAt = now
        if region == nil { press = nil }
    }

    mutating func cancel() { press = nil }

    mutating func route(_ event: Event, at point: CGPoint, now: TimeInterval) -> CGPoint {
        guard point.x.isFinite, point.y.isFinite, let region, now >= updatedAt, now - updatedAt <= 0.3 else {
            press = nil
            return point
        }
        if event == .down {
            // DaysYet's own press is handled by its input panel. Never redirect
            // it even if macOS delivered a press during a panel transition.
            press = region.slots.contains(where: { $0.contains(point) }) ? nil : Press(origin: point, began: now)
            return point
        }
        guard var current = press, now - current.began < 60 else { press = nil; return point }
        // A stationary long press opens the Dock's menu. Its subsequent menu
        // tracking must not be mistaken for rearranging an application.
        if !current.moved, now - current.began > 0.5 { press = nil; return point }
        current.moved = current.moved || hypot(point.x - current.origin.x, point.y - current.origin.y) >= 4
        var result = point
        if current.moved, region.contains(point) {
            let value = region.axis(point)
            let middle = (region.lower + region.upper) / 2
            // A small dead band keeps the target from flickering between both
            // sides while the user holds the pointer near the group's center.
            if current.before == nil { current.before = value == middle ? region.axis(current.origin) < middle : value < middle }
            else if value < middle - 8 { current.before = true }
            else if value > middle + 8 { current.before = false }
            result = region.outside(point, before: current.before ?? true)
                ?? region.outside(point, before: !(current.before ?? true)) ?? point
        }
        press = event == .up ? nil : current
        return result
    }
}

#if DAYSYET_DIRECT_DOCK_DRAG && DAYSYET_DOCK_GROUP_GUARD
import ApplicationServices
import OSLog

/// Experimental process-scoped filter: only left-button events already routed
/// to macOS Dock are eligible. No keyboard, other application events, synthetic
/// events, pointer warps, or Dock preference changes are involved.
@MainActor
final class MacDockGroupDropGuard {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var dockPID: pid_t?
    private var sourceFrame: CGRect?
    private var sourceSampleTime: TimeInterval = -.infinity
    private var lastAttempt: TimeInterval = -.infinity
    private var disabledByUser = false
    private var routing = MacDockGroupDropRouting()
    private var redirected = false
    private let log = Logger(subsystem: "com.hinoshiba.daysyet", category: "dock-group-guard")

    var isTracking: Bool { routing.isTracking }

    func connect(to pid: pid_t) {
        if dockPID != pid { stop(); dockPID = pid }
        guard tap == nil, !disabledByUser, pid > 1,
              ProcessInfo.processInfo.systemUptime - lastAttempt >= 2, AXIsProcessTrusted() else { return }
        lastAttempt = ProcessInfo.processInfo.systemUptime
        let mask = [CGEventType.leftMouseDown, .leftMouseDragged, .leftMouseUp]
            .reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreateForPid(pid: pid, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                return MainActor.assumeIsolated {
                    Unmanaged<MacDockGroupDropGuard>.fromOpaque(context).takeUnretainedValue().handle(type, event: event)
                }
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            log.notice("Dock-specific drag filter is unavailable")
            return
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return
        }
        self.tap = tap
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        log.notice("Dock-specific drag filter connected")
    }

    func update(_ region: MacDockGroupDropRegion?) {
        routing.update(region, now: ProcessInfo.processInfo.systemUptime)
    }

    func updateSource(_ frame: CGRect?, sampledAt time: TimeInterval) {
        sourceFrame = frame
        sourceSampleTime = time
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil
        tap = nil
        dockPID = nil
        sourceFrame = nil
        sourceSampleTime = -.infinity
        lastAttempt = -.infinity
        disabledByUser = false
        routing.update(nil, now: ProcessInfo.processInfo.systemUptime)
        redirected = false
    }

    private func handle(_ type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent> {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            routing.cancel()
            redirected = false
            if type == .tapDisabledByUserInput { disabledByUser = true }
            else if !disabledByUser, let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let kind: MacDockGroupDropRouting.Event
        switch type {
        case .leftMouseDown:
            redirected = false
            // Dock also receives separator-resize and background presses.
            // Only its native application-item subrole can arm the filter.
            // The classification was read on the geometry queue. Never make
            // synchronous AX requests to Dock while filtering its input.
            let sourceAge = ProcessInfo.processInfo.systemUptime - sourceSampleTime
            guard !event.flags.contains(.maskControl), sourceAge >= 0, sourceAge <= 0.2,
                  sourceFrame?.contains(event.location) == true else {
                routing.cancel()
                return Unmanaged.passUnretained(event)
            }
            kind = .down
        case .leftMouseDragged: kind = .dragged
        case .leftMouseUp: kind = .up
        default: return Unmanaged.passUnretained(event)
        }
        let destination = routing.route(kind, at: event.location, now: ProcessInfo.processInfo.systemUptime)
        if destination != event.location { event.location = destination; redirected = true }
        if type == .leftMouseUp, redirected {
            // No coordinates or other app identities are logged. Logging runs
            // after the callback so the input filter itself remains bounded.
            DispatchQueue.main.async { [log] in log.notice("Dock drag routed outside the DaysYet group") }
        }
        // In particular, always deliver mouse-up, including after invalidation.
        return Unmanaged.passUnretained(event)
    }

}
#endif
