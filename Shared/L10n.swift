import Foundation

enum L10n {
    static var isJapanese: Bool {
        Bundle.main.preferredLocalizations.first == "ja"
    }

    static func text(_ japanese: String, _ english: String) -> String {
        isJapanese ? japanese : english
    }
}
