import AppKit
import SwiftUI

@MainActor
final class MacAppModel {
    static let shared = MacAppModel()
    let store = ProfileStore()
    let preferences: MacWidgetPreferences
    private let setupDefaults: UserDefaults
    private let screenshotPreferencesSuite: String?
    lazy var controller = MacWidgetController(store: store, preferences: preferences)
    lazy var dockController = MacSystemDockController(store: store, preferences: preferences,
        openSettings: { [weak self] in self?.controller.showSettings() },
        openGroup: { [weak self] in self?.controller.showDockGroup() },
        readDockEdge: { [weak self] in self?.controller.currentSystemDockEdge },
        isChangingPlacement: { [weak self] in self?.controller.isChangingPlacement ?? false },
        accessRevoked: { [weak self] in self?.controller.abortDockPlacement() })
#if DAYSYET_DIRECT_DOCK_DRAG
    lazy var directDockController = MacDockDirectDragController(store: store, preferences: preferences,
        widget: controller, dock: dockController)
#if DAYSYET_DOCK_NATIVE_REORDER && DAYSYET_DOCK_REORDER_PROBE
    lazy var nativeMoveProbe = MacDockNativeMoveProbe()
#endif
#endif
    lazy var setupController: MacSetupController = {
#if DAYSYET_DIRECT_DOCK_DRAG
        let access = MacSetupDockAccess(
            isGranted: { [weak self] in self?.directDockController.refreshAccessibility() ?? false },
            openSettings: { [weak self] in self?.directDockController.openAccessibilitySettings() },
            enableDragging: { [weak self] in _ = self?.directDockController.refreshAccessibility() })
        return MacSetupController(defaults: setupDefaults, dockAccess: access)
#else
        return MacSetupController(defaults: setupDefaults)
#endif
    }()

    private init() {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--screenshot-mode") {
            // Isolate panel edits during UI review from the user's preferences.
            let suite = "com.hinoshiba.daysyet.screenshots.\(UUID().uuidString)"
            guard let defaults = UserDefaults(suiteName: suite) else {
                preconditionFailure("Could not create isolated screenshot preferences")
            }
            screenshotPreferencesSuite = suite
            setupDefaults = defaults
            preferences = MacWidgetPreferences(defaults: defaults)
            return
        }
#endif
        screenshotPreferencesSuite = nil
        setupDefaults = .standard
        preferences = MacWidgetPreferences()
    }

    func removeScreenshotPreferences() {
        if let suite = screenshotPreferencesSuite {
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
    }
}

@MainActor
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hosted unit tests must not create panels or change the desktop.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              NSClassFromString("XCTestCase") == nil else { return }
        let model = MacAppModel.shared
        model.dockController.synchronizeLocation()
        model.controller.start()
        model.controller.systemDockLandingChanged = { [weak model] landing in
            guard let model else { return }
            model.dockController.setLanding(landing,
                keepsNativeTilesVisible: model.controller.dragOrigin?.isSystemDock == true)
        }
        model.controller.systemDockDisplayReady = { [weak model] in await model?.dockController.waitForDisplay() ?? false }
        model.dockController.start()
#if DAYSYET_DIRECT_DOCK_DRAG
        model.controller.directDockDrag = model.directDockController
        model.directDockController.start()
#endif
        model.controller.setupController = model.setupController
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--screenshot-mode") {
            if arguments.contains("--screenshot-study-days") { model.controller.showSettings() }
            return
        }
#endif
#if DAYSYET_DIRECT_DOCK_DRAG && DAYSYET_DOCK_NATIVE_REORDER && DAYSYET_DOCK_REORDER_PROBE
        if MacDockRegistrationCleanup.nativeURLProbePending {
            MacDockNativeURLDragProbe.show()
            return
        }
#endif
        if !model.setupController.showIfNeeded(), !model.preferences.isVisible {
            model.controller.showSettings()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
#if DAYSYET_DIRECT_DOCK_DRAG && DAYSYET_DOCK_NATIVE_REORDER && DAYSYET_DOCK_REORDER_PROBE
        return MacDockNativeURLDragProbe.requestApplicationTermination()
#else
        return .terminateNow
#endif
    }

    func applicationWillTerminate(_ notification: Notification) {
#if DAYSYET_DIRECT_DOCK_DRAG
        MacAppModel.shared.directDockController.stop()
#endif
        MacAppModel.shared.dockController.stop()
        MacAppModel.shared.removeScreenshotPreferences()
    }

    // The resident panel owns startup; settings are opened explicitly.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let model = MacAppModel.shared
        if model.setupController.isVisible { model.setupController.show() }
        else { model.controller.showSettings() }
        return false
    }
}

@main
struct DaysYetMacApp: App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(L10n.text("設定…", "Settings…")) {
                    MacAppModel.shared.controller.showSettings()
                }
                .keyboardShortcut(",")
#if DAYSYET_DIRECT_DOCK_DRAG && DAYSYET_DOCK_NATIVE_REORDER && DAYSYET_DOCK_REORDER_PROBE
                Button("Dock並べ替えの試作…") { MacAppModel.shared.nativeMoveProbe.show() }
                    .keyboardShortcut("d", modifiers: [.command, .option])
                Button("Dock一括ドラッグの検証…") { MacDockNativeURLDragProbe.show() }
                    .keyboardShortcut("u", modifiers: [.command, .option])
#endif
            }
        }
    }
}
