import Foundation

/// Sent only over the anonymous pipe inherited by a DaysYet-owned helper.
struct MacDockTileMessage: Codable {
    let image: Data
    let title: String
    let accessibilityLabel: String
    let groupTitle: String
    let settingsTitle: String
    let returnTitle: String
    let quitTitle: String
    var displayRevision: UInt64? = nil
}

/// An acknowledgement confirms the helper called display() for this revision.
/// It is not a WindowServer fence; callers still allow a display update to land.
struct MacDockTileDisplayState {
    private(set) var sent: UInt64 = 0
    private(set) var displayed: UInt64 = 0
    var isCurrent: Bool { sent > 0 && displayed == sent }

    mutating func nextRevision() -> UInt64 {
        sent += 1
        return sent
    }

    static func acknowledgement(_ revision: UInt64) -> String { "displayed:\(revision)" }

    @discardableResult
    mutating func receive(_ line: String) -> Bool {
        let prefix = "displayed:"
        guard line.hasPrefix(prefix) else { return false }
        let raw = line.dropFirst(prefix.count)
        guard !raw.isEmpty, raw.utf8.allSatisfy({ (48...57).contains($0) }),
              let revision = UInt64(raw), revision > 0, revision <= sent else { return false }
        displayed = max(displayed, revision)
        return true
    }
}

enum MacDockTileAction: String {
    case openGroup, settings, returnToEdge, quit
}
