import AppKit
import SwiftUI
import XCTest
@testable import DaysYetMac

final class MacSystemDockLandingTests: XCTestCase {
    private let screen = NSRect(x: -1600, y: 120, width: 1600, height: 1000)
    private var visible: NSRect { NSRect(x: -1600, y: 200, width: 1600, height: 888) }
    private var metrics: [MetricKind] { [.week, .month, .year] }

    func testDockStripMaintainsAttachmentWhileSlidingAndStillReleasesInward() throws {
        let docking = MacWidgetDocking(edge: .right, screenFrame: screen, visibleFrame: visible, systemDockEdge: .bottom)
        let frame = docking.frame(edge: .right, position: 0.5)
        let anchor = NSPoint(x: frame.midX, y: frame.midY)
        var interaction = MacWidgetPointerInteraction()
        interaction.begin(at: anchor, frame: frame, bounds: visible, position: 0.5, clickCount: 1, timestamp: 1, docking: docking)
        for (x, y) in [(-950.0, 220.0), (-850, 239), (-600, 230), (-500, 240)] {
            let placement = try XCTUnwrap(interaction.update(at: NSPoint(x: x, y: y)))
            XCTAssertEqual(placement.attachment?.isSystemDock, true)
        }
        XCTAssertNil(interaction.update(at: NSPoint(x: -500, y: 241))?.attachment)
        XCTAssertEqual(interaction.update(at: NSPoint(x: -500, y: 210))?.attachment?.isSystemDock, true)
    }

    func testAutoHiddenDockUsesObservedIconDepthWithoutChangingOtherEdges() throws {
        let docking = MacWidgetDocking(edge: .bottom, screenFrame: screen, visibleFrame: screen,
            systemDockEdge: .bottom, sourceDockDepth: 58)
        let anchor = NSPoint(x: screen.midX, y: screen.minY + 58)
        let frame = NSRect(x: anchor.x - 24, y: anchor.y - 24, width: 48, height: 48)
        let point = NSPoint(x: anchor.x + 80, y: anchor.y)
        let target = try XCTUnwrap(docking.target(at: point, previous: nil, originalFrame: frame, anchor: anchor))
        XCTAssertNotNil(docking.attachment(at: point, target: target, previous: nil))
        let left = NSPoint(x: screen.minX + 41, y: screen.midY)
        let leftTarget = try XCTUnwrap(docking.target(at: left, previous: nil, originalFrame: frame, anchor: anchor))
        XCTAssertNil(docking.attachment(at: left, target: leftTarget, previous: .left))
    }

    @MainActor
    func testEveryDockOrientationCarriesOneCircleAtThePointerAndOtherEdgesStillExpand() async throws {
        for reducedMotion in [false, true] {
            for edge in [MacWidgetEdge.bottom, .left, .right] {
                try await context(reducesMotion: reducedMotion, nativeDockEdge: edge) { widget, _, _ in
                    let center = edge == .bottom ? NSPoint(x: screen.midX, y: screen.minY + 28)
                        : NSPoint(x: edge == .left ? screen.minX + 28 : screen.maxX - 28, y: screen.midY)
                    let icon = NSRect(x: center.x - 24, y: center.y - 24, width: 48, height: 48)
                    let docking = MacWidgetDocking(edge: edge, screenFrame: screen, visibleFrame: visible,
                        metricCount: metrics.count, systemDockEdge: edge, sourceDockDepth: 60)
                    for metric in metrics {
                        widget.beginPointerPress(at: center, frame: icon, bounds: visible,
                            clickCount: 1, timestamp: 1, docking: docking, nativeDockMetric: metric)
                        let first = edge == .bottom ? NSPoint(x: center.x + 150, y: center.y)
                            : NSPoint(x: center.x, y: center.y - 150)
                        _ = widget.updatePointerPress(at: first)
                        try await eventually { widget.dragVisual?.coalescence == 1 }
                        XCTAssertEqual(widget.dragOrigin?.metric, metric)
                        XCTAssertEqual(widget.dragAttachment?.isSystemDock, true)
                        XCTAssertNil(widget.dockLandingVisual, "The group must not be revealed while the mouse is held.")
                        let second = edge == .bottom ? NSPoint(x: first.x + 60, y: first.y)
                            : NSPoint(x: first.x, y: first.y - 60)
                        _ = widget.updatePointerPress(at: second)
                        XCTAssertEqual(widget.dragVisual?.circleFrame.midX, second.x)
                        XCTAssertEqual(widget.dragVisual?.circleFrame.midY, second.y)
                        XCTAssertEqual(widget.dragVisual?.imageOpacity, 0)
                        XCTAssertEqual(widget.dragVisual?.circleOpacity, 1)
                        let ordinaryEdge = edge == .bottom ? NSPoint(x: screen.minX + 20, y: screen.midY)
                            : NSPoint(x: screen.midX, y: screen.minY + 20)
                        _ = widget.updatePointerPress(at: ordinaryEdge)
                        try await eventually { widget.dragVisual?.coalescence == 0 }
                        XCTAssertEqual(widget.dragAttachment?.isSystemDock, false)
                        widget.abortNativeDockDrag()
                    }
                }
            }
        }
    }

    @MainActor
    func testLandingPreviewContainsCirclesWithTransparentGapsAndNoBar() throws {
        try context { widget, preferences, store in
            for edge in [MacWidgetEdge.bottom, .left, .right] {
                let layout = MacSystemDockGroupLayout(edge: edge, count: metrics.count)
                let renderer = ImageRenderer(content: MacSystemDockGroupView(store: store, preferences: preferences,
                    edge: edge, landing: true))
                renderer.scale = 2
                let cg = try XCTUnwrap(renderer.cgImage)
                let bitmap = NSBitmapImageRep(cgImage: cg)
                for index in metrics.indices {
                    let ring = layout.ring(at: index)
                    let center = try XCTUnwrap(bitmap.colorAt(x: Int(ring.midX * 2), y: Int(ring.midY * 2)))
                    XCTAssertGreaterThan(center.alphaComponent, 0.99)
                }
                let gap = edge == .bottom ? CGPoint(x: 84, y: 36) : CGPoint(x: 48, y: 72)
                let gapColor = try XCTUnwrap(bitmap.colorAt(x: Int(gap.x * 2), y: Int(gap.y * 2)))
                XCTAssertLessThan(gapColor.alphaComponent, 0.01, "There must be no shared black base between circles.")
                let caption = try XCTUnwrap(bitmap.colorAt(x: Int(layout.size.width), y: Int((layout.size.height - 16) * 2)))
                XCTAssertLessThan(caption.alphaComponent, 0.01)
                let attachment = XCTAttachment(image: NSImage(cgImage: cg, size: layout.size))
                attachment.name = "Circles-only Dock landing \(edge.rawValue)"
                attachment.lifetime = .keepAlways
                add(attachment)
                let output = URL(fileURLWithPath: "/tmp/daysyet-dock-landing-preview", isDirectory: true)
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                try bitmap.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent("\(edge.rawValue).png"))
            }
            XCTAssertNil(widget.dragVisual)
        }
    }

    func testTheCarriedCircleRevealsTheOtherMembersDuringInsertion() throws {
        let layout = MacSystemDockGroupLayout(edge: .bottom, count: metrics.count)
        let frame = layout.frame(near: NSPoint(x: screen.midX, y: screen.minY + 20), screen: screen, visible: visible)
        let focus = layout.focus(in: frame, index: 1)
        let visual = MacWidgetDragVisual(widgetFrame: frame, focusFrame: focus, circleFrame: focus, coalescence: 1)
        let initial = MacSystemDockLandingVisual.start(metrics: metrics, grabbed: .month, visual: visual)
        XCTAssertEqual(initial.tiles.filter { $0.value.opacity > 0 }.map(\.key), [.month])
        XCTAssertTrue(initial.tiles.values.allSatisfy { $0.frame == focus })
        let target = MacWidgetDropTarget(edge: .bottom, position: 0.5, frame: frame, isSystemDock: true)
        let frames = Dictionary(uniqueKeysWithValues: metrics.enumerated().map { index, metric in
            (metric, NSRect(x: -950 + index * 60, y: 128, width: 48, height: 48))
        })
        let destination = MacSystemDockLandingVisual.destination(metrics: metrics, nativeFrames: frames,
            target: target, docking: MacWidgetDocking(edge: .right, screenFrame: screen, visibleFrame: visible))
        for progress in [0.0, 0.2, 0.5, 0.9, 1] {
            let flight = initial.interpolated(to: destination, progress: progress)
            XCTAssertEqual(flight.tiles.count, 3)
            XCTAssertEqual(flight.tiles[.month]?.opacity, 1)
            for metric in [MetricKind.week, .year] {
                XCTAssertEqual(try XCTUnwrap(flight.tiles[metric]?.opacity), 1 - pow(1 - progress, 3), accuracy: 0.0001)
            }
            let ordered = try metrics.map { try XCTUnwrap(flight.tiles[$0]?.frame) }
            if progress > 0 {
                XCTAssertLessThan(ordered[0].midX, ordered[1].midX)
                XCTAssertLessThan(ordered[1].midX, ordered[2].midX)
            }
        }
        XCTAssertEqual(initial.interpolated(to: destination, progress: 1).tiles.mapValues(\.frame), frames)
    }

    @MainActor
    func testDockPreviewStaysCollectedThroughSlidingAndUntilSlotsAreReady() async throws {
        try await context { widget, preferences, store in
            var presented: [MacSystemDockPresentation] = []
            let dock = MacSystemDockController(store: store, preferences: preferences, openSettings: {}, present: { presented = $0 })
            dock.start()
            defer { dock.stop() }
            widget.systemDockLandingChanged = { dock.setLanding($0) }
            let docking = MacWidgetDocking(edge: .right, screenFrame: screen, visibleFrame: visible, systemDockEdge: .bottom)
            let frame = docking.frame(edge: .right, position: 0.5)
            widget.beginPointerPress(at: NSPoint(x: frame.midX, y: frame.midY), frame: frame, bounds: visible,
                clickCount: 1, timestamp: 1, docking: docking)
            let contact = NSPoint(x: screen.midX, y: visible.minY + 20)
            _ = widget.updatePointerPress(at: contact)
            try await eventually { widget.dragVisual?.coalescence == 1 }
            for offset in [CGFloat(-70), 0, 80] {
                let pointer = NSPoint(x: contact.x + offset, y: contact.y + 10)
                _ = widget.updatePointerPress(at: pointer)
                XCTAssertEqual(widget.dragVisual?.coalescence, 1)
                XCTAssertEqual(widget.dragVisual?.circleFrame.midX, pointer.x)
                XCTAssertEqual(widget.dragVisual?.circleFrame.midY, pointer.y)
            }
            let target = try XCTUnwrap(widget.dragAttachment)
            let layout = MacSystemDockGroupLayout(edge: .bottom, count: 3)
            let frames = Dictionary(uniqueKeysWithValues: metrics.enumerated().map {
                ($0.element, layout.focus(in: target.frame.offsetBy(dx: 20, dy: -80), index: $0.offset))
            })
            var actualFrames: [MetricKind: NSRect] = [:]
            widget.nativeDockFrames = { actualFrames }
            guard case .drag(let placement) = widget.finishPointerPress(at: contact, doubleClickInterval: 0.5) else {
                return XCTFail("Expected drag completion")
            }
            widget.settleDrop(placement)
            dock.refresh()
            XCTAssertTrue(preferences.isInSystemDock)
            XCTAssertEqual(widget.dragVisual?.coalescence, 1)
            XCTAssertEqual(widget.dockLandingVisual?.tiles.count, 3)
            XCTAssertEqual(widget.dockLandingVisual?.tiles.values.filter { $0.opacity > 0 }.count, 1)
            XCTAssertEqual(presented.count, 3)
            XCTAssertTrue(presented.allSatisfy { $0.opacity == 0 })
            try await Task.sleep(for: .milliseconds(70))
            XCTAssertEqual(widget.dragVisual?.coalescence, 1)
            XCTAssertEqual(widget.dockLandingVisual?.tiles.count, 3)
            XCTAssertEqual(widget.dockLandingVisual?.tiles.values.filter { $0.opacity > 0 }.count, 1)
            actualFrames = frames
            try await eventually { !widget.isDockLanding }
            XCTAssertEqual(presented.count, 3)
            XCTAssertTrue(presented.allSatisfy { $0.opacity == 1 })
            XCTAssertNil(widget.dragVisual)
            XCTAssertNil(widget.dockLandingVisual)
        }
    }

    @MainActor
    func testEscapeDuringCommittedHandoffRestoresNativeTilesAndCancelsPendingWork() async throws {
        try await context { widget, preferences, store in
            var changes: [Bool] = []
            widget.systemDockLandingChanged = { changes.append($0) }
            widget.nativeDockFrames = { [:] }
            let docking = MacWidgetDocking(edge: .right, screenFrame: screen, visibleFrame: visible, systemDockEdge: .bottom)
            let frame = docking.frame(edge: .right, position: 0.5)
            widget.beginPointerPress(at: NSPoint(x: frame.midX, y: frame.midY), frame: frame, bounds: visible,
                clickCount: 1, timestamp: 1, docking: docking)
            guard case .drag(let placement) = widget.finishPointerPress(at: NSPoint(x: screen.midX, y: screen.minY + 20), doubleClickInterval: 0.5) else {
                return XCTFail("Expected drag completion")
            }
            widget.settleDrop(placement)
            XCTAssertTrue(widget.isDockLanding)
            widget.closeDetails()
            XCTAssertEqual(changes, [true, false])
            XCTAssertTrue(preferences.isInSystemDock)
            XCTAssertNil(widget.dockLandingVisual)
            try await Task.sleep(for: .milliseconds(400))
            XCTAssertFalse(widget.isDockLanding)
            XCTAssertNil(widget.dockLandingVisual)
            XCTAssertNil(widget.dragVisual)
            XCTAssertEqual(changes, [true, false])
            XCTAssertEqual(store.profile.macDashboardMetrics.count, 3)
        }
    }

    @MainActor
    func testNativeDockDropKeepsAllSixTilesOpaqueThroughoutTheMoveAndHandoff() async throws {
        try await context(reducesMotion: true, nativeDockEdge: .bottom, metricCount: 6) { widget, preferences, store in
            let groupMetrics = store.profile.macDashboardMetrics
            var presented: [MacSystemDockPresentation] = []
            var released = false
            let dock = MacSystemDockController(store: store, preferences: preferences, openSettings: {},
                present: {
                    presented = $0
                    if released, !$0.isEmpty {
                        XCTAssertEqual($0.count, 6)
                        XCTAssertTrue($0.allSatisfy { $0.opacity == 1 },
                            "No helper update after release may make the existing circles transparent.")
                    }
                })
            dock.start()
            defer { dock.stop() }
            widget.nativeDockDragChanged = { dock.setDragging($0) }
            var restoredWithPreview = false
            widget.systemDockLandingChanged = { landing in
                dock.setLanding(landing, keepsNativeTilesVisible: widget.dragOrigin?.isSystemDock == true)
                if !landing, widget.dockLandingVisual != nil {
                    restoredWithPreview = presented.count == 6 && presented.allSatisfy { $0.opacity == 1 }
                }
            }
            var received: (NSPoint, MetricKind)?
            var allowCompletion = false
            widget.commitSystemDockDrop = { point, metric in
                received = (point, metric)
                while !allowCompletion, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(10)) }
                return !Task.isCancelled
            }
            let icon = NSRect(x: screen.midX - 100, y: screen.minY + 8, width: 64, height: 64)
            let docking = MacWidgetDocking(edge: .bottom, screenFrame: screen, visibleFrame: visible,
                metricCount: 6, systemDockEdge: .bottom)
            widget.nativeDockFrames = {
                Dictionary(uniqueKeysWithValues: groupMetrics.enumerated().map {
                    ($0.element, icon.offsetBy(dx: CGFloat($0.offset) * 68, dy: 0))
                })
            }
            widget.beginPointerPress(at: NSPoint(x: icon.midX, y: icon.midY), frame: icon, bounds: visible,
                clickCount: 1, timestamp: 1, docking: docking, nativeDockMetric: .month)
            let drop = NSPoint(x: icon.midX + 180, y: icon.midY)
            guard case .drag(let placement) = widget.finishPointerPress(at: drop, doubleClickInterval: 0.5) else {
                return XCTFail("Expected a native Dock drag")
            }
            XCTAssertTrue(presented.allSatisfy { $0.opacity == 0.22 }, "A held drag keeps its existing source treatment.")
            released = true
            widget.settleDrop(placement)
            try await eventually { received != nil }
            XCTAssertEqual(received?.0, drop)
            XCTAssertEqual(received?.1, .month)
            XCTAssertTrue(widget.isDockLanding)
            XCTAssertEqual(widget.dockLandingVisual?.tiles.count, 1, "Already-visible native circles need no duplicate fan-out.")
            XCTAssertEqual(widget.dockLandingVisual?.tiles.filter { $0.value.opacity > 0 }.map(\.key), [.month])
            XCTAssertTrue(presented.allSatisfy { $0.opacity == 1 })
            for presentation in presented {
                let renderer = ImageRenderer(content: MacSystemDockTileView(presentation: presentation))
                let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
                XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2,
                    y: bitmap.pixelsHigh / 2)).alphaComponent, 0.99)
            }
            allowCompletion = true
            try await eventually { !widget.isDockLanding }
            XCTAssertTrue(restoredWithPreview, "Native images must remain fully visible when the preview disappears.")
            XCTAssertTrue(presented.allSatisfy { $0.opacity == 1 })
            XCTAssertNil(widget.dockLandingVisual)
        }
    }

    @MainActor
    func testChangingToAnotherEdgeDuringNativeCommitClearsTheLandingPreview() async throws {
        try await context(reducesMotion: true, nativeDockEdge: .bottom) { widget, preferences, _ in
            var entered = false
            var allowCompletion = false
            widget.commitSystemDockDrop = { _, _ in
                entered = true
                while !allowCompletion, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(10)) }
                return false
            }
            let icon = NSRect(x: screen.midX - 24, y: screen.minY + 8, width: 48, height: 48)
            let docking = MacWidgetDocking(edge: .bottom, screenFrame: screen, visibleFrame: visible,
                metricCount: metrics.count, systemDockEdge: .bottom)
            widget.beginPointerPress(at: NSPoint(x: icon.midX, y: icon.midY), frame: icon, bounds: visible,
                clickCount: 1, timestamp: 1, docking: docking, nativeDockMetric: .month)
            guard case .drag(let placement) = widget.finishPointerPress(
                at: NSPoint(x: icon.midX + 180, y: icon.midY), doubleClickInterval: 0.5) else {
                return XCTFail("Expected a native Dock drag")
            }
            widget.settleDrop(placement)
            try await eventually { entered }
            XCTAssertTrue(widget.isDockLanding)
            XCTAssertTrue(preferences.selectEdge(.right, dockEdge: .bottom))
            allowCompletion = true
            try await eventually { !widget.isChangingPlacement }
            XCTAssertFalse(preferences.isInSystemDock)
            XCTAssertEqual(preferences.edge, .right)
            XCTAssertFalse(widget.isDockLanding)
            XCTAssertNil(widget.dockLandingVisual)
            XCTAssertNil(widget.dragVisual)
        }
    }

    @MainActor
    func testEscapeCancelsPendingNativeGroupMoveAndPreventsItsLateHandoff() async throws {
        try await context { widget, preferences, _ in
            var entered = false
            var cancelled = false
            widget.commitSystemDockDrop = { _, _ in
                entered = true
                do { try await Task.sleep(for: .seconds(30)) }
                catch { cancelled = Task.isCancelled }
                return !cancelled
            }
            let docking = MacWidgetDocking(edge: .right, screenFrame: screen, visibleFrame: visible,
                systemDockEdge: .bottom)
            let frame = docking.frame(edge: .right, position: 0.5)
            widget.beginPointerPress(at: NSPoint(x: frame.midX, y: frame.midY), frame: frame, bounds: visible,
                clickCount: 1, timestamp: 1, docking: docking)
            guard case .drag(let placement) = widget.finishPointerPress(
                at: NSPoint(x: screen.midX, y: screen.minY + 20), doubleClickInterval: 0.5) else {
                return XCTFail("Expected a Dock landing")
            }
            widget.settleDrop(placement)
            try await eventually { entered }
            widget.closeDetails()
            try await eventually { cancelled }
            XCTAssertFalse(widget.isDockLanding)
            XCTAssertNil(widget.dockLandingVisual)
            XCTAssertNil(widget.dragVisual)
            XCTAssertTrue(preferences.isInSystemDock)
        }
    }

    @MainActor
    func testInterruptedNativeMoveNeverFansThePreviewOutIntoScatteredSlots() async throws {
        try await context { widget, preferences, _ in
            widget.commitSystemDockDrop = { _, _ in false }
            let scattered = Dictionary(uniqueKeysWithValues: metrics.enumerated().map {
                ($0.element, NSRect(x: screen.minX + 200 + CGFloat($0.offset) * 350,
                                   y: screen.minY + 8, width: 48, height: 48))
            })
            widget.nativeDockFrames = { scattered }
            var restoredFrames: [MetricKind: NSRect]?
            widget.systemDockLandingChanged = { landing in
                if !landing, let visual = widget.dockLandingVisual { restoredFrames = visual.tiles.mapValues(\.frame) }
            }
            let docking = MacWidgetDocking(edge: .right, screenFrame: screen, visibleFrame: visible,
                systemDockEdge: .bottom)
            let frame = docking.frame(edge: .right, position: 0.5)
            widget.beginPointerPress(at: NSPoint(x: frame.midX, y: frame.midY), frame: frame, bounds: visible,
                clickCount: 1, timestamp: 1, docking: docking)
            guard case .drag(let placement) = widget.finishPointerPress(
                at: NSPoint(x: screen.midX, y: screen.minY + 20), doubleClickInterval: 0.5) else {
                return XCTFail("Expected a Dock landing")
            }
            widget.settleDrop(placement)
            let initial = try XCTUnwrap(widget.dockLandingVisual?.tiles.mapValues(\.frame))
            try await eventually { !widget.isDockLanding }
            XCTAssertEqual(restoredFrames, initial)
            XCTAssertNotEqual(restoredFrames, scattered)
            XCTAssertTrue(preferences.isInSystemDock)
            XCTAssertNil(widget.dockLandingVisual)
        }
    }

    @MainActor
    func testMissingGeometryAtReleaseAndDuringFlightKeepsTheCarriedCircleOpaque() async throws {
        try await context(nativeDockEdge: .bottom) { widget, _, _ in
            var frames: [MetricKind: NSRect]?
            widget.nativeDockFrames = { frames }
            widget.commitSystemDockDrop = { _, _ in true }
            var awaitingDisplay = false
            var displayReady = false
            widget.systemDockDisplayReady = {
                awaitingDisplay = true
                while !displayReady, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(10)) }
                return !Task.isCancelled
            }
            try beginNativeLanding(widget)
            defer { widget.abortDockPlacement() }
            let initial = try XCTUnwrap(widget.dockLandingVisual)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(widget.dockLandingVisual, initial, "A nil geometry read must keep the carried circle visible.")
            let confirmed = Dictionary(uniqueKeysWithValues: metrics.enumerated().map {
                ($0.element, NSRect(x: screen.midX + CGFloat($0.offset) * 68,
                                   y: screen.minY + 8, width: 48, height: 48))
            })
            frames = confirmed
            try await eventually { widget.dockLandingVisual?.tiles[.month]?.frame != initial.tiles[.month]?.frame }
            // A transient partial read during the flight must neither fade the
            // preview nor move it back toward an inferred Dock position.
            frames = [.month: try XCTUnwrap(confirmed[.month])]
            let deadline = ContinuousClock.now.advanced(by: .seconds(2))
            while !awaitingDisplay, ContinuousClock.now < deadline {
                XCTAssertEqual(widget.dockLandingVisual?.tiles[.month]?.opacity, 1)
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertTrue(awaitingDisplay)
            XCTAssertEqual(widget.dockLandingVisual?.tiles.mapValues(\.frame), [.month: try XCTUnwrap(confirmed[.month])])
            XCTAssertTrue(try XCTUnwrap(widget.dockLandingVisual).tiles.values.allSatisfy { $0.opacity == 1 })
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertTrue(widget.isDockLanding, "Do not dismiss the preview before the native tile has drawn.")
            displayReady = true
            try await eventually { !widget.isDockLanding }
            XCTAssertNil(widget.dockLandingVisual)
        }
    }

    @MainActor
    func testUnavailableGeometryHandsOffFromAnOpaqueCircleWithoutInventingSlots() async throws {
        for reducedMotion in [false, true] {
            try await context(reducesMotion: reducedMotion, nativeDockEdge: .bottom) { widget, _, _ in
                widget.nativeDockFrames = { nil }
                widget.commitSystemDockDrop = { _, _ in true }
                var restored = false
                widget.systemDockLandingChanged = { if !$0 { restored = true } }
                var awaitingDisplay = false
                var displayReady = false
                widget.systemDockDisplayReady = {
                    awaitingDisplay = true
                    while !displayReady, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(10)) }
                    return !Task.isCancelled
                }
                try beginNativeLanding(widget)
                defer { widget.abortDockPlacement() }
                let initial = try XCTUnwrap(widget.dockLandingVisual)
                try await eventually { awaitingDisplay }
                XCTAssertTrue(restored)
                XCTAssertEqual(widget.dockLandingVisual, initial)
                XCTAssertEqual(widget.dockLandingVisual?.tiles[.month]?.opacity, 1)
                XCTAssertTrue(widget.isDockLanding)
                displayReady = true
                try await eventually { !widget.isDockLanding }
                XCTAssertNil(widget.dragVisual)
            }
        }
    }

    @MainActor
    func testLandingOverlayDrawsOpaqueCirclesWithoutIntermediateImageSnapshots() throws {
        let viewport = NSRect(x: 0, y: 0, width: 400, height: 220)
        let carried = NSRect(x: 145, y: 82, width: 44, height: 44)
        let visual = MacWidgetDragVisual(widgetFrame: carried, focusFrame: carried, circleFrame: carried, coalescence: 1)
        let docking = MacWidgetDocking(edge: .left, screenFrame: viewport, visibleFrame: viewport, systemDockEdge: .left)
        let target = MacWidgetDropTarget(edge: .left, position: 0.5, frame: NSRect(x: 0, y: 0, width: 80, height: 220), isSystemDock: true)
        let frames = Dictionary(uniqueKeysWithValues: metrics.enumerated().map {
            ($0.element, NSRect(x: 12, y: 12 + $0.offset * 66, width: 48, height: 48))
        })
        let presentations = Dictionary(uniqueKeysWithValues: metrics.map {
            ($0, MacSystemDockPresentation(snapshot: TimeProgressCalculator.snapshot(for: $0, profile: .initial), accent: .green))
        })
        let initial = MacSystemDockLandingVisual.start(metrics: metrics, grabbed: .month, visual: visual)
        let destination = MacSystemDockLandingVisual.destination(metrics: metrics, nativeFrames: frames, target: target, docking: docking)
        for progress in [0.0, 0.5, 1.0] {
            let landing = initial.interpolated(to: destination, progress: progress)
            let overlay = MacWidgetDragOverlay(docking: docking, visual: visual, widgetImage: nil,
                snapshot: try XCTUnwrap(presentations[.month]?.snapshot), accent: .green,
                dockLanding: landing, dockPresentations: presentations)
            let renderer = ImageRenderer(content: overlay)
            renderer.scale = 1
            let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
            let active = try XCTUnwrap(landing.tiles[.month]?.frame)
            let center = try XCTUnwrap(bitmap.colorAt(x: Int(active.midX), y: Int(viewport.maxY - active.midY)))
            XCTAssertGreaterThan(center.alphaComponent, 0.99, "The carried circle must have real opaque pixels, not just opacity state.")
            if progress == 1 {
                for frame in frames.values {
                    let color = try XCTUnwrap(bitmap.colorAt(x: Int(frame.midX), y: Int(viewport.maxY - frame.midY)))
                    XCTAssertGreaterThan(color.alphaComponent, 0.99)
                }
                XCTAssertLessThan(try XCTUnwrap(bitmap.colorAt(x: 36, y: 151)).alphaComponent, 0.01,
                    "The gap between circles must stay clear.")
            }
        }
    }

    @MainActor
    func testLateDisplayAcknowledgementRetainsPreviewThroughRetry() async throws {
        try await context(reducesMotion: true, nativeDockEdge: .bottom) { widget, _, _ in
            widget.commitSystemDockDrop = { _, _ in true }
            widget.nativeDockFrames = {
                Dictionary(uniqueKeysWithValues: self.metrics.enumerated().map {
                    ($0.element, NSRect(x: self.screen.midX + CGFloat($0.offset) * 68,
                        y: self.screen.minY + 8, width: 48, height: 48))
                })
            }
            var attempts = 0
            var displayReady = false
            widget.systemDockDisplayReady = {
                attempts += 1
                if attempts == 1 { return false }
                while !displayReady, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(10)) }
                return !Task.isCancelled
            }
            try beginNativeLanding(widget)
            defer { widget.abortDockPlacement() }
            try await eventually { attempts == 2 }
            XCTAssertTrue(widget.isDockLanding)
            XCTAssertEqual(widget.dockLandingVisual?.tiles[.month]?.opacity, 1)
            displayReady = true
            try await eventually { !widget.isDockLanding }
            XCTAssertNil(widget.dockLandingVisual)
        }
    }

    @MainActor
    private func beginNativeLanding(_ widget: MacWidgetController) throws {
        let icon = NSRect(x: screen.midX - 24, y: screen.minY + 8, width: 48, height: 48)
        let docking = MacWidgetDocking(edge: .bottom, screenFrame: screen, visibleFrame: visible,
            metricCount: metrics.count, systemDockEdge: .bottom)
        widget.beginPointerPress(at: NSPoint(x: icon.midX, y: icon.midY), frame: icon, bounds: visible,
            clickCount: 1, timestamp: 1, docking: docking, nativeDockMetric: .month)
        guard case .drag(let placement) = widget.finishPointerPress(
            at: NSPoint(x: icon.midX + 180, y: icon.midY), doubleClickInterval: 0.5) else {
            return XCTFail("Expected a native Dock landing")
        }
        widget.settleDrop(placement)
    }

    @MainActor
    private func context<T>(_ body: (MacWidgetController, MacWidgetPreferences, ProfileStore) throws -> T) throws -> T {
        let suite = "com.hinoshiba.daysyet.dock-landing.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = MacWidgetPreferences(defaults: defaults, supportsSystemDock: true, readDockPermission: { true })
        let store = ProfileStore(profile: .initial, saveProfile: { _ in })
        return try body(MacWidgetController(store: store, preferences: preferences, reducesMotion: { false }), preferences, store)
    }

    @MainActor
    private func context(reducesMotion: Bool = false, nativeDockEdge: MacWidgetEdge? = nil, metricCount: Int = 3,
                         _ body: (MacWidgetController, MacWidgetPreferences, ProfileStore) async throws -> Void) async throws {
        let suite = "com.hinoshiba.daysyet.dock-landing.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = MacWidgetPreferences(defaults: defaults, supportsSystemDock: true, readDockPermission: { true })
        if let edge = nativeDockEdge {
            // Establish the source before observing preference changes. A real
            // edge change during a held drag deliberately cancels that drag.
            preferences.reconcileDockLocation(edge)
            preferences.edge = edge
            preferences.isInSystemDock = true
        }
        var profile = UserProfile.initial
        profile.dashboardMetrics = Array(MetricKind.allCases.prefix(metricCount))
        let store = ProfileStore(profile: profile, saveProfile: { _ in })
        try await body(MacWidgetController(store: store, preferences: preferences, reducesMotion: { reducesMotion }), preferences, store)
    }

    @MainActor
    private func eventually(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition())
    }
}
