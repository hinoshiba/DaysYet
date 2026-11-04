import AppKit
import XCTest
@testable import DaysYetMac

final class MacDockGroupDropGuardTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1200, height: 1000)
    private let slots = [CGRect(x: 300, y: 930, width: 60, height: 60),
                         CGRect(x: 370, y: 930, width: 60, height: 60),
                         CGRect(x: 440, y: 930, width: 60, height: 60)]

    func testForeignDockDragSnapsBeforeOrAfterWholeGroupIncludingGaps() throws {
        var routing = try bottomRouting()
        let source = CGPoint(x: 250, y: 960)
        XCTAssertEqual(routing.route(.down, at: source, now: 1), source)
        // The first target is a gap, not one of DaysYet's actual icon squares.
        XCTAssertEqual(routing.route(.dragged, at: CGPoint(x: 365, y: 960), now: 1.1), CGPoint(x: 296, y: 960))
        XCTAssertEqual(routing.route(.dragged, at: CGPoint(x: 435, y: 960), now: 1.15), CGPoint(x: 504, y: 960))
        XCTAssertEqual(routing.route(.up, at: CGPoint(x: 435, y: 960), now: 1.2), CGPoint(x: 504, y: 960))
        XCTAssertFalse(routing.isTracking)
    }

    func testLeftAndRightDocksRedirectAlongVerticalAxisOnly() throws {
        for edge in [MacWidgetEdge.left, .right] {
            let x: CGFloat = edge == .left ? 10 : 1130
            let native = [CGRect(x: x, y: 300, width: 60, height: 60), CGRect(x: x, y: 370, width: 60, height: 60)]
            let region = try XCTUnwrap(MacDockGroupDropRegion(edge: edge, screen: screen, slots: native))
            var routing = MacDockGroupDropRouting()
            routing.update(region, now: 1)
            let pointerX = x + 30
            _ = routing.route(.down, at: CGPoint(x: pointerX, y: 250), now: 1)
            XCTAssertEqual(routing.route(.dragged, at: CGPoint(x: pointerX, y: 340), now: 1.1), CGPoint(x: pointerX, y: 296))
            XCTAssertEqual(routing.route(.up, at: CGPoint(x: pointerX, y: 400), now: 1.2), CGPoint(x: pointerX, y: 434))
        }
    }

    func testOwnGroupPressIsNeverRedirected() throws {
        var routing = try bottomRouting()
        let ownCorner = CGPoint(x: 301, y: 931)
        XCTAssertEqual(routing.route(.down, at: ownCorner, now: 1), ownCorner)
        let target = CGPoint(x: 435, y: 960)
        XCTAssertEqual(routing.route(.dragged, at: target, now: 1.1), target)
        XCTAssertEqual(routing.route(.up, at: target, now: 1.2), target)
        XCTAssertFalse(routing.isTracking)
    }

    func testClicksAndDragsOutsideTheGroupPassThrough() throws {
        var routing = try bottomRouting()
        let source = CGPoint(x: 250, y: 960)
        _ = routing.route(.down, at: source, now: 1)
        XCTAssertEqual(routing.route(.up, at: source, now: 1.1), source)
        _ = routing.route(.down, at: source, now: 1.15)
        for point in [CGPoint(x: 250, y: 960), CGPoint(x: 600, y: 960), CGPoint(x: 400, y: 700), CGPoint(x: 400, y: 1200)] {
            XCTAssertEqual(routing.route(.dragged, at: point, now: 1.2), point)
        }
    }

    func testCenterHysteresisDoesNotAlternateAtEveryPixel() throws {
        var routing = try bottomRouting()
        _ = routing.route(.down, at: CGPoint(x: 250, y: 960), now: 1)
        for x in [399.0, 401, 398, 405] {
            XCTAssertEqual(routing.route(.dragged, at: CGPoint(x: x, y: 960), now: 1.1).x, 296)
        }
        XCTAssertEqual(routing.route(.dragged, at: CGPoint(x: 410, y: 960), now: 1.2).x, 504)
        XCTAssertEqual(routing.route(.up, at: CGPoint(x: 399, y: 960), now: 1.25).x, 504)
    }

    func testMissingStaleOrChangedDisplayGeometryReleasesInputWithoutLosingMouseUp() throws {
        let target = CGPoint(x: 400, y: 960)
        for invalidation in 0..<3 {
            var routing = try bottomRouting()
            _ = routing.route(.down, at: CGPoint(x: 250, y: 960), now: 1)
            _ = routing.route(.dragged, at: target, now: 1.1)
            if invalidation == 0 { routing.update(nil, now: 1.15) }
            if invalidation == 1 { routing.cancel() }
            let releaseTime = invalidation == 2 ? 1.5 : 1.2
            XCTAssertEqual(routing.route(.up, at: target, now: releaseTime), target)
            XCTAssertFalse(routing.isTracking)
        }
    }

    func testFreshGeometryCanFollowDockMagnificationDuringTheSameDrag() throws {
        var routing = try bottomRouting()
        _ = routing.route(.down, at: CGPoint(x: 250, y: 960), now: 1)
        _ = routing.route(.dragged, at: CGPoint(x: 260, y: 960), now: 1.1)
        let magnified = [CGRect(x: 280, y: 900, width: 90, height: 90), CGRect(x: 380, y: 900, width: 90, height: 90),
                         CGRect(x: 480, y: 900, width: 90, height: 90)]
        routing.update(try XCTUnwrap(MacDockGroupDropRegion(edge: .bottom, screen: screen, slots: magnified)), now: 2)
        XCTAssertEqual(routing.route(.dragged, at: CGPoint(x: 350, y: 950), now: 2.1), CGPoint(x: 276, y: 950))
        XCTAssertEqual(routing.route(.up, at: CGPoint(x: 550, y: 950), now: 2.2), CGPoint(x: 574, y: 950))
    }

    func testLongPressMenuAndChangedDisplayDoNotRedirectARelease() throws {
        let target = CGPoint(x: 400, y: 960)
        var menu = try bottomRouting()
        _ = menu.route(.down, at: CGPoint(x: 250, y: 960), now: 1)
        menu.update(try XCTUnwrap(MacDockGroupDropRegion(edge: .bottom, screen: screen, slots: slots)), now: 1.6)
        XCTAssertEqual(menu.route(.dragged, at: target, now: 1.7), target)
        XCTAssertFalse(menu.isTracking)

        var display = try bottomRouting()
        _ = display.route(.down, at: CGPoint(x: 250, y: 960), now: 1)
        _ = display.route(.dragged, at: target, now: 1.1)
        let resized = CGRect(x: 0, y: 0, width: 1400, height: 1000)
        display.update(try XCTUnwrap(MacDockGroupDropRegion(edge: .bottom, screen: resized, slots: slots)), now: 1.15)
        XCTAssertEqual(display.route(.up, at: target, now: 1.2), target)
        XCTAssertFalse(display.isTracking)
    }

    func testAReleaseWithoutTheLastDragSampleStillUsesTheOutsideTarget() throws {
        var routing = try bottomRouting()
        _ = routing.route(.down, at: CGPoint(x: 250, y: 960), now: 1)
        XCTAssertEqual(routing.route(.up, at: CGPoint(x: 480, y: 960), now: 1.1), CGPoint(x: 504, y: 960))
        XCTAssertFalse(routing.isTracking)
    }

    func testNegativeDisplayCoordinatesAndScreenEdgesRemainBounded() throws {
        let upperDisplay = CGRect(x: -1200, y: -1000, width: 1200, height: 1000)
        let native = [CGRect(x: -1200, y: -70, width: 60, height: 60), CGRect(x: -1130, y: -70, width: 60, height: 60)]
        let region = try XCTUnwrap(MacDockGroupDropRegion(edge: .bottom, screen: upperDisplay, slots: native))
        var routing = MacDockGroupDropRouting()
        routing.update(region, now: 1)
        _ = routing.route(.down, at: CGPoint(x: -1000, y: -40), now: 1)
        let destination = routing.route(.up, at: CGPoint(x: -1190, y: -40), now: 1.1)
        XCTAssertEqual(destination, CGPoint(x: -1066, y: -40))
        XCTAssertTrue(upperDisplay.contains(destination))
    }

    func testInvalidPartialOrNonDockRegionsAreRejected() {
        XCTAssertNil(MacDockGroupDropRegion(edge: .top, screen: screen, slots: slots))
        XCTAssertNil(MacDockGroupDropRegion(edge: .bottom, screen: screen, slots: [slots[0]]))
        XCTAssertNil(MacDockGroupDropRegion(edge: .bottom, screen: .zero, slots: slots))
        XCTAssertNil(MacDockGroupDropRegion(edge: .bottom, screen: screen,
            slots: [slots[0], CGRect(x: CGFloat.nan, y: 930, width: 60, height: 60)]))
        XCTAssertNil(MacDockGroupDropRegion(edge: .bottom, screen: screen,
            slots: [CGRect(x: 300, y: 100, width: 60, height: 60), CGRect(x: 370, y: 100, width: 60, height: 60)]))
    }

    private func bottomRouting() throws -> MacDockGroupDropRouting {
        var routing = MacDockGroupDropRouting()
        routing.update(try XCTUnwrap(MacDockGroupDropRegion(edge: .bottom, screen: screen, slots: slots)), now: 1)
        return routing
    }
}
