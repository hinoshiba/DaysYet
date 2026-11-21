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
                    XCTAssertEqual(result.frame.minY, visible.minY)
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

    func testEveryEdgeCanLandOnAnotherDisplayInEitherDirection() throws {
        let primaryFrame = NSRect(x: 0, y: 0, width: 1512, height: 982)
        let secondaryFrames = [
            NSRect(x: -1920, y: 120, width: 1920, height: 1080),
            NSRect(x: 1512, y: -120, width: 1920, height: 1080),
            NSRect(x: -180, y: 982, width: 1920, height: 1080),
            NSRect(x: 180, y: -1080, width: 1920, height: 1080)
        ]
        for secondaryFrame in secondaryFrames {
            let primary = dragDisplay(id: "primary", frame: primaryFrame, notch: 32)
            let secondary = dragDisplay(id: "secondary", frame: secondaryFrame)
            for (source, destination) in [(primary, secondary), (secondary, primary)] {
                let frame = source.docking.frame(edge: .right, position: 0.3)
                let anchor = NSPoint(x: frame.midX, y: frame.midY)
                let bounds = destination.docking.screenFrame
                let points: [MacWidgetEdge: NSPoint] = [
                    .left: NSPoint(x: bounds.minX + 2, y: bounds.midY),
                    .right: NSPoint(x: bounds.maxX - 2, y: bounds.midY),
                    .top: NSPoint(x: bounds.midX, y: bounds.maxY - 2),
                    .bottom: NSPoint(x: bounds.midX, y: bounds.minY + 2)
                ]
                for edge in MacWidgetEdge.allCases {
                    for mouseUpOnly in [false, true] {
                        var interaction = MacWidgetPointerInteraction()
                        interaction.begin(at: anchor, frame: frame, bounds: source.docking.visibleFrame,
                            position: 0.3, clickCount: 1, timestamp: 1, docking: source.docking,
                            displays: [primary, secondary])
                        XCTAssertEqual(interaction.displayID, source.id)
                        let point = try XCTUnwrap(points[edge])
                        let expected = try XCTUnwrap(destination.docking.target(at: point, previous: nil,
                            originalFrame: frame, anchor: anchor))
                        if !mouseUpOnly {
                            let preview = try XCTUnwrap(interaction.update(at: point))
                            XCTAssertTrue(preview.isDetached)
                            XCTAssertEqual(preview.target, expected)
                            XCTAssertEqual(interaction.displayID, destination.id)
                            XCTAssertEqual(interaction.docking?.topInfo, destination.docking.topInfo)
                            XCTAssertEqual(interaction.originalFrame, frame)
                        }
                        guard case .drag(let drop) = interaction.finish(at: point, doubleClickInterval: 0.5) else {
                            return XCTFail("Crossing displays must also work when mouse-up supplies the first movement.")
                        }
                        XCTAssertEqual(drop.target, expected)
                        XCTAssertEqual(drop.edge, edge)
                        XCTAssertTrue(bounds.contains(drop.frame))
                    }
                }
            }
        }
    }

    func testTangentialSlideDetachesWhenItCrossesOntoAnotherDisplay() throws {
        let source = dragDisplay(id: "source", frame: NSRect(x: 0, y: 0, width: 1512, height: 982), edge: .bottom)
        let destination = dragDisplay(id: "destination", frame: NSRect(x: 1512, y: 0, width: 1920, height: 1080), edge: .bottom)
        let frame = source.docking.frame(edge: .bottom, position: 0.5)
        let anchor = NSPoint(x: frame.midX, y: frame.midY)
        var interaction = MacWidgetPointerInteraction()
        interaction.begin(at: anchor, frame: frame, bounds: source.docking.visibleFrame, position: 0.5,
            clickCount: 1, timestamp: 1, docking: source.docking, displays: [source, destination])
        XCTAssertEqual(interaction.update(at: NSPoint(x: anchor.x + 80, y: anchor.y))?.isSlidingAlongEdge, true)
        let point = NSPoint(x: destination.docking.screenFrame.midX, y: anchor.y)
        let preview = try XCTUnwrap(interaction.update(at: point))
        XCTAssertTrue(preview.isDetached)
        XCTAssertFalse(preview.isSlidingAlongEdge)
        XCTAssertEqual(preview.target?.edge, .bottom)
        XCTAssertEqual(interaction.displayID, destination.id)
        XCTAssertTrue(destination.docking.screenFrame.contains(try XCTUnwrap(preview.target).frame))
        XCTAssertEqual(preview.frame, frame.offsetBy(dx: point.x - anchor.x, dy: 0),
                       "Changing displays must preserve the original drag anchor.")
    }

    func testDisplayGapAndDestinationCenterHaveNoLandingAndCancelRetainsSource() throws {
        let source = dragDisplay(id: "source", frame: NSRect(x: 0, y: 0, width: 1512, height: 982))
        let destination = dragDisplay(id: "destination", frame: NSRect(x: 1700, y: 0, width: 1920, height: 1080))
        let frame = source.docking.frame(edge: .right, position: 0.3)
        let anchor = NSPoint(x: frame.midX, y: frame.midY)
        for release in [NSPoint(x: 1600, y: 500), NSPoint(x: 2660, y: 540)] {
            var interaction = MacWidgetPointerInteraction()
            interaction.begin(at: anchor, frame: frame, bounds: source.docking.visibleFrame, position: 0.3,
                clickCount: 1, timestamp: 1, docking: source.docking, displays: [source, destination])
            XCTAssertNotNil(interaction.update(at: NSPoint(x: 1710, y: 500))?.attachment)
            let preview = try XCTUnwrap(interaction.update(at: release))
            XCTAssertNil(preview.target)
            XCTAssertNil(preview.attachment)
            guard case .drag(let drop) = interaction.finish(at: release, doubleClickInterval: 0.5) else {
                return XCTFail("Expected a canceled landing.")
            }
            XCTAssertNil(drop.target)
            XCTAssertEqual(drop.frame, frame)
            XCTAssertEqual(drop.position, 0.3)
            XCTAssertEqual(drop.edge, .right)
        }
        var interaction = MacWidgetPointerInteraction()
        interaction.begin(at: anchor, frame: frame, bounds: source.docking.visibleFrame, position: 0.3,
            clickCount: 1, timestamp: 1, docking: source.docking, displays: [source, destination])
        _ = interaction.update(at: NSPoint(x: 1710, y: 500))
        interaction.cancel()
        XCTAssertNil(interaction.displayID)
        XCTAssertEqual(interaction.finish(at: anchor, doubleClickInterval: 0.5), .none)
    }

    func testChangingDisplaysClearsAttachmentHysteresisAndSourceDockDepth() throws {
        let source = dragDisplay(id: "source", frame: NSRect(x: 0, y: 0, width: 1512, height: 982), edge: .left)
        let destination = dragDisplay(id: "destination", frame: NSRect(x: 1512, y: 0, width: 1920, height: 1080), edge: .left)
        let frame = source.docking.frame(edge: .left, position: 0.5)
        let anchor = NSPoint(x: frame.midX, y: frame.midY)
        var interaction = MacWidgetPointerInteraction()
        interaction.begin(at: anchor, frame: frame, bounds: source.docking.visibleFrame, position: 0.5,
            clickCount: 1, timestamp: 1, docking: source.docking, displays: [source, destination])
        XCTAssertEqual(interaction.update(at: NSPoint(x: 10, y: 800))?.attachment?.edge, .left)
        let crossing = try XCTUnwrap(interaction.update(at: NSPoint(x: 1550, y: 500)))
        XCTAssertEqual(crossing.target?.edge, .left)
        XCTAssertNil(crossing.attachment, "A new display must use the entry distance, not the old edge's release distance.")

        var dockSource = source.docking
        dockSource.systemDockEdge = .bottom
        dockSource.sourceDockDepth = 140
        var dockDestination = destination.docking
        dockDestination.systemDockEdge = .bottom
        interaction.begin(at: anchor, frame: frame, bounds: source.docking.visibleFrame, position: 0.5,
            clickCount: 1, timestamp: 2, docking: dockSource, displays: [
                MacWidgetDragDisplay(id: source.id, docking: dockSource),
                MacWidgetDragDisplay(id: destination.id, docking: dockDestination)
            ])
        let otherDock = try XCTUnwrap(interaction.update(at: NSPoint(x: 2472, y: 100)))
        XCTAssertEqual(otherDock.target?.isSystemDock, true)
        XCTAssertNil(otherDock.attachment)
        XCTAssertEqual(interaction.docking?.sourceDockDepth, 0)
        let originalDock = try XCTUnwrap(interaction.update(at: NSPoint(x: 756, y: 100)))
        XCTAssertEqual(originalDock.attachment?.isSystemDock, true)
        XCTAssertEqual(interaction.docking?.sourceDockDepth, 140)
    }

    private func dragDisplay(id: String, frame: NSRect, edge: MacWidgetEdge = .right,
                             notch: CGFloat = 0) -> MacWidgetDragDisplay {
        MacWidgetDragDisplay(id: id, docking: MacWidgetDocking(edge: edge, screenFrame: frame,
            visibleFrame: NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height - 32),
            topInfo: MacTopNotchInfo(cameraInset: notch, notchWidth: notch > 0 ? 180 : 0, centerX: frame.midX)))
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

    func testBottomRailSlidesNearEitherCornerAboveTheDock() throws {
        for count in [3, 8] {
            for position in [0.0, 1.0] {
                let docking = MacWidgetDocking(edge: .bottom, screenFrame: screen,
                    visibleFrame: visible, metricCount: count)
                let frame = docking.frame(edge: .bottom, position: position)
                let focus = MacWidgetDragGeometry.focusFrame(in: frame, edge: .bottom,
                    index: position == 0 ? 0 : count - 1, scale: 1,
                    metricCount: count, topInfo: docking.topInfo)
                let anchor = NSPoint(x: focus.midX, y: focus.midY)
                var interaction = MacWidgetPointerInteraction()
                interaction.begin(at: anchor, frame: frame, bounds: visible, position: position,
                    clickCount: 1, timestamp: 1, docking: docking)
                let direction: CGFloat = position == 0 ? 1 : -1
                for distance in [CGFloat(6), 12, 40] {
                    let point = NSPoint(x: anchor.x + direction * distance, y: anchor.y)
                    let placement = try XCTUnwrap(interaction.update(at: point))
                    XCTAssertTrue(placement.isSlidingAlongEdge)
                    XCTAssertEqual(placement.attachment?.edge, .bottom)
                    XCTAssertEqual(placement.frame.minX, frame.minX + direction * distance, accuracy: 0.001)
                }
                let release = NSPoint(x: anchor.x + direction * 40, y: anchor.y)
                guard case .drag(let drop) = interaction.finish(at: release, doubleClickInterval: 0.5) else {
                    return XCTFail("Expected a bottom slide")
                }
                XCTAssertEqual(drop.target?.edge, .bottom)
                XCTAssertEqual(drop.frame.minX, frame.minX + direction * 40, accuracy: 0.001)
            }
        }
    }

    func testInsetBottomRailCanSlideOutsideThePhysicalSnapZone() throws {
        let screen = NSRect(x: -1280, y: 120, width: 1280, height: 600)
        let visible = NSRect(x: screen.minX, y: screen.minY + 140, width: screen.width, height: 428)
        let docking = MacWidgetDocking(edge: .bottom, screenFrame: screen, visibleFrame: visible)
        let frame = docking.frame(edge: .bottom, position: 0.5)
        let anchor = NSPoint(x: frame.midX, y: frame.midY)
        var interaction = MacWidgetPointerInteraction()
        interaction.begin(at: anchor, frame: frame, bounds: visible, position: 0.5,
            clickCount: 1, timestamp: 1, docking: docking)
        let point = NSPoint(x: anchor.x + 80, y: anchor.y)
        let placement = try XCTUnwrap(interaction.update(at: point))
        XCTAssertTrue(placement.isSlidingAlongEdge)
        XCTAssertEqual(placement.attachment?.edge, .bottom)
        guard case .drag(let drop) = interaction.finish(at: point, doubleClickInterval: 0.5) else {
            return XCTFail("Expected a bottom slide")
        }
        XCTAssertEqual(drop.target?.edge, .bottom)
        XCTAssertEqual(drop.frame.minX, frame.minX + 80, accuracy: 0.001)
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
