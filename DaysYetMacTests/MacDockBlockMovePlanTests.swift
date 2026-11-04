import XCTest
@testable import DaysYetMac

final class MacDockBlockMovePlanTests: XCTestCase {
    private func minimumAdjacentExchanges(from order: [Int], to expected: [Int]) -> Int {
        let ranks = Dictionary(uniqueKeysWithValues: expected.enumerated().map { ($0.element, $0.offset) })
        let ranked = order.map { ranks[$0]! }
        return ranked.indices.reduce(0) { total, index in
            total + ranked.dropFirst(index + 1).filter { $0 < ranked[index] }.count
        }
    }

    func testEveryPermutationUsesTheMinimumExchangesAroundEveryForeignAnchor() throws {
        func permutations(_ values: [Int]) -> [[Int]] {
            if values.count <= 1 { return [values] }
            return values.indices.flatMap { index in
                var rest = values
                let first = rest.remove(at: index)
                return permutations(rest).map { [first] + $0 }
            }
        }
        for input in permutations([0, 1, 2, -1, -2, -3]) {
            let foreign = input.filter { $0 < 0 }
            for insertion in 0...foreign.count {
                let plan = try XCTUnwrap(MacDockBlockMovePlan.steps(
                    order: input.map { $0 < 0 ? nil : $0 }, members: [0, 1, 2], insertion: insertion))
                var expected = foreign
                expected.insert(contentsOf: [0, 1, 2], at: insertion)
                var result = input
                for step in plan {
                    let source = try XCTUnwrap(result.firstIndex(of: step.member))
                    let value = result.remove(at: source)
                    result.insert(value, at: source + step.offset)
                    XCTAssertEqual(result.filter { $0 < 0 }, foreign)
                }
                XCTAssertEqual(result, expected, "input=\(input), insertion=\(insertion)")
                XCTAssertEqual(plan.reduce(0) { $0 + abs($1.offset) },
                    minimumAdjacentExchanges(from: input, to: expected), "input=\(input), insertion=\(insertion)")
                if input == expected { XCTAssertTrue(plan.isEmpty) }
            }
        }
    }

    func testSixMembersCrossSixForeignItemsInSixContinuousRunsInBothDirections() throws {
        let members = Array(0..<6)
        let crossedForeign = [-2, -3, -4, -5, -6, -7]
        let before = [-1] + members + crossedForeign + [-8]
        let after = [-1] + crossedForeign + members + [-8]
        for (input, insertion, direction) in [(before, 7, 1), (after, 1, -1)] {
            let plan = try XCTUnwrap(MacDockBlockMovePlan.steps(
                order: input.map { $0 < 0 ? nil : $0 }, members: members, insertion: insertion))
            XCTAssertEqual(plan.reduce(0) { $0 + abs($1.offset) }, 36)
            XCTAssertEqual(plan.count, 6)
            XCTAssertEqual(Set(plan.map(\.member)), Set(members))
            XCTAssertTrue(plan.allSatisfy { $0.offset == direction * 6 })
            XCTAssertEqual(plan.map(\.member), direction > 0 ? Array(members.reversed()) : members)

            let foreign = input.filter { $0 < 0 }
            var result = input
            for step in plan {
                for _ in 0..<abs(step.offset) {
                    let source = try XCTUnwrap(result.firstIndex(of: step.member))
                    result.swapAt(source, source + direction)
                    XCTAssertEqual(result.filter { $0 < 0 }, foreign)
                }
            }
            XCTAssertEqual(result, direction > 0 ? after : before)
        }
    }

    func testEqualRunCountsKeepTheForwardCandidate() throws {
        let plan = try XCTUnwrap(MacDockBlockMovePlan.steps(
            order: [nil, 2, 1, 0, nil], members: [0, 1, 2], insertion: 1))
        XCTAssertEqual(plan, [.init(member: 2, offset: 2), .init(member: 1, offset: 1)])
    }

    func testSingleIntruderRepairsOnlyTheMembersAcrossTheChosenBoundary() throws {
        let members = Array(0..<6)
        for split in 1..<members.count {
            let input = [-1] + Array(members[..<split]) + [-2] + Array(members[split...]) + [-3]
            var costs: [Int] = []
            // Keep the group before or after the intruder. Already-correct
            // members must never cycle through one another during repair.
            for insertion in [1, 2] {
                let plan = try XCTUnwrap(MacDockBlockMovePlan.steps(
                    order: input.map { $0 < 0 ? nil : $0 }, members: members, insertion: insertion))
                let cost = plan.reduce(0) { $0 + abs($1.offset) }
                costs.append(cost)
                XCTAssertEqual(cost, insertion == 1 ? members.count - split : split)
                let moved = Set(plan.map(\.member))
                XCTAssertEqual(moved, Set(insertion == 1 ? Array(members[split...]) : Array(members[..<split])))
                var result = input
                for step in plan {
                    let source = try XCTUnwrap(result.firstIndex(of: step.member))
                    let value = result.remove(at: source)
                    result.insert(value, at: source + step.offset)
                    XCTAssertEqual(result.filter { $0 < 0 }, [-1, -2, -3])
                }
                var expected = [-1, -2, -3]
                expected.insert(contentsOf: members, at: insertion)
                XCTAssertEqual(result, expected)
            }
            XCTAssertEqual(costs.min(), min(split, members.count - split))
        }
    }

    func testEveryInsertionOfIntactAndSplitGroupsPreservesOthersAndMemberOrder() throws {
        // Distinct negative IDs stand for unrelated native Dock items.
        let samples = [[-1, -2, 0, 1, 2, -3, -4], [0, -1, 1, -2, 2, -3, -4],
                       [-1, 2, -2, 0, 1, -3, -4], [2, 1, 0, -1, -2, -3, -4]]
        for input in samples {
            for insertion in 0...4 {
                let plan = try XCTUnwrap(MacDockBlockMovePlan.steps(order: input.map { $0 < 0 ? nil : $0 }, members: [0, 1, 2], insertion: insertion))
                var result = input
                for step in plan {
                    let source = try XCTUnwrap(result.firstIndex(of: step.member))
                    let value = result.remove(at: source)
                    result.insert(value, at: source + step.offset)
                }
                XCTAssertEqual(result.filter { $0 < 0 }, [-1, -2, -3, -4])
                XCTAssertEqual(Array(result[insertion..<(insertion + 3)]), [0, 1, 2])
            }
        }
    }
    func testRejectsMissingDuplicateUnknownMembersAndInvalidDestinations() {
        for order: [Int?] in [[0, 0, 1], [0, nil], [0, 1, 3]] {
            XCTAssertNil(MacDockBlockMovePlan.steps(order: order, members: [0, 1], insertion: 0))
        }
        for insertion in [-1, 2] {
            XCTAssertNil(MacDockBlockMovePlan.steps(order: [nil, 0, 1], members: [0, 1], insertion: insertion))
        }
        XCTAssertNil(MacDockBlockMovePlan.steps(order: [0], members: [], insertion: 0))
        XCTAssertNil(MacDockBlockMovePlan.steps(order: [0, 1], members: [0, 0], insertion: 0))
    }
}
