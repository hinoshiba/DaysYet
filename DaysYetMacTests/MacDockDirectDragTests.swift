import AppKit
import XCTest
@testable import DaysYetMac

final class MacDockDirectDragTests: XCTestCase {
    private let screen = NSRect(x: -1600, y: 120, width: 1600, height: 1000)
    private let icon = NSRect(x: -840, y: 128, width: 64, height: 64)

    func testWholeDockSlotIsProtectedIncludingTransparentCornersButNotNeighbors() {
        let frame = NSRect(x: -100, y: 20, width: 64, height: 64)
        XCTAssertTrue(MacDockDirectHitGeometry.contains(NSPoint(x: -68, y: 52), frame: frame))
        XCTAssertTrue(MacDockDirectHitGeometry.contains(NSPoint(x: -40, y: 52), frame: frame))
        XCTAssertTrue(MacDockDirectHitGeometry.contains(NSPoint(x: -39, y: 52), frame: frame))
        for corner in [NSPoint(x: -99, y: 21), NSPoint(x: -37, y: 21),
                       NSPoint(x: -99, y: 83), NSPoint(x: -37, y: 83)] {
            XCTAssertTrue(MacDockDirectHitGeometry.contains(corner, frame: frame))
        }
        XCTAssertFalse(MacDockDirectHitGeometry.contains(NSPoint(x: -101, y: 52), frame: frame))
        XCTAssertFalse(MacDockDirectHitGeometry.contains(NSPoint(x: -35, y: 52), frame: frame))
        XCTAssertFalse(MacDockDirectHitGeometry.contains(NSPoint(x: 4, y: 52), frame: frame))
        for bad in [NSRect.zero, NSRect(x: 0, y: 0, width: 1000, height: 64),
                    NSRect(x: CGFloat.nan, y: 0, width: 64, height: 64)] {
            XCTAssertFalse(MacDockDirectHitGeometry.contains(.zero, frame: bad))
        }
        XCTAssertFalse(MacDockDirectHitGeometry.contains(NSPoint(x: CGFloat.infinity, y: 52), frame: frame))
    }

    @MainActor
    func testGrabbingTransparentCornerStillMovesAllCirclesToAnotherEdge() throws {
        try context { widget, preferences, store in
            var presentations: [MacSystemDockPresentation] = []
            let dock = MacSystemDockController(store: store, preferences: preferences, openSettings: {},
                present: { presentations = $0 })
            dock.start()
            defer { dock.stop() }
            widget.nativeDockDragChanged = { dock.setDragging($0) }
            let geometry = MacWidgetDocking(edge: .bottom, screenFrame: screen,
                visibleFrame: screen.insetBy(dx: 0, dy: 80), metricCount: 3, systemDockEdge: .bottom)
            widget.beginPointerPress(at: NSPoint(x: icon.minX + 1, y: icon.minY + 1), frame: icon,
                bounds: geometry.visibleFrame, clickCount: 1, timestamp: 1, docking: geometry, nativeDockMetric: .month)
            let left = NSPoint(x: screen.minX + 20, y: screen.midY)
            _ = widget.updatePointerPress(at: left)
            XCTAssertEqual(presentations.count, 3)
            guard case .drag(let placement) = widget.finishPointerPress(at: left, doubleClickInterval: 0.5) else {
                return XCTFail("The slot corner must begin a group drag")
            }
            widget.settleDrop(placement)
            XCTAssertFalse(preferences.isInSystemDock)
            XCTAssertTrue(presentations.isEmpty)
            XCTAssertEqual(preferences.edge, .left)
        }
    }

    @MainActor
    func testNativePressUsesTheGrabbedMetricAndDimsOnlyAfterMovement() throws {
        try context { widget, preferences, store in
            var states: [Bool] = []
            widget.nativeDockDragChanged = { states.append($0) }
            begin(widget, metric: store.profile.macDashboardMetrics[1])
            XCTAssertTrue(widget.hasNativeDockPress)
            XCTAssertEqual(widget.dragOrigin?.metric, .month)
            XCTAssertEqual(widget.dragOrigin?.widgetFrame, icon)
            XCTAssertEqual(widget.dragOrigin?.isNativeDock, true)
            XCTAssertTrue(states.isEmpty)
            _ = widget.updatePointerPress(at: NSPoint(x: icon.midX + 2, y: icon.midY))
            XCTAssertTrue(states.isEmpty)
            _ = widget.updatePointerPress(at: NSPoint(x: screen.midX, y: screen.midY))
            XCTAssertEqual(states, [true])
            XCTAssertEqual(widget.dragVisual?.coalescence, 1)
            XCTAssertTrue(preferences.isInSystemDock)
            widget.abortNativeDockDrag()
            XCTAssertEqual(states, [true, false])
            XCTAssertFalse(widget.hasNativeDockPress)
            XCTAssertNil(widget.dragOrigin)
            XCTAssertNil(widget.dragVisual)
            XCTAssertTrue(preferences.isInSystemDock)
        }
    }

    @MainActor
    func testCentralReleaseEscapeAndDockReturnKeepAllNativeTiles() throws {
        try context { widget, preferences, store in
            var presentations: [MacSystemDockPresentation] = []
            let dock = MacSystemDockController(store: store, preferences: preferences, openSettings: {},
                present: { presentations = $0 })
            dock.start()
            defer { dock.stop() }
            widget.nativeDockDragChanged = { dock.setDragging($0) }
            for action in 0..<3 {
                begin(widget, metric: .month)
                let center = NSPoint(x: screen.midX, y: screen.midY)
                _ = widget.updatePointerPress(at: center)
                XCTAssertEqual(presentations.count, 3)
                XCTAssertTrue(presentations.allSatisfy { $0.opacity == 0.22 })
                if action == 1 { widget.closeDetails() }
                else {
                    let point = action == 2 ? NSPoint(x: screen.midX, y: screen.minY + 20) : center
                    guard case .drag(let placement) = widget.finishPointerPress(at: point, doubleClickInterval: 0.5) else {
                        XCTFail("Expected a drag"); return
                    }
                    widget.settleDrop(placement)
                }
                XCTAssertTrue(preferences.isInSystemDock)
                XCTAssertEqual(preferences.edge, .bottom)
                XCTAssertEqual(preferences.verticalPosition, 0.24)
                XCTAssertEqual(preferences.horizontalPosition, 0.72)
                XCTAssertNil(widget.dragVisual)
                XCTAssertTrue(presentations.allSatisfy { $0.opacity == 1 })
            }
        }
    }

    @MainActor
    func testNativeDragKeepsTilesUntilReleaseAtAnotherEdgeThenRemovesWholeGroup() throws {
        try context { widget, preferences, store in
            var presentations: [MacSystemDockPresentation] = []
            let dock = MacSystemDockController(store: store, preferences: preferences, openSettings: {},
                present: { presentations = $0 })
            dock.start()
            defer { dock.stop() }
            widget.nativeDockDragChanged = { dock.setDragging($0) }
            begin(widget, metric: .year)
            let left = NSPoint(x: screen.minX + 20, y: screen.midY)
            _ = widget.updatePointerPress(at: left)
            XCTAssertEqual(presentations.count, 3)
            XCTAssertTrue(preferences.isInSystemDock)
            XCTAssertEqual(widget.dragAttachment?.edge, .left)
            XCTAssertEqual(widget.dragVisual?.coalescence, 0)
            guard case .drag(let placement) = widget.finishPointerPress(at: left, doubleClickInterval: 0.5) else {
                XCTFail("Expected a drag"); return
            }
            widget.settleDrop(placement)
            XCTAssertFalse(preferences.isInSystemDock)
            XCTAssertEqual(preferences.edge, .left)
            XCTAssertTrue(presentations.isEmpty)
            XCTAssertNil(widget.dragOrigin)
        }
    }

    @MainActor
    func testNativeClickDoesNotDimOrMoveTheDockGroup() throws {
        try context { widget, preferences, _ in
            var started = false
            widget.nativeDockDragChanged = { if $0 { started = true } }
            begin(widget, metric: .week)
            XCTAssertEqual(widget.finishPointerPress(at: NSPoint(x: icon.midX, y: icon.midY), doubleClickInterval: 0.5), .none)
            XCTAssertFalse(started)
            XCTAssertTrue(preferences.isInSystemDock)
            XCTAssertNil(widget.dragOrigin)
        }
    }

#if DAYSYET_DIRECT_DOCK_DRAG
    func testAXFrameConversionPreservesNegativeAndUpperDisplayCoordinates() {
        XCTAssertEqual(MacDockAccessibilityReader.appKitFrame(position: CGPoint(x: -1500, y: 800),
            size: CGSize(width: 64, height: 64), primaryScreenMaxY: 1000), NSRect(x: -1500, y: 136, width: 64, height: 64))
        XCTAssertEqual(MacDockAccessibilityReader.appKitFrame(position: CGPoint(x: 100, y: -500),
            size: CGSize(width: 80, height: 80), primaryScreenMaxY: 1000), NSRect(x: 100, y: 1420, width: 80, height: 80))
        XCTAssertNil(MacDockAccessibilityReader.appKitFrame(position: .zero, size: .zero, primaryScreenMaxY: 1000))
        XCTAssertNil(MacDockAccessibilityReader.appKitFrame(position: CGPoint(x: CGFloat.nan, y: 0),
            size: CGSize(width: 64, height: 64), primaryScreenMaxY: 1000))
    }
#endif

    @MainActor
    private func begin(_ widget: MacWidgetController, metric: MetricKind) {
        let docking = MacWidgetDocking(edge: .bottom, screenFrame: screen,
            visibleFrame: screen.insetBy(dx: 0, dy: 80), metricCount: 3, systemDockEdge: .bottom)
        widget.beginPointerPress(at: NSPoint(x: icon.midX, y: icon.midY), frame: icon, bounds: docking.visibleFrame,
            clickCount: 1, timestamp: 1, docking: docking, nativeDockMetric: metric)
    }

    @MainActor
    private func context(_ body: (MacWidgetController, MacWidgetPreferences, ProfileStore) throws -> Void) throws {
        let suite = "com.hinoshiba.daysyet.direct-dock.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = MacWidgetPreferences(defaults: defaults, supportsSystemDock: true, readDockPermission: { true })
        preferences.edge = .bottom
        preferences.verticalPosition = 0.24
        preferences.horizontalPosition = 0.72
        preferences.isInSystemDock = true
        preferences.reconcileDockLocation(.bottom)
        let store = ProfileStore(profile: .initial, saveProfile: { _ in })
        let widget = MacWidgetController(store: store, preferences: preferences, reducesMotion: { true })
        try body(widget, preferences, store)
    }
}
