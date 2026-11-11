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
            XCTAssertEqual(panelFocus, dropFocus,
                "The live circle must occupy the committed destination, including inside a larger hover canvas.")
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
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
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
