import AppKit

/// A visible, isolated receiver for testing the public drag protocol used by
/// Dock application icons. It never opens, copies or moves a dropped file.
@MainActor
final class DockDragProbeView: NSView {
    private let status = NSTextField(wrappingLabelWithString: "DockのDaysYetの丸を、ここへドラッグしてください。")
    private let detail = NSTextField(wrappingLabelWithString: "テスト用の受け取り窓です。通常のファイルは受け取りません。")
    private var entered = false
    private var acceptedOperation: NSDragOperation = []
    private let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("daysyet-dock-drag-probe-events.jsonl")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        registerForDraggedTypes([.fileURL, .URL, .string, NSPasteboard.PasteboardType("public.data"),
                                 NSPasteboard.PasteboardType("NSFilenamesPboardType")])
        let source = ProbeDragSource(frame: NSRect(x: 24, y: frame.height - 76, width: 48, height: 48))
        source.image = Self.icon
        source.imageScaling = .scaleProportionallyUpOrDown
        source.setAccessibilityLabel("比較用の通常ドラッグ")
        addSubview(source)
        let sourceLabel = NSTextField(labelWithString: "比較用：この丸から中央へドラッグ")
        sourceLabel.frame = NSRect(x: 90, y: frame.height - 58, width: 320, height: 24)
        sourceLabel.font = .systemFont(ofSize: 13)
        addSubview(sourceLabel)
        status.font = .systemFont(ofSize: 21, weight: .semibold)
        status.alignment = .center
        detail.font = .systemFont(ofSize: 13)
        detail.alignment = .center
        detail.textColor = .secondaryLabelColor
        for label in [status, detail] {
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
        }
        NSLayoutConstraint.activate([
            status.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            status.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            status.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 20),
            detail.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            detail.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            detail.topAnchor.constraint(equalTo: status.bottomAnchor, constant: 20)
        ])
        record("ready", [:])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        if let source = subviews.first(where: { $0 is ProbeDragSource && $0.frame.contains(local) }) { return source }
        return self
    }

    private func matches(_ sender: NSDraggingInfo) -> Bool {
        let roots = [Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL.path] + ["week", "month", "year", "healthyLife", "customLife", "activity", "workday", "study"].map {
            "/Applications/DaysYet.app/Contents/Helpers/DaysYetDock_\($0).app"
        }
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL], urls.count == 1 else { return false }
        return roots.contains(urls[0].resolvingSymlinksInPath().standardizedFileURL.path)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        entered = true
        let own = matches(sender)
        let allowed = sender.draggingSourceOperationMask
        acceptedOperation = [.generic, .copy, .link].first(where: { allowed.contains($0) }) ?? []
        let types = sender.draggingPasteboard.types?.map(\.rawValue) ?? []
        record("entered", ["ownItem": own, "types": types, "sourceOperations": allowed.rawValue,
                           "selectedOperation": acceptedOperation.rawValue, "localSource": sender.draggingSource != nil])
        status.stringValue = own ? "DaysYetの丸を受信しました" : "別の項目です（受け取りません）"
        detail.stringValue = own ? "ここで離すと、受け取りの成否を表示します。" : "このウインドウの外へ戻してください。"
        layer?.backgroundColor = (own ? NSColor.systemBlue.withAlphaComponent(0.15) : NSColor.windowBackgroundColor).cgColor
        return own ? acceptedOperation : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        matches(sender) ? acceptedOperation : []
    }

    override func updateDraggingItemsForDrag(_ sender: NSDraggingInfo?) {
        guard let sender, matches(sender) else { return }
        var changed = 0
        sender.enumerateDraggingItems(options: [], for: self, classes: [NSURL.self], searchOptions: [.urlReadingFileURLsOnly: true]) { item, _, _ in
            let pointer = self.convert(sender.draggingLocation, from: nil)
            item.setDraggingFrame(NSRect(x: pointer.x - 20, y: pointer.y - 20, width: 40, height: 40), contents: Self.icon)
            changed += 1
        }
        record("imageUpdated", ["count": changed])
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let own = matches(sender)
        record("prepare", ["ownItem": own, "operation": acceptedOperation.rawValue])
        return own && !acceptedOperation.isEmpty
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard matches(sender), !acceptedOperation.isEmpty else { return false }
        status.stringValue = sender.draggingSource == nil ? "成功：外部から直接受け取れました" : "成功：比較用の通常ドラッグを受信"
        detail.stringValue = "公開のドラッグAPIで、DaysYetの項目を識別できました。"
        layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.18).cgColor
        record("accepted", ["sequence": sender.draggingSequenceNumber, "localSource": sender.draggingSource != nil])
        return true
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        status.stringValue = "領域から出ました（未確定）"
        detail.stringValue = "もう一度、Dockの丸をこのウインドウへドラッグできます。"
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        record("exited", [:])
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        record("ended", ["hadEntered": entered])
        entered = false
    }

    private func record(_ phase: String, _ values: [String: Any]) {
        var data = values
        data["phase"] = phase
        data["time"] = Date().timeIntervalSince1970
        guard var bytes = try? JSONSerialization.data(withJSONObject: data, options: [.sortedKeys]) else { return }
        bytes.append(10)
        if !FileManager.default.fileExists(atPath: logURL.path) { FileManager.default.createFile(atPath: logURL.path, contents: nil) }
        guard let file = try? FileHandle(forWritingTo: logURL) else { return }
        defer { try? file.close() }
        _ = try? file.seekToEnd()
        try? file.write(contentsOf: bytes)
    }

    static var icon: NSImage {
        NSImage(size: NSSize(width: 128, height: 128), flipped: false) { _ in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: 8, y: 8, width: 112, height: 112)).fill()
            NSColor.systemTeal.setStroke()
            let ring = NSBezierPath(ovalIn: NSRect(x: 18, y: 18, width: 92, height: 92))
            ring.lineWidth = 5
            ring.stroke()
            let text = "TEST" as NSString
            text.draw(in: NSRect(x: 20, y: 49, width: 88, height: 32), withAttributes: [.font: NSFont.systemFont(ofSize: 26, weight: .semibold), .foregroundColor: NSColor.white])
            return true
        }
    }
}

@MainActor
final class ProbeDragSource: NSImageView, NSDraggingSource {
    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: Bundle.main.bundleURL as NSURL)
        item.setDraggingFrame(bounds, contents: DockDragProbeView.icon)
        beginDraggingSession(with: [item], event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
}

@MainActor
final class ProbeDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let applicationMenu = NSMenu()
        applicationMenu.addItem(withTitle: "Quit Dock Drag Probe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let item = NSMenuItem()
        item.submenu = applicationMenu
        menu.addItem(item)
        NSApp.mainMenu = menu
        NSApp.applicationIconImage = DockDragProbeView.icon
        let tileView = NSImageView(frame: NSRect(origin: .zero, size: NSApp.dockTile.size))
        tileView.image = DockDragProbeView.icon
        tileView.imageScaling = .scaleProportionallyUpOrDown
        NSApp.dockTile.contentView = tileView
        NSApp.setActivationPolicy(.regular)
        NSApp.dockTile.display()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 320),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "DaysYet — Dock Drag Probe"
        window.contentView = DockDragProbeView(frame: NSRect(x: 0, y: 0, width: 440, height: 320))
        window.center()
        window.isReleasedWhenClosed = false
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window?.makeKeyAndOrderFront(nil)
        return false
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = ProbeDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
