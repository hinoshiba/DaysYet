import AppKit
import SwiftUI
import XCTest
@testable import DaysYetMac

final class MacWidgetDragMorphTests: XCTestCase {
    func testVisualFollowingIsBoundedAndIndependentOfRefreshRate() {
        let initial = MacWidgetDragVisual(widgetFrame: .zero, focusFrame: .zero,
            circleFrame: NSRect(x: 0, y: 0, width: 40, height: 40), coalescence: 1)
        var target = initial
        target.circleFrame = initial.circleFrame.offsetBy(dx: 600, dy: -300)
        var results: [MacWidgetDragVisual] = []
        for fps in [60, 120] {
            var visual = initial
            for _ in 0..<(fps / 10) {
                visual = visual.following(target, elapsed: 1 / Double(fps))
                XCTAssertGreaterThan(visual.circleFrame.minX, 0)
                XCTAssertLessThan(visual.circleFrame.minX, 600)
                XCTAssertEqual(visual.coalescence, 1)
                XCTAssertEqual(visual.circleOpacity, 1)
            }
            results.append(visual)
        }
        XCTAssertEqual(results[0].circleFrame.minX, results[1].circleFrame.minX, accuracy: 0.000001)
        XCTAssertEqual(results[0].circleFrame.minY, results[1].circleFrame.minY, accuracy: 0.000001)
        XCTAssertGreaterThan(results[0].circleFrame.minX, 500, "The lag must stay short enough to follow a drag.")
    }

    @MainActor
    func testDragCollectsTheMetricUnderThePointerOnEveryEdge() throws {
        try withController { controller, preferences in
            for edge in MacWidgetEdge.allCases {
                preferences.edge = edge
                for scale in [0.8, 1.5] {
                    preferences.scale = scale
                    let screen = NSRect(x: -1600, y: 120, width: 1600, height: 1000)
                    let docking = MacWidgetDocking(edge: edge, screenFrame: screen, visibleFrame: screen,
                        topInfo: MacTopNotchInfo(cameraInset: 32, notchWidth: 180, centerX: screen.midX), scale: scale)
                    let frame = docking.frame(edge: edge, position: 0.5)
                    for (index, metric) in controller.activeMetrics.enumerated() {
                        let focus = MacWidgetDragGeometry.focusFrame(in: frame, edge: edge, index: index, scale: scale,
                            metricCount: controller.activeMetrics.count, topInfo: docking.topInfo)
                        let pointer = NSPoint(x: focus.midX, y: focus.midY)
                        controller.beginPointerPress(at: pointer, frame: frame, bounds: screen,
                            clickCount: 1, timestamp: 1, docking: docking)
                        let origin = try XCTUnwrap(controller.dragOrigin)
                        XCTAssertEqual(origin.metric, metric)
                        XCTAssertEqual(origin.focusFrame, focus)
                        _ = controller.updatePointerPress(at: NSPoint(x: screen.midX, y: screen.midY))
                        XCTAssertNil(controller.hoveredMetric)
                        XCTAssertEqual(controller.dragOrigin?.metric, metric, "Clearing hover must not change the carried circle.")
                        _ = controller.finishPointerPress(at: pointer, doubleClickInterval: 0.5)
                    }
                }
            }
        }
    }

    func testCollapseAndUnfoldUseTheGrabbedCircleAsTheirAnchor() {
        let widget = NSRect(x: -210, y: 160, width: 204, height: 462)
        for focus in [NSRect(x: -45, y: 200, width: 34, height: 34), NSRect(x: -45, y: 540, width: 60, height: 60)] {
            let circle = MacWidgetDragGeometry.circleFrame(center: NSPoint(x: focus.midX, y: focus.midY), scale: 1)
            let original = MacWidgetDragVisual(widgetFrame: widget, focusFrame: focus, circleFrame: circle, coalescence: 0)
            XCTAssertEqual(original.imageFrame, widget)
            var collapsed = original
            collapsed.coalescence = 1
            for progress in [0.0, 0.2, 0.5, 0.8, 1.0] {
                let visual = original.interpolated(to: collapsed, progress: progress)
                let scale = visual.imageFrame.width / widget.width
                XCTAssertEqual(visual.imageFrame.minX + (focus.midX - widget.minX) * scale, circle.midX, accuracy: 0.000001)
                XCTAssertEqual(visual.imageFrame.minY + (focus.midY - widget.minY) * scale, circle.midY, accuracy: 0.000001)
            }
            XCTAssertEqual(collapsed.imageOpacity, 0)
            XCTAssertEqual(collapsed.circleOpacity, 1)
            XCTAssertEqual(collapsed.interpolated(to: original, progress: 1).imageFrame, widget)
            XCTAssertEqual(collapsed.interpolated(to: original, progress: 1).circleOpacity, 0)
        }
    }

    func testReturnFlightRemainsOneSmallCircleUntilArrival() {
        for edge in MacWidgetEdge.allCases {
            for scale in [0.8, 1, 1.5] {
                let screen = NSRect(x: 0, y: 0, width: 1512, height: 982)
                let frame = MacWidgetPlacement.frame(in: screen, edge: edge, position: 0.5, expanded: true, scale: scale)
                let focus = MacWidgetDragGeometry.focusFrame(in: frame, edge: edge, index: 2,
                    scale: scale, metricCount: 3, topInfo: MacTopNotchInfo(centerX: screen.midX))
                let flying = MacWidgetDragVisual(widgetFrame: frame, focusFrame: focus,
                    circleFrame: MacWidgetDragGeometry.circleFrame(center: NSPoint(x: 650, y: 400), scale: scale), coalescence: 1)
                var arrived = flying
                arrived.circleFrame = MacWidgetDragGeometry.circleFrame(center: NSPoint(x: focus.midX, y: focus.midY), scale: scale)
                for progress in [0.0, 0.25, 0.5, 0.75, 1.0] {
                    let visual = flying.interpolated(to: arrived, progress: progress, spring: true)
                    XCTAssertEqual(visual.circleFrame.width, visual.circleFrame.height)
                    XCTAssertLessThanOrEqual(visual.circleFrame.width, 46)
                    XCTAssertEqual(visual.imageOpacity, 0, "The complete rail must not reappear during the return flight.")
                    XCTAssertEqual(visual.circleOpacity, 1)
                }
                XCTAssertEqual(flying.interpolated(to: arrived, progress: 1, spring: true), arrived)
            }
        }
    }

    @MainActor
    func testDetachedRenderingContainsOnlyTheCarriedCircle() throws {
        try withController { controller, preferences in
            preferences.edge = .right
            let screen = NSRect(x: 0, y: 0, width: 480, height: 320)
            let docking = MacWidgetDocking(edge: .right, screenFrame: screen, visibleFrame: screen)
            let widget = docking.frame(edge: .right, position: 0.5)
            let sourceRenderer = ImageRenderer(content: MacDesktopWidgetView(store: controller.store,
                preferences: preferences, controller: controller).frame(width: widget.width, height: widget.height))
            let source = try XCTUnwrap(sourceRenderer.nsImage)
            let focus = MacWidgetDragGeometry.focusFrame(in: widget, edge: .right, index: 1, scale: 1,
                metricCount: 3, topInfo: docking.topInfo)
            let metric = controller.activeMetrics[1]
            let snapshot = TimeProgressCalculator.snapshot(for: metric, profile: controller.store.profile)
            let center = NSPoint(x: 240, y: 160)
            for progress in [CGFloat(0), 0.5, 1] {
                let visual = MacWidgetDragVisual(widgetFrame: widget, focusFrame: focus,
                    circleFrame: MacWidgetDragGeometry.circleFrame(center: center, scale: 1), coalescence: progress)
                let renderer = ImageRenderer(content: MacWidgetDragOverlay(docking: docking,
                    visual: visual, widgetImage: source, snapshot: snapshot,
                    accent: MacWidgetStyle.accent(for: metric, theme: .vividNight)))
                let cgImage = try XCTUnwrap(renderer.cgImage)
                let bitmap = NSBitmapImageRep(cgImage: cgImage)
                let attachment = XCTAttachment(image: NSImage(cgImage: cgImage, size: screen.size))
                attachment.name = "Drag collection \(progress)"
                attachment.lifetime = .keepAlways
                add(attachment)
                if progress == 1 {
                    XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: 240, y: 160)).alphaComponent, 0.9)
                    for x in stride(from: 0, to: 480, by: 8) {
                        for y in stride(from: 0, to: 320, by: 8) where hypot(Double(x - 240), Double(y - 160)) > 60 {
                            XCTAssertLessThan(try XCTUnwrap(bitmap.colorAt(x: x, y: y)).alphaComponent, 0.01,
                                              "No rail, details, other circles, or labels may travel with the circle.")
                        }
                    }
                }
            }
        }
    }

    @MainActor
    private func withController(_ body: (MacWidgetController, MacWidgetPreferences) throws -> Void) throws {
        let suite = "com.hinoshiba.daysyet.drag-morph.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = MacWidgetPreferences(defaults: defaults)
        let controller = MacWidgetController(store: ProfileStore(profile: .initial, saveProfile: { _ in }),
            preferences: preferences, reducesMotion: { true })
        try body(controller, preferences)
    }
}
