import AppKit

enum MacDockDirectHitGeometry {
    static func contains(_ point: NSPoint, frame: NSRect) -> Bool {
        guard [frame.minX, frame.minY, frame.width, frame.height, point.x, point.y].allSatisfy(\.isFinite),
              frame.width >= 12, frame.height >= 12, frame.width <= 256, frame.height <= 256 else { return false }
        let radius = min(frame.width, frame.height) * 0.44
        return hypot(point.x - frame.midX, point.y - frame.midY) <= radius
    }
}

#if DAYSYET_DIRECT_DOCK_DRAG
import ApplicationServices
import Combine
import SwiftUI

/// Direct-distribution experiment. This code is omitted from the normal
/// App Store build. It reads only our own Dock item geometry and never writes
/// Dock preferences, performs AX actions or synthesizes input events.
@MainActor
final class MacDockDirectDragController: ObservableObject {
    @Published private(set) var accessibilityGranted = AXIsProcessTrusted()
    @Published private(set) var detectedCircleCount = 0
    private let store: ProfileStore
    private let preferences: MacWidgetPreferences
    private let widget: MacWidgetController
    private let dock: MacSystemDockController
    private let reader = MacDockAccessibilityReader()
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
        preferences.objectWillChange.receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.configurationChanged() }.store(in: &subscriptions)
        store.$profile.dropFirst().receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.configurationChanged() }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.configurationChanged(reset: true) }.store(in: &subscriptions)
        let events: NSEvent.EventTypeMask = [.mouseMoved, .flagsChanged]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateInputAcceptance() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            MainActor.assumeIsolated { self?.updateInputAcceptance() }
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
        preferences.directlyDragsFromDock && preferences.isVisible && preferences.isInSystemDock && accessibilityGranted
    }

    private var currentFrames: [MetricKind: NSRect] {
        ProcessInfo.processInfo.systemUptime - geometryTime <= 0.25 ? frames : [:]
    }

    private func configurationChanged(reset: Bool = false) {
        generation += 1
        if reset || !preferences.directlyDragsFromDock || !preferences.isVisible || !accessibilityGranted
            || capturing.map({ !store.profile.macDashboardMetrics.contains($0) }) == true {
            invalidateInput()
        } else if !preferences.isInSystemDock {
            if widget.hasNativeDockPress { widget.abortNativeDockDrag() }
            removePanels()
        }
        refresh()
    }

    private func invalidateInput() {
        widget.abortNativeDockDrag()
        capturing = nil
        dock.setDragging(false)
        removePanels()
    }

    private func removePanels() {
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
        guard enabled else {
            if !accessibilityGranted { invalidateInput() }
            if !panels.isEmpty { removePanels() }
            return
        }
        updateInputAcceptance()
        guard let dockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier else {
            invalidateInput()
            dockProcessID = nil
            return
        }
        if dockProcessID != dockPID {
            invalidateInput()
            dockProcessID = dockPID
        }
        guard !reading, let primary = NSScreen.screens.first else { return }
        let pointer = NSEvent.mouseLocation
        // Poll tightly only around the Dock or while returning a captured drag.
        let nearEdge = NSScreen.screens.contains { screen in
            screen.frame.contains(pointer) && (pointer.x - screen.frame.minX < 200
                || screen.frame.maxX - pointer.x < 200 || pointer.y - screen.frame.minY < 200)
        }
        guard nearEdge || capturing != nil || widget.isDockLanding else {
            for panel in panels.values { panel.ignoresMouseEvents = true }
            return
        }
        let allowed = Dictionary(uniqueKeysWithValues: store.profile.macDashboardMetrics.map {
            ($0, Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/DaysYetDock_\($0.rawValue).app"))
        })
        let generation = generation
        let maxY = primary.frame.maxY
        let discoveringNewSlots = widget.isDockLanding
        reading = true
        let reader = reader
        readQueue.async { [weak self] in
            let items = reader.read(dockPID: dockPID, allowedURLs: allowed, primaryScreenMaxY: maxY,
                                    discoveringNewSlots: discoveringNewSlots)
            DispatchQueue.main.async {
                guard let self else { return }
                self.reading = false
                guard self.generation == generation, self.enabled else { return }
                self.apply(items)
            }
        }
    }

    private func apply(_ items: [MacDockAccessibilityItem]) {
        let items = items.filter { store.profile.macDashboardMetrics.contains($0.metric) }
        frames = Dictionary(uniqueKeysWithValues: items.map { ($0.metric, $0.frame) })
        geometryTime = ProcessInfo.processInfo.systemUptime
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
            panel.setFrame(item.frame, display: false)
        }
        updateInputAcceptance()
    }

    private func updateInputAcceptance() {
        guard capturing == nil else { return }
        let pointer = NSEvent.mouseLocation
        let bypass = NSEvent.modifierFlags.contains(.option) || !enabled
            || widget.isDockLanding
            || ProcessInfo.processInfo.systemUptime - geometryTime > 0.25
            || NSEvent.pressedMouseButtons != 0
        for (metric, panel) in panels {
            let hit = !bypass && frames[metric].map { MacDockDirectHitGeometry.contains(pointer, frame: $0) } == true
            panel.ignoresMouseEvents = !hit
            if hit { panel.orderFrontRegardless() }
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
            guard enabled, capturing == nil, !event.modifierFlags.contains(.option),
                  store.profile.macDashboardMetrics.contains(metric),
                  ProcessInfo.processInfo.systemUptime - geometryTime <= 0.25,
                  MacDockDirectHitGeometry.contains(pointer, frame: panel.frame) else { return }
            capturing = metric
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
            if case .drag(let placement) = completion { widget.settleDrop(placement) }
            else {
                capturing = nil
                updateInputAcceptance()
                widget.showDockGroup()
            }
        default: break
        }
    }
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
        view.setAccessibilityLabel(L10n.text("\(metric.shortTitle)：ドラッグしてDockから取り出す", "\(metric.shortTitle): drag out of the Dock"))
        contentView = view
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control)) {
            guard canShowMenu?() == true else { return }
            if event.modifierFlags.contains(.option) { orderOut(nil); return }
            let menu = NSMenu()
            menu.addItem(withTitle: L10n.text("グループを開く", "Open group"), action: #selector(openGroup), keyEquivalent: "").target = self
            menu.addItem(withTitle: L10n.text("DaysYetの設定…", "DaysYet Settings…"), action: #selector(settings), keyEquivalent: "").target = self
            menu.addItem(.separator())
            let hint = NSMenuItem(title: L10n.text("Optionキーで通常のDock操作", "Hold Option for standard Dock controls"), action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
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

struct MacDockDirectDragSettings: View {
    @ObservedObject var preferences: MacWidgetPreferences
    @ObservedObject var direct: MacDockDirectDragController
    var showSetup: () -> Void
    var body: some View {
        Toggle(L10n.text("Dockから直接ドラッグ（試作）", "Drag directly from the Dock (experimental)"), isOn: $preferences.directlyDragsFromDock)
        if preferences.directlyDragsFromDock {
            if direct.accessibilityGranted {
                Text(direct.detectedCircleCount > 0
                    ? L10n.text("Dockの丸をそのままつかめます。Optionキーを押すと、Dock本来の並べ替えやメニューを使えます。", "Drag a Dock circle directly. Hold Option to use the Dock’s original rearrangement and menus.")
                    : L10n.text("Dockを表示して丸にポインタを合わせると、直接ドラッグできます。", "Show the Dock and point at a circle to drag it directly."))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(L10n.text("Dock内のDaysYetの位置を調べるため、アクセシビリティの許可が必要です。", "Accessibility permission is needed to locate DaysYet’s circles in the Dock."))
                    .font(.caption).foregroundStyle(.secondary)
                Button(L10n.text("アクセシビリティの設定ガイド…", "Accessibility setup guide…"), action: showSetup)
            }
        }
    }
}
#endif
