import AppKit
import XCTest
@testable import DaysYetMac

final class MacWidgetDockingTests: XCTestCase {
    private let screen = NSRect(x: -1600, y: 120, width: 1600, height: 1000)
    private var visible: NSRect { NSRect(x: -1600, y: 200, width: 1600, height: 888) }

    private func layout(_ edge: MacWidgetEdge) -> MacWidgetDocking {
        MacWidgetDocking(edge: edge, screenFrame: screen, visibleFrame: visible,
            topInfo: MacTopNotchInfo(cameraInset: 32, notchWidth: 180, centerX: screen.midX))
    }

    private func begin(_ edge: MacWidgetEdge, position: Double = 0.5) -> (MacWidgetPointerInteraction, NSRect, NSPoint) {
        let docking = layout(edge)
        let frame = docking.frame(edge: edge, position: position)
        let anchor = NSPoint(x: frame.midX, y: frame.midY)
        var interaction = MacWidgetPointerInteraction()
        interaction.begin(at: anchor, frame: frame, bounds: visible, position: position,
            clickCount: 1, timestamp: 1, docking: docking)
        return (interaction, frame, anchor)
    }

    func testEveryEdgeResistsThenDetachesAndRetainsTheCapturedAnchor() throws {
        for edge in MacWidgetEdge.allCases {
            var (interaction, frame, anchor) = begin(edge)
            XCTAssertNil(interaction.update(at: NSPoint(x: anchor.x + 2, y: anchor.y + 2)))
            let movement: NSPoint
            switch edge {
            case .left: movement = NSPoint(x: 20, y: 8)
            case .right: movement = NSPoint(x: -20, y: 8)
            case .bottom: movement = NSPoint(x: 8, y: 20)
            case .top: movement = NSPoint(x: 8, y: -20)
            }
            let pull = try XCTUnwrap(interaction.update(at: NSPoint(x: anchor.x + movement.x, y: anchor.y + movement.y)))
            XCTAssertFalse(pull.isDetached)
            XCTAssertEqual(pull.frame.minX, frame.minX + movement.x * 0.32, accuracy: 0.001)
            XCTAssertEqual(pull.frame.minY, frame.minY + movement.y * 0.32, accuracy: 0.001)
            XCTAssertNil(pull.target)
            let free = try XCTUnwrap(interaction.update(at: NSPoint(x: anchor.x + 100, y: anchor.y + 80)))
            XCTAssertTrue(free.isDetached)
            XCTAssertEqual(free.frame, frame.offsetBy(dx: 100, dy: 80))
            let returned = try XCTUnwrap(interaction.update(at: anchor))
            XCTAssertTrue(returned.isDetached, "Returning to the anchor must not stick again during the same drag.")
            XCTAssertEqual(returned.frame, frame)
        }
    }

    func testAllSixteenEdgeRoutesLandOnTheSelectedDisplay() throws {
        let points: [MacWidgetEdge: NSPoint] = [
            .left: NSPoint(x: visible.minX + 2, y: visible.midY),
            .right: NSPoint(x: visible.maxX - 2, y: visible.midY),
            .top: NSPoint(x: screen.midX, y: screen.maxY - 2),
            .bottom: NSPoint(x: visible.midX, y: visible.minY + 2)
        ]
        for source in MacWidgetEdge.allCases {
            for destination in MacWidgetEdge.allCases {
                var (interaction, _, _) = begin(source)
                _ = interaction.update(at: NSPoint(x: screen.midX, y: screen.midY))
                let point = try XCTUnwrap(points[destination])
                let preview = try XCTUnwrap(interaction.update(at: point)?.target)
                XCTAssertEqual(preview.edge, destination)
                guard case .drag(let result) = interaction.finish(at: point, doubleClickInterval: 0.5) else {
                    return XCTFail("A completed edge drop must be a drag.")
                }
                XCTAssertEqual(result.edge, destination)
                XCTAssertEqual(result.target, preview)
                XCTAssertEqual(result.frame, preview.frame)
                XCTAssertTrue(screen.contains(result.frame))
                if destination == .top {
                    XCTAssertEqual(result.frame.maxY, screen.maxY)
                    XCTAssertEqual(result.frame.midX, screen.midX)
                } else if destination == .bottom {
                    XCTAssertEqual(result.frame.minY, screen.minY)
                }
            }
        }
    }

    func testCenterOutsideScreenAndShortPullRestoreTheOriginalPlacement() throws {
        for edge in MacWidgetEdge.allCases {
            for center in [NSPoint(x: screen.midX, y: screen.midY), NSPoint(x: screen.maxX + 500, y: screen.midY)] {
                var (interaction, frame, _) = begin(edge, position: 0.3)
                guard case .drag(let result) = interaction.finish(at: center, doubleClickInterval: 0.5) else {
                    return XCTFail("Mouse-up alone must recognize a drag.")
                }
                XCTAssertNil(result.target)
                XCTAssertEqual(result.frame, frame)
                XCTAssertEqual(result.position, 0.3)
                XCTAssertEqual(result.edge, edge)
            }
            var (interaction, frame, anchor) = begin(edge)
            let shortPull = edge == .bottom || edge == .top
                ? NSPoint(x: anchor.x, y: anchor.y + 12) : NSPoint(x: anchor.x + 12, y: anchor.y)
            guard case .drag(let result) = interaction.finish(at: shortPull, doubleClickInterval: 0.5) else {
                return XCTFail("An attempted pull must not become a click.")
            }
            XCTAssertNil(result.target)
            XCTAssertEqual(result.frame, frame)
        }
    }

    func testQuarterDisplayZonesScaleWithThePhysicalScreen() {
        for size in [NSSize(width: 1600, height: 1000), NSSize(width: 900, height: 1600), NSSize(width: 5120, height: 2880)] {
            let screen = NSRect(origin: NSPoint(x: -1920, y: 144), size: size)
            let visible = NSRect(x: screen.minX + 72, y: screen.minY + 80, width: size.width - 72, height: size.height - 112)
            let docking = MacWidgetDocking(edge: .left, screenFrame: screen, visibleFrame: visible)
            let frame = docking.frame(edge: .left, position: 0.5)
            let anchor = NSPoint(x: frame.midX, y: frame.midY)
            for edge in MacWidgetEdge.allCases {
                let span = edge == .left || edge == .right ? size.width : size.height
                for offset in [CGFloat(-1), 0, 1] {
                    let distance = span / 4 + offset
                    let point: NSPoint
                    switch edge {
                    case .left: point = NSPoint(x: screen.minX + distance, y: screen.midY)
                    case .right: point = NSPoint(x: screen.maxX - distance, y: screen.midY)
                    case .top: point = NSPoint(x: screen.midX, y: screen.maxY - distance)
                    case .bottom: point = NSPoint(x: screen.midX, y: screen.minY + distance)
                    }
                    XCTAssertEqual(docking.target(at: point, previous: edge, originalFrame: frame, anchor: anchor)?.edge,
                                   offset <= 0 ? edge : nil)
                }
            }
            XCTAssertNil(docking.target(at: NSPoint(x: screen.midX, y: screen.midY), previous: .left,
                                        originalFrame: frame, anchor: anchor))
        }
    }

    func testOverlappingCornerZonesAlwaysChooseThePhysicallyNearerEdge() {
        let docking = layout(.left)
        let frame = docking.frame(edge: .left, position: 0.5)
        let anchor = NSPoint(x: frame.midX, y: frame.midY)
        for horizontal in [MacWidgetEdge.left, .right] {
            for vertical in [MacWidgetEdge.top, .bottom] {
                for (dx, dy) in [(CGFloat(120), CGFloat(80)), (80, 120), (100, 100)] {
                    let point = NSPoint(x: horizontal == .left ? screen.minX + dx : screen.maxX - dx,
                                        y: vertical == .bottom ? screen.minY + dy : screen.maxY - dy)
                    for previous in [horizontal, vertical] {
                        let expected = dx == dy ? previous : dx < dy ? horizontal : vertical
                        XCTAssertEqual(docking.target(at: point, previous: previous, originalFrame: frame, anchor: anchor)?.edge, expected)
                    }
                }
            }
        }
    }

    func testSameEdgeDropsPreserveTheGrabOffsetAndCancelDoesNotCompleteADrop() throws {
        for edge in [MacWidgetEdge.left, .right, .bottom] {
            let docking = layout(edge)
            let frame = docking.frame(edge: edge, position: 0.3)
            let anchor = NSPoint(x: frame.minX + 0.3 * frame.width, y: frame.minY + 0.7 * frame.height)
            let target = try XCTUnwrap(docking.target(at: anchor, previous: nil, originalFrame: frame, anchor: anchor))
            XCTAssertEqual(target.position, 0.3, accuracy: 0.000001)
            var (interaction, _, _) = begin(edge)
            _ = interaction.update(at: NSPoint(x: screen.midX, y: screen.midY))
            interaction.cancel()
            XCTAssertFalse(interaction.isPressed)
            XCTAssertEqual(interaction.finish(at: anchor, doubleClickInterval: 0.5), .none)
        }
    }

    func testDockFitsAvailableWidthAndKeepsCirclesAndDetailsWithinItsSurface() throws {
        for count in [3, MetricKind.allCases.count] {
            for scale in [0.8, 1, 1.5] {
                for detailScale in [1.0, 1.5] {
                    for width in [CGFloat(320), 1600] {
                        let bounds = NSRect(x: -1600, y: 200, width: width, height: 888)
                        for expanded in [false, true] {
                            let magnification = expanded ? 1.8 : 1
                            let frame = MacWidgetPlacement.frame(in: bounds, edge: .bottom, position: 0.7,
                                expanded: expanded, scale: scale, metricCount: count,
                                hoverScale: magnification, detailScale: detailScale)
                            XCTAssertTrue(bounds.contains(frame))
                            if !expanded {
                                XCTAssertEqual(MacWidgetPlacement.dockExpansion(in: frame.size, scale: scale,
                                    metricCount: count, detailScale: detailScale), 0, accuracy: 0.000001,
                                    "A compressed closed Dock must not reveal details.")
                            }
                            for index in 0..<count {
                                let ring = MacWidgetPlacement.dockRingFrame(in: frame.size, index: CGFloat(index),
                                    scale: scale, metricCount: count, magnification: magnification, detailScale: detailScale)
                                let path = MacWidgetSurface.path(in: frame.size, edge: .bottom, selectedIndex: CGFloat(index),
                                    scale: scale, metricCount: count, hoverScale: magnification, detailScale: detailScale,
                                    magnifications: [index: magnification])
                                for angle in stride(from: 0.0, to: 2 * .pi, by: .pi / 8) {
                                    let point = CGPoint(x: ring.midX + cos(angle) * ring.width / 2,
                                                        y: ring.midY + sin(angle) * ring.height / 2)
                                    XCTAssertTrue(CGRect(origin: .zero, size: frame.size).contains(point))
                                    XCTAssertTrue(path.contains(point), "Circle must remain visible inside the Dock.")
                                }
                                XCTAssertEqual(MacWidgetSurface.sideHoverIndex(at: CGPoint(x: ring.midX, y: ring.midY),
                                    in: frame.size, edge: .bottom, scale: scale, metricCount: count,
                                    magnifications: [index: magnification], detailScale: detailScale), index)
                                if expanded {
                                    let detail = MacWidgetPlacement.dockDetailFrame(in: frame.size,
                                        selectedIndex: CGFloat(index), scale: scale, metricCount: count, detailScale: detailScale)
                                    for x in [detail.minX, detail.maxX] {
                                        for y in [detail.minY, detail.maxY] {
                                            XCTAssertTrue(path.contains(CGPoint(x: x, y: y)))
                                        }
                                    }
                                }
                            }
                            XCTAssertFalse(MacWidgetSurface.contains(CGPoint(x: 1, y: 1), in: frame.size,
                                edge: .bottom, selectedIndex: 0, scale: scale, metricCount: count, detailScale: detailScale))
                        }
                    }
                }
            }
        }
    }

    @MainActor
    func testOnlyCommittedDropsPersistAndBottomPositionDoesNotReplaceSidePosition() throws {
        let suite = "com.hinoshiba.daysyet.docking.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = MacWidgetPreferences(defaults: defaults)
        preferences.edge = .right
        preferences.verticalPosition = 0.24
        let controller = MacWidgetController(store: ProfileStore(profile: .initial, saveProfile: { _ in }),
                                             preferences: preferences, reducesMotion: { true })
        let docking = layout(.right)
        let frame = docking.frame(edge: .right, position: 0.24)
        let anchor = NSPoint(x: frame.midX, y: frame.midY)
        controller.beginPointerPress(at: anchor, frame: frame, bounds: visible, clickCount: 1, timestamp: 1, docking: docking)
        let point = NSPoint(x: screen.midX - 200, y: visible.minY + 8)
        XCTAssertEqual(controller.updatePointerPress(at: point)?.target?.edge, .bottom)
        XCTAssertEqual(MacWidgetPreferences(defaults: defaults).edge, .right)
        guard case .drag(let drop) = controller.finishPointerPress(at: point, doubleClickInterval: 0.5) else {
            return XCTFail("Expected a completed bottom drop.")
        }
        controller.saveDrop(drop)
        let restored = MacWidgetPreferences(defaults: defaults)
        XCTAssertEqual(restored.edge, .bottom)
        XCTAssertEqual(restored.horizontalPosition, try XCTUnwrap(drop.target).position)
        XCTAssertEqual(restored.verticalPosition, 0.24)
        controller.saveDrop(.init(frame: frame, position: 0.5, edge: .left))
        XCTAssertEqual(preferences.edge, .bottom, "A canceled drop must not write preferences.")
        preferences.keepDetailsOpen = true
        controller.beginPointerPress(at: anchor, frame: frame, bounds: visible, clickCount: 1, timestamp: 2, docking: docking)
        _ = controller.updatePointerPress(at: point)
        // Escape routes to closeDetails, but a captured drag takes priority
        // over changing the user's pinned-detail preference.
        controller.closeDetails()
        XCTAssertEqual(controller.finishPointerPress(at: point, doubleClickInterval: 0.5), .none)
        XCTAssertEqual(preferences.edge, .bottom)
        XCTAssertEqual(preferences.horizontalPosition, restored.horizontalPosition)
        XCTAssertTrue(preferences.keepDetailsOpen)
        preferences.reset()
        XCTAssertEqual(MacWidgetPreferences(defaults: defaults).horizontalPosition, 0.5)
    }
}
