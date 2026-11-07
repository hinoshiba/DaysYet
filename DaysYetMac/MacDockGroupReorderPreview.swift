#if DAYSYET_DIRECT_DOCK_DRAG && DAYSYET_DOCK_NATIVE_REORDER
import AppKit
import QuartzCore
import SwiftUI

/// Keeps the circles visible while their existing native Dock slots are moved.
/// The caller owns the handoff to and from the real tiles.
@MainActor
final class MacDockGroupReorderPreview {
    private var panel: MacDockGroupReorderPanel?
    private var canvas: MacDockGroupReorderCanvas?
    private var screenFrame = NSRect.zero
    private var screenNumber: NSNumber?
    private var frames: [MetricKind: NSRect] = [:]
    private var generation: UInt = 0

    /// A failed preparation leaves an already visible preview intact. In
    /// particular, the caller must not hide native tiles when this returns false.
    @discardableResult
    func show(frames: [MetricKind: NSRect], presentations: [MacSystemDockPresentation]) -> Bool {
        let kinds = presentations.map(\.snapshot.kind)
        guard !Task.isCancelled, Self.valid(frames), kinds.count == frames.count,
              Set(kinds).count == kinds.count, Set(kinds) == Set(frames.keys),
              let screen = NSScreen.screens.first(where: { screen in
                  frames.values.allSatisfy { screen.frame.contains($0) }
              }) else { return false }

        // Render the same view used by the native helpers before changing any
        // windows. A plain AppKit canvas can then draw its first frame
        // synchronously, without waiting for SwiftUI's next update pass.
        let largestSide = frames.values.reduce(CGFloat(128)) { max($0, $1.width, $1.height) }
        let renderScale = max(screen.backingScaleFactor, largestSide * screen.backingScaleFactor / 128)
        var images: [MetricKind: NSImage] = [:]
        for var presentation in presentations {
            guard !Task.isCancelled else { return false }
            // Native helpers may already be dimmed for a captured drag. Their
            // replacement must remain fully visible until the caller dismisses it.
            presentation.opacity = 1
            let renderer = ImageRenderer(content: MacSystemDockTileView(presentation: presentation))
            renderer.scale = renderScale
            guard let image = renderer.nsImage else { return false }
            images[presentation.snapshot.kind] = image
        }

        generation &+= 1
        let window = panel ?? MacDockGroupReorderPanel(contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let view = canvas ?? MacDockGroupReorderCanvas(frame: NSRect(origin: .zero, size: screen.frame.size))
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.level = .statusBar
        window.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces, .stationary]
        view.autoresizingMask = [.width, .height]
        view.wantsLayer = true
        view.setAccessibilityElement(false)
        window.contentView = view
        window.setFrame(screen.frame, display: false)
        view.frame = NSRect(origin: .zero, size: screen.frame.size)
        view.prepare(screen: screen.frame, frames: frames, images: images, order: kinds)
        panel = window
        canvas = view
        screenFrame = screen.frame
        screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        self.frames = frames

        window.orderFrontRegardless()
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        view.display()
        flush(window)
        let ready = window.isVisible && view.hasDrawnCurrentRevision
        if !ready { dismiss() }
        return ready
    }

    /// Frames use AppKit's global, bottom-left coordinate system. The panel
    /// stays fixed to its screen; only the cached circles move inside it.
    func animate(to destination: [MetricKind: NSRect], duration: TimeInterval) async {
        guard !Task.isCancelled, let window = panel, let view = canvas, window.isVisible,
              Self.valid(destination), Set(destination.keys) == Set(frames.keys),
              destination.values.allSatisfy({ screenFrame.contains($0) }), duration.isFinite,
              screenIsPresent else { return }
        generation &+= 1
        let currentGeneration = generation
        let origin = frames
        if duration <= 0 {
            frames = destination
            view.update(frames: destination)
            view.displayIfNeeded()
            flush(window)
            return
        }
        let started = ProcessInfo.processInfo.systemUptime
        while !Task.isCancelled, currentGeneration == generation, screenIsPresent {
            let progress = min(max((ProcessInfo.processInfo.systemUptime - started) / duration, 0), 1)
            let eased = CGFloat(1 - pow(1 - progress, 3))
            frames = destination
            if progress < 1 {
                for (kind, to) in destination {
                    guard let from = origin[kind] else { continue }
                    frames[kind] = NSRect(x: from.minX + (to.minX - from.minX) * eased,
                                          y: from.minY + (to.minY - from.minY) * eased,
                                          width: from.width + (to.width - from.width) * eased,
                                          height: from.height + (to.height - from.height) * eased)
                }
            }
            view.update(frames: frames)
            view.displayIfNeeded()
            flush(window)
            if progress >= 1 { return }
            do { try await Task.sleep(for: .milliseconds(16)) }
            catch { return }
        }
    }

    func dismiss() {
        generation &+= 1
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
        canvas = nil
        frames = [:]
        screenFrame = .zero
        screenNumber = nil
    }

    private var screenIsPresent: Bool {
        NSScreen.screens.contains { screen in
            screen.frame == screenFrame &&
                (screenNumber == nil || screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber == screenNumber)
        }
    }

    private static func valid(_ frames: [MetricKind: NSRect]) -> Bool {
        (1...8).contains(frames.count) && frames.values.allSatisfy { frame in
            [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite) &&
                (8...512).contains(frame.width) && (8...512).contains(frame.height)
        }
    }

    private func flush(_ window: NSWindow) {
        window.displayIfNeeded()
        CATransaction.flush()
    }
}

@MainActor
private final class MacDockGroupReorderPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor
private final class MacDockGroupReorderCanvas: NSView {
    private var screenFrame = NSRect.zero
    private var frames: [MetricKind: NSRect] = [:]
    private var images: [MetricKind: NSImage] = [:]
    private var order: [MetricKind] = []
    private var revision: UInt = 0
    private var drawnRevision: UInt?

    override var isOpaque: Bool { false }
    var hasDrawnCurrentRevision: Bool { drawnRevision == revision }

    func prepare(screen: NSRect, frames: [MetricKind: NSRect], images: [MetricKind: NSImage], order: [MetricKind]) {
        screenFrame = screen
        self.frames = frames
        self.images = images
        self.order = order
        revision &+= 1
        needsDisplay = true
    }

    func update(frames: [MetricKind: NSRect]) {
        let changed = Array(self.frames.values) + Array(frames.values)
        self.frames = frames
        revision &+= 1
        for frame in changed {
            setNeedsDisplay(frame.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY).insetBy(dx: -1, dy: -1))
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current else { return }
        context.cgContext.clear(dirtyRect)
        context.imageInterpolation = .high
        for kind in order {
            guard let frame = frames[kind], let image = images[kind] else { continue }
            // Preserve the native square image's aspect ratio even when an AX
            // tile frame includes extra width or height around its contents.
            let side = min(frame.width, frame.height)
            let rect = NSRect(x: frame.midX - side / 2 - screenFrame.minX,
                              y: frame.midY - side / 2 - screenFrame.minY,
                              width: side, height: side)
            guard rect.intersects(dirtyRect) else { continue }
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
        }
        context.flushGraphics()
        drawnRevision = revision
    }
}
#endif
