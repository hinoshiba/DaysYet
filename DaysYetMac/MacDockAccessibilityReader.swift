#if DAYSYET_DIRECT_DOCK_DRAG
import AppKit
import ApplicationServices

struct MacDockAccessibilityItem: Sendable {
    let metric: MetricKind
    /// AppKit global coordinates, in points rather than backing pixels.
    let frame: NSRect
}

enum MacDockAccessibilitySample: Sendable {
    case current([MacDockAccessibilityItem])
    /// The bounded read ran out of time, rather than observing hidden tiles.
    case temporarilyUnavailable
}

/// Read-only Dock inspection for the explicitly enabled direct-distribution
/// prototype. The caller must confine this instance to one serial queue.
/// No permission prompt, AX action, attribute mutation, or event posting occurs.
final class MacDockAccessibilityReader: @unchecked Sendable {
    private static let messageTimeout: Float = 0.025
    private static let readDuration: TimeInterval = 0.075
    private static let discoveryInterval: TimeInterval = 0.75
    private static let maximumElements = 512
    private static let maximumChildren = 256
    private static let maximumDepth = 5

    private enum ReadFailure: Error { case exhausted, temporarilyUnavailable, unavailable }

    private struct Budget {
        let deadline: TimeInterval
        var operations = 96

        mutating func consume() throws {
            guard operations > 0, ProcessInfo.processInfo.systemUptime < deadline else { throw ReadFailure.exhausted }
            operations -= 1
        }
    }

    private struct Node {
        let element: AXUIElement
        let depth: Int
    }

    private struct Discovery {
        var queue: [Node]
        var cursor = 0
        var visited: [AXUIElement] = []
        var matches: [MetricKind: AXUIElement] = [:]
        var ambiguous = Set<MetricKind>()
    }

    private var processID: pid_t?
    private var allowedPaths: [MetricKind: String] = [:]
    private var root: AXUIElement?
    private var elements: [MetricKind: AXUIElement] = [:]
    private var discovery: Discovery?
    private var nextDiscovery: TimeInterval = 0
    private var mayUsePreviousSnapshot = false

    /// Helper processes can disappear and return under the same file URLs.
    /// Call on the reader's serial queue when leaving Dock mode.
    func invalidate() { reset() }

#if DAYSYET_DOCK_GROUP_GUARD
    /// Classification for a possible native app-item drag. Only the subrole
    /// and rectangle are read; no other app's name or URL is retained.
    /// Run on this reader's serial queue, never inside an event-tap callback.
    func applicationItemFrame(at point: CGPoint) -> CGRect? {
        guard let processID, point.x.isFinite, point.y.isFinite else { return nil }
        let application = AXUIElementCreateApplication(processID)
        guard AXUIElementSetMessagingTimeout(application, 0.005) == .success else { return nil }
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(application, Float(point.x), Float(point.y), &hit) == .success,
              let hit, AXUIElementSetMessagingTimeout(hit, 0.005) == .success else { return nil }
        var raw: CFArray?
        let names = [kAXSubroleAttribute, kAXPositionAttribute, kAXSizeAttribute]
        guard AXUIElementCopyMultipleAttributeValues(hit, names as CFArray, [], &raw) == .success,
              let raw, CFArrayGetCount(raw) == 3 else { return nil }
        let values = raw as [AnyObject]
        guard values[0] as? String == kAXApplicationDockItemSubrole as String,
              let origin = Self.point(values[1]), let size = Self.size(values[2]),
              Self.appKitFrame(position: origin, size: size, primaryScreenMaxY: 0) != nil else { return nil }
        let frame = CGRect(origin: origin, size: size)
        return frame.contains(point) ? frame : nil
    }
#endif

    func sample(dockPID: pid_t, allowedURLs: [MetricKind: URL], primaryScreenMaxY: CGFloat,
                discoveringNewSlots: Bool = false, allowDragOcclusion: Bool = false) -> MacDockAccessibilitySample {
        let items = read(dockPID: dockPID, allowedURLs: allowedURLs, primaryScreenMaxY: primaryScreenMaxY,
                         discoveringNewSlots: discoveringNewSlots, allowDragOcclusion: allowDragOcclusion)
        return mayUsePreviousSnapshot ? .temporarilyUnavailable : .current(items)
    }

    func read(dockPID: pid_t, allowedURLs: [MetricKind: URL], primaryScreenMaxY: CGFloat,
              discoveringNewSlots: Bool = false, allowDragOcclusion: Bool = false) -> [MacDockAccessibilityItem] {
        mayUsePreviousSnapshot = false
        // Checking trust never requests it. Permission can be revoked between
        // polls, so old element references must not survive that transition.
        guard dockPID > 0, primaryScreenMaxY.isFinite, AXIsProcessTrusted() else {
            reset()
            return []
        }
        let paths = allowedURLs.compactMapValues(Self.localPath)
        guard !paths.isEmpty, paths.count == allowedURLs.count, Set(paths.values).count == paths.count else {
            reset()
            return []
        }
        var invalidatedPreviousGeometry = false
        if processID != dockPID || allowedPaths != paths || root == nil {
            invalidatedPreviousGeometry = true
            reset()
            processID = dockPID
            allowedPaths = paths
            let application = AXUIElementCreateApplication(dockPID)
            guard AXUIElementSetMessagingTimeout(application, Self.messageTimeout) == .success else { return [] }
            root = application
        }
        guard let root else { return [] }
        let now = ProcessInfo.processInfo.systemUptime
        var budget = Budget(deadline: now + Self.readDuration)
        do {
            if discovery != nil || (elements.count < paths.count && (now >= nextDiscovery || discoveringNewSlots)) {
                if discovery == nil { discovery = Discovery(queue: [Node(element: root, depth: 0)]) }
                try advanceDiscovery(budget: &budget)
                // A partial tree traversal has no complete identity result yet.
                guard discovery == nil else { return [] }
            }

            let screens = Self.activeDisplayBounds()
            guard !screens.isEmpty else { return [] }
            var result: [MacDockAccessibilityItem] = []
            var needsRediscovery = false
            for metric in MetricKind.allCases {
                guard let element = elements[metric], let path = paths[metric] else { continue }
                let values = try attributes(element, names: [kAXSubroleAttribute, kAXURLAttribute,
                    kAXPositionAttribute, kAXSizeAttribute, kAXEnabledAttribute, kAXHiddenAttribute], budget: &budget)
                guard values[0] as? String == (kAXApplicationDockItemSubrole as String),
                      Self.pathValue(values[1]) == path else {
                    invalidatedPreviousGeometry = true
                    needsRediscovery = true
                    continue
                }
                if Self.boolean(values[4]) == false || Self.boolean(values[5]) == true {
                    invalidatedPreviousGeometry = true
                    continue
                }
                guard let position = Self.point(values[2]), let size = Self.size(values[3]),
                      let frame = Self.appKitFrame(position: position, size: size, primaryScreenMaxY: primaryScreenMaxY) else {
                    invalidatedPreviousGeometry = true
                    continue
                }
                let quartzFrame = CGRect(origin: position, size: size)
                // Auto-hidden Dock items can retain off-screen AX geometry.
                // Never turn such a rectangle into an interactive overlay.
                guard screens.contains(where: { $0.insetBy(dx: -1, dy: -1).contains(quartzFrame) }) else {
                    invalidatedPreviousGeometry = true
                    continue
                }
                // During a Dock-owned drag its image can cover a verified
                // slot. Keep reading that slot's current geometry and identity.
                guard try allowDragOcclusion || isVisible(element, in: root, at: CGPoint(x: quartzFrame.midX, y: quartzFrame.midY), budget: &budget) else {
                    invalidatedPreviousGeometry = true
                    needsRediscovery = true
                    continue
                }
                result.append(MacDockAccessibilityItem(metric: metric, frame: frame))
            }
            if needsRediscovery, now >= nextDiscovery || discoveringNewSlots {
                discovery = Discovery(queue: [Node(element: root, depth: 0)])
            }
            // Do not return old rectangles after a slow or stalled AX request.
            guard ProcessInfo.processInfo.systemUptime < budget.deadline else {
                mayUsePreviousSnapshot = !invalidatedPreviousGeometry
                return []
            }
            return result
        } catch ReadFailure.exhausted, ReadFailure.temporarilyUnavailable {
            // Keep a bounded discovery's cursor so large Docks can be resolved
            // across polls, but never return a previous poll's frame values.
            // A later timeout must not resurrect an earlier observation that
            // a particular tile disappeared, moved off-screen, or changed identity.
            mayUsePreviousSnapshot = !invalidatedPreviousGeometry
            return []
        } catch {
            elements.removeAll()
            discovery = nil
            let application = AXUIElementCreateApplication(dockPID)
            self.root = AXUIElementSetMessagingTimeout(application, Self.messageTimeout) == .success ? application : nil
            nextDiscovery = now + Self.discoveryInterval
            return []
        }
    }

    private func reset() {
        processID = nil
        allowedPaths.removeAll()
        root = nil
        elements.removeAll()
        discovery = nil
        nextDiscovery = 0
    }

    private func advanceDiscovery(budget: inout Budget) throws {
        guard var walk = discovery else { return }
        // Preserve progress even if the time or operation budget is exhausted.
        defer { discovery = walk.cursor < walk.queue.count ? walk : nil }
        while walk.cursor < walk.queue.count {
            let node = walk.queue[walk.cursor]
            if walk.visited.contains(where: { CFEqual($0, node.element) }) {
                walk.cursor += 1
                continue
            }
            guard AXUIElementSetMessagingTimeout(node.element, Self.messageTimeout) == .success else { throw ReadFailure.unavailable }
            let identity = try attributes(node.element, names: [kAXRoleAttribute, kAXSubroleAttribute, kAXHiddenAttribute], budget: &budget)
            if Self.boolean(identity[2]) != true {
                if identity[1] as? String == (kAXApplicationDockItemSubrole as String) {
                    let value = try attributes(node.element, names: [kAXURLAttribute], budget: &budget)[0]
                    if let path = Self.pathValue(value), let metric = allowedPaths.first(where: { $0.value == path })?.key {
                        if let previous = walk.matches[metric], !CFEqual(previous, node.element) {
                            walk.matches.removeValue(forKey: metric)
                            walk.ambiguous.insert(metric)
                        } else if !walk.ambiguous.contains(metric) {
                            walk.matches[metric] = node.element
                        }
                    }
                } else if identity[0] as? String != (kAXDockItemRole as String), node.depth < Self.maximumDepth {
                    // Dock tiles are leaves. Traverse only their bounded parent
                    // hierarchy, never another application's AX tree.
                    let remaining = Self.maximumElements - walk.queue.count
                    if remaining > 0 {
                        let children = try childElements(node.element, maximum: min(remaining, Self.maximumChildren), budget: &budget)
                        walk.queue.append(contentsOf: children.map { Node(element: $0, depth: node.depth + 1) })
                    }
                }
            }
            walk.visited.append(node.element)
            walk.cursor += 1
        }
        elements = walk.matches
        nextDiscovery = ProcessInfo.processInfo.systemUptime + Self.discoveryInterval
    }

    private func attributes(_ element: AXUIElement, names: [String], budget: inout Budget) throws -> [AnyObject] {
        try budget.consume()
        var values: CFArray?
        let error = AXUIElementCopyMultipleAttributeValues(element, names as CFArray, [], &values)
        if error == .cannotComplete { throw ReadFailure.temporarilyUnavailable }
        guard error == .success,
              let values, CFArrayGetCount(values) == names.count else { throw ReadFailure.unavailable }
        // Unsupported optional attributes remain AXError/CFNull values; callers
        // check the expected public value type rather than force-casting them.
        return values as [AnyObject]
    }

    private func childElements(_ element: AXUIElement, maximum: Int, budget: inout Budget) throws -> [AXUIElement] {
        try budget.consume()
        var values: CFArray?
        let error = AXUIElementCopyAttributeValues(element, kAXChildrenAttribute as CFString, 0, maximum, &values)
        if error == .attributeUnsupported || error == .noValue { return [] }
        if error == .cannotComplete { throw ReadFailure.temporarilyUnavailable }
        guard error == .success, let values else { throw ReadFailure.unavailable }
        return (values as [AnyObject]).compactMap { value in
            guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            return (value as! AXUIElement)
        }
    }

    private func isVisible(_ expected: AXUIElement, in application: AXUIElement, at point: CGPoint, budget: inout Budget) throws -> Bool {
        try budget.consume()
        var hit: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(application, Float(point.x), Float(point.y), &hit)
        if error == .noValue { return false }
        if error == .cannotComplete { throw ReadFailure.temporarilyUnavailable }
        guard error == .success else { throw ReadFailure.unavailable }
        // Limit hit testing to the Dock, so our own overlay cannot hide the
        // native item from this check and cause a show/hide feedback loop.
        for _ in 0..<4 {
            guard let candidate = hit else { return false }
            if CFEqual(candidate, expected) { return true }
            guard AXUIElementSetMessagingTimeout(candidate, Self.messageTimeout) == .success else { return false }
            let parent = try attributes(candidate, names: [kAXParentAttribute], budget: &budget)[0]
            guard CFGetTypeID(parent) == AXUIElementGetTypeID() else { return false }
            hit = (parent as! AXUIElement)
        }
        return false
    }

    private static func localPath(_ url: URL) -> String? {
        guard url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost",
              url.query == nil, url.fragment == nil else { return nil }
        let path = url.standardizedFileURL.path
        return path.hasPrefix("/") && !path.isEmpty ? path : nil
    }

    private static func pathValue(_ value: AnyObject) -> String? {
        guard CFGetTypeID(value) == CFURLGetTypeID(), let url = value as? URL else { return nil }
        return localPath(url)
    }

    private static func boolean(_ value: AnyObject) -> Bool? {
        guard CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
        return value as? Bool
    }

    private static func point(_ value: AnyObject) -> CGPoint? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let ax = value as! AXValue
        var point = CGPoint.zero
        guard AXValueGetType(ax) == .cgPoint, AXValueGetValue(ax, .cgPoint, &point) else { return nil }
        return point
    }

    private static func size(_ value: AnyObject) -> CGSize? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let ax = value as! AXValue
        var size = CGSize.zero
        guard AXValueGetType(ax) == .cgSize, AXValueGetValue(ax, .cgSize, &size) else { return nil }
        return size
    }

    static func appKitFrame(position: CGPoint, size: CGSize, primaryScreenMaxY: CGFloat) -> NSRect? {
        guard position.x.isFinite, position.y.isFinite, primaryScreenMaxY.isFinite,
              size.width.isFinite, size.height.isFinite,
              size.width >= 8, size.height >= 8, size.width <= 512, size.height <= 512 else { return nil }
        let frame = NSRect(x: position.x, y: primaryScreenMaxY - position.y - size.height, width: size.width, height: size.height)
        guard frame.minX.isFinite, frame.maxX.isFinite, frame.minY.isFinite, frame.maxY.isFinite else { return nil }
        return frame
    }

    private static func activeDisplayBounds() -> [CGRect] {
        var identifiers = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(UInt32(identifiers.count), &identifiers, &count) == .success else { return [] }
        return identifiers.prefix(Int(count)).map(CGDisplayBounds).filter { !$0.isEmpty && !$0.isInfinite && !$0.isNull }
    }
}
#endif
