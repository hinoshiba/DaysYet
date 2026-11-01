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
    private(set) var dragPresentation: MacWidgetPointerInteraction.Placement?
    private(set) var dragOrigin: MacWidgetDragOrigin?
    private(set) var dragVisual: MacWidgetDragVisual?
    private(set) var dragAttachment: MacWidgetDropTarget?
    private(set) var dockLandingVisual: MacSystemDockLandingVisual?
    private(set) var isDockLanding = false
    private(set) var isHandingOffToEdge = false
    let store: ProfileStore
    let preferences: MacWidgetPreferences
    var showsEdgeWidget: Bool { preferences.isVisible && !preferences.isInSystemDock }
    var isChangingPlacement: Bool { pointerInteraction.isPressed || isSettling }
    var currentSystemDockEdge: MacWidgetEdge? {
        selectedScreen.map { MacSystemDockLocation.resolve(on: $0, fallback: preferences.lastSystemDockEdge) }
    }
    var nativeDockDragChanged: ((Bool) -> Void)?
    var nativeDockReturnFrame: ((MetricKind) -> NSRect?)?
    var nativeDockFrames: (() -> [MetricKind: NSRect]?)?
    var systemDockLandingChanged: ((Bool) -> Void)?
    weak var setupController: MacSetupController?
#if DAYSYET_DIRECT_DOCK_DRAG
    var directDockDrag: MacDockDirectDragController?
#endif
    private var panel: MacWidgetPanel?
    private var nativeDockInputPanel: NSPanel?
    private var dockGroupPanel: MacWidgetPanel?
    private var dockGroupScreen: NSScreen?
    private var dockGroupEdge: MacWidgetEdge = .bottom
    private var dockGroupAnchor = NSPoint.zero
    private var dockGroupFrame = NSRect.zero
    private var dragDisplayID: String?
    private var eventOwningPanel: NSPanel? {
        if dragOrigin?.isNativeDock == true { return nativeDockInputPanel }
        return dragOrigin?.isSystemDock == true ? dockGroupPanel : panel
    }
    var hasNativeDockPress: Bool { dragOrigin?.isNativeDock == true && pointerInteraction.isPressed }

    /// Losing permission, the source display or the Dock must release input
    /// immediately, rather than animating toward a stale native icon.
    func abortNativeDockDrag() {
        guard dragOrigin?.isNativeDock == true else { return }
        pointerInteraction.cancel()
        clearDragPresentation()
        synchronize()
    }
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
    private var dragOverlay: MacWidgetPanel?
    private var dragOverlayHost: NSHostingView<MacWidgetDragOverlay>?
    private var settleTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?
    private var attachmentTask: Task<Void, Never>?
    private var dragPreviewEdge: MacWidgetEdge?
    private var dragPreviewImages: [MacWidgetEdge: NSImage] = [:]
    private var dragDocking: MacWidgetDocking?
    private var dragWidgetImage: NSImage?
    private var dockLandingImages: [MetricKind: NSImage] = [:]
    private var dragMetricSnapshot: MetricSnapshot?
    private var dragAccent = Color.clear
    private var isSettling = false
    private var hasDragCursor = false
    private var previousMetrics: [MetricKind]
    private var previousEdge: MacWidgetEdge
    private let reducesMotion: () -> Bool

    var activeMetrics: [MetricKind] {
        preferences.isInSystemDock ? store.profile.macDashboardMetrics : store.profile.macWidgetMetrics(for: preferences.edge)
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

    func showDockGroup(fromDock: Bool = true) {
        guard preferences.isVisible, preferences.isInSystemDock,
              !pointerInteraction.isPressed, !isSettling else { return }
        var point = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? selectedScreen else { return }
        dockGroupScreen = screen
        dockGroupEdge = MacSystemDockLocation.resolve(on: screen, dockClick: fromDock ? point : nil,
                                                     fallback: preferences.lastSystemDockEdge)
        if !fromDock {
            switch dockGroupEdge {
            case .left: point = NSPoint(x: screen.frame.minX, y: screen.frame.midY)
            case .right: point = NSPoint(x: screen.frame.maxX, y: screen.frame.midY)
            case .bottom, .top: point = NSPoint(x: screen.frame.midX, y: screen.frame.minY)
            }
        }
        dockGroupAnchor = point
        preferences.lastSystemDockEdge = dockGroupEdge
        let window: MacWidgetPanel
        if let existing = dockGroupPanel {
            window = existing
        } else {
            window = MacWidgetPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.title = L10n.text("DaysYet — Dockグループ", "DaysYet — Dock group")
            window.isFloatingPanel = true
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.hidesOnDeactivate = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.isReleasedWhenClosed = false
            window.allowsKeyboardFocus = true
            window.onCancel = { [weak self] in self?.closeDetails() }
            window.onPointerEvent = { [weak self] in self?.handleDockGroupPointerEvent($0) ?? false }
            dockGroupPanel = window
        }
        window.contentView = NSHostingView(rootView: dockGroupView())
        positionDockGroup()
        window.alphaValue = reducesMotion() ? 1 : 0
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if !reducesMotion() {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                window.animator().alphaValue = 1
            }
        }
    }

    private func dockGroupView(edge: MacWidgetEdge? = nil, landing: Bool = false) -> MacSystemDockGroupView {
        MacSystemDockGroupView(store: store, preferences: preferences, edge: edge ?? dockGroupEdge, landing: landing,
            openSettings: { [weak self] in self?.closeDockGroup(); self?.showSettings() },
            returnToEdge: { [weak self] in self?.preferences.returnToScreenEdge() })
    }

    private func positionDockGroup() {
        guard let screen = dockGroupScreen, let window = dockGroupPanel else { return }
        let layout = MacSystemDockGroupLayout(edge: dockGroupEdge, count: store.profile.macDashboardMetrics.count, scale: preferences.scale)
        dockGroupFrame = layout.frame(near: dockGroupAnchor, screen: screen.frame, visible: screen.visibleFrame)
        window.setFrame(dockGroupFrame, display: true)
    }

    private func closeDockGroup() {
        guard !pointerInteraction.isPressed else { return }
        dockGroupPanel?.orderOut(nil)
    }

    private func docking(on screen: NSScreen, edge: MacWidgetEdge) -> MacWidgetDocking {
        let info = MacTopNotchInfo.resolve(screenFrame: screen.frame, topInset: screen.safeAreaInsets.top,
            leftArea: screen.auxiliaryTopLeftArea ?? .zero, rightArea: screen.auxiliaryTopRightArea ?? .zero)
        let dockEdge = MacSystemDockLocation.resolve(on: screen, fallback: preferences.lastSystemDockEdge)
        preferences.lastSystemDockEdge = dockEdge
        return MacWidgetDocking(edge: edge, screenFrame: screen.frame, visibleFrame: screen.visibleFrame,
            topInfo: info, scale: preferences.scale, metricCount: store.profile.macDashboardMetrics.count,
            detailScale: preferences.detailScale, systemDockEdge: dockEdge)
    }

    func metricHoverChanged(_ metric: MetricKind, hovering: Bool) {
        // Top selection is driven by physical line geometry and proximity,
        // including pointer positions outside the tiny closed NSPanel.
        guard preferences.edge != .top, !pointerInteraction.isPressed, !isSettling else { return }
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
        guard !pointerInteraction.isPressed, !isSettling, activeMetrics.contains(metric) else { return }
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
              !pointerInteraction.isPressed, !isSettling, activeMetrics.contains(metric) else { return }
        setSelection(metric)
        // Selection rechecks the pointer synchronously. Do not reopen a panel
        // after that check has moved the pointer out or onto another circle.
        guard isHovered, hoveredMetric == metric, preferences.isVisible,
              !pointerInteraction.isPressed, !isSettling, activeMetrics.contains(metric) else { return }
        setExpanded(true)
        updatePointerAcceptance()
    }

    func hoverChanged(_ hovering: Bool) {
        guard preferences.edge != .top, !pointerInteraction.isPressed, !isSettling else { return }
        setHovered(hovering)
    }

    func sideHoverChanged(inside: Bool, metric: MetricKind?) {
        guard preferences.edge != .top, !pointerInteraction.isPressed, !isSettling else { return }
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
        if pointerInteraction.isPressed || isSettling {
            cancelPointerDrag()
            return
        }
        if dockGroupPanel?.isVisible == true {
            closeDockGroup()
            return
        }
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
        if preferences.edge == .bottom { preferences.horizontalPosition = 0.5 }
        else { preferences.verticalPosition = 0.5 }
        synchronize()
    }

    func resetPreferences() {
        pointerInteraction.cancel()
        clearDragPresentation()
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
        setupController?.resetCompletion()
        synchronize()
    }

    func showSettings() {
        fputs("DIAGNOSTIC showSettings active=\(NSApp.isActive) visible=\(settingsWindow?.isVisible.description ?? "nil") minimized=\(settingsWindow?.isMiniaturized.description ?? "nil")\n", stderr)
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
        clearDragPresentation()
        closeDockGroup()
        closeTask?.cancel()
        intentTask?.cancel()
        intentTask = nil
        isHovered = false
        hoveredMetric = nil
        suppressTopHoverUntilExit = false
        synchronize()
    }

    private func synchronize(animated: Bool = false, preservingDrag: Bool = false) {
        if isSettling && !preservingDrag {
            guard !preferences.isVisible else { return }
            clearDragPresentation()
        }
        let metricsChanged = reconcileMetricConfiguration(preservingDrag: preservingDrag)
        // Preference notifications already queued when the press began must
        // not animate the panel back to its previous saved position.
        if pointerInteraction.isPressed {
            let sourceStillVisible = preferences.isVisible && (dragOrigin?.isSystemDock == true
                ? preferences.isInSystemDock : !preferences.isInSystemDock)
            guard !sourceStillVisible else { return }
            pointerInteraction.cancel()
            clearDragPresentation()
        }
        displays = NSScreen.screens.map { MacDisplay(id: displayID(for: $0), name: $0.localizedName) }
        if !preferences.isVisible || !preferences.isInSystemDock { closeDockGroup() }
        else if dockGroupPanel?.isVisible == true, !isSettling { positionDockGroup() }
        if showsEdgeWidget {
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
            positionPanel(animated: animated && !metricsChanged && panel?.isVisible == true, preservingDrag: preservingDrag)
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
    private func reconcileMetricConfiguration(preservingDrag: Bool = false) -> Bool {
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
        if !preservingDrag { clearDragPresentation() }
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

    private func positionPanel(animated: Bool, preservingDrag: Bool = false) {
        guard !pointerInteraction.isPressed, !isSettling || preservingDrag, let screen = selectedScreen, let panel else { return }
        let info = MacTopNotchInfo.resolve(screenFrame: screen.frame, topInset: screen.safeAreaInsets.top,
                                           leftArea: screen.auxiliaryTopLeftArea ?? .zero,
                                           rightArea: screen.auxiliaryTopRightArea ?? .zero)
        if info != topInfo { topInfo = info }
        // Status-bar level covers the menu-bar strip, while system menus remain
        // above this panel. Side widgets retain normal floating-panel behavior.
        panel.level = preferences.edge == .top ? .statusBar : .floating
        panel.attachesToPhysicalEdge = preferences.edge == .top || preferences.edge == .bottom
        let destination = MacWidgetPlacement.frame(in: screen.visibleFrame, edge: preferences.edge,
                                                   position: preferences.edge == .bottom ? preferences.horizontalPosition : preferences.verticalPosition,
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
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        globalPointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: events.union(clicks)) { [weak self] event in
            MainActor.assumeIsolated {
                if event.type == .leftMouseDown || event.type == .rightMouseDown { self?.closeDockGroup() }
                self?.updatePointerAcceptance()
            }
        }
        localPointerMonitor = NSEvent.addLocalMonitorForEvents(matching: events.union(clicks).union(.keyDown)) { [weak self] event in
            if event.type == .leftMouseDown || event.type == .rightMouseDown, event.window !== self?.dockGroupPanel {
                self?.closeDockGroup()
            }
            if event.type == .keyDown, event.keyCode == 53,
               self?.pointerInteraction.isPressed == true || self?.isSettling == true {
                self?.cancelPointerDrag()
                return nil
            }
            MainActor.assumeIsolated { self?.updatePointerAcceptance() }
            return event
        }
    }

    private func updatePointerAcceptance() {
        guard let panel, panel.isVisible else { return }
        if pointerInteraction.isPressed || isSettling {
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
                magnifications: indexedMagnifications, detailScale: preferences.detailScale)
            sideHoverChanged(inside: inside, metric: index.map { activeMetrics[$0] })
        }
    }

    private func handlePointerEvent(_ event: NSEvent) -> Bool {
        guard let panel, [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown].contains(event.type) else { return false }
        if isSettling { return true }
        fputs("DIAGNOSTIC event=\(event.type.rawValue) count=\(event.clickCount) time=\(event.timestamp) active=\(NSApp.isActive) pressed=\(pointerInteraction.isPressed)\n", stderr)
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
                bounds: selectedScreen?.visibleFrame,
                clickCount: event.clickCount, timestamp: event.timestamp,
                docking: selectedScreen.map { docking(on: $0, edge: preferences.edge) })
            dragDisplayID = selectedScreen.map { displayID(for: $0) }
            panel.ignoresMouseEvents = false
            return true
        case .leftMouseDragged:
            guard pointerInteraction.isPressed else { return false }
            _ = updatePointerPress(at: pointer)
            return true
        case .leftMouseUp:
            guard pointerInteraction.isPressed else { return false }
            let completion = finishPointerPress(at: pointer, doubleClickInterval: NSEvent.doubleClickInterval)
            fputs("DIAGNOSTIC completion=\(completion)\n", stderr)
            if case .drag(let placement) = completion {
                settleDrop(placement)
                return true
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

    private func handleDockGroupPointerEvent(_ event: NSEvent) -> Bool {
        guard let window = dockGroupPanel, let screen = dockGroupScreen else { return false }
        if isSettling { return event.type == .leftMouseDown || event.type == .leftMouseDragged || event.type == .leftMouseUp }
        let point: NSPoint
        if let quartz = event.cgEvent, let primary = NSScreen.screens.first {
            point = MacWidgetPointerInteraction.appKitPoint(fromQuartz: quartz.location, primaryScreenMaxY: primary.frame.maxY)
        } else {
            point = window.convertPoint(toScreen: event.locationInWindow)
        }
        switch event.type {
        case .leftMouseDown:
            guard !event.modifierFlags.contains(.control) else { return false }
            let layout = MacSystemDockGroupLayout(edge: dockGroupEdge, count: store.profile.macDashboardMetrics.count, scale: preferences.scale)
            let local = NSPoint(x: point.x - window.frame.minX, y: window.frame.maxY - point.y)
            guard let index = layout.index(at: local) else { return false }
            beginPointerPress(at: point, frame: window.frame, bounds: screen.visibleFrame,
                clickCount: event.clickCount, timestamp: event.timestamp,
                docking: docking(on: screen, edge: dockGroupEdge), dockGroupIndex: index)
            dragDisplayID = displayID(for: screen)
            return true
        case .leftMouseDragged:
            guard pointerInteraction.isPressed else { return false }
            _ = updatePointerPress(at: point)
            return true
        case .leftMouseUp:
            guard pointerInteraction.isPressed else { return false }
            let completion = finishPointerPress(at: point, doubleClickInterval: NSEvent.doubleClickInterval)
            if case .drag(let placement) = completion { settleDrop(placement) }
            else if completion == .openSettings { closeDockGroup(); showSettings() }
            return true
        default: return false
        }
    }

    func beginPointerPress(at point: NSPoint, frame: NSRect, bounds: NSRect?,
                           clickCount: Int, timestamp: TimeInterval, docking: MacWidgetDocking? = nil,
                           dockGroupIndex: Int? = nil, nativeDockMetric: MetricKind? = nil) {
        clearDragPresentation()
        captureDragOrigin(at: point, frame: frame, docking: docking, dockGroupIndex: dockGroupIndex, nativeDockMetric: nativeDockMetric)
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
            position: preferences.edge == .bottom ? preferences.horizontalPosition : preferences.verticalPosition,
            clickCount: clickCount, timestamp: timestamp, docking: docking)
    }

    /// A real mouse sequence owned by our transparent input panel over a Dock
    /// circle. No synthetic events or macOS Dock drag session are involved.
    func beginNativeDockPress(metric: MetricKind, at point: NSPoint, frame: NSRect, inputPanel: NSPanel,
                              clickCount: Int, timestamp: TimeInterval) {
        guard preferences.isInSystemDock, preferences.isVisible,
              store.profile.macDashboardMetrics.contains(metric),
              let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else { return }
        closeDockGroup()
        let edge = MacSystemDockLocation.resolve(on: screen, dockClick: point,
            fallback: preferences.lastSystemDockEdge)
        preferences.lastSystemDockEdge = edge
        var geometry = docking(on: screen, edge: edge)
        geometry.sourceDockDepth = geometry.distance(to: edge, from: point)
        beginPointerPress(at: point, frame: frame, bounds: screen.visibleFrame, clickCount: clickCount,
            timestamp: timestamp, docking: geometry, nativeDockMetric: metric)
        nativeDockInputPanel = inputPanel
        dragDisplayID = displayID(for: screen)
    }

    func updatePointerPress(at point: NSPoint) -> MacWidgetPointerInteraction.Placement? {
        let placement = pointerInteraction.update(at: point)
        if pointerInteraction.isDragging { hoveredMetric = nil }
        if let placement { presentDrag(placement) }
        return placement
    }

    func finishPointerPress(at point: NSPoint, doubleClickInterval: TimeInterval) -> MacWidgetPointerInteraction.Completion {
        // Mouse-up can be the first event beyond the drag threshold.
        _ = updatePointerPress(at: point)
        let completion = pointerInteraction.finish(at: point, doubleClickInterval: doubleClickInterval)
        if case .drag = completion { hoveredMetric = nil }
        else { clearDragPresentation() }
        return completion
    }

    private func captureDragOrigin(at point: NSPoint, frame: NSRect, docking: MacWidgetDocking?, dockGroupIndex: Int?, nativeDockMetric: MetricKind?) {
        dragOrigin = nil
        dragDocking = docking
        dragWidgetImage = nil
        guard let docking, !activeMetrics.isEmpty else { return }
        if let metric = nativeDockMetric, store.profile.macDashboardMetrics.contains(metric) {
            dragOrigin = MacWidgetDragOrigin(metric: metric, widgetFrame: frame,
                focusFrame: frame.insetBy(dx: frame.width * 0.05, dy: frame.height * 0.05),
                pointer: point, isSystemDock: true, isNativeDock: true)
            let snapshot = TimeProgressCalculator.snapshot(for: metric, profile: store.profile)
            dragMetricSnapshot = snapshot
            dragAccent = MacWidgetStyle.accent(for: metric, theme: store.profile.widgetTheme, customColors: preferences.customColors)
            let renderer = ImageRenderer(content: MacSystemDockTileView(presentation:
                MacSystemDockPresentation(snapshot: snapshot, accent: dragAccent)))
            renderer.scale = 2
            dragWidgetImage = renderer.nsImage
            return
        }
        if let index = dockGroupIndex, store.profile.macDashboardMetrics.indices.contains(index) {
            let metric = store.profile.macDashboardMetrics[index]
            let layout = MacSystemDockGroupLayout(edge: docking.edge, count: store.profile.macDashboardMetrics.count, scale: docking.scale)
            dragOrigin = MacWidgetDragOrigin(metric: metric, widgetFrame: frame, focusFrame: layout.focus(in: frame, index: index),
                pointer: point, isSystemDock: true)
            dragMetricSnapshot = TimeProgressCalculator.snapshot(for: metric, profile: store.profile)
            dragAccent = MacWidgetStyle.accent(for: metric, theme: store.profile.widgetTheme, customColors: preferences.customColors)
            if dockGroupPanel != nil { dragWidgetImage = groupImage(edge: docking.edge) }
            return
        }
        let local = CGPoint(x: point.x - frame.minX, y: frame.maxY - point.y)
        let hit: Int?
        if docking.edge == .top {
            hit = MacWidgetSurface.topHoverIndex(at: local, in: frame.size, scale: docking.scale,
                topCameraInset: docking.topInfo.cameraInset, topNotchWidth: docking.topInfo.notchWidth, proximity: false)
        } else {
            hit = MacWidgetSurface.sideHoverIndex(at: local, in: frame.size, edge: docking.edge,
                scale: docking.scale, metricCount: activeMetrics.count, magnifications: indexedMagnifications,
                detailScale: docking.detailScale)
        }
        let fallback = hoveredMetric ?? selectedMetric
        let index = hit ?? fallback.flatMap { activeMetrics.firstIndex(of: $0) } ?? 0
        let metric = activeMetrics[index]
        let focus = MacWidgetDragGeometry.focusFrame(in: frame, edge: docking.edge, index: index,
            scale: docking.scale, metricCount: activeMetrics.count, topInfo: docking.topInfo,
            magnification: hoverMagnifications[metric] ?? 1, detailScale: docking.detailScale)
        dragOrigin = MacWidgetDragOrigin(metric: metric, widgetFrame: frame, focusFrame: focus, pointer: point)
        dragMetricSnapshot = TimeProgressCalculator.snapshot(for: metric, profile: store.profile)
        dragAccent = MacWidgetStyle.accent(for: metric, theme: store.profile.widgetTheme, customColors: preferences.customColors)
        if panel != nil { dragWidgetImage = widgetImage(in: frame.size) }
    }

    private func widgetImage(in size: CGSize, previewEdge: MacWidgetEdge? = nil) -> NSImage? {
        let renderer = ImageRenderer(content: MacDesktopWidgetView(store: store, preferences: preferences, controller: self,
            previewEdge: previewEdge, previewTopInfo: previewEdge == nil ? nil : dragDocking?.topInfo)
            .frame(width: size.width, height: size.height))
        renderer.scale = selectedScreen?.backingScaleFactor ?? 2
        return renderer.nsImage
    }

    private func groupImage(edge: MacWidgetEdge, landing: Bool = false) -> NSImage? {
        let renderer = ImageRenderer(content: dockGroupView(edge: edge, landing: landing))
        renderer.scale = dockGroupScreen?.backingScaleFactor ?? selectedScreen?.backingScaleFactor ?? 2
        return renderer.nsImage
    }

    private func presentDrag(_ placement: MacWidgetPointerInteraction.Placement) {
        guard let origin = dragOrigin, let docking = dragDocking else { return }
        if !hasDragCursor, let panel = eventOwningPanel {
            NSCursor.closedHand.push()
            hasDragCursor = true
            (panel as? MacWidgetPanel)?.allowsKeyboardFocus = true
            panel.makeKey()
        }
        if panel != nil, placement.isDetached, dragPresentation?.isDetached != true {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        } else if panel != nil, let target = placement.attachment, target.edge != dragPresentation?.attachment?.edge {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        dragPresentation = placement
        if placement.isSlidingAlongEdge, let target = placement.attachment {
            collapseTask?.cancel()
            collapseTask = nil
            attachmentTask?.cancel()
            attachmentTask = nil
            dragWidgetImage = attachmentImage(for: target)
            dragPreviewEdge = target.edge
            dragAttachment = target
            dragVisual = attachmentVisual(for: target, coalescence: 0)
            refreshDragOverlay()
            hideDragSourceAfterDrawingOverlay()
            return
        }
        if dragVisual == nil {
            if origin.isNativeDock { nativeDockDragChanged?(true) }
            dragVisual = MacWidgetDragVisual(widgetFrame: origin.widgetFrame, focusFrame: origin.focusFrame,
                circleFrame: MacWidgetDragGeometry.circleFrame(center: NSPoint(x: origin.focusFrame.midX, y: origin.focusFrame.midY),
                                                               scale: docking.scale), coalescence: 0)
            refreshDragOverlay()
            // Leave the event-owning window in place. Only the overlay image
            // contracts and moves; an invisible rail never follows the cursor.
            hideDragSourceAfterDrawingOverlay()
            if reducesMotion() {
                updateDragLift(progress: 1)
            } else {
                let start = ProcessInfo.processInfo.systemUptime
                collapseTask = Task { [weak self] in
                    while !Task.isCancelled {
                        guard let self else { return }
                        let progress = min((ProcessInfo.processInfo.systemUptime - start) / 0.18, 1)
                        self.updateDragLift(progress: progress)
                        if progress >= 1 {
                            self.collapseTask = nil
                            return
                        }
                        try? await Task.sleep(for: .milliseconds(16))
                    }
                }
            }
        }
        if updateHeldAttachment(placement.attachment) { return }
        if collapseTask == nil {
            updateDragLift(progress: 1)
        } else {
            refreshDragOverlay()
        }
    }

    /// The pointer remains captured throughout contact, unfolding, and pulling
    /// away. These previews never touch the saved edge or either position.
    private func updateHeldAttachment(_ target: MacWidgetDropTarget?) -> Bool {
        let previous = dragAttachment
        dragAttachment = target
        if let target {
            if previous?.edge == target.edge {
                if attachmentTask == nil { dragVisual = attachmentVisual(for: target, coalescence: 0) }
                refreshDragOverlay()
                return true
            }
            collapseTask?.cancel()
            collapseTask = nil
            attachmentTask?.cancel()
            attachmentTask = nil
            if reducesMotion() {
                dragWidgetImage = attachmentImage(for: target)
                dragPreviewEdge = target.edge
                dragVisual = attachmentVisual(for: target, coalescence: 0)
                refreshDragOverlay()
            } else {
                attachmentTask = Task { [weak self] in
                    guard let self else { return }
                    if var collected = self.dragVisual, collected.coalescence < 1 {
                        collected.coalescence = 1
                        guard await self.animateDrag(to: collected, duration: 0.08) else { return }
                    }
                    guard !Task.isCancelled, let latest = self.dragAttachment else { return }
                    self.dragWidgetImage = self.attachmentImage(for: latest)
                    self.dragPreviewEdge = latest.edge
                    guard await self.animateHeldAttachment(coalescence: 1, duration: 0.12),
                          await self.animateHeldAttachment(coalescence: 0, duration: 0.16) else { return }
                    self.attachmentTask = nil
                }
            }
            return true
        }
        guard previous != nil else { return false }
        attachmentTask?.cancel()
        attachmentTask = nil
        collapseTask?.cancel()
        if reducesMotion() || dragVisual?.coalescence == 1 {
            collapseTask = nil
            updateDragLift(progress: 1)
        } else if let initial = dragVisual, let docking = dragDocking {
            let start = ProcessInfo.processInfo.systemUptime
            collapseTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self, let pointer = self.dragPresentation?.pointer else { return }
                    let progress = min((ProcessInfo.processInfo.systemUptime - start) / 0.14, 1)
                    var collected = initial
                    collected.circleFrame = MacWidgetDragGeometry.circleFrame(center: pointer, scale: docking.scale)
                    collected.coalescence = 1
                    self.dragVisual = initial.interpolated(to: collected, progress: progress)
                    self.refreshDragOverlay()
                    if progress >= 1 {
                        self.collapseTask = nil
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(16))
                }
            }
        }
        return true
    }

    private func attachmentImage(for target: MacWidgetDropTarget) -> NSImage? {
        if let image = dragPreviewImages[target.edge] { return image }
        let image = target.isSystemDock ? groupImage(edge: target.edge, landing: true)
            : widgetImage(in: target.frame.size, previewEdge: target.edge)
        dragPreviewImages[target.edge] = image
        return image
    }

    private func attachmentVisual(for target: MacWidgetDropTarget, coalescence: CGFloat) -> MacWidgetDragVisual? {
        guard let origin = dragOrigin, let docking = dragDocking else { return nil }
        let metrics = target.isSystemDock ? store.profile.macDashboardMetrics : store.profile.macWidgetMetrics(for: target.edge)
        let index = metrics.firstIndex(of: origin.metric) ?? 0
        let focus = target.isSystemDock
            ? MacSystemDockGroupLayout(edge: target.edge, count: metrics.count, scale: docking.scale).focus(in: target.frame, index: index)
            : MacWidgetDragGeometry.focusFrame(in: target.frame, edge: target.edge, index: index,
                scale: docking.scale, metricCount: metrics.count, topInfo: docking.topInfo, detailScale: docking.detailScale)
        return MacWidgetDragVisual(widgetFrame: target.frame, focusFrame: focus,
            circleFrame: MacWidgetDragGeometry.circleFrame(center: NSPoint(x: focus.midX, y: focus.midY), scale: docking.scale),
            coalescence: coalescence)
    }

    private func animateHeldAttachment(coalescence: CGFloat, duration: TimeInterval) async -> Bool {
        guard let initial = dragVisual else { return false }
        let start = ProcessInfo.processInfo.systemUptime
        while !Task.isCancelled {
            guard pointerInteraction.isPressed, let target = dragAttachment,
                  let destination = attachmentVisual(for: target, coalescence: coalescence) else { return false }
            let progress = min((ProcessInfo.processInfo.systemUptime - start) / duration, 1)
            // Read the latest point on every frame so sliding along the edge
            // does not restart the unfolding animation on each mouse event.
            dragVisual = initial.interpolated(to: destination, progress: progress)
            refreshDragOverlay()
            if progress >= 1 { return true }
            try? await Task.sleep(for: .milliseconds(16))
        }
        return false
    }

    private func updateDragLift(progress: Double) {
        guard let origin = dragOrigin, let docking = dragDocking, let placement = dragPresentation,
              let pointer = placement.pointer else { return }
        let center = NSPoint(x: origin.focusFrame.midX, y: origin.focusFrame.midY)
        let destination = placement.isDetached ? pointer
            : NSPoint(x: center.x + (pointer.x - origin.pointer.x) * 0.32,
                      y: center.y + (pointer.y - origin.pointer.y) * 0.32)
        let initial = MacWidgetDragVisual(widgetFrame: origin.widgetFrame, focusFrame: origin.focusFrame,
            circleFrame: MacWidgetDragGeometry.circleFrame(center: center, scale: docking.scale), coalescence: 0)
        let target = MacWidgetDragVisual(widgetFrame: origin.widgetFrame, focusFrame: origin.focusFrame,
            circleFrame: MacWidgetDragGeometry.circleFrame(center: destination, scale: docking.scale), coalescence: 1)
        dragVisual = initial.interpolated(to: target, progress: progress)
        refreshDragOverlay()
    }

    private func refreshDragOverlay() {
        guard panel != nil, let docking = dragDocking, let visual = dragVisual, let snapshot = dragMetricSnapshot else { return }
        let view = MacWidgetDragOverlay(docking: docking,
            visual: visual, widgetImage: dragWidgetImage, snapshot: snapshot, accent: dragAccent,
            dockLanding: dockLandingVisual, dockImages: dockLandingImages)
        if let host = dragOverlayHost {
            host.rootView = view
        } else {
            let overlay = MacWidgetPanel(contentRect: docking.screenFrame, styleMask: [.borderless, .nonactivatingPanel],
                                         backing: .buffered, defer: false)
            overlay.attachesToPhysicalEdge = true
            overlay.setFrame(docking.screenFrame, display: false)
            overlay.isOpaque = false
            overlay.backgroundColor = .clear
            overlay.hasShadow = false
            overlay.ignoresMouseEvents = true
            overlay.level = .statusBar
            overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            overlay.isReleasedWhenClosed = false
            let host = NSHostingView(rootView: view)
            overlay.contentView = host
            dragOverlay = overlay
            dragOverlayHost = host
            overlay.orderFrontRegardless()
        }
    }

    private func drawWindowNow(_ window: NSWindow) {
        window.contentView?.needsLayout = true
        window.contentView?.layoutSubtreeIfNeeded()
        window.contentView?.needsDisplay = true
        window.contentView?.displayIfNeeded()
        window.displayIfNeeded()
        CATransaction.flush()
    }

    private func hideDragSourceAfterDrawingOverlay() {
        guard let overlay = dragOverlay, let source = eventOwningPanel?.contentView,
              source.alphaValue > 0 else { return }
        // The fullscreen hosting view may not have drawn its first frame yet.
        // Keep the real widget visible until its moving replacement is ready.
        drawWindowNow(overlay)
        source.alphaValue = 0
    }

    /// Persist only a valid landing. Center releases and Escape retain both axes.
    func saveDrop(_ placement: MacWidgetPointerInteraction.Placement) {
        guard let target = placement.target else { return }
        // The gesture may have observed a newer Dock location than the polling
        // timer. Commit using the same geometry that produced its preview.
        if let dockEdge = dragDocking?.systemDockEdge { preferences.reconcileDockLocation(dockEdge) }
        if let dragDisplayID { preferences.displayID = dragDisplayID }
        if target.isSystemDock {
            preferences.lastSystemDockEdge = target.edge
            preferences.edge = target.edge
            preferences.isInSystemDock = true
            return
        }
        preferences.isInSystemDock = false
        if target.edge == .bottom { preferences.horizontalPosition = target.position }
        else if target.edge != .top { preferences.verticalPosition = target.position }
        preferences.edge = target.edge
    }

    private func clearDragPresentation() {
        let wasNativeDock = dragOrigin?.isNativeDock == true
        let wasDockLanding = isDockLanding
        collapseTask?.cancel()
        collapseTask = nil
        attachmentTask?.cancel()
        attachmentTask = nil
        settleTask?.cancel()
        settleTask = nil
        isSettling = false
        dragPresentation = nil
        dragOrigin = nil
        dragVisual = nil
        dockLandingVisual = nil
        dockLandingImages = [:]
        isDockLanding = false
        isHandingOffToEdge = false
        dragAttachment = nil
        dragPreviewEdge = nil
        dragPreviewImages = [:]
        dragDocking = nil
        dragWidgetImage = nil
        dragMetricSnapshot = nil
        dragDisplayID = nil
        panel?.contentView?.alphaValue = 1
        dockGroupPanel?.contentView?.alphaValue = 1
        nativeDockInputPanel?.contentView?.alphaValue = 1
        nativeDockInputPanel = nil
        dragOverlay?.orderOut(nil)
        dragOverlay = nil
        dragOverlayHost = nil
        if hasDragCursor {
            NSCursor.pop()
            hasDragCursor = false
        }
        if wasNativeDock { nativeDockDragChanged?(false) }
        if wasDockLanding { systemDockLandingChanged?(false) }
    }

    private func cancelPointerDrag() {
        pointerInteraction.cancel()
        if isDockLanding || isHandingOffToEdge {
            // Mouse-up has already committed this landing. Escape now only
            // finishes the handoff; it must not restart a circle-return path.
            clearDragPresentation()
            synchronize()
            return
        }
        settleDrop(nil)
    }

    func settleDrop(_ placement: MacWidgetPointerInteraction.Placement?) {
        collapseTask?.cancel()
        collapseTask = nil
        attachmentTask?.cancel()
        attachmentTask = nil
        settleTask?.cancel()
        let origin = dragOrigin
        if placement?.target?.isSystemDock == true, origin != nil, !isDockLanding {
            isDockLanding = true
            systemDockLandingChanged?(true)
        }
        if let placement { saveDrop(placement) }
        isHovered = false
        hoveredMetric = nil
        // Rebuild the hidden panel at its final position without discarding the
        // circle. Its snapshot will unfold only after that circle has arrived.
        isSettling = true
        if let origin { setSelection(origin.metric, animated: false) }
        synchronize(preservingDrag: true)
        if preferences.isInSystemDock {
            settleDockDrop(placement, origin: origin)
            return
        }
        guard let panel, let origin, let docking = dragDocking, let visual = dragVisual,
              preferences.isVisible else {
            clearDragPresentation()
            synchronize()
            return
        }
        let destinationFrame = panel.frame
        let index = activeMetrics.firstIndex(of: origin.metric) ?? 0
        let focus = MacWidgetDragGeometry.focusFrame(in: destinationFrame, edge: preferences.edge, index: index,
            scale: preferences.scale, metricCount: activeMetrics.count, topInfo: topInfo, detailScale: preferences.detailScale)
        let destinationImage = widgetImage(in: destinationFrame.size)
        let destination = MacWidgetDragVisual(widgetFrame: destinationFrame, focusFrame: focus,
            circleFrame: MacWidgetDragGeometry.circleFrame(center: NSPoint(x: focus.midX, y: focus.midY), scale: docking.scale),
            coalescence: 1)
        if reducesMotion() {
            dragWidgetImage = destinationImage
            var opened = destination
            opened.coalescence = 0
            dragVisual = opened
            refreshDragOverlay()
            settleTask = Task { [weak self] in await self?.finishEdgeHandoff() }
            return
        }
        if let held = dragAttachment, held.edge == placement?.target?.edge, dragPreviewEdge == held.edge {
            // A held edge preview is already unfolding or fully open. Releasing
            // commits it in place; never collect it into a circle a second time.
            dragWidgetImage = destinationImage
            var opened = destination
            opened.coalescence = 0
            if visual.coalescence == 0 {
                dragVisual = opened
                refreshDragOverlay()
                settleTask = Task { [weak self] in await self?.finishEdgeHandoff() }
            } else {
                settleTask = Task { [weak self] in
                    guard let self, await self.animateDrag(to: opened, duration: 0.14) else { return }
                    await self.finishEdgeHandoff()
                }
            }
            return
        }
        refreshDragOverlay()
        settleTask = Task { [weak self] in
            guard let self else { return }
            if visual.coalescence < 1 {
                var collected = visual
                collected.coalescence = 1
                guard await self.animateDrag(to: collected, duration: 0.08) else { return }
            }
            self.dragWidgetImage = destinationImage
            guard await self.animateDrag(to: destination, duration: 0.26, spring: true) else { return }
            var opened = destination
            opened.coalescence = 0
            guard await self.animateDrag(to: opened, duration: 0.18) else { return }
            await self.finishEdgeHandoff()
        }
    }

    private func finishEdgeHandoff() async {
        guard !Task.isCancelled else { return }
        guard let panel, let visual = dragVisual,
              preferences.isVisible, !preferences.isInSystemDock else {
            clearDragPresentation()
            synchronize()
            return
        }
        isHandingOffToEdge = true
        panel.contentView?.alphaValue = 1
        // SwiftUI layout and layer updates otherwise arrive after orderOut
        // removes the drag window, leaving a blank frame at the destination.
        drawWindowNow(panel)
        if reducesMotion() {
            await Task.yield()
            guard !Task.isCancelled else { return }
        } else {
            var faded = visual
            faded.opacity = 0
            guard await animateDrag(to: faded, duration: 0.08) else { return }
        }
        clearDragPresentation()
        synchronize()
    }

    private func settleDockDrop(_ placement: MacWidgetPointerInteraction.Placement?, origin: MacWidgetDragOrigin?) {
        if let target = placement?.target, target.isSystemDock,
           let origin, let docking = dragDocking, let visual = dragVisual,
           preferences.isVisible, !reducesMotion() {
            settleOpenDockGroup(target: target, origin: origin, docking: docking, visual: visual)
            return
        }
        guard let origin, let docking = dragDocking, let visual = dragVisual,
              panel != nil, preferences.isVisible, !reducesMotion() else {
            if placement?.target?.isSystemDock == true { closeDockGroup() }
            clearDragPresentation()
            synchronize()
            return
        }
        let returnsToNative = origin.isNativeDock
        let returnsToGroup = placement?.target == nil && origin.isSystemDock && !returnsToNative
        let nativeFrame = nativeDockReturnFrame?(origin.metric) ?? origin.widgetFrame
        let frame = returnsToNative ? nativeFrame : (returnsToGroup ? origin.widgetFrame : (placement?.target?.frame ?? origin.widgetFrame))
        let edge = placement?.target?.edge ?? docking.edge
        let layout = MacSystemDockGroupLayout(edge: edge, count: store.profile.macDashboardMetrics.count, scale: docking.scale)
        let index = store.profile.macDashboardMetrics.firstIndex(of: origin.metric) ?? 0
        let focus = returnsToNative ? nativeFrame : layout.focus(in: frame, index: index)
        let dockPoint = returnsToNative ? NSPoint(x: nativeFrame.midX, y: nativeFrame.midY)
            : layout.dockPoint(from: frame, screen: docking.screenFrame)
        let destination = MacWidgetDragVisual(widgetFrame: frame, focusFrame: focus,
            circleFrame: MacWidgetDragGeometry.circleFrame(center: returnsToGroup ? NSPoint(x: focus.midX, y: focus.midY) : dockPoint,
                                                           scale: docking.scale), coalescence: 1)
        settleTask = Task { [weak self] in
            guard let self else { return }
            if visual.coalescence < 1 {
                var collected = visual
                collected.coalescence = 1
                guard await self.animateDrag(to: collected, duration: 0.12) else { return }
            }
            if returnsToGroup { self.dragWidgetImage = self.groupImage(edge: edge) }
            if returnsToNative {
                guard await self.animateNativeDockReturn(to: destination, metric: origin.metric, duration: 0.22) else { return }
                guard self.nativeDockReturnFrame?(origin.metric) != nil else {
                    self.clearDragPresentation()
                    self.synchronize()
                    return
                }
            } else {
                guard await self.animateDrag(to: destination, duration: 0.22, spring: true) else { return }
            }
            var final = destination
            if returnsToNative, let snapshot = self.dragMetricSnapshot {
                let renderer = ImageRenderer(content: MacSystemDockTileView(presentation:
                    MacSystemDockPresentation(snapshot: snapshot, accent: self.dragAccent)))
                renderer.scale = 2
                self.dragWidgetImage = renderer.nsImage
                final.focusFrame = frame.insetBy(dx: frame.width * 0.05, dy: frame.height * 0.05)
                final.coalescence = 0
            } else if returnsToGroup { final.coalescence = 0 }
            else {
                final.circleFrame = NSRect(x: dockPoint.x - 6, y: dockPoint.y - 6, width: 12, height: 12)
                final.opacity = 0
            }
            if returnsToNative {
                guard await self.animateNativeDockReturn(to: final, metric: origin.metric, duration: 0.16) else { return }
            } else {
                guard await self.animateDrag(to: final, duration: 0.16) else { return }
            }
            if !returnsToGroup { self.closeDockGroup() }
            self.clearDragPresentation()
            self.synchronize()
        }
    }

    private func settleOpenDockGroup(target: MacWidgetDropTarget, origin: MacWidgetDragOrigin,
                                     docking: MacWidgetDocking, visual: MacWidgetDragVisual) {
        let metrics = store.profile.macDashboardMetrics
        let layout = MacSystemDockGroupLayout(edge: target.edge, count: metrics.count, scale: docking.scale)
        let isOpenPreview = dragAttachment?.isSystemDock == true && dragPreviewEdge == target.edge
        let initial = MacSystemDockLandingVisual.start(metrics: metrics, grabbed: origin.metric,
            visual: visual, layout: layout, isOpenPreview: isOpenPreview)
        dockLandingVisual = initial
        for metric in metrics {
            let renderer = ImageRenderer(content: MacSystemDockTileView(presentation: MacSystemDockPresentation(
                snapshot: TimeProgressCalculator.snapshot(for: metric, profile: store.profile),
                accent: MacWidgetStyle.accent(for: metric, theme: store.profile.widgetTheme,
                                             customColors: preferences.customColors))))
            renderer.scale = 2
            dockLandingImages[metric] = renderer.nsImage
        }
        refreshDragOverlay()
        settleTask = Task { [weak self] in
            guard let self else { return }
            // Let newly launched helper slots establish their actual positions.
            // The open preview stays open during this short handoff.
            let deadline = ProcessInfo.processInfo.systemUptime + 0.35
            while !Task.isCancelled, let frames = self.nativeDockFrames?(),
                  metrics.contains(where: { frames[$0] == nil }),
                  ProcessInfo.processInfo.systemUptime < deadline {
                try? await Task.sleep(for: .milliseconds(16))
            }
            guard !Task.isCancelled else { return }
            let start = ProcessInfo.processInfo.systemUptime
            var lastDestination = MacSystemDockLandingVisual.destination(metrics: metrics, nativeFrames: [:], target: target, docking: docking)
            var hasNativeFrames = false
            while !Task.isCancelled {
                let frames = self.nativeDockFrames?() ?? [:]
                hasNativeFrames = metrics.allSatisfy { frames[$0] != nil }
                if hasNativeFrames {
                    lastDestination = .destination(metrics: metrics, nativeFrames: frames, target: target, docking: docking)
                }
                var destination = lastDestination
                let progress = min((ProcessInfo.processInfo.systemUptime - start) / 0.28, 1)
                if !hasNativeFrames {
                    for metric in metrics { destination.tiles[metric]?.opacity = 0 }
                }
                self.dockLandingVisual = initial.interpolated(to: destination, progress: progress)
                self.refreshDragOverlay()
                if progress >= 1 { break }
                try? await Task.sleep(for: .milliseconds(16))
            }
            guard !Task.isCancelled else { return }
            self.closeDockGroup()
            self.clearDragPresentation()
            self.synchronize()
        }
    }

    private func animateNativeDockReturn(to destination: MacWidgetDragVisual, metric: MetricKind, duration: TimeInterval) async -> Bool {
        guard let initial = dragVisual else { return false }
        let start = ProcessInfo.processInfo.systemUptime
        while !Task.isCancelled {
            var target = destination
            if let frame = nativeDockReturnFrame?(metric) {
                target.widgetFrame = frame
                target.focusFrame = frame.insetBy(dx: frame.width * 0.05, dy: frame.height * 0.05)
                target.circleFrame.origin = NSPoint(x: frame.midX - target.circleFrame.width / 2,
                                                   y: frame.midY - target.circleFrame.height / 2)
            } else {
                // Auto-hide may remove the target during the flight. Fade out
                // instead of reopening a phantom circle over another app.
                target.opacity = 0
            }
            let progress = min((ProcessInfo.processInfo.systemUptime - start) / duration, 1)
            dragVisual = initial.interpolated(to: target, progress: progress, spring: destination.coalescence == 1)
            refreshDragOverlay()
            if progress >= 1 { return true }
            try? await Task.sleep(for: .milliseconds(16))
        }
        return false
    }

    private func animateDrag(to target: MacWidgetDragVisual, duration: TimeInterval, spring: Bool = false) async -> Bool {
        guard let initial = dragVisual else { return false }
        let start = ProcessInfo.processInfo.systemUptime
        while !Task.isCancelled {
            let progress = min((ProcessInfo.processInfo.systemUptime - start) / duration, 1)
            dragVisual = initial.interpolated(to: target, progress: progress, spring: spring)
            refreshDragOverlay()
            if progress >= 1 { return true }
            try? await Task.sleep(for: .milliseconds(16))
        }
        return false
    }

    private func resumeMetricHover(at pointer: NSPoint) {
        guard preferences.edge != .top, let panel, panel.isVisible else { return }
        let scale = MacWidgetPlacement.clampedScale(preferences.scale)
        let local = CGPoint(x: pointer.x - panel.frame.minX, y: panel.frame.maxY - pointer.y)
        let metrics = activeMetrics
        guard let index = MacWidgetSurface.sideHoverIndex(at: local, in: panel.frame.size,
                edge: preferences.edge, scale: scale, metricCount: metrics.count, magnifications: indexedMagnifications,
                detailScale: preferences.detailScale),
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
        settleTask?.cancel()
        collapseTask?.cancel()
        attachmentTask?.cancel()
        closeTask?.cancel()
        intentTask?.cancel()
        intentTask = nil
    }
}

private final class MacWidgetPanel: NSPanel {
    var onCancel: (() -> Void)?
    var onPointerEvent: ((NSEvent) -> Bool)?
    var attachesToPhysicalEdge = false
    var allowsKeyboardFocus = false
    // Hover resizes without activating; deliberate clicks can focus controls.
    override var canBecomeKey: Bool { allowsKeyboardFocus }
    override var canBecomeMain: Bool { false }
    override func sendEvent(_ event: NSEvent) {
        if onPointerEvent?(event) == true { return }
        super.sendEvent(event)
    }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        attachesToPhysicalEdge ? frameRect : super.constrainFrameRect(frameRect, to: screen)
    }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() }
        else { super.keyDown(with: event) }
    }
}
