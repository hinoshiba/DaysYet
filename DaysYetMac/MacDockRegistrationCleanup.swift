import AppKit

/// Only exact helper URLs inside this app are owned by DaysYet. A display
/// name or bundle-identifier prefix alone is never sufficient to remove a tile.
struct MacDockRegistrationPlan {
    static let keys = ["persistent-apps", "recent-apps"]
    let replacements: [String: [Any]]
    let removed: [String: [Any]]
    var count: Int { removed.values.reduce(0) { $0 + $1.count } }

    init(values: [String: [Any]], appURL: URL) {
        let helpers = Dictionary(uniqueKeysWithValues: MetricKind.allCases.map { metric in
            (appURL.appendingPathComponent("Contents/Helpers/DaysYetDock_\(metric.rawValue).app").standardizedFileURL.path,
             "com.hinoshiba.daysyet.dock.\(metric.rawValue)")
        })
        var replacements: [String: [Any]] = [:]
        var removed: [String: [Any]] = [:]
        for key in Self.keys {
            guard let entries = values[key] else { continue }
            var kept: [Any] = []
            var owned: [Any] = []
            for entry in entries {
                if Self.isOwned(entry, helpers: helpers) { owned.append(entry) }
                else { kept.append(entry) }
            }
            if !owned.isEmpty { replacements[key] = kept; removed[key] = owned }
        }
        self.replacements = replacements
        self.removed = removed
    }

    private static func isOwned(_ entry: Any, helpers: [String: String]) -> Bool {
        guard let tile = entry as? [String: Any],
              let data = tile["tile-data"] as? [String: Any],
              let file = data["file-data"] as? [String: Any],
              let rawURL = file["_CFURLString"] as? String,
              let url = URL(string: rawURL), url.isFileURL,
              url.host == nil || url.host == "" || url.host == "localhost",
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              let identifier = helpers[url.standardizedFileURL.path] else { return false }
        // Older Dock records omit the identifier; the exact embedded path is
        // still sufficient. A contradictory identifier is left untouched.
        if let actual = data["bundle-identifier"] { return actual as? String == identifier }
        return true
    }
}

/// The direct build removes only its own saved helper entries. Normal Dock
/// exits change nothing here; reloading the Dock is reserved for stale pins.
@MainActor
final class MacDockRegistrationCleanup {
    enum Result: Equatable { case unchanged, removed(Int), failed, deferred }
    // A native URL-drag experiment must never reach the older preference-write
    // recovery path, including through app exit, a settings change, or a crash
    // followed by relaunch. Only a verified probe cleanup clears this marker.
    private static let nativeURLProbeKey = "daysyet-native-url-probe-pending"
    private static let nativeURLProbeMetricsKey = "daysyet-native-url-probe-metrics"
    static var nativeURLProbePending: Bool { UserDefaults.standard.bool(forKey: nativeURLProbeKey) }
    static var pendingNativeURLProbeMetrics: [MetricKind]? {
        guard let values = UserDefaults.standard.stringArray(forKey: nativeURLProbeMetricsKey),
              values.count == 6, Set(values).count == 6 else { return nil }
        let metrics = values.compactMap(MetricKind.init(rawValue:))
        return metrics.count == values.count ? metrics : nil
    }
    @discardableResult
    static func beginNativeURLProbe(metrics: [MetricKind]) -> Bool {
        guard metrics.count == 6, Set(metrics).count == 6 else { return false }
        UserDefaults.standard.set(metrics.map(\.rawValue), forKey: nativeURLProbeMetricsKey)
        UserDefaults.standard.set(true, forKey: nativeURLProbeKey)
        return true
    }
    static func finishNativeURLProbe() {
        UserDefaults.standard.removeObject(forKey: nativeURLProbeKey)
        UserDefaults.standard.removeObject(forKey: nativeURLProbeMetricsKey)
    }
    private let appURL: URL
    private let read: () -> [String: [Any]]
    private let backUp: ([String: [Any]]) -> Bool
    private let write: ([String: [Any]]) -> Bool
    private let reload: () -> Bool
    private let mayRun: () -> Bool

    init(appURL: URL, read: @escaping () -> [String: [Any]],
         backUp: @escaping ([String: [Any]]) -> Bool,
         write: @escaping ([String: [Any]]) -> Bool, reload: @escaping () -> Bool,
         mayRun: @escaping () -> Bool = { true }) {
        self.appURL = appURL
        self.read = read
        self.backUp = backUp
        self.write = write
        self.reload = reload
        self.mayRun = mayRun
    }

    @discardableResult
    func run() -> Result {
        guard mayRun() else { return .deferred }
        let initial = MacDockRegistrationPlan(values: read(), appURL: appURL)
        guard initial.count > 0 else { return .unchanged }
        guard backUp(initial.removed) else { return .failed }
        // Re-read after filesystem work so another app's newly pinned items
        // and ordering are retained. Never restore a whole old Dock plist.
        let current = MacDockRegistrationPlan(values: read(), appURL: appURL)
        guard current.count > 0 else { return .unchanged }
        if !(current.removed as NSDictionary).isEqual(to: initial.removed), !backUp(current.removed) { return .failed }
        guard write(current.replacements), reload() else { return .failed }
        return .removed(current.count)
    }

    static func system(appURL: URL = Bundle.main.bundleURL) -> MacDockRegistrationCleanup {
#if DAYSYET_DIRECT_DOCK_DRAG
        let domain = "com.apple.dock" as CFString
        return MacDockRegistrationCleanup(appURL: appURL, read: {
            guard CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else { return [:] }
            return Dictionary(uniqueKeysWithValues: MacDockRegistrationPlan.keys.compactMap { key in
                guard let values = CFPreferencesCopyValue(key as CFString, domain,
                    kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [Any] else { return nil }
                return (key, values)
            })
        }, backUp: { removed in
            do {
                let directory = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Application Support/DaysYet/Dock Recovery", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                       attributes: [.posixPermissions: 0o700])
                let data = try PropertyListSerialization.data(fromPropertyList: removed, format: .binary, options: 0)
                try data.write(to: directory.appendingPathComponent("\(UUID().uuidString).plist"), options: .atomic)
                return true
            } catch { return false }
        }, write: { replacements in
            CFPreferencesSetMultiple(replacements as CFDictionary, nil, domain,
                                     kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            return CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        }, reload: {
            // Dock caches pinned items. Reload only after removing our entries,
            // never for an ordinary group move, and never reset its settings.
            let docks = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
            return docks.allSatisfy { $0.processIdentifier > 1 && Darwin.kill($0.processIdentifier, SIGTERM) == 0 }
        }, mayRun: { !Self.nativeURLProbePending })
#else
        return MacDockRegistrationCleanup(appURL: appURL, read: { [:] }, backUp: { _ in false },
                                          write: { _ in false }, reload: { false })
#endif
    }
}
