import AppKit
import SwiftUI
import XCTest
@testable import DaysYetMac

final class MacSystemDockTests: XCTestCase {
    @MainActor
    func testDockModePersistsWithoutReplacingTheSavedScreenPlacement() throws {
        try withPreferences { preferences, defaults in
            XCTAssertFalse(preferences.isInSystemDock)
            preferences.edge = .bottom
            preferences.horizontalPosition = 0.78
            preferences.verticalPosition = 0.23
            preferences.isInSystemDock = true
            let restored = MacWidgetPreferences(defaults: defaults, readDockPermission: { true })
            XCTAssertTrue(restored.isInSystemDock)
            XCTAssertEqual(restored.edge, .bottom)
            XCTAssertEqual(restored.horizontalPosition, 0.78)
            XCTAssertEqual(restored.verticalPosition, 0.23)
            restored.reset()
            XCTAssertFalse(MacWidgetPreferences(defaults: defaults, readDockPermission: { true }).isInSystemDock)
        }
    }

    @MainActor
    func testEveryConfiguredCircleGetsATileAndLiveEditsUpdateTheTileList() async throws {
        try await withPreferences { preferences, _ in
            let store = ProfileStore(profile: .initial, saveProfile: { _ in })
            var batches: [[MetricKind]] = []
            let controller = MacSystemDockController(store: store, preferences: preferences,
                openSettings: { XCTFail("A headless presenter must not open settings.") },
                present: { batches.append($0.map(\.snapshot.kind)) })
            controller.start()
            XCTAssertTrue(batches.isEmpty)
            preferences.isInSystemDock = true
            try await eventually { batches.last == [.week, .month, .year] }
            store.addMacDashboardMetric()
            try await eventually { batches.last == store.profile.macDashboardMetrics && batches.last?.count == 4 }
            store.setDashboardMetric(.activity, at: 0)
            try await eventually { batches.last?.first == .activity }
            store.removeMacDashboardMetric(at: 3)
            try await eventually { batches.last == store.profile.macDashboardMetrics && batches.last?.count == 3 }
            controller.stop()
            XCTAssertEqual(batches.last, [])
            let count = batches.count
            preferences.isInSystemDock = false
            try await Task.sleep(for: .milliseconds(30))
            XCTAssertEqual(batches.count, count, "Queued notifications cannot resurrect stopped Dock tiles.")
        }
    }

    @MainActor
    func testVisibleReorderHandoffDoesNotLeakIntoTheNextRepairOrInsertion() throws {
        try withPreferences { preferences, _ in
            preferences.isInSystemDock = true
            var presentations: [MacSystemDockPresentation] = []
            let controller = MacSystemDockController(store: ProfileStore(profile: .initial, saveProfile: { _ in }),
                preferences: preferences, openSettings: {}, present: { presentations = $0 })
            controller.start()
            defer { controller.stop() }
            controller.setDragging(true)
            XCTAssertEqual(presentations.map(\.opacity), [0.22, 0.22, 0.22])
            controller.setLanding(true, keepsNativeTilesVisible: true)
            XCTAssertEqual(presentations.map(\.opacity), [1, 1, 1])
            controller.setDragging(false)
            XCTAssertEqual(presentations.map(\.opacity), [1, 1, 1])
            controller.setLanding(false)
            XCTAssertEqual(presentations.map(\.opacity), [1, 1, 1])
            // Repair owns a separately drawn preview; insertion has no old
            // group to preserve. Both retain their ordinary replacement flow.
            controller.setLanding(true)
            XCTAssertEqual(presentations.map(\.opacity), [0, 0, 0])
            controller.setLanding(false)
            XCTAssertEqual(presentations.map(\.opacity), [1, 1, 1])
        }
    }

    @MainActor
    func testHidingAndReturningToTheEdgeRemoveEveryDockTile() throws {
        try withPreferences { preferences, _ in
            preferences.edge = .bottom
            preferences.horizontalPosition = 0.78
            preferences.isInSystemDock = true
            let store = ProfileStore(profile: .initial, saveProfile: { _ in })
            let edge = MacWidgetController(store: store, preferences: preferences, reducesMotion: { true })
            var visible: [MacSystemDockPresentation] = []
            let controller = MacSystemDockController(store: store, preferences: preferences,
                openSettings: {}, present: { visible = $0 })
            controller.start()
            XCTAssertEqual(visible.count, 3)
            XCTAssertFalse(edge.showsEdgeWidget)
            preferences.isVisible = false
            controller.refresh()
            XCTAssertTrue(visible.isEmpty)
            preferences.isVisible = true
            controller.refresh()
            XCTAssertEqual(visible.count, 3)
            controller.returnToEdge()
            XCTAssertTrue(visible.isEmpty)
            XCTAssertTrue(edge.showsEdgeWidget)
            XCTAssertEqual(preferences.edge, .right)
            XCTAssertEqual(preferences.horizontalPosition, 0.78)
            controller.stop()
        }
    }

    @MainActor
    func testRefreshRecalculatesTimeAndKeepsAllEightConfiguredMetrics() throws {
        try withPreferences { preferences, _ in
            var profile = UserProfile.initial
            profile.dashboardMetrics = MetricKind.allCases
            let store = ProfileStore(profile: profile, saveProfile: { _ in })
            preferences.isInSystemDock = true
            var visible: [MacSystemDockPresentation] = []
            let controller = MacSystemDockController(store: store, preferences: preferences,
                openSettings: {}, present: { visible = $0 })
            controller.start()
            let earlier = Date(timeIntervalSince1970: 1_790_000_000)
            controller.refresh(now: earlier)
            XCTAssertEqual(visible.map(\.snapshot.kind), MetricKind.allCases)
            let first = try XCTUnwrap(visible.first?.snapshot)
            controller.refresh(now: earlier.addingTimeInterval(3600))
            XCTAssertNotEqual(visible.first?.snapshot.remainingFraction, first.remainingFraction)
            controller.stop()
        }
    }

    @MainActor
    func testSelectingAnEdgeAutomaticallyJoinsOnlyTheDockSide() throws {
        for dockEdge in [MacWidgetEdge.left, .right, .bottom] {
            try withPreferences { preferences, _ in
                preferences.reconcileDockLocation(dockEdge)
                for edge in MacWidgetEdge.allCases {
                    preferences.edge = edge
                    XCTAssertEqual(preferences.isInSystemDock, edge == dockEdge)
                    preferences.reconcileDockLocation(dockEdge)
                    XCTAssertEqual(preferences.isInSystemDock, edge == dockEdge)
                }
                preferences.edge = dockEdge
                preferences.returnToScreenEdge()
                preferences.reconcileDockLocation(dockEdge)
                XCTAssertNotEqual(preferences.edge, dockEdge)
                XCTAssertFalse(preferences.isInSystemDock, "Returning or a failed launch must not immediately rejoin the Dock.")
            }
        }
    }

    @MainActor
    func testLegacyDockGroupMigratesOnceAndLaterLaunchesRespectTheSelectedEdge() throws {
        try withPreferences { preferences, defaults in
            preferences.edge = .top
            preferences.isInSystemDock = true
            preferences.verticalPosition = 0.23
            preferences.horizontalPosition = 0.78
            let migrated = MacWidgetPreferences(defaults: defaults, readDockPermission: { true })
            migrated.reconcileDockLocation(.left)
            XCTAssertTrue(migrated.isInSystemDock)
            XCTAssertEqual(migrated.edge, .left)
            XCTAssertEqual(migrated.verticalPosition, 0.23)
            XCTAssertEqual(migrated.horizontalPosition, 0.78)
            let relaunched = MacWidgetPreferences(defaults: defaults, readDockPermission: { true })
            relaunched.reconcileDockLocation(.bottom)
            XCTAssertEqual(relaunched.edge, .left)
            XCTAssertFalse(relaunched.isInSystemDock)
            relaunched.edge = .bottom
            XCTAssertTrue(relaunched.isInSystemDock)
        }
    }

    @MainActor
    func testSettingsAndDockMovesUpdateAllTilesWithoutChangingTheSelectedEdge() async throws {
        try await withPreferences { preferences, _ in
            var dockEdge = MacWidgetEdge.left
            var visible: [MacSystemDockPresentation] = []
            let dock = MacSystemDockController(store: ProfileStore(profile: .initial, saveProfile: { _ in }),
                preferences: preferences, openSettings: {}, readDockEdge: { dockEdge },
                present: { visible = $0 })
            dock.start()
            defer { dock.stop() }
            XCTAssertTrue(visible.isEmpty)
            preferences.edge = .left
            try await eventually { visible.count == 3 }
            dockEdge = .bottom
            dock.synchronizeLocation()
            try await eventually { visible.isEmpty }
            XCTAssertEqual(preferences.edge, .left)
            preferences.edge = .bottom
            try await eventually { visible.count == 3 }
            preferences.edge = .top
            try await eventually { visible.isEmpty }
        }
    }

    @MainActor
    func testLocationObservationCannotCommitOrInterruptAHeldPreview() throws {
        try withPreferences { preferences, _ in
            var dockEdge = MacWidgetEdge.left
            var interacting = false
            let dock = MacSystemDockController(store: ProfileStore(profile: .initial, saveProfile: { _ in }),
                preferences: preferences, openSettings: {}, readDockEdge: { dockEdge },
                isChangingPlacement: { interacting }, present: { _ in })
            dock.synchronizeLocation()
            XCTAssertFalse(preferences.isInSystemDock)
            interacting = true
            dockEdge = .right
            dock.synchronizeLocation()
            XCTAssertFalse(preferences.isInSystemDock)
            interacting = false
            dock.synchronizeLocation()
            XCTAssertTrue(preferences.isInSystemDock)
            XCTAssertEqual(preferences.edge, .right)
        }
    }

    @MainActor
    func testDockDropSavesItsActualEdgeAndRestoresTheSamePlacement() throws {
        try withPreferences { preferences, defaults in
            preferences.reconcileDockLocation(.bottom)
            let widget = MacWidgetController(store: ProfileStore(profile: .initial, saveProfile: { _ in }),
                                             preferences: preferences)
            let frame = NSRect(x: 100, y: 0, width: 240, height: 100)
            let target = MacWidgetDropTarget(edge: .bottom, position: 0.6, frame: frame, isSystemDock: true)
            widget.saveDrop(.init(frame: frame, position: 0.6, edge: .bottom, target: target))
            XCTAssertEqual(preferences.edge, .bottom)
            XCTAssertTrue(preferences.isInSystemDock)
            let restored = MacWidgetPreferences(defaults: defaults, readDockPermission: { true })
            restored.reconcileDockLocation(.bottom)
            XCTAssertEqual(restored.edge, .bottom)
            XCTAssertTrue(restored.isInSystemDock)
            restored.edge = .left
            XCTAssertFalse(restored.isInSystemDock)
        }
    }

    func testAutoHiddenDockOrientationAcceptsOnlyPhysicalDockSides() {
        for edge in [MacWidgetEdge.left, .right, .bottom] {
            XCTAssertEqual(MacSystemDockLocation.configuredEdge(orientation: edge.rawValue), edge)
        }
        for invalid in [nil, "", "top", "unknown"] {
            XCTAssertNil(MacSystemDockLocation.configuredEdge(orientation: invalid))
        }
    }

    @MainActor
    func testDockImagesHaveTransparentCornersAndSurviveThePipeMessage() throws {
        for kind in MetricKind.allCases {
            let snapshot = TimeProgressCalculator.snapshot(for: kind, profile: .initial,
                now: Date(timeIntervalSince1970: 1_790_000_000))
            let presentation = MacSystemDockPresentation(snapshot: snapshot,
                accent: MacWidgetStyle.accent(for: kind, theme: .vividNight))
            let renderer = ImageRenderer(content: MacSystemDockTileView(presentation: presentation))
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.cgImage)
            XCTAssertEqual(image.width, 256)
            XCTAssertEqual(image.height, 256)
            let bitmap = NSBitmapImageRep(cgImage: image)
            XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: 0, y: 0)).alphaComponent, 0)
            XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: 128, y: 128)).alphaComponent, 1)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let message = MacDockTileMessage(image: data, title: snapshot.title + "\n\"日本語\"",
                accessibilityLabel: snapshot.accessibilitySummary, groupTitle: "グループを開く", settingsTitle: "設定", returnTitle: "戻す", quitTitle: "終了")
            let encoded = try JSONEncoder().encode(message)
            XCTAssertFalse(encoded.contains(10), "Each update must stay on one line in the pipe.")
            let decoded = try JSONDecoder().decode(MacDockTileMessage.self, from: encoded)
            XCTAssertEqual(decoded.image, data)
            XCTAssertEqual(decoded.title, message.title)
            let attachment = XCTAttachment(image: NSImage(cgImage: image, size: NSSize(width: 128, height: 128)))
            attachment.name = "System Dock - \(kind.rawValue)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    func testHiddenDockImagesRemainFullyTransparentAfterTheHelperPNGRoundTrip() throws {
        for kind in MetricKind.allCases {
            let snapshot = TimeProgressCalculator.snapshot(for: kind, profile: .initial,
                now: Date(timeIntervalSince1970: 1_790_000_000))
            let presentation = MacSystemDockPresentation(snapshot: snapshot,
                accent: MacWidgetStyle.accent(for: kind, theme: .vividNight), opacity: 0)
            // Match the parent's renderer and PNG/message encoding, then use
            // the helper's NSImage decoder rather than inspecting only the
            // SwiftUI opacity property or the pre-encoding bitmap.
            let renderer = ImageRenderer(content: MacSystemDockTileView(presentation: presentation))
            renderer.scale = 2
            let rendered = try XCTUnwrap(renderer.cgImage)
            let png = try XCTUnwrap(NSBitmapImageRep(cgImage: rendered).representation(using: .png, properties: [:]))
            let message = MacDockTileMessage(image: png, title: snapshot.title,
                accessibilityLabel: snapshot.accessibilitySummary, groupTitle: "グループを開く",
                settingsTitle: "設定", returnTitle: "戻す", quitTitle: "終了")
            let decoded = try JSONDecoder().decode(MacDockTileMessage.self, from: JSONEncoder().encode(message))
            let helperImage = try XCTUnwrap(NSImage(data: decoded.image))
            let pixels = try XCTUnwrap(helperImage.cgImage(forProposedRect: nil, context: nil, hints: nil))
            XCTAssertEqual(pixels.width, 256)
            XCTAssertEqual(pixels.height, 256)
            let bitmap = NSBitmapImageRep(cgImage: pixels)
            XCTAssertTrue(bitmap.hasAlpha)
            let allTransparent = (0..<bitmap.pixelsHigh).allSatisfy { y in
                (0..<bitmap.pixelsWide).allSatisfy { x in
                    bitmap.colorAt(x: x, y: y)?.alphaComponent == 0
                }
            }
            XCTAssertTrue(allTransparent, "Hidden \(kind.rawValue) must contain no visible background, ring, or text pixels.")
        }
    }

    func testEveryMetricHasADistinctEmbeddedHelperApp() throws {
        var identifiers = Set<String>()
        for kind in MetricKind.allCases {
            let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/DaysYetDock_\(kind.rawValue).app")
            let bundle = try XCTUnwrap(Bundle(url: url))
            let identifier = try XCTUnwrap(bundle.bundleIdentifier)
            XCTAssertTrue(identifiers.insert(identifier).inserted)
            XCTAssertEqual(identifier, "com.hinoshiba.daysyet.dock.\(kind.rawValue)")
            XCTAssertEqual(bundle.object(forInfoDictionaryKey: "LSUIElement") as? Bool, true)
            XCTAssertTrue(FileManager.default.isExecutableFile(atPath: try XCTUnwrap(bundle.executablePath)))
        }
    }

    @MainActor
    private func withPreferences(_ body: (MacWidgetPreferences, UserDefaults) throws -> Void) throws {
        let suite = "com.hinoshiba.daysyet.system-dock.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(MacWidgetPreferences(defaults: defaults, readDockPermission: { true }), defaults)
    }

    @MainActor
    private func withPreferences(_ body: (MacWidgetPreferences, UserDefaults) async throws -> Void) async throws {
        let suite = "com.hinoshiba.daysyet.system-dock.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try await body(MacWidgetPreferences(defaults: defaults, readDockPermission: { true }), defaults)
    }

    @MainActor
    private func eventually(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition())
    }
}
