import AppKit

// An isolated capability probe, not a replacement for DaysYet's drag handling.
// Its six disposable apps have identities and paths distinct from DaysYet.
struct ProbeDockRecords {
    static let keys = ["persistent-apps", "recent-apps"]
    let appURL: URL

    func url(_ index: Int) -> URL {
        appURL.appendingPathComponent("Contents/Helpers/Group Test \(index + 1).app").resolvingSymlinksInPath()
    }

    func ownedIndex(_ entry: Any) -> Int? {
        guard let record = entry as? [String: Any], let data = record["tile-data"] as? [String: Any],
              let file = data["file-data"] as? [String: Any], let raw = file["_CFURLString"] as? String,
              let candidate = URL(string: raw), candidate.isFileURL,
              candidate.host == nil || candidate.host == "" || candidate.host == "localhost",
              candidate.user == nil, candidate.password == nil, candidate.query == nil, candidate.fragment == nil,
              let index = (0..<6).first(where: { url($0).standardizedFileURL.path == candidate.resolvingSymlinksInPath().standardizedFileURL.path }) else { return nil }
        if let identifier = data["bundle-identifier"],
           identifier as? String != "com.hinoshiba.daysyet.dock-group-move-probe.tile\(index + 1)" { return nil }
        return index
    }

    func positions(_ values: [String: [Any]]) -> [Int] {
        (values["persistent-apps"] ?? []).enumerated().compactMap { ownedIndex($0.element) == nil ? nil : $0.offset }
    }

    func isCompleteGroup(_ values: [String: [Any]]) -> Bool {
        let entries = values["persistent-apps"] ?? []
        let positions = positions(values)
        return positions.count == 6 && entries.compactMap(ownedIndex) == Array(0..<6)
            && positions.last! - positions.first! == 5
    }

    func removingOwned(_ values: [String: [Any]]) -> [String: [Any]] {
        values.mapValues { $0.filter { ownedIndex($0) == nil } }
    }

    func otherPaths(_ values: [String: [Any]]) -> [String] {
        (values["persistent-apps"] ?? []).filter { ownedIndex($0) == nil }.compactMap {
            (($0 as? [String: Any])?["tile-data"] as? [String: Any])?["file-data"] as? [String: Any]
        }.compactMap { $0["_CFURLString"] as? String }
    }

    static func read() -> [String: [Any]]? {
        let domain = "com.apple.dock" as CFString
        guard CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else { return nil }
        var values: [String: [Any]] = [:]
        for key in keys {
            let value = CFPreferencesCopyValue(key as CFString, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            guard value == nil || value is [Any] else { return nil }
            values[key] = (value as? [Any]) ?? []
        }
        return values
    }

    // Only closing the probe performs this cleanup. Dragging itself uses
    // AppKit's native drag session, with no Dock preference writes or reload.
    @MainActor
    func cleanup() -> Bool {
        guard let initial = Self.read() else { return false }
        let removed = initial.mapValues { $0.filter { ownedIndex($0) != nil } }
        guard removed.values.contains(where: { !$0.isEmpty }) else { return true }
        do {
            let folder = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/DaysYet/Dock Group Probe Recovery")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                   attributes: [.posixPermissions: 0o700])
            let backup = folder.appendingPathComponent("\(UUID().uuidString).plist")
            try PropertyListSerialization.data(fromPropertyList: removed, format: .binary, options: 0)
                .write(to: backup, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
        } catch { return false }
        guard let current = Self.read() else { return false }
        let updated = removingOwned(current)
        var changed: [String: [Any]] = [:]
        for key in Self.keys where (current[key]! as NSArray) != (updated[key]! as NSArray) { changed[key] = updated[key]! }
        guard !changed.isEmpty else { return true }
        let domain = "com.apple.dock" as CFString
        CFPreferencesSetMultiple(changed as CFDictionary, nil, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        guard CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else { return false }
        return NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
            .allSatisfy { $0.processIdentifier > 1 && Darwin.kill($0.processIdentifier, SIGTERM) == 0 }
    }
}

@MainActor
func probeIcon(_ index: Int, size: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        let colors: [NSColor] = [.systemTeal, .systemBlue, .systemPurple, .systemPink, .systemOrange, .systemGreen]
        NSColor(white: 0.08, alpha: 1).setFill()
        NSBezierPath(ovalIn: rect.insetBy(dx: size * 0.05, dy: size * 0.05)).fill()
        colors[index].setStroke()
        let ring = NSBezierPath(ovalIn: rect.insetBy(dx: size * 0.15, dy: size * 0.15))
        ring.lineWidth = size * 0.055
        ring.stroke()
        let text = "\(index + 1)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size * 0.36, weight: .semibold), .foregroundColor: NSColor.white]
        let textSize = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: (size - textSize.width) / 2, y: (size - textSize.height) / 2), withAttributes: attributes)
        return true
    }
}

@MainActor
final class ProbeSource: NSView, NSDraggingSource {
    let records = ProbeDockRecords(appURL: Bundle.main.bundleURL)
    var status: ((String) -> Void)?
    private var before: [String: [Any]]?
    private var press: NSPoint?
    private var generation = 0

    override func draw(_ dirtyRect: NSRect) {
        for index in 0..<6 { probeIcon(index, size: 56).draw(in: iconFrame(index)) }
    }
    private func iconFrame(_ index: Int) -> NSRect { NSRect(x: CGFloat(index) * 66, y: 5, width: 56, height: 56) }
    override func mouseDown(with event: NSEvent) { press = convert(event.locationInWindow, from: nil) }
    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let press, hypot(point.x - press.x, point.y - press.y) >= 4 else { return }
        self.press = nil
        before = ProbeDockRecords.read()
        generation += 1
        status?("6個をまとめてドラッグ中 — Dockのアプリ同士の隙間へ")
        let items = (0..<6).map { index in
            let item = NSDraggingItem(pasteboardWriter: records.url(index) as NSURL)
            item.setDraggingFrame(iconFrame(index), contents: probeIcon(index, size: 56))
            return item
        }
        let session = beginDraggingSession(with: items, event: event, source: self)
        session.draggingFormation = .none
        session.draggingLeaderIndex = min(5, max(0, Int(press.x / 66)))
        session.animatesToStartingPositionsOnCancelOrFail = true
    }
    override func mouseUp(with event: NSEvent) { press = nil }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        status?("Dockの結果を確認しています…")
        let token = generation
        // Dock persists its change asynchronously. These reads never reorder it.
        for delay in [0.4, 1.2, 2.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.generation == token else { return }
                self.report(operation: operation)
            }
        }
    }
    private func report(operation: NSDragOperation) {
        guard let before, let after = ProbeDockRecords.read() else { status?("Dockの結果を読み取れませんでした"); return }
        let count = records.positions(after).count
        guard records.otherPaths(before) == records.otherPaths(after) else {
            status?("他アプリの並びにも変更を検出 — この方式はまだ使えません")
            return
        }
        guard records.isCompleteGroup(after) else {
            status?("結果：\(count) / 6個を検出。6個の連続した塊にはなっていません。")
            return
        }
        if records.isCompleteGroup(before) {
            status?(records.positions(before) == records.positions(after)
                ? "結果：6個の位置は変わっていません。別の隙間でもう一度お試しください。"
                : "並べ替え成功：6個まとめて移動。他アプリの順番も維持されています。")
        } else {
            status?("追加成功：6個が連続しています。次は、この窓の丸をDockの別の隙間へ。")
        }
    }
}

@MainActor
final class ProbeDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 325),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "DaysYet — Dockの塊移動テスト"
        window.isReleasedWhenClosed = false
        window.delegate = self
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 580, height: 325))
        func label(_ text: String, rect: NSRect, size: CGFloat, color: NSColor = .labelColor) -> NSTextField {
            let label = NSTextField(wrappingLabelWithString: text)
            label.frame = rect
            label.font = .systemFont(ofSize: size)
            label.textColor = color
            content.addSubview(label)
            return label
        }
        _ = label("Dock内で、6個をまとめて並べ替えられるか確認", rect: NSRect(x: 24, y: 275, width: 532, height: 28), size: 19)
        _ = label("① この丸をDockの隙間へドラッグ。\n② 同じ丸を、この窓からDockの別の隙間へもう一度ドラッグ。", rect: NSRect(x: 24, y: 214, width: 532, height: 46), size: 14)
        let source = ProbeSource(frame: NSRect(x: 96, y: 132, width: 396, height: 66))
        source.setAccessibilityElement(true)
        source.setAccessibilityRole(.group)
        source.setAccessibilityLabel("Dock移動テスト：6個の丸をまとめてドラッグ")
        content.addSubview(source)
        let status = label("この窓の、どの丸からでも始められます。", rect: NSRect(x: 24, y: 65, width: 532, height: 52), size: 15)
        source.status = { [weak status] in status?.stringValue = $0 }
        _ = label("テスト専用の6項目です。閉じると除去し、Dockを一度再表示します。", rect: NSRect(x: 24, y: 20, width: 532, height: 30), size: 12, color: .secondaryLabelColor)
        window.contentView = content
        window.center()
        self.window = window
        let menu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "テストを終了して片付ける", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let item = NSMenuItem(); item.submenu = appMenu; menu.addItem(item); NSApp.mainMenu = menu
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { NSApp.terminate(nil); return false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard ProbeDockRecords(appURL: Bundle.main.bundleURL).cleanup() else {
            let alert = NSAlert()
            alert.messageText = "テスト用アイコンを片付けられませんでした"
            alert.informativeText = "Dockから番号1〜6のテスト項目を取り除いてから、もう一度終了してください。"
            alert.runModal()
            return .terminateCancel
        }
        return .terminateNow
    }
}

func selfTest() {
    let fixture = URL(fileURLWithPath: "/tmp").appendingPathComponent("daysyet-group-probe-test-\(UUID().uuidString).app")
    for index in 1...6 {
        try! FileManager.default.createDirectory(at: fixture.appendingPathComponent("Contents/Helpers/Group Test \(index).app"), withIntermediateDirectories: true)
    }
    defer { try? FileManager.default.removeItem(at: fixture) }
    let records = ProbeDockRecords(appURL: fixture)
    func item(_ url: URL, identifier: String? = nil) -> [String: Any] {
        var data: [String: Any] = ["file-data": ["_CFURLString": url.absoluteString]]
        if let identifier { data["bundle-identifier"] = identifier }
        return ["tile-data": data]
    }
    let group = (0..<6).map { item(records.url($0)) }
    let foreign = item(URL(fileURLWithPath: "/Applications/Another.app"))
    let complete: [String: [Any]] = ["persistent-apps": [foreign] + group, "recent-apps": [group[0], foreign]]
    precondition(records.isCompleteGroup(complete))
    precondition(!records.isCompleteGroup(["persistent-apps": Array(group.prefix(3)) + [foreign] + Array(group.suffix(3))]))
    precondition(!records.isCompleteGroup(["persistent-apps": Array(repeating: group[0], count: 6)]))
    precondition(!records.isCompleteGroup(["persistent-apps": Array(group.reversed())]))
    precondition(records.ownedIndex(item(records.url(0), identifier: "another.app")) == nil)
    let alias = URL(fileURLWithPath: "/private/tmp").appendingPathComponent(fixture.lastPathComponent)
        .appendingPathComponent("Contents/Helpers/Group Test 1.app")
    precondition(records.ownedIndex(item(alias)) == 0)
    precondition(records.ownedIndex(item(URL(fileURLWithPath: "/different/Probe.app/Contents/Helpers/Group Test 1.app"))) == nil)
    precondition(records.ownedIndex(item(URL(string: "file://remote/tmp/Probe.app/Contents/Helpers/Group%20Test%201.app")!)) == nil)
    precondition(records.ownedIndex(item(records.url(0).appending(queryItems: [.init(name: "x", value: "1")]))) == nil)
    let cleaned = records.removingOwned(complete)
    precondition((cleaned["persistent-apps"]! as NSArray) == ([foreign] as NSArray))
    precondition((cleaned["recent-apps"]! as NSArray) == ([foreign] as NSArray))
    precondition(records.otherPaths(complete) == records.otherPaths(cleaned))
    print("Probe checks passed: group detection, duplicates, exact ownership and unrelated-entry preservation.")
}

try MainActor.assumeIsolated {
if CommandLine.arguments.contains("--self-test") {
    selfTest()
} else if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--render-icons" {
    let folder = URL(fileURLWithPath: CommandLine.arguments[2])
    for index in 0..<6 {
        let iconset = folder.appendingPathComponent("tile\(index + 1).iconset")
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        for size in [16, 32, 128, 256, 512] {
            let icon = probeIcon(index, size: CGFloat(size))
            let data = NSBitmapImageRep(data: icon.tiffRepresentation!)!.representation(using: .png, properties: [:])!
            try data.write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
        }
    }
} else if Bundle.main.bundleIdentifier?.hasPrefix("com.hinoshiba.daysyet.dock-group-move-probe.tile") == true {
    // The test apps only reserve disposable Dock items. Opening one does nothing.
    exit(0)
} else {
    let app = NSApplication.shared
    let delegate = ProbeDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
}
