import AppKit
import Combine
import XCTest
@testable import DaysYetMac

final class MacWidgetSelectionTests: XCTestCase {
    @MainActor
    func testInitialHoverAndReopeningStartAtTheRequestedRow() async throws {
        try await withController { controller in
            XCTAssertFalse(controller.isExpanded)
            XCTAssertNil(controller.selectedMetric)

            controller.metricHoverChanged(.month, hovering: true)
            let opened = try await eventually {
                controller.isExpanded && controller.selectedMetric == .month
            }
            XCTAssertTrue(opened)
            XCTAssertEqual(controller.selectionPosition, 1)

            controller.hoverChanged(false)
            let closed = try await eventually { !controller.isExpanded }
            XCTAssertTrue(closed)

            controller.metricHoverChanged(.year, hovering: true)
            let reopened = try await eventually {
                controller.isExpanded && controller.selectedMetric == .year
            }
            XCTAssertTrue(reopened)
            // Opening directly on the third ring must not travel from the
            // previously selected ring before it displays the new details.
            XCTAssertEqual(controller.selectionPosition, 2)
        }
    }

    @MainActor
    func testExpandedSelectionMovesThroughIntermediatePositions() async throws {
        try requireMotion()
        try await withController { controller in
            try await openFirstRow(controller)
            var positions: [CGFloat] = []
            let observation = controller.$selectionPosition.dropFirst().sink {
                positions.append($0)
            }
            defer { observation.cancel() }

            controller.metricHoverChanged(.year, hovering: true)
            let arrived = try await eventually {
                controller.selectedMetric == .year && controller.selectionPosition == 2
            }

            XCTAssertTrue(arrived)
            XCTAssertTrue(controller.isExpanded)
            XCTAssertTrue(positions.contains { $0 > 0 && $0 < 2 }, "Changing rings must animate instead of jumping.")
            XCTAssertTrue(positions.allSatisfy { $0 >= 0 && $0 <= 2 }, "Selection must stay within the two target rows.")
            for (previous, next) in zip(positions, positions.dropFirst()) {
                XCTAssertGreaterThanOrEqual(next, previous)
            }
        }
    }

    @MainActor
    func testRetargetingUsesTheCurrentPositionAndFinishesAtTheLatestRow() async throws {
        try requireMotion()
        try await withController { controller in
            try await openFirstRow(controller)
            var requestedRetarget = false
            var positionAtRetarget: CGFloat?
            var retargetedPositions: [CGFloat] = []
            let selectionObservation = controller.$selectedMetric.dropFirst().sink { metric in
                if metric == .month {
                    positionAtRetarget = controller.selectionPosition
                }
            }
            let positionObservation = controller.$selectionPosition.dropFirst().sink { position in
                if controller.selectedMetric == .month {
                    retargetedPositions.append(position)
                }
                if !requestedRetarget, controller.selectedMetric == .year, position > 0, position < 2 {
                    requestedRetarget = true
                    // Simulate another ring hover during movement, without
                    // relying on a sleep landing on a particular frame.
                    controller.metricHoverChanged(.month, hovering: true)
                }
            }
            defer {
                selectionObservation.cancel()
                positionObservation.cancel()
            }

            controller.metricHoverChanged(.year, hovering: true)
            let arrived = try await eventually {
                controller.selectedMetric == .month && controller.selectionPosition == 1
            }

            XCTAssertTrue(arrived)
            XCTAssertTrue(requestedRetarget)
            let origin = try XCTUnwrap(positionAtRetarget)
            XCTAssertGreaterThan(origin, 0)
            XCTAssertLessThanOrEqual(origin, 2)
            let lowerBound = min(origin, 1)
            let upperBound = max(origin, 1)
            XCTAssertFalse(retargetedPositions.isEmpty)
            XCTAssertTrue(retargetedPositions.allSatisfy { $0 >= lowerBound && $0 <= upperBound })
            // The canceled movement must not later overwrite the new target.
            try await Task.sleep(for: .milliseconds(300))
            XCTAssertEqual(controller.selectedMetric, .month)
            XCTAssertEqual(controller.selectionPosition, 1)
        }
    }

    @MainActor
    func testCloseDetailsCancelsADeferredHover() async throws {
        try await withController { controller in
            controller.metricHoverChanged(.year, hovering: true)
            controller.closeDetails()
            try await Task.sleep(for: .milliseconds(300))
            XCTAssertFalse(controller.isExpanded)
            XCTAssertNil(controller.selectedMetric)

            controller.hoverChanged(false)
            try await openFirstRow(controller)
            controller.metricHoverChanged(.year, hovering: true)
            controller.closeDetails()
            try await Task.sleep(for: .milliseconds(300))

            XCTAssertFalse(controller.isExpanded)
            XCTAssertEqual(controller.selectedMetric, .week)
            XCTAssertEqual(controller.selectionPosition, 0)
        }
    }

    @MainActor
    func testCloseDetailsCancelsMovementAndLeavesTheSelectionSettled() async throws {
        try requireMotion()
        try await withController { controller in
            try await openFirstRow(controller)
            controller.metricHoverChanged(.year, hovering: true)
            let moving = try await eventually {
                controller.selectedMetric == .year && controller.selectionPosition > 0 && controller.selectionPosition < 2
            }
            XCTAssertTrue(moving)

            controller.closeDetails()
            XCTAssertFalse(controller.isExpanded)
            XCTAssertEqual(controller.selectionPosition, 2)
            var laterPositions: [CGFloat] = []
            let observation = controller.$selectionPosition.dropFirst().sink {
                laterPositions.append($0)
            }
            defer { observation.cancel() }

            try await Task.sleep(for: .milliseconds(300))
            XCTAssertFalse(controller.isExpanded)
            XCTAssertEqual(controller.selectedMetric, .year)
            XCTAssertEqual(controller.selectionPosition, 2)
            XCTAssertTrue(laterPositions.isEmpty, "Canceled movement must not publish more positions after closing.")
        }
    }

    @MainActor
    func testAdditionalSideRowsCanBeSelectedAndSurviveReordering() async throws {
        var profile = UserProfile.initial
        profile.dashboardMetrics = [.week, .month, .year, .healthyLife, .customLife, .activity, .workday, .study]
        try await withController(profile: profile) { controller in
            XCTAssertEqual(controller.activeMetrics.count, 8)
            controller.metricHoverChanged(.study, hovering: true)
            let opened = try await eventually {
                controller.isExpanded && controller.selectedMetric == .study
            }
            XCTAssertTrue(opened)
            XCTAssertEqual(controller.selectionPosition, 7)

            controller.preferences.keepDetailsOpen = true
            controller.store.update { $0.dashboardMetrics = [.study, .week, .month, .year, .healthyLife, .customLife, .activity, .workday] }
            let reordered = try await eventually { controller.selectionPosition == 0 }
            XCTAssertTrue(reordered)
            XCTAssertEqual(controller.selectedMetric, .study)
            XCTAssertTrue(controller.isExpanded)
        }
    }

    @MainActor
    func testRemovingSelectedExtraRowReconcilesToTheFirstRemainingMetric() async throws {
        var profile = UserProfile.initial
        profile.dashboardMetrics = [.week, .month, .year, .healthyLife]
        try await withController(profile: profile) { controller in
            controller.metricHoverChanged(.healthyLife, hovering: true)
            let opened = try await eventually { controller.selectedMetric == .healthyLife }
            XCTAssertTrue(opened)
            XCTAssertEqual(controller.selectionPosition, 3)

            controller.store.update { $0.dashboardMetrics = [.week, .month, .year] }
            let reconciled = try await eventually {
                controller.selectedMetric == .week && controller.selectionPosition == 0
            }
            XCTAssertTrue(reconciled)
            XCTAssertEqual(controller.activeMetrics, [.week, .month, .year])
            try await Task.sleep(for: .milliseconds(300))
            XCTAssertEqual(controller.selectedMetric, .week)
            XCTAssertEqual(controller.selectionPosition, 0)
        }
    }

    @MainActor
    func testProfileChangeCancelsHoverForARemovedRow() async throws {
        var profile = UserProfile.initial
        profile.dashboardMetrics = [.week, .month, .year, .healthyLife]
        try await withController(profile: profile) { controller in
            controller.metricHoverChanged(.healthyLife, hovering: true)
            controller.store.update { $0.dashboardMetrics = [.week, .month, .year] }
            try await Task.sleep(for: .milliseconds(300))
            XCTAssertFalse(controller.isExpanded)
            XCTAssertEqual(controller.selectedMetric, .week)
            XCTAssertEqual(controller.selectionPosition, 0)

            // A late SwiftUI hover callback for the removed view is also ignored.
            controller.metricHoverChanged(.healthyLife, hovering: true)
            try await Task.sleep(for: .milliseconds(300))
            XCTAssertFalse(controller.isExpanded)
            XCTAssertEqual(controller.selectedMetric, .week)
        }
    }

    @MainActor
    func testTopPlacementReconcilesAnExtraSelectionAndKeepsOnlyTheFirstThree() async throws {
        var profile = UserProfile.initial
        profile.dashboardMetrics = [.week, .month, .year, .healthyLife]
        try await withController(profile: profile) { controller in
            controller.metricHoverChanged(.healthyLife, hovering: true)
            let opened = try await eventually { controller.selectedMetric == .healthyLife }
            XCTAssertTrue(opened)
            controller.preferences.keepDetailsOpen = true
            controller.preferences.edge = .top

            let reconciled = try await eventually {
                controller.selectedMetric == .week && controller.selectionPosition == 0
            }
            XCTAssertTrue(reconciled)
            XCTAssertEqual(controller.activeMetrics, [.week, .month, .year])
            XCTAssertTrue(controller.isExpanded)

            controller.preferences.edge = .right
            let restored = try await eventually { controller.activeMetrics.count == 4 }
            XCTAssertTrue(restored)
            // Allow queued preference delivery to settle before the next hover.
            try await Task.sleep(for: .milliseconds(20))
            controller.metricHoverChanged(.healthyLife, hovering: true)
            let selectedAgain = try await eventually {
                controller.selectedMetric == .healthyLife && controller.selectionPosition == 3
            }
            XCTAssertTrue(selectedAgain)
        }
    }

    @MainActor
    func testSwitchingToTopCancelsADeferredExtraRowHover() async throws {
        var profile = UserProfile.initial
        profile.dashboardMetrics = [.week, .month, .year, .healthyLife]
        try await withController(profile: profile) { controller in
            controller.metricHoverChanged(.healthyLife, hovering: true)
            controller.preferences.edge = .top
            try await Task.sleep(for: .milliseconds(300))
            XCTAssertFalse(controller.isExpanded)
            XCTAssertEqual(controller.activeMetrics, [.week, .month, .year])
            XCTAssertEqual(controller.selectedMetric, .week)
            XCTAssertEqual(controller.selectionPosition, 0)
        }
    }

    @MainActor
    private func withController(profile: UserProfile = .initial,
                                _ body: @MainActor (MacWidgetController) async throws -> Void) async throws {
        let suiteName = "com.hinoshiba.daysyet.mac.selection.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let preferences = MacWidgetPreferences(defaults: defaults)
        preferences.edge = .left
        // Inject both reads and writes, and never start a panel or reset the
        // repository: these tests cannot modify the user's saved profile.
        let store = ProfileStore(profile: profile, saveProfile: { _ in })
        let controller = MacWidgetController(store: store, preferences: preferences)
        defer {
            controller.closeDetails()
            defaults.removePersistentDomain(forName: suiteName)
        }
        try await body(controller)
    }

    @MainActor
    private func openFirstRow(_ controller: MacWidgetController) async throws {
        controller.metricHoverChanged(.week, hovering: true)
        let opened = try await eventually {
            controller.isExpanded && controller.selectedMetric == .week
        }
        XCTAssertTrue(opened)
        XCTAssertEqual(controller.selectionPosition, 0)
    }

    @MainActor
    private func eventually(_ condition: @MainActor () -> Bool) async throws -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while !condition(), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    @MainActor
    private func requireMotion() throws {
        // Respect the machine's accessibility preference instead of changing
        // it just to exercise interpolation. State/cancellation tests still run.
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                      "Interpolation is intentionally disabled while Reduce Motion is enabled.")
    }
}
