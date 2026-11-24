import AppKit
import SwiftUI
import XCTest
@testable import DaysYetMac

final class MacWidgetHandoffTests: XCTestCase {
    @MainActor
    func testDockLandingKeepsRealOverlayPixelsThroughNativeMoveAndDisplayHandoff() async throws {
        try await withWindow(reducesMotion: false, allowsDock: true) { controller, window, _ in
            let screen = try XCTUnwrap(NSScreen.screens.first)
            let docking = MacWidgetDocking(edge: .right, screenFrame: screen.frame,
                visibleFrame: screen.visibleFrame, systemDockEdge: .left)
            let focus = MacWidgetDragGeometry.focusFrame(in: window.frame, edge: .right, index: 1,
                scale: 1, metricCount: 3, topInfo: docking.topInfo)
            let drop = NSPoint(x: screen.frame.minX + 24, y: screen.frame.midY)
            var finishMove = false
            var waitingForMove = false
            var finishDisplay = false
            var waitingForDisplay = false
            controller.commitSystemDockDrop = { _, _ in
                waitingForMove = true
                while !finishMove, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(10)) }
                return !Task.isCancelled
            }
            controller.systemDockDisplayReady = {
                waitingForDisplay = true
                while !finishDisplay, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(10)) }
                return !Task.isCancelled
            }
            controller.nativeDockFrames = {
                Dictionary(uniqueKeysWithValues: controller.store.profile.macDashboardMetrics.enumerated().map {
                    ($0.element, NSRect(x: screen.frame.minX + 8,
                        y: screen.frame.midY - 90 + CGFloat($0.offset) * 60, width: 48, height: 48))
                })
            }
            controller.beginPointerPress(at: NSPoint(x: focus.midX, y: focus.midY), frame: window.frame,
                bounds: screen.visibleFrame, clickCount: 1, timestamp: 1, docking: docking)
            _ = controller.updatePointerPress(at: drop)
            let collected = try await eventually { controller.dragVisual?.coalescence == 1 }
            XCTAssertTrue(collected)
            guard case .drag(let placement) = controller.finishPointerPress(at: drop, doubleClickInterval: 0.5) else {
                return XCTFail("Expected a Dock drop")
            }
            controller.settleDrop(placement)
            let moving = try await eventually { waitingForMove }
            XCTAssertTrue(moving)
            let overlay = try XCTUnwrap(NSApp.windows.first {
                ($0.contentView as? NSHostingView<MacWidgetDragOverlay>)?.rootView.dockLanding != nil
            })
            let host = try XCTUnwrap(overlay.contentView as? NSHostingView<MacWidgetDragOverlay>)
            @MainActor func assertCarriedPixels() throws {
                XCTAssertTrue(overlay.isVisible)
                let metric = try XCTUnwrap(controller.dragOrigin?.metric)
                let circle = try XCTUnwrap(controller.dockLandingVisual?.tiles[metric]?.frame)
                host.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let x = Int((circle.midX - overlay.frame.minX) * CGFloat(bitmap.pixelsWide) / overlay.frame.width)
                let y = Int((overlay.frame.maxY - circle.midY) * CGFloat(bitmap.pixelsHigh) / overlay.frame.height)
                XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: x, y: y)).alphaComponent, 0.99)
            }
            try assertCarriedPixels()
            try await Task.sleep(for: .milliseconds(100))
            try assertCarriedPixels()
            finishMove = true
            let displaying = try await eventually { waitingForDisplay }
            XCTAssertTrue(displaying)
            try assertCarriedPixels()
            finishDisplay = true
            let finished = try await eventually { controller.dragVisual == nil }
            XCTAssertTrue(finished)
            XCTAssertFalse(overlay.isVisible)
        }
    }

    @MainActor
    func testLiveWidgetDrawsUnderTheOverlayBeforeLandingOrReturningFinishes() async throws {
        for reducesMotion in [false, true] {
            for edge: MacWidgetEdge? in [.bottom, .right, nil] {
                try await withWindow(reducesMotion: reducesMotion) { controller, window, host in
                    let (drop, overlay) = try await release(controller, window: window, at: edge)
                    var drewWhileCovered = false
                    host.onDraw = {
                        if host.alphaValue == 1, overlay.isVisible {
                            drewWhileCovered = true
                        }
                    }
                    controller.settleDrop(drop)
                    let finished = try await eventually { controller.dragVisual == nil }
                    XCTAssertTrue(finished)
                    XCTAssertTrue(drewWhileCovered, "A landing must render the live widget before dismissing its moving image.")
                    XCTAssertTrue(window.isVisible)
                    XCTAssertEqual(host.alphaValue, 1)
                    XCTAssertFalse(overlay.isVisible)
                    XCTAssertEqual(controller.preferences.edge, edge ?? .right)
                    XCTAssertFalse(controller.isHandingOffToEdge)
                }
            }
        }
    }

    @MainActor
    func testReleasingATrailingPreviewAnimatesToTheCommittedPanelBeforeHandoff() async throws {
        try await withWindow(reducesMotion: false, supportsSystemDock: false) { controller, window, host in
            let (drop, overlay) = try await release(controller, window: window, at: .bottom, slideBeforeRelease: 120)
            let trailing = try XCTUnwrap(controller.dragVisual)
            XCTAssertEqual(trailing.coalescence, 0)
            XCTAssertGreaterThan(abs(trailing.imageFrame.minX - drop.frame.minX), 1)
            var drewWhileCovered = false
            host.onDraw = {
                if host.alphaValue == 1, overlay.isVisible { drewWhileCovered = true }
            }
            controller.settleDrop(drop)
            XCTAssertEqual(controller.dragVisual?.imageFrame, trailing.imageFrame,
                "Releasing must start the landing from the visible position, without snapping ahead.")
            let panelFocus = MacWidgetDragGeometry.focusFrame(in: window.frame, edge: .bottom,
                index: 1, scale: 1, metricCount: 3, topInfo: MacTopNotchInfo())
            let dropFocus = MacWidgetDragGeometry.focusFrame(in: drop.frame, edge: .bottom,
                index: 1, scale: 1, metricCount: 3, topInfo: MacTopNotchInfo())
            // Recomputing the saved normalized position may differ by a single
            // floating-point bit; still require far less than a physical pixel.
            for (actual, expected) in [(panelFocus.minX, dropFocus.minX), (panelFocus.minY, dropFocus.minY),
                                       (panelFocus.width, dropFocus.width), (panelFocus.height, dropFocus.height)] {
                XCTAssertEqual(actual, expected, accuracy: 0.000001,
                    "The live circle must occupy the committed destination, including inside a larger hover canvas.")
            }
            XCTAssertTrue(overlay.isVisible)
            XCTAssertEqual(host.alphaValue, 0)
            let finished = try await eventually { controller.dragVisual == nil }
            XCTAssertTrue(finished)
            XCTAssertTrue(drewWhileCovered)
            XCTAssertEqual(host.alphaValue, 1)
            XCTAssertFalse(overlay.isVisible)
            XCTAssertEqual(controller.preferences.edge, .bottom)
            XCTAssertEqual(controller.preferences.horizontalPosition, drop.position)
        }
    }

    @MainActor
    func testReleasingDuringHeldFlightReachesTheEdgeBeforeUnfolding() async throws {
        try await withWindow(reducesMotion: false, supportsSystemDock: false) { controller, window, host in
            let screen = try XCTUnwrap(NSScreen.screens.first)
            let docking = MacWidgetDocking(edge: .right, screenFrame: screen.frame, visibleFrame: screen.visibleFrame)
            let sourceFocus = MacWidgetDragGeometry.focusFrame(in: window.frame, edge: .right, index: 1,
                scale: 1, metricCount: 3, topInfo: docking.topInfo)
            controller.beginPointerPress(at: NSPoint(x: sourceFocus.midX, y: sourceFocus.midY), frame: window.frame,
                bounds: screen.visibleFrame, clickCount: 1, timestamp: 1, docking: docking)
            let point = NSPoint(x: screen.frame.minX + 20, y: screen.frame.midY)
            let preview = try XCTUnwrap(controller.updatePointerPress(at: point)?.attachment)
            XCTAssertEqual(preview.edge, .left)
            // Switching the visual's geometry to the target marks the start of
            // held flight, after collection but before the circle arrives.
            let flying = try await eventually {
                controller.dragVisual?.widgetFrame == preview.frame && controller.dragVisual?.coalescence == 1
            }
            XCTAssertTrue(flying)
            let beforeRelease = try XCTUnwrap(controller.dragVisual)
            XCTAssertGreaterThan(abs(beforeRelease.circleFrame.midX - preview.frame.midX), 20)
            let overlay = try XCTUnwrap(NSApp.windows.first {
                $0.isVisible && $0.contentView is NSHostingView<MacWidgetDragOverlay>
            })
            var drewWhileCovered = false
            host.onDraw = {
                if host.alphaValue == 1, overlay.isVisible { drewWhileCovered = true }
            }
            guard case .drag(let drop) = controller.finishPointerPress(at: point, doubleClickInterval: 0.5) else {
                return XCTFail("Expected a completed edge drop during flight")
            }
            controller.settleDrop(drop)
            XCTAssertEqual(controller.dragVisual?.circleFrame, beforeRelease.circleFrame,
                "Releasing must continue from the visible circle instead of jumping to the edge.")
            let destination = MacWidgetDragGeometry.focusFrame(in: window.frame, edge: .left, index: 1,
                scale: 1, metricCount: 3, topInfo: docking.topInfo)
            var sawFlight = false
            var sawUnfolding = false
            let finished = try await eventually {
                guard let visual = controller.dragVisual else { return true }
                let remaining = hypot(visual.circleFrame.midX - destination.midX,
                                      visual.circleFrame.midY - destination.midY)
                if remaining > 0.001 {
                    sawFlight = true
                    XCTAssertEqual(visual.coalescence, 1,
                        "The rail must not unfold while the released circle is still traveling to the edge.")
                } else if visual.coalescence < 1 {
                    sawUnfolding = true
                }
                return false
            }
            XCTAssertTrue(finished)
            XCTAssertTrue(sawFlight)
            XCTAssertTrue(sawUnfolding)
            XCTAssertTrue(drewWhileCovered)
            XCTAssertEqual(host.alphaValue, 1)
            XCTAssertFalse(overlay.isVisible)
            XCTAssertEqual(controller.preferences.edge, .left)
        }
    }

    @MainActor
    func testPullingAwayDuringUnfoldingCollectsExactlyTheVisibleSurface() async throws {
        try await withWindow(reducesMotion: false, supportsSystemDock: false) { controller, window, _ in
            let (point, overlay, overlayHost) = try await beginPartialUnfold(controller, window: window)
            let partial = try XCTUnwrap(controller.dragVisual)
            let frame = partial.renderedFrame
            let screen = try XCTUnwrap(NSScreen.screens.first)
            XCTAssertEqual(overlayHost.rootView.visual, partial)
            let before = try render(overlayHost.rootView, in: frame, scale: screen.backingScaleFactor)
            XCTAssertEqual(controller.dragVisual, partial)
            let center = NSPoint(x: screen.frame.midX, y: point.y)
            let detached = try XCTUnwrap(controller.updatePointerPress(at: center))
            XCTAssertNil(detached.attachment)
            let collectedStart = try XCTUnwrap(controller.dragVisual)
            XCTAssertNil(collectedStart.attachmentEdge)
            XCTAssertEqual(collectedStart.coalescence, 0)
            XCTAssertEqual(collectedStart.imageFrame, frame,
                "Recollection must begin from the visible rail's position and size.")
            XCTAssertEqual(collectedStart.circleFrame, partial.circleFrame)
            let collecting = try await eventually { overlayHost.rootView.visual.attachmentEdge == nil }
            XCTAssertTrue(collecting)
            let frozen = try XCTUnwrap(overlayHost.rootView.widgetImage)
            let frozenImage = try XCTUnwrap(frozen.cgImage(forProposedRect: nil, context: nil, hints: nil))
            // NSImage may use the display's profile while ImageRenderer uses
            // sRGB. Normalize the bitmaps before comparing component values.
            let after = try XCTUnwrap(NSBitmapImageRep(cgImage: frozenImage)
                .converting(to: .sRGB, renderingIntent: .relativeColorimetric))
            XCTAssertEqual(after.pixelsWide, before.pixelsWide)
            XCTAssertEqual(after.pixelsHigh, before.pixelsHigh)
            var maximumDifference: CGFloat = 0
            for y in 0..<min(before.pixelsHigh, after.pixelsHigh) {
                for x in 0..<min(before.pixelsWide, after.pixelsWide) {
                    let lhs = try XCTUnwrap(before.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                    let rhs = try XCTUnwrap(after.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                    maximumDifference = max(maximumDifference, abs(lhs.alphaComponent - rhs.alphaComponent))
                    if max(lhs.alphaComponent, rhs.alphaComponent) > 0.01 {
                        maximumDifference = max(maximumDifference, abs(lhs.redComponent - rhs.redComponent),
                            abs(lhs.greenComponent - rhs.greenComponent), abs(lhs.blueComponent - rhs.blueComponent))
                    }
                }
            }
            XCTAssertLessThanOrEqual(maximumDifference, 2.0 / 255,
                "The collection snapshot must contain the partial reveal, not the complete unrevealed rail.")
            let carried = try await eventually { controller.dragVisual?.coalescence == 1 }
            XCTAssertTrue(carried)
            guard case .drag(let drop) = controller.finishPointerPress(at: center, doubleClickInterval: 0.5) else {
                return XCTFail("Expected a completed center release")
            }
            XCTAssertNil(drop.target)
            controller.settleDrop(drop)
            let finished = try await eventually { controller.dragVisual == nil }
            XCTAssertTrue(finished)
            XCTAssertEqual(controller.preferences.edge, .right)
            XCTAssertFalse(overlay.isVisible)
            XCTAssertEqual(window.contentView?.alphaValue, 1)
        }
    }

    @MainActor
    func testReleasingDuringUnfoldingKeepsTheAttachedCircleAndWallFixed() async throws {
        try await withWindow(reducesMotion: false, supportsSystemDock: false) { controller, window, host in
            let (point, overlay, _) = try await beginPartialUnfold(controller, window: window)
            let partial = try XCTUnwrap(controller.dragVisual)
            guard case .drag(let drop) = controller.finishPointerPress(at: point, doubleClickInterval: 0.5) else {
                return XCTFail("Expected a completed release during unfolding")
            }
            controller.settleDrop(drop)
            XCTAssertEqual(controller.dragVisual, partial,
                "Mouse-up must not replace the attached presentation or restart from a carried circle.")
            var previousCoalescence = partial.coalescence
            var sawContinuation = false
            let finished = try await eventually {
                guard let visual = controller.dragVisual else { return true }
                XCTAssertEqual(visual.attachmentEdge, .left)
                XCTAssertEqual(visual.circleFrame, partial.circleFrame)
                XCTAssertEqual(visual.imageFrame.minX, partial.imageFrame.minX, accuracy: 0.000001)
                XCTAssertEqual(visual.circleOpacity, 0, "Only the native snapshot may draw the attached circle.")
                XCTAssertLessThanOrEqual(visual.coalescence, previousCoalescence)
                if visual.coalescence < partial.coalescence { sawContinuation = true }
                previousCoalescence = visual.coalescence
                return false
            }
            XCTAssertTrue(finished)
            XCTAssertTrue(sawContinuation)
            XCTAssertEqual(controller.preferences.edge, .left)
            XCTAssertFalse(overlay.isVisible)
            XCTAssertEqual(host.alphaValue, 1)
        }
    }

    @MainActor
    func testEscapeAndHideDuringHandoffCannotRestartOrResurrectTheDrag() async throws {
        for hide in [false, true] {
            try await withWindow(reducesMotion: false) { controller, window, host in
                let (drop, overlay) = try await release(controller, window: window, at: .bottom)
                controller.settleDrop(drop)
                let revealing = try await eventually { controller.isHandingOffToEdge }
                XCTAssertTrue(revealing)
                if hide { controller.hideWidget() }
                else { controller.closeDetails() }
                try await Task.sleep(for: .milliseconds(150))
                XCTAssertNil(controller.dragVisual)
                XCTAssertFalse(controller.isHandingOffToEdge)
                XCTAssertFalse(overlay.isVisible)
                XCTAssertEqual(window.isVisible, !hide)
                XCTAssertEqual(host.alphaValue, 1)
                XCTAssertEqual(controller.preferences.edge, .bottom, "Escape finishes an already committed landing.")
            }
        }
    }

    @MainActor
    func testChangingDisplayModeBeforeHandoffStartsCannotLeaveTheOverlayStuck() async throws {
        try await withWindow(reducesMotion: false) { controller, window, _ in
            let (drop, overlay) = try await release(controller, window: window, at: .bottom)
            controller.settleDrop(drop)
            controller.preferences.isInSystemDock = true
            let finished = try await eventually { controller.dragVisual == nil }
            XCTAssertTrue(finished)
            XCTAssertTrue(controller.preferences.isInSystemDock)
            XCTAssertFalse(controller.isHandingOffToEdge)
            XCTAssertFalse(overlay.isVisible)
            XCTAssertFalse(window.isVisible)
        }
    }

    @MainActor
    private func beginPartialUnfold(_ controller: MacWidgetController, window: NSWindow) async throws
        -> (NSPoint, NSWindow, NSHostingView<MacWidgetDragOverlay>) {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let docking = MacWidgetDocking(edge: .right, screenFrame: screen.frame, visibleFrame: screen.visibleFrame)
        let focus = MacWidgetDragGeometry.focusFrame(in: window.frame, edge: .right, index: 1,
            scale: 1, metricCount: 3, topInfo: docking.topInfo)
        controller.beginPointerPress(at: NSPoint(x: focus.midX, y: focus.midY), frame: window.frame,
            bounds: screen.visibleFrame, clickCount: 1, timestamp: 1, docking: docking)
        let point = NSPoint(x: screen.frame.minX + 20, y: screen.frame.midY)
        _ = controller.updatePointerPress(at: point)
        let partial = try await eventually {
            guard let visual = controller.dragVisual else { return false }
            return visual.attachmentEdge == .left && visual.coalescence < 0.75 && visual.coalescence > 0.2
        }
        XCTAssertTrue(partial)
        let overlay = try XCTUnwrap(NSApp.windows.first {
            $0.isVisible && $0.contentView is NSHostingView<MacWidgetDragOverlay>
        })
        return (point, overlay, try XCTUnwrap(overlay.contentView as? NSHostingView<MacWidgetDragOverlay>))
    }

    @MainActor
    private func render(_ view: MacWidgetDragOverlay, in frame: NSRect, scale: CGFloat) throws -> NSBitmapImageRep {
        var preview = view
        preview.canvasFrame = frame
        let renderer = ImageRenderer(content: preview)
        renderer.scale = scale
        return try XCTUnwrap(NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
            .converting(to: .sRGB, renderingIntent: .relativeColorimetric))
    }

    @MainActor
    private func release(_ controller: MacWidgetController, window: NSWindow,
                         at edge: MacWidgetEdge?, slideBeforeRelease: CGFloat = 0) async throws -> (MacWidgetPointerInteraction.Placement, NSWindow) {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let docking = MacWidgetDocking(edge: .right, screenFrame: screen.frame, visibleFrame: screen.visibleFrame)
        let frame = window.frame
        let focus = MacWidgetDragGeometry.focusFrame(in: frame, edge: .right, index: 1, scale: 1,
            metricCount: 3, topInfo: docking.topInfo)
        controller.beginPointerPress(at: NSPoint(x: focus.midX, y: focus.midY), frame: frame,
            bounds: screen.visibleFrame, clickCount: 1, timestamp: 1, docking: docking)
        let center = NSPoint(x: screen.frame.midX, y: screen.frame.midY)
        _ = controller.updatePointerPress(at: center)
        let point: NSPoint
        if edge == .bottom { point = NSPoint(x: center.x, y: screen.frame.minY + 20) }
        else if edge == .right { point = NSPoint(x: screen.frame.maxX - 20, y: center.y) }
        else { point = center }
        let preview = controller.updatePointerPress(at: point)
        let arrived = try await eventually {
            if edge != nil {
                return controller.dragVisual?.coalescence == 0
                    && controller.dragVisual?.widgetFrame == preview?.target?.frame
            }
            return controller.dragVisual?.coalescence == 1
        }
        XCTAssertTrue(arrived)
        let overlay = try XCTUnwrap(NSApp.windows.first {
            $0.isVisible && $0.contentView is NSHostingView<MacWidgetDragOverlay>
        })
        XCTAssertEqual(window.contentView?.alphaValue, 0)
        let releasePoint = NSPoint(x: point.x + slideBeforeRelease, y: point.y)
        if slideBeforeRelease != 0 { _ = controller.updatePointerPress(at: releasePoint) }
        guard case .drag(let drop) = controller.finishPointerPress(at: releasePoint, doubleClickInterval: 0.5) else {
            throw NSError(domain: "Expected completed drag", code: 1)
        }
        return (drop, overlay)
    }

    @MainActor
    private func withWindow(reducesMotion: Bool, allowsDock: Bool = false,
                            supportsSystemDock: Bool = true,
                            _ body: (MacWidgetController, NSWindow, DrawRecordingWidgetHost) async throws -> Void) async throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "A WindowServer display is required for drawing-order coverage.")
        let suite = "com.hinoshiba.daysyet.handoff.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let preferences = MacWidgetPreferences(defaults: defaults, supportsSystemDock: supportsSystemDock, readDockPermission: { allowsDock })
        preferences.edge = .right
        preferences.verticalPosition = 0.24
        preferences.magnifiesOnHover = true
        preferences.hoverScale = 1.55
        let controller = MacWidgetController(store: ProfileStore(profile: .initial, saveProfile: { _ in }),
            preferences: preferences, reducesMotion: { reducesMotion })
        let previousWindows = Set(NSApp.windows.map(ObjectIdentifier.init))
        // Exercise our own AppKit/SwiftUI windows with isolated preferences and
        // a synthetic profile. No mouse events or other applications are driven.
        controller.start()
        defer {
            controller.hideWidget()
            for window in NSApp.windows where !previousWindows.contains(ObjectIdentifier(window)) {
                (window.contentView as? DrawRecordingWidgetHost)?.onDraw = nil
                window.contentView = nil
                window.close()
            }
            defaults.removePersistentDomain(forName: suite)
        }
        let window = try XCTUnwrap(NSApp.windows.first {
            ($0.contentView as? NSHostingView<MacDesktopWidgetView>)?.rootView.controller === controller
        })
        let original = try XCTUnwrap(window.contentView as? NSHostingView<MacDesktopWidgetView>)
        let host = DrawRecordingWidgetHost(rootView: original.rootView)
        window.contentView = host
        try await body(controller, window, host)
    }

    @MainActor
    private func eventually(_ predicate: () -> Bool) async throws -> Bool {
        // Flight duration follows distance, so real large displays need more
        // time than the former fixed-duration return plus unfolding.
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !predicate(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        return predicate()
    }
}

@MainActor
private final class DrawRecordingWidgetHost: NSHostingView<MacDesktopWidgetView> {
    var onDraw: (() -> Void)?

    override func viewWillDraw() {
        super.viewWillDraw()
        onDraw?()
    }
}
