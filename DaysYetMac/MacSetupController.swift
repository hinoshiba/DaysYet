import AppKit
import Combine
import SwiftUI

/// The ordinary build has no Dock access capability and never requests AX permission.
@MainActor
struct MacSetupDockAccess {
    let isGranted: () -> Bool
    let openSettings: () -> Void
    let enableDragging: () -> Void
}

@MainActor
final class MacSetupController: NSObject, ObservableObject, NSWindowDelegate {
    enum Step: String { case startup, movement }
    private enum Key {
        static let completedVersion = "mac-setup-completed-version"
        static let step = "mac-setup-step"
    }
    private static let version = 1

    @Published private(set) var step: Step
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var hasOpenedAccessibilitySettings = false
    let loginItem: MacLoginItemSettings
    private let defaults: UserDefaults
    private let dockAccess: MacSetupDockAccess?
    private var window: NSWindow?
    private var refreshTimer: Timer?

    var offersDirectDockDrag: Bool { dockAccess != nil }
    var needsSetup: Bool { defaults.integer(forKey: Key.completedVersion) < Self.version }
    var isVisible: Bool { window?.isVisible == true }

    init(defaults: UserDefaults = .standard, loginItem: MacLoginItemSettings? = nil,
         dockAccess: MacSetupDockAccess? = nil) {
        self.defaults = defaults
        self.loginItem = loginItem ?? MacLoginItemSettings()
        self.dockAccess = dockAccess
        step = Step(rawValue: defaults.string(forKey: Key.step) ?? "") ?? .startup
        super.init()
        refresh()
    }

    @discardableResult
    func showIfNeeded() -> Bool {
        guard needsSetup else { return false }
        show()
        return true
    }

    func show(startingAt requestedStep: Step? = nil) {
        if let requestedStep { go(to: requestedStep) }
        refresh()
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 740, height: 650),
                                  styleMask: [.titled, .closable, .miniaturizable],
                                  backing: .buffered, defer: false)
            window.title = L10n.text("DaysYet — はじめの設定", "DaysYet — Get started")
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: MacSetupView(setup: self, loginItem: loginItem))
            window.center()
            self.window = window
        }
        refreshTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
        NSApp.activate(ignoringOtherApps: true)
        window?.deminiaturize(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func go(to step: Step) {
        self.step = step
        // Reopening a completed guide should not turn it into a new first run.
        if needsSetup { defaults.set(step.rawValue, forKey: Key.step) }
        refresh()
    }

    func refresh() {
        loginItem.refresh()
        let granted = dockAccess?.isGranted() ?? false
        if accessibilityGranted != granted { accessibilityGranted = granted }
    }

    func openAccessibilitySettings() {
        guard let dockAccess else { return }
        hasOpenedAccessibilitySettings = true
        dockAccess.openSettings()
        // A request is not a grant. Only the OS status can enable the finish action.
        refresh()
    }

    func finishEnablingDockDrag() {
        refresh()
        guard accessibilityGranted, let dockAccess else { return }
        dockAccess.enableDragging()
        finish()
    }

    func finish() {
        defaults.set(Self.version, forKey: Key.completedVersion)
        defaults.removeObject(forKey: Key.step)
        refreshTimer?.invalidate()
        refreshTimer = nil
        window?.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) { finish() }

    func resetCompletion() {
        defaults.removeObject(forKey: Key.completedVersion)
        defaults.removeObject(forKey: Key.step)
        step = .startup
        hasOpenedAccessibilitySettings = false
    }
}
