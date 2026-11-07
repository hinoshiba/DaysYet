import AppKit

/// Each configured timeline owns one standard Dock tile. It receives only its
/// rendered image and labels; no profile, dates or credentials are read here.
@MainActor
final class DockTileDelegate: NSObject, NSApplicationDelegate {
    private var message: MacDockTileMessage?
    private var buffer = Data()
    private var stopping = false
    private var parentMonitor: DispatchSourceProcess?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard fcntl(FileHandle.standardOutput.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
            shutdown()
            return
        }
        guard CommandLine.arguments.contains("--daysyet-dock-tile") else {
            shutdown()
            return
        }
        let parent = getppid()
        guard parent > 1 else { shutdown(); return }
        // EOF handles ordinary exit; this source also handles a crashed parent.
        let monitor = DispatchSource.makeProcessSource(identifier: parent, eventMask: .exit, queue: .main)
        monitor.setEventHandler { [weak self] in self?.shutdown() }
        monitor.resume()
        parentMonitor = monitor
        FileHandle.standardInput.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor in self?.receive(data) }
        }
    }

    private func receive(_ data: Data) {
        guard !stopping else { return }
        guard !data.isEmpty else { shutdown(); return }
        buffer.append(data)
        guard buffer.count < 2_000_000 else { shutdown(); return }
        while let newline = buffer.firstIndex(of: 10) {
            let line = buffer.prefix(upTo: newline)
            buffer.removeSubrange(...newline)
            guard let update = try? JSONDecoder().decode(MacDockTileMessage.self, from: line),
                  let image = NSImage(data: update.image) else { shutdown(); return }
            message = update
            let tile = NSApp.dockTile
            let view = NSImageView(frame: NSRect(origin: .zero, size: tile.size))
            view.image = image
            view.imageScaling = .scaleProportionallyUpOrDown
            view.autoresizingMask = [.width, .height]
            view.setAccessibilityLabel(update.accessibilityLabel)
            tile.contentView = view
            if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
            tile.display()
            if let revision = update.displayRevision {
                let line = MacDockTileDisplayState.acknowledgement(revision) + "\n"
                try? FileHandle.standardOutput.write(contentsOf: Data(line.utf8))
            }
        }
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        guard let message else { return nil }
        let menu = NSMenu()
        let title = NSMenuItem(title: message.title, action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        for (title, action) in [(message.groupTitle, MacDockTileAction.openGroup), (message.settingsTitle, .settings),
                                (message.returnTitle, .returnToEdge), (message.quitTitle, .quit)] {
            let item = NSMenuItem(title: title, action: #selector(performAction(_:)), keyEquivalent: "")
            item.representedObject = action.rawValue
            item.target = self
            menu.addItem(item)
        }
        return menu
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        send(.openGroup)
        return false
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if !stopping {
            send(.quit)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.shutdown() }
            return .terminateCancel
        }
        return .terminateNow
    }

    @objc private func performAction(_ item: NSMenuItem) {
        guard let rawValue = item.representedObject as? String, let action = MacDockTileAction(rawValue: rawValue) else { return }
        send(action)
    }

    private func send(_ action: MacDockTileAction) {
        try? FileHandle.standardOutput.write(contentsOf: Data((action.rawValue + "\n").utf8))
    }

    private func shutdown() {
        guard !stopping else { return }
        stopping = true
        FileHandle.standardInput.readabilityHandler = nil
        parentMonitor?.cancel()
        parentMonitor = nil
        // Remove transient helper tiles rather than leaving recent-app entries.
        NSApp.setActivationPolicy(.accessory)
        NSApp.terminate(nil)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = DockTileDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
