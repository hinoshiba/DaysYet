#if DAYSYET_DIRECT_DOCK_DRAG && DAYSYET_DOCK_NATIVE_REORDER && DAYSYET_DOCK_REORDER_PROBE
import Foundation

/// Disposable app bundles built by Tools/DockGroupMoveProbe/build.sh. The
/// containing probe app is never launched: its historical cleanup is not used.
/// A Move drop into Finder can affect these fixtures, never DaysYet's helpers.
enum MacDockNativeURLProbeFixtures {
    static let appURL = URL(fileURLWithPath: "/tmp/daysyet-native-url-fixtures/DaysYet Dock Group Move Probe.app",
                            isDirectory: true).resolvingSymlinksInPath()

    static func paths(metrics: [MetricKind]) -> [MetricKind: String]? {
        guard metrics.count == 6, Set(metrics).count == 6 else { return nil }
        return Dictionary(uniqueKeysWithValues: metrics.enumerated().map { index, metric in
            (metric, appURL.appendingPathComponent("Contents/Helpers/Group Test \(index + 1).app",
                                                   isDirectory: true).standardizedFileURL.path)
        })
    }

    static func available(metrics: [MetricKind]) -> Bool {
        guard let paths = paths(metrics: metrics) else { return false }
        return metrics.enumerated().allSatisfy { index, metric in
            guard let path = paths[metric] else { return false }
            let url = URL(fileURLWithPath: path, isDirectory: true)
            guard url.resolvingSymlinksInPath().path == path,
                  let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true,
                  let bundle = Bundle(url: url),
                  bundle.bundleIdentifier == "com.hinoshiba.daysyet.dock-group-move-probe.tile\(index + 1)",
                  let executable = bundle.executableURL,
                  executable.path.hasPrefix(path + "/Contents/MacOS/"),
                  FileManager.default.isExecutableFile(atPath: executable.path) else { return false }
            return true
        }
    }
}
#endif
