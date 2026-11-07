import AppKit
import XCTest
@testable import DaysYetMac

@MainActor
final class MacDockPermissionTests: XCTestCase {
    func testRetiredVisualHandoffDiscardsLegacyOptInWithoutDisablingDockPlacement() throws {
        try withPreferences { preferences, defaults in
            XCTAssertFalse(preferences.dockVisualHandoffEnabled)
            defaults.set(true, forKey: "mac-widget-dock-visual-handoff")
            let restored = MacWidgetPreferences(defaults: defaults, readDockPermission: { true })
            XCTAssertFalse(restored.dockVisualHandoffEnabled)
            XCTAssertNil(defaults.object(forKey: "mac-widget-dock-visual-handoff"))
            XCTAssertTrue(restored.selectEdge(.bottom, dockEdge: .bottom))
            XCTAssertTrue(restored.isInSystemDock)
            XCTAssertFalse(restored.dockVisualHandoffEnabled)
            restored.reset()
            XCTAssertFalse(MacWidgetPreferences(defaults: defaults, readDockPermission: { true }).dockVisualHandoffEnabled)
        }
    }

    func testSettingsRejectsDockSideWithoutChangingPlacementOrCoordinates() throws {
        try withPreferences { preferences, _ in
            preferences.edge = .bottom
            preferences.verticalPosition = 0.27
            preferences.horizontalPosition = 0.73
            preferences.reconcileDockLocation(.left)
            XCTAssertFalse(preferences.selectEdge(.left, dockEdge: .left))
            XCTAssertEqual(preferences.edge, .bottom)
            XCTAssertFalse(preferences.isInSystemDock)
            XCTAssertEqual(preferences.verticalPosition, 0.27)
            XCTAssertEqual(preferences.horizontalPosition, 0.73)
            XCTAssertTrue(preferences.dockPermissionRequired)
            XCTAssertTrue(preferences.selectEdge(.top, dockEdge: .left))
            XCTAssertEqual(preferences.edge, .top)
            XCTAssertFalse(preferences.dockPermissionRequired)
        }
    }

    func testAutomaticDockPlacementCannotBypassPermissionThroughDirectPreferenceEdits() throws {
        try withPreferences { preferences, _ in
            preferences.reconcileDockLocation(.left)
            preferences.edge = .left
            XCTAssertNotEqual(preferences.edge, .left)
            XCTAssertFalse(preferences.isInSystemDock)
            XCTAssertTrue(preferences.dockPermissionRequired)
        }
    }

    func testSavedDockPlacementCannotLaunchHelpersWithoutPermission() throws {
        try withPreferences { preferences, defaults in
            preferences.edge = .left
            preferences.isInSystemDock = true
            let restored = MacWidgetPreferences(defaults: defaults, readDockPermission: { false })
            var batches: [[MacSystemDockPresentation]] = []
            let dock = MacSystemDockController(store: store(), preferences: restored, openSettings: {},
                readDockEdge: { .left }, present: { batches.append($0) })
            dock.start()
            defer { dock.stop() }
            XCTAssertTrue(batches.allSatisfy(\.isEmpty))
            XCTAssertFalse(restored.isInSystemDock)
            XCTAssertNotEqual(restored.edge, .left)
            XCTAssertTrue(restored.dockPermissionRequired)
        }
    }

    func testGrantAllowsRetryAndRevocationRemovesEveryTileEvenDuringInteraction() throws {
        var granted = false
        try withPreferences(permission: { granted }) { preferences, _ in
            var interacting = false
            var visible: [MacSystemDockPresentation] = []
            var cancelled = 0
            let dock = MacSystemDockController(store: store(), preferences: preferences, openSettings: {},
                readDockEdge: { .left }, isChangingPlacement: { interacting },
                accessRevoked: { cancelled += 1 }, present: { visible = $0 })
            dock.start()
            defer { dock.stop() }
            XCTAssertFalse(preferences.selectEdge(.left, dockEdge: .left))
            dock.refresh()
            XCTAssertTrue(visible.isEmpty)
            granted = true
            XCTAssertTrue(preferences.selectEdge(.left, dockEdge: .left))
            dock.refresh()
            XCTAssertEqual(visible.count, 3)
            XCTAssertTrue(preferences.isInSystemDock)
            interacting = true
            granted = false
            dock.synchronizeLocation()
            XCTAssertTrue(visible.isEmpty)
            XCTAssertEqual(cancelled, 1)
            XCTAssertFalse(preferences.isInSystemDock)
            XCTAssertNotEqual(preferences.edge, .left)
            dock.refresh()
            XCTAssertTrue(visible.isEmpty)
            XCTAssertEqual(cancelled, 1)
        }
    }

    func testPermissionIsRecheckedAtTheFinalPresentationBoundary() throws {
        var granted = true
        var readsBeforeRevocation: Int?
        try withPreferences(permission: {
            if let remaining = readsBeforeRevocation {
                readsBeforeRevocation = remaining - 1
                return remaining > 0
            }
            return granted
        }) { preferences, _ in
            preferences.reconcileDockLocation(.left)
            preferences.edge = .left
            var batches: [[MacSystemDockPresentation]] = []
            let dock = MacSystemDockController(store: store(), preferences: preferences, openSettings: {},
                present: { batches.append($0) })
            // The synchronization check passes, then permission disappears
            // before the presenter would create the helper processes.
            readsBeforeRevocation = 1
            dock.start()
            defer { dock.stop() }
            XCTAssertTrue(batches.allSatisfy(\.isEmpty))
            XCTAssertFalse(preferences.isInSystemDock)
            granted = false
            readsBeforeRevocation = nil
        }
    }

    func testBlockedDragHasNoDockPreviewAndReturnsWithoutCommitting() throws {
        try withPreferences { preferences, _ in
            preferences.reconcileDockLocation(.bottom)
            let widget = MacWidgetController(store: store(), preferences: preferences, reducesMotion: { true })
            let geometry = docking()
            let frame = geometry.frame(edge: .right, position: 0.5)
            let original = (preferences.edge, preferences.verticalPosition, preferences.horizontalPosition)
            widget.beginPointerPress(at: NSPoint(x: frame.midX, y: frame.midY), frame: frame,
                bounds: geometry.visibleFrame, clickCount: 1, timestamp: 1, docking: geometry)
            let point = NSPoint(x: 800, y: 20)
            _ = widget.updatePointerPress(at: point)
            XCTAssertNil(widget.dragAttachment)
            XCTAssertEqual(widget.dragVisual?.coalescence, 1)
            guard case .drag(let placement) = widget.finishPointerPress(at: point, doubleClickInterval: 0.5) else {
                return XCTFail("Expected a drag")
            }
            var landingChanges: [Bool] = []
            widget.systemDockLandingChanged = { landingChanges.append($0) }
            widget.settleDrop(placement)
            XCTAssertTrue(landingChanges.isEmpty)
            XCTAssertEqual(preferences.edge, original.0)
            XCTAssertEqual(preferences.verticalPosition, original.1)
            XCTAssertEqual(preferences.horizontalPosition, original.2)
            XCTAssertFalse(preferences.isInSystemDock)
            XCTAssertTrue(preferences.dockPermissionRequired)
            XCTAssertNil(widget.dragVisual)
        }
    }

    func testRevocationBetweenPreviewAndMouseUpPreventsDockInsertion() throws {
        var granted = true
        try withPreferences(permission: { granted }) { preferences, _ in
            preferences.reconcileDockLocation(.bottom)
            let widget = MacWidgetController(store: store(), preferences: preferences, reducesMotion: { true })
            let geometry = docking()
            let frame = geometry.frame(edge: .right, position: 0.5)
            widget.beginPointerPress(at: NSPoint(x: frame.midX, y: frame.midY), frame: frame,
                bounds: geometry.visibleFrame, clickCount: 1, timestamp: 1, docking: geometry)
            let point = NSPoint(x: 800, y: 20)
            _ = widget.updatePointerPress(at: point)
            XCTAssertEqual(widget.dragAttachment?.isSystemDock, true)
            granted = false
            guard case .drag(let placement) = widget.finishPointerPress(at: point, doubleClickInterval: 0.5) else {
                return XCTFail("Expected a drag")
            }
            widget.saveDrop(placement)
            XCTAssertEqual(preferences.edge, .right)
            XCTAssertFalse(preferences.isInSystemDock)
            widget.settleDrop(placement)
            XCTAssertFalse(widget.isDockLanding)
            XCTAssertEqual(preferences.edge, .right)
            XCTAssertNil(widget.dragVisual)
        }
    }

    private func store() -> ProfileStore { ProfileStore(profile: .initial, saveProfile: { _ in }) }

    private func docking() -> MacWidgetDocking {
        MacWidgetDocking(edge: .right, screenFrame: NSRect(x: 0, y: 0, width: 1600, height: 1000),
            visibleFrame: NSRect(x: 0, y: 80, width: 1600, height: 890), systemDockEdge: .bottom)
    }

    private func withPreferences(permission: @escaping () -> Bool = { false },
                                 _ body: (MacWidgetPreferences, UserDefaults) throws -> Void) throws {
        let suite = "com.hinoshiba.daysyet.dock-permission.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(MacWidgetPreferences(defaults: defaults, readDockPermission: permission), defaults)
    }
}
