import AppKit
import SwiftUI

@MainActor
final class MacAppModel {
    static let shared = MacAppModel()
    let store = ProfileStore()
    let preferences: MacWidgetPreferences
    private let screenshotPreferencesSuite: String?
    lazy var controller = MacWidgetController(store: store, preferences: preferences)

    private init() {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--screenshot-mode") {
            // Isolate panel edits during UI review from the user's preferences.
            let suite = "com.hinoshiba.daysyet.screenshots.\(UUID().uuidString)"
            guard let defaults = UserDefaults(suiteName: suite) else {
                preconditionFailure("Could not create isolated screenshot preferences")
            }
            screenshotPreferencesSuite = suite
            preferences = MacWidgetPreferences(defaults: defaults)
            return
        }
#endif
        screenshotPreferencesSuite = nil
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
        model.controller.start()
        if !model.preferences.isVisible { model.controller.showSettings() }
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--screenshot-mode") && arguments.contains("--screenshot-study-days") {
            model.controller.showSettings()
        }
#endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        MacAppModel.shared.removeScreenshotPreferences()
    }

    // The resident panel owns startup; settings are opened explicitly.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MacAppModel.shared.controller.showSettings()
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
            }
        }
    }
}
