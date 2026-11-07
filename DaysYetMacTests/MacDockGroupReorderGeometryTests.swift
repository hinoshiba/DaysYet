import AppKit
import XCTest
@testable import DaysYetMac

final class MacDockGroupReorderGeometryTests: XCTestCase {
    private typealias Geometry = MacDockGroupReorderGeometry
    private typealias Slot = Geometry.Slot
    private let members: [MetricKind] = [.week, .month, .year, .healthyLife, .customLife, .activity]

    func testEveryGrabbedCircleTargetsTheSameForeignGapOnAllDockEdges() {
        let order: [MetricKind?] = [nil, nil] + members.map(Optional.some) + [nil, nil, nil]
        for edge in [MacWidgetEdge.bottom, .left, .right] {
            let slots = layout(order, edge: edge)
            let foreign = slots.filter { $0.metric == nil }
            for insertion in 1...5 {
                let before = center(foreign[insertion - 1].frame)
                let target: NSPoint
                if insertion < foreign.count {
                    let after = center(foreign[insertion].frame)
                    target = NSPoint(x: (before.x + after.x) / 2, y: (before.y + after.y) / 2)
                } else {
                    target = offset(before, by: 48, edge: edge)
                }
                for metric in members {
                    XCTAssertEqual(Geometry.insertion(at: target, grabbed: metric, members: members,
                        slots: slots, edge: edge), insertion, "edge=\(edge), member=\(metric)")
                }
            }
        }
    }

    func testOriginalGroupSlotsKeepTheirGapRegardlessOfGrabbedCircle() {
        let order: [MetricKind?] = [nil, nil] + members.map(Optional.some) + [nil, nil, nil]
        let distances: [CGFloat] = [-31, 0, 31]
        let previousInsertions: [Int?] = [nil, 1, 2, 3]
        for edge in [MacWidgetEdge.bottom, .left, .right] {
            let slots = layout(order, edge: edge)
            for slot in slots where slot.metric != nil {
                for distance in distances {
                    let point = offset(center(slot.frame), by: distance, edge: edge)
                    for metric in members {
                        for previous in previousInsertions {
                            XCTAssertEqual(Geometry.insertion(at: point, grabbed: metric, members: members,
                                slots: slots, edge: edge, previous: previous), 2,
                                "edge=\(edge), member=\(metric), previous=\(String(describing: previous))")
                        }
                    }
                }
            }
        }
    }

    func testDestinationsClampAfterFinderAndAtTheLastForeignItem() {
        for edge in [MacWidgetEdge.bottom, .left, .right] {
            let slots = layout([nil, nil] + members.map(Optional.some) + [nil, nil, nil], edge: edge)
            for metric in [members[0], members[5]] {
                let before = edge == .bottom ? NSPoint(x: -10_000, y: 50) : NSPoint(x: 50, y: 10_000)
                let after = edge == .bottom ? NSPoint(x: 10_000, y: 50) : NSPoint(x: 50, y: -10_000)
                XCTAssertEqual(Geometry.insertion(at: before, grabbed: metric, members: members, slots: slots, edge: edge), 1)
                XCTAssertEqual(Geometry.insertion(at: after, grabbed: metric, members: members, slots: slots, edge: edge), 5)
            }
        }
    }

    func testHysteresisUsesTheForeignCenterInBothDirectionsAndAllOrientations() {
        for edge in [MacWidgetEdge.bottom, .left, .right] {
            let slots = layout([nil, nil] + members.map(Optional.some) + [nil, nil, nil], edge: edge)
            let boundary = center(slots[8].frame)
            func insertion(_ delta: CGFloat, previous: Int? = nil) -> Int? {
                Geometry.insertion(at: offset(boundary, by: delta, edge: edge), grabbed: .week, members: members,
                    slots: slots, edge: edge, previous: previous)
            }
            XCTAssertEqual(insertion(6), 3)
            XCTAssertEqual(insertion(6, previous: 2), 2)
            XCTAssertEqual(insertion(14, previous: 2), 3)
            XCTAssertEqual(insertion(-6), 2)
            XCTAssertEqual(insertion(-6, previous: 3), 3)
            XCTAssertEqual(insertion(-14, previous: 3), 2)
            XCTAssertEqual(insertion(6, previous: 0), 3)
            XCTAssertEqual(insertion(-6, previous: 6), 2)
            XCTAssertEqual(insertion(0), 3)
            XCTAssertEqual(insertion(0, previous: 2), 2)
            XCTAssertEqual(insertion(0, previous: 3), 3)
            // A previous destination several gaps away cannot hold the circle
            // on the wrong side of intermediate applications.
            XCTAssertEqual(insertion(6, previous: 1), 3)
            XCTAssertEqual(insertion(-6, previous: 5), 2)
        }
    }

    func testSplitAndReversedGroupsCanBePlacedButAreNotAlreadyContiguous() {
        let samples: [[MetricKind?]] = [
            [nil, .week, nil, .month, .year, nil, .healthyLife, .customLife, .activity, nil],
            [nil] + members.reversed().map(Optional.some) + [nil]
        ]
        for order in samples {
            let slots = layout(order)
            XCTAssertEqual(Geometry.currentInsertion(members: members, slots: slots), 1)
            XCTAssertFalse(Geometry.isContiguous(members: members, slots: slots))
            XCTAssertEqual(Geometry.insertion(at: center(slots[1].frame), grabbed: .week,
                members: members, slots: slots, edge: .bottom), 1)
        }
        let intact = layout([nil, nil] + members.map(Optional.some) + [nil])
        XCTAssertEqual(Geometry.currentInsertion(members: members, slots: intact), 2)
        XCTAssertTrue(Geometry.isContiguous(members: members, slots: intact))
    }

    func testRepairMovesAnIntruderToTheNearerOutsideOfTheGroup() {
        for edge in [MacWidgetEdge.bottom, .left, .right] {
            for (gap, expected) in [(1, 3), (3, 2), (5, 2)] {
                let order: [MetricKind?] = [nil, nil] + members.prefix(gap).map(Optional.some)
                    + [nil] + members.dropFirst(gap).map(Optional.some) + [nil, nil]
                let slots = layout(order, edge: edge)
                XCTAssertFalse(Geometry.isContiguous(members: members, slots: slots))
                XCTAssertEqual(Geometry.currentInsertion(members: members, slots: slots), 2)
                XCTAssertEqual(Geometry.repairInsertion(members: members, slots: slots), expected)
                if gap == 3 {
                    XCTAssertEqual(Geometry.repairInsertion(members: members, slots: slots, preferred: 3), 3)
                    XCTAssertEqual(Geometry.repairInsertion(members: members, slots: slots, preferred: 2), 2)
                    XCTAssertEqual(Geometry.repairInsertion(members: members, slots: slots, preferred: 4), 2)
                } else {
                    XCTAssertEqual(Geometry.repairInsertion(members: members, slots: slots, preferred: 2), expected)
                }
            }
        }
    }

    func testRepairUsesOddMedianAndNeverPlacesGroupBeforeFinder() {
        let five = Array(members.prefix(5))
        let split: [MetricKind?] = [nil] + five.prefix(2).map(Optional.some) + [nil]
            + five.dropFirst(2).map(Optional.some) + [nil]
        XCTAssertEqual(Geometry.repairInsertion(members: five, slots: layout(split), preferred: 1), 2)
        let beforeFinder = layout(members.map(Optional.some) + [nil, nil])
        XCTAssertEqual(Geometry.currentInsertion(members: members, slots: beforeFinder), 0)
        XCTAssertEqual(Geometry.repairInsertion(members: members, slots: beforeFinder), 1)
        let afterAllForeign = layout([nil, nil] + members.map(Optional.some))
        XCTAssertEqual(Geometry.repairInsertion(members: members, slots: afterAllForeign), 2)
    }

    func testDockMagnificationAndNegativeScreenCoordinatesRemainValid() {
        let order: [MetricKind?] = [nil, nil] + members.map(Optional.some) + [nil]
        for edge in [MacWidgetEdge.bottom, .left, .right] {
            let slots = layout(order, edge: edge).enumerated().map { index, slot in
                let size: CGFloat = index == 4 || index == 8 ? 100 : 64
                let point = center(slot.frame)
                let frame: NSRect
                switch edge {
                case .bottom: frame = NSRect(x: point.x - size / 2 - 1_000, y: -500, width: size, height: size)
                case .left: frame = NSRect(x: -1_000, y: point.y - size / 2 - 2_000, width: size, height: size)
                case .right: frame = NSRect(x: -1_000 - size, y: point.y - size / 2 - 2_000, width: size, height: size)
                case .top: fatalError("Not a native Dock edge")
                }
                return Slot(metric: slot.metric, frame: frame)
            }
            XCTAssertTrue(Geometry.isContiguous(members: members, slots: slots))
            let boundary = center(slots[8].frame)
            for metric in members {
                XCTAssertEqual(Geometry.insertion(at: center(slots[4].frame), grabbed: metric,
                    members: members, slots: slots, edge: edge), 2)
                // This foreign icon is 100pt wide/tall, so its local dead band
                // is 20pt even on screens with negative global coordinates.
                let boundaryCases: [(CGFloat, Int, Int)] = [
                    (14, 2, 2), (22, 2, 3), (-14, 3, 3), (-22, 3, 2)
                ]
                for (distance, previous, expected) in boundaryCases {
                    XCTAssertEqual(Geometry.insertion(at: offset(boundary, by: distance, edge: edge),
                        grabbed: metric, members: members, slots: slots, edge: edge, previous: previous), expected)
                }
            }
        }
    }

    func testMissingDuplicateUnknownAndEmptyMembershipFailClosed() {
        let valid = layout([nil] + members.map(Optional.some) + [nil])
        let invalid: [[Slot]] = [
            [], Array(valid.dropLast(2)),
            layout([nil] + members.map(Optional.some) + [.week]),
            layout([nil] + members.map(Optional.some) + [.study]),
            layout(members.map(Optional.some)),
            layout([nil] + members.map(Optional.some) + Array(repeating: nil, count: 506))
        ]
        for slots in invalid { assertRejected(slots) }
        for badMembers: [MetricKind] in [[], [.week, .week], Array(members.dropLast())] {
            assertRejected(valid, members: badMembers)
        }
        XCTAssertNil(Geometry.insertion(at: center(valid[1].frame), grabbed: .study,
            members: members, slots: valid, edge: .bottom))
    }

    func testInvalidRectanglesMixedDockLinesAndWrongNativeOrderFailClosed() {
        let valid = layout([nil] + members.map(Optional.some) + [nil])
        let invalidFrames = [NSRect.zero, NSRect(x: 10, y: 20, width: -64, height: 64),
            NSRect(x: 10, y: 20, width: 7, height: 64), NSRect(x: 10, y: 20, width: 64, height: 513),
            NSRect(x: CGFloat.nan, y: 20, width: 64, height: 64),
            NSRect(x: 10, y: CGFloat.infinity, width: 64, height: 64),
            NSRect(x: 10, y: 20, width: CGFloat.infinity, height: 64)]
        for frame in invalidFrames {
            var slots = valid
            slots[2] = Slot(metric: slots[2].metric, frame: frame)
            assertRejected(slots)
        }
        var offLine = valid
        offLine[2] = Slot(metric: offLine[2].metric, frame: offLine[2].frame.offsetBy(dx: 0, dy: 500))
        assertRejected(offLine)
        var duplicateFrame = valid
        duplicateFrame[2] = Slot(metric: duplicateFrame[2].metric, frame: duplicateFrame[1].frame)
        assertRejected(duplicateFrame)
        assertRejected(Array(valid.reversed()))
        XCTAssertNil(Geometry.insertion(at: .zero, grabbed: .week, members: members, slots: valid, edge: .left))
        XCTAssertNil(Geometry.insertion(at: .zero, grabbed: .week, members: members, slots: valid, edge: .top))
        for point in [NSPoint(x: CGFloat.nan, y: 0), NSPoint(x: 0, y: CGFloat.infinity)] {
            XCTAssertNil(Geometry.insertion(at: point, grabbed: .week, members: members, slots: valid, edge: .bottom))
        }
    }

    private func assertRejected(_ slots: [Slot], members requested: [MetricKind]? = nil,
                                file: StaticString = #filePath, line: UInt = #line) {
        let selected = requested ?? members
        XCTAssertNil(Geometry.insertion(at: .zero, grabbed: .week, members: selected,
            slots: slots, edge: .bottom), file: file, line: line)
        XCTAssertNil(Geometry.currentInsertion(members: selected, slots: slots), file: file, line: line)
        XCTAssertFalse(Geometry.isContiguous(members: selected, slots: slots), file: file, line: line)
        XCTAssertNil(Geometry.repairInsertion(members: selected, slots: slots), file: file, line: line)
    }

    private func layout(_ order: [MetricKind?], edge: MacWidgetEdge = .bottom) -> [Slot] {
        order.enumerated().map { index, metric in
            let frame = edge == .bottom
                ? NSRect(x: 20 + CGFloat(index) * 72, y: 10, width: 64, height: 64)
                : NSRect(x: edge == .left ? 10 : 1_100, y: 900 - CGFloat(index) * 72, width: 64, height: 64)
            return Slot(metric: metric, frame: frame)
        }
    }

    private func center(_ frame: NSRect) -> NSPoint {
        NSPoint(x: frame.midX, y: frame.midY)
    }

    private func offset(_ point: NSPoint, by distance: CGFloat, edge: MacWidgetEdge) -> NSPoint {
        edge == .bottom ? NSPoint(x: point.x + distance, y: point.y)
            : NSPoint(x: point.x, y: point.y - distance)
    }
}
