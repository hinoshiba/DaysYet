#if DAYSYET_DIRECT_DOCK_DRAG && DAYSYET_DOCK_NATIVE_REORDER
import AppKit
import ApplicationServices
import OSLog
import ScreenCaptureKit

struct MacDockCapturedSnapshot {
    let image: CGImage
    /// AppKit global coordinates, in points.
    let frame: NSRect
    let displayID: CGDirectDisplayID
    let screenFrame: NSRect
    let dockPID: pid_t
    let edge: MacWidgetEdge
}

enum MacDockSnapshotProcessPolicy {
    static func isSameLifetime(expectedPID: pid_t, currentPID: pid_t, retainedProcessTerminated: Bool,
                               initialLaunchDate: Date?, currentLaunchDate: Date?) -> Bool {
        guard expectedPID > 0, currentPID == expectedPID, !retainedProcessTerminated else { return false }
        // NSRunningApplication can omit launchDate for the real system Dock.
        // Its retained lifetime and verified PID/path remain mandatory; dates
        // add a consistency check only when both observations provide one.
        if let initialLaunchDate, let currentLaunchDate { return initialLaunchDate == currentLaunchDate }
        return true
    }
}

/// Geometry shared by the permission-gated provider and its noncapturing tests.
enum MacDockSnapshotGeometry {
    static let maximumPixels = 8_388_608
    static let maximumDimension = 16_384

    struct Item: Sendable {
        let frame: NSRect
        let isApplication: Bool
        let isTrash: Bool
    }

    struct DockBounds: Sendable {
        let listFrame: NSRect?
        let items: [Item]
    }

    struct Region: Equatable, Sendable {
        let frame: NSRect
        let sourceRect: CGRect
        let pixelWidth: Int
        let pixelHeight: Int
    }

    static func isFinite(_ frame: CGRect) -> Bool {
        [frame.origin.x, frame.origin.y, frame.size.width, frame.size.height,
         frame.maxX, frame.maxY].allSatisfy(\.isFinite)
            && frame.width > 0 && frame.height > 0
    }

    static func approximatelyEqual(_ first: CGRect, _ second: CGRect, tolerance: CGFloat = 1) -> Bool {
        isFinite(first) && isFinite(second)
            && abs(first.minX - second.minX) <= tolerance
            && abs(first.minY - second.minY) <= tolerance
            && abs(first.maxX - second.maxX) <= tolerance
            && abs(first.maxY - second.maxY) <= tolerance
    }

    static func quartzRect(_ frame: NSRect, primaryScreenMaxY: CGFloat) -> CGRect? {
        guard isFinite(frame), primaryScreenMaxY.isFinite else { return nil }
        let result = CGRect(x: frame.minX, y: primaryScreenMaxY - frame.maxY,
                            width: frame.width, height: frame.height)
        return isFinite(result) ? result : nil
    }

    static func region(bounds: DockBounds, layoutFrames: [NSRect], edge: MacWidgetEdge,
                       screenFrame: NSRect, primaryScreenMaxY: CGFloat, scale: CGFloat) -> Region? {
        guard edge != .top, isFinite(screenFrame), primaryScreenMaxY.isFinite,
              scale.isFinite, (1...4).contains(scale),
              (2...512).contains(bounds.items.count),
              (1...256).contains(layoutFrames.count),
              bounds.items.filter(\.isTrash).count == 1,
              layoutFrames.allSatisfy({ isFinite($0) && screenFrame.contains($0) }),
              bounds.items.allSatisfy({ isFinite($0.frame) && screenFrame.contains($0.frame) }) else { return nil }
        let applications = bounds.items.filter(\.isApplication).map(\.frame)
        guard applications.count == layoutFrames.count else { return nil }
        // A current layout must match every application in this exact AXList;
        // a second Dock/list or a partially hidden Dock cannot establish bounds.
        var unmatched = applications
        for frame in layoutFrames {
            let matches = unmatched.indices.filter { approximatelyEqual(unmatched[$0], frame, tolerance: 2) }
            guard matches.count == 1, let match = matches.first else { return nil }
            unmatched.remove(at: match)
        }
        guard unmatched.isEmpty, let first = bounds.items.first else { return nil }
        let itemUnion = bounds.items.dropFirst().reduce(first.frame) { $0.union($1.frame) }
        let horizontal = edge == .bottom
        let normalDepth = horizontal ? itemUnion.height : itemUnion.width
        let screenDepth = horizontal ? screenFrame.height : screenFrame.width
        guard normalDepth <= screenDepth * 0.25 else { return nil }

        var visibleBounds = itemUnion
        if let list = bounds.listFrame {
            guard isFinite(list) else { return nil }
            // Some Dock versions expose a full-display AXList. Its rectangle
            // is never a capture fallback: the complete visible item set,
            // including Trash, is still the only geometric authority there.
            let listDepth = horizontal ? list.height : list.width
            if screenFrame.contains(list), listDepth <= screenDepth * 0.25,
               list.insetBy(dx: -2, dy: -2).contains(itemUnion) {
                visibleBounds = visibleBounds.union(list)
            }
        }
        let padding = min(CGFloat(24), max(CGFloat(12), normalDepth * 0.2))
        let proposed: CGRect
        switch edge {
        case .bottom:
            proposed = CGRect(x: visibleBounds.minX - padding, y: screenFrame.minY,
                width: visibleBounds.width + padding * 2,
                height: visibleBounds.maxY + padding - screenFrame.minY)
        case .left:
            proposed = CGRect(x: screenFrame.minX, y: visibleBounds.minY - padding,
                width: visibleBounds.maxX + padding - screenFrame.minX,
                height: visibleBounds.height + padding * 2)
        case .right:
            proposed = CGRect(x: visibleBounds.minX - padding, y: visibleBounds.minY - padding,
                width: screenFrame.maxX - visibleBounds.minX + padding,
                height: visibleBounds.height + padding * 2)
        case .top:
            return nil
        }
        guard isFinite(proposed) else { return nil }
        let clipped = proposed.intersection(screenFrame)
        guard isFinite(clipped), clipped.contains(itemUnion),
              let quartz = quartzRect(clipped, primaryScreenMaxY: primaryScreenMaxY),
              let quartzScreen = quartzRect(screenFrame, primaryScreenMaxY: primaryScreenMaxY) else { return nil }
        let local = quartz.offsetBy(dx: -quartzScreen.minX, dy: -quartzScreen.minY)
        let minX = floor(local.minX * scale) / scale
        let minY = floor(local.minY * scale) / scale
        let maxX = ceil(local.maxX * scale) / scale
        let maxY = ceil(local.maxY * scale) / scale
        let source = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        let displayLocal = CGRect(origin: .zero, size: screenFrame.size)
        guard isFinite(source), displayLocal.contains(source),
              source.width * source.height <= screenFrame.width * screenFrame.height * 0.25,
              (horizontal ? source.height : source.width) <= screenDepth * 0.25 else { return nil }
        let width = Int((source.width * scale).rounded())
        let height = Int((source.height * scale).rounded())
        guard (1...maximumDimension).contains(width), (1...maximumDimension).contains(height),
              width <= maximumPixels / height else { return nil }
        let globalQuartz = source.offsetBy(dx: quartzScreen.minX, dy: quartzScreen.minY)
        let frame = NSRect(x: globalQuartz.minX, y: primaryScreenMaxY - globalQuartz.maxY,
                           width: globalQuartz.width, height: globalQuartz.height)
        guard screenFrame.contains(frame) else { return nil }
        return Region(frame: frame, sourceRect: source, pixelWidth: width, pixelHeight: height)
    }
}

/// The caller opts in before calling capture. Construction performs no capture,
/// enumeration, permission query, UI work, or filesystem/network access.
@MainActor
final class MacDockSnapshotCapture {
    /// Fixed identifiers only: never interpolate captured pixels, window
    /// titles, other applications, paths, or framework error descriptions.
    private enum FailureStage: String {
        case request = "authorization-or-stale-request"
        case environment = "environment"
        case preparedEnvironment = "prepared-environment"
        case preparedIdentity = "prepared-identity"
        case bounds = "dock-bounds"
        case boundsEnvironment = "bounds-environment"
        case shareableContent = "shareable-content"
        case shareableEnvironment = "shareable-content-environment"
        case display = "display-match"
        case ownApplication = "own-exclusion-app"
        case dockWindow = "dock-window-layer-match"
        case scale = "display-scale"
        case beforeCaptureEnvironment = "pre-capture-environment"
        case beforeCaptureBounds = "pre-capture-bounds"
        case beforeCaptureStale = "pre-capture-stale-region"
        case capture = "image-capture"
        case afterCaptureEnvironment = "post-capture-environment"
        case afterCaptureBounds = "post-capture-bounds"
        case afterCaptureStale = "post-capture-stale-region"
        case imageEnvironment = "image-validation-environment"
        case dimensions = "pixel-dimensions"
        case opacity = "image-opacity"
    }

    private static let log = Logger(subsystem: "com.hinoshiba.daysyet", category: "dock-snapshot")

    private static func failed<T>(_ stage: FailureStage) -> T? {
        log.notice("capture rejected stage=\(stage.rawValue, privacy: .public)")
        return nil
    }

    struct PreparedCapture {
        let region: MacDockSnapshotGeometry.Region
        let displayID: CGDirectDisplayID
        let screenFrame: NSRect
        let dockPID: pid_t
        let edge: MacWidgetEdge
        let environmentIsCurrent: @MainActor () -> Bool
        let captureImage: @MainActor () async -> CGImage?
    }

    struct Dependencies {
        let permission: @MainActor () -> Bool
        let prepare: @MainActor (MacDockNativeLayout, @escaping @MainActor () -> Bool) async -> PreparedCapture?
    }

    private let dependencies: Dependencies
    private static let metadataQueue = DispatchQueue(label: "com.hinoshiba.daysyet.dock-snapshot-metadata", qos: .userInitiated)
    private static let imageQueue = DispatchQueue(label: "com.hinoshiba.daysyet.dock-snapshot-image", qos: .userInitiated)

    init() {
        dependencies = Dependencies(permission: { Self.isGranted() }, prepare: { layout, mayContinue in
            await Self.prepare(layout: layout, mayContinue: mayContinue)
        })
    }

    /// Test seam: injected providers never require TCC, AX, or real pixels.
    init(dependencies: Dependencies) { self.dependencies = dependencies }

    static func isGranted() -> Bool { CGPreflightScreenCaptureAccess() }

    /// Only an explicit user-facing permission button may call this method.
    /// Neither capture nor any failure/retry path requests access.
    static func requestAccess() -> Bool { CGRequestScreenCaptureAccess() }

    func capture(layout: MacDockNativeLayout,
                 isCurrent: @escaping @MainActor () -> Bool) async -> MacDockCapturedSnapshot? {
        let permission = dependencies.permission
        let mayContinue: @MainActor () -> Bool = {
            !Task.isCancelled && isCurrent() && permission()
        }
        guard mayContinue() else { return Self.failed(.request) }
        guard let prepared = await dependencies.prepare(layout, mayContinue) else { return nil }
        guard mayContinue(), prepared.environmentIsCurrent() else { return Self.failed(.preparedEnvironment) }
        guard prepared.dockPID == layout.dockPID, prepared.edge == layout.edge else { return Self.failed(.preparedIdentity) }
        guard mayContinue() else { return Self.failed(.request) }
        guard let captured = await prepared.captureImage() else { return nil }
        guard mayContinue(), prepared.environmentIsCurrent() else { return Self.failed(.afterCaptureEnvironment) }
        guard captured.width == prepared.region.pixelWidth,
              captured.height == prepared.region.pixelHeight else { return Self.failed(.dimensions) }
        let image = await Self.opaqueImage(captured)
        guard mayContinue(), prepared.environmentIsCurrent() else { return Self.failed(.imageEnvironment) }
        guard let image else { return Self.failed(.opacity) }
        Self.log.notice("capture ready")
        return MacDockCapturedSnapshot(image: image, frame: prepared.region.frame,
            displayID: prepared.displayID, screenFrame: prepared.screenFrame,
            dockPID: prepared.dockPID, edge: prepared.edge)
    }

    private struct ScreenState: Equatable {
        let id: CGDirectDisplayID
        let frame: NSRect
        let scale: CGFloat
    }

    private struct Environment {
        let dock: NSRunningApplication
        let dockPID: pid_t
        let launchDate: Date?
        let edge: MacWidgetEdge
        let screens: [ScreenState]
        let screen: ScreenState
        let primaryMaxY: CGFloat
    }

    private static func screens() -> [ScreenState]? {
        let all = NSScreen.screens
        guard !all.isEmpty else { return nil }
        let result = all.compactMap { screen -> ScreenState? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  MacDockSnapshotGeometry.isFinite(screen.frame), screen.backingScaleFactor.isFinite,
                  (1...4).contains(screen.backingScaleFactor) else { return nil }
            return ScreenState(id: number.uint32Value, frame: screen.frame, scale: screen.backingScaleFactor)
        }
        return result.count == all.count && Set(result.map(\.id)).count == result.count ? result : nil
    }

    private static func verifiedDock(pid: pid_t) -> NSRunningApplication? {
        guard pid > 0, let dock = NSRunningApplication(processIdentifier: pid), !dock.isTerminated,
              dock.bundleIdentifier == "com.apple.dock",
              dock.bundleURL?.standardizedFileURL.path == "/System/Library/CoreServices/Dock.app" else { return nil }
        return dock
    }

    private static func currentEdge() -> MacWidgetEdge? {
        guard CFPreferencesAppSynchronize("com.apple.dock" as CFString) else { return nil }
        let orientation = CFPreferencesCopyAppValue("orientation" as CFString, "com.apple.dock" as CFString) as? String
        return MacSystemDockLocation.configuredEdge(orientation: orientation)
    }

    private static func environment(layout: MacDockNativeLayout) -> Environment? {
        guard layout.edge != .top, AXIsProcessTrusted(), !layout.items.isEmpty,
              let dock = verifiedDock(pid: layout.dockPID),
              currentEdge() == layout.edge, let all = screens(), let primary = all.first else { return nil }
        let matching = all.filter { screen in
            layout.items.allSatisfy { MacDockSnapshotGeometry.isFinite($0.frame) && screen.frame.contains($0.frame) }
        }
        guard matching.count == 1, let screen = matching.first,
              let quartzScreen = MacDockSnapshotGeometry.quartzRect(screen.frame, primaryScreenMaxY: primary.frame.maxY),
              MacDockSnapshotGeometry.approximatelyEqual(CGDisplayBounds(screen.id), quartzScreen) else { return nil }
        return Environment(dock: dock, dockPID: layout.dockPID, launchDate: dock.launchDate, edge: layout.edge,
            screens: all, screen: screen, primaryMaxY: primary.frame.maxY)
    }

    private static func matches(_ environment: Environment) -> Bool {
        guard AXIsProcessTrusted(), let dock = verifiedDock(pid: environment.dockPID),
              environment.dock.processIdentifier == environment.dockPID,
              environment.dock.bundleIdentifier == "com.apple.dock",
              environment.dock.bundleURL?.standardizedFileURL.path == "/System/Library/CoreServices/Dock.app",
              MacDockSnapshotProcessPolicy.isSameLifetime(expectedPID: environment.dockPID,
                currentPID: dock.processIdentifier, retainedProcessTerminated: environment.dock.isTerminated,
                initialLaunchDate: environment.launchDate, currentLaunchDate: dock.launchDate),
              screens() == environment.screens,
              currentEdge() == environment.edge else { return false }
        return true
    }

    private static func prepare(layout: MacDockNativeLayout,
                                mayContinue: @escaping @MainActor () -> Bool) async -> PreparedCapture? {
        guard mayContinue() else { return failed(.request) }
        guard let environment = environment(layout: layout) else { return failed(.environment) }
        let layoutFrames = layout.items.map(\.frame)
        guard let region = await readRegion(environment: environment, layoutFrames: layoutFrames) else { return failed(.bounds) }
        guard mayContinue(), matches(environment) else { return failed(.boundsEnvironment) }
        // This is the first ScreenCaptureKit call. The permission guard must
        // stay immediately before enumeration, which can otherwise prompt.
        guard mayContinue() else { return failed(.request) }
        let content: SCShareableContent
        do { content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) }
        catch { return failed(.shareableContent) }
        guard mayContinue(), matches(environment) else { return failed(.shareableEnvironment) }
        guard let display = content.displays.first(where: { $0.displayID == environment.screen.id }),
              let quartzScreen = MacDockSnapshotGeometry.quartzRect(environment.screen.frame,
                    primaryScreenMaxY: environment.primaryMaxY),
              MacDockSnapshotGeometry.approximatelyEqual(display.frame, quartzScreen),
              // SCDisplay.width/height are logical points (SCShareableContent.h),
              // unlike SCStreamConfiguration.width/height, which are pixels.
              abs(CGFloat(display.width) - environment.screen.frame.width) <= 1,
              abs(CGFloat(display.height) - environment.screen.frame.height) <= 1 else { return failed(.display) }
        guard let ownApplication = content.applications.first(where: { $0.processID == getpid() }) else { return failed(.ownApplication) }
        guard let quartzRegion = MacDockSnapshotGeometry.quartzRect(region.frame,
            primaryScreenMaxY: environment.primaryMaxY) else { return failed(.bounds) }
        let dockLayer = Int(CGWindowLevelForKey(.dockWindow))
        guard content.windows.contains(where: { window in
            window.isOnScreen && window.owningApplication?.processID == environment.dockPID
                && window.owningApplication?.bundleIdentifier == "com.apple.dock"
                && window.windowLayer == dockLayer
                && MacDockSnapshotGeometry.isFinite(window.frame)
                && window.frame.intersects(quartzRegion)
        }) else { return failed(.dockWindow) }
        // Display exclusion retains the composited Dock and desktop. Including
        // only the Dock app/window does not provide that composition guarantee.
        let filter = SCContentFilter(display: display, excludingApplications: [ownApplication], exceptingWindows: [])
        guard abs(CGFloat(filter.pointPixelScale) - environment.screen.scale) < 0.001 else { return failed(.scale) }
        let config = SCStreamConfiguration()
        config.sourceRect = region.sourceRect
        config.width = region.pixelWidth
        config.height = region.pixelHeight
        config.destinationRect = CGRect(x: 0, y: 0, width: region.pixelWidth, height: region.pixelHeight)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.capturesAudio = false
        config.ignoreShadowsDisplay = false
        config.ignoreGlobalClipDisplay = false
        config.shouldBeOpaque = false // true fills transparent pixels with white.
        if #available(macOS 15.0, *) { config.captureMicrophone = false; config.showMouseClicks = false }
        if #available(macOS 14.2, *) { filter.includeMenuBar = false }
        return PreparedCapture(region: region, displayID: display.displayID,
            screenFrame: environment.screen.frame, dockPID: environment.dockPID, edge: environment.edge,
            environmentIsCurrent: { matches(environment) }, captureImage: {
                guard mayContinue(), matches(environment) else { return failed(.beforeCaptureEnvironment) }
                guard let before = await readRegion(environment: environment, layoutFrames: layoutFrames) else { return failed(.beforeCaptureBounds) }
                guard mayContinue(), matches(environment) else { return failed(.beforeCaptureEnvironment) }
                guard before == region else { return failed(.beforeCaptureStale) }
                // No default/empty sourceRect is ever passed to this API.
                guard mayContinue() else { return failed(.request) }
                let image: CGImage
                do { image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) }
                catch { return failed(.capture) }
                guard mayContinue(), matches(environment) else { return failed(.afterCaptureEnvironment) }
                guard let after = await readRegion(environment: environment, layoutFrames: layoutFrames) else { return failed(.afterCaptureBounds) }
                guard mayContinue(), matches(environment) else { return failed(.afterCaptureEnvironment) }
                guard after == region else { return failed(.afterCaptureStale) }
                return image
            })
    }

    private static func readRegion(environment: Environment, layoutFrames: [NSRect]) async -> MacDockSnapshotGeometry.Region? {
        let pid = environment.dockPID
        let maxY = environment.primaryMaxY
        let bounds = await withCheckedContinuation { continuation in
            metadataQueue.async {
                continuation.resume(returning: DockBoundsReader.read(pid: pid, primaryMaxY: maxY))
            }
        }
        guard let bounds else { return nil }
        let regions = bounds.compactMap { candidate in
            MacDockSnapshotGeometry.region(bounds: candidate, layoutFrames: layoutFrames,
                edge: environment.edge, screenFrame: environment.screen.frame,
                primaryScreenMaxY: maxY, scale: environment.screen.scale)
        }
        return regions.count == 1 ? regions.first : nil
    }

    private static func opaqueImage(_ image: CGImage) async -> CGImage? {
        await withCheckedContinuation { continuation in
            imageQueue.async { continuation.resume(returning: Self.validatedOpaqueImage(image)) }
        }
    }

    /// An alpha channel is acceptable only when every captured pixel is opaque.
    /// Never invent a white/black background to conceal a failed composition.
    nonisolated static func validatedOpaqueImage(_ image: CGImage) -> CGImage? {
        guard image.width > 0, image.height > 0,
              image.width <= MacDockSnapshotGeometry.maximumDimension,
              image.height <= MacDockSnapshotGeometry.maximumDimension,
              image.width <= MacDockSnapshotGeometry.maximumPixels / image.height,
              let colorSpace = image.colorSpace, colorSpace.model == .rgb else { return nil }
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return image
        case .premultipliedFirst, .premultipliedLast, .first, .last:
            break
        default:
            return nil
        }
        let bytesPerRow = image.width * 4
        var bytes = Data(count: bytesPerRow * image.height)
        let valid = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let context = CGContext(data: base, width: image.width, height: image.height,
                    bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.setBlendMode(.copy)
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let samples = raw.bindMemory(to: UInt8.self)
            for alpha in stride(from: 3, to: samples.count, by: 4) where samples[alpha] != 255 { return false }
            return true
        }
        guard valid, let provider = CGDataProvider(data: bytes as CFData) else { return nil }
        return CGImage(width: image.width, height: image.height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: bytesPerRow, space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: image.renderingIntent)
    }
}

/// This reader exposes geometry/subroles only. Other apps' names and URLs are
/// neither requested nor retained, and all AX interaction is read-only.
private enum DockBoundsReader {
    private struct Node { let element: AXUIElement; let depth: Int }
    private struct Budget {
        let deadline = ProcessInfo.processInfo.systemUptime + 0.30
        var calls = 512
        mutating func consume() -> Bool {
            defer { calls -= 1 }
            return calls > 0 && ProcessInfo.processInfo.systemUptime < deadline
        }
    }

    static func read(pid: pid_t, primaryMaxY: CGFloat) -> [MacDockSnapshotGeometry.DockBounds]? {
        guard pid > 0, primaryMaxY.isFinite, AXIsProcessTrusted() else { return nil }
        let root = AXUIElementCreateApplication(pid)
        guard AXUIElementSetMessagingTimeout(root, 0.015) == .success else { return nil }
        var budget = Budget()
        var queue = [Node(element: root, depth: 0)]
        var cursor = 0
        var result: [MacDockSnapshotGeometry.DockBounds] = []
        while cursor < queue.count {
            guard queue.count <= 512, budget.consume() else { return nil }
            let node = queue[cursor]; cursor += 1
            guard let role = attribute(node.element, kAXRoleAttribute as CFString) as? String else { return nil }
            if role == kAXListRole as String {
                guard let value = list(node.element, pid: pid, primaryMaxY: primaryMaxY, budget: &budget) else { return nil }
                if !value.items.isEmpty { result.append(value) }
                continue
            }
            guard node.depth < 4 else { continue }
            guard budget.consume(), let children = children(node.element) else { return nil }
            queue.append(contentsOf: children.map { Node(element: $0, depth: node.depth + 1) })
        }
        return result.isEmpty ? nil : result
    }

    private static func list(_ element: AXUIElement, pid: pid_t, primaryMaxY: CGFloat,
                             budget: inout Budget) -> MacDockSnapshotGeometry.DockBounds? {
        guard budget.consume(), let initial = children(element) else { return nil }
        let listFrame = frame(element, primaryMaxY: primaryMaxY, budget: &budget)
        var queue = initial.map { Node(element: $0, depth: 0) }
        var cursor = 0
        var items: [MacDockSnapshotGeometry.Item] = []
        while cursor < queue.count {
            guard queue.count <= 512, budget.consume() else { return nil }
            let node = queue[cursor]; cursor += 1
            var owner: pid_t = 0
            guard AXUIElementGetPid(node.element, &owner) == .success, owner == pid else { return nil }
            let names = [kAXRoleAttribute, kAXSubroleAttribute, kAXHiddenAttribute, kAXPositionAttribute, kAXSizeAttribute]
            var raw: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(node.element, names as CFArray, [], &raw) == .success,
                  let raw, CFArrayGetCount(raw) == names.count else { return nil }
            let values = raw as [AnyObject]
            guard let role = values[0] as? String else { return nil }
            if values[2] as? Bool == true { continue }
            let subrole = values[1] as? String
            let isDockItem = role == kAXDockItemRole as String
                || subrole?.hasSuffix("DockItem") == true
            if isDockItem {
                guard let rect = frame(position: values[3], size: values[4], primaryMaxY: primaryMaxY) else { return nil }
                items.append(.init(frame: rect,
                    isApplication: subrole == kAXApplicationDockItemSubrole as String,
                    isTrash: subrole == kAXTrashDockItemSubrole as String))
            } else if node.depth < 3 {
                guard budget.consume(), let childNodes = children(node.element) else { return nil }
                queue.append(contentsOf: childNodes.map { Node(element: $0, depth: node.depth + 1) })
            }
        }
        return MacDockSnapshotGeometry.DockBounds(listFrame: listFrame, items: items)
    }

    private static func attribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name, &value) == .success ? value : nil
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
        if error == .attributeUnsupported || error == .noValue { return [] }
        guard error == .success, let children = value as? [AXUIElement], children.count <= 256 else { return nil }
        return children
    }

    private static func frame(_ element: AXUIElement, primaryMaxY: CGFloat, budget: inout Budget) -> NSRect? {
        guard budget.consume() else { return nil }
        var raw: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element,
            [kAXPositionAttribute, kAXSizeAttribute] as CFArray, [], &raw) == .success,
              let raw, CFArrayGetCount(raw) == 2 else { return nil }
        let values = raw as [AnyObject]
        return frame(position: values[0], size: values[1], primaryMaxY: primaryMaxY)
    }

    private static func frame(position: CFTypeRef, size: CFTypeRef, primaryMaxY: CGFloat) -> NSRect? {
        guard CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        let positionValue = position as! AXValue
        let sizeValue = size as! AXValue
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetType(positionValue) == .cgPoint, AXValueGetType(sizeValue) == .cgSize,
              AXValueGetValue(positionValue, .cgPoint, &point), AXValueGetValue(sizeValue, .cgSize, &dimensions) else { return nil }
        let rect = NSRect(x: point.x, y: primaryMaxY - point.y - dimensions.height,
                          width: dimensions.width, height: dimensions.height)
        return MacDockSnapshotGeometry.isFinite(rect) ? rect : nil
    }
}
#endif
