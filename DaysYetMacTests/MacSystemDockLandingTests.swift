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

    func testAnOpenRowKeepsAllCirclesSeparateThroughoutItsFlight() throws {
        let layout = MacSystemDockGroupLayout(edge: .bottom, count: metrics.count)
        let frame = layout.frame(near: NSPoint(x: screen.midX, y: screen.minY + 20), screen: screen, visible: visible)
        let focus = layout.focus(in: frame, index: 1)
        let visual = MacWidgetDragVisual(widgetFrame: frame, focusFrame: focus, circleFrame: focus, coalescence: 0)
        let initial = MacSystemDockLandingVisual.start(metrics: metrics, grabbed: .month, visual: visual,
            layout: layout, isOpenPreview: true)
        let target = MacWidgetDropTarget(edge: .bottom, position: 0.5, frame: frame, isSystemDock: true)
        let frames = Dictionary(uniqueKeysWithValues: metrics.enumerated().map { index, metric in
            (metric, NSRect(x: -950 + index * 60, y: 128, width: 48, height: 48))
        })
        let destination = MacSystemDockLandingVisual.destination(metrics: metrics, nativeFrames: frames,
            target: target, docking: MacWidgetDocking(edge: .right, screenFrame: screen, visibleFrame: visible))
        for progress in [0.0, 0.2, 0.5, 0.9, 1] {
            let flight = initial.interpolated(to: destination, progress: progress)
            XCTAssertEqual(flight.tiles.count, 3)
            for metric in metrics { XCTAssertEqual(flight.tiles[metric]?.opacity, 1) }
            let ordered = try metrics.map { try XCTUnwrap(flight.tiles[$0]?.frame) }
            XCTAssertLessThan(ordered[0].maxX, ordered[1].minX)
            XCTAssertLessThan(ordered[1].maxX, ordered[2].minX)
        }
        XCTAssertEqual(initial.interpolated(to: destination, progress: 1).tiles.mapValues(\.frame), frames)
    }

    @MainActor
    func testReleasingAnAttachedDockPreviewDoesNotCollectItAgain() async throws {
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
            try await eventually { widget.dragVisual?.coalescence == 0 }
            for offset in [CGFloat(-70), 0, 80] {
                _ = widget.updatePointerPress(at: NSPoint(x: contact.x + offset, y: contact.y + 10))
                XCTAssertEqual(widget.dragVisual?.coalescence, 0)
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
            XCTAssertEqual(widget.dragVisual?.coalescence, 0)
            XCTAssertEqual(widget.dockLandingVisual?.tiles.count, 3)
            XCTAssertEqual(presented.count, 3)
            XCTAssertTrue(presented.allSatisfy { $0.opacity == 0 })
            try await Task.sleep(for: .milliseconds(70))
            XCTAssertEqual(widget.dragVisual?.coalescence, 0)
            XCTAssertEqual(widget.dockLandingVisual?.tiles.count, 3)
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
    private func context<T>(_ body: (MacWidgetController, MacWidgetPreferences, ProfileStore) throws -> T) throws -> T {
        let suite = "com.hinoshiba.daysyet.dock-landing.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = MacWidgetPreferences(defaults: defaults)
        let store = ProfileStore(profile: .initial, saveProfile: { _ in })
        return try body(MacWidgetController(store: store, preferences: preferences, reducesMotion: { false }), preferences, store)
    }

    @MainActor
    private func context(_ body: (MacWidgetController, MacWidgetPreferences, ProfileStore) async throws -> Void) async throws {
        let suite = "com.hinoshiba.daysyet.dock-landing.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = MacWidgetPreferences(defaults: defaults)
        let store = ProfileStore(profile: .initial, saveProfile: { _ in })
        try await body(MacWidgetController(store: store, preferences: preferences, reducesMotion: { false }), preferences, store)
    }

    @MainActor
    private func eventually(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition())
    }
}
