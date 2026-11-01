import AppKit
import ServiceManagement
import SwiftUI
import XCTest
@testable import DaysYetMac

@MainActor
final class MacSetupTests: XCTestCase {
    func testFirstRunResumesAfterStartupAndCompletionDoesNotRepeat() throws {
        let fixture = try SetupFixture()
        let setup = fixture.makeSetup()
        XCTAssertTrue(setup.needsSetup)
        XCTAssertEqual(setup.step, .startup)
        setup.go(to: .movement)
        XCTAssertEqual(fixture.makeSetup().step, .movement)
        setup.finish()
        let nextLaunch = fixture.makeSetup()
        XCTAssertFalse(nextLaunch.needsSetup)
        XCTAssertFalse(nextLaunch.showIfNeeded())
        XCTAssertEqual(nextLaunch.step, .startup)
        // Reviewing the tutorial later must not cause another first-run prompt.
        nextLaunch.go(to: .movement)
        XCTAssertFalse(fixture.makeSetup().needsSetup)
        nextLaunch.resetCompletion()
        XCTAssertTrue(fixture.makeSetup().needsSetup)
        XCTAssertEqual(fixture.makeSetup().step, .startup)
    }

    func testShowingAndSkippingTheGuideCannotChangeSystemSettings() throws {
        let fixture = try SetupFixture()
        let setup = fixture.makeSetup()
        setup.refresh()
        setup.go(to: .movement)
        setup.finish()
        XCTAssertEqual(fixture.permissionRequests, 0)
        XCTAssertEqual(fixture.enableDragCalls, 0)
        XCTAssertEqual(fixture.loginChanges, 0)
        XCTAssertEqual(fixture.loginSettingsOpened, 0)
        XCTAssertFalse(setup.needsSetup)
    }

    func testRequestWaitsForActualPermissionAndCompletionEnablesOnlyAfterGrant() throws {
        let fixture = try SetupFixture()
        let setup = fixture.makeSetup()
        setup.go(to: .movement)
        setup.openAccessibilitySettings()
        XCTAssertEqual(fixture.permissionRequests, 1)
        XCTAssertTrue(setup.hasOpenedAccessibilitySettings)
        XCTAssertFalse(setup.accessibilityGranted)
        setup.finishEnablingDockDrag()
        XCTAssertTrue(setup.needsSetup)
        XCTAssertEqual(fixture.enableDragCalls, 0)

        fixture.granted = true
        setup.refresh()
        XCTAssertTrue(setup.accessibilityGranted)
        XCTAssertEqual(fixture.enableDragCalls, 0, "Returning from Settings does not opt in automatically.")
        setup.finishEnablingDockDrag()
        XCTAssertEqual(fixture.enableDragCalls, 1)
        XCTAssertFalse(setup.needsSetup)
        XCTAssertEqual(fixture.loginChanges, 0)
    }

    func testRevokedPermissionIsRecheckedBeforeEnabling() throws {
        let fixture = try SetupFixture()
        fixture.granted = true
        let setup = fixture.makeSetup()
        XCTAssertTrue(setup.accessibilityGranted)
        fixture.granted = false
        setup.finishEnablingDockDrag()
        XCTAssertFalse(setup.accessibilityGranted)
        XCTAssertTrue(setup.needsSetup)
        XCTAssertEqual(fixture.enableDragCalls, 0)
    }

    func testClosingIsAnOptionalSkipAndStandardBuildNeedsNoPermission() throws {
        let fixture = try SetupFixture()
        let setup = fixture.makeSetup(direct: false)
        XCTAssertFalse(setup.offersDirectDockDrag)
        setup.go(to: .movement)
        setup.openAccessibilitySettings()
        XCTAssertFalse(setup.hasOpenedAccessibilitySettings)
        XCTAssertFalse(setup.accessibilityGranted)
        XCTAssertEqual(fixture.permissionRequests, 0)
        setup.windowWillClose(Notification(name: NSWindow.willCloseNotification))
        XCTAssertFalse(fixture.makeSetup(direct: false).needsSetup)
        XCTAssertEqual(fixture.enableDragCalls, 0)
    }

    func testGuideRefreshesLaunchAtLoginFromTheSystem() throws {
        let fixture = try SetupFixture()
        let setup = fixture.makeSetup()
        XCTAssertFalse(setup.loginItem.isEnabled)
        fixture.loginStatus = .requiresApproval
        setup.refresh()
        XCTAssertTrue(setup.loginItem.requiresApproval)
        fixture.loginStatus = .enabled
        setup.refresh()
        XCTAssertTrue(setup.loginItem.isEnabled)
        setup.loginItem.setEnabled(false)
        XCTAssertFalse(setup.loginItem.isEnabled)
        XCTAssertEqual(fixture.loginChanges, 1)
    }

    func testSetupScreensRenderInBothLanguages() async throws {
        let fixture = try SetupFixture()
        for japanese in [true, false] {
            for state in ["startup", "approval", "unavailable", "permission", "waiting", "granted", "standard", "dark"] {
                fixture.loginStatus = state == "approval" ? .requiresApproval
                    : state == "unavailable" ? .notFound : .notRegistered
                fixture.granted = state == "granted"
                let setup = fixture.makeSetup(direct: state != "standard")
                setup.go(to: ["startup", "approval", "unavailable"].contains(state) ? .startup : .movement)
                if state == "waiting" { setup.openAccessibilitySettings() }
                let view = MacSetupView(setup: setup, loginItem: setup.loginItem, isJapanese: japanese)
                    .environment(\.colorScheme, state == "dark" ? .dark : .light)
                let host = NSHostingView(rootView: view)
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 740, height: 650),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = host
                defer { window.contentView = nil; window.close() }
                host.frame = NSRect(x: 0, y: 0, width: 740, height: 650)
                host.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let image = NSImage(size: host.bounds.size)
                image.addRepresentation(bitmap)
                let attachment = XCTAttachment(image: image)
                attachment.name = "Setup-\(japanese ? "ja" : "en")-\(state)"
                attachment.lifetime = .keepAlways
                add(attachment)
                XCTAssertEqual(host.bounds.size, NSSize(width: 740, height: 650))
            }
        }
    }
}

/// No real service registration, permission prompts, or user preferences in tests.
@MainActor
private final class SetupFixture {
    let suite: String
    let defaults: UserDefaults
    var granted = false
    var permissionRequests = 0
    var enableDragCalls = 0
    var loginChanges = 0
    var loginSettingsOpened = 0
    var loginStatus = SMAppService.Status.notRegistered

    init() throws {
        suite = "com.hinoshiba.daysyet.setup.tests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    deinit { defaults.removePersistentDomain(forName: suite) }

    func makeSetup(direct: Bool = true) -> MacSetupController {
        let login = MacLoginItemSettings(readStatus: { self.loginStatus }, register: {
            self.loginChanges += 1
            self.loginStatus = .enabled
        }, unregister: {
            self.loginChanges += 1
            self.loginStatus = .notRegistered
        }, openSystemSettings: { self.loginSettingsOpened += 1 })
        let access = direct ? MacSetupDockAccess(isGranted: { self.granted },
                                               openSettings: { self.permissionRequests += 1 },
                                               enableDragging: { self.enableDragCalls += 1 }) : nil
        return MacSetupController(defaults: defaults, loginItem: login, dockAccess: access)
    }
}
