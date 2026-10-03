import AppKit
import Combine
import ColorSync
import QuartzCore
import SwiftUI

/// One presentation frame keeps the circle and its details on the same clock.
struct MacSideHoverPresentation: Equatable {
    var magnifications: [MetricKind: CGFloat] = [:]
    var expansion: CGFloat = 0

    func interpolated(to target: Self, progress: Double) -> Self {
        let progress = min(max(progress, 0), 1)
        guard progress < 1 else { return target }
        let eased = 1 - pow(1 - progress, 3)
        let metrics = Set(magnifications.keys).union(target.magnifications.keys)
        return Self(magnifications: Dictionary(uniqueKeysWithValues: metrics.map { metric in
            let from = magnifications[metric] ?? 1
            return (metric, from + ((target.magnifications[metric] ?? 1) - from) * eased)
        }), expansion: expansion + (target.expansion - expansion) * eased)
    }
}

@MainActor
final class MacWidgetController: ObservableObject {
    private static let sideHoverAnimationDuration: TimeInterval = 0.18

    @Published private(set) var selectedMetric: MetricKind?
    @Published private(set) var hoveredMetric: MetricKind? {
        didSet { if oldValue != hoveredMetric { updateMagnification() } }
    }
    @Published private(set) var sideHoverPresentation = MacSideHoverPresentation()
    @Published private(set) var selectionPosition: CGFloat = 0
    @Published private(set) var isExpanded = false
    @Published private(set) var displays: [MacDisplay] = []
    @Published private(set) var topInfo = MacTopNotchInfo()
    let store: ProfileStore
    let preferences: MacWidgetPreferences
    private var panel: MacWidgetPanel?
    private var settingsWindow: NSWindow?
    private var subscriptions = Set<AnyCancellable>()
    private var closeTask: Task<Void, Never>?
    private var intentTask: Task<Void, Never>?
    private var selectionTask: Task<Void, Never>?
    private var magnificationTask: Task<Void, Never>?
    private var isHovered = false
    private var suppressTopHoverUntilExit = false
    private var globalPointerMonitor: Any?
    private var localPointerMonitor: Any?
    private var animationPointerTimer: Timer?
    private var pointerInteraction = MacWidgetPointerInteraction()
    private var previousMetrics: [MetricKind]
    private var previousEdge: MacWidgetEdge
    private let reducesMotion: () -> Bool

    var activeMetrics: [MetricKind] {
        store.profile.macWidgetMetrics(for: preferences.edge)
    }

    var hoverScaleLimit: Double {
        preferences.magnifiesOnHover && preferences.edge != .top ? preferences.hoverScale : 1
    }

    var hoverMagnifications: [MetricKind: CGFloat] { sideHoverPresentation.magnifications }

    var sideHoverExpansion: CGFloat? {
        hoverScaleLimit > 1 ? sideHoverPresentation.expansion : nil
    }

    var indexedMagnifications: [Int: CGFloat] {
        Dictionary(uniqueKeysWithValues: activeMetrics.enumerated().compactMap { index, metric in
            hoverMagnifications[metric].map { (index, $0) }
        })
    }

    private func updateMagnification(animated: Bool = true) {
        magnificationTask?.cancel()
        var target = MacSideHoverPresentation(expansion: isExpanded ? 1 : 0)
        if hoverScaleLimit > 1, preferences.isVisible, let metric = hoveredMetric, activeMetrics.contains(metric) {
            target.magnifications = [metric: hoverScaleLimit]
        }
        guard animated, hoverScaleLimit > 1, !reducesMotion(),
              preferences.edge != .top, sideHoverPresentation != target else {
            if sideHoverPresentation != target { sideHoverPresentation = target }
            return
        }
        let origin = sideHoverPresentation
        let start = ProcessInfo.processInfo.systemUptime
        magnificationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let progress = min((ProcessInfo.processInfo.systemUptime - start) / Self.sideHoverAnimationDuration, 1)
                self.sideHoverPresentation = origin.interpolated(to: target, progress: progress)
                self.updatePointerAcceptance()
                if progress >= 1 { return }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    init(store: ProfileStore, preferences: MacWidgetPreferences,
         reducesMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }) {
        self.store = store
        self.preferences = preferences
        self.reducesMotion = reducesMotion
        previousMetrics = store.profile.macWidgetMetrics(for: preferences.edge)
        previousEdge = preferences.edge
        // Observe configuration independently of the panel's lifetime. Delivery
        // on the main queue reads the committed values after @Published willSet.
        preferences.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.synchronize(animated: true) }
            .store(in: &subscriptions)
        store.$profile.dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.synchronize(animated: true) }
            .store(in: &subscriptions)
    }

    func start() {
        guard panel == nil else { return }
        let window = MacWidgetPanel(contentRect: NSRect(origin: .zero, size: MacWidgetPlacement.railSize),
                                    styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.title = L10n.text("DaysYet タイムレール", "DaysYet time rail")
        window.isFloatingPanel = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.acceptsMouseMovedEvents = true
        window.isReleasedWhenClosed = false
        window.onCancel = { [weak self] in self?.closeDetails() }
        window.onPointerEvent = { [weak self] event in self?.handlePointerEvent(event) ?? false }
        window.contentView = NSHostingView(rootView: MacDesktopWidgetView(store: store, preferences: preferences, controller: self))
        panel = window
        installPointerMonitoring()

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.screenConfigurationChanged() }
            .store(in: &subscriptions)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.screenConfigurationChanged() }
            .store(in: &subscriptions)
        synchronize()
    }

    func showWidget() {
        preferences.isVisible = true
        synchronize()
    }

    func hideWidget() {
        preferences.isVisible = false
        synchronize()
    }

    func metricHoverChanged(_ metric: MetricKind, hovering: Bool) {
        // Top selection is driven by physical line geometry and proximity,
        // including pointer positions outside the tiny closed NSPanel.
        guard preferences.edge != .top, !pointerInteraction.isPressed else { return }
        if !hovering {
            if hoveredMetric == metric {
                hoveredMetric = nil
                intentTask?.cancel()
                intentTask = nil
            }
            return
        }
        beginMetricHover(metric)
    }

    private func beginMetricHover(_ metric: MetricKind) {
        guard !pointerInteraction.isPressed, activeMetrics.contains(metric) else { return }
        setHovered(true)
        guard hoveredMetric != metric else { return }
        hoveredMetric = metric
        intentTask?.cancel()
        intentTask = nil
        guard !isExpanded || selectedMetric != metric else { return }
        if hoverScaleLimit > 1 {
            showHoveredDetails(for: metric)
            return
        }
        let delay = isExpanded ? 80 : 160
        intentTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.intentTask = nil
            self.showHoveredDetails(for: metric)
        }
    }

    private func showHoveredDetails(for metric: MetricKind) {
        guard isHovered, hoveredMetric == metric, preferences.isVisible,
              !pointerInteraction.isPressed, activeMetrics.contains(metric) else { return }
        setSelection(metric)
        // Selection rechecks the pointer synchronously. Do not reopen a panel
        // after that check has moved the pointer out or onto another circle.
        guard isHovered, hoveredMetric == metric, preferences.isVisible,
              !pointerInteraction.isPressed, activeMetrics.contains(metric) else { return }
        setExpanded(true)
        updatePointerAcceptance()
    }

    func hoverChanged(_ hovering: Bool) {
        guard preferences.edge != .top, !pointerInteraction.isPressed else { return }
        setHovered(hovering)
    }

    func sideHoverChanged(inside: Bool, metric: MetricKind?) {
        guard preferences.edge != .top, !pointerInteraction.isPressed else { return }
        setHovered(inside)
        // The expanded surface and its circle share one hover state, including
        // the space between them. A directly hovered row still takes priority.
        let metric = metric ?? (isExpanded || (sideHoverExpansion ?? 0) > 0 ? selectedMetric : nil)
        if inside, let metric {
            beginMetricHover(metric)
        } else if hoveredMetric != nil {
            hoveredMetric = nil
            intentTask?.cancel()
            intentTask = nil
        }
    }

    private func setHovered(_ hovering: Bool) {
        guard hovering != isHovered else { return }
        isHovered = hovering
        closeTask?.cancel()
        if !hovering {
            hoveredMetric = nil
            intentTask?.cancel()
            intentTask = nil
        }
        if !hovering, !preferences.keepDetailsOpen {
            if hoverScaleLimit > 1 {
                setExpanded(false)
                return
            }
            closeTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled, let self, !self.isHovered, !self.preferences.keepDetailsOpen else { return }
                self.setExpanded(false)
            }
        }
    }

    func closeDetails() {
        closeTask?.cancel()
        intentTask?.cancel()
        intentTask = nil
        if preferences.edge == .top {
            suppressTopHoverUntilExit = true
            hoveredMetric = nil
        }
        preferences.keepDetailsOpen = false
        setExpanded(false)
    }

    func recenter() {
        preferences.verticalPosition = 0.5
        synchronize()
    }

    func resetPreferences() {
        pointerInteraction.cancel()
        closeTask?.cancel()
        intentTask?.cancel()
        intentTask = nil
        selectionTask?.cancel()
        isHovered = false
        hoveredMetric = nil
        suppressTopHoverUntilExit = false
        selectedMetric = nil
        selectionPosition = 0
        isExpanded = false
        preferences.reset()
        synchronize()
    }

    func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 660),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = L10n.text("DaysYet — 設定", "DaysYet — Settings")
            window.contentMinSize = NSSize(width: 700, height: 620)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: MacSettingsView(store: store, preferences: preferences, controller: self))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func setExpanded(_ expanded: Bool) {
        if !expanded { releasePanelFocus() }
        guard preferences.isVisible, isExpanded != expanded else { return }
        isExpanded = expanded
        updateMagnification()
        if !expanded { setSelection(selectedMetric) }
        positionPanel(animated: true)
    }

    private func releasePanelFocus() {
        guard let panel else { return }
        panel.allowsKeyboardFocus = false
        guard panel.isKeyWindow else { return }
        // Normal AppKit ordering releases a nonactivating panel's keyboard
        // focus. Returning it without making it key leaves the rail visible.
        panel.orderOut(nil)
        if preferences.isVisible { panel.orderFrontRegardless() }
    }

    private func setSelection(_ metric: MetricKind?, metrics: [MetricKind]? = nil, animated: Bool = true) {
        let metrics = metrics ?? activeMetrics
        let metric = metric.flatMap { metrics.contains($0) ? $0 : metrics.first }
        if selectedMetric != metric { selectedMetric = metric }
        let destination = CGFloat(metric.flatMap { metrics.firstIndex(of: $0) } ?? 0)
        selectionTask?.cancel()
        guard animated, isExpanded, preferences.edge != .top,
              !reducesMotion(),
              selectionPosition != destination else {
            if selectionPosition != destination { selectionPosition = destination }
            updatePointerAcceptance()
            return
        }
        // One interpolated position drives the contour, text, and hit testing,
        // so the interactive surface follows the visible movement exactly.
        let origin = selectionPosition
        let start = ProcessInfo.processInfo.systemUptime
        selectionTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let elapsed = (ProcessInfo.processInfo.systemUptime - start) / Self.sideHoverAnimationDuration
                let progress = min(max(elapsed, 0), 1)
                let eased = 1 - pow(1 - progress, 3)
                self.selectionPosition = origin + (destination - origin) * eased
                self.updatePointerAcceptance()
                if progress >= 1 { return }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    private func screenConfigurationChanged() {
        pointerInteraction.cancel()
        closeTask?.cancel()
        intentTask?.cancel()
        intentTask = nil
        isHovered = false
        hoveredMetric = nil
        suppressTopHoverUntilExit = false
        synchronize()
    }

    private func synchronize(animated: Bool = false) {
        let metricsChanged = reconcileMetricConfiguration()
        // Preference notifications already queued when the press began must
        // not animate the panel back to its previous saved position.
        if pointerInteraction.isPressed {
            guard !preferences.isVisible else { return }
            pointerInteraction.cancel()
        }
        displays = NSScreen.screens.map { MacDisplay(id: displayID(for: $0), name: $0.localizedName) }
        if preferences.isVisible {
            if hoverScaleLimit > 1, intentTask != nil, isHovered, let metric = hoveredMetric, activeMetrics.contains(metric) {
                // Enabling magnification during a deferred hover must not leave
                // the enlarged circle waiting for the old detail delay.
                intentTask?.cancel()
                intentTask = nil
                setSelection(metric)
                if isHovered, hoveredMetric == metric { isExpanded = true }
            }
            if !preferences.keepDetailsOpen { releasePanelFocus() }
            if preferences.keepDetailsOpen {
                if selectedMetric == nil { setSelection(activeMetrics.first) }
                isExpanded = true
            } else if !isHovered {
                isExpanded = false
                setSelection(selectedMetric)
            }
            // Settle against the committed selection before resizing the
            // reserved canvas, including when enabling a deferred hover.
            updateMagnification(animated: false)
            // A new row count or edge changes the coordinate system itself.
            // Apply that frame together with its selection and hit-test layout.
            positionPanel(animated: animated && !metricsChanged && panel?.isVisible == true)
            panel?.orderFrontRegardless()
            updatePointerAcceptance()
        } else {
            closeTask?.cancel()
            intentTask?.cancel()
            intentTask = nil
            animationPointerTimer?.invalidate()
            isHovered = false
            hoveredMetric = nil
            suppressTopHoverUntilExit = false
            isExpanded = false
            updateMagnification(animated: false)
            panel?.allowsKeyboardFocus = false
            panel?.orderOut(nil)
            setSelection(selectedMetric)
        }
    }

    @discardableResult
    private func reconcileMetricConfiguration() -> Bool {
        let metrics = activeMetrics
        guard previousMetrics != metrics || previousEdge != preferences.edge else { return false }
        previousMetrics = metrics
        previousEdge = preferences.edge
        // A queued hover or an in-flight row animation refers to the old list.
        // Settle the selection before the contour changes size or placement.
        intentTask?.cancel()
        intentTask = nil
        selectionTask?.cancel()
        closeTask?.cancel()
        pointerInteraction.cancel()
        hoveredMetric = nil
        isHovered = false
        suppressTopHoverUntilExit = false
        let selection = selectedMetric.flatMap { metrics.contains($0) ? $0 : nil } ?? metrics.first
        setSelection(selection, metrics: metrics, animated: false)
        return true
    }

    private var selectedScreen: NSScreen? {
        NSScreen.screens.first(where: { displayID(for: $0) == preferences.displayID }) ?? NSScreen.screens.first
    }

    private func displayID(for screen: NSScreen) -> String {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return "" }
        return CFUUIDCreateString(nil, uuid) as String
    }

    private func positionPanel(animated: Bool) {
        guard !pointerInteraction.isPressed, let screen = selectedScreen, let panel else { return }
        let info = MacTopNotchInfo.resolve(screenFrame: screen.frame, topInset: screen.safeAreaInsets.top,
                                           leftArea: screen.auxiliaryTopLeftArea ?? .zero,
                                           rightArea: screen.auxiliaryTopRightArea ?? .zero)
        if info != topInfo { topInfo = info }
        // Status-bar level covers the menu-bar strip, while system menus remain
        // above this panel. Side widgets retain normal floating-panel behavior.
        panel.level = preferences.edge == .top ? .statusBar : .floating
        panel.attachesToPhysicalTop = preferences.edge == .top
        let destination = MacWidgetPlacement.frame(in: screen.visibleFrame, edge: preferences.edge,
                                                   position: preferences.verticalPosition,
                                                   expanded: isExpanded || hoverScaleLimit > 1, scale: preferences.scale,
                                                   screenFrame: screen.frame, topInfo: info,
                                                   metricCount: activeMetrics.count,
                                                   hoverScale: hoverScaleLimit, detailScale: preferences.detailScale)
        animationPointerTimer?.invalidate()
        // Magnified side widgets keep a transparent canvas large enough for
        // the full transition. Its visible contour and text use the same
        // published presentation as the circle instead of a window animator.
        if animated && hoverScaleLimit == 1 && !reducesMotion() {
            let duration = isExpanded ? 0.24 : 0.18
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
                panel.animator().setFrame(destination, display: true)
            }
            // Track the changing contour even when the pointer is stationary.
            // This timer lives only for the short native resize animation.
            let deadline = Date.now.addingTimeInterval(duration + 0.04)
            animationPointerTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] timer in
                MainActor.assumeIsolated {
                    self?.updatePointerAcceptance()
                    if Date.now >= deadline { timer.invalidate() }
                }
            }
        } else {
            panel.setFrame(destination, display: true)
        }
        updatePointerAcceptance()
    }

    private func installPointerMonitoring() {
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        globalPointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePointerAcceptance() }
        }
        localPointerMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            MainActor.assumeIsolated { self?.updatePointerAcceptance() }
            return event
        }
    }

    private func updatePointerAcceptance() {
        guard let panel, panel.isVisible else { return }
        if pointerInteraction.isPressed {
            // Keep the mouse sequence even when a drag leaves the silhouette
            // or reaches the edge of the selected display.
            panel.ignoresMouseEvents = false
            return
        }
        let pointer = NSEvent.mouseLocation
        let local = CGPoint(x: pointer.x - panel.frame.minX, y: panel.frame.maxY - pointer.y)
        let inside = panel.frame.contains(pointer) && MacWidgetSurface.contains(local, in: panel.frame.size,
                                               edge: preferences.edge, selectedIndex: selectionPosition,
                                               scale: preferences.scale, topCameraInset: topInfo.cameraInset,
                                               topNotchWidth: topInfo.notchWidth, metricCount: activeMetrics.count,
                                               hoverScale: hoverScaleLimit, detailScale: preferences.detailScale,
                                               magnifications: indexedMagnifications, sideExpansion: sideHoverExpansion)
        // Transparent corners and the unused space beside the moving detail must
        // allow clicks to reach the application underneath the widget.
        panel.ignoresMouseEvents = !inside
        if preferences.edge == .top {
            let overCamera = MacWidgetSurface.topCameraHoverFrame(in: panel.frame.size,
                scale: preferences.scale, topCameraInset: topInfo.cameraInset,
                topNotchWidth: topInfo.notchWidth).contains(local)
            let index = MacWidgetSurface.topHoverIndex(at: local, in: panel.frame.size,
                scale: preferences.scale, topCameraInset: topInfo.cameraInset,
                topNotchWidth: topInfo.notchWidth, proximity: !isExpanded)
            let inHoverRegion = overCamera || index != nil
            if !inHoverRegion { suppressTopHoverUntilExit = false }
            setHovered(inside || inHoverRegion)
            if inHoverRegion, !suppressTopHoverUntilExit {
                let metrics = activeMetrics
                if let index, metrics.indices.contains(index) {
                    beginMetricHover(metrics[index])
                } else if overCamera, let metric = selectedMetric.flatMap({ metrics.contains($0) ? $0 : nil }) ?? metrics.first {
                    beginMetricHover(metric)
                }
            } else {
                hoveredMetric = nil
                intentTask?.cancel()
                intentTask = nil
            }
        } else {
            let index = MacWidgetSurface.sideHoverIndex(at: local, in: panel.frame.size,
                edge: preferences.edge, scale: preferences.scale, metricCount: activeMetrics.count,
                magnifications: indexedMagnifications)
            sideHoverChanged(inside: inside, metric: index.map { activeMetrics[$0] })
        }
    }

    private func handlePointerEvent(_ event: NSEvent) -> Bool {
        guard let panel, [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown].contains(event.type) else { return false }
        let pointer: NSPoint
        if let quartzEvent = event.cgEvent, let primaryScreen = NSScreen.screens.first {
            // Use the event's recorded global point: a busy main thread may
            // receive mouse-down only after the live pointer has already moved.
            pointer = MacWidgetPointerInteraction.appKitPoint(fromQuartz: quartzEvent.location,
                                                               primaryScreenMaxY: primaryScreen.frame.maxY)
        } else {
            pointer = event.window.map { $0.convertPoint(toScreen: event.locationInWindow) } ?? event.locationInWindow
        }
        switch event.type {
        case .leftMouseDown:
            guard !event.modifierFlags.contains(.control) else {
                pointerInteraction.cancel()
                return false
            }
            let local = CGPoint(x: pointer.x - panel.frame.minX, y: panel.frame.maxY - pointer.y)
            guard MacWidgetSurface.contains(local, in: panel.frame.size, edge: preferences.edge,
                    selectedIndex: selectionPosition, scale: preferences.scale,
                    topCameraInset: topInfo.cameraInset, topNotchWidth: topInfo.notchWidth,
                    metricCount: activeMetrics.count, hoverScale: hoverScaleLimit,
                    detailScale: preferences.detailScale, magnifications: indexedMagnifications,
                    sideExpansion: sideHoverExpansion) else { return false }
            animationPointerTimer?.invalidate()
            // Stop a resize already in flight before taking its drag anchor.
            let currentFrame = panel.frame
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                panel.animator().setFrame(currentFrame, display: true)
            }
            beginPointerPress(at: pointer, frame: currentFrame,
                bounds: preferences.edge == .top ? nil : selectedScreen?.visibleFrame,
                clickCount: event.clickCount, timestamp: event.timestamp)
            panel.ignoresMouseEvents = false
            return true
        case .leftMouseDragged:
            guard pointerInteraction.isPressed else { return false }
            if let placement = updatePointerPress(at: pointer) {
                panel.setFrame(placement.frame, display: true)
            }
            return true
        case .leftMouseUp:
            guard pointerInteraction.isPressed else { return false }
            let completion = finishPointerPress(at: pointer, doubleClickInterval: NSEvent.doubleClickInterval)
            if case .drag(let placement) = completion {
                panel.setFrame(placement.frame, display: true)
                preferences.verticalPosition = placement.position
            }
            synchronize()
            setSelection(selectedMetric)
            resumeMetricHover(at: NSEvent.mouseLocation)
            if completion == .openSettings { showSettings() }
            return true
        case .rightMouseDown:
            // A secondary click must not become the first half of a double click.
            if pointerInteraction.isPressed { return true }
            pointerInteraction.cancel()
            updatePointerAcceptance()
            return false
        default:
            return false
        }
    }

    func beginPointerPress(at point: NSPoint, frame: NSRect, bounds: NSRect?,
                           clickCount: Int, timestamp: TimeInterval) {
        closeTask?.cancel()
        intentTask?.cancel()
        intentTask = nil
        // A press is still a possible click. Keep the side circle enlarged
        // until movement establishes a drag, including between double clicks.
        if hoverScaleLimit <= 1 { hoveredMetric = nil }
        isHovered = true
        selectionTask?.cancel()
        magnificationTask?.cancel()
        pointerInteraction.begin(at: point, frame: frame, bounds: bounds,
            position: preferences.verticalPosition, clickCount: clickCount, timestamp: timestamp)
    }

    func updatePointerPress(at point: NSPoint) -> MacWidgetPointerInteraction.Placement? {
        let placement = pointerInteraction.update(at: point)
        if pointerInteraction.isDragging { hoveredMetric = nil }
        return placement
    }

    func finishPointerPress(at point: NSPoint, doubleClickInterval: TimeInterval) -> MacWidgetPointerInteraction.Completion {
        // Mouse-up can be the first event beyond the drag threshold.
        let completion = pointerInteraction.finish(at: point, doubleClickInterval: doubleClickInterval)
        if case .drag = completion { hoveredMetric = nil }
        return completion
    }

    private func resumeMetricHover(at pointer: NSPoint) {
        guard preferences.edge != .top, let panel, panel.isVisible else { return }
        let scale = MacWidgetPlacement.clampedScale(preferences.scale)
        let local = CGPoint(x: pointer.x - panel.frame.minX, y: panel.frame.maxY - pointer.y)
        let metrics = activeMetrics
        guard let index = MacWidgetSurface.sideHoverIndex(at: local, in: panel.frame.size,
                edge: preferences.edge, scale: scale, metricCount: metrics.count, magnifications: indexedMagnifications),
              MacWidgetSurface.contains(local, in: panel.frame.size,
                edge: preferences.edge, selectedIndex: selectionPosition, scale: scale,
                metricCount: metrics.count, hoverScale: hoverScaleLimit, detailScale: preferences.detailScale,
                magnifications: indexedMagnifications, sideExpansion: sideHoverExpansion) else { return }
        if metrics.indices.contains(index) { beginMetricHover(metrics[index]) }
    }

    deinit {
        if let globalPointerMonitor { NSEvent.removeMonitor(globalPointerMonitor) }
        if let localPointerMonitor { NSEvent.removeMonitor(localPointerMonitor) }
        animationPointerTimer?.invalidate()
        selectionTask?.cancel()
        magnificationTask?.cancel()
        closeTask?.cancel()
        intentTask?.cancel()
        intentTask = nil
    }
}

private final class MacWidgetPanel: NSPanel {
    var onCancel: (() -> Void)?
    var onPointerEvent: ((NSEvent) -> Bool)?
    var attachesToPhysicalTop = false
    var allowsKeyboardFocus = false
    // Hover resizes without activating; deliberate clicks can focus controls.
    override var canBecomeKey: Bool { allowsKeyboardFocus }
    override var canBecomeMain: Bool { false }
    override func sendEvent(_ event: NSEvent) {
        if onPointerEvent?(event) == true { return }
        super.sendEvent(event)
    }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        attachesToPhysicalTop ? frameRect : super.constrainFrameRect(frameRect, to: screen)
    }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() }
        else { super.keyDown(with: event) }
    }
}
