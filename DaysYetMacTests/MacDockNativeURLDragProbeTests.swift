#if DAYSYET_DIRECT_DOCK_DRAG && DAYSYET_DOCK_NATIVE_REORDER && DAYSYET_DOCK_REORDER_PROBE
import AppKit
import XCTest
@testable import DaysYetMac

@MainActor
final class MacDockNativeURLDragProbeTests: XCTestCase {
    private typealias Validation = MacDockNativeURLDragValidation
    private let members = ["week", "month", "year", "healthy-life", "custom-life", "activity"]
    private let metrics: [MetricKind] = [.week, .month, .year, .healthyLife, .customLife, .activity]
    private var before: [String] { ["finder", "mail"] + members + ["safari", "terminal"] }

    func testExistingGroupMustReachTheRequestedForeignGapInBothDirections() {
        for insertion in [1, 3, 4] {
            XCTAssertEqual(Validation.classify(before: before, after: order(insertion: insertion),
                members: members, insertion: insertion), .moved)
        }
    }

    func testCreatingSixNewPinsDoesNotCountAsMovingSixExistingItems() {
        let after = order(insertion: 3)
        for incomplete in [["finder", "mail", "safari", "terminal"],
                           Array(before.filter { $0 != "activity" })] {
            XCTAssertEqual(Validation.classify(before: incomplete, after: after,
                members: members, insertion: 3), .invalidIdentity)
        }
    }

    func testDragMoveCallbackCannotMakeAnUnchangedNativeOrderSuccessful() {
        // A destination's reported NSDragOperation.move is deliberately not
        // evidence accepted by this policy. Its actual native order must move.
        XCTAssertEqual(Validation.classify(before: before, after: before,
            members: members, insertion: 3), .unchanged)
        XCTAssertEqual(Validation.classify(before: before, after: before,
            members: members, insertion: nil), .unchanged)
    }

    func testDifferentOrUnconfirmedGapIsNotAConfirmedMove() {
        let after = order(insertion: 3)
        for insertion: Int? in [nil, 0, 1, 2, 4, 5, Int.max] {
            XCTAssertEqual(Validation.classify(before: before, after: after,
                members: members, insertion: insertion), .wrongInsertion)
        }
        let reversed = ["finder", "mail", "safari"] + Array(members.reversed()) + ["terminal"]
        XCTAssertNotEqual(Validation.classify(before: before, after: reversed,
            members: members, insertion: 3), .moved)
        let split = ["finder", "mail"] + Array(members.prefix(3)) + ["safari"]
            + Array(members.suffix(3)) + ["terminal"]
        XCTAssertNotEqual(Validation.classify(before: before, after: split,
            members: members, insertion: 3), .moved)
    }

    func testDuplicateOrMissingIdentitiesFailBeforeAnySuccessClaim() {
        let valid = order(insertion: 3)
        for invalid in [valid + [members[0]], valid + ["finder"], valid.filter { $0 != members[5] }] {
            XCTAssertEqual(Validation.classify(before: before, after: invalid,
                members: members, insertion: 3), .invalidIdentity)
        }
        XCTAssertEqual(Validation.classify(before: before + [members[0]], after: valid,
            members: members, insertion: 3), .invalidIdentity)
        XCTAssertEqual(Validation.classify(before: before, after: valid,
            members: members + [members[0]], insertion: 3), .invalidIdentity)
        XCTAssertEqual(Validation.classify(before: before, after: valid,
            members: [], insertion: 3), .invalidIdentity)
    }

    func testForeignReorderAdditionRemovalOrRecordMutationRejectsTheTrial() {
        let valid = order(insertion: 3)
        let changedForeign = [
            ["finder", "safari", "mail"] + members + ["terminal"],
            ["finder", "mail", "safari"] + members + ["terminal", "new-app"],
            ["finder", "mail", "safari"] + members
        ]
        for changed in changedForeign {
            XCTAssertEqual(Validation.classify(before: before, after: changed,
                members: members, insertion: 3), .foreignChanged)
        }
        XCTAssertEqual(Validation.classify(before: before, after: valid,
            members: members, insertion: 3, foreignRecordsMatch: false), .foreignChanged)
        XCTAssertEqual(Validation.classify(before: before, after: valid,
            members: members, insertion: 3, environmentMatches: false), .environmentChanged)
    }

    func testRealDaysYetHelpersAreForeignToTheDisposableFixtureTrial() {
        let fixtures = (1...6).map { "fixture-\($0)" }
        let realHelpers = metrics.map { "real-daysyet-\($0.rawValue)" }
        let original = ["finder"] + realHelpers + fixtures + ["browser"]
        let moved = ["finder"] + fixtures + realHelpers + ["browser"]
        XCTAssertEqual(Validation.classify(before: original, after: moved,
            members: fixtures, insertion: 1), .moved)
        XCTAssertEqual(Validation.classify(before: original,
            after: ["finder"] + fixtures + Array(realHelpers.reversed()) + ["browser"],
            members: fixtures, insertion: 1), .foreignChanged)
        XCTAssertEqual(Validation.classify(before: original,
            after: ["finder"] + fixtures + Array(realHelpers.dropLast()) + ["browser"],
            members: fixtures, insertion: 1), .foreignChanged)
    }

    func testKnownFixtureIdentityCannotBecomeForeignWhenItsPathMovesOrDisappears() {
        let identifier = "com.hinoshiba.daysyet.dock-group-move-probe.tile1"
        let expected = "/private/tmp/daysyet-native-url-fixtures/Group Test 1.app"
        let paths = [identifier: expected]
        XCTAssertTrue(Validation.fixtureIdentityIsConsistent(bundleIdentifier: identifier,
            exactPath: expected, expectedPathsByBundleIdentifier: paths))
        XCTAssertFalse(Validation.fixtureIdentityIsConsistent(bundleIdentifier: identifier,
            exactPath: "/Users/example/Desktop/Group Test 1.app", expectedPathsByBundleIdentifier: paths))
        XCTAssertFalse(Validation.fixtureIdentityIsConsistent(bundleIdentifier: identifier,
            exactPath: nil, expectedPathsByBundleIdentifier: paths))
        XCTAssertTrue(Validation.fixtureIdentityIsConsistent(bundleIdentifier: "com.example.foreign",
            exactPath: "/Applications/Foreign.app", expectedPathsByBundleIdentifier: paths))
    }

    func testInspectionRetriesOnlyTransientReadsWithinAttemptAndTimeLimits() {
        // A transient AX read may recover, but retrying must not replace an
        // explicit rejection or keep preparation pending without a bound.
        for attempts in [1, 2] {
            XCTAssertTrue(Validation.canRetryInspection(state: .unavailable, attempts: attempts,
                elapsed: 1.499, interrupted: false))
        }
        XCTAssertFalse(Validation.canRetryInspection(state: .unavailable, attempts: 3,
            elapsed: 0.1, interrupted: false))
        for elapsed: TimeInterval in [1.5, 2, -.infinity, -0.1, .infinity, .nan] {
            XCTAssertFalse(Validation.canRetryInspection(state: .unavailable, attempts: 1,
                elapsed: elapsed, interrupted: false))
        }
        for state in [MacDockNativeGuardPolicy.State.matched, .rejected] {
            XCTAssertFalse(Validation.canRetryInspection(state: state, attempts: 1,
                elapsed: 0.1, interrupted: false))
        }
        XCTAssertFalse(Validation.canRetryInspection(state: .unavailable, attempts: 1,
            elapsed: 0.1, interrupted: true))
    }

    func testCleanupSelectsOnlyNewOwnedPinsAndPreservesBaselinePins() {
        let baseline: Set<MetricKind> = [.week, .year]
        let current: Set<MetricKind> = [.week, .month, .year, .activity]
        XCTAssertEqual(Validation.cleanupSelection(requested: [.month, .activity], members: metrics,
            baselinePins: baseline, currentPins: current), [.month, .activity])
        XCTAssertEqual(Validation.cleanupSelection(requested: [.month, .customLife, .activity], members: metrics,
            baselinePins: baseline, currentPins: current), [.month, .activity])
        XCTAssertEqual(Validation.cleanupSelection(requested: [], members: metrics,
            baselinePins: baseline, currentPins: current), [])
        // One forbidden item rejects the entire request; no partial cleanup
        // may quietly remove a preexisting pin while cleaning newly added ones.
        for requested: [MetricKind] in [[.week], [.month, .year], [.month, .month], [.month, .study]] {
            XCTAssertNil(Validation.cleanupSelection(requested: requested, members: metrics,
                baselinePins: baseline, currentPins: current))
        }
        XCTAssertNil(Validation.cleanupSelection(requested: [.month], members: metrics,
            baselinePins: baseline.union([.study]), currentPins: current))
        XCTAssertNil(Validation.cleanupSelection(requested: [.month], members: metrics,
            baselinePins: baseline, currentPins: current.union([.study])))
    }

    func testCleanupDoesNotToggleAPinThatWasAlreadyRemoved() {
        XCTAssertEqual(Validation.cleanupSelection(requested: [.week, .month], members: metrics,
            baselinePins: [], currentPins: []), [])
        XCTAssertEqual(Validation.cleanupSelection(requested: [.week, .month], members: metrics,
            baselinePins: [], currentPins: [.month]), [.month])
    }

    func testCleanupWaitsForLateOptionsAndNeverResendsAMenuAction() {
        var progress = Validation.CleanupMenuProgress()
        XCTAssertEqual(progress.next(optionsAvailable: false, commandAvailable: false, cancelled: false), .wait)
        XCTAssertEqual(progress.next(optionsAvailable: false, commandAvailable: false, cancelled: false), .wait)
        XCTAssertEqual(progress.next(optionsAvailable: true, commandAvailable: false, cancelled: false), .openOptions)
        XCTAssertEqual(progress.next(optionsAvailable: true, commandAvailable: false, cancelled: false), .wait)
        XCTAssertEqual(progress.next(optionsAvailable: true, commandAvailable: true, cancelled: false), .remove)
        // An uncertain AXPress response must not cause a second removal (or
        // toggle Keep in Dock back on) when the same menu is observed again.
        XCTAssertEqual(progress.next(optionsAvailable: true, commandAvailable: true, cancelled: false), .stop)

        var cancelled = Validation.CleanupMenuProgress()
        XCTAssertEqual(cancelled.next(optionsAvailable: false, commandAvailable: false, cancelled: true), .stop)
        XCTAssertEqual(cancelled.next(optionsAvailable: true, commandAvailable: true, cancelled: false), .stop)

        var directCommand = Validation.CleanupMenuProgress()
        XCTAssertEqual(directCommand.next(optionsAvailable: false, commandAvailable: true, cancelled: false), .remove)
    }

    func testCleanupWaitsForIndependentPinAndAXUpdatesButRejectsAnyOtherRemoval() {
        let original = ["finder", "fixture-1", "real-daysyet", "fixture-2", "mail"]
        let removed = original.filter { $0 != "fixture-1" }
        let pins: Set<String> = ["fixture-1", "fixture-2"]
        let remaining: Set<String> = ["fixture-2"]
        for (order, currentPins) in [(original, pins), (original, remaining), (removed, pins)] {
            XCTAssertEqual(Validation.observeRemoval(order: order, pins: currentPins, previousOrder: original,
                previousPins: pins, member: "fixture-1", foreignUnchanged: true), .waiting)
        }
        XCTAssertEqual(Validation.observeRemoval(order: removed, pins: remaining, previousOrder: original,
            previousPins: pins, member: "fixture-1", foreignUnchanged: true), .completed)
        for changed in [removed.filter { $0 != "real-daysyet" }, removed.filter { $0 != "fixture-2" },
                        ["finder", "mail", "real-daysyet", "fixture-2"]] {
            XCTAssertEqual(Validation.observeRemoval(order: changed, pins: remaining, previousOrder: original,
                previousPins: pins, member: "fixture-1", foreignUnchanged: true), .changed)
        }
        XCTAssertEqual(Validation.observeRemoval(order: removed, pins: [], previousOrder: original,
            previousPins: pins, member: "fixture-1", foreignUnchanged: true), .changed)
        XCTAssertEqual(Validation.observeRemoval(order: removed, pins: remaining, previousOrder: original,
            previousPins: pins, member: "fixture-1", foreignUnchanged: false), .changed)
    }

    func testCleanupRetriesOnlyTemporaryReadsWithinBothBudgets() {
        XCTAssertTrue(Validation.canRetryCleanupRead(state: .unavailable, attempts: 2, elapsed: 0.59,
            remaining: 0.1, interrupted: false))
        for state: MacDockNativeGuardPolicy.State in [.matched, .rejected] {
            XCTAssertFalse(Validation.canRetryCleanupRead(state: state, attempts: 1, elapsed: 0,
                remaining: 1, interrupted: false))
        }
        for (attempts, elapsed, remaining, interrupted) in [(3, 0.1, 1.0, false), (1, 0.6, 1.0, false),
                                                            (1, 0.1, 0.025, false), (1, 0.1, 1.0, true)] {
            XCTAssertFalse(Validation.canRetryCleanupRead(state: .unavailable, attempts: attempts, elapsed: elapsed,
                remaining: remaining, interrupted: interrupted))
        }
    }

    func testOperationModesAreExactAndNeverOfferPrivateOrDeleteOperations() {
        XCTAssertEqual(MacDockNativeURLDragMode.move.operationMask, .move)
        XCTAssertEqual(MacDockNativeURLDragMode.link.operationMask, .link)
        XCTAssertEqual(MacDockNativeURLDragMode.copy.operationMask, .copy)
        let combined: NSDragOperation = [.copy, .link, .generic, .move]
        XCTAssertEqual(MacDockNativeURLDragMode.publicOperations.operationMask, combined)
        // The obsolete .all mask is 15 and silently omits move (16).
        XCTAssertTrue(MacDockNativeURLDragMode.publicOperations.operationMask.contains(.move))
        for mode in MacDockNativeURLDragMode.allCases {
            XCTAssertFalse(mode.operationMask.contains(.private))
            XCTAssertFalse(mode.operationMask.contains(.delete))
            XCTAssertFalse(mode.operationMask.isEmpty)
        }
    }

    func testPayloadPathsUseOnlySixDisposableFixturesNeverTheRunningAppsHelpers() throws {
        let paths = try XCTUnwrap(MacDockNativeURLProbeFixtures.paths(metrics: metrics))
        XCTAssertEqual(paths.count, 6)
        XCTAssertEqual(Set(paths.values).count, 6)
        let productionHelpers = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers").standardizedFileURL.path + "/"
        for (index, metric) in metrics.enumerated() {
            let path = try XCTUnwrap(paths[metric])
            XCTAssertFalse(path.hasPrefix(productionHelpers))
            XCTAssertFalse(path.contains("DaysYetDock_"))
            XCTAssertEqual(URL(fileURLWithPath: path).lastPathComponent, "Group Test \(index + 1).app")
        }
        XCTAssertNil(MacDockNativeURLProbeFixtures.paths(metrics: Array(metrics.dropLast())))
        XCTAssertNil(MacDockNativeURLProbeFixtures.paths(metrics: metrics + [.study]))
        XCTAssertNil(MacDockNativeURLProbeFixtures.paths(metrics: [.week, .week, .month, .year, .healthyLife, .activity]))
    }

    func testClosingOrStartingAnotherDragIsBlockedUntilVerificationAndRecoveryFinish() {
        XCTAssertTrue(MacDockNativeURLDragProbePhase.idle.canClose)
        XCTAssertTrue(MacDockNativeURLDragProbePhase.idle.canStartDrag)
        for phase in [MacDockNativeURLDragProbePhase.preparing, .dragging, .inspecting, .cleaning, .blocked] {
            XCTAssertFalse(phase.canClose)
            XCTAssertFalse(phase.canStartDrag)
        }
    }

    private func order(insertion: Int) -> [String] {
        let foreign = ["finder", "mail", "safari", "terminal"]
        return Array(foreign.prefix(insertion)) + members + Array(foreign.dropFirst(insertion))
    }
}
#endif
