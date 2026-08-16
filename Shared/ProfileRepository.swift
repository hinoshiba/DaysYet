import Foundation

enum ProfileRepository {
    static let appGroupIdentifier = "group.com.hinoshiba.daysyet"
    private static let profileKey = "user-profile-v1"

    static func load() -> UserProfile {
        guard let data = defaults.data(forKey: profileKey),
              let profile = try? decoder.decode(UserProfile.self, from: data) else {
            return .initial
        }
        return profile
    }

    static func save(_ profile: UserProfile) {
        guard let data = try? encoder.encode(profile) else { return }
        defaults.set(data, forKey: profileKey)
    }

    static func reset() {
        defaults.removeObject(forKey: profileKey)
    }

    private static let defaults = UserDefaults(suiteName: appGroupIdentifier)!

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}
