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
