import AppKit
import SwiftUI
import XCTest
@testable import DaysYetMac

final class MacWidgetAttachmentTests: XCTestCase {
    private let screen = NSRect(x: -1600, y: 120, width: 1600, height: 1000)
    private var visible: NSRect { NSRect(x: -1600, y: 200, width: 1600, height: 888) }

    @MainActor
    func testVisualLagDoesNotDelayTheDrop() async throws {
        try await withController(reducesMotion: false) { controller, preferences in
            begin(controller)
            let first = NSPoint(x: screen.midX, y: screen.midY)
            _ = controller.updatePointerPress(at: first)
            let collected = try await eventually { controller.dragVisual?.coalescence == 1 }
            XCTAssertTrue(collected)
            let next = NSPoint(x: first.x + 100, y: first.y + 60)
            _ = controller.updatePointerPress(at: next)
            XCTAssertNotEqual(controller.dragVisual?.circleFrame.midX, next.x, "Only the visual should trail the pointer.")
            let caughtUp = try await eventually { controller.dragVisual?.circleFrame.midX == next.x }
            XCTAssertTrue(caughtUp, "The preview must catch up even without another input event.")

            let dropPoint = point(at: .bottom, distance: 20)
            guard case .drag(let drop) = controller.finishPointerPress(at: dropPoint, doubleClickInterval: 0.5) else {
                return XCTFail("Expected a drag")
            }
            XCTAssertEqual(drop.target?.edge, .bottom, "Mouse-up must use the latest pointer even while the visual is behind.")
            controller.settleDrop(drop)
            XCTAssertEqual(preferences.edge, .bottom)
            XCTAssertNil(controller.dragVisual)
        }
    }

    @MainActor
    func testCancelStopsFollowingWithoutRestoringAStalePreview() async throws {
        try await withController(reducesMotion: false) { controller, preferences in
            begin(controller)
            let first = NSPoint(x: screen.midX, y: screen.midY)
            _ = controller.updatePointerPress(at: first)
            let collected = try await eventually { controller.dragVisual?.coalescence == 1 }
            XCTAssertTrue(collected)
            _ = controller.updatePointerPress(at: NSPoint(x: first.x + 100, y: first.y + 60))
            controller.closeDetails()
            try await Task.sleep(for: .milliseconds(400))
            XCTAssertNil(controller.dragVisual)
            XCTAssertEqual(preferences.edge, .right, "Canceling must preserve the original placement.")
        }
    }

    @MainActor
    func testEdgeSlideKeepsItsShapeWhileFollowingAndSavesTheLatestPoint() async throws {
        try await withController(reducesMotion: false) { controller, preferences in
            preferences.edge = .bottom
            let docking = MacWidgetDocking(edge: .bottom, screenFrame: screen, visibleFrame: visible)
            let frame = docking.frame(edge: .bottom, position: 0.5)
            let anchor = NSPoint(x: frame.midX, y: frame.midY)
            controller.beginPointerPress(at: anchor, frame: frame, bounds: visible, clickCount: 1, timestamp: 1, docking: docking)
            _ = controller.updatePointerPress(at: NSPoint(x: anchor.x + 6, y: anchor.y))
            let previous = try XCTUnwrap(controller.dragVisual)
            let end = NSPoint(x: anchor.x + 120, y: anchor.y)
            let placement = try XCTUnwrap(controller.updatePointerPress(at: end))
            XCTAssertTrue(placement.isSlidingAlongEdge)
            XCTAssertEqual(controller.dragVisual?.circleFrame, previous.circleFrame)
            XCTAssertEqual(controller.dragVisual?.coalescence, 0)
            guard case .drag(let drop) = controller.finishPointerPress(at: end, doubleClickInterval: 0.5) else {
                return XCTFail("Expected a slide")
            }
            controller.settleDrop(drop)
            XCTAssertEqual(preferences.horizontalPosition, placement.position)
            controller.closeDetails()
            try await Task.sleep(for: .milliseconds(400))
            XCTAssertNil(controller.dragVisual)
        }
    }

    @MainActor
    func testBottomRailSlidesWithoutMorphingFromTheFirstMovement() async throws {
        try await withController { controller, preferences in
            preferences.edge = .bottom
            let visible = NSRect(x: screen.minX + 80, y: screen.minY, width: screen.width - 80, height: screen.height - 32)
            let docking = MacWidgetDocking(edge: .bottom, screenFrame: screen, visibleFrame: visible, systemDockEdge: .left)
            let frame = docking.frame(edge: .bottom, position: 0.5)
            let point = NSPoint(x: frame.midX, y: frame.midY)
            XCTAssertEqual(frame.minY, screen.minY, "The rail is attached to the physical bottom edge.")
            controller.beginPointerPress(at: point, frame: frame, bounds: visible, clickCount: 1, timestamp: 1, docking: docking)
            for offset in [CGFloat(6), 20, 80, 120] {
                let update = try XCTUnwrap(controller.updatePointerPress(at: NSPoint(x: point.x + offset, y: point.y)))
                XCTAssertTrue(update.isSlidingAlongEdge)
                XCTAssertEqual(controller.dragVisual?.coalescence, 0)
                XCTAssertEqual(controller.dragVisual?.widgetFrame.width, frame.width)
                XCTAssertEqual(controller.dragVisual?.widgetFrame.minX ?? 0, frame.minX + offset, accuracy: 0.001)
                XCTAssertEqual(preferences.horizontalPosition, 0.72, "A held slide is still only a preview.")
            }
            let release = NSPoint(x: point.x + 120, y: point.y)
            guard case .drag(let placement) = controller.finishPointerPress(at: release, doubleClickInterval: 0.5) else {
                return XCTFail("Expected a completed slide")
            }
            XCTAssertTrue(placement.isSlidingAlongEdge)
            XCTAssertEqual(controller.dragVisual?.coalescence, 0)
            controller.saveDrop(placement)
            XCTAssertEqual(preferences.edge, .bottom)
            XCTAssertFalse(preferences.isInSystemDock)
            XCTAssertEqual(preferences.horizontalPosition, placement.position)
        }
    }

    @MainActor
    func testSlidingBottomRailOnlyCollectsWhenPulledInwardAndCanReachAnotherEdge() async throws {
        try await withController { controller, preferences in
            preferences.edge = .bottom
            let visible = NSRect(x: screen.minX + 80, y: screen.minY, width: screen.width - 80, height: screen.height - 32)
            let docking = MacWidgetDocking(edge: .bottom, screenFrame: screen, visibleFrame: visible, systemDockEdge: .left)
            let frame = docking.frame(edge: .bottom, position: 0.5)
            let point = NSPoint(x: frame.midX, y: frame.midY)
            controller.beginPointerPress(at: point, frame: frame, bounds: visible, clickCount: 1, timestamp: 1, docking: docking)
            _ = controller.updatePointerPress(at: NSPoint(x: point.x + 100, y: point.y))
            _ = controller.updatePointerPress(at: NSPoint(x: point.x + 100, y: point.y + 31))
            XCTAssertEqual(controller.dragVisual?.coalescence, 0)
            let pulled = try XCTUnwrap(controller.updatePointerPress(at: NSPoint(x: point.x + 100, y: point.y + 32)))
            XCTAssertFalse(pulled.isSlidingAlongEdge)
            XCTAssertNil(pulled.attachment)
            XCTAssertEqual(controller.dragVisual?.coalescence, 1)
            _ = controller.updatePointerPress(at: self.point(at: .right, distance: 20))
            XCTAssertEqual(controller.dragAttachment?.edge, .right)
            XCTAssertEqual(controller.dragVisual?.coalescence, 0)
            controller.closeDetails()
        }
    }

    private func point(at edge: MacWidgetEdge, distance: CGFloat = 1) -> NSPoint {
        switch edge {
        case .left: NSPoint(x: screen.minX + distance, y: screen.midY)
        case .right: NSPoint(x: screen.maxX - distance, y: screen.midY)
        case .top: NSPoint(x: screen.midX, y: screen.maxY - distance)
        case .bottom: NSPoint(x: screen.midX, y: visible.minY + distance)
        }
    }

    @MainActor
    func testLandingPreviewsRenderEveryCircleWithoutChangingTheSourceLayout() async throws {
        try await withController { controller, preferences in
            while controller.store.profile.macDashboardMetrics.count < MetricKind.allCases.count {
                controller.store.addMacDashboardMetric()
            }
            preferences.scale = 1.5
            preferences.keepDetailsOpen = true
            controller.showWidget()
            let docking = MacWidgetDocking(edge: .right, screenFrame: screen, visibleFrame: visible,
                topInfo: MacTopNotchInfo(cameraInset: 32, notchWidth: 180, centerX: screen.midX), scale: 1.5,
                metricCount: controller.store.profile.macDashboardMetrics.count)
            for edge in MacWidgetEdge.allCases {
                let frame = docking.frame(edge: edge, position: 0.5)
                let renderer = ImageRenderer(content: MacDesktopWidgetView(store: controller.store, preferences: preferences,
                    controller: controller, previewEdge: edge, previewTopInfo: docking.topInfo)
                    .frame(width: frame.width, height: frame.height))
                let image = try XCTUnwrap(renderer.cgImage)
                let bitmap = NSBitmapImageRep(cgImage: image)
                let metrics = controller.store.profile.macWidgetMetrics(for: edge)
                for index in metrics.indices {
                    let focus = MacWidgetDragGeometry.focusFrame(in: frame, edge: edge, index: index,
                        scale: 1.5, metricCount: metrics.count, topInfo: docking.topInfo)
                    let color = try XCTUnwrap(bitmap.colorAt(x: Int(focus.midX - frame.minX), y: Int(frame.maxY - focus.midY)))
                    XCTAssertGreaterThan(color.alphaComponent, 0.99, "Every circle/segment must remain visible in its preview.")
                }
                let attachment = XCTAttachment(image: NSImage(cgImage: image, size: frame.size))
                attachment.name = "Held edge preview - \(edge.rawValue)"
                attachment.lifetime = .keepAlways
                add(attachment)
                XCTAssertEqual(preferences.edge, .right)
                XCTAssertTrue(preferences.keepDetailsOpen)
            }
        }
    }

    @MainActor
    func testExpandedHitCircleUnfoldsAtEveryScaleWithoutSavingThePreview() async throws {
        try await withController { controller, preferences in
            for (scale, radius, contactRadius) in [(0.8, CGFloat(16), CGFloat(24)), (1.0, 20, 30), (1.5, 23, 34.5)] {
                preferences.scale = scale
                for edge in MacWidgetEdge.allCases {
                    begin(controller)
                    _ = controller.updatePointerPress(at: NSPoint(x: screen.midX, y: screen.midY))
                    let approached = try XCTUnwrap(controller.updatePointerPress(at: point(at: edge, distance: 150)))
                    XCTAssertEqual(approached.target?.edge, edge)
                    XCTAssertNil(approached.attachment)
                    XCTAssertEqual(controller.dragVisual?.coalescence, 1)

                    let beforeContact = point(at: edge, distance: contactRadius + 1)
                    let floating = try XCTUnwrap(controller.updatePointerPress(at: beforeContact))
                    XCTAssertNil(floating.attachment, "Stay floating one point outside the enlarged hit area.")
                    XCTAssertEqual(controller.dragVisual?.coalescence, 1)
                    let circle = try XCTUnwrap(controller.dragVisual?.circleFrame)
                    XCTAssertEqual(circle.width, radius * 2, accuracy: 0.000001, "Only the hit area should grow.")
                    let gap: CGFloat
                    switch edge {
                    case .left: gap = circle.minX - screen.minX
                    case .right: gap = screen.maxX - circle.maxX
                    case .top: gap = screen.maxY - circle.maxY
                    case .bottom: gap = circle.minY - visible.minY
                    }
                    XCTAssertEqual(gap, contactRadius - radius + 1, accuracy: 0.000001)

                    let contact = point(at: edge, distance: contactRadius)
                    let touched = try XCTUnwrap(controller.updatePointerPress(at: contact))
                    XCTAssertEqual(touched.attachment?.edge, edge)
                    XCTAssertEqual(controller.dragAttachment, touched.target)
                    XCTAssertEqual(controller.dragVisual?.coalescence, 0, "Unfold at the enlarged perimeter, before the visible circle touches the edge.")
                    XCTAssertEqual(controller.dragVisual?.widgetFrame, touched.target?.frame)
                    XCTAssertEqual(controller.dragVisual?.circleOpacity, 0)
                    XCTAssertEqual(preferences.edge, .right)
                    XCTAssertEqual(preferences.verticalPosition, 0.24)
                    XCTAssertEqual(preferences.horizontalPosition, 0.72)

                    guard case .drag(let drop) = controller.finishPointerPress(at: contact, doubleClickInterval: 0.5) else {
                        return XCTFail("The press must remain captured while attached.")
                    }
                    XCTAssertEqual(drop.attachment?.edge, edge)
                    XCTAssertEqual(controller.dragVisual?.coalescence, 0, "Releasing an attached widget must not collect it again.")
                    XCTAssertEqual(preferences.edge, .right)
                }
            }
        }
    }

    @MainActor
    func testPullingAwayCollectsAgainAndCornerContactSwitchesToTheNearerEdge() async throws {
        try await withController { controller, preferences in
            begin(controller)
            _ = controller.updatePointerPress(at: point(at: .left))
            _ = controller.updatePointerPress(at: point(at: .left, distance: 40))
            XCTAssertEqual(controller.dragAttachment?.edge, .left)
            XCTAssertEqual(controller.dragVisual?.coalescence, 0)
            let pulled = try XCTUnwrap(controller.updatePointerPress(at: point(at: .left, distance: 41)))
            XCTAssertEqual(pulled.target?.edge, .left)
            XCTAssertNil(controller.dragAttachment)
            XCTAssertEqual(controller.dragVisual?.coalescence, 1)
            XCTAssertEqual(controller.dragVisual?.circleFrame.midX, point(at: .left, distance: 41).x)

            _ = controller.updatePointerPress(at: NSPoint(x: screen.minX + 1, y: screen.maxY - 3))
            XCTAssertEqual(controller.dragAttachment?.edge, .left)
            _ = controller.updatePointerPress(at: NSPoint(x: screen.minX + 3, y: screen.maxY - 1))
            XCTAssertEqual(controller.dragAttachment?.edge, .top)
            XCTAssertEqual(controller.dragVisual?.coalescence, 0)
            XCTAssertEqual(preferences.edge, .right)
            controller.closeDetails()
            XCTAssertNil(controller.dragVisual)
            XCTAssertEqual(preferences.edge, .right)
        }
    }

    @MainActor
    func testHeldAnimationFinishesWhilePressedAndTracksMovementAlongTheEdge() async throws {
        try await withController(reducesMotion: false) { controller, preferences in
            begin(controller)
            _ = controller.updatePointerPress(at: point(at: .left, distance: 30))
            var last: MacWidgetPointerInteraction.Placement?
            for offset in [CGFloat(20), 60, 100] {
                try await Task.sleep(for: .milliseconds(25))
                last = controller.updatePointerPress(at: NSPoint(x: screen.minX + 30, y: screen.midY + offset))
            }
            let opened = try await eventually { controller.dragVisual?.coalescence == 0 }
            XCTAssertTrue(opened)
            XCTAssertEqual(controller.dragVisual?.widgetFrame, last?.target?.frame)
            XCTAssertEqual(preferences.edge, .right)
            _ = controller.updatePointerPress(at: point(at: .left, distance: 41))
            let collected = try await eventually { controller.dragVisual?.coalescence == 1 }
            XCTAssertTrue(collected)
            XCTAssertNil(controller.dragAttachment)
            // Reaching another edge in the same press must still unfold.
            _ = controller.updatePointerPress(at: point(at: .bottom, distance: 30))
            let reopened = try await eventually { controller.dragVisual?.coalescence == 0 }
            XCTAssertTrue(reopened)
            XCTAssertEqual(controller.dragAttachment?.edge, .bottom)
            XCTAssertEqual(preferences.edge, .right)
            controller.closeDetails()
        }
    }

    @MainActor
    func testCancelDuringUnfoldingCannotRestoreAStalePreview() async throws {
        try await withController(reducesMotion: false) { controller, preferences in
            begin(controller)
            _ = controller.updatePointerPress(at: point(at: .bottom))
            try await Task.sleep(for: .milliseconds(40))
            controller.closeDetails()
            XCTAssertNil(controller.dragVisual)
            XCTAssertNil(controller.dragAttachment)
            try await Task.sleep(for: .milliseconds(350))
            XCTAssertNil(controller.dragVisual)
            XCTAssertEqual(preferences.edge, .right)
            XCTAssertEqual(preferences.verticalPosition, 0.24)
            begin(controller)
            _ = controller.updatePointerPress(at: point(at: .top))
            let opened = try await eventually { controller.dragVisual?.coalescence == 0 }
            XCTAssertTrue(opened)
            XCTAssertEqual(controller.dragAttachment?.edge, .top)
            controller.closeDetails()
        }
    }

    @MainActor
    private func begin(_ controller: MacWidgetController) {
        let docking = MacWidgetDocking(edge: .right, screenFrame: screen, visibleFrame: visible,
            topInfo: MacTopNotchInfo(cameraInset: 32, notchWidth: 180, centerX: screen.midX),
            scale: controller.preferences.scale)
        let frame = docking.frame(edge: .right, position: 0.24)
        controller.beginPointerPress(at: NSPoint(x: frame.midX, y: frame.midY), frame: frame, bounds: visible,
                                     clickCount: 1, timestamp: 1, docking: docking)
    }

    @MainActor
    private func withController(reducesMotion: Bool = true,
                                _ body: (MacWidgetController, MacWidgetPreferences) async throws -> Void) async throws {
        let suite = "com.hinoshiba.daysyet.attachment.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = MacWidgetPreferences(defaults: defaults)
        preferences.edge = .right
        preferences.verticalPosition = 0.24
        preferences.horizontalPosition = 0.72
        let controller = MacWidgetController(store: ProfileStore(profile: .initial, saveProfile: { _ in }),
            preferences: preferences, reducesMotion: { reducesMotion })
        // No panel is started; the controller exercises the real drag animation
        // without opening a window or touching the user's desktop/preferences.
        try await body(controller, preferences)
    }

    @MainActor
    private func eventually(_ condition: () -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        return condition()
    }
}
