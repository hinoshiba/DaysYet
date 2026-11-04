import AppKit
import XCTest
@testable import DaysYetMac

@MainActor
final class MacDockRegistrationCleanupTests: XCTestCase {
    private let app = URL(fileURLWithPath: "/Applications/Days Yet.app")

    func testRemovesEveryOwnedPinAndRecentEntryPreservingOtherTilesAndOrder() {
        let other1 = entry(URL(fileURLWithPath: "/Applications/Other.app"), id: "other", guid: 1)
        let other2 = entry(app, id: "com.hinoshiba.daysyet", guid: 2)
        let week = helper(.week, guid: 3)
        let month = helper(.month, guid: 4)
        let values: [String: [Any]] = ["persistent-apps": [other1, week, other2, month, week],
                                      "recent-apps": [month, other1], "persistent-others": [week]]
        let plan = MacDockRegistrationPlan(values: values, appURL: app)
        XCTAssertEqual(plan.count, 4)
        XCTAssertEqual(plan.replacements["persistent-apps"] as? NSArray, [other1, other2] as NSArray)
        XCTAssertEqual(plan.replacements["recent-apps"] as? NSArray, [other1] as NSArray)
        XCTAssertNil(plan.replacements["persistent-others"])
    }

    func testSimilarNamesForgedIdentifiersOtherInstallsAndMalformedEntriesAreUntouched() {
        let expectedURL = app.appendingPathComponent("Contents/Helpers/DaysYetDock_week.app")
        let cases: [Any] = [
            entry(URL(fileURLWithPath: "/Applications/DaysYetDock_week.app"), id: "com.hinoshiba.daysyet.dock.week"),
            entry(URL(fileURLWithPath: "/tmp/Days Yet.app/Contents/Helpers/DaysYetDock_week.app"), id: "com.hinoshiba.daysyet.dock.week"),
            entry(expectedURL, id: "other.application"),
            entry(URL(string: "https://example.com/Applications/Days%20Yet.app/Contents/Helpers/DaysYetDock_week.app")!),
            entry(URL(string: "file://remote/Applications/Days%20Yet.app/Contents/Helpers/DaysYetDock_week.app")!),
            ["tile-data": ["bundle-identifier": "com.hinoshiba.daysyet.dock.week"]],
            ["tile-data": ["file-label": "DaysYet · 今週"]], "malformed", 42
        ]
        let plan = MacDockRegistrationPlan(values: ["persistent-apps": cases], appURL: app)
        XCTAssertEqual(plan.count, 0)
        XCTAssertTrue(plan.replacements.isEmpty)
    }

    func testExactPercentEncodedHelperURLWithoutLegacyBundleIdentifierIsRecognized() {
        let week = entry(app.appendingPathComponent("Contents/Helpers/DaysYetDock_week.app"))
        let plan = MacDockRegistrationPlan(values: ["persistent-apps": [week]], appURL: app)
        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan.replacements["persistent-apps"]?.count, 0)
    }

    func testOrdinaryExitDoesNotWriteBackupPreferencesOrReloadDock() {
        var mutations = 0
        let cleanup = MacDockRegistrationCleanup(appURL: app, read: { ["persistent-apps": []] },
            backUp: { _ in mutations += 1; return true }, write: { _ in mutations += 1; return true },
            reload: { mutations += 1; return true })
        XCTAssertEqual(cleanup.run(), .unchanged)
        XCTAssertEqual(mutations, 0)
    }

    func testPendingNativeProbeDefersCleanupBeforeEvenReadingDockPreferences() {
        var mayRun = false
        var calls: [String] = []
        let cleanup = MacDockRegistrationCleanup(appURL: app,
            read: { calls.append("read"); return ["persistent-apps": []] },
            backUp: { _ in calls.append("backup"); return true },
            write: { _ in calls.append("write"); return true },
            reload: { calls.append("reload"); return true }, mayRun: { mayRun })
        XCTAssertEqual(cleanup.run(), .deferred)
        XCTAssertTrue(calls.isEmpty)
        // A second exit/startup attempt must not consume or bypass the guard.
        XCTAssertEqual(cleanup.run(), .deferred)
        XCTAssertTrue(calls.isEmpty)
        mayRun = true
        XCTAssertEqual(cleanup.run(), .unchanged)
        XCTAssertEqual(calls, ["read"])
    }

    func testHostStopAndStartupRecoveryCannotReloadDockWhileProbeCleanupIsPending() {
        var calls: [String] = []
        let cleanup = MacDockRegistrationCleanup(appURL: app,
            read: { calls.append("read"); return ["persistent-apps": [self.helper(.week)]] },
            backUp: { _ in calls.append("backup"); return true },
            write: { _ in calls.append("write"); return true },
            reload: { calls.append("reload"); return true }, mayRun: { false })
        let host = MacDockTileProcessHost(action: { _ in XCTFail("Unexpected helper action") },
            failed: { XCTFail("Unexpected helper failure") },
            cleanupFailed: { XCTFail("Deferred cleanup is not an instruction to retry mutation") }, cleanup: cleanup)
        host.stop()
        host.removeStaleRegistrations()
        host.stop()
        XCTAssertTrue(calls.isEmpty)
    }

    func testCleanupBacksUpOnlyOwnedEntriesAndPreservesConcurrentDockChanges() {
        let pin = helper(.month)
        let other = entry(URL(fileURLWithPath: "/Applications/Newly Pinned.app"), id: "new.app")
        var values: [String: [Any]] = ["persistent-apps": [pin]]
        var saved: [String: [Any]] = [:]
        var reloads = 0
        let cleanup = MacDockRegistrationCleanup(appURL: app, read: { values }, backUp: {
            saved = $0
            values["persistent-apps"] = [other, pin]
            return true
        }, write: { changes in
            for (key, entries) in changes { values[key] = entries }
            return true
        }, reload: { reloads += 1; return true })
        XCTAssertEqual(cleanup.run(), .removed(1))
        XCTAssertEqual(saved["persistent-apps"] as? NSArray, [pin] as NSArray)
        XCTAssertEqual(values["persistent-apps"] as? NSArray, [other] as NSArray)
        XCTAssertEqual(reloads, 1)
        XCTAssertEqual(cleanup.run(), .unchanged)
        XCTAssertEqual(reloads, 1)
    }

    func testBackupOrWriteFailureNeverReloadsDock() {
        for backupSucceeds in [false, true] {
            var writes = 0
            var reloads = 0
            let cleanup = MacDockRegistrationCleanup(appURL: app,
                read: { ["persistent-apps": [self.helper(.year)]] }, backUp: { _ in backupSucceeds },
                write: { _ in writes += 1; return false }, reload: { reloads += 1; return true })
            XCTAssertEqual(cleanup.run(), .failed)
            XCTAssertEqual(writes, backupSucceeds ? 1 : 0)
            XCTAssertEqual(reloads, 0)
        }
    }

    func testHostStopCleansPinsEvenWithoutTrackedHelperProcesses() {
        var entries: [String: [Any]] = ["persistent-apps": [helper(.week), helper(.month)]]
        var reloads = 0
        let cleanup = MacDockRegistrationCleanup(appURL: app, read: { entries }, backUp: { _ in true },
            write: { changes in
                for (key, values) in changes { entries[key] = values }
                return true
            }, reload: { reloads += 1; return true })
        let host = MacDockTileProcessHost(action: { _ in XCTFail("Unexpected helper action") },
            failed: { XCTFail("Unexpected helper failure") }, cleanup: cleanup)
        host.stop()
        XCTAssertEqual(entries["persistent-apps"]?.count, 0)
        XCTAssertEqual(reloads, 1)
        host.stop()
        XCTAssertEqual(reloads, 1)
    }

    private func helper(_ metric: MetricKind, guid: Int = 100) -> [String: Any] {
        entry(app.appendingPathComponent("Contents/Helpers/DaysYetDock_\(metric.rawValue).app"),
              id: "com.hinoshiba.daysyet.dock.\(metric.rawValue)", guid: guid)
    }

    private func entry(_ url: URL, id: String? = nil, guid: Int = 100) -> [String: Any] {
        var data: [String: Any] = ["file-data": ["_CFURLString": url.absoluteString, "_CFURLStringType": 15],
                                   "file-label": "unchanged", "book": Data([1, 2, 3])]
        if let id { data["bundle-identifier"] = id }
        return ["GUID": guid, "tile-type": "file-tile", "tile-data": data]
    }
}
