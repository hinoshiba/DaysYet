import AppKit
import SwiftUI

@MainActor
final class MacDockTileProcessHost {
    private var tiles: [MetricKind: MacDockTileProcess] = [:]
    private let action: (MacDockTileAction) -> Void
    private let failed: () -> Void

    init(action: @escaping (MacDockTileAction) -> Void, failed: @escaping () -> Void) {
        self.action = action
        self.failed = failed
    }

    func update(_ presentations: [MacSystemDockPresentation]) throws {
        let kinds = Set(presentations.map { $0.snapshot.kind })
        for kind in Array(tiles.keys) where !kinds.contains(kind) {
            tiles.removeValue(forKey: kind)?.stop()
        }
        for presentation in presentations {
            let kind = presentation.snapshot.kind
            let tile: MacDockTileProcess
            if let existing = tiles[kind] {
                tile = existing
            } else {
                let bundle = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/DaysYetDock_\(kind.rawValue).app")
                guard let executable = Bundle(url: bundle)?.executableURL else { throw CocoaError(.fileNoSuchFile) }
                tile = try MacDockTileProcess(executable: executable, action: action, failed: failed)
                tiles[kind] = tile
            }
            try tile.update(presentation)
        }
    }

    func stop() {
        for tile in tiles.values { tile.stop() }
        tiles.removeAll()
    }
}

@MainActor
private final class MacDockTileProcess {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var outputBuffer = Data()
    private var stopped = false
    private let action: (MacDockTileAction) -> Void
    private let failed: () -> Void

    init(executable: URL, action: @escaping (MacDockTileAction) -> Void, failed: @escaping () -> Void) throws {
        self.action = action
        self.failed = failed
        process.executableURL = executable
        process.arguments = ["--daysyet-dock-tile"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            Task { @MainActor in self?.receive(data) }
        }
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.stopped else { return }
                self.failed()
            }
        }
        do {
            try process.run()
        } catch {
            stop()
            throw error
        }
        // The parent must not retain its own copy of the child's pipe ends.
        try? input.fileHandleForReading.close()
        try? output.fileHandleForWriting.close()
    }

    func update(_ presentation: MacSystemDockPresentation) throws {
        let renderer = ImageRenderer(content: MacSystemDockTileView(presentation: presentation))
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let message = MacDockTileMessage(image: data,
            title: "\(presentation.snapshot.title) — \(presentation.snapshot.percentageText)",
            accessibilityLabel: presentation.snapshot.accessibilitySummary,
            groupTitle: L10n.text("グループを開く", "Open group"),
            settingsTitle: L10n.text("DaysYetの設定…", "DaysYet Settings…"),
            returnTitle: L10n.text("画面の端に戻す", "Return to screen edge"),
            quitTitle: L10n.text("DaysYetを終了", "Quit DaysYet"))
        var encoded = try JSONEncoder().encode(message)
        encoded.append(10)
        try input.fileHandleForWriting.write(contentsOf: encoded)
    }

    private func receive(_ data: Data) {
        guard !stopped, !data.isEmpty else { return }
        outputBuffer.append(data)
        guard outputBuffer.count < 4096 else { failed(); return }
        while let newline = outputBuffer.firstIndex(of: 10) {
            let line = String(data: outputBuffer.prefix(upTo: newline), encoding: .utf8)
            outputBuffer.removeSubrange(...newline)
            if let line, let command = MacDockTileAction(rawValue: line) { action(command) }
        }
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        process.terminationHandler = nil
        output.fileHandleForReading.readabilityHandler = nil
        // EOF asks the helper to remove its Dock tile and quit normally.
        try? input.fileHandleForWriting.close()
        try? output.fileHandleForReading.close()
        let process = process
        Task {
            try? await Task.sleep(for: .seconds(2))
            if process.isRunning { process.terminate() }
        }
    }
}
