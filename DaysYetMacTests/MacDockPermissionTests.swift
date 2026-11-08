import AppKit
import XCTest
@testable import DaysYetMac

@MainActor
final class MacDockPermissionTests: XCTestCase {
    func testStandardBuildCanSelectAndRestoreTheBottomEdgeWithABottomDock() throws {
        // This is the App Store configuration: Dock integration is compiled out.
        let suite = "com.hinoshiba.daysyet.bottom-regression.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = MacWidgetPreferences(defaults: defaults, supportsSystemDock: false)
        preferences.verticalPosition = 0.27
        preferences.horizontalPosition = 0.73
        XCTAssertTrue(preferences.selectEdge(.bottom, dockEdge: .bottom))
        XCTAssertEqual(preferences.edge, .bottom)
        XCTAssertFalse(preferences.isInSystemDock)
        XCTAssertFalse(preferences.dockPermissionRequired)
        let restored = MacWidgetPreferences(defaults: defaults, supportsSystemDock: false)
        restored.reconcileDockLocation(.bottom)
        XCTAssertEqual(restored.edge, .bottom)
        XCTAssertEqual(restored.verticalPosition, 0.27)
        XCTAssertEqual(restored.horizontalPosition, 0.73)
    }

    func testStandardBuildDragPreviewsAndSavesEveryDockSideAsAnOrdinaryRail() throws {
        let suite = "com.hinoshiba.daysyet.edge-drop.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        // Even an old Accessibility grant must not enable omitted Dock integration.
        let preferences = MacWidgetPreferences(defaults: defaults, supportsSystemDock: false, readDockPermission: { true })
        XCTAssertFalse(preferences.canUseSystemDock)
        let widget = MacWidgetController(store: store(), preferences: preferences, reducesMotion: { true })
        defer { widget.closeDetails() }
        for origin in [NSPoint.zero, NSPoint(x: -1512, y: 120)] {
            let screen = NSRect(origin: origin, size: NSSize(width: 1512, height: 982))
            for dockEdge in [MacWidgetEdge.bottom, .left, .right] {
                var visible = screen
                visible.size.height -= 38
                if dockEdge == .bottom { visible.origin.y += 80; visible.size.height -= 80 }
                if dockEdge == .left { visible.origin.x += 80; visible.size.width -= 80 }
                if dockEdge == .right { visible.size.width -= 80 }
                preferences.edge = .top
                preferences.reconcileDockLocation(dockEdge)
                let geometry = MacWidgetDocking(edge: .top, screenFrame: screen,
                    visibleFrame: visible, systemDockEdge: dockEdge)
                let frame = geometry.frame(edge: .top, position: 0.5)
                widget.beginPointerPress(at: NSPoint(x: frame.midX, y: frame.midY), frame: frame,
                    bounds: visible, clickCount: 1, timestamp: 1, docking: geometry)
                let point: NSPoint
                switch dockEdge {
                case .bottom: point = NSPoint(x: visible.midX + 80, y: visible.minY + 20)
                case .left: point = NSPoint(x: visible.minX + 20, y: visible.midY)
                case .right: point = NSPoint(x: visible.maxX - 20, y: visible.midY)
                case .top: fatalError("The macOS Dock cannot be at the top.")
                }
                let preview = try XCTUnwrap(widget.updatePointerPress(at: point))
                let target = try XCTUnwrap(preview.attachment)
                XCTAssertEqual(target.edge, dockEdge)
                XCTAssertFalse(target.isSystemDock)
                XCTAssertTrue(visible.contains(target.frame), "The rail must be visible above or beside the Dock.")
                XCTAssertEqual(widget.dragVisual?.coalescence, 0)
                XCTAssertEqual(preferences.edge, .top, "Holding a preview must not save it.")
                guard case .drag(let drop) = widget.finishPointerPress(at: point, doubleClickInterval: 0.5) else {
                    return XCTFail("Expected a completed edge drop")
                }
                widget.saveDrop(drop)
                preferences.reconcileDockLocation(dockEdge)
                XCTAssertEqual(preferences.edge, dockEdge)
                XCTAssertFalse(preferences.isInSystemDock)
                XCTAssertFalse(preferences.dockPermissionRequired)
            }
        }
    }

    func testStandardBuildRestoresLegacyDockPlacementWithoutStartingHelpers() throws {
        let suite = "com.hinoshiba.daysyet.dock-migration.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "mac-widget-system-dock")
        defaults.set("bottom", forKey: "mac-widget-edge")
        let preferences = MacWidgetPreferences(defaults: defaults, supportsSystemDock: false)
        var batches: [[MacSystemDockPresentation]] = []
        let dock = MacSystemDockController(store: store(), preferences: preferences, openSettings: {},
            readDockEdge: { .bottom }, present: { batches.append($0) })
        dock.start()
        defer { dock.stop() }
        XCTAssertEqual(preferences.edge, .bottom)
        XCTAssertFalse(preferences.isInSystemDock)
        XCTAssertFalse(preferences.dockPermissionRequired)
        XCTAssertTrue(batches.allSatisfy(\.isEmpty))
    }

    func testRetiredVisualHandoffDiscardsLegacyOptInWithoutDisablingDockPlacement() throws {
        try withPreferences { preferences, defaults in
            XCTAssertFalse(preferences.dockVisualHandoffEnabled)
            defaults.set(true, forKey: "mac-widget-dock-visual-handoff")
            let restored = MacWidgetPreferences(defaults: defaults, supportsSystemDock: true, readDockPermission: { true })
            XCTAssertFalse(restored.dockVisualHandoffEnabled)
            XCTAssertNil(defaults.object(forKey: "mac-widget-dock-visual-handoff"))
            XCTAssertTrue(restored.selectEdge(.bottom, dockEdge: .bottom))
            XCTAssertTrue(restored.isInSystemDock)
            XCTAssertFalse(restored.dockVisualHandoffEnabled)
            restored.reset()
            XCTAssertFalse(MacWidgetPreferences(defaults: defaults, supportsSystemDock: true, readDockPermission: { true }).dockVisualHandoffEnabled)
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
            let restored = MacWidgetPreferences(defaults: defaults, supportsSystemDock: true, readDockPermission: { false })
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
        try body(MacWidgetPreferences(defaults: defaults, supportsSystemDock: true, readDockPermission: permission), defaults)
    }
}
