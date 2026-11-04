import XCTest
@testable import DaysYetMac

final class MacDockNativeMoverTests: XCTestCase {
    func testIntactSixMemberGroupCrossesOneForeignItemWithSixKeysInEitherDirection() throws {
        let members = Array(0..<6)
        for (input, insertion): ([Int], Int) in [
            ([-1] + members + [-2, -3], 2),
            ([-1, -2] + members + [-3], 1)
        ] {
            let plan = try XCTUnwrap(MacDockBlockMovePlan.steps(
                order: input.map { $0 < 0 ? nil : $0 }, members: members, insertion: insertion))
            XCTAssertEqual(plan.reduce(0) { $0 + abs($1.offset) }, 6)
            var result = input
            for step in plan {
                let index = try XCTUnwrap(result.firstIndex(of: step.member))
                let member = result.remove(at: index)
                result.insert(member, at: index + step.offset)
            }
            XCTAssertEqual(result.filter { $0 < 0 }, [-1, -2, -3])
            XCTAssertEqual(Array(result[insertion..<(insertion + members.count)]), members)
        }
    }

    func testInsertionCannotCrossFinderOrUseInvalidForeignIndex() {
        let order = ["finder", "a", "week", "month", "b"]
        let members: Set<String> = ["week", "month"]
        for insertion in 1...3 {
            XCTAssertTrue(MacDockNativeMoveValidation.allowsInsertion(insertion, order: order,
                members: members, finder: "finder"))
        }
        for insertion in [Int.min, -1, 0, 4, Int.max] {
            XCTAssertFalse(MacDockNativeMoveValidation.allowsInsertion(insertion, order: order,
                members: members, finder: "finder"))
        }
        for invalid in [["a", "finder", "week", "month"], ["week", "month"],
                        ["finder", "week", "finder", "month"]] {
            XCTAssertFalse(MacDockNativeMoveValidation.allowsInsertion(1, order: invalid,
                members: members, finder: "finder"))
        }
    }

    func testOnlyTheRequestedAdjacentExchangeCompletesAPendingKey() throws {
        let before = ["finder", "a", "week", "month", "b"]
        let expected = try XCTUnwrap(MacDockNativeMoveValidation.adjacentOrder(before, member: "week", direction: -1))
        XCTAssertEqual(expected, ["finder", "week", "a", "month", "b"])
        XCTAssertEqual(MacDockNativeMoveValidation.observe(before, before: before, expected: expected), .waiting)
        XCTAssertEqual(MacDockNativeMoveValidation.observe(expected, before: before, expected: expected), .completed)
        // Another application closing/opening, a foreign reorder, a duplicate,
        // or a second unexpected movement must stop the remaining key sequence.
        for changed in [
            ["finder", "week", "month", "b"],
            ["finder", "a", "week", "month", "new", "b"],
            ["finder", "b", "week", "month", "a"],
            ["finder", "a", "week", "week", "month", "b"],
            ["finder", "a", "month", "week", "b"]
        ] {
            XCTAssertEqual(MacDockNativeMoveValidation.observe(changed, before: before, expected: expected), .changed)
        }
    }

    func testExactExchangeRemainsSuccessfulWhenSelectionChangesInsideDock() {
        XCTAssertEqual(MacDockNativeMoveValidation.completedExchange(observation: .completed,
            dockHasFocus: true, targetSelected: true, foreignUnchanged: true, cancelled: false), .verified)
        XCTAssertEqual(MacDockNativeMoveValidation.completedExchange(observation: .completed,
            dockHasFocus: true, targetSelected: false, foreignUnchanged: true, cancelled: false), .verifiedWithSelectionChange)
    }

    func testReselectingCannotTurnAnUnconfirmedMoveOrInterruptionIntoSuccess() {
        for observation in [MacDockNativeMoveValidation.Observation.waiting, .changed] {
            XCTAssertEqual(MacDockNativeMoveValidation.completedExchange(observation: observation,
                dockHasFocus: true, targetSelected: false, foreignUnchanged: true, cancelled: false), .stopped)
        }
        // The selection can be reacquired only inside the already verified
        // Dock transaction. Unknown/other-app focus and user cancellation
        // must never be treated as a harmless hover change.
        for selected in [true, false] {
            XCTAssertEqual(MacDockNativeMoveValidation.completedExchange(observation: .completed,
                dockHasFocus: false, targetSelected: selected, foreignUnchanged: true, cancelled: false), .stopped)
            XCTAssertEqual(MacDockNativeMoveValidation.completedExchange(observation: .completed,
                dockHasFocus: true, targetSelected: selected, foreignUnchanged: false, cancelled: false), .stopped)
            XCTAssertEqual(MacDockNativeMoveValidation.completedExchange(observation: .completed,
                dockHasFocus: true, targetSelected: selected, foreignUnchanged: true, cancelled: true), .stopped)
        }
    }

    func testAdjacentMoveRejectsAmbiguousMembersAndInvalidDirections() {
        XCTAssertNil(MacDockNativeMoveValidation.adjacentOrder(["finder", "week", "week"], member: "week", direction: 1))
        XCTAssertNil(MacDockNativeMoveValidation.adjacentOrder(["finder", "month"], member: "week", direction: 1))
        XCTAssertNil(MacDockNativeMoveValidation.adjacentOrder(["finder", "week"], member: "week", direction: 1))
        for direction in [Int.min, -2, 0, 2, Int.max] {
            XCTAssertNil(MacDockNativeMoveValidation.adjacentOrder(["finder", "week", "a"], member: "week", direction: direction))
        }
    }

    func testSessionGateRequiresTheCurrentLoggedInConsoleUserAndKnownFocus() {
        func allowed(console: Bool = true, loggedIn: Bool = true, sameUser: Bool = true,
                     focus: String? = "com.apple.finder", front: String? = "com.hinoshiba.daysyet") -> Bool {
            MacDockNativeSessionPolicy.allowsInteraction(onConsole: console, loginDone: loggedIn,
                userMatches: sameUser, focusedBundleID: focus, frontmostBundleID: front)
        }
        XCTAssertTrue(allowed())
        XCTAssertTrue(allowed(focus: "com.apple.dock"))
        XCTAssertFalse(allowed(console: false))
        XCTAssertFalse(allowed(loggedIn: false))
        XCTAssertFalse(allowed(sameUser: false))
        XCTAssertFalse(allowed(focus: nil))
        XCTAssertFalse(allowed(front: nil))
    }

    func testSessionGateRejectsLoginWindowAndScreenSaversInEitherFocusSource() {
        for blocker in ["com.apple.loginwindow", "com.apple.ScreenSaver.Engine",
                        "com.apple.ScreenSaver.Engine.legacyScreenSaver", "com.apple.ScreenSaverEngine"] {
            XCTAssertFalse(MacDockNativeSessionPolicy.allowsInteraction(onConsole: true, loginDone: true, userMatches: true,
                focusedBundleID: blocker, frontmostBundleID: "com.hinoshiba.daysyet"))
            XCTAssertFalse(MacDockNativeSessionPolicy.allowsInteraction(onConsole: true, loginDone: true, userMatches: true,
                focusedBundleID: "com.apple.dock", frontmostBundleID: blocker))
        }
    }

    func testSessionReadUnavailableIsDistinctFromConfirmedBlocked() {
        let normal = "com.hinoshiba.daysyet"
        XCTAssertEqual(MacDockNativeSessionPolicy.check(onConsole: true, loginDone: true, userMatches: true,
            focusedBundleID: nil, frontmostBundleID: normal).state, .unavailable)
        XCTAssertEqual(MacDockNativeSessionPolicy.check(onConsole: nil, loginDone: true, userMatches: true,
            focusedBundleID: "com.apple.dock", frontmostBundleID: normal).state, .unavailable)
        XCTAssertEqual(MacDockNativeSessionPolicy.check(onConsole: true, loginDone: true, userMatches: true,
            focusedBundleID: "com.apple.dock", frontmostBundleID: normal).state, .matched)
        // A known lock/session blocker must stop immediately even when the
        // focused-application read is missing; it is not a transient retry.
        for check in [
            MacDockNativeSessionPolicy.check(onConsole: false, loginDone: nil, userMatches: nil,
                focusedBundleID: nil, frontmostBundleID: nil),
            MacDockNativeSessionPolicy.check(onConsole: nil, loginDone: nil, userMatches: nil,
                focusedBundleID: nil, frontmostBundleID: "com.apple.loginwindow"),
            MacDockNativeSessionPolicy.check(onConsole: true, loginDone: true, userMatches: true,
                focusedBundleID: "com.apple.ScreenSaver.Engine", frontmostBundleID: nil)
        ] {
            XCTAssertEqual(check.state, .rejected)
        }
    }

    func testTransientReadRetryIsWorkerOnlyAndBoundedByBothBudgets() {
        func retry(_ state: MacDockNativeGuardPolicy.State = .unavailable, attempts: Int = 1,
                   elapsed: TimeInterval = 0.03, remaining: TimeInterval = 10,
                   interrupted: Bool = false, mainThread: Bool = false) -> Bool {
            MacDockNativeGuardPolicy.canRetry(state, attempts: attempts, elapsed: elapsed,
                remaining: remaining, interrupted: interrupted, mainThread: mainThread)
        }
        XCTAssertTrue(retry())
        XCTAssertTrue(retry(attempts: 2))
        XCTAssertFalse(retry(attempts: 3))
        XCTAssertFalse(retry(elapsed: 0.2))
        XCTAssertFalse(retry(remaining: 0))
        XCTAssertFalse(retry(interrupted: true))
        XCTAssertFalse(retry(mainThread: true))
        XCTAssertFalse(retry(.matched))
        XCTAssertFalse(retry(.rejected))
    }
}
