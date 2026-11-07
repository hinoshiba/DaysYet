#if DAYSYET_DIRECT_DOCK_DRAG && DAYSYET_DOCK_NATIVE_REORDER
import AppKit
import QuartzCore

enum MacDockSnapshotShieldPolicy {
    static let maximumLifetime: TimeInterval = 8
    static let maximumRevealDuration: TimeInterval = 0.25
    static let maximumPixels = 16_777_216

    static func valid(frame: NSRect, screen: NSRect, edge: MacWidgetEdge,
                      pixelWidth: Int, pixelHeight: Int, scale: CGFloat) -> Bool {
        guard [frame.minX, frame.minY, frame.width, frame.height, frame.maxX, frame.maxY,
               screen.minX, screen.minY, screen.width, screen.height, screen.maxX, screen.maxY,
               scale].allSatisfy(\.isFinite),
              frame.width > 0, frame.height > 0, screen.width > 0, screen.height > 0,
              scale > 0, screen.contains(frame), pixelWidth > 0, pixelHeight > 0,
              pixelWidth <= maximumPixels / pixelHeight else { return false }
        let area = frame.width * frame.height
        let screenArea = screen.width * screen.height
        guard area.isFinite, screenArea.isFinite, area <= screenArea * 0.25,
              abs(CGFloat(pixelWidth) - (frame.width * scale).rounded()) <= 1,
              abs(CGFloat(pixelHeight) - (frame.height * scale).rounded()) <= 1 else { return false }
        // A captured strip may cover the Dock, never a large unrelated part of
        // the desktop. The one-pixel allowance is only for capture alignment.
        let allowance = 1 / scale
        switch edge {
        case .bottom: return frame.maxY - screen.minY <= screen.height * 0.25 + allowance
        case .left: return frame.maxX - screen.minX <= screen.width * 0.25 + allowance
        case .right: return screen.maxX - frame.minX <= screen.width * 0.25 + allowance
        case .top: return false
        }
    }

    static func revealDuration(_ duration: TimeInterval) -> TimeInterval {
        duration.isFinite ? min(max(duration, 0), maximumRevealDuration) : 0
    }
}

/// Pure lifetime/input policy. After a press cancels a shield, its image goes
/// away immediately while the transparent window consumes the rest of that
/// same mouse sequence. An old reveal can never close a newer shield.
struct MacDockSnapshotShieldLifetime {
    enum Phase: Equatable { case hidden, covered, revealing, draining }
    private(set) var phase: Phase = .hidden
    private(set) var generation: UInt64 = 0
    private(set) var pressedButtons = Set<Int>()
    private var shownAt: TimeInterval = 0
    private var cancellationDelivered = false

    var hasImage: Bool { phase == .covered || phase == .revealing }

    @discardableResult
    mutating func begin(now: TimeInterval) -> UInt64 {
        generation &+= 1
        phase = .covered
        shownAt = now
        pressedButtons.removeAll()
        cancellationDelivered = false
        return generation
    }

    mutating func beginReveal() -> UInt64? {
        guard hasImage else { return nil }
        generation &+= 1
        phase = .revealing
        return generation
    }

    func canReveal(_ token: UInt64) -> Bool { phase == .revealing && generation == token }

    func expired(now: TimeInterval) -> Bool {
        hasImage && (!now.isFinite || now < shownAt || now - shownAt >= MacDockSnapshotShieldPolicy.maximumLifetime)
    }

    mutating func cancelOnce() -> Bool {
        guard phase != .hidden, !cancellationDelivered else { return false }
        cancellationDelivered = true
        return true
    }

    mutating func press(_ button: Int) {
        if phase != .hidden { pressedButtons.insert(button) }
    }

    mutating func release(_ button: Int) -> Bool {
        pressedButtons.remove(button)
        guard phase == .draining, pressedButtons.isEmpty else { return false }
        phase = .hidden
        return true
    }

    /// A local event monitor can request dismissal before NSPanel.sendEvent
    /// receives the down event. Preserve that press using the current hardware
    /// buttons only when the pointer is actually inside this window.
    mutating func dismiss(hardwareButtons: UInt64, pointerInside: Bool) -> Bool {
        generation &+= 1
        if pointerInside {
            for button in 0..<64 where hardwareButtons & (UInt64(1) << button) != 0 {
                pressedButtons.insert(button)
            }
        }
        phase = pressedButtons.isEmpty ? .hidden : .draining
        return phase == .hidden
    }

    mutating func pollRelease(hardwareButtons: UInt64) -> Bool {
        guard phase == .draining else { return false }
        if hardwareButtons == 0 { pressedButtons.removeAll() }
        else {
            pressedButtons = pressedButtons.filter { button in
                !(0..<64).contains(button) || hardwareButtons & (UInt64(1) << button) != 0
            }
        }
        guard pressedButtons.isEmpty else { return false }
        phase = .hidden
        return true
    }
}

/// This renderer is also exercised offscreen in tests. The region never grows
/// beyond the captured rectangle, and alpha=1 covers every pixel, including
/// the outermost row and column. Clearing the image clears its backing pixels.
enum MacDockSnapshotShieldRendering {
    static func draw(_ image: CGImage?, in bounds: CGRect, context: CGContext, opacity: CGFloat) {
        context.saveGState()
        defer { context.restoreGState() }
        context.clear(bounds)
        guard let image, opacity > 0 else { return }
        if opacity >= 1 {
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(bounds)
        }
        context.setBlendMode(.normal)
        context.setAlpha(min(opacity, 1))
        context.interpolationQuality = .none
        context.draw(image, in: bounds)
    }
}

@MainActor
final class MacDockSnapshotShield {
    private var panel: MacDockSnapshotShieldPanel?
    private var canvas: MacDockSnapshotShieldCanvas?
    private var lifetime = MacDockSnapshotShieldLifetime()
    private var timer: Timer?
    private var onCancel: (() -> Void)?
    private var metadata: Metadata?

    private struct Metadata {
        let displayID: CGDirectDisplayID
        let screenFrame: NSRect
        let scale: CGFloat
        let dock: NSRunningApplication
    }

    // A transparent input drain is deliberately not a visible snapshot. The
    // controller must not start another native move while the button is down.
    var isVisible: Bool { lifetime.hasImage && panel?.isVisible == true }

    @discardableResult
    func show(_ snapshot: MacDockCapturedSnapshot, onCancel: @escaping () -> Void) -> Bool {
        guard lifetime.phase != .draining, NSEvent.pressedMouseButtons == 0 else { return false }
        dismiss()
        guard !Task.isCancelled, CGPreflightScreenCaptureAccess(),
              let screen = NSScreen.screens.first(where: {
                  ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == snapshot.displayID
              }), screen.frame == snapshot.screenFrame,
              MacDockSnapshotShieldPolicy.valid(frame: snapshot.frame, screen: snapshot.screenFrame,
                  edge: snapshot.edge, pixelWidth: snapshot.image.width, pixelHeight: snapshot.image.height,
                  scale: screen.backingScaleFactor),
              let dock = NSRunningApplication(processIdentifier: snapshot.dockPID), !dock.isTerminated,
              dock.bundleIdentifier == "com.apple.dock",
              dock.bundleURL?.path == "/System/Library/CoreServices/Dock.app" else { return false }

        let window = MacDockSnapshotShieldPanel(contentRect: snapshot.frame,
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let view = MacDockSnapshotShieldCanvas(frame: NSRect(origin: .zero, size: snapshot.frame.size))
        view.image = snapshot.image
        view.setAccessibilityElement(false)
        window.title = "DaysYet — Dock transition"
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
        window.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces, .stationary]
        window.contentView = view
        window.setFrame(snapshot.frame, display: false)
        window.onInput = { [weak self] event in self?.consume(event) }
        panel = window
        canvas = view
        metadata = Metadata(displayID: snapshot.displayID, screenFrame: snapshot.screenFrame,
            scale: screen.backingScaleFactor, dock: dock)
        self.onCancel = onCancel
        lifetime.begin(now: ProcessInfo.processInfo.systemUptime)
        window.orderFrontRegardless()
        drawNow()
        guard window.isVisible, view.hasDrawnImage else { dismiss(); return false }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.01
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        return true
    }

    func reveal(duration: TimeInterval = 0.12) async {
        guard let token = lifetime.beginReveal(), let view = canvas, let window = panel else { return }
        let duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0
            : MacDockSnapshotShieldPolicy.revealDuration(duration)
        let began = ProcessInfo.processInfo.systemUptime
        let initialOpacity = view.imageOpacity
        window.isOpaque = false
        window.backgroundColor = .clear
        // Keep the window's alpha at 1: alpha-zero windows can stop receiving
        // input before the stale screenshot has finished disappearing.
        while lifetime.canReveal(token) {
            guard !Task.isCancelled else { dismiss(); return }
            guard metadataIsCurrent else { requestCancellation(); return }
            let progress = duration > 0 ? min((ProcessInfo.processInfo.systemUptime - began) / duration, 1) : 1
            view.imageOpacity = initialOpacity * CGFloat(1 - progress)
            drawNow()
            if progress >= 1 { break }
            do { try await Task.sleep(for: .milliseconds(16)) }
            catch {
                if lifetime.canReveal(token) { dismiss() }
                return
            }
        }
        if lifetime.canReveal(token) { dismiss() }
    }

    func dismiss() {
        let inside = panel.map { $0.isVisible && $0.frame.contains(NSEvent.mouseLocation) } ?? false
        let finished = lifetime.dismiss(hardwareButtons: UInt64(NSEvent.pressedMouseButtons), pointerInside: inside)
        onCancel = nil
        metadata = nil
        // Release captured pixels immediately, even if an already-owned press
        // still needs its mouse-up consumed by the transparent window.
        canvas?.image = nil
        canvas?.imageOpacity = 0
        panel?.isOpaque = false
        panel?.backgroundColor = .clear
        drawNow()
        if finished { closeWindow() }
    }

    private var metadataIsCurrent: Bool {
        guard let metadata, CGPreflightScreenCaptureAccess(), !metadata.dock.isTerminated,
              let screen = NSScreen.screens.first(where: {
                  ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == metadata.displayID
              }) else { return false }
        return screen.frame == metadata.screenFrame && screen.backingScaleFactor == metadata.scale
    }

    private func tick() {
        if lifetime.phase == .draining {
            if lifetime.pollRelease(hardwareButtons: UInt64(NSEvent.pressedMouseButtons)) { closeWindow() }
        } else if lifetime.expired(now: ProcessInfo.processInfo.systemUptime) || !metadataIsCurrent {
            requestCancellation()
        }
    }

    private func requestCancellation() {
        guard lifetime.cancelOnce() else { return }
        let token = lifetime.generation
        let callback = onCancel
        callback?()
        // The callback may synchronously dismiss or replace this generation.
        if lifetime.generation == token { dismiss() }
    }

    private func consume(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            lifetime.press(event.buttonNumber)
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            lifetime.press(event.buttonNumber)
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            if lifetime.release(event.buttonNumber) { closeWindow(); return }
        default: break
        }
        requestCancellation()
    }

    private func drawNow() {
        guard let panel, let canvas else { return }
        canvas.needsDisplay = true
        canvas.displayIfNeeded()
        panel.displayIfNeeded()
        CATransaction.flush()
    }

    private func closeWindow() {
        timer?.invalidate()
        timer = nil
        canvas?.image = nil
        panel?.onInput = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel?.close()
        panel = nil
        canvas = nil
        metadata = nil
        onCancel = nil
    }

    deinit {
        timer?.invalidate()
        let window = panel
        let view = canvas
        Task { @MainActor in
            view?.image = nil
            window?.onInput = nil
            window?.orderOut(nil)
            window?.contentView = nil
            window?.close()
        }
    }
}

@MainActor
private final class MacDockSnapshotShieldPanel: NSPanel {
    var onInput: ((NSEvent) -> Void)?
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .leftMouseDragged, .leftMouseUp,
             .rightMouseDown, .rightMouseDragged, .rightMouseUp,
             .otherMouseDown, .otherMouseDragged, .otherMouseUp, .scrollWheel,
             .magnify, .rotate, .swipe, .smartMagnify, .pressure:
            onInput?(event)
            return
        case .keyDown where event.keyCode == 53:
            onInput?(event)
            return
        default: super.sendEvent(event)
        }
    }
}

@MainActor
private final class MacDockSnapshotShieldCanvas: NSView {
    var image: CGImage? { didSet { hasDrawnImage = false; needsDisplay = true } }
    var imageOpacity: CGFloat = 1 { didSet { needsDisplay = true } }
    private(set) var hasDrawnImage = false
    override var isOpaque: Bool { image != nil && imageOpacity >= 1 }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        MacDockSnapshotShieldRendering.draw(image, in: bounds, context: context, opacity: imageOpacity)
        hasDrawnImage = image != nil
    }
}
#endif
