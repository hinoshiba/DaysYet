import AppKit

enum MacDockPermission {
    static var canRequest: Bool {
#if DAYSYET_DIRECT_DOCK_DRAG
        true
#else
        false
#endif
    }

    static func isGranted() -> Bool {
#if DAYSYET_DIRECT_DOCK_DRAG
        AXIsProcessTrusted()
#else
        // Builds without Accessibility support cannot offer permission-gated Dock placement.
        false
#endif
    }
}

enum MacDockDirectHitGeometry {
    static func contains(_ point: NSPoint, frame: NSRect) -> Bool {
        guard [frame.minX, frame.minY, frame.width, frame.height, point.x, point.y].allSatisfy(\.isFinite),
              frame.width >= 12, frame.height >= 12, frame.width <= 256, frame.height <= 256 else { return false }
        // The transparent corners belong to the same Dock tile. Letting a
        // press through there starts macOS's single-icon rearrangement drag.
        return frame.contains(point)
    }
}

#if DAYSYET_DIRECT_DOCK_DRAG
import ApplicationServices
import Combine
import OSLog
import SwiftUI

/// Direct-distribution controller, omitted from the App Store build. Verified
/// own-tile panels capture a group drag; the optional native mover maintains
/// its position using permission-gated Dock selection and keyboard operations.
@MainActor
final class MacDockDirectDragController: ObservableObject {
    @Published private(set) var accessibilityGranted = AXIsProcessTrusted()
    @Published private(set) var detectedCircleCount = 0
    private let store: ProfileStore
    private let preferences: MacWidgetPreferences
    private let widget: MacWidgetController
    private let dock: MacSystemDockController
    private let reader = MacDockAccessibilityReader()
    private let log = Logger(subsystem: "com.hinoshiba.daysyet", category: "dock-interaction")
#if DAYSYET_DOCK_GROUP_GUARD
    private let groupDropGuard = MacDockGroupDropGuard()
#endif
    private let readQueue = DispatchQueue(label: "com.hinoshiba.daysyet.dock-geometry", qos: .userInteractive)
    private var panels: [MetricKind: MacDockInputPanel] = [:]
    private var frames: [MetricKind: NSRect] = [:]
    private var timer: Timer?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var subscriptions = Set<AnyCancellable>()
    private var reading = false
    private var generation = 0
    private var permissionCheck = Date.distantPast
    private var capturing: MetricKind?
    private var dockProcessID: pid_t?
    private var geometryTime: TimeInterval = 0
    private var externalNativeSuspensions = 0
    private var nativeOperationSuspended = false
    private var nativeReorderSuspended: Bool { externalNativeSuspensions > 0 || nativeOperationSuspended }
#if DAYSYET_DOCK_NATIVE_REORDER
    private let nativeMover = MacDockNativeMover()
    private let reorderPreview = MacDockGroupReorderPreview()
    private let snapshotCapture = MacDockSnapshotCapture()
    private let snapshotShield = MacDockSnapshotShield()
    private var nativeOrderReading = false
    private var nextNativeOrderRead: TimeInterval = 0
    private var lastPhysicalActivity: TimeInterval = 0
    private var preferredInsertion: Int?
    private var nativeCommitTask: Task<Void, Never>?
    private var nativePlacementGeneration = 0
    private var nativeRepairActive = false
    private var reorderMetrics: [MetricKind]?
    private var reorderEdge: MacWidgetEdge?
#endif

    func setNativeReorderSuspended(_ suspended: Bool) {
        externalNativeSuspensions = max(0, externalNativeSuspensions + (suspended ? 1 : -1))
#if DAYSYET_DOCK_NATIVE_REORDER
        if suspended, nativeRepairActive { cancelNativePlacement() }
#endif
        if suspended {
            // External trials own the Dock interaction for their entire
            // lifetime. Discard input windows and invalidate queued geometry
            // reads, instead of repeatedly ordering hidden windows out while
            // the trial is trying to hold focus and start a native drag.
            removePanels()
#if DAYSYET_DOCK_GROUP_GUARD
            groupDropGuard.stop()
#endif
        } else if externalNativeSuspensions == 0 {
            refresh()
        }
        updateInputAcceptance()
    }

    private func setNativeOperationSuspended(_ suspended: Bool) {
        nativeOperationSuspended = suspended
        if suspended {
            for panel in panels.values { panel.ignoresMouseEvents = true; panel.orderOut(nil) }
        }
        updateInputAcceptance()
    }

    init(store: ProfileStore, preferences: MacWidgetPreferences, widget: MacWidgetController, dock: MacSystemDockController) {
        self.store = store
        self.preferences = preferences
        self.widget = widget
        self.dock = dock
    }

    func start() {
        guard timer == nil else { return }
        widget.nativeDockDragChanged = { [weak self] dragging in
            guard let self else { return }
            self.dock.setDragging(dragging)
            if !dragging {
                self.capturing = nil
                for (metric, panel) in self.panels {
                    if let frame = self.frames[metric] { panel.setFrame(frame, display: false) }
                    else { panel.orderOut(nil) }
                }
                self.updateInputAcceptance()
            }
        }
        widget.nativeDockReturnFrame = { [weak self] metric in self?.currentFrames[metric] }
        widget.nativeDockFrames = { [weak self] in
            guard let self, self.enabled else { return nil }
            return self.currentFrames
        }
#if DAYSYET_DOCK_NATIVE_REORDER
        widget.commitSystemDockDrop = { [weak self] point, grabbed in
            await self?.commitNativePlacement(at: point, grabbed: grabbed) ?? false
        }
#endif
        preferences.objectWillChange.receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.configurationChanged() }.store(in: &subscriptions)
        store.$profile.dropFirst().receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.configurationChanged() }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.configurationChanged(reset: true) }.store(in: &subscriptions)
        var events: NSEvent.EventTypeMask = [.mouseMoved, .flagsChanged]
#if DAYSYET_DOCK_NATIVE_REORDER
        events.formUnion(MacDockNativeInputPolicy.cancellingEvents)
#endif
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] event in
            MainActor.assumeIsolated {
#if DAYSYET_DOCK_NATIVE_REORDER
                self?.recordPhysicalActivity(event)
#endif
                self?.updateInputAcceptance()
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            MainActor.assumeIsolated {
#if DAYSYET_DOCK_NATIVE_REORDER
                self?.recordPhysicalActivity(event)
#endif
                self?.updateInputAcceptance()
            }
            return event
        }
        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    func stop() {
#if DAYSYET_DOCK_NATIVE_REORDER
        cancelNativePlacement()
        widget.commitSystemDockDrop = nil
#endif
#if DAYSYET_DOCK_GROUP_GUARD
        groupDropGuard.stop()
#endif
        timer?.invalidate()
        timer = nil
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        subscriptions.removeAll()
        invalidateInput()
    }

    @discardableResult
    func refreshAccessibility() -> Bool {
        permissionCheck = .now
        let granted = AXIsProcessTrusted()
        if accessibilityGranted != granted { accessibilityGranted = granted }
        return granted
    }

    func openAccessibilitySettings() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        if !NSWorkspace.shared.open(url),
           let settings = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") {
            NSWorkspace.shared.openApplication(at: settings, configuration: NSWorkspace.OpenConfiguration())
        }
        refreshAccessibility()
        refresh()
    }

    private var enabled: Bool {
        preferences.isVisible && preferences.isInSystemDock && accessibilityGranted
    }

    private var currentFrames: [MetricKind: NSRect] {
        ProcessInfo.processInfo.systemUptime - geometryTime <= 0.25 ? frames : [:]
    }

    private func configurationChanged(reset: Bool = false) {
#if DAYSYET_DOCK_NATIVE_REORDER
        if snapshotShield.isVisible,
           reset || !preferences.dockVisualHandoffEnabled || !preferences.isVisible || !preferences.isInSystemDock {
            cancelSnapshotHandoff()
        }
        if let reorderMetrics,
           reorderMetrics != store.profile.macDashboardMetrics || reorderEdge != preferences.lastSystemDockEdge {
            cancelNativePlacement()
        }
#endif
        generation += 1
        if reset || !preferences.isVisible || !accessibilityGranted
            || capturing.map({ !store.profile.macDashboardMetrics.contains($0) }) == true {
            invalidateInput()
        } else if !preferences.isInSystemDock {
#if DAYSYET_DOCK_NATIVE_REORDER
            cancelNativePlacement()
#endif
            if widget.hasNativeDockPress { widget.abortNativeDockDrag() }
            removePanels()
        }
        refresh()
    }

    private func invalidateInput() {
#if DAYSYET_DOCK_NATIVE_REORDER
        cancelNativePlacement()
#endif
        widget.abortNativeDockDrag()
        capturing = nil
        dock.setDragging(false)
        removePanels()
    }

    private func removePanels() {
#if DAYSYET_DOCK_GROUP_GUARD
        groupDropGuard.update(nil)
#endif
        generation += 1
        if !panels.isEmpty || !frames.isEmpty {
            let reader = reader
            readQueue.async { reader.invalidate() }
        }
        for panel in panels.values { panel.orderOut(nil) }
        panels.removeAll()
        frames.removeAll()
        geometryTime = 0
        if detectedCircleCount != 0 { detectedCircleCount = 0 }
    }

    private func refresh() {
        if Date.now.timeIntervalSince(permissionCheck) >= 1 {
            refreshAccessibility()
        }
        guard externalNativeSuspensions == 0 else { return }
        guard enabled else {
#if DAYSYET_DOCK_GROUP_GUARD
            groupDropGuard.stop()
#endif
            if !accessibilityGranted { invalidateInput() }
            if !panels.isEmpty { removePanels() }
            return
        }
        updateInputAcceptance()
        guard let dockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
            .first(where: { $0.bundleURL?.path == "/System/Library/CoreServices/Dock.app" })?.processIdentifier else {
            invalidateInput()
            dockProcessID = nil
            return
        }
        if dockProcessID != dockPID {
            invalidateInput()
            dockProcessID = dockPID
        }
#if DAYSYET_DOCK_NATIVE_REORDER
        refreshNativeOrder()
#endif
#if DAYSYET_DOCK_GROUP_GUARD
        if nativeReorderSuspended {
            groupDropGuard.stop()
        } else {
            groupDropGuard.connect(to: dockPID)
            if widget.isChangingPlacement { groupDropGuard.update(nil) }
        }
#endif
        guard !reading, let primary = NSScreen.screens.first else { return }
        // A fast approach followed by a press must not beat the input surface.
        // Refresh verified slots while the group exists, not only on hover.
        let allowed = Dictionary(uniqueKeysWithValues: store.profile.macDashboardMetrics.map {
            ($0, Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/DaysYetDock_\($0.rawValue).app"))
        })
        let generation = generation
        let maxY = primary.frame.maxY
        let discoveringNewSlots = widget.isDockLanding
        var allowDragOcclusion = false
#if DAYSYET_DOCK_GROUP_GUARD
        allowDragOcclusion = groupDropGuard.isTracking
        let mouse = NSEvent.mouseLocation
        let sourcePoint = CGPoint(x: mouse.x, y: maxY - mouse.y)
        let sourceSampleTime = ProcessInfo.processInfo.systemUptime
#endif
        reading = true
        let reader = reader
        readQueue.async { [weak self] in
            let sample = reader.sample(dockPID: dockPID, allowedURLs: allowed, primaryScreenMaxY: maxY,
                                    discoveringNewSlots: discoveringNewSlots, allowDragOcclusion: allowDragOcclusion)
#if DAYSYET_DOCK_GROUP_GUARD
            let sourceFrame = reader.applicationItemFrame(at: sourcePoint)
#endif
            DispatchQueue.main.async {
                guard let self else { return }
                self.reading = false
                guard self.generation == generation, self.enabled else { return }
#if DAYSYET_DOCK_GROUP_GUARD
                self.groupDropGuard.updateSource(sourceFrame, sampledAt: sourceSampleTime)
#endif
                switch sample {
                case .current(let items): self.apply(items)
                case .temporarilyUnavailable:
                    // A slow read has not observed hidden or replaced icons.
                    // Keep the previous verified snapshot only for its existing
                    // 250ms lifetime; never renew that lifetime on a failed read.
                    self.updateInputAcceptance()
                }
            }
        }
    }

    private func apply(_ items: [MacDockAccessibilityItem]) {
        let items = items.filter { store.profile.macDashboardMetrics.contains($0.metric) }
        frames = Dictionary(uniqueKeysWithValues: items.map { ($0.metric, $0.frame) })
        geometryTime = ProcessInfo.processInfo.systemUptime
#if DAYSYET_DOCK_GROUP_GUARD
        updateGroupDropRegion()
#endif
        if detectedCircleCount != items.count { detectedCircleCount = items.count }
        guard capturing == nil else { return }
        for metric in Array(panels.keys) where frames[metric] == nil {
            panels.removeValue(forKey: metric)?.orderOut(nil)
        }
        for item in items {
            let panel: MacDockInputPanel
            if let existing = panels[item.metric] { panel = existing }
            else {
                panel = MacDockInputPanel(metric: item.metric)
                panel.onPointer = { [weak self, weak panel] event in
                    guard let self, let panel else { return }
                    self.handle(event, metric: item.metric, panel: panel)
                }
                panel.onCancel = { [weak self] in self?.widget.closeDetails() }
                panel.onOpenGroup = { [weak self] in self?.widget.showDockGroup() }
                panel.onSettings = { [weak self] in self?.widget.showSettings() }
                panel.canShowMenu = { [weak self] in self?.capturing == nil }
                panels[item.metric] = panel
            }
            if panel.frame != item.frame { panel.setFrame(item.frame, display: false) }
        }
        updateInputAcceptance()
    }

#if DAYSYET_DOCK_GROUP_GUARD
    private func updateGroupDropRegion() {
        guard !nativeReorderSuspended, !widget.isChangingPlacement, frames.count == store.profile.macDashboardMetrics.count,
              let primary = NSScreen.screens.first,
              let screen = NSScreen.screens.first(where: { screen in frames.values.allSatisfy { screen.frame.insetBy(dx: -1, dy: -1).contains($0) } }) else {
            groupDropGuard.update(nil)
            return
        }
        func quartz(_ rect: NSRect) -> CGRect {
            CGRect(x: rect.minX, y: primary.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
        }
        groupDropGuard.update(MacDockGroupDropRegion(edge: preferences.lastSystemDockEdge,
            screen: quartz(screen.frame), slots: frames.values.map(quartz)))
    }
#endif

    private func updateInputAcceptance() {
        guard capturing == nil else { return }
        let unavailable = nativeReorderSuspended || !enabled
            || widget.isDockLanding
            || ProcessInfo.processInfo.systemUptime - geometryTime > 0.25
        for (metric, panel) in panels {
            // Keep every verified slot protected, even before the pointer
            // enters it. A hover-only panel can miss a quick mouse-down.
            let protected = !unavailable && frames[metric] != nil
            panel.ignoresMouseEvents = !protected
            if protected {
                if !panel.isVisible { panel.orderFrontRegardless() }
            }
            else { panel.orderOut(nil) }
        }
    }

    private func handle(_ event: NSEvent, metric: MetricKind, panel: MacDockInputPanel) {
        let pointer: NSPoint
        if let quartz = event.cgEvent, let primary = NSScreen.screens.first {
            pointer = MacWidgetPointerInteraction.appKitPoint(fromQuartz: quartz.location, primaryScreenMaxY: primary.frame.maxY)
        } else { pointer = panel.convertPoint(toScreen: event.locationInWindow) }
        switch event.type {
        case .leftMouseDown:
            guard enabled, capturing == nil,
                  store.profile.macDashboardMetrics.contains(metric),
                  ProcessInfo.processInfo.systemUptime - geometryTime <= 0.25,
                  MacDockDirectHitGeometry.contains(pointer, frame: panel.frame) else { return }
#if DAYSYET_DOCK_NATIVE_REORDER
            nativeMover.cancel()
            lastPhysicalActivity = ProcessInfo.processInfo.systemUptime
#endif
            capturing = metric
            log.notice("Captured a DaysYet Dock press")
            for other in panels.values where other !== panel { other.ignoresMouseEvents = true }
            widget.beginNativeDockPress(metric: metric, at: pointer, frame: panel.frame, inputPanel: panel,
                                        clickCount: event.clickCount, timestamp: event.timestamp)
            if !widget.hasNativeDockPress { capturing = nil; updateInputAcceptance() }
        case .leftMouseDragged:
            guard capturing == metric else { return }
            _ = widget.updatePointerPress(at: pointer)
        case .leftMouseUp:
            guard capturing == metric else { return }
            let completion = widget.finishPointerPress(at: pointer, doubleClickInterval: NSEvent.doubleClickInterval)
            if case .drag(let placement) = completion {
                log.notice("Captured Dock drag released; target=\(placement.target?.edge.rawValue ?? "return", privacy: .public), native=\(placement.target?.isSystemDock == true)")
                widget.settleDrop(placement)
            }
            else {
                capturing = nil
                updateInputAcceptance()
                widget.showDockGroup()
            }
        default: break
        }
    }

#if DAYSYET_DOCK_NATIVE_REORDER
    private func recordPhysicalActivity(_ event: NSEvent) {
        guard event.type != .mouseMoved,
              event.cgEvent?.getIntegerValueField(.eventSourceUserData) != MacDockNativeKeySequence.marker else { return }
        lastPhysicalActivity = ProcessInfo.processInfo.systemUptime
        if snapshotShield.isVisible { cancelSnapshotHandoff() }
    }

    private func cancelSnapshotHandoff() {
        cancelNativePlacement()
        widget.abortDockPlacement()
    }

    private func cancelNativePlacement() {
        nativePlacementGeneration += 1
        nativeCommitTask?.cancel()
        nativeCommitTask = nil
        nativeMover.cancel()
        reorderPreview.dismiss()
        snapshotShield.dismiss()
        if nativeRepairActive { dock.setLanding(false) }
        nativeRepairActive = false
        reorderMetrics = nil
        reorderEdge = nil
        nativeOperationSuspended = false
        preferredInsertion = nil
        nextNativeOrderRead = ProcessInfo.processInfo.systemUptime + 0.5
    }

    private func slots(_ layout: MacDockNativeLayout) -> [MacDockGroupReorderGeometry.Slot] {
        layout.items.map { .init(metric: $0.metric, frame: $0.frame) }
    }

    private func readNativeLayout(metrics: [MetricKind], edge: MacWidgetEdge) async -> MacDockNativeLayout? {
        let token = nativePlacementGeneration
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(returning: nil); return }
                nativeMover.readLayout(metrics: metrics, edge: edge) { continuation.resume(returning: $0) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, self.nativePlacementGeneration == token else { return }
                self.nativeMover.cancel()
            }
        }
    }

    private func reorderNative(metrics: [MetricKind], edge: MacWidgetEdge, insertion: Int) async -> (Bool, MacDockNativeLayout?, String) {
        let token = nativePlacementGeneration
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(returning: (false, nil, "")); return }
                nativeMover.reorder(metrics: metrics, edge: edge, insertion: insertion) { success, layout, message in
                    continuation.resume(returning: (success, layout, message))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, self.nativePlacementGeneration == token else { return }
                self.nativeMover.cancel()
            }
        }
    }

    private func acceptNativeLayout(_ layout: MacDockNativeLayout) {
        guard layout.dockPID == dockProcessID, layout.edge == preferences.lastSystemDockEdge else { return }
        // An older geometry poll must not overwrite the post-move snapshot.
        generation += 1
        apply(layout.items.compactMap { item in
            item.metric.map { MacDockAccessibilityItem(metric: $0, frame: item.frame) }
        })
    }

    private func hasCompleteNativeGroup(_ layout: MacDockNativeLayout?, metrics: [MetricKind], edge: MacWidgetEdge) -> Bool {
        guard let layout, layout.dockPID == dockProcessID, layout.edge == edge else { return false }
        // Native order is authoritative while Dock frames may still be animating.
        // Only a complete, configured sequence can be a landing destination.
        let order = layout.items.map(\.metric)
        guard !metrics.isEmpty, order.compactMap({ $0 }).count == metrics.count,
              let first = order.firstIndex(where: { $0 != nil }), first + metrics.count <= order.count else { return false }
        return Array(order[first..<(first + metrics.count)]) == metrics.map(Optional.some)
    }

    private func commitNativePlacement(at point: NSPoint, grabbed: MetricKind) async -> Bool {
        guard enabled, !nativeRepairActive else {
            log.notice("Dock placement deferred because the group is unavailable or repairing")
            return false
        }
        log.notice("Committing a captured Dock group drop")
        let activityBeforeMove = lastPhysicalActivity
        nativePlacementGeneration += 1
        let token = nativePlacementGeneration
        let metrics = store.profile.macDashboardMetrics
        let edge = preferences.lastSystemDockEdge
        reorderMetrics = metrics
        reorderEdge = edge
        setNativeOperationSuspended(true)
        defer {
            if nativePlacementGeneration == token {
                snapshotShield.dismiss()
                reorderMetrics = nil
                reorderEdge = nil
                setNativeOperationSuspended(false)
                nextNativeOrderRead = ProcessInfo.processInfo.systemUptime + 0.6
            }
        }
        var layout: MacDockNativeLayout?
        let deadline = ProcessInfo.processInfo.systemUptime + 1
        repeat {
            guard enabled, !Task.isCancelled, nativePlacementGeneration == token,
                  lastPhysicalActivity == activityBeforeMove else { return false }
            layout = await readNativeLayout(metrics: metrics, edge: edge)
            guard enabled, !Task.isCancelled, nativePlacementGeneration == token,
                  lastPhysicalActivity == activityBeforeMove else { return false }
            if layout != nil { break }
            try? await Task.sleep(for: .milliseconds(60))
        } while ProcessInfo.processInfo.systemUptime < deadline
        guard enabled, !Task.isCancelled, nativePlacementGeneration == token, var layout else {
            log.notice("Dock group drop ended before a complete native layout was available")
            return false
        }
        if dockProcessID == nil { dockProcessID = layout.dockPID }
        let useSnapshot = preferences.dockVisualHandoffEnabled && MacDockSnapshotCapture.isGranted()
        let isCurrent: @MainActor () -> Bool = { [weak self] in
            guard let self else { return false }
            return !Task.isCancelled && self.enabled && self.nativePlacementGeneration == token
                && self.lastPhysicalActivity == activityBeforeMove && self.preferences.dockVisualHandoffEnabled
                && self.preferences.lastSystemDockEdge == edge && self.store.profile.macDashboardMetrics == metrics
        }
        if useSnapshot {
            // A drop can arrive during hover magnification or helper launch.
            // First settle that geometry, then choose the gap and capture the
            // same layout. No native reorder input has been sent at this point.
            guard await dock.waitForDisplay(), isCurrent(),
                  let stable = await settledNativeLayout(metrics: metrics, edge: edge, token: token,
                    activity: activityBeforeMove, requiresShield: false, requiresCompleteGroup: false),
                  isCurrent() else { return false }
            layout = stable
        }
        guard layout.dockPID == dockProcessID,
              let insertion = MacDockGroupReorderGeometry.insertion(at: point, grabbed: grabbed,
                members: metrics, slots: slots(layout), edge: edge, previous: preferredInsertion) else {
            log.notice("Dock group drop rejected invalid or changing native geometry")
            return false
        }
        if useSnapshot {
            // Capture only after every owned helper has submitted its invisible
            // image. A single snapshot must not bake the old circles into it.
            guard isCurrent(),
                  let snapshot = await snapshotCapture.capture(layout: layout, isCurrent: isCurrent),
                  isCurrent(), snapshotShield.show(snapshot, onCancel: { [weak self] in self?.cancelSnapshotHandoff() }) else {
                if isCurrent() {
                    preferences.systemDockError = L10n.text(
                        "Dockの表示を準備できませんでした。もう一度移動してください。",
                        "The Dock transition could not be prepared. Try moving the group again.")
                }
                return false
            }
            // The capture is asynchronous. Confirm that no layout change
            // occurred while it was being prepared, before sending any input.
            guard let fresh = await readNativeLayout(metrics: metrics, edge: edge), isCurrent(),
                  Self.sameNativeFrames(layout, fresh) else { return false }
            log.notice("Dock regional snapshot prepared; starting native placement")
        }
        var result = await reorderNative(metrics: metrics, edge: edge, insertion: insertion)
        log.notice("Dock group drop result: \(result.2, privacy: .public)")
        guard nativePlacementGeneration == token, enabled, !Task.isCancelled else { return false }
        if let partial = result.1, !hasCompleteNativeGroup(partial, metrics: metrics, edge: edge),
           partial.dockPID == dockProcessID, partial.edge == edge,
           lastPhysicalActivity == activityBeforeMove {
            // A transient native selection/layout failure may interrupt an
            // exchange. Retry once under the same preview, only if no new user
            // action occurred. A physical cancellation must not replay a drop;
            // the ordinary idle repair can later restore group adjacency.
            let recoveryDeadline = ProcessInfo.processInfo.systemUptime + 1.5
            while NSEvent.pressedMouseButtons != 0 || ProcessInfo.processInfo.systemUptime - lastPhysicalActivity < 0.5 {
                guard nativePlacementGeneration == token, enabled, !Task.isCancelled else { return false }
                if ProcessInfo.processInfo.systemUptime >= recoveryDeadline { break }
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard nativePlacementGeneration == token, enabled, !Task.isCancelled else { return false }
            if lastPhysicalActivity == activityBeforeMove, NSEvent.pressedMouseButtons == 0,
               ProcessInfo.processInfo.systemUptime - lastPhysicalActivity >= 0.5 {
                result = await reorderNative(metrics: metrics, edge: edge, insertion: insertion)
                log.notice("Dock group drop recovery: \(result.2, privacy: .public)")
                guard nativePlacementGeneration == token, enabled, !Task.isCancelled else { return false }
            }
        }
        if let current = result.1 { acceptNativeLayout(current) }
        let complete = hasCompleteNativeGroup(result.1, metrics: metrics, edge: edge)
        if useSnapshot, complete {
            // Native order changes before its animation ends. Keep the old
            // Dock image until two fresh complete layouts have settled.
            guard let stable = await settledNativeLayout(metrics: metrics, edge: edge, token: token,
                activity: activityBeforeMove), nativePlacementGeneration == token, !Task.isCancelled,
                preferences.dockVisualHandoffEnabled, MacDockSnapshotCapture.isGranted() else { return false }
            acceptNativeLayout(stable)
            await snapshotShield.reveal(duration: 0.14)
            guard nativePlacementGeneration == token, enabled, !Task.isCancelled,
                  lastPhysicalActivity == activityBeforeMove else { return false }
            log.notice("Dock regional transition revealed after complete native placement")
        }
        if result.0, complete {
            preferredInsertion = insertion
            preferences.systemDockError = nil
        } else {
            preferences.systemDockError = L10n.text(
                "Dock内の位置を変更できませんでした。丸を掴んでもう一度お試しください。",
                "The Dock group could not move. Grab a circle and try again.")
        }
        return complete
    }

    private func settledNativeLayout(metrics: [MetricKind], edge: MacWidgetEdge, token: Int,
                                     activity: TimeInterval, requiresShield: Bool = true,
                                     requiresCompleteGroup: Bool = true) async -> MacDockNativeLayout? {
        let deadline = ProcessInfo.processInfo.systemUptime + 0.8
        var previous: MacDockNativeLayout?
        repeat {
            guard enabled, nativePlacementGeneration == token, !Task.isCancelled,
                  lastPhysicalActivity == activity, preferences.dockVisualHandoffEnabled,
                  preferences.lastSystemDockEdge == edge, store.profile.macDashboardMetrics == metrics,
                  MacDockSnapshotCapture.isGranted(), !requiresShield || snapshotShield.isVisible else { return nil }
            if let current = await readNativeLayout(metrics: metrics, edge: edge),
               current.dockPID == dockProcessID, current.edge == edge,
               MacDockGroupReorderGeometry.currentInsertion(members: metrics, slots: slots(current)) != nil,
               !requiresCompleteGroup || (hasCompleteNativeGroup(current, metrics: metrics, edge: edge)
                   && MacDockGroupReorderGeometry.isContiguous(members: metrics, slots: slots(current))) {
                if let previous, Self.sameNativeFrames(previous, current) { return current }
                previous = current
            } else { previous = nil }
            do { try await Task.sleep(for: .milliseconds(48)) } catch { return nil }
        } while ProcessInfo.processInfo.systemUptime < deadline
        return nil
    }

    private static func sameNativeFrames(_ lhs: MacDockNativeLayout, _ rhs: MacDockNativeLayout) -> Bool {
        guard lhs.dockPID == rhs.dockPID, lhs.edge == rhs.edge, lhs.items.count == rhs.items.count else { return false }
        return zip(lhs.items, rhs.items).allSatisfy { a, b in
            a.metric == b.metric && abs(a.frame.minX - b.frame.minX) <= 0.5
                && abs(a.frame.minY - b.frame.minY) <= 0.5 && abs(a.frame.width - b.frame.width) <= 0.5
                && abs(a.frame.height - b.frame.height) <= 0.5
        }
    }

    private func refreshNativeOrder() {
        let now = ProcessInfo.processInfo.systemUptime
        guard enabled, !nativeOrderReading, !nativeMover.busy, !nativeReorderSuspended,
              !widget.isChangingPlacement, capturing == nil,
              now >= nextNativeOrderRead else { return }
        nextNativeOrderRead = now + 0.4
        nativeOrderReading = true
        let metrics = store.profile.macDashboardMetrics
        let edge = preferences.lastSystemDockEdge
        let token = nativePlacementGeneration
        nativeMover.readLayout(metrics: metrics, edge: edge) { [weak self] layout in
            guard let self else { return }
            self.nativeOrderReading = false
            guard self.nativePlacementGeneration == token, self.enabled, !self.nativeReorderSuspended,
                  self.store.profile.macDashboardMetrics == metrics,
                  self.preferences.lastSystemDockEdge == edge,
                  !self.widget.isChangingPlacement, self.capturing == nil,
                  let layout, layout.dockPID == self.dockProcessID else { return }
            let slots = self.slots(layout)
            if MacDockGroupReorderGeometry.isContiguous(members: metrics, slots: slots) {
                self.preferredInsertion = MacDockGroupReorderGeometry.currentInsertion(members: metrics, slots: slots)
                return
            }
            guard NSEvent.pressedMouseButtons == 0,
                  ProcessInfo.processInfo.systemUptime - self.lastPhysicalActivity >= 0.5,
                  let insertion = MacDockGroupReorderGeometry.repairInsertion(
                    members: metrics, slots: slots, preferred: self.preferredInsertion) else { return }
            self.repairNativeGroup(layout: layout, metrics: metrics, insertion: insertion)
        }
    }

    private func repairNativeGroup(layout: MacDockNativeLayout, metrics: [MetricKind], insertion: Int) {
        guard !nativeRepairActive, !nativeReorderSuspended else { return }
        let presentations = metrics.map { kind in
            MacSystemDockPresentation(snapshot: TimeProgressCalculator.snapshot(for: kind, profile: store.profile),
                accent: MacWidgetStyle.accent(for: kind, theme: store.profile.widgetTheme, customColors: preferences.customColors))
        }
        let original = Dictionary(uniqueKeysWithValues: layout.items.compactMap { item in
            item.metric.map { ($0, item.frame) }
        })
        let target = Dictionary(uniqueKeysWithValues: metrics.enumerated().map { index, kind in
            (kind, layout.items[insertion + index].frame)
        })
        guard reorderPreview.show(frames: original, presentations: presentations) else { return }
        let activityBeforeMove = lastPhysicalActivity
        nativePlacementGeneration += 1
        let token = nativePlacementGeneration
        nativeRepairActive = true
        reorderMetrics = metrics
        reorderEdge = layout.edge
        setNativeOperationSuspended(true)
        // The preview has drawn before native circles become transparent.
        dock.setLanding(true)
        nativeCommitTask = Task { [weak self] in
            guard let self else { return }
            await self.reorderPreview.animate(to: target, duration: 0.12)
            guard !Task.isCancelled, self.enabled, self.nativePlacementGeneration == token else { return }
            var result: (Bool, MacDockNativeLayout?, String) = (false, nil, "入力が変わったため、まとめ直しを中止しました。")
            // The preparation animation runs before the mover installs its
            // input monitor. A click during that interval must cancel this
            // repair too, rather than starting keys after the click completes.
            if self.lastPhysicalActivity == activityBeforeMove, NSEvent.pressedMouseButtons == 0 {
                result = await self.reorderNative(metrics: metrics, edge: layout.edge, insertion: insertion)
                guard !Task.isCancelled, self.enabled, self.nativePlacementGeneration == token else { return }
                if let partial = result.1, partial.dockPID == self.dockProcessID, partial.edge == layout.edge,
                   !self.hasCompleteNativeGroup(partial, metrics: metrics, edge: layout.edge),
                   self.lastPhysicalActivity == activityBeforeMove, NSEvent.pressedMouseButtons == 0 {
                    // Keep the coherent preview through one fresh bounded
                    // attempt. New physical input never replays this repair.
                    result = await self.reorderNative(metrics: metrics, edge: layout.edge, insertion: insertion)
                    guard !Task.isCancelled, self.enabled, self.nativePlacementGeneration == token else { return }
                    self.log.notice("Dock group repair recovery: \(result.2, privacy: .public)")
                }
            }
            self.log.notice("Dock group repair result: \(result.2, privacy: .public)")
            guard !Task.isCancelled, self.nativePlacementGeneration == token else { return }
            if let current = result.1 {
                self.acceptNativeLayout(current)
                if self.hasCompleteNativeGroup(current, metrics: metrics, edge: layout.edge) {
                    let frames = Dictionary(uniqueKeysWithValues: current.items.compactMap { item in item.metric.map { ($0, item.frame) } })
                    await self.reorderPreview.animate(to: frames, duration: 0.12)
                }
            }
            guard !Task.isCancelled, self.nativePlacementGeneration == token else { return }
            self.dock.setLanding(false)
            // Helper IPC redraw arrives asynchronously; retain the identical
            // preview through one display update before revealing the native UI.
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled, self.nativePlacementGeneration == token else { return }
            self.reorderPreview.dismiss()
            self.nativeRepairActive = false
            self.reorderMetrics = nil
            self.reorderEdge = nil
            self.nativeCommitTask = nil
            self.preferredInsertion = result.0 ? insertion : nil
            self.setNativeOperationSuspended(false)
            self.nextNativeOrderRead = ProcessInfo.processInfo.systemUptime + (result.0 ? 0.5 : 3)
        }
    }
#endif
}

@MainActor
private final class MacDockInputPanel: NSPanel {
    var onPointer: ((NSEvent) -> Void)?
    var onCancel: (() -> Void)?
    var onOpenGroup: (() -> Void)?
    var onSettings: (() -> Void)?
    var canShowMenu: (() -> Bool)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(metric: MetricKind) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        title = "DaysYet — \(metric.shortTitle)"
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isFloatingPanel = true
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let view = NSView()
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        view.setAccessibilityLabel(L10n.text("\(metric.shortTitle)：ドラッグしてグループを移動", "\(metric.shortTitle): drag to move the group"))
        contentView = view
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control)) {
            guard canShowMenu?() == true else { return }
            let menu = NSMenu()
            menu.addItem(withTitle: L10n.text("グループを開く", "Open group"), action: #selector(openGroup), keyEquivalent: "").target = self
            menu.addItem(withTitle: L10n.text("DaysYetの設定…", "DaysYet Settings…"), action: #selector(settings), keyEquivalent: "").target = self
            if let contentView { NSMenu.popUpContextMenu(menu, with: event, for: contentView) }
            return
        }
        if [.leftMouseDown, .leftMouseDragged, .leftMouseUp].contains(event.type) { onPointer?(event); return }
        super.sendEvent(event)
    }
    @objc private func openGroup() { onOpenGroup?() }
    @objc private func settings() { onSettings?() }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() } else { super.keyDown(with: event) }
    }
}

#endif
