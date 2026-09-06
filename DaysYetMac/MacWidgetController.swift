import AppKit
import Combine
import ColorSync
import QuartzCore
import SwiftUI

@MainActor
final class MacWidgetController: ObservableObject {
    @Published private(set) var selectedMetric: MetricKind?
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
    private var isHovered = false
    private var hoveredMetric: MetricKind?
    private var suppressTopHoverUntilExit = false
    private var globalPointerMonitor: Any?
    private var localPointerMonitor: Any?
    private var animationPointerTimer: Timer?
    private var pointerInteraction = MacWidgetPointerInteraction()

    init(store: ProfileStore, preferences: MacWidgetPreferences) {
        self.store = store
        self.preferences = preferences
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

        preferences.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.synchronize(animated: true) }
            .store(in: &subscriptions)
        store.$profile
            .receive(on: DispatchQueue.main)
            .sink { [weak self] profile in
                guard let self else { return }
                let metrics = profile.normalizedDashboardMetrics
                let selection = self.selectedMetric.flatMap { metrics.contains($0) ? $0 : nil } ?? metrics.first
                self.setSelection(selection, metrics: metrics)
            }
            .store(in: &subscriptions)
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
            }
            return
        }
        beginMetricHover(metric)
    }

    private func beginMetricHover(_ metric: MetricKind) {
        guard !pointerInteraction.isPressed else { return }
        setHovered(true)
        guard hoveredMetric != metric else { return }
        hoveredMetric = metric
        intentTask?.cancel()
        guard !isExpanded || selectedMetric != metric else { return }
        let delay = isExpanded ? 80 : 160
        intentTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(delay))
            guard !Task.isCancelled, let self, self.isHovered,
                  self.hoveredMetric == metric, self.preferences.isVisible else { return }
            self.setSelection(metric)
            self.setExpanded(true)
            self.updatePointerAcceptance()
        }
    }

    func hoverChanged(_ hovering: Bool) {
        guard preferences.edge != .top, !pointerInteraction.isPressed else { return }
        setHovered(hovering)
    }

    private func setHovered(_ hovering: Bool) {
        guard hovering != isHovered else { return }
        isHovered = hovering
        closeTask?.cancel()
        if !hovering {
            hoveredMetric = nil
            intentTask?.cancel()
        }
        if !hovering, !preferences.keepDetailsOpen {
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

    private func setSelection(_ metric: MetricKind?, metrics: [MetricKind]? = nil) {
        let metrics = metrics ?? store.profile.normalizedDashboardMetrics
        selectedMetric = metric
        let destination = CGFloat(metric.flatMap { metrics.firstIndex(of: $0) } ?? 0)
        selectionTask?.cancel()
        guard isExpanded, preferences.edge != .top,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              selectionPosition != destination else {
            selectionPosition = destination
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
                let elapsed = (ProcessInfo.processInfo.systemUptime - start) / 0.18
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
        isHovered = false
        hoveredMetric = nil
        suppressTopHoverUntilExit = false
        synchronize()
    }

    private func synchronize(animated: Bool = false) {
        // Preference notifications already queued when the press began must
        // not animate the panel back to its previous saved position.
        if pointerInteraction.isPressed {
            guard !preferences.isVisible else { return }
            pointerInteraction.cancel()
        }
        displays = NSScreen.screens.map { MacDisplay(id: displayID(for: $0), name: $0.localizedName) }
        if preferences.isVisible {
            if !preferences.keepDetailsOpen { releasePanelFocus() }
            if preferences.keepDetailsOpen {
                if selectedMetric == nil { setSelection(store.profile.normalizedDashboardMetrics.first) }
                isExpanded = true
            } else if !isHovered {
                isExpanded = false
                setSelection(selectedMetric)
            }
            positionPanel(animated: animated && panel?.isVisible == true)
            panel?.orderFrontRegardless()
            updatePointerAcceptance()
        } else {
            closeTask?.cancel()
            intentTask?.cancel()
            animationPointerTimer?.invalidate()
            isHovered = false
            hoveredMetric = nil
            suppressTopHoverUntilExit = false
            isExpanded = false
            panel?.allowsKeyboardFocus = false
            panel?.orderOut(nil)
            setSelection(selectedMetric)
        }
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
                                                   expanded: isExpanded, scale: preferences.scale,
                                                   screenFrame: screen.frame, topInfo: info)
        animationPointerTimer?.invalidate()
        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
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
                                               topNotchWidth: topInfo.notchWidth)
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
                let metrics = store.profile.normalizedDashboardMetrics
                if let index, metrics.indices.contains(index) {
                    beginMetricHover(metrics[index])
                } else if overCamera, let metric = selectedMetric.flatMap({ metrics.contains($0) ? $0 : nil }) ?? metrics.first {
                    beginMetricHover(metric)
                }
            } else {
                hoveredMetric = nil
                intentTask?.cancel()
            }
        } else {
            setHovered(inside)
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
                    topCameraInset: topInfo.cameraInset, topNotchWidth: topInfo.notchWidth) else { return false }
            closeTask?.cancel()
            intentTask?.cancel()
            hoveredMetric = nil
            isHovered = true
            selectionTask?.cancel()
            animationPointerTimer?.invalidate()
            // Stop a resize already in flight before taking its drag anchor.
            let currentFrame = panel.frame
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                panel.animator().setFrame(currentFrame, display: true)
            }
            pointerInteraction.begin(at: pointer, frame: currentFrame,
                bounds: preferences.edge == .top ? nil : selectedScreen?.visibleFrame,
                position: preferences.verticalPosition, clickCount: event.clickCount, timestamp: event.timestamp)
            panel.ignoresMouseEvents = false
            return true
        case .leftMouseDragged:
            guard pointerInteraction.isPressed else { return false }
            if let placement = pointerInteraction.update(at: pointer) {
                panel.setFrame(placement.frame, display: true)
            }
            return true
        case .leftMouseUp:
            guard pointerInteraction.isPressed else { return false }
            let completion = pointerInteraction.finish(at: pointer, doubleClickInterval: NSEvent.doubleClickInterval)
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

    private func resumeMetricHover(at pointer: NSPoint) {
        guard preferences.edge != .top, let panel, panel.isVisible else { return }
        let scale = MacWidgetPlacement.clampedScale(preferences.scale)
        let local = CGPoint(x: pointer.x - panel.frame.minX, y: panel.frame.maxY - pointer.y)
        let railX = preferences.edge == .right ? panel.frame.width - 46 * scale : 0
        let rows = CGRect(x: railX, y: 31 * scale, width: 46 * scale, height: 150 * scale)
        guard rows.contains(local), MacWidgetSurface.contains(local, in: panel.frame.size,
                edge: preferences.edge, selectedIndex: selectionPosition, scale: scale) else { return }
        let index = min(Int((local.y - rows.minY) / (50 * scale)), 2)
        let metrics = store.profile.normalizedDashboardMetrics
        if metrics.indices.contains(index) { beginMetricHover(metrics[index]) }
    }

    deinit {
        if let globalPointerMonitor { NSEvent.removeMonitor(globalPointerMonitor) }
        if let localPointerMonitor { NSEvent.removeMonitor(localPointerMonitor) }
        animationPointerTimer?.invalidate()
        selectionTask?.cancel()
        closeTask?.cancel()
        intentTask?.cancel()
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
