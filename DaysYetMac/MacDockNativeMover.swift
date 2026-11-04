import AppKit

/// Ordering policy for a contiguous block. Indices refer to app items in the
/// Dock; other applications retain their relative order.
enum MacDockBlockMovePlan {
    struct Step: Equatable { let member: Int; let offset: Int }

    static func steps(order: [Int?], members: [Int], insertion: Int) -> [Step]? {
        guard !members.isEmpty, members.count <= 8, Set(members).count == members.count,
              members.allSatisfy({ member in order.filter { $0 == member }.count == 1 }),
              order.compactMap({ $0 }).allSatisfy({ members.contains($0) }) else { return nil }
        let others = order.filter { $0 == nil }.count
        guard (0...others).contains(insertion) else { return nil }
        if Array(order[insertion..<(insertion + members.count)]) == members.map(Optional.some) { return [] }
        let memberIndices = Dictionary(uniqueKeysWithValues: members.enumerated().map { ($0.element, $0.offset) })
        var foreignIndex = 0
        let initial: [(member: Int?, rank: Int)] = order.map { member in
            if let member { return (member, insertion + memberIndices[member]!) }
            defer { foreignIndex += 1 }
            return (nil, foreignIndex + (foreignIndex >= insertion ? members.count : 0))
        }
        // Every requested adjacent exchange removes exactly one inversion in
        // the final order. Foreign ranks already increase, so no exchange can
        // require selecting a foreign app. This attains the minimum key count
        // without cycling already-correct members around the foreign anchor.
        func candidate(reverse: Bool) -> [Step]? {
            var current = initial
            var steps: [Step] = []
            let indices = reverse ? Array((0..<(current.count - 1)).reversed()) : Array(0..<(current.count - 1))
            var exchanged = true
            while exchanged {
                exchanged = false
                for index in indices where current[index].rank > current[index + 1].rank {
                    let member: Int
                    let direction: Int
                    if let owned = current[index].member { member = owned; direction = 1 }
                    else if let owned = current[index + 1].member { member = owned; direction = -1 }
                    else { return nil }
                    current.swapAt(index, index + 1)
                    if let last = steps.last, last.member == member, last.offset.signum() == direction {
                        steps[steps.count - 1] = Step(member: member, offset: last.offset + direction)
                    } else {
                        steps.append(Step(member: member, offset: direction))
                    }
                    exchanged = true
                }
            }
            guard current.map(\.rank) == Array(current.indices),
                  Array(current[insertion..<(insertion + members.count)]).map(\.member) == members.map(Optional.some) else { return nil }
            return steps
        }
        guard let forward = candidate(reverse: false), let reverse = candidate(reverse: true) else { return nil }
        let forwardKeys = forward.reduce(0) { $0 + abs($1.offset) }
        let reverseKeys = reverse.reduce(0) { $0 + abs($1.offset) }
        // A forward scan carries right-moving members continuously, while a
        // reverse scan does the same for left-moving members. Prefer fewer
        // member runs at the same minimum key count; ties keep the forward plan.
        if reverseKeys < forwardKeys || (reverseKeys == forwardKeys && reverse.count < forward.count) { return reverse }
        return forward
    }
}

/// The caller receives positions and its own metric identities only.
struct MacDockNativeLayout {
    struct Item {
        let metric: MetricKind?
        let frame: NSRect
    }
    let dockPID: pid_t
    let edge: MacWidgetEdge
    let items: [Item]
}

/// The native executor accepts only the old order while waiting, or the exact
/// adjacent exchange it requested. Any third order means someone intervened.
enum MacDockNativeMoveValidation {
    enum Observation: Equatable { case waiting, completed, changed }
    enum Completion: Equatable { case verified, verifiedWithSelectionChange, stopped }

    /// Selection is a precondition for the next key, not proof that the last
    /// key moved the right item. The exact observed exchange is that proof.
    /// A hover change inside Dock may require selection to be reacquired; an
    /// unknown/foreign focus, setting change, or physical input still stops us.
    static func completedExchange(observation: Observation, dockHasFocus: Bool,
                                  targetSelected: Bool, foreignUnchanged: Bool,
                                  cancelled: Bool) -> Completion {
        guard observation == .completed, dockHasFocus, foreignUnchanged, !cancelled else { return .stopped }
        return targetSelected ? .verified : .verifiedWithSelectionChange
    }

    static func allowsInsertion(_ insertion: Int, order: [String], members: Set<String>, finder: String) -> Bool {
        let foreign = order.filter { !members.contains($0) }
        return !members.contains(finder) && order.first == finder && foreign.first == finder
            && order.filter { $0 == finder }.count == 1 && insertion >= 1 && insertion <= foreign.count
    }

    static func observe(_ order: [String], before: [String], expected: [String]) -> Observation {
        if order == expected { return .completed }
        return order == before ? .waiting : .changed
    }

    static func adjacentOrder(_ order: [String], member: String, direction: Int) -> [String]? {
        guard direction == 1 || direction == -1, order.filter({ $0 == member }).count == 1,
              let index = order.firstIndex(of: member), order.indices.contains(index + direction) else { return nil }
        var result = order
        result.swapAt(index, index + direction)
        return result
    }
}

enum MacDockNativeGuardPolicy {
    enum State: String { case matched, rejected, unavailable }
    struct Check: Equatable {
        let state: State
        let reason: String
        var axError: Int32? = nil
        static let matched = Check(state: .matched, reason: "matched")
        static func rejected(_ reason: String) -> Check { Check(state: .rejected, reason: reason) }
        static func unavailable(_ reason: String, axError: Int32? = nil) -> Check {
            Check(state: .unavailable, reason: reason, axError: axError)
        }
    }
    static let maximumAttempts = 3
    static let retryBudget: TimeInterval = 0.2

    static func canRetry(_ state: State, attempts: Int, elapsed: TimeInterval,
                         remaining: TimeInterval, interrupted: Bool, mainThread: Bool) -> Bool {
        state == .unavailable && attempts < maximumAttempts && elapsed < retryBudget
            && remaining > 0 && !interrupted && !mainThread
    }
}

enum MacDockNativeSessionPolicy {
    static func check(onConsole: Bool?, loginDone: Bool?, userMatches: Bool?,
                      focusedBundleID: String?, frontmostBundleID: String?) -> MacDockNativeGuardPolicy.Check {
        // A confirmed blocker wins even if another session/focus field is
        // unavailable. Missing information never implies an unlocked session.
        if onConsole == false { return .rejected("off-console") }
        if loginDone == false { return .rejected("login-incomplete") }
        if userMatches == false { return .rejected("different-user") }
        if let frontmostBundleID, blocksInteraction(bundleID: frontmostBundleID) { return .rejected("frontmost-blocked") }
        if let focusedBundleID, blocksInteraction(bundleID: focusedBundleID) { return .rejected("focused-blocked") }
        guard onConsole != nil, loginDone != nil, userMatches != nil else { return .unavailable("session-fields") }
        guard focusedBundleID != nil else { return .unavailable("focused-owner") }
        guard frontmostBundleID != nil else { return .unavailable("frontmost-owner") }
        return .matched
    }

    static func allowsInteraction(onConsole: Bool, loginDone: Bool, userMatches: Bool,
                                  focusedBundleID: String?, frontmostBundleID: String?) -> Bool {
        check(onConsole: onConsole, loginDone: loginDone, userMatches: userMatches,
              focusedBundleID: focusedBundleID, frontmostBundleID: frontmostBundleID).state == .matched
    }

    static func blocksInteraction(bundleID: String) -> Bool {
        let identifier = bundleID.lowercased()
        return identifier == "com.apple.loginwindow"
            || (identifier.hasPrefix("com.apple.") && identifier.contains("screensaver"))
    }
}

#if DAYSYET_DIRECT_DOCK_DRAG && DAYSYET_DOCK_NATIVE_REORDER
import ApplicationServices
import OSLog
import SwiftUI

#if DAYSYET_DOCK_REORDER_PROBE
/// Probe evidence stays in memory. Identities and the saved-record token may
/// contain foreign application paths; never log, display, or persist them.
struct MacDockNativeProbeState {
    let dockPID: pid_t
    let edge: MacWidgetEdge
    let screenFrames: [NSRect]
    let orderedIdentities: [String]
    let metrics: [MetricKind]
    let ownedIdentities: [String]
    let items: [MacDockNativeLayout.Item]
    let ownPinnedMetrics: Set<MetricKind>
    let foreignSavedRecords: Data
    fileprivate let dock: NSRunningApplication
    fileprivate let launchDate: Date?

    var foreignOrder: [String] {
        zip(orderedIdentities, items).compactMap { $0.1.metric == nil ? $0.0 : nil }
    }

    func sameEnvironment(as other: Self) -> Bool {
        guard dockPID == other.dockPID, edge == other.edge, screenFrames == other.screenFrames,
              !dock.isTerminated, !other.dock.isTerminated else { return false }
        if let launchDate, let otherDate = other.launchDate { return launchDate == otherDate }
        return true
    }
}

enum MacDockNativeURLDragValidation {
    static let inspectionMaximumAttempts = 3
    static let inspectionBudget: TimeInterval = 1.5
    enum Outcome: Equatable {
        case moved, unchanged, wrongInsertion, invalidIdentity, environmentChanged, foreignChanged
    }

    static func classify(before: [String], after: [String], members: [String], insertion: Int?,
                         environmentMatches: Bool = true, foreignRecordsMatch: Bool = true) -> Outcome {
        guard environmentMatches else { return .environmentChanged }
        guard !members.isEmpty, members.count <= 8, Set(members).count == members.count,
              Set(before).count == before.count, Set(after).count == after.count,
              members.allSatisfy({ before.contains($0) && after.contains($0) }) else { return .invalidIdentity }
        let owned = Set(members)
        let foreign = before.filter { !owned.contains($0) }
        guard foreignRecordsMatch, foreign == after.filter({ !owned.contains($0) }) else { return .foreignChanged }
        if before == after { return .unchanged }
        guard let insertion, insertion >= 1, insertion <= foreign.count else { return .wrongInsertion }
        var expected = foreign
        expected.insert(contentsOf: members, at: insertion)
        return after == expected ? .moved : .wrongInsertion
    }

    static func cleanupSelection(requested: [MetricKind], members: [MetricKind],
                                 baselinePins: Set<MetricKind>, currentPins: Set<MetricKind>) -> [MetricKind]? {
        let owned = Set(members)
        guard !members.isEmpty, members.count <= 8, owned.count == members.count,
              Set(requested).count == requested.count, Set(requested).isSubset(of: owned),
              baselinePins.isSubset(of: owned), currentPins.isSubset(of: owned),
              Set(requested).isDisjoint(with: baselinePins) else { return nil }
        return requested.filter { currentPins.contains($0) }
    }

    static func fixtureIdentityIsConsistent(bundleIdentifier: String?, exactPath: String?,
                                            expectedPathsByBundleIdentifier: [String: String]) -> Bool {
        guard let bundleIdentifier, let expected = expectedPathsByBundleIdentifier[bundleIdentifier] else { return true }
        return exactPath == expected
    }

    static func canRetryInspection(state: MacDockNativeGuardPolicy.State, attempts: Int,
                                   elapsed: TimeInterval, interrupted: Bool) -> Bool {
        state == .unavailable && !interrupted && attempts < inspectionMaximumAttempts
            && elapsed >= 0 && elapsed < inspectionBudget
    }

    static func canRetryCleanupRead(state: MacDockNativeGuardPolicy.State, attempts: Int,
                                    elapsed: TimeInterval, remaining: TimeInterval, interrupted: Bool) -> Bool {
        state == .unavailable && !interrupted && attempts < 3 && elapsed >= 0 && elapsed < 0.6 && remaining > 0.025
    }

    enum RemovalObservation: Equatable { case waiting, completed, changed }
    static func observeRemoval(order: [String], pins: Set<String>, previousOrder: [String], previousPins: Set<String>,
                               member: String, foreignUnchanged: Bool) -> RemovalObservation {
        guard foreignUnchanged, previousOrder.filter({ $0 == member }).count == 1, previousPins.contains(member) else { return .changed }
        let removedOrder = previousOrder.filter { $0 != member }
        let removedPins = previousPins.subtracting([member])
        guard order == previousOrder || order == removedOrder, pins == previousPins || pins == removedPins else { return .changed }
        return order == removedOrder && pins == removedPins ? .completed : .waiting
    }

    struct CleanupMenuProgress {
        enum Action: Equatable { case wait, openOptions, remove, stop }
        private var optionsRequested = false
        private var removalRequested = false
        private var interrupted = false
        mutating func next(optionsAvailable: Bool, commandAvailable: Bool, cancelled: Bool) -> Action {
            interrupted = interrupted || cancelled
            guard !interrupted, !removalRequested else { return .stop }
            if commandAvailable { removalRequested = true; return .remove }
            if optionsAvailable, !optionsRequested { optionsRequested = true; return .openOptions }
            return .wait
        }
    }
}

private final class MacDockNativeProbeReadDelivery<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var accepting = true
    private var value: Value?

    var isAccepting: Bool {
        lock.lock(); defer { lock.unlock() }
        return accepting
    }

    func deliver(_ value: Value) {
        lock.lock()
        guard accepting else { lock.unlock(); return }
        self.value = value
        lock.unlock()
        semaphore.signal()
    }

    func wait(until deadline: TimeInterval) -> Value? {
        let remaining = max(0, deadline - ProcessInfo.processInfo.systemUptime)
        let ready = semaphore.wait(timeout: .now() + remaining) == .success
        lock.lock(); defer { lock.unlock() }
        accepting = false
        defer { value = nil }
        return ready ? value : nil
    }
}
#endif

enum MacDockNativeInputPolicy {
    static let cancellingEvents: NSEvent.EventTypeMask = [
        .keyDown, .keyUp, .flagsChanged, .leftMouseDown, .leftMouseUp,
        .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
        .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel
    ]
}

private enum MacDockNativeDiagnostics {
    static let log = Logger(subsystem: "com.hinoshiba.daysyet", category: "native-dock-order")

    static func record(success: Bool, ownedCount: Int, stage: String, planned: Int, posted: Int = 0,
                       completed: Int, selectionChanges: Int, guardContext: String = "none",
                       began: TimeInterval, reason: String, runs: Int = 0, selectionWrites: Int = 0,
                       orderReadMS: Int = 0, dispatchMS: Int = 0, savedReadMS: Int = 0) {
        let milliseconds = Int(max(0, ProcessInfo.processInfo.systemUptime - began) * 1_000)
        // The reason and stage are fixed strings from this file. Do not pass
        // accessibility text, paths, physical keys, or pointer coordinates.
        log.notice("batch success=\(success) owned=\(ownedCount) stage=\(stage, privacy: .public) guard=\(guardContext, privacy: .public) planned=\(planned) posted=\(posted) completed=\(completed) runs=\(runs) selectionWrites=\(selectionWrites) selectionChanges=\(selectionChanges) orderReadMS=\(orderReadMS) dispatchMS=\(dispatchMS) savedReadMS=\(savedReadMS) elapsedMS=\(milliseconds) reason=\(reason, privacy: .public)")
    }

    static func guardRead(_ check: MacDockNativeGuardPolicy.Check, context: String, attempts: Int = 1) {
        log.notice("guard context=\(context, privacy: .public) state=\(check.state.rawValue, privacy: .public) reason=\(check.reason, privacy: .public) axError=\(check.axError ?? 0) attempts=\(attempts)")
    }

#if DAYSYET_DOCK_REORDER_PROBE
    static func urlProbeRead(stage: String, check: MacDockNativeGuardPolicy.Check, attempt: Int, began: TimeInterval) {
        let elapsed = Int(max(0, ProcessInfo.processInfo.systemUptime - began) * 1_000)
        // All strings are fixed stage/reason identifiers from this file.
        log.notice("url-probe-read stage=\(stage, privacy: .public) state=\(check.state.rawValue, privacy: .public) reason=\(check.reason, privacy: .public) axError=\(check.axError ?? 0) attempt=\(attempt) elapsedMS=\(elapsed)")
    }
#endif
}

enum MacDockNativeKeySequence {
    static let marker: Int64 = 0x4459534E41544956
    /// Keep key-specific flags generated by CoreGraphics (Fn, numeric pad and
    /// left/right modifier bits). Replacing the entire flags field erases them.
    static func make(key: CGKeyCode, modifier: CGKeyCode? = nil, flags: CGEventFlags = []) -> [CGEvent]? {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return nil }
        source.localEventsSuppressionInterval = 0
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else { return nil }
        var events: [CGEvent] = []
        var release: CGEvent?
        if let modifier {
            guard let press = CGEvent(keyboardEventSource: source, virtualKey: modifier, keyDown: true),
                  let lift = CGEvent(keyboardEventSource: source, virtualKey: modifier, keyDown: false) else { return nil }
            press.flags.formUnion(flags)
            events.append(press)
            release = lift
        }
        down.flags.formUnion(flags)
        up.flags.formUnion(flags)
        events += [down, up]
        if let release { events.append(release) }
        for event in events {
            event.timestamp = CGEventTimestamp(DispatchTime.now().uptimeNanoseconds)
            event.setIntegerValueField(.keyboardEventKeyboardType, value: Int64(source.keyboardType))
            event.setIntegerValueField(.eventSourceUserData, value: marker)
        }
        return events
    }
}

private final class MacDockNativeCancellation: @unchecked Sendable {
    enum Reason: Equatable { case requested, userInput, environment }
    private let lock = NSLock()
    private var storedReason: Reason?
    var reason: Reason? {
        lock.lock()
        defer { lock.unlock() }
        return storedReason
    }
    func cancel(_ reason: Reason) {
        lock.lock()
        defer { lock.unlock() }
        if storedReason == nil || reason == .userInput { storedReason = reason }
    }
}

/// Native keyboard ordering experiment. The shortcut strategy uses an enabled
/// Control-F3 binding, then sends ordering keys only after the system-wide AX
/// focus belongs to Dock and the selected item is our exact helper. No pointer
/// is warped, and no Dock preferences are written or reloaded.
@MainActor
final class MacDockNativeMover {
    enum Selection: String, CaseIterable {
        case selected, focused, focusedList, selectedChildren, selectedChildrenBalanced, focusedElement, frontmost, dockShortcut, dockShortcutHID, dockShortcutMain
    }
    private let queue = DispatchQueue(label: "com.hinoshiba.daysyet.native-dock-order")
    private(set) var busy = false
    private var operation: MacDockNativeCancellation?
    private var stopObservingInput: (() -> Void)?
    private var lastLayoutGate: MacDockNativeGuardPolicy.Check?
#if DAYSYET_DOCK_REORDER_PROBE
    private(set) var lastURLDragInspectionFailure: String?
#endif
    // A controller and the diagnostic window have different mover instances.
    // Native keyboard/menu mutations must still have a single process owner.
    private static var mutationLease: UUID?

    static var nativeURLProbeCanStart: Bool { mutationLease == nil }

    private static func acquireMutationLease() -> UUID? {
        guard mutationLease == nil else { return nil }
        let lease = UUID()
        mutationLease = lease
        return lease
    }

    private static func releaseMutationLease(_ lease: UUID) {
        if mutationLease == lease { mutationLease = nil }
    }

    private struct Environment {
        // System processes may have no Launch Services launch date. Retain
        // the verified process lifetime instead of requiring that optional date.
        let dock: NSRunningApplication
        let pid: pid_t
        let launchDate: Date?
        let edge: MacWidgetEdge
        let screenFrames: [NSRect]
        var primaryMaxY: CGFloat { screenFrames[0].maxY }
    }

    private struct EnvironmentRead {
        let check: MacDockNativeGuardPolicy.Check
        var value: Environment? = nil
    }

    func cancel() { operation?.cancel(.requested) }

    func readLayout(metrics: [MetricKind], edge: MacWidgetEdge,
                    completion: @escaping (MacDockNativeLayout?) -> Void) {
        guard !busy else { recordLayoutGate(.rejected("busy")); completion(nil); return }
        guard let paths = Self.helperPaths(metrics) else {
            recordLayoutGate(.rejected("invalid-members")); completion(nil); return
        }
        let cancellation = MacDockNativeCancellation()
        operation = cancellation
        busy = true
        queue.async { [self] in
            let deadline = ProcessInfo.processInfo.systemUptime + 1
            let read = Self.checkedEnvironment(edge: edge, cancellation: cancellation, deadline: deadline)
            var gate = read.check
            var layout: MacDockNativeLayout?
            if let environment = read.value {
                layout = Self.snapshot(pid: environment.pid).flatMap { Self.layout($0, paths: paths, environment: environment) }
                gate = Self.checkedEnvironment(edge: edge, expected: environment,
                    cancellation: cancellation, deadline: deadline).check
                if gate.state == .matched && layout == nil { gate = .unavailable("layout-items") }
            }
            let result = gate.state == .matched && cancellation.reason == nil ? layout : nil
            let finalGate = gate
            DispatchQueue.main.async { [self] in
                operation = nil
                busy = false
                recordLayoutGate(finalGate)
                completion(cancellation.reason == nil ? result : nil)
            }
        }
    }

    private func recordLayoutGate(_ check: MacDockNativeGuardPolicy.Check) {
        guard lastLayoutGate != check else { return }
        lastLayoutGate = check
        MacDockNativeDiagnostics.guardRead(check, context: "layout-read")
    }

#if DAYSYET_DOCK_REORDER_PROBE
    func inspectURLDrag(metrics: [MetricKind], edge: MacWidgetEdge,
                        completion: @escaping (MacDockNativeProbeState?) -> Void) {
        let began = ProcessInfo.processInfo.systemUptime
        func reject(_ reason: String) {
            lastURLDragInspectionFailure = "entry: \(reason)"
            MacDockNativeDiagnostics.urlProbeRead(stage: "entry", check: .rejected(reason), attempt: 0, began: began)
            completion(nil)
        }
        guard !busy else { reject("busy"); return }
        guard let paths = Self.probePaths(metrics) else { reject("invalid-members"); return }
        lastURLDragInspectionFailure = nil
        let cancellation = MacDockNativeCancellation()
        operation = cancellation
        busy = true
        queue.async { [self] in
            let deadline = began + MacDockNativeURLDragValidation.inspectionBudget
            var expected: Environment?
            var attempt = 0
            var result = URLDragStateRead(stage: "entry", check: .unavailable("not-started"))
            repeat {
                attempt += 1
                let read = Self.probeEnvironment(edge: edge, expected: expected,
                    cancellation: cancellation, deadline: deadline)
                if let environment = read.value {
                    // Retain the first verified Dock lifetime across retries.
                    // A replacement process must never reset the comparison.
                    if expected == nil { expected = environment }
                    result = Self.readURLDragStateAttempt(metrics: metrics, paths: paths, environment: environment,
                        cancellation: cancellation, deadline: deadline, validateBefore: false, boundedMainRead: true)
                } else {
                    result = URLDragStateRead(stage: "environment-before", check: read.check)
                }
                MacDockNativeDiagnostics.urlProbeRead(stage: result.stage, check: result.check, attempt: attempt, began: began)
                let now = ProcessInfo.processInfo.systemUptime
                guard Self.urlProbeMayRetry(result, attempts: attempt, began: began, cancellation: cancellation),
                      deadline - now > 0.04 else { break }
                Thread.sleep(forTimeInterval: 0.04)
            } while true
            let final = result
            let loop = CFRunLoopGetMain()
            CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) {
                MainActor.assumeIsolated { [self] in
                    self.operation = nil
                    self.busy = false
                    if cancellation.reason != nil {
                        self.lastURLDragInspectionFailure = "completion: cancelled"
                        completion(nil)
                    } else {
                        self.lastURLDragInspectionFailure = final.value == nil ? final.failureDescription : nil
                        completion(final.value)
                    }
                }
            }
            CFRunLoopWakeUp(loop)
        }
    }

    /// Only metrics absent from the pre-drag pin set may be removed. The
    /// caller keeps automatic repair and registration cleanup suspended until
    /// a subsequent inspection proves that all newly added pins are gone.
    func cleanupURLDragPins(metrics: [MetricKind], before: MacDockNativeProbeState,
                            completion: @escaping (Bool, MacDockNativeProbeState?, String) -> Void) {
        runURLDragPinCleanup(metrics: metrics, reference: before, recovery: false, completion: completion)
    }

    /// Explicit recovery-button action after a previously interrupted probe.
    /// Unlike normal cleanup, it authorizes only the pins in this confirmed
    /// snapshot, which must still match in full before the first menu action.
    func recoverURLDragPins(metrics: [MetricKind], confirmed: MacDockNativeProbeState,
                            completion: @escaping (Bool, MacDockNativeProbeState?, String) -> Void) {
        runURLDragPinCleanup(metrics: metrics, reference: confirmed, recovery: true, completion: completion)
    }

    private func runURLDragPinCleanup(metrics: [MetricKind], reference: MacDockNativeProbeState, recovery: Bool,
                                      completion: @escaping (Bool, MacDockNativeProbeState?, String) -> Void) {
        let requested = Set(metrics)
        guard !busy, AXIsProcessTrusted(), CGPreflightPostEventAccess(), NSEvent.pressedMouseButtons == 0,
              requested.count == metrics.count, requested.isSubset(of: Set(reference.metrics)),
              recovery ? requested.isSubset(of: reference.ownPinnedMetrics) : requested.isDisjoint(with: reference.ownPinnedMetrics),
              let paths = Self.probePaths(reference.metrics), let lease = Self.acquireMutationLease() else {
            completion(false, nil, "解除対象・権限・Dockの操作状態を確認できません。")
            return
        }
        let cancellation = MacDockNativeCancellation()
        guard beginObservingInput(cancellation) else {
            Self.releaseMutationLease(lease)
            completion(false, nil, "ユーザー操作の中断を確認できないため、固定を解除しませんでした。")
            return
        }
        operation = cancellation
        busy = true
        queue.async { [self] in
            let environment = Environment(dock: reference.dock, pid: reference.dockPID,
                launchDate: reference.launchDate, edge: reference.edge, screenFrames: reference.screenFrames)
            let deadline = ProcessInfo.processInfo.systemUptime + 10
            let result = Self.performURLDragPinCleanup(metrics: metrics, reference: reference, recovery: recovery,
                paths: paths, environment: environment, cancellation: cancellation, deadline: deadline)
            DispatchQueue.main.async { [self] in
                stopObservingInput?()
                stopObservingInput = nil
                operation = nil
                busy = false
                Self.releaseMutationLease(lease)
                let verified = cancellation.reason == nil && result.success
                completion(verified, cancellation.reason == nil ? result.state : nil,
                    verified ? "指定した試験用の固定だけを解除しました。"
                        : (result.success ? "固定解除後の状態を確定できませんでした。" : result.message))
            }
        }
    }

    private static func probePaths(_ metrics: [MetricKind]) -> [String: MetricKind]? {
        guard !metrics.isEmpty, Set(metrics).count == metrics.count,
              let values = MacDockNativeURLProbeFixtures.paths(metrics: metrics), values.count == metrics.count,
              Set(values.values).count == metrics.count else { return nil }
        return Dictionary(uniqueKeysWithValues: values.map { ($0.value, $0.key) })
    }
#endif

    private func beginObservingInput(_ cancellation: MacDockNativeCancellation) -> Bool {
        let started = ProcessInfo.processInfo.systemUptime
        let observe: (NSEvent) -> Void = { event in
            guard event.timestamp >= started,
                  event.cgEvent?.getIntegerValueField(.eventSourceUserData) != MacDockNativeKeySequence.marker else { return }
            cancellation.cancel(.userInput)
        }
        let global = NSEvent.addGlobalMonitorForEvents(matching: MacDockNativeInputPolicy.cancellingEvents, handler: observe)
        let local = NSEvent.addLocalMonitorForEvents(matching: MacDockNativeInputPolicy.cancellingEvents) { event in
            observe(event); return event
        }
        guard let global, let local else {
            if let global { NSEvent.removeMonitor(global) }
            if let local { NSEvent.removeMonitor(local) }
            return false
        }
        let screens = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { _ in cancellation.cancel(.environment) }
        let workspace = NSWorkspace.shared.notificationCenter
        let observers = [NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.screensDidSleepNotification,
                         NSWorkspace.willSleepNotification].map { name in
            workspace.addObserver(forName: name, object: nil, queue: .main) { _ in cancellation.cancel(.environment) }
        }
        stopObservingInput = {
            NSEvent.removeMonitor(global)
            NSEvent.removeMonitor(local)
            NotificationCenter.default.removeObserver(screens)
            for observer in observers { workspace.removeObserver(observer) }
        }
        return true
    }

    func reorder(metrics: [MetricKind], edge: MacWidgetEdge, insertion: Int,
                 completion: @escaping (Bool, MacDockNativeLayout?, String) -> Void) {
        guard !MacDockRegistrationCleanup.nativeURLProbePending else {
            completion(false, nil, "URLドラッグ試験が完了するまで、通常の並べ替えは停止しています。")
            return
        }
        let began = ProcessInfo.processInfo.systemUptime
        guard !busy, AXIsProcessTrusted(), CGPreflightPostEventAccess(), NSEvent.pressedMouseButtons == 0,
              let paths = Self.helperPaths(metrics) else {
            MacDockNativeDiagnostics.record(success: false, ownedCount: metrics.count, stage: "start",
                planned: 0, completed: 0, selectionChanges: 0, began: began, reason: "preflight rejected")
            completion(false, nil, "権限・Dock・操作状態を確認してください。")
            return
        }
        let read = Self.environmentRead(edge: edge)
        guard let environment = read.value else {
            MacDockNativeDiagnostics.guardRead(read.check, context: "batch-start")
            completion(false, nil, "Dockまたは操作できるデスクトップを確認できないため、移動しませんでした。")
            return
        }
        guard let lease = Self.acquireMutationLease() else {
            MacDockNativeDiagnostics.guardRead(.rejected("mutation-busy"), context: "batch-start")
            completion(false, nil, "別のDock操作が完了するまで、移動を開始しませんでした。")
            return
        }
        let cancellation = MacDockNativeCancellation()
        let started = ProcessInfo.processInfo.systemUptime
        let mask = MacDockNativeInputPolicy.cancellingEvents
        // Store only a cancellation bit. No physical key codes, characters,
        // mouse positions, or other application's input are retained.
        let observe: (NSEvent) -> Void = { event in
            guard event.timestamp >= started,
                  event.cgEvent?.getIntegerValueField(.eventSourceUserData) != MacDockNativeKeySequence.marker else { return }
            cancellation.cancel(.userInput)
        }
        let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: observe)
        let local = NSEvent.addLocalMonitorForEvents(matching: mask) { event in observe(event); return event }
        guard let global, let local else {
            if let global { NSEvent.removeMonitor(global) }
            if let local { NSEvent.removeMonitor(local) }
            Self.releaseMutationLease(lease)
            MacDockNativeDiagnostics.record(success: false, ownedCount: metrics.count, stage: "input-monitor",
                planned: 0, completed: 0, selectionChanges: 0, began: began, reason: "input monitoring unavailable")
            completion(false, nil, "ユーザー操作の中断を確認できないため、移動しませんでした。")
            return
        }
        let screens = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { _ in cancellation.cancel(.environment) }
        let workspace = NSWorkspace.shared.notificationCenter
        let workspaceObservers = [NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.screensDidSleepNotification,
                                  NSWorkspace.willSleepNotification].map { name in
            workspace.addObserver(forName: name, object: nil, queue: .main) { _ in cancellation.cancel(.environment) }
        }
        // Observer tokens are confined to the main actor instead of passing
        // non-Sendable Foundation objects through the native worker queue.
        stopObservingInput = {
            NSEvent.removeMonitor(global)
            NSEvent.removeMonitor(local)
            NotificationCenter.default.removeObserver(screens)
            for observer in workspaceObservers { workspace.removeObserver(observer) }
        }
        operation = cancellation
        busy = true
        let members = metrics.map(Self.helperPath)
        queue.async { [self] in
            let result = Self.performReorder(members: members, paths: paths, insertion: insertion,
                                             environment: environment, cancellation: cancellation)
            // Read positions after Escape has left keyboard navigation, so the
            // returned layout does not intentionally retain its magnification.
            let layoutGate = Self.checkedEnvironment(edge: edge, expected: environment,
                cancellation: cancellation, deadline: began + 12, context: "final-layout")
            let layout = layoutGate.check.state == .matched
                ? Self.snapshot(pid: environment.pid).flatMap { Self.layout($0, paths: paths, environment: environment) }
                : nil
            DispatchQueue.main.async { [self] in
                stopObservingInput?()
                stopObservingInput = nil
                operation = nil
                busy = false
                Self.releaseMutationLease(lease)
                MacDockNativeDiagnostics.log.notice("batch finalized success=\(result.success) layout=\(layout != nil)")
                completion(result.success, layout, result.message)
            }
        }
    }

    private static func environmentRead(edge: MacWidgetEdge, expected: Environment? = nil) -> EnvironmentRead {
        let session = sessionCheck()
        guard session.state == .matched else { return EnvironmentRead(check: session) }
        guard edge != .top else { return EnvironmentRead(check: .rejected("unsupported-edge")) }
        let frames = NSScreen.screens.map(\.frame)
        guard !frames.isEmpty, frames.allSatisfy({ frame in
            [frame.minX, frame.minY, frame.maxX, frame.maxY].allSatisfy(\.isFinite)
                && frame.width > 0 && frame.height > 0
        }) else { return EnvironmentRead(check: .unavailable("screens")) }
        if let expected, frames != expected.screenFrames { return EnvironmentRead(check: .rejected("screens-changed")) }
        if let expected, expected.dock.isTerminated { return EnvironmentRead(check: .rejected("dock-terminated")) }
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
            .first(where: { !$0.isTerminated && $0.bundleURL?.path == "/System/Library/CoreServices/Dock.app" }) else {
            return EnvironmentRead(check: .unavailable("dock-process"))
        }
        if let expected, dock.processIdentifier != expected.pid { return EnvironmentRead(check: .rejected("dock-pid-changed")) }
        let launchDate = dock.launchDate
        if let before = expected?.launchDate, let now = launchDate, before != now {
            return EnvironmentRead(check: .rejected("dock-launch-changed"))
        }
        guard CFPreferencesAppSynchronize("com.apple.dock" as CFString) else {
            return EnvironmentRead(check: .unavailable("dock-preferences"))
        }
        let orientation = CFPreferencesCopyAppValue("orientation" as CFString, "com.apple.dock" as CFString) as? String
        guard let configured = MacSystemDockLocation.configuredEdge(orientation: orientation) else {
            return EnvironmentRead(check: .unavailable("dock-orientation"))
        }
        guard configured == edge else { return EnvironmentRead(check: .rejected("dock-edge-changed")) }
        return EnvironmentRead(check: .matched, value: Environment(dock: dock, pid: dock.processIdentifier,
            launchDate: launchDate, edge: edge, screenFrames: frames))
    }

    private nonisolated static func onMain<T>(_ body: @MainActor () -> T) -> T {
        if Thread.isMainThread { return MainActor.assumeIsolated { body() } }
        return DispatchQueue.main.sync { MainActor.assumeIsolated { body() } }
    }

    private nonisolated static func priorityInterruption(_ cancellation: MacDockNativeCancellation,
                                                         deadline: TimeInterval, forMutation: Bool) -> MacDockNativeGuardPolicy.Check? {
        if let reason = cancellation.reason {
            switch reason {
            case .requested: return .rejected("cancelled")
            case .userInput: return .rejected("physical-input")
            case .environment: return .rejected("environment-notification")
            }
        }
        guard ProcessInfo.processInfo.systemUptime < deadline else { return .rejected("deadline") }
        guard AXIsProcessTrusted() else { return .rejected("accessibility-permission") }
        if forMutation {
            guard CGPreflightPostEventAccess() else { return .rejected("event-permission") }
            guard onMain({ NSEvent.pressedMouseButtons == 0 }) else {
                cancellation.cancel(.userInput)
                return .rejected("physical-input")
            }
        }
        return nil
    }

    /// Retry reads only, never a posted key. A fresh matched result is required
    /// after a transient failure; neither the last success nor an unknown
    /// session authorizes input. Main-thread callers get exactly one read.
    private nonisolated static func checkedEnvironment(edge: MacWidgetEdge, expected: Environment? = nil,
                                                       cancellation: MacDockNativeCancellation, deadline: TimeInterval,
                                                       forMutation: Bool = false, context: String? = nil) -> EnvironmentRead {
        let began = ProcessInfo.processInfo.systemUptime
        var attempts = 0
        var result = EnvironmentRead(check: .unavailable("environment"))
        repeat {
            if let priority = priorityInterruption(cancellation, deadline: deadline, forMutation: forMutation) {
                result = EnvironmentRead(check: priority); break
            }
            if attempts > 0 && ProcessInfo.processInfo.systemUptime - began >= MacDockNativeGuardPolicy.retryBudget {
                result = EnvironmentRead(check: .unavailable("environment-read-budget")); break
            }
            attempts += 1
            result = onMain { environmentRead(edge: edge, expected: expected) }
            if let priority = priorityInterruption(cancellation, deadline: deadline, forMutation: forMutation) {
                result = EnvironmentRead(check: priority); break
            }
            let now = ProcessInfo.processInfo.systemUptime
            if result.check.state != .rejected && attempts > 1 && now - began >= MacDockNativeGuardPolicy.retryBudget {
                result = EnvironmentRead(check: .unavailable("environment-read-budget")); break
            }
            guard MacDockNativeGuardPolicy.canRetry(result.check.state, attempts: attempts, elapsed: now - began,
                remaining: deadline - now, interrupted: cancellation.reason != nil, mainThread: Thread.isMainThread) else { break }
            Thread.sleep(forTimeInterval: min(0.025, deadline - now,
                MacDockNativeGuardPolicy.retryBudget - (now - began)))
        } while true
        if let context, result.check.state != .matched || attempts > 1 {
            MacDockNativeDiagnostics.guardRead(result.check, context: context, attempts: attempts)
        }
        return result
    }

    private nonisolated static func sessionAllowsInteraction() -> Bool {
        sessionCheck().state == .matched
    }

    private nonisolated static func sessionCheck() -> MacDockNativeGuardPolicy.Check {
        // Only public session keys are used. On-console alone does not prove an
        // unlocked desktop, so also inspect the currently focused application.
        guard AXIsProcessTrusted() else { return .rejected("accessibility-permission") }
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        let onConsole = session?[kCGSessionOnConsoleKey as String] as? Bool
        let loginDone = session?[kCGSessionLoginDoneKey as String] as? Bool
        let userMatches = (session?[kCGSessionUserIDKey as String] as? NSNumber).map { $0.uint32Value == getuid() }
        let frontmost = onMain { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
        let initial = MacDockNativeSessionPolicy.check(onConsole: onConsole, loginDone: loginDone,
            userMatches: userMatches, focusedBundleID: nil, frontmostBundleID: frontmost)
        if initial.state == .rejected { return initial }
        guard session != nil, onConsole != nil, loginDone != nil, userMatches != nil else { return .unavailable("session-fields") }
        let system = AXUIElementCreateSystemWide()
        _ = AXUIElementSetMessagingTimeout(system, 0.025)
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &value)
        guard AXIsProcessTrusted() else { return .rejected("accessibility-permission") }
        guard status == .success, let focused = value, CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            return .unavailable("focused-application", axError: status.rawValue)
        }
        var pid: pid_t = 0
        let pidStatus = AXUIElementGetPid(focused as! AXUIElement, &pid)
        guard pidStatus == .success, pid > 1 else { return .unavailable("focused-pid", axError: pidStatus.rawValue) }
        let focusedBundleID = onMain { NSRunningApplication(processIdentifier: pid)?.bundleIdentifier }
        return MacDockNativeSessionPolicy.check(onConsole: onConsole, loginDone: loginDone, userMatches: userMatches,
            focusedBundleID: focusedBundleID, frontmostBundleID: onMain { NSWorkspace.shared.frontmostApplication?.bundleIdentifier })
    }

    private nonisolated static func helperPath(_ metric: MetricKind) -> String {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/DaysYetDock_\(metric.rawValue).app")
            .resolvingSymlinksInPath().standardizedFileURL.path
    }

    private nonisolated static func helperPaths(_ metrics: [MetricKind]) -> [String: MetricKind]? {
        guard !metrics.isEmpty, metrics.count <= 8, Set(metrics).count == metrics.count else { return nil }
        return Dictionary(uniqueKeysWithValues: metrics.map { (helperPath($0), $0) })
    }

    private nonisolated static func validMembers(_ items: [Item], paths: [String: MetricKind]) -> Bool {
        let actual = items.map(\.path)
        guard paths.keys.allSatisfy({ path in actual.filter { $0 == path }.count == 1 }) else { return false }
        // A profile change may leave an old helper visible briefly. It must not
        // silently turn into a foreign item during an in-flight operation.
        let allHelpers = Set(MetricKind.allCases.map(helperPath))
        return actual.allSatisfy { !allHelpers.contains($0) || paths[$0] != nil }
    }

    private nonisolated static func layout(_ items: [Item], paths: [String: MetricKind],
                                           environment: Environment) -> MacDockNativeLayout? {
        guard validMembers(items, paths: paths) else { return nil }
        var result: [MacDockNativeLayout.Item] = []
        for item in items {
            guard let frame = item.quartzFrame else { return nil }
            let converted = NSRect(x: frame.minX, y: environment.primaryMaxY - frame.maxY,
                                   width: frame.width, height: frame.height)
            result.append(.init(metric: paths[item.path], frame: converted))
        }
        return MacDockNativeLayout(dockPID: environment.pid, edge: environment.edge, items: result)
    }

    func step(metric: MetricKind, edge: MacWidgetEdge, forward: Bool, selection: Selection = .selected,
              completion: @escaping (String) -> Void) {
        guard !MacDockRegistrationCleanup.nativeURLProbePending else {
            completion("URLドラッグ試験が完了するまで、通常の並べ替えは停止しています。")
            return
        }
        guard !busy, AXIsProcessTrusted(), Self.sessionAllowsInteraction(), NSEvent.pressedMouseButtons == 0,
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
                .first(where: { $0.bundleURL?.path == "/System/Library/CoreServices/Dock.app" }),
              let lease = Self.acquireMutationLease() else {
            completion("権限・Dock・操作状態を確認してください。")
            return
        }
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/DaysYetDock_\(metric.rawValue).app")
            .resolvingSymlinksInPath().standardizedFileURL.path
        let pid = dock.processIdentifier
        let key: CGKeyCode = edge == .bottom ? (forward ? 124 : 123) : (forward ? 125 : 126)
        busy = true
        queue.async { [weak self] in
            let result = Self.performStep(path: url, pid: pid, key: key, forward: forward, selection: selection)
            DispatchQueue.main.async {
                self?.busy = false
                Self.releaseMutationLease(lease)
                completion(result)
            }
        }
    }

    func unpin(metric: MetricKind, completion: @escaping (String) -> Void) {
        guard !MacDockRegistrationCleanup.nativeURLProbePending else {
            completion("URLドラッグ試験の固定解除は、専用の試験画面から行ってください。")
            return
        }
        guard !busy, AXIsProcessTrusted(), Self.sessionAllowsInteraction(),
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
                .first(where: { $0.bundleURL?.path == "/System/Library/CoreServices/Dock.app" }),
              let lease = Self.acquireMutationLease() else {
            completion("権限とDockの状態を確認してください。"); return
        }
        let path = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/DaysYetDock_\(metric.rawValue).app")
            .resolvingSymlinksInPath().standardizedFileURL.path
        let pid = dock.processIdentifier
        busy = true
        queue.async { [weak self] in
            let result = Self.removePin(path: path, pid: pid)
            DispatchQueue.main.async {
                self?.busy = false
                Self.releaseMutationLease(lease)
                completion(result)
            }
        }
    }

    private nonisolated static func pinned(_ path: String) -> Bool? {
        let domain = "com.apple.dock" as CFString
        guard CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else { return nil }
        let entries = CFPreferencesCopyValue("persistent-apps" as CFString, domain,
            kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [[String: Any]] ?? []
        return entries.contains { entry in
            guard let data = entry["tile-data"] as? [String: Any], let file = data["file-data"] as? [String: Any],
                  let raw = file["_CFURLString"] as? String, let url = URL(string: raw), url.isFileURL else { return false }
            return url.resolvingSymlinksInPath().standardizedFileURL.path == path
        }
    }

    private nonisolated static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private nonisolated static func focusDockWithStandardShortcut(hid: Bool, mainThread: Bool,
                                                                 settleDelay: TimeInterval = 0.3,
                                                                 eventInterval: TimeInterval = 0.012,
                                                                 guardContext: String? = nil,
                                                                 cancellation: MacDockNativeCancellation? = nil,
                                                                 deadline: TimeInterval = .greatestFiniteMagnitude) -> Bool {
        // Symbolic hotkey 8 is Dock focus. Fail closed for disabled/custom
        // bindings; never send an arbitrary saved key combination globally.
        guard AXIsProcessTrusted(), CGPreflightPostEventAccess(),
              !CGEventSource.buttonState(.combinedSessionState, button: .left),
              let hotkeys = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString,
                  "com.apple.symbolichotkeys" as CFString) as? [String: Any],
              let entry = hotkeys["8"] as? [String: Any], entry["enabled"] as? Bool == true,
              let value = entry["value"] as? [String: Any], value["type"] as? String == "standard",
              let parameters = value["parameters"] as? [NSNumber], parameters.count == 3,
              parameters[0].intValue == 65535, parameters[1].intValue == 99,
              [262144, 8650752].contains(parameters[2].intValue),
              systemKeyStroke(99, modifier: 59, flags: CGEventFlags(rawValue: parameters[2].uint64Value),
                              hid: hid, mainThread: mainThread, eventInterval: eventInterval,
                              guardContext: guardContext, cancellation: cancellation, deadline: deadline) else { return false }
        if settleDelay > 0 { Thread.sleep(forTimeInterval: settleDelay) }
        return true
    }

    private nonisolated static func systemKeyStroke(_ key: CGKeyCode, modifier: CGKeyCode? = nil,
                                                    flags: CGEventFlags = [], hid: Bool = false,
                                                    mainThread: Bool = false, eventInterval: TimeInterval = 0.012,
                                                    guardContext: String? = nil,
                                                    cancellation: MacDockNativeCancellation? = nil,
                                                    deadline: TimeInterval = .greatestFiniteMagnitude) -> Bool {
        if mainThread && !Thread.isMainThread {
            return DispatchQueue.main.sync {
                systemKeyStroke(key, modifier: modifier, flags: flags, hid: hid, eventInterval: eventInterval,
                                guardContext: guardContext, cancellation: cancellation, deadline: deadline)
            }
        }
        let held = CGEventSource.flagsState(.hidSystemState).intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
        guard held.isEmpty, AXIsProcessTrusted(), CGPreflightPostEventAccess() else { return false }
        let session = sessionCheck()
        guard session.state == .matched else {
            if let guardContext { MacDockNativeDiagnostics.guardRead(session, context: guardContext) }
            return false
        }
        guard let events = MacDockNativeKeySequence.make(key: key, modifier: modifier, flags: flags) else { return false }
        if let cancellation, let priority = priorityInterruption(cancellation, deadline: deadline, forMutation: true) {
            if let guardContext { MacDockNativeDiagnostics.guardRead(priority, context: guardContext) }
            return false
        }
        guard ProcessInfo.processInfo.systemUptime < deadline else { return false }
        // Construct the full balanced sequence before posting its first event.
        // Dock's keyboard controller observes the system modifier state, so
        // setting flags only on a process-targeted arrow event is insufficient.
        for (index, event) in events.enumerated() {
            event.timestamp = CGEventTimestamp(DispatchTime.now().uptimeNanoseconds)
            event.post(tap: hid ? .cghidEventTap : .cgSessionEventTap)
            if eventInterval > 0, index < events.count - 1 { Thread.sleep(forTimeInterval: eventInterval) }
        }
        return true
    }

    private nonisolated static func systemFocusIsDock(pid: pid_t, expectedItem: AXUIElement? = nil) -> Bool {
        let system = AXUIElementCreateSystemWide()
        _ = AXUIElementSetMessagingTimeout(system, 0.025)
        // Dock may own keyboard focus without replacing the frontmost app's
        // menu bar. Prefer the focused UI element when it is available.
        if let focused = attribute(system, kAXFocusedUIElementAttribute), CFGetTypeID(focused) == AXUIElementGetTypeID() {
            let element = focused as! AXUIElement
            var actualPID: pid_t = 0
            guard AXUIElementGetPid(element, &actualPID) == .success, actualPID == pid else { return false }
            if let expectedItem, attribute(element, kAXRoleAttribute) as? String == kAXDockItemRole as String {
                return CFEqual(element, expectedItem)
            }
            return true
        }
        guard let focused = attribute(system, kAXFocusedApplicationAttribute), CFGetTypeID(focused) == AXUIElementGetTypeID() else { return false }
        var actualPID: pid_t = 0
        return AXUIElementGetPid(focused as! AXUIElement, &actualPID) == .success && actualPID == pid
    }

    private nonisolated static func focusSummary(pid: pid_t, item: AXUIElement) -> String {
        let system = AXUIElementCreateSystemWide()
        _ = AXUIElementSetMessagingTimeout(system, 0.025)
        let systemDescription = [kAXFocusedApplicationAttribute, kAXFocusedUIElementAttribute].map { name in
            guard let value = attribute(system, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return "\(name): unavailable" }
            let element = value as! AXUIElement
            var actualPID: pid_t = 0
            _ = AXUIElementGetPid(element, &actualPID)
            let owner = actualPID == pid ? "Dock" : actualPID == getpid() ? "DaysYet" : "other"
            return "\(name): \(owner)/\(attribute(element, kAXRoleAttribute) as? String ?? "unknown")"
        }.joined(separator: ", ")
        let root = AXUIElementCreateApplication(pid)
        _ = AXUIElementSetMessagingTimeout(root, 0.025)
        let rootFocus = attribute(root, kAXFocusedUIElementAttribute)
        let parent = attribute(item, kAXParentAttribute)
        let listFocused: Bool? = parent.flatMap { value in
            guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            return attribute(value as! AXUIElement, kAXFocusedAttribute) as? Bool
        }
        return "\(systemDescription), rootTarget=\(rootFocus.map { CFEqual($0, item) } == true), listFocus=\(listFocused.map(String.init) ?? "?")"
    }

    private nonisolated static func menuItem(_ root: AXUIElement, titles: Set<String>) -> AXUIElement? {
        var nodes = [root]
        var cursor = 0
        let deadline = ProcessInfo.processInfo.systemUptime + 0.2
        while cursor < nodes.count, nodes.count < 96, ProcessInfo.processInfo.systemUptime < deadline {
            let element = nodes[cursor]; cursor += 1
            if attribute(element, kAXRoleAttribute) as? String == kAXMenuItemRole as String,
               let title = attribute(element, kAXTitleAttribute) as? String, titles.contains(title) { return element }
            if let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement], children.count < 64 { nodes += children }
        }
        return nil
    }

    private nonisolated static func removePin(path: String, pid: pid_t) -> String {
        guard sessionAllowsInteraction() else { return "操作できるデスクトップではないため、中止しました。" }
        guard let isPinned = pinned(path) else { return "Dockの固定状態を確認できません。" }
        guard isPinned else { return "対象の丸は固定されていません。" }
        guard let items = snapshot(pid: pid), items.filter({ $0.path == path }).count == 1,
              let source = items.first(where: { $0.path == path }) else { return "対象の丸を確認できません。" }
        guard sessionAllowsInteraction(), AXUIElementPerformAction(source.element, kAXShowMenuAction as CFString) == .success else {
            return "Dockメニューを安全に開けないため、中止しました。"
        }
        defer {
            // Only Dock receives Escape; it cannot dismiss another app's UI.
            if sessionAllowsInteraction(), let down = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true),
               let up = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: false) {
                down.flags = []; up.flags = []; down.postToPid(pid); up.postToPid(pid)
            }
        }
        Thread.sleep(forTimeInterval: 0.05)
        guard let rawMenu = attribute(source.element, kAXShownMenuUIElementAttribute),
              CFGetTypeID(rawMenu) == AXUIElementGetTypeID() else { return "対象のDockメニューを確認できません。" }
        let menu = rawMenu as! AXUIElement
        if let options = menuItem(menu, titles: ["Options", "オプション"]) {
            _ = AXUIElementPerformAction(options, kAXPressAction as CFString)
            Thread.sleep(forTimeInterval: 0.05)
        }
        let remove = menuItem(menu, titles: ["Remove from Dock", "Dockから削除"])
        let keep = menuItem(menu, titles: ["Keep in Dock", "Dockに追加"])
        let checkedKeep = keep.flatMap { item -> AXUIElement? in
            guard let mark = attribute(item, kAXMenuItemMarkCharAttribute) as? String, !mark.isEmpty else { return nil }
            return item
        }
        guard let command = remove ?? checkedKeep, AXIsProcessTrusted(), sessionAllowsInteraction(), pinned(path) == true,
              let currentMenu = attribute(source.element, kAXShownMenuUIElementAttribute), CFEqual(rawMenu, currentMenu) else {
            return "安全に実行できる固定解除メニューが見つかりません。"
        }
        guard AXUIElementPerformAction(command, kAXPressAction as CFString) == .success else { return "固定解除を実行できませんでした。" }
        Thread.sleep(forTimeInterval: 0.2)
        return pinned(path) == false ? "成功：Dockを再起動せず固定を解除しました。" : "固定解除の反映をまだ確認できません。"
    }

    private struct Item {
        let element: AXUIElement
        let path: String
        let quartzFrame: CGRect?
    }

    private nonisolated static func applicationPath(_ value: CFTypeRef?) -> String? {
        let url = (value as? URL) ?? (value as? String).flatMap(URL.init(string:))
        guard let url, url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost" else { return nil }
        return url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private enum SelectionCheck: String {
        case ready, alreadySelected, focusUnavailable, identityChanged, parentUnavailable
        case selectionUnsupported, selectionWriteFailed, selectionChanged

        var isReady: Bool { self == .ready || self == .alreadySelected }
    }

    /// Called on the main thread immediately before each arrow. Dock's hover
    /// state is allowed to change between arrows, but the next event must still
    /// target exactly the owned helper verified by the fresh order snapshot.
    private nonisolated static func selectOwnedItem(_ item: Item, expectedPath: String, pid: pid_t) -> SelectionCheck {
        guard Thread.isMainThread, systemFocusIsDock(pid: pid) else { return .focusUnavailable }
        var owner: pid_t = 0
        guard item.path == expectedPath, applicationPath(attribute(item.element, kAXURLAttribute)) == expectedPath,
              AXUIElementGetPid(item.element, &owner) == .success, owner == pid else { return .identityChanged }
        // Consecutive moves of the same owned item need a fresh identity and
        // selection check, not another write that restarts Dock's selection UI.
        if attribute(item.element, kAXSelectedAttribute) as? Bool == true,
           systemFocusIsDock(pid: pid, expectedItem: item.element) {
            return .alreadySelected
        }
        guard let parent = attribute(item.element, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else {
            return .parentUnavailable
        }
        let list = parent as! AXUIElement
        guard AXUIElementGetPid(list, &owner) == .success, owner == pid else { return .parentUnavailable }
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(list, kAXSelectedChildrenAttribute as CFString, &settable) == .success,
              settable.boolValue else { return .selectionUnsupported }
        guard AXUIElementSetAttributeValue(list, kAXSelectedChildrenAttribute as CFString, [item.element] as CFArray) == .success else {
            return .selectionWriteFailed
        }
        guard applicationPath(attribute(item.element, kAXURLAttribute)) == expectedPath,
              attribute(item.element, kAXSelectedAttribute) as? Bool == true else { return .selectionChanged }
        return systemFocusIsDock(pid: pid, expectedItem: item.element) ? .ready : .focusUnavailable
    }

    private nonisolated static func snapshot(pid: pid_t, includingFrames: Bool = true,
                                             readDeadline: TimeInterval = .greatestFiniteMagnitude,
                                             failure: ((MacDockNativeGuardPolicy.Check) -> Void)? = nil) -> [Item]? {
        func failed(_ reason: String, status: AXError? = nil) -> [Item]? {
            let check: MacDockNativeGuardPolicy.Check
            if !AXIsProcessTrusted() || status == .apiDisabled { check = .rejected("accessibility-permission") }
            else if status == .illegalArgument || status == .attributeUnsupported { check = .rejected(reason) }
            else { check = .unavailable(reason, axError: status?.rawValue) }
            failure?(check)
            return nil
        }
        func embeddedError(_ value: AnyObject) -> AXError? {
            guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
            let value = value as! AXValue
            var error = AXError.success
            return AXValueGetType(value) == .axError && AXValueGetValue(value, .axError, &error) ? error : nil
        }
        guard AXIsProcessTrusted() else { return failed("accessibility-permission") }
        let root = AXUIElementCreateApplication(pid)
        let timeoutStatus = AXUIElementSetMessagingTimeout(root, 0.025)
        guard timeoutStatus == .success else { return failed("ax-timeout-configuration", status: timeoutStatus) }
        var nodes: [(AXUIElement, Int)] = [(root, 0)]
        var cursor = 0
        var items: [Item] = []
        let deadline = min(readDeadline, ProcessInfo.processInfo.systemUptime + 0.35)
        let attributes = includingFrames
            ? [kAXSubroleAttribute, kAXURLAttribute, kAXPositionAttribute, kAXSizeAttribute]
            : [kAXSubroleAttribute, kAXURLAttribute]
        while cursor < nodes.count, nodes.count < 512, ProcessInfo.processInfo.systemUptime < deadline {
            let (element, depth) = nodes[cursor]; cursor += 1
            var raw: CFArray?
            let status = AXUIElementCopyMultipleAttributeValues(element, attributes as CFArray, [], &raw)
            guard status == .success, let raw else { return failed("ax-attributes", status: status) }
            let values = raw as [AnyObject]
            guard values.count == attributes.count else { return failed("ax-attribute-count") }
            if values[0] as? String == kAXApplicationDockItemSubrole as String {
                guard let path = applicationPath(values[1]) else { return failed("ax-item-url", status: embeddedError(values[1])) }
                var frame: CGRect?
                if includingFrames, CFGetTypeID(values[2]) == AXValueGetTypeID(), CFGetTypeID(values[3]) == AXValueGetTypeID() {
                    let position = values[2] as! AXValue
                    let size = values[3] as! AXValue
                    var point = CGPoint.zero
                    var dimensions = CGSize.zero
                    if AXValueGetType(position) == .cgPoint, AXValueGetType(size) == .cgSize,
                       AXValueGetValue(position, .cgPoint, &point), AXValueGetValue(size, .cgSize, &dimensions),
                       [point.x, point.y, dimensions.width, dimensions.height].allSatisfy(\.isFinite),
                       dimensions.width > 0, dimensions.height > 0 {
                        frame = CGRect(origin: point, size: dimensions)
                    }
                }
                if includingFrames, frame == nil {
                    failure?(.unavailable("ax-frame", axError: (embeddedError(values[2]) ?? embeddedError(values[3]))?.rawValue))
                }
                items.append(Item(element: element, path: path, quartzFrame: frame))
            } else if depth < 3 {
                var children: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
                   let children = children as? [AXUIElement], children.count < 256 {
                    nodes.append(contentsOf: children.map { ($0, depth + 1) })
                }
            }
        }
        guard cursor == nodes.count else { return failed("ax-tree-read-budget") }
        guard !items.isEmpty else { return failed("ax-items-empty") }
        return items
    }

    private struct SavedDockState {
        let pins: Set<String>
        let foreign: [String: Any]
    }

    private nonisolated static func savedDockState(owned: Set<String>) -> SavedDockState? {
        let domain = "com.apple.dock" as CFString
        guard CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else { return nil }
        var foreign: [String: Any] = [:]
        var pins = Set<String>()
        for key in ["persistent-apps", "persistent-others", "recent-apps"] {
            let raw = CFPreferencesCopyValue(key as CFString, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            guard raw == nil || raw is [[String: Any]] else { return nil }
            let entries = raw as? [[String: Any]] ?? []
            foreign[key] = entries.filter { entry in
                guard let data = entry["tile-data"] as? [String: Any],
                      let file = data["file-data"] as? [String: Any],
                      let string = file["_CFURLString"] as? String,
                      let url = URL(string: string), url.isFileURL else { return true }
                let path = url.resolvingSymlinksInPath().standardizedFileURL.path
                guard owned.contains(path) else { return true }
                if key == "persistent-apps" { pins.insert(path) }
                return false
            }
        }
        return SavedDockState(pins: pins, foreign: foreign)
    }

#if DAYSYET_DOCK_REORDER_PROBE
    /// A deterministic equality token, not a loggable digest. Tagged scalar
    /// values and sorted dictionary keys preserve every saved-record field.
    private nonisolated static func savedRecordToken(_ value: Any) -> Data? {
        func canonical(_ value: Any) -> Any? {
            if let values = value as? [String: Any] {
                var result: [Any] = ["dictionary"]
                for key in values.keys.sorted() {
                    guard let child = canonical(values[key]!) else { return nil }
                    result.append([key, child])
                }
                return result
            }
            if let values = value as? [Any] {
                var result: [Any] = ["array"]
                for value in values {
                    guard let child = canonical(value) else { return nil }
                    result.append(child)
                }
                return result
            }
            if let value = value as? String { return ["string", value] }
            if let value = value as? Data { return ["data", value.base64EncodedString()] }
            if let value = value as? Date { return ["date", String(value.timeIntervalSinceReferenceDate.bitPattern)] }
            if let value = value as? NSNumber {
                return ["number", String(cString: value.objCType), value.stringValue]
            }
            return nil
        }
        guard let encoded = canonical(value) else { return nil }
        return try? JSONSerialization.data(withJSONObject: encoded)
    }

    private nonisolated static func probeExactFilePath(_ value: CFTypeRef?) -> String? {
        guard let url = (value as? URL) ?? (value as? String).flatMap(URL.init(string:)), url.isFileURL,
              url.host == nil || url.host == "" || url.host == "localhost",
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { return nil }
        return url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private struct URLDragStateRead {
        let stage: String
        let check: MacDockNativeGuardPolicy.Check
        var value: MacDockNativeProbeState? = nil
        var failureDescription: String {
            let error = check.axError.map { " (AX \($0))" } ?? ""
            return "\(stage): \(check.reason)\(error)"
        }
    }

    private nonisolated static func urlProbeMayRetry(_ result: URLDragStateRead, attempts: Int,
                                                     began: TimeInterval, cancellation: MacDockNativeCancellation) -> Bool {
        MacDockNativeURLDragValidation.canRetryInspection(state: result.check.state, attempts: attempts,
            elapsed: ProcessInfo.processInfo.systemUptime - began, interrupted: cancellation.reason != nil)
    }

    private nonisolated static func probeOnMain<T>(deadline: TimeInterval, _ body: @escaping @MainActor () -> T) -> T? {
        guard ProcessInfo.processInfo.systemUptime < deadline else { return nil }
        if Thread.isMainThread { return MainActor.assumeIsolated { body() } }
        let delivery = MacDockNativeProbeReadDelivery<T>()
        let loop = CFRunLoopGetMain()
        // Native drag tracking need not service the main dispatch queue. A
        // read-only block in common modes also has a bounded worker wait.
        CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) {
            guard delivery.isAccepting, ProcessInfo.processInfo.systemUptime < deadline else { return }
            delivery.deliver(MainActor.assumeIsolated { body() })
        }
        CFRunLoopWakeUp(loop)
        return delivery.wait(until: deadline)
    }

    private nonisolated static func probeEnvironment(edge: MacWidgetEdge, expected: Environment?,
                                                      cancellation: MacDockNativeCancellation,
                                                      deadline: TimeInterval) -> EnvironmentRead {
        if let check = priorityInterruption(cancellation, deadline: deadline, forMutation: false) {
            return EnvironmentRead(check: check)
        }
        guard let result = probeOnMain(deadline: deadline, {
            guard cancellation.reason == nil else { return EnvironmentRead(check: .rejected("cancelled")) }
            return environmentRead(edge: edge, expected: expected)
        }) else { return EnvironmentRead(check: .unavailable("main-handoff-timeout")) }
        if let check = priorityInterruption(cancellation, deadline: deadline, forMutation: false) {
            return EnvironmentRead(check: check)
        }
        return result
    }

    private nonisolated static func probeSavedState(paths: [String: MetricKind], metrics: [MetricKind],
                                                     failure: ((MacDockNativeGuardPolicy.Check) -> Void)? = nil) -> (pins: Set<String>, foreign: Data)? {
        func failed(_ check: MacDockNativeGuardPolicy.Check) -> (pins: Set<String>, foreign: Data)? {
            failure?(check)
            return nil
        }
        let domain = "com.apple.dock" as CFString
        guard CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else {
            return failed(.unavailable("saved-preferences"))
        }
        var foreign: [String: Any] = [:]
        var pins = Set<String>()
        var seenApps = Set<String>()
        let expectedIdentities = Dictionary(uniqueKeysWithValues: metrics.enumerated().compactMap { index, metric -> (String, String)? in
            guard let path = paths.first(where: { $0.value == metric })?.key else { return nil }
            return ("com.hinoshiba.daysyet.dock-group-move-probe.tile\(index + 1)", path)
        })
        guard expectedIdentities.count == metrics.count else { return failed(.rejected("fixture-mapping")) }
        for key in ["persistent-apps", "persistent-others", "recent-apps"] {
            let raw = CFPreferencesCopyValue(key as CFString, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            guard raw == nil || raw is [[String: Any]] else { return failed(.rejected("saved-record-type")) }
            var retained: [[String: Any]] = []
            for entry in raw as? [[String: Any]] ?? [] {
                guard let data = entry["tile-data"] as? [String: Any] else { retained.append(entry); continue }
                let rawURL = (data["file-data"] as? [String: Any])?["_CFURLString"] as? String
                // Finder can move the disposable bundle and Dock can follow
                // its alias. Such a known fixture must not silently become a
                // foreign record and make cleanup look complete.
                guard MacDockNativeURLDragValidation.fixtureIdentityIsConsistent(
                    bundleIdentifier: data["bundle-identifier"] as? String,
                    exactPath: rawURL.flatMap { probeExactFilePath($0 as CFString) },
                    expectedPathsByBundleIdentifier: expectedIdentities) else { return failed(.rejected("fixture-location")) }
                guard let rawURL else { retained.append(entry); continue }
                guard let path = applicationPath(rawURL as CFString) else { retained.append(entry); continue }
                if key != "persistent-others", !seenApps.insert(path).inserted { return failed(.rejected("saved-duplicate-identity")) }
                guard let metric = paths[path] else {
                    retained.append(entry)
                    continue
                }
                guard key != "persistent-others", probeExactFilePath(rawURL as CFString) == path,
                      let index = metrics.firstIndex(of: metric) else { return failed(.rejected("fixture-record-location")) }
                if let identifier = data["bundle-identifier"],
                   identifier as? String != "com.hinoshiba.daysyet.dock-group-move-probe.tile\(index + 1)" {
                    return failed(.rejected("fixture-bundle-identity"))
                }
                if key == "persistent-apps" { pins.insert(path) }
            }
            foreign[key] = retained
        }
        guard let token = savedRecordToken(foreign) else { return failed(.rejected("saved-record-value")) }
        return (pins, token)
    }

    private nonisolated static func readURLDragState(metrics: [MetricKind], paths: [String: MetricKind],
                                                     environment: Environment, cancellation: MacDockNativeCancellation,
                                                     deadline: TimeInterval) -> MacDockNativeProbeState? {
        readURLDragStateAttempt(metrics: metrics, paths: paths, environment: environment,
            cancellation: cancellation, deadline: deadline).value
    }

    private nonisolated static func readURLDragStateAttempt(metrics: [MetricKind], paths: [String: MetricKind],
                                                            environment: Environment, cancellation: MacDockNativeCancellation,
                                                            deadline: TimeInterval, validateBefore: Bool = true,
                                                            boundedMainRead: Bool = false) -> URLDragStateRead {
        func gate() -> MacDockNativeGuardPolicy.Check {
            if boundedMainRead {
                return probeEnvironment(edge: environment.edge, expected: environment,
                    cancellation: cancellation, deadline: deadline).check
            }
            return checkedEnvironment(edge: environment.edge, expected: environment,
                cancellation: cancellation, deadline: deadline).check
        }
        func failed(_ stage: String, _ check: MacDockNativeGuardPolicy.Check) -> URLDragStateRead {
            URLDragStateRead(stage: stage, check: check)
        }
        if validateBefore {
            let check = gate()
            guard check.state == .matched else { return failed("environment-before", check) }
        }
        if let check = priorityInterruption(cancellation, deadline: deadline, forMutation: false) {
            return failed("before-records", check)
        }
        var detail = MacDockNativeGuardPolicy.Check.unavailable("saved-state")
        guard let saved = probeSavedState(paths: paths, metrics: metrics, failure: { detail = $0 }) else {
            return failed("saved-before", detail)
        }
        detail = .unavailable("ax-state")
        guard let first = snapshot(pid: environment.pid, readDeadline: deadline, failure: { detail = $0 }) else {
            return failed("ax-first", detail)
        }
        guard Set(first.map(\.path)).count == first.count else { return failed("identity-first", .rejected("duplicate-identity")) }
        guard probeOwnedIdentitiesMatch(first, paths: paths, failure: { detail = $0 }) else {
            return failed("identity-first", detail)
        }
        if let check = priorityInterruption(cancellation, deadline: deadline, forMutation: false) {
            return failed("between-snapshots", check)
        }
        detail = .unavailable("ax-state")
        guard let last = snapshot(pid: environment.pid, readDeadline: deadline, failure: { detail = $0 }) else {
            return failed("ax-second", detail)
        }
        guard Set(last.map(\.path)).count == last.count else { return failed("identity-second", .rejected("duplicate-identity")) }
        guard first.map(\.path) == last.map(\.path) else { return failed("order-match", .unavailable("order-not-settled")) }
        guard probeOwnedIdentitiesMatch(last, paths: paths, failure: { detail = $0 }) else {
            return failed("identity-second", detail)
        }
        guard saved.pins.isSubset(of: Set(last.map(\.path))) else {
            return failed("pins-present", .unavailable("pin-item-not-settled"))
        }
        guard let layout = probeLayout(last, paths: paths, environment: environment) else {
            return failed("frames", detail.reason == "ax-frame" ? detail : .unavailable("ax-frame"))
        }
        detail = .unavailable("saved-state")
        guard let finalSaved = probeSavedState(paths: paths, metrics: metrics, failure: { detail = $0 }) else {
            return failed("saved-after", detail)
        }
        guard saved.pins == finalSaved.pins else { return failed("pins-match", .unavailable("pins-not-settled")) }
        guard saved.foreign == finalSaved.foreign else { return failed("foreign-match", .unavailable("saved-records-not-settled")) }
        let check = gate()
        guard check.state == .matched else { return failed("environment-after", check) }
        let finder = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
            .resolvingSymlinksInPath().standardizedFileURL.path
        guard last.first?.path == finder else { return failed("finder", .rejected("finder-order")) }
        let state = MacDockNativeProbeState(dockPID: environment.pid, edge: environment.edge,
            screenFrames: environment.screenFrames, orderedIdentities: last.map(\.path), metrics: metrics,
            ownedIdentities: metrics.compactMap { metric in paths.first(where: { $0.value == metric })?.key },
            items: layout.items, ownPinnedMetrics: Set(saved.pins.compactMap { paths[$0] }),
            foreignSavedRecords: saved.foreign, dock: environment.dock, launchDate: environment.launchDate)
        return URLDragStateRead(stage: "complete", check: .matched, value: state)
    }

    private nonisolated static func probeLayout(_ items: [Item], paths: [String: MetricKind],
                                                environment: Environment) -> MacDockNativeLayout? {
        guard Set(items.map(\.path)).count == items.count else { return nil }
        var result: [MacDockNativeLayout.Item] = []
        for item in items {
            guard let frame = item.quartzFrame else { return nil }
            result.append(.init(metric: paths[item.path], frame: NSRect(x: frame.minX,
                y: environment.primaryMaxY - frame.maxY, width: frame.width, height: frame.height)))
        }
        return MacDockNativeLayout(dockPID: environment.pid, edge: environment.edge, items: result)
    }

    private nonisolated static func probeOwnedIdentitiesMatch(_ items: [Item], paths: [String: MetricKind],
                                                              failure: ((MacDockNativeGuardPolicy.Check) -> Void)? = nil) -> Bool {
        for item in items where paths[item.path] != nil {
            var value: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(item.element, kAXURLAttribute as CFString, &value)
            guard AXIsProcessTrusted(), status != .apiDisabled else {
                failure?(.rejected("accessibility-permission")); return false
            }
            guard status == .success else {
                failure?(.unavailable("owned-url-read", axError: status.rawValue)); return false
            }
            guard probeExactFilePath(value) == item.path else {
                failure?(.rejected("owned-url-identity")); return false
            }
        }
        return true
    }

    private struct URLPinCleanupResult {
        let success: Bool
        let message: String
        var state: MacDockNativeProbeState? = nil
    }

    private nonisolated static func retryCleanupRead<Value>(cancellation: MacDockNativeCancellation, deadline: TimeInterval,
                                                             read: (TimeInterval) -> (Value?, MacDockNativeGuardPolicy.Check)) -> (Value?, MacDockNativeGuardPolicy.Check) {
        let began = ProcessInfo.processInfo.systemUptime
        let readDeadline = min(deadline, began + 0.8)
        var attempts = 0
        repeat {
            if let check = priorityInterruption(cancellation, deadline: readDeadline, forMutation: true) { return (nil, check) }
            attempts += 1
            let result = read(readDeadline)
            if let check = priorityInterruption(cancellation, deadline: readDeadline, forMutation: true) { return (nil, check) }
            if result.0 != nil { return result }
            let now = ProcessInfo.processInfo.systemUptime
            guard MacDockNativeURLDragValidation.canRetryCleanupRead(state: result.1.state, attempts: attempts,
                elapsed: now - began, remaining: readDeadline - now, interrupted: cancellation.reason != nil) else { return result }
            Thread.sleep(forTimeInterval: 0.025)
        } while true
    }

    private nonisolated static func cleanupState(metrics: [MetricKind], paths: [String: MetricKind], environment: Environment,
                                                 cancellation: MacDockNativeCancellation, deadline: TimeInterval,
                                                 failure: (MacDockNativeGuardPolicy.Check) -> Void) -> MacDockNativeProbeState? {
        let result = retryCleanupRead(cancellation: cancellation, deadline: deadline) { readDeadline in
            let state = readURLDragStateAttempt(metrics: metrics, paths: paths, environment: environment,
                cancellation: cancellation, deadline: readDeadline)
            var check = state.check
            if state.value == nil { check = .init(state: check.state, reason: "\(state.stage).\(check.reason)", axError: check.axError) }
            return (state.value, check)
        }
        if result.0 == nil { failure(result.1) }
        return result.0
    }

    private struct ProbeCleanupObservation {
        let items: [Item]
        let pins: Set<String>
    }

    private nonisolated static func cleanupObservation(paths: [String: MetricKind], metrics: [MetricKind],
                                                        environment: Environment, cancellation: MacDockNativeCancellation,
                                                        deadline: TimeInterval, orders: [[String]], pins: [Set<String>],
                                                        foreignRecords: Data) -> (ProbeCleanupObservation?, MacDockNativeGuardPolicy.Check) {
        retryCleanupRead(cancellation: cancellation, deadline: deadline) { readDeadline in
            let gate = checkedEnvironment(edge: environment.edge, expected: environment, cancellation: cancellation,
                deadline: readDeadline, forMutation: true).check
            guard gate.state == .matched else { return (nil, gate) }
            var detail = MacDockNativeGuardPolicy.Check.unavailable("saved-state")
            guard let saved = probeSavedState(paths: paths, metrics: metrics, failure: { detail = $0 }) else { return (nil, detail) }
            guard saved.foreign == foreignRecords else { return (nil, .rejected("foreign-records-changed")) }
            guard pins.contains(saved.pins) else { return (nil, .rejected("pins-changed")) }
            guard let items = snapshot(pid: environment.pid, includingFrames: false, readDeadline: readDeadline,
                failure: { detail = $0 }) else { return (nil, detail) }
            guard orders.contains(items.map(\.path)), Set(items.map(\.path)).count == items.count else {
                return (nil, .rejected("native-order-changed"))
            }
            guard probeOwnedIdentitiesMatch(items, paths: paths, failure: { detail = $0 }) else { return (nil, detail) }
            return (ProbeCleanupObservation(items: items, pins: saved.pins), .matched)
        }
    }

    private nonisolated static func performURLDragPinCleanup(metrics: [MetricKind], reference: MacDockNativeProbeState,
                                                              recovery: Bool, paths: [String: MetricKind],
                                                              environment: Environment,
                                                              cancellation: MacDockNativeCancellation,
                                                              deadline: TimeInterval) -> URLPinCleanupResult {
        let began = ProcessInfo.processInfo.systemUptime
        var stage = "initial-state"
        var failure = MacDockNativeGuardPolicy.Check.unavailable("state-unavailable")
        var completed = 0
        func stopped(_ message: String = "固定解除を中止しました。残った試験用の固定を確認してください。") -> URLPinCleanupResult {
            let code = "\(stage): \(failure.reason)" + (failure.axError.map { " (AX \($0))" } ?? "")
            MacDockNativeDiagnostics.urlProbeRead(stage: "cleanup.\(stage)", check: failure, attempt: completed, began: began)
            return URLPinCleanupResult(success: false, message: "\(message)\n\(completed)個の解除を確認済み。\(code)")
        }
        guard let initial = cleanupState(metrics: reference.metrics, paths: paths, environment: environment,
            cancellation: cancellation, deadline: deadline, failure: { failure = $0 }) else { return stopped() }
        guard reference.sameEnvironment(as: initial), reference.ownedIdentities == initial.ownedIdentities else {
            failure = .rejected("reference-environment-or-identity-changed"); return stopped()
        }
        if recovery {
            guard initial.orderedIdentities == reference.orderedIdentities,
                  initial.ownPinnedMetrics == reference.ownPinnedMetrics,
                  initial.foreignSavedRecords == reference.foreignSavedRecords else {
                failure = .rejected("confirmed-state-changed")
                return stopped("確認した固定状態が変わりました。もう一度確認してください。")
            }
        } else {
            guard reference.ownPinnedMetrics.isSubset(of: initial.ownPinnedMetrics),
                  MacDockNativeURLDragValidation.cleanupSelection(requested: metrics, members: reference.metrics,
                    baselinePins: reference.ownPinnedMetrics, currentPins: initial.ownPinnedMetrics) != nil else {
                failure = .rejected("baseline-pin-protection")
                return stopped("試験前から存在した固定は解除できません。")
            }
        }
        // A failed trial may have coincided with a legitimate foreign change.
        // Cleanup never restores that change. Its invariant is this fresh
        // cleanup-start state, while the old snapshot authorizes own pins only.
        let foreignRecords = initial.foreignSavedRecords
        let foreignOrder = initial.foreignOrder
        var expectedOrder = initial.orderedIdentities
        var expectedPins = Set(initial.ownPinnedMetrics.compactMap { metric in paths.first(where: { $0.value == metric })?.key })
        for metric in metrics where initial.ownPinnedMetrics.contains(metric) {
            stage = "before-item"
            guard let path = paths.first(where: { $0.value == metric })?.key,
                  let items = probeMutationSnapshot(paths: paths, metrics: reference.metrics, environment: environment,
                    cancellation: cancellation, deadline: deadline, expectedOrder: expectedOrder,
                    expectedPins: expectedPins, foreignRecords: foreignRecords, failure: { failure = $0 }),
                  let source = items.first(where: { $0.path == path }) else { return stopped() }
            let removedOrder = expectedOrder.filter { $0 != path }
            var removedPins = expectedPins
            removedPins.remove(path)
            stage = "menu"
            let removed = removeProbePin(source: source, paths: paths, metrics: reference.metrics,
                environment: environment, cancellation: cancellation, deadline: deadline,
                expectedOrder: expectedOrder, expectedPins: expectedPins, foreignRecords: foreignRecords,
                failure: { itemStage, check in stage = itemStage; failure = check })
            guard removed else { return stopped() }

            // The disposable fixtures are not running. Removing this alias
            // should remove exactly this slot, never relocate another item.
            stage = "confirm-removal"
            let settleDeadline = min(deadline, ProcessInfo.processInfo.systemUptime + 1)
            var confirmed = false
            repeat {
                let read = cleanupObservation(paths: paths, metrics: reference.metrics, environment: environment,
                    cancellation: cancellation, deadline: settleDeadline, orders: [expectedOrder, removedOrder],
                    pins: [expectedPins, removedPins], foreignRecords: foreignRecords)
                guard let current = read.0 else { failure = read.1; return stopped() }
                let observation = MacDockNativeURLDragValidation.observeRemoval(order: current.items.map(\.path), pins: current.pins,
                    previousOrder: expectedOrder, previousPins: expectedPins, member: path, foreignUnchanged: true)
                guard observation != .changed else { failure = .rejected("unexpected-removal"); return stopped() }
                if observation == .completed { confirmed = true; break }
                Thread.sleep(forTimeInterval: 0.015)
            } while ProcessInfo.processInfo.systemUptime < settleDeadline
            guard confirmed else { failure = .unavailable("removal-not-settled"); return stopped("解除後の対象項目の消滅を確認できませんでした。") }
            completed += 1
            expectedOrder = removedOrder
            expectedPins = removedPins
        }
        stage = "final-state"
        guard let final = cleanupState(metrics: reference.metrics, paths: paths, environment: environment,
            cancellation: cancellation, deadline: deadline, failure: { failure = $0 }) else { return stopped() }
        guard final.orderedIdentities == expectedOrder, final.foreignOrder == foreignOrder, final.foreignSavedRecords == foreignRecords,
              Set(metrics).isDisjoint(with: final.ownPinnedMetrics),
              Set(final.ownPinnedMetrics.compactMap { metric in paths.first(where: { $0.value == metric })?.key }) == expectedPins else {
            failure = .rejected("final-state-changed")
            return stopped()
        }
        return URLPinCleanupResult(success: true, message: "指定した試験用の固定だけを解除しました。", state: final)
    }

    private nonisolated static func probeMutationSnapshot(paths: [String: MetricKind], metrics: [MetricKind],
                                                           environment: Environment, cancellation: MacDockNativeCancellation,
                                                           deadline: TimeInterval, expectedOrder: [String],
                                                           expectedPins: Set<String>, foreignRecords: Data,
                                                           failure: ((MacDockNativeGuardPolicy.Check) -> Void)? = nil) -> [Item]? {
        let read = cleanupObservation(paths: paths, metrics: metrics, environment: environment,
            cancellation: cancellation, deadline: deadline, orders: [expectedOrder], pins: [expectedPins], foreignRecords: foreignRecords)
        if read.0 == nil { failure?(read.1) }
        return read.0?.items
    }

    private nonisolated static func probeMenuItem(_ root: AXUIElement, titles: Set<String>, pid: pid_t) -> AXUIElement? {
        var nodes = [root]
        var cursor = 0
        var matches: [AXUIElement] = []
        let deadline = ProcessInfo.processInfo.systemUptime + 0.2
        while cursor < nodes.count, nodes.count < 96, ProcessInfo.processInfo.systemUptime < deadline {
            let element = nodes[cursor]; cursor += 1
            var owner: pid_t = 0
            guard AXUIElementGetPid(element, &owner) == .success, owner == pid else { return nil }
            if attribute(element, kAXRoleAttribute) as? String == kAXMenuItemRole as String,
               let title = attribute(element, kAXTitleAttribute) as? String, titles.contains(title),
               attribute(element, kAXEnabledAttribute) as? Bool == true { matches.append(element) }
            if let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
                guard children.count < 64 else { return nil }
                nodes += children
            }
        }
        return cursor == nodes.count && matches.count == 1 ? matches[0] : nil
    }

    private nonisolated static func removeProbePin(source: Item, paths: [String: MetricKind], metrics: [MetricKind],
                                                   environment: Environment, cancellation: MacDockNativeCancellation,
                                                   deadline: TimeInterval, expectedOrder: [String],
                                                   expectedPins: Set<String>, foreignRecords: Data,
                                                   failure: (String, MacDockNativeGuardPolicy.Check) -> Void) -> Bool {
        var openedMenu: AXUIElement?
        func fail(_ stage: String, _ check: MacDockNativeGuardPolicy.Check) -> Bool {
            failure(stage, check)
            return false
        }
        func owns(_ element: AXUIElement) -> Bool {
            var pid: pid_t = 0
            return AXUIElementGetPid(element, &pid) == .success && pid == environment.pid
        }
        func currentMenu() -> AXUIElement? {
            guard owns(source.element), probeExactFilePath(attribute(source.element, kAXURLAttribute)) == source.path,
                  let menu = attribute(source.element, kAXShownMenuUIElementAttribute),
                  CFGetTypeID(menu) == AXUIElementGetTypeID() else { return nil }
            let element = menu as! AXUIElement
            return owns(element) ? element : nil
        }
        func act(_ element: AXUIElement, action: String, menu: AXUIElement? = nil) -> Bool {
            var detail = MacDockNativeGuardPolicy.Check.unavailable("state-unavailable")
            guard probeMutationSnapshot(paths: paths, metrics: metrics, environment: environment,
                cancellation: cancellation, deadline: deadline, expectedOrder: expectedOrder,
                expectedPins: expectedPins, foreignRecords: foreignRecords, failure: { detail = $0 }) != nil else {
                return fail("menu-read", detail)
            }
            return onMain {
                let check = environmentRead(edge: environment.edge, expected: environment).check
                guard check.state == .matched else { return fail("before-action", check) }
                if let check = priorityInterruption(cancellation, deadline: deadline, forMutation: true) { return fail("before-action", check) }
                guard owns(source.element), owns(element),
                      probeExactFilePath(attribute(source.element, kAXURLAttribute)) == source.path,
                      attribute(source.element, kAXSubroleAttribute) as? String == kAXApplicationDockItemSubrole as String else {
                    return fail("before-action", .rejected("owned-element-changed"))
                }
                if let menu {
                    guard let shown = currentMenu(), CFEqual(menu, shown),
                          attribute(element, kAXEnabledAttribute) as? Bool == true else {
                        return fail("before-action", .rejected("menu-changed-or-disabled"))
                    }
                } else if currentMenu() != nil { return fail("before-action", .rejected("menu-already-open")) }
                var actions: CFArray?
                guard AXUIElementCopyActionNames(element, &actions) == .success,
                      (actions as? [String])?.contains(action) == true else { return fail("action", .rejected("action-unavailable")) }
                let status = AXUIElementPerformAction(element, action as CFString)
                guard status == .success else {
                    // The target may already have acted despite an AX error.
                    // Never retry an issued command, only subsequent reads.
                    return fail("action", .init(state: .rejected, reason: "action-unconfirmed", axError: status.rawValue))
                }
                return true
            }
        }
        defer {
            // Dismiss only our still-identical menu. Never send a global key
            // or cancel a menu after new physical input or an unknown session.
            if let openedMenu, cancellation.reason != .userInput,
               ProcessInfo.processInfo.systemUptime < deadline {
                onMain {
                    guard environmentRead(edge: environment.edge, expected: environment).check.state == .matched,
                          NSEvent.pressedMouseButtons == 0, let shown = currentMenu(), CFEqual(shown, openedMenu) else { return }
                    var actions: CFArray?
                    if AXUIElementCopyActionNames(shown, &actions) == .success,
                       (actions as? [String])?.contains(kAXCancelAction as String) == true {
                        _ = AXUIElementPerformAction(shown, kAXCancelAction as CFString)
                    }
                }
            }
        }
        guard act(source.element, action: kAXShowMenuAction as String) else { return false }
        let menuDeadline = min(deadline, ProcessInfo.processInfo.systemUptime + 0.8)
        while openedMenu == nil, ProcessInfo.processInfo.systemUptime < menuDeadline {
            if let check = priorityInterruption(cancellation, deadline: deadline, forMutation: true) { return fail("wait-menu", check) }
            openedMenu = currentMenu()
            if openedMenu == nil { Thread.sleep(forTimeInterval: 0.015) }
        }
        guard let menu = openedMenu else { return fail("wait-menu", .unavailable("menu-not-ready")) }
        var progress = MacDockNativeURLDragValidation.CleanupMenuProgress()
        let commandDeadline = min(deadline, ProcessInfo.processInfo.systemUptime + 0.8)
        repeat {
            if let check = priorityInterruption(cancellation, deadline: deadline, forMutation: true) { return fail("wait-command", check) }
            guard let shown = currentMenu() else { return fail("wait-command", .unavailable("menu-unavailable")) }
            guard CFEqual(shown, menu) else { return fail("wait-command", .rejected("menu-changed")) }
            let remove = probeMenuItem(menu, titles: ["Remove from Dock", "Dockから削除"], pid: environment.pid)
            let checkedKeep = remove == nil ? probeMenuItem(menu, titles: ["Keep in Dock", "Dockに追加"], pid: environment.pid).flatMap { item -> AXUIElement? in
                guard let mark = attribute(item, kAXMenuItemMarkCharAttribute) as? String, !mark.isEmpty else { return nil }
                return item
            } : nil
            let command = remove ?? checkedKeep
            let options = command == nil ? probeMenuItem(menu, titles: ["Options", "オプション"], pid: environment.pid) : nil
            switch progress.next(optionsAvailable: options != nil, commandAvailable: command != nil, cancelled: cancellation.reason != nil) {
            case .openOptions:
                guard let options, act(options, action: kAXPressAction as String, menu: menu) else { return false }
            case .remove:
                guard let command else { return fail("wait-command", .rejected("command-missing")) }
                return act(command, action: kAXPressAction as String, menu: menu)
            case .stop: return fail("wait-command", .rejected("cancelled"))
            case .wait: break
            }
            Thread.sleep(forTimeInterval: 0.015)
        } while ProcessInfo.processInfo.systemUptime < commandDeadline
        return fail("wait-command", .unavailable("command-not-ready"))
    }
#endif

    private struct ReorderResult {
        let success: Bool
        let message: String
    }

    private nonisolated static func performReorder(members: [String], paths: [String: MetricKind], insertion: Int,
                                                   environment: Environment,
                                                   cancellation: MacDockNativeCancellation) -> ReorderResult {
        let began = ProcessInfo.processInfo.systemUptime
        var stage = "preflight"
        var guardContext = "initial"
        var plannedKeys = 0
        var postedKeys = 0
        var completedKeys = 0
        var selectionChanges = 0
        var plannedRuns = 0
        var selectionWrites = 0
        var orderReadTime: TimeInterval = 0
        var dispatchTime: TimeInterval = 0
        var savedReadTime: TimeInterval = 0
        let owned = Set(members)
        MacDockNativeDiagnostics.log.notice("batch started owned=\(members.count)")
        guard let saved = savedDockState(owned: owned) else {
            MacDockNativeDiagnostics.record(success: false, ownedCount: members.count, stage: stage,
                planned: 0, completed: 0, selectionChanges: 0, began: began, reason: "saved state unavailable")
            return ReorderResult(success: false, message: "Dockの固定状態を確認できないため、移動しませんでした。")
        }
        func finish(_ success: Bool, _ message: String) -> ReorderResult {
            MacDockNativeDiagnostics.record(success: success, ownedCount: members.count, stage: stage,
                planned: plannedKeys, posted: postedKeys, completed: completedKeys, selectionChanges: selectionChanges,
                guardContext: guardContext, began: began, reason: message, runs: plannedRuns,
                selectionWrites: selectionWrites, orderReadMS: Int(orderReadTime * 1_000),
                dispatchMS: Int(dispatchTime * 1_000), savedReadMS: Int(savedReadTime * 1_000))
            let progress = !success && completedKeys > 0 ? "（\(completedKeys)枠の移動後に中止）" : ""
            guard let current = savedDockState(owned: owned) else {
                return ReorderResult(success: success, message: "\(message)\(progress) 固定状態の再確認はできませんでした。")
            }
            let added = current.pins.subtracting(saved.pins).count
            let removed = saved.pins.subtracting(current.pins).count
            return ReorderResult(success: success,
                message: "\(message)\(progress) 固定: \(saved.pins.count)→\(current.pins.count)（追加\(added)・解除\(removed)）。")
        }
        let deadline = began + 12
        // Keep the established main-thread/HID route. The interval is isolated
        // from the one-step probe so it can be tuned without changing that probe.
        let eventInterval: TimeInterval = 0.001
        func interruption(_ context: String, priorityOnly: Bool = false) -> String? {
            guardContext = context
            let check = priorityOnly
                ? (priorityInterruption(cancellation, deadline: deadline, forMutation: true) ?? .matched)
                : checkedEnvironment(edge: environment.edge, expected: environment,
                    cancellation: cancellation, deadline: deadline, forMutation: true, context: context).check
            guard check.state != .matched else { return nil }
            switch check.reason {
            case "cancelled": return "移動をキャンセルしました。"
            case "physical-input": return "ユーザー操作を検出したため、追加の移動を中止しました。"
            case "deadline": return "移動時間の上限に達したため、中止しました。"
            case "accessibility-permission", "event-permission": return "移動中に操作の許可が無効になりました。"
            default:
                return check.state == .unavailable
                    ? "Dockまたは操作できるデスクトップの状態を一時的に確認できないため、中止しました。"
                    : "Dock・画面・操作できるデスクトップの状態が変わったため、中止しました。"
            }
        }
        func readOrder() -> [Item]? {
            let started = ProcessInfo.processInfo.systemUptime
            defer { orderReadTime += ProcessInfo.processInfo.systemUptime - started }
            // Every URL and subrole is live. Pixel frames are only needed for
            // the initial/final layout, not each verified adjacent exchange.
            return snapshot(pid: environment.pid, includingFrames: false)
        }
        func foreignStateUnchanged() -> Bool {
            let started = ProcessInfo.processInfo.systemUptime
            defer { savedReadTime += ProcessInfo.processInfo.systemUptime - started }
            guard let current = savedDockState(owned: owned) else { return false }
            return NSDictionary(dictionary: saved.foreign).isEqual(to: current.foreign)
        }
        if let reason = interruption("initial") { return finish(false, reason) }
        stage = "initial-snapshot"
        guard let initial = readOrder(), validMembers(initial, paths: paths) else {
            return finish(false, "グループの全項目を一意に確認できません。")
        }
        let initialOrder = initial.map(\.path)
        let foreignOrder = initialOrder.filter { !owned.contains($0) }
        let finder = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
            .resolvingSymlinksInPath().standardizedFileURL.path
        stage = "plan"
        guard MacDockNativeMoveValidation.allowsInsertion(insertion, order: initialOrder, members: owned, finder: finder) else {
            return finish(false, "Finderの前やDockの範囲外には移動できません。")
        }
        let indexes = Dictionary(uniqueKeysWithValues: members.enumerated().map { ($0.element, $0.offset) })
        guard let plan = MacDockBlockMovePlan.steps(order: initialOrder.map { indexes[$0] },
                                                    members: Array(members.indices), insertion: insertion) else {
            return finish(false, "グループの移動順を安全に作成できません。")
        }
        plannedKeys = plan.reduce(0) { $0 + abs($1.offset) }
        plannedRuns = plan.count
        guard plannedKeys <= 128 else {
            return finish(false, "移動距離が上限を超えています。近い位置へ分けて移動してください。")
        }
        if plan.isEmpty { return finish(true, "グループは指定位置に整列しています。") }
        var finalOrder = foreignOrder
        finalOrder.insert(contentsOf: members, at: insertion)
        var expectedOrder = initialOrder
        var currentItems = initial
        var acquiredFocus = false
        var selectedElement: AXUIElement?
        defer {
            // A user may have moved focus elsewhere or opened a Dock menu.
            // Never use Escape to clean up somebody else's new interaction.
            if acquiredFocus {
                onMain {
                    guard cancellation.reason != .userInput, ProcessInfo.processInfo.systemUptime < deadline,
                          AXIsProcessTrusted(), NSEvent.pressedMouseButtons == 0 else { return }
                    let read = environmentRead(edge: environment.edge, expected: environment)
                    guard read.check.state == .matched else {
                        MacDockNativeDiagnostics.guardRead(read.check, context: "cleanup"); return
                    }
                    guard systemFocusIsDock(pid: environment.pid, expectedItem: selectedElement) else {
                        MacDockNativeDiagnostics.guardRead(.unavailable("dock-focus"), context: "cleanup"); return
                    }
                    _ = systemKeyStroke(53, hid: true, mainThread: true, eventInterval: eventInterval,
                                        guardContext: "cleanup-session", deadline: deadline)
                }
            }
        }
        stage = "focus"
        if !systemFocusIsDock(pid: environment.pid) {
            guardContext = "before-focus-key"
            let started = onMain {
                let read = checkedEnvironment(edge: environment.edge, expected: environment,
                    cancellation: cancellation, deadline: deadline, forMutation: true, context: "before-focus-key")
                guard read.check.state == .matched else { return false }
                return focusDockWithStandardShortcut(hid: true, mainThread: true,
                    settleDelay: 0, eventInterval: eventInterval, guardContext: "focus-key-session",
                    cancellation: cancellation, deadline: deadline)
            }
            guard started else {
                return finish(false, "標準のControl-F3でDockの操作を開始できませんでした。")
            }
            acquiredFocus = true
            let focusDeadline = ProcessInfo.processInfo.systemUptime + 0.6
            while !systemFocusIsDock(pid: environment.pid) {
                if let reason = interruption("waiting-focus") { return finish(false, reason) }
                guard ProcessInfo.processInfo.systemUptime < focusDeadline else {
                    return finish(false, "Dockへのキーフォーカスを確認できません。")
                }
                Thread.sleep(forTimeInterval: 0.008)
            }
        }
        for step in plan {
            let direction = step.offset > 0 ? 1 : -1
            let key: CGKeyCode = environment.edge == .bottom ? (direction > 0 ? 124 : 123) : (direction > 0 ? 125 : 126)
            for _ in 0..<abs(step.offset) {
                stage = "before-arrow"
                // Until the main-queue gate below, this branch only reads.
                // Recheck cancellation now; validate the complete environment
                // immediately before any selection write or input is posted.
                if let reason = interruption("before-arrow", priorityOnly: true) { return finish(false, reason) }
                guard let fresh = readOrder(), fresh.map(\.path) == expectedOrder,
                      let target = fresh.first(where: { $0.path == members[step.member] }),
                      systemFocusIsDock(pid: environment.pid),
                      foreignStateUnchanged(),
                      let nextOrder = MacDockNativeMoveValidation.adjacentOrder(expectedOrder,
                          member: members[step.member], direction: direction) else {
                    return finish(false, "移動直前の順番・Dockフォーカス・設定を確認できないため、中止しました。")
                }
                guardContext = "before-arrow-key"
                let dispatchStarted = ProcessInfo.processInfo.systemUptime
                let attempt: (posted: Bool, selected: Bool, stage: String, wroteSelection: Bool) = onMain {
                    // Recheck after entering the main queue: an input monitor
                    // may have cancelled this transaction while it was queued.
                    let read = checkedEnvironment(edge: environment.edge, expected: environment,
                        cancellation: cancellation, deadline: deadline, forMutation: true, context: "before-arrow-key")
                    guard read.check.state == .matched else {
                        return (false, false, "send-context", false)
                    }
                    let selection = selectOwnedItem(target, expectedPath: members[step.member], pid: environment.pid)
                    guard selection.isReady else { return (false, false, "selection-\(selection.rawValue)", false) }
                    // Verify the exact target before every arrow, even when
                    // the selection write was unnecessary for this member.
                    guard cancellation.reason == nil, NSEvent.pressedMouseButtons == 0,
                          ProcessInfo.processInfo.systemUptime < deadline,
                          attribute(target.element, kAXSelectedAttribute) as? Bool == true,
                          systemFocusIsDock(pid: environment.pid, expectedItem: target.element) else {
                        return (false, true, "send-recheck", selection == .ready)
                    }
                    return (systemKeyStroke(key, modifier: 58, flags: .maskAlternate, hid: true,
                        mainThread: true, eventInterval: eventInterval, guardContext: "arrow-key-session",
                        cancellation: cancellation, deadline: deadline), true, "send", selection == .ready)
                }
                dispatchTime += ProcessInfo.processInfo.systemUptime - dispatchStarted
                if attempt.wroteSelection { selectionWrites += 1 }
                if attempt.selected { selectedElement = target.element }
                stage = attempt.stage
                guard attempt.posted else {
                    return finish(false, "キー操作を安全に送れないため、中止しました。")
                }
                postedKeys += 1
                stage = "confirm-arrow"
                let movementDeadline = ProcessInfo.processInfo.systemUptime + 0.6
                var didMove = false
                while !didMove {
                    if let reason = interruption("waiting-order") { return finish(false, reason) }
                    guard let observed = readOrder() else {
                        return finish(false, "移動後のDockを確認できないため、中止しました。")
                    }
                    switch MacDockNativeMoveValidation.observe(observed.map(\.path), before: expectedOrder, expected: nextOrder) {
                    case .changed:
                        return finish(false, "想定した隣接交換以外の変更を検出したため、中止しました。")
                    case .completed:
                        guard let target = observed.first(where: { $0.path == members[step.member] }) else {
                            return finish(false, "移動後の対象項目を確認できないため、中止しました。")
                        }
                        // Count an observed exchange even if a subsequent
                        // focus change requires us to stop. Diagnostics must
                        // not report zero movement after a real partial move.
                        currentItems = observed
                        selectedElement = target.element
                        expectedOrder = nextOrder
                        completedKeys += 1
                        guardContext = "after-exchange"
                        let selected = attribute(target.element, kAXSelectedAttribute) as? Bool == true
                        let foreignUnchanged = foreignStateUnchanged()
                        let dockFocused = systemFocusIsDock(pid: environment.pid)
                        switch MacDockNativeMoveValidation.completedExchange(observation: .completed,
                            dockHasFocus: dockFocused, targetSelected: selected, foreignUnchanged: foreignUnchanged,
                            cancelled: cancellation.reason != nil) {
                        case .stopped:
                            if let reason = interruption("after-exchange") { return finish(false, reason) }
                            return finish(false, "移動後のDockフォーカス・設定が変わったため、中止しました。")
                        case .verifiedWithSelectionChange:
                            selectionChanges += 1
                        case .verified:
                            break
                        }
                        didMove = true
                    case .waiting:
                        guard systemFocusIsDock(pid: environment.pid) else {
                            return finish(false, "移動の確認中にDockフォーカスが変わったため、中止しました。")
                        }
                        guard ProcessInfo.processInfo.systemUptime < movementDeadline else {
                            return finish(false, "1枠の移動を確認できなかったため、中止しました。")
                        }
                        Thread.sleep(forTimeInterval: 0.008)
                    }
                }
            }
        }
        stage = "final-validation"
        if let reason = interruption("final-validation") { return finish(false, reason) }
        guard currentItems.map(\.path) == finalOrder, validMembers(currentItems, paths: paths),
              let final = readOrder(), final.map(\.path) == finalOrder,
              foreignStateUnchanged(), systemFocusIsDock(pid: environment.pid) else {
            return finish(false, "グループの最終配置を確認できません。")
        }
        return finish(true, "成功：Dockを再起動せず、グループをまとめて移動しました。")
    }

    private nonisolated static func performStep(path: String, pid: pid_t, key: CGKeyCode, forward: Bool, selection: Selection) -> String {
        guard sessionAllowsInteraction() else { return "操作できるデスクトップではないため、中止しました。" }
        guard let before = snapshot(pid: pid), before.filter({ $0.path == path }).count == 1,
              let index = before.firstIndex(where: { $0.path == path }) else { return "DaysYetの対象アイコンを確認できません。" }
        guard (0..<before.count).contains(index + (forward ? 1 : -1)) else { return "すでにDockの端です。" }
        let item = before[index]
        let root = AXUIElementCreateApplication(pid)
        _ = AXUIElementSetMessagingTimeout(root, 0.025)
        let usesShortcut = [.dockShortcut, .dockShortcutHID, .dockShortcutMain].contains(selection)
        let focusBefore = usesShortcut ? focusSummary(pid: pid, item: item.element) : ""
        if usesShortcut, !focusDockWithStandardShortcut(hid: selection != .dockShortcut, mainThread: selection == .dockShortcutMain) {
            return "標準のControl-F3が無効または変更されているため、中止しました。"
        }
        let focusAfterShortcut = usesShortcut ? focusSummary(pid: pid, item: item.element) : ""
        defer {
            if usesShortcut, sessionAllowsInteraction(), systemFocusIsDock(pid: pid) {
                _ = systemKeyStroke(53)
            }
        }
        let target: AXUIElement
        let name: String
        let value: CFTypeRef
        switch selection {
        case .selected: target = item.element; name = kAXSelectedAttribute; value = kCFBooleanTrue
        case .focused: target = item.element; name = kAXFocusedAttribute; value = kCFBooleanTrue
        case .focusedElement: target = root; name = kAXFocusedUIElementAttribute; value = item.element
        case .focusedList, .selectedChildren, .selectedChildrenBalanced, .dockShortcut, .dockShortcutHID, .dockShortcutMain:
            guard let parent = attribute(item.element, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { return "Dockの親要素がありません。" }
            target = parent as! AXUIElement; name = kAXSelectedChildrenAttribute; value = [item.element] as CFArray
            if selection == .focusedList {
                var writable = DarwinBoolean(false)
                guard attribute(target, kAXRoleAttribute) as? String == kAXListRole as String,
                      AXUIElementIsAttributeSettable(target, kAXFocusedAttribute as CFString, &writable) == .success,
                      writable.boolValue else { return "DockリストはAXFocusedの変更に対応していません。" }
                guard AXUIElementSetAttributeValue(target, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success,
                      attribute(target, kAXFocusedAttribute) as? Bool == true else { return "Dockリストのフォーカスを取得できません。" }
            }
        case .frontmost: target = root; name = kAXFrontmostAttribute; value = kCFBooleanTrue
        }
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(target, name as CFString, &settable) == .success,
              settable.boolValue else { return "Dockは \(name) の変更に対応していません。" }
        let selected = AXUIElementSetAttributeValue(target, name as CFString, value)
        guard selected == .success else { return "\(name) の変更に失敗しました（\(selected.rawValue)）。" }
        if selection == .frontmost {
            _ = AXUIElementSetAttributeValue(item.element, kAXSelectedAttribute as CFString, kCFBooleanTrue)
        }
        var actual: CFTypeRef?
        guard AXIsProcessTrusted() else { return "移動直前に権限が無効になりました。" }
        let selectionRead = AXUIElementCopyAttributeValue(item.element, kAXSelectedAttribute as CFString, &actual)
        let focused = attribute(item.element, kAXFocusedAttribute) as? Bool
        let focusedItem = attribute(root, kAXFocusedUIElementAttribute)
        let isFocusTarget = focusedItem.map { CFEqual($0, item.element) } == true
        if let focusedItem, CFGetTypeID(focusedItem) == AXUIElementGetTypeID(),
           attribute(focusedItem as! AXUIElement, kAXRoleAttribute) as? String == kAXDockItemRole as String,
           !isFocusTarget { return "キー入力先が別のDock項目のため中止しました。" }
        guard (selectionRead == .success && actual as? Bool == true) || focused == true || isFocusTarget else {
            return "\(name)：選択 \((actual as? Bool).map(String.init) ?? "不明")、フォーカス \(focused.map(String.init) ?? "不明")、対象一致 \(isFocusTarget)。移動は未実行です。"
        }
        guard let fresh = snapshot(pid: pid) else { return "選択後のDockの順番を読み取れませんでした。" }
        guard fresh.map(\.path) == before.map(\.path) else { return "選択後にDockの順番が変わったため中止しました。" }
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else {
            return "Dock宛ての移動操作を作成できませんでした。"
        }
        // Alternate is attached to these two events only. Never synthesize a
        // modifier-down sequence that could leave a modifier stuck globally.
        down.flags.formUnion(.maskAlternate)
        up.flags.formUnion(.maskAlternate)
        down.setIntegerValueField(.eventSourceUserData, value: 0x4459534E41544956)
        up.setIntegerValueField(.eventSourceUserData, value: 0x4459534E41544956)
        guard sessionAllowsInteraction() else { return "操作できるデスクトップではないため、中止しました。" }
        if usesShortcut {
            guard systemFocusIsDock(pid: pid, expectedItem: item.element),
                  attribute(item.element, kAXSelectedAttribute) as? Bool == true,
                  !CGEventSource.buttonState(.combinedSessionState, button: .left),
                  systemKeyStroke(key, modifier: 58, flags: .maskAlternate, hid: selection != .dockShortcut, mainThread: selection == .dockShortcutMain) else {
                return "Dockへのフォーカスを確認できません。\n前: \(focusBefore)\nキー後: \(focusAfterShortcut)\n選択後: \(focusSummary(pid: pid, item: item.element))"
            }
        } else if selection == .selectedChildrenBalanced || selection == .focusedList {
            guard let events = MacDockNativeKeySequence.make(key: key, modifier: 58, flags: .maskAlternate) else { return "操作を作成できません。" }
            for event in events {
                event.postToPid(pid)
                Thread.sleep(forTimeInterval: 0.012)
            }
        } else {
            down.postToPid(pid)
            up.postToPid(pid)
        }
        // A bounded wait on the private worker queue lets Dock finish its
        // normal animation; the application main thread stays responsive.
        Thread.sleep(forTimeInterval: 0.2)
        guard let after = snapshot(pid: pid), after.filter({ $0.path == path }).count == 1,
              let destination = after.firstIndex(where: { $0.path == path }) else { return "移動後の位置を確認できません。" }
        guard before.filter({ $0.path != path }).map(\.path) == after.filter({ $0.path != path }).map(\.path) else {
            return "他項目にも変更があったため、追加操作を中止しました。"
        }
        if destination == index + (forward ? 1 : -1) { return "成功：Dockを再起動せず、対象の丸を1枠移動しました。" }
        return "選択には成功しましたが、位置は変わりませんでした（\(index) → \(destination)）。"
    }
}

#if DAYSYET_DOCK_REORDER_PROBE
@MainActor
final class MacDockNativeMoveProbe: ObservableObject {
    @Published var status = "Dockに配置してから、1枠の移動を確認します。"
    @Published var selection = MacDockNativeMover.Selection.selected
    private let mover = MacDockNativeMover()
    private var window: NSWindow?
    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 420),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "DaysYet — Dock並べ替えの試作"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: MacDockNativeMoveProbeView(probe: self))
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func move(forward: Bool) {
        let model = MacAppModel.shared
        guard !mover.busy else { return }
        guard model.preferences.isInSystemDock, let metric = model.store.profile.macDashboardMetrics.first else {
            status = "まずDockに配置してください。"; return
        }
        status = "対象の丸とDockの順番を確認しています…"
        model.directDockController.setNativeReorderSuspended(true)
        mover.step(metric: metric, edge: model.preferences.lastSystemDockEdge, forward: forward, selection: selection) { [weak self, weak model] result in
            model?.directDockController.setNativeReorderSuspended(false)
            self?.status = result
        }
    }
    func unpin() {
        let model = MacAppModel.shared
        guard !mover.busy, let metric = model.store.profile.macDashboardMetrics.first else { return }
        model.directDockController.setNativeReorderSuspended(true)
        mover.unpin(metric: metric) { [weak self, weak model] result in
            model?.directDockController.setNativeReorderSuspended(false)
            self?.status = result
        }
    }

    func moveGroup(by offset: Int) {
        let model = MacAppModel.shared
        guard !mover.busy, model.preferences.isInSystemDock else { return }
        let metrics = model.store.profile.macDashboardMetrics
        let edge = model.controller.currentSystemDockEdge ?? model.preferences.lastSystemDockEdge
        status = "グループの位置を確認しています…"
        model.directDockController.setNativeReorderSuspended(true)
        mover.readLayout(metrics: metrics, edge: edge) { [weak self, weak model] layout in
            guard let self, let model else {
                model?.directDockController.setNativeReorderSuspended(false)
                return
            }
            guard model.preferences.isInSystemDock, model.store.profile.macDashboardMetrics == metrics,
                  let layout, let first = layout.items.firstIndex(where: { $0.metric != nil }) else {
                model.directDockController.setNativeReorderSuspended(false)
                self.status = "グループの位置を確認できません。"
                return
            }
            let current = layout.items[..<first].filter { $0.metric == nil }.count
            let insertion = current + offset
            let foreignCount = layout.items.filter { $0.metric == nil }.count
            guard (1...max(1, foreignCount)).contains(insertion), insertion <= foreignCount else {
                model.directDockController.setNativeReorderSuspended(false)
                self.status = "Finderの前やDockの範囲外には移動できません。"
                return
            }
            self.status = "グループを移動しています…"
            self.mover.reorder(metrics: metrics, edge: edge, insertion: insertion) { [weak self, weak model] _, _, message in
                model?.directDockController.setNativeReorderSuspended(false)
                self?.status = message
            }
        }
    }

    func cancel() { mover.cancel() }
}

private struct MacDockNativeMoveProbeView: View {
    @ObservedObject var probe: MacDockNativeMoveProbe
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Dockを再起動せずに並べ替える").font(.title2.weight(.semibold))
            Text("まず先頭の丸を1枠だけ動かして、標準の移動操作を確認します。")
                .font(.callout).foregroundStyle(.secondary)
            Picker("選択方法", selection: $probe.selection) {
                ForEach(MacDockNativeMover.Selection.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            HStack {
                Button("Dockに配置") {
                    let model = MacAppModel.shared
                    model.controller.selectEdge(model.controller.currentSystemDockEdge ?? model.preferences.lastSystemDockEdge)
                }
                Button("1枠前へ") { probe.move(forward: false) }
                Button("1枠後へ") { probe.move(forward: true) }
                Button("固定解除") { probe.unpin() }
            }
            HStack {
                Button("グループ1枠前へ") { probe.moveGroup(by: -1) }
                Button("グループ1枠後へ") { probe.moveGroup(by: 1) }
                Button("グループを整列") { probe.moveGroup(by: 0) }
                Button("中止") { probe.cancel() }
            }
            Text(probe.status).font(.callout).fixedSize(horizontal: false, vertical: true)
            Button("アクセシビリティ設定…") { MacAppModel.shared.directDockController.openAccessibilitySettings() }
                .font(.caption)
        }
        .padding(24).frame(width: 620, height: 420)
    }
}
#endif
#endif
