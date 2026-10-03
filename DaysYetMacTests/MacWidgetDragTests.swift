import AppKit
import XCTest
@testable import DaysYetMac

final class MacWidgetDragTests: XCTestCase {
    func testRecordedQuartzPointsConvertAcrossScreensWithoutPixelScaling() {
        XCTAssertEqual(MacWidgetPointerInteraction.appKitPoint(fromQuartz: CGPoint(x: -1440, y: 1100),
            primaryScreenMaxY: 982), NSPoint(x: -1440, y: -118))
        XCTAssertEqual(MacWidgetPointerInteraction.appKitPoint(fromQuartz: CGPoint(x: 2200, y: -100),
            primaryScreenMaxY: 982), NSPoint(x: 2200, y: 1082))
    }

    func testDragStaysOnTheSelectedDisplayAndRoundTripsTheSavedPosition() throws {
        // A secondary display may have both a negative X and a nonzero Y.
        let bounds = NSRect(x: -1920, y: 144, width: 1920, height: 1020)
        for edge in [MacWidgetEdge.left, .right] {
            for scale in [0.8, 1.0, 1.5] {
                for expanded in [false, true] {
                    let initial = MacWidgetPlacement.frame(in: bounds, edge: edge, position: 0.37,
                                                            expanded: expanded, scale: scale)
                    let anchor = NSPoint(x: initial.midX, y: initial.midY)
                    for delta in [-3000.0, -113.0, 71.0, 3000.0] {
                        var interaction = MacWidgetPointerInteraction()
                        interaction.begin(at: anchor, frame: initial, bounds: bounds, position: 0.37,
                                          clickCount: 1, timestamp: 1)
                        // Moving horizontally across displays does not change the placement display.
                        let point = NSPoint(x: anchor.x + 2500, y: anchor.y + delta)
                        let placement = try XCTUnwrap(interaction.update(at: point))
                        XCTAssertEqual(placement.frame.minX, initial.minX)
                        XCTAssertEqual(placement.frame.size, initial.size)
                        XCTAssertGreaterThanOrEqual(placement.frame.minY, bounds.minY)
                        XCTAssertLessThanOrEqual(placement.frame.maxY, bounds.maxY)
                        let restored = MacWidgetPlacement.frame(in: bounds, edge: edge,
                            position: placement.position, expanded: expanded, scale: scale)
                        XCTAssertEqual(restored.minY, placement.frame.minY, accuracy: 0.000001)
                        XCTAssertEqual(restored.minX, placement.frame.minX)
                        XCTAssertEqual(interaction.finish(at: point, doubleClickInterval: 0.5), .drag(placement))
                    }
                }
            }
        }
    }

    func testMovementUsesTheInitialAnchorAndDoesNotAccumulateDeltas() throws {
        var interaction = beginInteraction()
        let first = try XCTUnwrap(interaction.update(at: NSPoint(x: 23, y: 120)))
        let second = try XCTUnwrap(interaction.update(at: NSPoint(x: 23, y: 130)))
        XCTAssertEqual(first.frame.minY, 120)
        XCTAssertEqual(second.frame.minY, 130)
        // A drag stays a drag even after returning to the mouse-down point.
        let returned = try XCTUnwrap(interaction.update(at: NSPoint(x: 23, y: 100)))
        XCTAssertEqual(returned.frame.minY, 100)
        XCTAssertEqual(interaction.finish(at: NSPoint(x: 23, y: 100), doubleClickInterval: 0.5), .drag(returned))
    }

    func testSmallMovementDoesNotMoveOrOpenSettingsAndTwoCompletedClicksDo() {
        var interaction = beginInteraction()
        XCTAssertNil(interaction.update(at: NSPoint(x: 25, y: 103)))
        XCTAssertEqual(interaction.finish(at: NSPoint(x: 25, y: 103), doubleClickInterval: 0.5), .none)
        XCTAssertFalse(interaction.isPressed)
        begin(&interaction, clickCount: 2, timestamp: 1.2)
        XCTAssertEqual(interaction.finish(at: NSPoint(x: 23, y: 100), doubleClickInterval: 0.5), .openSettings)
    }

    func testDraggingTheSecondClickAndTheNextNativeDoubleClickDoNotOpenSettings() throws {
        var interaction = beginInteraction()
        XCTAssertEqual(interaction.finish(at: NSPoint(x: 23, y: 100), doubleClickInterval: 0.5), .none)
        begin(&interaction, clickCount: 2, timestamp: 1.2)
        let end = NSPoint(x: 23, y: 160)
        let placement = try XCTUnwrap(interaction.update(at: end))
        XCTAssertEqual(interaction.finish(at: end, doubleClickInterval: 0.5), .drag(placement))

        // Native clickCount is not evidence of a completed previous click.
        begin(&interaction, clickCount: 3, timestamp: 1.3)
        XCTAssertEqual(interaction.finish(at: NSPoint(x: 23, y: 100), doubleClickInterval: 0.5), .none)
        begin(&interaction, clickCount: 4, timestamp: 1.4)
        XCTAssertEqual(interaction.finish(at: NSPoint(x: 23, y: 100), doubleClickInterval: 0.5), .openSettings)
    }

    func testHorizontalMovementCancelsAClickAndMouseUpCanSupplyTheFinalDragPoint() throws {
        var interaction = beginInteraction()
        let end = NSPoint(x: 28, y: 100)
        guard case .drag(let placement) = interaction.finish(at: end, doubleClickInterval: 0.5) else {
            return XCTFail("Even a horizontal drag at the threshold must not count as a click.")
        }
        XCTAssertEqual(placement.frame.minY, 100)
        begin(&interaction, clickCount: 2, timestamp: 1.2)
        XCTAssertEqual(interaction.finish(at: NSPoint(x: 23, y: 100), doubleClickInterval: 0.5), .none)
    }

    func testTopPlacementNeverDragsButStillAcceptsTwoClicks() {
        var interaction = beginInteraction(bounds: nil)
        XCTAssertNil(interaction.update(at: NSPoint(x: 23, y: 180)))
        XCTAssertEqual(interaction.finish(at: NSPoint(x: 23, y: 180), doubleClickInterval: 0.5), .none)
        begin(&interaction, clickCount: 2, timestamp: 1.2, bounds: nil)
        XCTAssertEqual(interaction.finish(at: NSPoint(x: 23, y: 100), doubleClickInterval: 0.5), .none)
        begin(&interaction, clickCount: 3, timestamp: 1.3, bounds: nil)
        XCTAssertEqual(interaction.finish(at: NSPoint(x: 23, y: 100), doubleClickInterval: 0.5), .openSettings)
    }

    func testExpiredOrCanceledClickDoesNotOpenSettings() {
        var interaction = beginInteraction()
        XCTAssertEqual(interaction.finish(at: NSPoint(x: 23, y: 100), doubleClickInterval: 0.5), .none)
        begin(&interaction, clickCount: 2, timestamp: 2)
        XCTAssertEqual(interaction.finish(at: NSPoint(x: 23, y: 100), doubleClickInterval: 0.5), .none)
        interaction.cancel()
        begin(&interaction, clickCount: 3, timestamp: 2.1)
        XCTAssertEqual(interaction.finish(at: NSPoint(x: 23, y: 100), doubleClickInterval: 0.5), .none)
    }

    func testFullHeightWidgetKeepsTheExistingFraction() throws {
        let bounds = NSRect(x: 0, y: 50, width: 1920, height: 212)
        let frame = MacWidgetPlacement.frame(in: bounds, edge: .left, position: 0.73, expanded: false)
        var interaction = MacWidgetPointerInteraction()
        interaction.begin(at: NSPoint(x: 23, y: 100), frame: frame, bounds: bounds, position: 0.73,
                          clickCount: 1, timestamp: 1)
        let placement = try XCTUnwrap(interaction.update(at: NSPoint(x: 23, y: 400)))
        XCTAssertEqual(placement.frame, frame)
        XCTAssertEqual(placement.position, 0.73)
    }

    @MainActor
    func testPendingSingleAndDoubleClicksKeepTheHoveredCircleMagnified() async throws {
        for edge in [MacWidgetEdge.left, .right] {
            try await withHoveredController(edge: edge) { controller in
                for clickCount in [1, 2] {
                    beginPress(controller, clickCount: clickCount, timestamp: clickCount == 1 ? 1 : 1.2)
                    // Hosting-view hover callbacks during a captured press
                    // must not turn a click into a temporary hover exit.
                    controller.sideHoverChanged(inside: false, metric: nil)
                    controller.metricHoverChanged(.month, hovering: false)
                    XCTAssertNil(controller.updatePointerPress(at: NSPoint(x: 25, y: 103)))
                    try await Task.sleep(for: .milliseconds(220))
                    XCTAssertEqual(controller.hoveredMetric, .month)
                    XCTAssertEqual(controller.hoverMagnifications, [.month: 1.8])
                    XCTAssertEqual(controller.selectedMetric, .month)
                    XCTAssertTrue(controller.isExpanded)

                    let completion = controller.finishPointerPress(at: NSPoint(x: 25, y: 103), doubleClickInterval: 0.5)
                    XCTAssertEqual(completion, clickCount == 1 ? .none : .openSettings)
                    XCTAssertEqual(controller.hoveredMetric, .month)
                    XCTAssertEqual(controller.hoverMagnifications, [.month: 1.8])
                }

                // Once the click has ended, a real exit must still shrink
                // the circle and close its unpinned details.
                controller.sideHoverChanged(inside: false, metric: nil)
                XCTAssertNil(controller.hoveredMetric)
                let closed = try await eventually {
                    controller.hoverMagnifications.isEmpty && !controller.isExpanded
                }
                XCTAssertTrue(closed)
            }
        }
    }

    @MainActor
    func testUnmagnifiedPressStillCancelsAndResumesDeferredDetailHover() async throws {
        for edge in [MacWidgetEdge.left, .right] {
            try await withHoveredController(edge: edge, magnifiesOnHover: false) { controller in
                beginPress(controller)
                XCTAssertNil(controller.hoveredMetric)
                try await Task.sleep(for: .milliseconds(220))
                XCTAssertFalse(controller.isExpanded)
                XCTAssertEqual(controller.finishPointerPress(at: NSPoint(x: 23, y: 100), doubleClickInterval: 0.5), .none)

                controller.sideHoverChanged(inside: true, metric: .month)
                let opened = try await eventually { controller.isExpanded && controller.selectedMetric == .month }
                XCTAssertTrue(opened, "An unmagnified click must resume the deferred detail hover after release.")
                XCTAssertTrue(controller.hoverMagnifications.isEmpty)
            }
        }
    }

    @MainActor
    func testPressDuringEnlargementKeepsTheCurrentScaleUntilRelease() async throws {
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                      "Enlargement is immediate while Reduce Motion is enabled.")
        for edge in [MacWidgetEdge.left, .right] {
            try await withHoveredController(edge: edge, settleInitialHover: false) { controller in
                let enlarging = try await eventually {
                    let scale = controller.hoverMagnifications[.month] ?? 1
                    return scale > 1 && scale < 1.8
                }
                XCTAssertTrue(enlarging)
                beginPress(controller)
                let snapshot = controller.hoverMagnifications
                try await Task.sleep(for: .milliseconds(220))
                XCTAssertEqual(controller.hoverMagnifications, snapshot,
                               "A captured press must freeze the circle with the detail resize.")
                XCTAssertEqual(controller.hoveredMetric, .month)

                XCTAssertEqual(controller.finishPointerPress(at: NSPoint(x: 23, y: 100), doubleClickInterval: 0.5), .none)
                controller.showWidget()
                let resumed = try await eventually { controller.hoverMagnifications == [.month: 1.8] }
                XCTAssertTrue(resumed, "Releasing the click must resume the normal hover presentation.")
            }
        }
    }

    @MainActor
    func testDragClearsHoverOnlyAfterThresholdAndKeepsItsInitialAnchor() async throws {
        for edge in [MacWidgetEdge.left, .right] {
            try await withHoveredController(edge: edge) { controller in
                beginPress(controller)
                XCTAssertNil(controller.updatePointerPress(at: NSPoint(x: 23, y: 104)))
                XCTAssertEqual(controller.hoveredMetric, .month)
                XCTAssertEqual(controller.hoverMagnifications, [.month: 1.8])

                let moved = try XCTUnwrap(controller.updatePointerPress(at: NSPoint(x: 23, y: 105)))
                XCTAssertEqual(moved.frame.minY, 105)
                XCTAssertNil(controller.hoveredMetric)
                controller.sideHoverChanged(inside: true, metric: .year)
                XCTAssertNil(controller.hoveredMetric, "A captured drag must not start hovering another circle.")

                // Returning to the anchor remains a drag and cannot open
                // settings or retain a saved movement from an earlier event.
                guard case .drag(let returned) = controller.finishPointerPress(
                    at: NSPoint(x: 23, y: 100), doubleClickInterval: 0.5) else {
                    return XCTFail("Crossing the threshold must remain a drag.")
                }
                XCTAssertEqual(returned.frame.minY, 100)
                XCTAssertNil(controller.hoveredMetric)

                controller.sideHoverChanged(inside: true, metric: .month)
                let magnified = try await eventually { controller.hoverMagnifications == [.month: 1.8] }
                XCTAssertTrue(magnified, "The circle must resume normal hover after dragging ends.")
            }
        }
    }

    @MainActor
    func testMouseUpAloneCanTurnASecondPressIntoADragAndClearHover() async throws {
        for edge in [MacWidgetEdge.left, .right] {
            try await withHoveredController(edge: edge) { controller in
                beginPress(controller)
                XCTAssertEqual(controller.finishPointerPress(at: NSPoint(x: 23, y: 100), doubleClickInterval: 0.5), .none)
                beginPress(controller, clickCount: 2, timestamp: 1.2)

                guard case .drag(let placement) = controller.finishPointerPress(
                    at: NSPoint(x: 23, y: 105), doubleClickInterval: 0.5) else {
                    return XCTFail("Mouse-up beyond the threshold must drag instead of opening settings.")
                }
                XCTAssertEqual(placement.frame.minY, 105)
                XCTAssertNil(controller.hoveredMetric)
                let settled = try await eventually { controller.hoverMagnifications.isEmpty }
                XCTAssertTrue(settled)
            }
        }
    }

    @MainActor
    private func withHoveredController(edge: MacWidgetEdge, settleInitialHover: Bool = true,
                                      magnifiesOnHover: Bool = true,
                                      _ body: @MainActor (MacWidgetController) async throws -> Void) async throws {
        let suiteName = "com.hinoshiba.daysyet.mac.click.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let preferences = MacWidgetPreferences(defaults: defaults)
        preferences.edge = edge
        preferences.magnifiesOnHover = magnifiesOnHover
        preferences.hoverScale = 1.8
        // Never start a panel or access the user's saved profile.
        let store = ProfileStore(profile: .initial, saveProfile: { _ in })
        let controller = MacWidgetController(store: store, preferences: preferences)
        defer {
            controller.sideHoverChanged(inside: false, metric: nil)
            defaults.removePersistentDomain(forName: suiteName)
        }
        controller.sideHoverChanged(inside: true, metric: .month)
        if settleInitialHover && magnifiesOnHover {
            let magnified = try await eventually { controller.hoverMagnifications == [.month: 1.8] }
            XCTAssertTrue(magnified)
        }
        try await body(controller)
    }

    @MainActor
    private func beginPress(_ controller: MacWidgetController, clickCount: Int = 1, timestamp: TimeInterval = 1) {
        controller.beginPointerPress(at: NSPoint(x: 23, y: 100),
            frame: NSRect(x: 0, y: 100, width: 204, height: 212),
            bounds: NSRect(x: 0, y: 0, width: 1920, height: 1000),
            clickCount: clickCount, timestamp: timestamp)
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

    private func beginInteraction(bounds: NSRect? = NSRect(x: 0, y: 0, width: 1920, height: 1000)) -> MacWidgetPointerInteraction {
        var interaction = MacWidgetPointerInteraction()
        begin(&interaction, clickCount: 1, timestamp: 1, bounds: bounds)
        return interaction
    }

    private func begin(_ interaction: inout MacWidgetPointerInteraction, clickCount: Int, timestamp: TimeInterval,
                       bounds: NSRect? = NSRect(x: 0, y: 0, width: 1920, height: 1000)) {
        interaction.begin(at: NSPoint(x: 23, y: 100), frame: NSRect(x: 0, y: 100, width: 46, height: 212),
                          bounds: bounds, position: 688.0 / 788.0, clickCount: clickCount, timestamp: timestamp)
    }
}
