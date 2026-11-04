import AppKit

/// Pure placement policy for a group of native app tiles. Frames use AppKit
/// screen coordinates; slots retain the Dock's native application order.
enum MacDockGroupReorderGeometry {
    struct Slot: Sendable {
        let metric: MetricKind?
        let frame: NSRect
    }

    /// The result indexes the foreign items after all group members are removed.
    /// The first foreign item is Finder, so insertion zero is never a destination.
    /// One dragged circle represents the whole group, regardless of its metric.
    static func insertion(at point: NSPoint, grabbed: MetricKind, members: [MetricKind],
                          slots: [Slot], edge: MacWidgetEdge, previous: Int? = nil) -> Int? {
        guard point.x.isFinite, point.y.isFinite, edge != .top,
              let snapshot = validated(members: members, slots: slots),
              members.contains(grabbed),
              isDockLine(slots, horizontal: edge == .bottom) else { return nil }

        let horizontal = edge == .bottom
        let pointer = tangent(point, horizontal: horizontal)
        let foreign = slots.filter { $0.metric == nil }
        let candidates = 1...snapshot.foreignCount
        // Each foreign icon's center separates the gaps before and after it.
        // An intact group's existing slots all belong to one gap. The grabbed
        // member does not offset the group's destination within that gap.
        let preceding = foreign.prefix { tangent(center($0.frame), horizontal: horizontal) <= pointer }.count
        let candidate = min(max(preceding, candidates.lowerBound), candidates.upperBound)

        guard let previous, candidates.contains(previous), abs(previous - candidate) == 1 else { return candidate }
        let boundaryFrame = foreign[min(previous, candidate)].frame
        let boundary = tangent(center(boundaryFrame), horizontal: horizontal)
        // Only adjacent gaps share a boundary. Hold near that foreign icon's
        // center, but never delay a deliberate move across several gaps.
        let margin = extent(boundaryFrame, horizontal: horizontal) * 0.2
        let crossed = candidate > previous ? pointer > boundary + margin : pointer < boundary - margin
        return crossed ? candidate : previous
    }

    /// Existing placement is anchored at the first owned tile, even for a split
    /// group. This may be zero for an invalid historical order before Finder.
    static func currentInsertion(members: [MetricKind], slots: [Slot]) -> Int? {
        guard let snapshot = validated(members: members, slots: slots),
              let first = snapshot.memberIndices.min() else { return nil }
        return slots[..<first].filter { $0.metric == nil }.count
    }

    /// Contiguity also requires the configured member order, not merely adjacency.
    static func isContiguous(members: [MetricKind], slots: [Slot]) -> Bool {
        guard let snapshot = validated(members: members, slots: slots),
              let first = snapshot.memberIndices.min() else { return false }
        return slots[first..<(first + members.count)].map(\.metric) == members.map(Optional.some)
    }

    /// Choose the smallest displacement when another app separates the group.
    /// A central split can keep either previously chosen outside destination.
    static func repairInsertion(members: [MetricKind], slots: [Slot], preferred: Int? = nil) -> Int? {
        guard let snapshot = validated(members: members, slots: slots) else { return nil }
        var precedingForeign = 0
        var insertions: [Int] = []
        for slot in slots {
            if slot.metric == nil { precedingForeign += 1 }
            else { insertions.append(precedingForeign) }
        }
        // Native order makes this array sorted already.
        let lower = insertions[(insertions.count - 1) / 2]
        let upper = insertions[insertions.count / 2]
        let chosen = preferred.flatMap { (lower...upper).contains($0) ? $0 : nil } ?? lower
        return min(max(chosen, 1), snapshot.foreignCount)
    }

    private struct Snapshot {
        let memberIndices: [Int]
        let foreignCount: Int
    }

    private static func validated(members: [MetricKind], slots: [Slot]) -> Snapshot? {
        guard (1...8).contains(members.count), Set(members).count == members.count,
              slots.count > members.count, slots.count <= 512,
              slots.allSatisfy({ valid($0.frame) }) else { return nil }
        let memberSet = Set(members)
        var seen = Set<MetricKind>()
        var indices: [Int] = []
        var foreignCount = 0
        for (index, slot) in slots.enumerated() {
            guard let metric = slot.metric else { foreignCount += 1; continue }
            guard memberSet.contains(metric), seen.insert(metric).inserted else { return nil }
            indices.append(index)
        }
        guard seen == memberSet, foreignCount > 0,
              isDockLine(slots, horizontal: true) || isDockLine(slots, horizontal: false) else { return nil }
        return Snapshot(memberIndices: indices, foreignCount: foreignCount)
    }

    private static func valid(_ frame: NSRect) -> Bool {
        [frame.origin.x, frame.origin.y, frame.width, frame.height,
         frame.minX, frame.minY, frame.maxX, frame.maxY].allSatisfy(\.isFinite)
            && (8...512).contains(frame.width) && (8...512).contains(frame.height)
    }

    private static func isDockLine(_ slots: [Slot], horizontal: Bool) -> Bool {
        var previous = -CGFloat.infinity
        var commonLower = -CGFloat.infinity
        var commonUpper = CGFloat.infinity
        for slot in slots {
            let frame = slot.frame
            let position = tangent(center(frame), horizontal: horizontal)
            guard position > previous else { return false }
            previous = position
            // A shared normal interval permits magnification while rejecting
            // frames mixed between displays or different Dock rows/columns.
            commonLower = max(commonLower, horizontal ? frame.minY : frame.minX)
            commonUpper = min(commonUpper, horizontal ? frame.maxY : frame.maxX)
        }
        return commonLower < commonUpper
    }

    private static func center(_ frame: NSRect) -> NSPoint {
        NSPoint(x: frame.midX, y: frame.midY)
    }

    private static func tangent(_ point: NSPoint, horizontal: Bool) -> CGFloat {
        horizontal ? point.x : -point.y
    }

    private static func extent(_ frame: NSRect, horizontal: Bool) -> CGFloat {
        horizontal ? frame.width : frame.height
    }
}
