import XCTest
@testable import DaysYetMac

final class MacDockTileDisplayStateTests: XCTestCase {
    func testOnlyTheLatestSubmittedImageCanCompleteTheDisplayBarrier() {
        var state = MacDockTileDisplayState()
        XCTAssertFalse(state.isCurrent)
        let first = state.nextRevision()
        let second = state.nextRevision()
        XCTAssertTrue(state.receive(MacDockTileDisplayState.acknowledgement(first)))
        XCTAssertFalse(state.isCurrent)
        XCTAssertTrue(state.receive(MacDockTileDisplayState.acknowledgement(second)))
        XCTAssertTrue(state.isCurrent)
        XCTAssertTrue(state.receive(MacDockTileDisplayState.acknowledgement(first)))
        XCTAssertTrue(state.isCurrent, "A delayed older receipt must not undo a newer one.")
        _ = state.nextRevision()
        XCTAssertFalse(state.isCurrent, "Refreshing the image must require another receipt.")
    }

    func testMalformedUnknownAndFutureReceiptsCannotCompleteTheBarrier() {
        var state = MacDockTileDisplayState()
        _ = state.nextRevision()
        for line in ["openGroup", "displayed:", "displayed:0", "displayed:2", "displayed:-1",
                     "displayed:+1", "displayed: 1", "displayed:1x", "displayed:18446744073709551616"] {
            XCTAssertFalse(state.receive(line), line)
            XCTAssertFalse(state.isCurrent)
        }
        XCTAssertTrue(state.receive("displayed:1"))
        XCTAssertTrue(state.isCurrent)
    }

    @MainActor
    func testRefreshDuringDisplayUpdateWaitsForItsReceiptBeforeHandingOff() async {
        var state = MacDockTileDisplayState()
        let first = state.nextRevision()
        state.receive(MacDockTileDisplayState.acknowledgement(first))
        var elapsed: TimeInterval = 0
        var sleeps: [Duration] = []
        var refreshedRevision: UInt64?

        let ready = await MacDockTileProcessHost.waitForDisplay(
            isAvailable: { true }, isCurrent: { state.isCurrent }, now: { elapsed },
            sleep: { duration in
                sleeps.append(duration)
                elapsed += self.seconds(duration)
                if sleeps.count == 1 {
                    // The first image was acknowledged, but a new render arrived
                    // before its display-update grace period finished.
                    refreshedRevision = state.nextRevision()
                } else if sleeps.count == 2, let refreshedRevision {
                    state.receive(MacDockTileDisplayState.acknowledgement(refreshedRevision))
                }
            })

        XCTAssertTrue(ready)
        XCTAssertEqual(sleeps, [.milliseconds(32), .milliseconds(10), .milliseconds(32)])
        XCTAssertTrue(state.isCurrent)
    }

    @MainActor
    func testUnacknowledgedRefreshKeepsTheOriginalWaitDeadline() async {
        var state = MacDockTileDisplayState()
        let first = state.nextRevision()
        state.receive(MacDockTileDisplayState.acknowledgement(first))
        var elapsed: TimeInterval = 0
        var refreshed = false

        let ready = await MacDockTileProcessHost.waitForDisplay(
            isAvailable: { true }, isCurrent: { state.isCurrent }, now: { elapsed },
            sleep: { duration in
                elapsed += self.seconds(duration)
                if !refreshed {
                    refreshed = true
                    _ = state.nextRevision()
                }
            })

        XCTAssertFalse(ready)
        XCTAssertGreaterThanOrEqual(elapsed, 0.5)
        XCTAssertLessThan(elapsed, 0.511, "A superseding render must not restart the 500ms deadline.")
    }

    @MainActor
    func testRemovedTilesAndCancelledSleepCannotCompleteTheDisplayWait() async {
        var available = true
        let removed = await MacDockTileProcessHost.waitForDisplay(
            isAvailable: { available }, isCurrent: { true }, now: { 0 },
            sleep: { _ in available = false })
        XCTAssertFalse(removed)

        let cancelled = await MacDockTileProcessHost.waitForDisplay(
            isAvailable: { true }, isCurrent: { true }, now: { 0 },
            sleep: { _ in throw CancellationError() })
        XCTAssertFalse(cancelled)
    }

    private func seconds(_ duration: Duration) -> TimeInterval {
        let components = duration.components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}
