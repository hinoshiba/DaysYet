import AppKit
import SwiftUI
import XCTest
@testable import DaysYetMac

final class MacSystemDockTransitionTests: XCTestCase {
    private let screen = NSRect(x: -1600, y: 120, width: 1600, height: 1000)
    private var visible: NSRect { NSRect(x: -1600, y: 200, width: 1600, height: 888) }

    private func point(_ edge: MacWidgetEdge, distance: CGFloat = 25) -> NSPoint {
        switch edge {
        case .left: NSPoint(x: screen.minX + distance, y: screen.midY)
        case .right: NSPoint(x: screen.maxX - distance, y: screen.midY)
        case .bottom: NSPoint(x: screen.midX, y: screen.minY + distance)
        case .top: NSPoint(x: screen.midX, y: screen.maxY - distance)
        }
    }

    func testOnlyTheDockSideRoutesIntoTheSystemDockAndCornersUseTheCloserEdge() throws {
        for dock in [MacWidgetEdge.left, .right, .bottom] {
            let docking = MacWidgetDocking(edge: .top, screenFrame: screen, visibleFrame: visible,
                metricCount: 8, systemDockEdge: dock)
            let original = docking.frame(edge: .top, position: 0.5)
            for edge in MacWidgetEdge.allCases {
                let target = try XCTUnwrap(docking.target(at: point(edge), previous: nil, originalFrame: original, anchor: point(.top)))
                XCTAssertEqual(target.edge, edge)
                XCTAssertEqual(target.isSystemDock, edge == dock)
                XCTAssertEqual(docking.attachment(at: point(edge), target: target, previous: nil), target)
            }
            let corner = NSPoint(x: screen.minX + 20, y: screen.maxY - 5)
            let target = try XCTUnwrap(docking.target(at: corner, previous: .left, originalFrame: original, anchor: point(.top)))
            XCTAssertEqual(target.edge, .top)
            XCTAssertFalse(target.isSystemDock)
        }
    }

    func testDockLocationUsesReservedSpaceAndAutoHiddenDockClickCoordinates() {
        XCTAssertEqual(MacSystemDockLocation.reservedEdge(screen: screen, visible: visible), .bottom)
        XCTAssertEqual(MacSystemDockLocation.reservedEdge(screen: screen,
            visible: NSRect(x: screen.minX + 72, y: screen.minY, width: screen.width - 72, height: screen.height - 32)), .left)
        XCTAssertEqual(MacSystemDockLocation.reservedEdge(screen: screen,
            visible: NSRect(x: screen.minX, y: screen.minY, width: screen.width - 72, height: screen.height - 32)), .right)
        XCTAssertNil(MacSystemDockLocation.reservedEdge(screen: screen,
            visible: NSRect(x: screen.minX, y: screen.minY, width: screen.width, height: screen.height - 32)))
        for edge in [MacWidgetEdge.left, .right, .bottom] {
            XCTAssertEqual(MacSystemDockLocation.clickedEdge(at: point(edge), screen: screen), edge)
        }
    }

    @MainActor
    func testDraggingAnyCircleOutMovesTheWholeGroupAndRemovesEveryDockTile() async throws {
        try await withContext(inDock: true, count: 8) { controller, preferences, store in
            var tiles: [MetricKind] = []
            var opened = 0
            let dock = MacSystemDockController(store: store, preferences: preferences, openSettings: {},
                openGroup: { opened += 1 }, present: { tiles = $0.map(\.snapshot.kind) })
            dock.start()
            dock.handle(.openGroup)
            XCTAssertEqual(opened, 1)
            XCTAssertEqual(tiles.count, 8)
            let docking = geometry(edge: .bottom, count: 8)
            let layout = MacSystemDockGroupLayout(edge: .bottom, count: 8)
            let frame = layout.frame(near: point(.bottom), screen: screen, visible: visible)
            let focus = layout.focus(in: frame, index: 7)
            controller.beginPointerPress(at: NSPoint(x: focus.midX, y: focus.midY), frame: frame, bounds: visible,
                clickCount: 1, timestamp: 1, docking: docking, dockGroupIndex: 7)
            XCTAssertEqual(controller.dragOrigin?.metric, store.profile.macDashboardMetrics[7])
            XCTAssertEqual(controller.dragOrigin?.focusFrame, focus)
            XCTAssertEqual(controller.dragOrigin?.isSystemDock, true)
            _ = controller.updatePointerPress(at: point(.left))
            XCTAssertEqual(controller.dragAttachment?.isSystemDock, false)
            XCTAssertEqual(controller.dragVisual?.coalescence, 0)
            XCTAssertTrue(preferences.isInSystemDock, "A held preview must not remove the real Dock group.")
            let drop = try finish(controller, at: point(.left))
            controller.settleDrop(drop)
            try await Task.sleep(for: .milliseconds(40))
            XCTAssertFalse(preferences.isInSystemDock)
            XCTAssertEqual(preferences.edge, .left)
            XCTAssertTrue(tiles.isEmpty)
            dock.handle(.openGroup)
            XCTAssertEqual(opened, 1, "A delayed Dock click cannot reopen a removed group.")
            dock.stop()
        }
    }

    @MainActor
    func testDockLandingSavesTheDockEdgeAndPreservesBothAxes() async throws {
        try await withContext(inDock: false) { controller, preferences, store in
            let docking = geometry(edge: .right)
            beginEdge(controller, docking: docking)
            _ = controller.updatePointerPress(at: point(.bottom))
            XCTAssertEqual(controller.dragAttachment?.isSystemDock, true)
            XCTAssertEqual(controller.dragVisual?.circleFrame.midX, point(.bottom).x)
            XCTAssertEqual(controller.dragVisual?.circleFrame.midY, point(.bottom).y)
            XCTAssertEqual(controller.dragVisual?.coalescence, 1)
            XCTAssertFalse(preferences.isInSystemDock)
            controller.settleDrop(try finish(controller, at: point(.bottom)))
            XCTAssertTrue(preferences.isInSystemDock)
            XCTAssertEqual(preferences.edge, .bottom)
            XCTAssertEqual(preferences.verticalPosition, 0.24)
            XCTAssertEqual(preferences.horizontalPosition, 0.72)
            XCTAssertEqual(store.profile.macDashboardMetrics.count, 3)
        }
    }

    @MainActor
    func testDropUsesTheDockLocationObservedByTheGestureBeforeTheNextPoll() async throws {
        try await withContext(inDock: false) { controller, preferences, _ in
            preferences.reconcileDockLocation(.left)
            // macOS moved its Dock to the bottom after the last background poll.
            beginEdge(controller, docking: geometry(edge: .right))
            _ = controller.updatePointerPress(at: point(.left))
            XCTAssertEqual(controller.dragAttachment?.isSystemDock, false)
            controller.settleDrop(try finish(controller, at: point(.left)))
            XCTAssertEqual(preferences.edge, .left)
            XCTAssertFalse(preferences.isInSystemDock)
            XCTAssertEqual(preferences.lastSystemDockEdge, .bottom)
        }
    }

    @MainActor
    func testCenterReleaseAndEscapeRestoreTheDockGroupWithoutChangingItsMode() async throws {
        try await withContext(inDock: true) { controller, preferences, _ in
            for cancel in [false, true] {
                let docking = geometry(edge: .bottom)
                let layout = MacSystemDockGroupLayout(edge: .bottom, count: 3)
                let frame = layout.frame(near: point(.bottom), screen: screen, visible: visible)
                let focus = layout.focus(in: frame, index: 1)
                controller.beginPointerPress(at: NSPoint(x: focus.midX, y: focus.midY), frame: frame, bounds: visible,
                    clickCount: 1, timestamp: 1, docking: docking, dockGroupIndex: 1)
                let center = NSPoint(x: screen.midX, y: screen.midY)
                _ = controller.updatePointerPress(at: center)
                XCTAssertEqual(controller.dragVisual?.coalescence, 1)
                XCTAssertNil(controller.dragPresentation?.target)
                if cancel { controller.closeDetails() }
                else { controller.settleDrop(try finish(controller, at: center)) }
                XCTAssertNil(controller.dragVisual)
                XCTAssertTrue(preferences.isInSystemDock)
                XCTAssertEqual(preferences.edge, .bottom)
                XCTAssertEqual(preferences.verticalPosition, 0.24)
            }
        }
    }

    @MainActor
    func testHeldDockPreviewCanPullAwayAndLandAtAnOrdinaryEdgeInTheSamePress() async throws {
        try await withContext(inDock: false) { controller, preferences, _ in
            beginEdge(controller, docking: geometry(edge: .right))
            _ = controller.updatePointerPress(at: point(.bottom))
            XCTAssertEqual(controller.dragAttachment?.isSystemDock, true)
            _ = controller.updatePointerPress(at: point(.bottom, distance: visible.minY - screen.minY + 41))
            XCTAssertNil(controller.dragAttachment)
            XCTAssertEqual(controller.dragVisual?.coalescence, 1)
            _ = controller.updatePointerPress(at: point(.left))
            XCTAssertEqual(controller.dragAttachment?.isSystemDock, false)
            XCTAssertEqual(controller.dragVisual?.coalescence, 0)
            controller.settleDrop(try finish(controller, at: point(.left)))
            XCTAssertFalse(preferences.isInSystemDock)
            XCTAssertEqual(preferences.edge, .left)
        }
    }

    @MainActor
    func testExpandedGroupsKeepAllCirclesVisibleAndHitTestableAtEveryDockOrientation() async throws {
        for count in [3, 8] {
            try await withContext(inDock: true, count: count) { _, preferences, store in
                for edge in [MacWidgetEdge.left, .right, .bottom] {
                    let layout = MacSystemDockGroupLayout(edge: edge, count: count)
                    let frame = layout.frame(near: point(edge), screen: screen, visible: visible)
                    XCTAssertTrue(visible.contains(frame))
                    let renderer = ImageRenderer(content: MacSystemDockGroupView(store: store, preferences: preferences, edge: edge))
                    renderer.scale = 2
                    let image = try XCTUnwrap(renderer.cgImage)
                    XCTAssertEqual(image.width, Int(layout.size.width * 2))
                    XCTAssertEqual(image.height, Int(layout.size.height * 2))
                    for index in 0..<count {
                        let ring = layout.ring(at: index)
                        XCTAssertEqual(layout.index(at: NSPoint(x: ring.midX, y: ring.midY)), index)
                        XCTAssertTrue(frame.contains(layout.focus(in: frame, index: index)))
                    }
                    let attachment = XCTAttachment(image: NSImage(cgImage: image, size: layout.size))
                    attachment.name = "Dock group \(edge.rawValue) \(count)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
    }

    private func geometry(edge: MacWidgetEdge, count: Int = 3) -> MacWidgetDocking {
        MacWidgetDocking(edge: edge, screenFrame: screen, visibleFrame: visible, metricCount: count, systemDockEdge: .bottom)
    }

    @MainActor
    private func beginEdge(_ controller: MacWidgetController, docking: MacWidgetDocking) {
        let frame = docking.frame(edge: docking.edge, position: 0.24)
        controller.beginPointerPress(at: NSPoint(x: frame.midX, y: frame.midY), frame: frame, bounds: visible,
            clickCount: 1, timestamp: 1, docking: docking)
    }

    @MainActor
    private func finish(_ controller: MacWidgetController, at point: NSPoint) throws -> MacWidgetPointerInteraction.Placement {
        guard case .drag(let drop) = controller.finishPointerPress(at: point, doubleClickInterval: 0.5) else {
            throw CocoaError(.coderInvalidValue)
        }
        return drop
    }

    @MainActor
    private func withContext(inDock: Bool, count: Int = 3,
        _ body: (MacWidgetController, MacWidgetPreferences, ProfileStore) async throws -> Void) async throws {
        let suite = "com.hinoshiba.daysyet.dock-transition.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = MacWidgetPreferences(defaults: defaults, supportsSystemDock: true, readDockPermission: { true })
        preferences.edge = inDock ? .bottom : .right
        preferences.verticalPosition = 0.24
        preferences.horizontalPosition = 0.72
        preferences.isInSystemDock = inDock
        preferences.reconcileDockLocation(.bottom)
        var profile = UserProfile.initial
        profile.dashboardMetrics = Array(MetricKind.allCases.prefix(count))
        let store = ProfileStore(profile: profile, saveProfile: { _ in })
        let controller = MacWidgetController(store: store, preferences: preferences, reducesMotion: { true })
        try await body(controller, preferences, store)
    }
}
