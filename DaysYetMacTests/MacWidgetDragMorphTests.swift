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

    func testReturnFlightKeepsOneCircleWhileMatchingTheDestinationSize() {
        for edge in MacWidgetEdge.allCases {
            for scale in [0.8, 1, 1.5] {
                let screen = NSRect(x: 0, y: 0, width: 1512, height: 982)
                let frame = MacWidgetPlacement.frame(in: screen, edge: edge, position: 0.5, expanded: true, scale: scale)
                let focus = MacWidgetDragGeometry.focusFrame(in: frame, edge: edge, index: 2,
                    scale: scale, metricCount: 3, topInfo: MacTopNotchInfo(centerX: screen.midX))
                let flying = MacWidgetDragVisual(widgetFrame: frame, focusFrame: focus,
                    circleFrame: MacWidgetDragGeometry.circleFrame(center: NSPoint(x: 650, y: 400), scale: scale), coalescence: 1)
                var arrived = flying
                arrived.circleFrame = MacWidgetDragGeometry.attachmentCircleFrame(focus: focus, edge: edge, scale: scale)
                let flight = MacWidgetReturnFlight(from: flying.circleFrame, to: arrived.circleFrame)
                for progress in [0.0, 0.25, 0.5, 0.75, 1.0] {
                    let visual = flying.interpolated(to: arrived, progress: progress, flight: flight)
                    XCTAssertEqual(visual.circleFrame.width, visual.circleFrame.height)
                    XCTAssertLessThanOrEqual(visual.circleFrame.width, max(flying.circleFrame.width, arrived.circleFrame.width))
                    XCTAssertEqual(visual.imageOpacity, 0, "The complete rail must not reappear during the return flight.")
                    XCTAssertEqual(visual.circleOpacity, 1)
                }
                XCTAssertEqual(flying.interpolated(to: arrived, progress: 1, flight: flight), arrived)
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
    func testCarriedCircleRendersInEachDisplaysOwnCanvas() throws {
        try withController { controller, _ in
            let sourceFrame = NSRect(x: 0, y: 0, width: 480, height: 320)
            let docking = MacWidgetDocking(edge: .right, screenFrame: sourceFrame, visibleFrame: sourceFrame)
            let widget = docking.frame(edge: .right, position: 0.5)
            let focus = MacWidgetDragGeometry.focusFrame(in: widget, edge: .right, index: 1,
                scale: 1, metricCount: 3, topInfo: docking.topInfo)
            let metric = controller.activeMetrics[1]
            let snapshot = TimeProgressCalculator.snapshot(for: metric, profile: controller.store.profile)
            for canvas in [NSRect(x: -480, y: 120, width: 480, height: 320),
                           NSRect(x: 480, y: -320, width: 480, height: 320),
                           NSRect(x: 0, y: 320, width: 480, height: 320)] {
                let center = NSPoint(x: canvas.minX + 180, y: canvas.minY + 100)
                let visual = MacWidgetDragVisual(widgetFrame: widget, focusFrame: focus,
                    circleFrame: MacWidgetDragGeometry.circleFrame(center: center, scale: 1), coalescence: 1)
                for scale in [CGFloat(1), 2] {
                    let renderer = ImageRenderer(content: MacWidgetDragOverlay(docking: docking,
                        visual: visual, widgetImage: nil, snapshot: snapshot,
                        accent: MacWidgetStyle.accent(for: metric, theme: .vividNight), canvasFrame: canvas))
                    renderer.scale = scale
                    let image = try XCTUnwrap(renderer.cgImage)
                    let bitmap = NSBitmapImageRep(cgImage: image)
                    XCTAssertEqual(bitmap.pixelsWide, Int(canvas.width * scale))
                    XCTAssertEqual(bitmap.pixelsHigh, Int(canvas.height * scale))
                    let x = Int((center.x - canvas.minX) * scale)
                    let y = Int((canvas.maxY - center.y) * scale)
                    XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: x, y: y)).alphaComponent, 0.9,
                        "Global coordinates must be converted using the overlay's display, including negative origins.")
                    XCTAssertLessThan(try XCTUnwrap(bitmap.colorAt(x: 10, y: 10)).alphaComponent, 0.01)
                }
            }
        }
    }

    @MainActor
    func testAttachedUnfoldKeepsFocusPixelsAndWallContactOnEveryEdge() throws {
        try withController { controller, preferences in
            for edge in MacWidgetEdge.allCases {
                for scale in [0.8, 1.0, 1.5] {
                    let fixture = try attachmentFixture(controller: controller, preferences: preferences,
                        edge: edge, scale: scale)
                    let finished = try renderAttachment(fixture, progress: 1)
                    let focus = fixture.arrived.focusFrame
                    let canvas = fixture.canvas
                    let pixelFocus = CGRect(x: (focus.minX - canvas.minX) * 2,
                        y: (canvas.maxY - focus.maxY) * 2, width: focus.width * 2, height: focus.height * 2)
                    let wall: CGPoint
                    switch edge {
                    case .left: wall = CGPoint(x: fixture.arrived.widgetFrame.minX + 0.75, y: focus.midY)
                    case .right: wall = CGPoint(x: fixture.arrived.widgetFrame.maxX - 0.75, y: focus.midY)
                    case .bottom: wall = CGPoint(x: focus.midX, y: fixture.arrived.widgetFrame.minY + 0.75)
                    case .top: wall = CGPoint(x: focus.midX, y: fixture.arrived.widgetFrame.maxY - 0.75)
                    }
                    let wallX = Int((wall.x - canvas.minX) * 2)
                    let wallY = Int((canvas.maxY - wall.y) * 2)
                    let finishedWallAlpha = try XCTUnwrap(finished.colorAt(x: wallX, y: wallY)).alphaComponent
                    XCTAssertGreaterThan(finishedWallAlpha, 0.9)
                    for progress in [0.0, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0] {
                        let frame = try renderAttachment(fixture, progress: progress)
                        let difference = try maximumPixelDifference(frame, finished, in: pixelFocus, ellipse: edge != .top)
                        // A masked layer may round its compositing color by two
                        // 8-bit levels even when no focus pixels are clipped.
                        XCTAssertLessThanOrEqual(difference, 2.0 / 255,
                            "The grabbed ring/segment must remain one fixed-size rendering: \(edge), scale \(scale), progress \(progress).")
                        // The vector surface can cover more of a fractional
                        // boundary pixel than the resampled final snapshot,
                        // but it must never open a gap at the contact point.
                        XCTAssertGreaterThanOrEqual(try XCTUnwrap(frame.colorAt(x: wallX, y: wallY)).alphaComponent,
                            finishedWallAlpha - 2.0 / 255,
                            "The material must touch the wall throughout unfolding: \(edge), scale \(scale), progress \(progress).")
                    }
                }
            }
        }
    }

    @MainActor
    func testFinishedAttachedUnfoldMatchesTheUnmaskedDestinationSnapshot() throws {
        try withController { controller, preferences in
            for edge in MacWidgetEdge.allCases {
                for scale in [0.8, 1.0, 1.5] {
                    let fixture = try attachmentFixture(controller: controller, preferences: preferences,
                        edge: edge, scale: scale)
                    let attached = try renderAttachment(fixture, progress: 1)
                    let unmasked = try renderAttachment(fixture, progress: 1, attachment: false)
                    let bounds = CGRect(x: 0, y: 0, width: CGFloat(attached.pixelsWide), height: CGFloat(attached.pixelsHigh))
                    XCTAssertLessThanOrEqual(try maximumPixelDifference(attached, unmasked, in: bounds), 1.0 / 255,
                        "The completed reveal must hand off the exact destination image without a final size or shape jump.")
                }
            }
        }
    }

    @MainActor
    func testUnfoldPreservesEndMetricsOnCompressedRailsAndBelowTheNotch() throws {
        try withController { controller, preferences in
            while controller.store.profile.macDashboardMetrics.count < MetricKind.allCases.count {
                controller.store.addMacDashboardMetric()
            }
            for edge in MacWidgetEdge.allCases {
                let count = controller.store.profile.macWidgetMetrics(for: edge).count
                for index in [0, count - 1] {
                    let fixture = try attachmentFixture(controller: controller, preferences: preferences,
                        edge: edge, scale: 1.5, index: index, screenHeight: 260, cameraInset: 32, notchWidth: 180)
                    let finished = try renderAttachment(fixture, progress: 1)
                    let focus = fixture.arrived.focusFrame
                    let pixelFocus = CGRect(x: (focus.minX - fixture.canvas.minX) * 2,
                        y: (fixture.canvas.maxY - focus.maxY) * 2, width: focus.width * 2, height: focus.height * 2)
                    for progress in [0.0, 0.25, 0.5, 0.75, 1.0] {
                        let frame = try renderAttachment(fixture, progress: progress)
                        XCTAssertLessThanOrEqual(try maximumPixelDifference(frame, finished, in: pixelFocus,
                            ellipse: edge != .top), 2.0 / 255,
                            "End metrics must retain their full fixed-size ring/segment in compressed and notched layouts.")
                    }
                }
            }
        }
    }

    @MainActor
    func testNeighborRingsAppearOnlyAfterTheirWholeFrameFitsTheGrowingSurface() throws {
        try withController { controller, preferences in
            while controller.store.profile.macDashboardMetrics.count < MetricKind.allCases.count {
                controller.store.addMacDashboardMetric()
            }
            for edge in [MacWidgetEdge.left, .right, .bottom] {
                for index in [0, MetricKind.allCases.count - 1] {
                    let fixture = try attachmentFixture(controller: controller, preferences: preferences,
                        edge: edge, scale: 1.5, index: index, screenHeight: 260)
                    let widget = fixture.arrived.widgetFrame
                    let bounds = CGRect(origin: .zero, size: widget.size)
                    func local(_ frame: NSRect) -> CGRect {
                        CGRect(x: frame.minX - widget.minX, y: widget.maxY - frame.maxY,
                               width: frame.width, height: frame.height)
                    }
                    let focus = local(fixture.arrived.focusFrame)
                    for ringFrame in fixture.arrived.attachmentRingFrames where ringFrame != fixture.arrived.focusFrame {
                        let ring = local(ringFrame)
                        var previousOpacity = 0.0
                        for step in 0...100 {
                            let reveal = MacWidgetAttachmentReveal(edge: edge, focusFrame: focus, progress: CGFloat(step) / 100,
                                finalSurface: fixture.arrived.attachmentSurface)
                            let opacity = reveal.contentOpacity(for: ring, in: bounds)
                            XCTAssertGreaterThanOrEqual(opacity, previousOpacity)
                            XCTAssertLessThanOrEqual(opacity, 1)
                            if step == 0 { XCTAssertEqual(opacity, 0) }
                            if step == 100 { XCTAssertEqual(opacity, 1) }
                            if opacity > 0, step < 100 {
                                let path = reveal.path(in: bounds)
                                for point in [CGPoint(x: ring.minX, y: ring.minY), CGPoint(x: ring.maxX, y: ring.minY),
                                              CGPoint(x: ring.minX, y: ring.maxY), CGPoint(x: ring.maxX, y: ring.maxY)] {
                                    XCTAssertTrue(path.contains(point), "No neighboring ring or digit may be cut by the advancing surface.")
                                }
                            }
                            previousOpacity = opacity
                        }
                    }
                }
            }
        }
    }

    @MainActor
    func testLiquidSurfaceBulgesBeyondTheFinalSilhouetteAndSettlesExactly() throws {
        try withController { controller, preferences in
            for edge in [MacWidgetEdge.left, .right, .bottom] {
                let fixture = try attachmentFixture(controller: controller, preferences: preferences, edge: edge, scale: 1)
                let widget = fixture.arrived.widgetFrame
                let bounds = CGRect(origin: .zero, size: widget.size)
                let focus = CGRect(x: fixture.arrived.focusFrame.minX - widget.minX,
                    y: widget.maxY - fixture.arrived.focusFrame.maxY,
                    width: fixture.arrived.focusFrame.width, height: fixture.arrived.focusFrame.height)
                let finalSurface = try XCTUnwrap(fixture.arrived.attachmentSurface)
                let finalBitmap = try renderAttachment(fixture, progress: 1)
                var bulgingSamples = 0
                var visibleBulgingSamples = 0
                for progress in [CGFloat(0.1), 0.25, 0.4, 0.55, 0.7, 0.85, 0.95] {
                    let reveal = MacWidgetAttachmentReveal(edge: edge, focusFrame: focus, progress: progress,
                        finalSurface: finalSurface)
                    let outline = reveal.path(in: bounds)
                    if progress == 0.1 {
                        let vertical = edge == .left || edge == .right
                        let length = vertical ? bounds.height : bounds.width
                        let contact = stride(from: CGFloat(0.5), to: length, by: 0.5).filter { along in
                            let point: CGPoint
                            switch edge {
                            case .left: point = CGPoint(x: 0.5, y: along)
                            case .right: point = CGPoint(x: bounds.width - 0.5, y: along)
                            case .bottom: point = CGPoint(x: along, y: bounds.height - 0.5)
                            case .top: point = CGPoint(x: along, y: 0.5)
                            }
                            return outline.contains(point)
                        }
                        let contactSpan = try XCTUnwrap(contact.last) - XCTUnwrap(contact.first)
                        let bodySpan = vertical ? outline.boundingRect.height : outline.boundingRect.width
                        XCTAssertLessThan(contactSpan, bodySpan * 0.85,
                            "Wetting contact must lag the rounded outer lobe, forming a concave meniscus rather than a uniform zoom.")
                        assertConnectedSurface(outline)
                    }
                    var visual = fixture.arrived
                    visual.coalescence = 1 - progress
                    let outlineBounds = outline.boundingRect
                    let globalOutline = NSRect(x: widget.minX + outlineBounds.minX,
                        y: widget.maxY - outlineBounds.maxY, width: outlineBounds.width, height: outlineBounds.height)
                    XCTAssertTrue(visual.renderedFrame.contains(globalOutline),
                        "An interrupted liquid contour must fit completely inside its recapture canvas.")
                    let bitmap = try renderAttachment(fixture,
                        progress: MacWidgetDragMotion.unfoldPhase(coalescence: 1 - progress))
                    XCTAssertTrue(bounds.insetBy(dx: -24, dy: -24).contains(outline.boundingRect),
                        "Surface tension must remain a small deformation around the destination rail.")
                    for y in stride(from: Int(floor(bounds.minY - 12)), through: Int(ceil(bounds.maxY + 12)), by: 2) {
                        for x in stride(from: Int(floor(bounds.minX - 12)), through: Int(ceil(bounds.maxX + 12)), by: 2) {
                            let point = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
                            if outline.contains(point), !finalSurface.contains(point) {
                                bulgingSamples += 1
                                let pixelX = Int((widget.minX - fixture.canvas.minX + point.x) * 2)
                                let pixelY = Int((fixture.canvas.maxY - widget.maxY + point.y) * 2)
                                let originalAlpha = try XCTUnwrap(finalBitmap.colorAt(x: pixelX, y: pixelY)).alphaComponent
                                let liquidAlpha = try XCTUnwrap(bitmap.colorAt(x: pixelX, y: pixelY)).alphaComponent
                                if originalAlpha < 0.1, liquidAlpha > 0.5 { visibleBulgingSamples += 1 }
                            }
                        }
                    }
                }
                XCTAssertGreaterThan(bulgingSamples, 4,
                    "A liquid surface must deform beyond its final silhouette, not just reveal a clipped rectangle.")
                XCTAssertGreaterThan(visibleBulgingSamples, 4,
                    "The native renderer must draw the liquid bulge, not clip it back to the final snapshot's alpha.")
                let settled = MacWidgetAttachmentReveal(edge: edge, focusFrame: focus, progress: 1,
                    finalSurface: finalSurface).path(in: bounds)
                XCTAssertEqual(settled.cgPath, finalSurface, "The liquid must finish on the exact live surface.")
                let almostSettled = MacWidgetAttachmentReveal(edge: edge, focusFrame: focus, progress: 0.9999,
                    finalSurface: finalSurface).path(in: bounds).boundingRect
                XCTAssertEqual(almostSettled.minX, settled.boundingRect.minX, accuracy: 0.25)
                XCTAssertEqual(almostSettled.maxX, settled.boundingRect.maxX, accuracy: 0.25)
                XCTAssertEqual(almostSettled.minY, settled.boundingRect.minY, accuracy: 0.25)
                XCTAssertEqual(almostSettled.maxY, settled.boundingRect.maxY, accuracy: 0.25)
            }
        }
    }

    private func assertConnectedSurface(_ outline: Path, file: StaticString = #filePath, line: UInt = #line) {
        let bounds = outline.boundingRect.insetBy(dx: -1, dy: -1).integral
        let width = Int(bounds.width)
        let height = Int(bounds.height)
        var filled = Set<Int>()
        for y in 0..<height {
            for x in 0..<width where outline.contains(CGPoint(x: bounds.minX + CGFloat(x) + 0.5,
                                                             y: bounds.minY + CGFloat(y) + 0.5)) {
                filled.insert(y * width + x)
            }
        }
        guard let first = filled.first else {
            return XCTFail("The liquid surface must contain visible material.", file: file, line: line)
        }
        var pending = [first]
        var visited: Set<Int> = [first]
        while let current = pending.popLast() {
            let x = current % width
            let y = current / width
            for dy in -1...1 {
                for dx in -1...1 where dx != 0 || dy != 0 {
                    let nx = x + dx
                    let ny = y + dy
                    guard (0..<width).contains(nx), (0..<height).contains(ny) else { continue }
                    let next = ny * width + nx
                    if filled.contains(next), visited.insert(next).inserted { pending.append(next) }
                }
            }
        }
        XCTAssertEqual(visited.count, filled.count,
            "The rounded lobe, central core, and wall contact must form one connected liquid surface.", file: file, line: line)
    }

    private struct AttachmentRenderFixture {
        let docking: MacWidgetDocking
        let arrived: MacWidgetDragVisual
        let source: NSImage
        let snapshot: MetricSnapshot
        let accent: Color
        let canvas: NSRect
    }

    @MainActor
    private func attachmentFixture(controller: MacWidgetController, preferences: MacWidgetPreferences,
                                   edge: MacWidgetEdge, scale: Double, index requestedIndex: Int = 1,
                                   screenHeight: CGFloat = 360, cameraInset: CGFloat = 0,
                                   notchWidth: CGFloat = 0) throws -> AttachmentRenderFixture {
        preferences.edge = edge
        preferences.scale = scale
        let screen = NSRect(x: 0, y: 0, width: 480, height: screenHeight)
        let metrics = controller.store.profile.macWidgetMetrics(for: edge)
        let index = min(requestedIndex, metrics.count - 1)
        let metric = metrics[index]
        let docking = MacWidgetDocking(edge: edge, screenFrame: screen, visibleFrame: screen,
            topInfo: MacTopNotchInfo(cameraInset: cameraInset, notchWidth: notchWidth, centerX: screen.midX),
            scale: scale, metricCount: metrics.count)
        let widget = docking.frame(edge: edge, position: 0.5)
        let sourceRenderer = ImageRenderer(content: MacDesktopWidgetView(store: controller.store,
            preferences: preferences, controller: controller, previewEdge: edge, previewTopInfo: docking.topInfo)
            .frame(width: widget.width, height: widget.height))
        sourceRenderer.scale = 2
        let source = try XCTUnwrap(sourceRenderer.nsImage)
        let focus = MacWidgetDragGeometry.focusFrame(in: widget, edge: edge, index: index,
            scale: scale, metricCount: metrics.count, topInfo: docking.topInfo)
        let rings = edge == .top ? [] : metrics.indices.map {
            MacWidgetDragGeometry.focusFrame(in: widget, edge: edge, index: $0, scale: scale,
                metricCount: metrics.count, topInfo: docking.topInfo)
        }
        let arrived = MacWidgetDragVisual(widgetFrame: widget, focusFrame: focus,
            circleFrame: MacWidgetDragGeometry.attachmentCircleFrame(focus: focus, edge: edge, scale: scale),
            coalescence: 1, attachmentEdge: edge, attachmentRingFrames: rings,
            attachmentSurface: MacWidgetSurface.path(in: widget.size, edge: edge,
                selectedIndex: controller.selectionPosition, scale: scale,
                topCameraInset: docking.topInfo.cameraInset, topNotchWidth: docking.topInfo.notchWidth,
                metricCount: metrics.count, detailScale: docking.detailScale, sideExpansion: 0))
        return AttachmentRenderFixture(docking: docking, arrived: arrived, source: source,
            snapshot: TimeProgressCalculator.snapshot(for: metric, profile: controller.store.profile),
            accent: MacWidgetStyle.accent(for: metric, theme: controller.store.profile.widgetTheme),
            canvas: widget.insetBy(dx: -50, dy: -50))
    }

    @MainActor
    private func renderAttachment(_ fixture: AttachmentRenderFixture, progress: Double,
                                  attachment: Bool = true) throws -> NSBitmapImageRep {
        var opened = fixture.arrived
        opened.coalescence = 0
        var visual = fixture.arrived.interpolated(to: opened, progress: progress)
        if !attachment { visual.attachmentEdge = nil }
        let renderer = ImageRenderer(content: MacWidgetDragOverlay(docking: fixture.docking,
            visual: visual, widgetImage: fixture.source, snapshot: fixture.snapshot,
            accent: fixture.accent, canvasFrame: fixture.canvas))
        renderer.scale = 2
        return NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
    }

    private func maximumPixelDifference(_ first: NSBitmapImageRep, _ second: NSBitmapImageRep,
                                        in region: CGRect, ellipse: Bool = false) throws -> CGFloat {
        XCTAssertEqual(first.pixelsWide, second.pixelsWide)
        XCTAssertEqual(first.pixelsHigh, second.pixelsHigh)
        var difference: CGFloat = 0
        for y in max(Int(ceil(region.minY)), 0)..<min(Int(floor(region.maxY)), first.pixelsHigh) {
            for x in max(Int(ceil(region.minX)), 0)..<min(Int(floor(region.maxX)), first.pixelsWide) {
                if ellipse {
                    let dx = (CGFloat(x) + 0.5 - region.midX) / (region.width / 2)
                    let dy = (CGFloat(y) + 0.5 - region.midY) / (region.height / 2)
                    if dx * dx + dy * dy > 1 { continue }
                }
                let a = try XCTUnwrap(first.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                let b = try XCTUnwrap(second.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                difference = max(difference, abs(a.redComponent - b.redComponent), abs(a.greenComponent - b.greenComponent),
                    abs(a.blueComponent - b.blueComponent), abs(a.alphaComponent - b.alphaComponent))
            }
        }
        return difference
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
