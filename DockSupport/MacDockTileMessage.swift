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
}

enum MacDockTileAction: String {
    case openGroup, settings, returnToEdge, quit
}
