#if DAYSYET_DIRECT_DOCK_DRAG && DAYSYET_DOCK_NATIVE_REORDER && DAYSYET_DOCK_REORDER_PROBE
import AppKit
import OSLog
import SwiftUI

enum MacDockNativeURLDragMode: String, CaseIterable, Identifiable {
    case move, link, publicOperations, copy
    var id: String { rawValue }
    var operationMask: NSDragOperation {
        switch self {
        case .move: .move
        case .link: .link
        case .publicOperations: [.copy, .move, .link, .generic]
        case .copy: .copy
        }
    }
    var title: String {
        switch self {
        case .move: "Move"
        case .link: "Link"
        case .publicOperations: "Copy / Move / Link / Generic"
        case .copy: "Copy"
        }
    }
}

enum MacDockNativeURLDragProbePhase: String {
    case idle, preparing, dragging, inspecting, cleaning, blocked
    var canClose: Bool { self == .idle }
    var canStartDrag: Bool { self == .idle }
}

/// A disposable-file experiment, not a production helper rearranger. All Dock
/// identities and foreign saved-record evidence remain private and in memory.
@MainActor
final class MacDockNativeURLDragProbe: NSObject, ObservableObject, NSWindowDelegate {
    private static let shared = MacDockNativeURLDragProbe()
    private static let log = Logger(subsystem: "com.hinoshiba.daysyet", category: "native-dock-url-probe")
    static func show() { shared.open() }

    static func requestApplicationTermination() -> NSApplication.TerminateReply {
        guard MacDockRegistrationCleanup.nativeURLProbePending else { return .terminateNow }
        shared.open()
        shared.terminationRequested = true
        shared.requestClose()
        // Always reply on a later MainActor turn, including an already-clean
        // recovery. NSApplication must receive terminateLater before the reply.
        return .terminateLater
    }

    @Published var mode: MacDockNativeURLDragMode = .move {
        didSet { trace("mode.selected") }
    }
    @Published private(set) var phase: MacDockNativeURLDragProbePhase = .inspecting {
        didSet { trace("phase.changed") }
    }
    @Published private(set) var status = L10n.text("Dockの状態を確認しています。", "Inspecting the Dock.")
    @Published private(set) var seedRequired = true {
        didSet { trace("seed.changed") }
    }
    @Published private(set) var recoveryRequired = false
    @Published private(set) var image: NSImage?
    @Published private(set) var lastResult: String?
    @Published private(set) var lastInspection = ""
    private let mover = MacDockNativeMover()
    private var window: NSWindow?
    private var metrics: [MetricKind] = []
    private var initial: MacDockNativeProbeState?
    private var suspended = false
    private var closeRequested = false
    private var terminationRequested = false
    private var preparationID: UUID?
    private var readingPreparation = false
    private var configuration: Configuration?
    private var beganFreshSession = false
    private var nativeDragStarted = false
    private var sessionNumber = 0
    private var eventNumber = 0
    private var statusCode = "initial"
    private var preparationWatchdog: Timer?
    private var preparationReadyAt: TimeInterval?

    fileprivate struct PreparedDrag {
        let before: MacDockNativeProbeState
        let urls: [URL]
        let operation: NSDragOperation
        let image: NSImage
        let seed: Bool
        let id: UUID
        let preparedAt: TimeInterval
    }

    private struct Configuration {
        let metrics: [MetricKind]
        let edge: MacWidgetEdge
        let visible: Bool
        let inDock: Bool
        let screens: [NSRect]

        @MainActor init() {
            let model = MacAppModel.shared
            metrics = model.store.profile.macDashboardMetrics
            edge = model.controller.currentSystemDockEdge ?? model.preferences.lastSystemDockEdge
            visible = model.preferences.isVisible
            inDock = model.preferences.isInSystemDock
            screens = NSScreen.screens.map(\.frame)
        }

        @MainActor var stillMatches: Bool {
            let current = Self()
            return metrics == current.metrics && edge == current.edge && visible == current.visible
                && inDock == current.inDock && screens == current.screens
        }
    }

    fileprivate var canDrag: Bool {
        phase.canStartDrag && !closeRequested && !recoveryRequired && !mover.busy
    }

    private var edge: MacWidgetEdge {
        let model = MacAppModel.shared
        return model.controller.currentSystemDockEdge ?? model.preferences.lastSystemDockEdge
    }

    private func open() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            trace("window.reused")
            return
        }
        sessionNumber += 1
        closeRequested = false
        recoveryRequired = false
        seedRequired = true
        beganFreshSession = false
        nativeDragStarted = false
        lastInspection = ""
        initial = nil
        configuration = Configuration()
        let pending = MacDockRegistrationCleanup.nativeURLProbePending
        metrics = pending ? (MacDockRegistrationCleanup.pendingNativeURLProbeMetrics ?? [])
            : (configuration?.metrics ?? [])
        image = makeImage()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 590),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = L10n.text("DaysYet — Dock一括ドラッグの検証", "DaysYet — Native Dock Group Drag Trial")
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: MacDockNativeURLDragProbeView(probe: self))
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        trace(pending ? "window.opened-recovery" : "window.opened-fresh")

        guard MacDockNativeURLProbeFixtures.paths(metrics: metrics) != nil else {
            if pending { suspend() }
            block(L10n.text("検証する6項目を確認できません。未解決の検証がある場合、通常操作は停止したままです。",
                            "The six trial members could not be identified. Any unresolved trial remains suspended."), code: "initial.invalid-members")
            return
        }
        if !pending {
            // No suspension/await between checking the global mutation owner
            // and setting the persistent exclusion marker.
            guard MacDockNativeMover.nativeURLProbeCanStart,
                  MacDockRegistrationCleanup.beginNativeURLProbe(metrics: metrics) else {
                block(L10n.text("別のDock操作が進行中です。この画面を閉じ、完了後に開き直してください。",
                                "Another Dock operation is running. Close this window and reopen it when that finishes."), code: "initial.mutation-busy")
                return
            }
            beganFreshSession = true
        }
        suspend()
        phase = .inspecting
        updateStatus("initial.reading", L10n.text("検証用アイコンの状態を確認しています。", "Inspecting the disposable test icons."))
        Task { @MainActor in
            guard let state = await inspect("initial") else {
                block(readFailure, code: "initial.read-failed")
                return
            }
            if pending {
                recoveryRequired = true
                block(L10n.text("前回の検証が未完了です。「検証アイコンを片付けて閉じる」で現在の固定を確認して解除してください。",
                                "An earlier trial is unfinished. Use Clean Up Test Icons and Close to inspect and remove its current pins."), code: "initial.pending-session")
            } else if Self.isEmpty(state) {
                initial = state
                seedRequired = true
                phase = .idle
                updateStatus("initial.ready-empty", L10n.text("① 丸をDockへドラッグして、検証用アイコン6個をコピーで追加します。",
                                   "1. Drag the circle into the Dock to add six disposable test icons using Copy."))
            } else {
                recoveryRequired = true
                block(L10n.text("検証用アイコンがすでに残っています。新しい検証の前に、現在の固定を確認して片付けてください。",
                                "Test icons already remain in the Dock. Inspect and clean them up before starting a new trial."), code: "initial.existing-fixtures")
            }
            continueClosingIfRequested()
        }
    }

    private func suspend() {
        guard !suspended else { return }
        suspended = true
        MacAppModel.shared.directDockController.setNativeReorderSuspended(true)
    }

    fileprivate func prepareDrag(completion: @escaping (PreparedDrag?) -> Void) {
        trace("prepare.requested")
        guard canDrag, configuration?.stillMatches == true,
              MacDockRegistrationCleanup.nativeURLProbePending,
              MacDockNativeURLProbeFixtures.available(metrics: metrics),
              let paths = MacDockNativeURLProbeFixtures.paths(metrics: metrics), let image else {
            if phase == .idle {
                block(L10n.text("設定または検証用アプリが変わりました。検証を終了して片付けてください。",
                                "The configuration or disposable apps changed. End the trial and clean up."), code: "prepare.precondition-failed")
            }
            completion(nil)
            return
        }
        let id = UUID()
        let frozenMode = mode
        preparationID = id
        preparationReadyAt = nil
        readingPreparation = true
        phase = .preparing
        startPreparationWatchdog()
        updateStatus("prepare.reading", L10n.text("押したまま少し待ってください。操作直前のDockを確認しています。",
                           "Keep holding briefly while the current Dock state is checked."))
        Task { @MainActor in
            let state = await inspect("prepare")
            readingPreparation = false
            guard preparationID == id, !closeRequested else {
                stopPreparationWatchdog()
                phase = .idle
                updateStatus("prepare.released", L10n.text("手が離されたため、ドラッグを開始しませんでした。もう一度丸を掴んでください。",
                    "The press ended before preparation finished. Grab the circle again to retry."))
                completion(nil)
                continueClosingIfRequested()
                return
            }
            guard let state else {
                preparationID = nil
                block(readFailure, code: "prepare.read-failed")
                completion(nil)
                return
            }
            guard let initial,
                  configuration?.stillMatches == true, state.sameEnvironment(as: initial),
                  state.foreignOrder == initial.foreignOrder,
                  state.foreignSavedRecords == initial.foreignSavedRecords,
                  Self.isEmpty(state) || Self.isComplete(state) else {
                preparationID = nil
                block(L10n.text("操作直前の状態が揃わないため、ドラッグを開始しませんでした。検証を終了して片付けてください。",
                                "The current state could not be verified, so no drag started. End the trial and clean up."), code: "prepare.invariant-failed")
                completion(nil)
                return
            }
            let seed = Self.isEmpty(state)
            seedRequired = seed
            preparationReadyAt = ProcessInfo.processInfo.systemUptime
            updateStatus("prepare.ready", L10n.text("確認できました。押したまま丸を動かしてください。",
                "The state is verified. Move the circle while keeping the button held."))
            trace("prepare.ready", operation: seed ? .copy : frozenMode.operationMask, state: state)
            completion(PreparedDrag(before: state, urls: metrics.compactMap { paths[$0].map { URL(fileURLWithPath: $0) } },
                operation: seed ? .copy : frozenMode.operationMask, image: image, seed: seed, id: id,
                preparedAt: ProcessInfo.processInfo.systemUptime))
        }
    }

    fileprivate func cancelPreparation() {
        trace("prepare.cancelled")
        preparationID = nil
        stopPreparationWatchdog()
        if phase == .preparing, readingPreparation {
            updateStatus("prepare.cancelled-await-read", L10n.text("手が離されました。確認処理が終わるまで待っています。ドラッグは開始しません。",
                "The press ended. Waiting for the read to finish; no drag will start."))
        }
        if phase == .preparing, !readingPreparation {
            phase = .idle
            updateStatus("prepare.cancelled", L10n.text("ドラッグ準備を取り消しました。", "Drag preparation cancelled."))
            continueClosingIfRequested()
        }
    }

    fileprivate func beginDrag(_ prepared: PreparedDrag) -> Bool {
        guard phase == .preparing, preparationID == prepared.id, !closeRequested,
              configuration?.stillMatches == true, NSEvent.pressedMouseButtons & 1 != 0,
              ProcessInfo.processInfo.systemUptime - prepared.preparedAt <= 0.75,
              prepared.urls.count == 6, MacDockNativeURLProbeFixtures.available(metrics: metrics) else {
            trace("drag.start-rejected", operation: prepared.operation)
            cancelPreparation()
            return false
        }
        preparationID = nil
        stopPreparationWatchdog()
        nativeDragStarted = true
        phase = .dragging
        updateStatus("drag.started", prepared.seed
            ? L10n.text("コピーで6個追加します。Dock上で離してください。", "Release over the Dock to add six icons using Copy.")
            : L10n.text("既存の6個を一度のドラッグで移せるか確認しています。Dock上で離してください。",
                        "Testing whether one native drag can move the existing six icons. Release over the Dock."))
        trace("drag.started", operation: prepared.operation, state: prepared.before)
        return true
    }

    fileprivate func dragEnded(_ prepared: PreparedDrag, point: NSPoint, operation: NSDragOperation) {
        trace("drag.ended", operation: operation)
        guard phase == .dragging else { trace("drag.end-ignored"); return }
        phase = .inspecting
        updateStatus("drag.inspecting", L10n.text("Dockの動きが落ち着いてから、実際の順序を確認しています。",
                           "Waiting for the Dock to settle, then inspecting its actual order."))
        let insertion = Self.insertion(at: point, state: prepared.before)
        Task { @MainActor in
            guard let after = await settledInspection() else {
                block(readFailure, code: "result.read-failed")
                retainResult("result.read-failed", operation: operation)
                continueClosingIfRequested()
                return
            }
            let environmentMatches = configuration?.stillMatches == true && prepared.before.sameEnvironment(as: after)
            let foreignMatches = prepared.before.foreignOrder == after.foreignOrder
                && prepared.before.foreignSavedRecords == after.foreignSavedRecords
            if prepared.seed {
                if environmentMatches, foreignMatches, Self.isComplete(after) {
                    seedRequired = false
                    phase = .idle
                    updateStatus("seed.added-six", L10n.text("6個の検証アイコンを追加しました。これは追加の確認です。② モードを選び、同じ丸をもう一度ドラッグして既存6個の移動を試します。",
                                       "Six test icons were added. This confirms addition only. 2. Select a mode, then drag the same circle again to test moving those existing six icons."))
                } else if environmentMatches, foreignMatches, Self.isEmpty(after) {
                    phase = .idle
                    updateStatus("seed.unchanged-empty", L10n.text("追加されませんでした（取消またはDockが未受理）。もう一度試せます。",
                                       "Nothing was added: the drag was cancelled or not accepted by the Dock. You can try again."))
                } else {
                    block(L10n.text("追加後の6個または他アイコンの状態が揃いません。移動成功とは判定せず、検証を停止しました。",
                                    "The added group or other Dock items did not match. This is not a successful move; the trial is stopped."), code: "seed.mismatch")
                }
            } else {
                let result = MacDockNativeURLDragValidation.classify(before: prepared.before.orderedIdentities,
                    after: after.orderedIdentities, members: prepared.before.ownedIdentities, insertion: insertion,
                    environmentMatches: environmentMatches, foreignRecordsMatch: foreignMatches)
                switch result {
                case .moved:
                    guard Self.isComplete(after) else {
                        block(L10n.text("移動後の6個の固定を確認できません。検証を停止しました。",
                                        "The six pins could not be confirmed after the move. The trial stopped."), code: "mode.moved-pins-mismatch")
                        retainResult("mode.moved-pins-mismatch", operation: operation, state: after)
                        continueClosingIfRequested()
                        return
                    }
                    phase = .idle
                    updateStatus("mode.moved", L10n.text("実際の順序から、既存6個が指定位置へ移ったことを確認しました。アニメーションの滑らかさは見た目で確認してください。",
                                       "The actual order confirms that the existing six icons reached the requested gap. Judge the animation's smoothness visually."))
                case .unchanged:
                    guard Self.isComplete(after) else {
                        block(L10n.text("順序は同じですが、6個の固定状態が変わりました。検証を停止しました。",
                                        "The order is unchanged, but the six pins changed. The trial stopped."), code: "mode.unchanged-pins-mismatch")
                        retainResult("mode.unchanged-pins-mismatch", operation: operation, state: after)
                        continueClosingIfRequested()
                        return
                    }
                    phase = .idle
                    updateStatus("mode.unchanged", operation.isEmpty
                        ? L10n.text("順序は変わりませんでした。取消または未受理です。", "The actual order did not change: cancelled or not accepted.")
                        : L10n.text("Dockから完了通知がありましたが、既存6個の順序は変わりませんでした。",
                                    "The Dock reported completion, but the existing six icons did not move."))
                case .wrongInsertion:
                    block(L10n.text("指定位置への一括移動は確認できませんでした。位置違い・分散・Dock外へのドロップの可能性があります。",
                                    "A group move to the requested gap could not be confirmed: the position, grouping, or drop destination differed."), code: "mode.wrong-insertion")
                case .invalidIdentity:
                    block(L10n.text("6個の一致を確認できません。欠落や重複の可能性があるため検証を停止しました。",
                                    "The six identities could not be verified. The trial stopped because items may be missing or duplicated."), code: "mode.invalid-identity")
                case .environmentChanged:
                    block(L10n.text("Dock・画面・設定が変わったため、結果を確定せず停止しました。",
                                    "The Dock, displays, or configuration changed, so no result was confirmed."), code: "mode.environment-changed")
                case .foreignChanged:
                    block(L10n.text("検証用以外のアイコンに変化がありました。追加の操作を止めました。",
                                    "Other Dock items changed. Further trial operations are stopped."), code: "mode.foreign-changed")
                }
            }
            retainResult(statusCode, operation: operation, state: after)
            continueClosingIfRequested()
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        trace("window.close-requested")
        requestClose()
        return false
    }

    func windowDidBecomeKey(_ notification: Notification) { trace("window.became-key") }
    func windowDidResignKey(_ notification: Notification) { trace("window.resigned-key") }
    func windowWillClose(_ notification: Notification) { trace("window.will-close") }

    fileprivate func requestClose() {
        trace("close.requested")
        closeRequested = true
        if !MacDockRegistrationCleanup.nativeURLProbePending {
            finishClosing()
            return
        }
        switch phase {
        case .dragging:
            updateStatus("close.waiting-drag", L10n.text("ドラッグを離すかEscapeで取り消すと、確認と後片付けを行います。",
                               "Release the drag or press Escape; inspection and cleanup will then continue."))
        case .preparing:
            cancelPreparation()
        case .inspecting, .cleaning:
            break
        case .idle, .blocked:
            if initial != nil, !recoveryRequired { cleanUp(recovery: false) }
            else {
                block(L10n.text("現在残っている検証用の固定を解除するには、「検証アイコンを片付けて閉じる」を押してください。",
                                "Use Clean Up Test Icons and Close to authorize removing the currently remaining test pins."), code: "close.requires-recovery")
            }
        }
    }

    fileprivate func recoverAndClose() {
        trace("recovery.requested")
        guard phase == .blocked || phase == .idle, !mover.busy,
              MacDockRegistrationCleanup.nativeURLProbePending,
              MacDockNativeURLProbeFixtures.paths(metrics: metrics) != nil else { return }
        closeRequested = true
        cleanUp(recovery: true)
    }

    fileprivate func retryInspection() {
        guard phase == .blocked, !mover.busy, !readingPreparation, !terminationRequested,
              MacDockRegistrationCleanup.nativeURLProbePending,
              MacDockNativeURLProbeFixtures.paths(metrics: metrics) != nil else {
            trace("retry.rejected")
            return
        }
        trace("retry.requested")
        closeRequested = false
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        phase = .inspecting
        updateStatus("retry.reading", L10n.text("現在の状態を読み直しています。前回の判定は下に残ります。",
            "Reading the current state again. The previous trial result is retained below."))
        Task { @MainActor in
            guard let state = await inspect("retry") else {
                block(readFailure, code: "retry.read-failed")
                return
            }
            guard !recoveryRequired else {
                block(L10n.text("現在の検証アイコンは\(state.items.compactMap(\.metric).count)個、固定は\(state.ownPinnedMetrics.count)個です。未完了の片付けを終えてから、新しい検証を開始してください。",
                                "The Dock currently has \(state.items.compactMap(\.metric).count) test icons and \(state.ownPinnedMetrics.count) test pins. Finish cleanup before starting a new trial."), code: "retry.recovery-only")
                return
            }
            guard configuration?.stillMatches == true else {
                block(L10n.text("検証開始時から画面または設定が変わっています。現在の検証を片付けてください。",
                                "The displays or configuration changed since this trial began. Clean up the current trial."), code: "retry.configuration-changed")
                return
            }
            if let initial {
                guard initial.sameEnvironment(as: state), initial.foreignOrder == state.foreignOrder,
                      initial.foreignSavedRecords == state.foreignSavedRecords,
                      Self.isEmpty(state) || Self.isComplete(state) else {
                    block(L10n.text("開始時のDock状態との一致を確認できません。成功判定を変えず、検証を停止したままにします。",
                                    "The Dock no longer matches the initial state. The previous verdict is retained and the trial stays stopped."), code: "retry.invariant-mismatch")
                    return
                }
            } else {
                // Only this process's untouched new session can establish a
                // delayed empty baseline. A crash/recovery session or an
                // existing six-icon group must never fabricate a seed result.
                guard beganFreshSession, !nativeDragStarted, Self.isEmpty(state) else {
                    recoveryRequired = true
                    block(L10n.text("追加前に検証アイコンが0個だったことを確認できません。現在の固定を片付けてから、新しい検証を開始してください。",
                                    "An empty pre-addition state could not be established. Clean up the current pins before starting a new trial."), code: "retry.no-empty-baseline")
                    return
                }
                self.initial = state
                trace("retry.established-empty-baseline", state: state)
            }
            seedRequired = Self.isEmpty(state)
            phase = .idle
            updateStatus("retry.ready", seedRequired
                ? L10n.text("追加前の検証アイコン0個・固定0個を確認しました。まず丸をDockへドラッグして6個を追加してください。",
                            "Confirmed zero test icons and zero pins before addition. Drag the circle into the Dock to add six icons first.")
                : L10n.text("開始時の条件と6個の並びを再確認しました。前回の結果はそのまま残し、次のドラッグを試せます。",
                            "The original conditions and the six-icon group were reverified. The previous result is unchanged; you can try another drag."))
            continueClosingIfRequested()
        }
    }

    private func continueClosingIfRequested() {
        guard closeRequested else { return }
        requestClose()
    }

    private func cleanUp(recovery: Bool) {
        guard !mover.busy, phase != .dragging, phase != .cleaning else { return }
        // Once cleanup has been requested, any failed read stays a recovery
        // flow rather than silently resuming native drag experiments.
        recoveryRequired = true
        phase = .cleaning
        updateStatus(recovery ? "recovery.cleaning" : "close.cleaning", L10n.text("検証用アイコンの固定を解除しています。完了までDockを操作せずお待ちください。",
                           "Removing the test icons' pins. Please leave the Dock untouched until this finishes."))
        Task { @MainActor in
            // The button's mouse-up must precede the backend's physical-input
            // guard. This delay never substitutes for a verified state.
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard let current = await inspect(recovery ? "recovery-before" : "cleanup-before") else {
                block(readFailure, code: "cleanup.read-failed"); return
            }
            if !Self.isEmpty(current) {
                let result: (Bool, MacDockNativeProbeState?, String)
                if recovery {
                    result = await withCheckedContinuation { continuation in
                        mover.recoverURLDragPins(metrics: metrics.filter { current.ownPinnedMetrics.contains($0) }, confirmed: current) {
                            continuation.resume(returning: ($0, $1, $2))
                        }
                    }
                } else if let initial {
                    result = await withCheckedContinuation { continuation in
                        mover.cleanupURLDragPins(metrics: metrics, before: initial) {
                            continuation.resume(returning: ($0, $1, $2))
                        }
                    }
                } else {
                    block(readFailure, code: "cleanup.no-baseline")
                    return
                }
                guard result.0 else {
                    recoveryRequired = true
                    let detail = result.2.trimmingCharacters(in: .whitespacesAndNewlines)
                    trace("cleanup.backend-failed", detail: detail)
                    let message = L10n.text("片付けを完了できませんでした。検証用アイコンの状態を再確認して、片付けを再実行してください。",
                                            "Cleanup could not be completed. Inspect the remaining test icons and retry cleanup.")
                    block(detail.isEmpty ? message : "\(message)\n\(detail)", code: "cleanup.native-failed")
                    return
                }
            }
            // Even a successful native cleanup callback is not enough. Keep
            // both the durable marker and suspension until a fresh clean read.
            guard let final = await inspect("cleanup-final"), Self.isEmpty(final),
                  current.sameEnvironment(as: final), current.foreignOrder == final.foreignOrder,
                  current.foreignSavedRecords == final.foreignSavedRecords else {
                recoveryRequired = true
                block(L10n.text("固定解除後の状態を確認できません。通常操作は停止したまま、復旧を待っています。",
                                "The final clean state could not be verified. Normal operations remain suspended pending recovery."), code: "cleanup.final-mismatch")
                return
            }
            trace("cleanup.verified-empty", state: final)
            MacDockRegistrationCleanup.finishNativeURLProbe()
            finishClosing()
        }
    }

    private func block(_ message: String, code: String) {
        phase = .blocked
        stopPreparationWatchdog()
        updateStatus(code, message)
        if terminationRequested {
            terminationRequested = false
            Task { @MainActor in NSApp.reply(toApplicationShouldTerminate: false) }
        }
    }

    private func finishClosing() {
        guard !MacDockRegistrationCleanup.nativeURLProbePending else { return }
        trace("close.finished")
        stopPreparationWatchdog()
        preparationID = nil
        initial = nil
        configuration = nil
        metrics = []
        if suspended {
            suspended = false
            MacAppModel.shared.directDockController.setNativeReorderSuspended(false)
        }
        window?.delegate = nil
        window?.close()
        window = nil
        let reply = terminationRequested
        terminationRequested = false
        closeRequested = false
        if reply { Task { @MainActor in NSApp.reply(toApplicationShouldTerminate: true) } }
    }

    private func updateStatus(_ code: String, _ message: String) {
        statusCode = code
        status = message
        trace("status.changed")
    }

    private func retainResult(_ code: String, operation: NSDragOperation, state: MacDockNativeProbeState? = nil) {
        lastResult = status
        trace("result.retained", detail: code, operation: operation, state: state)
    }

    /// Only codes, counts, operation bits and this app's window flags are
    /// emitted. Never pass paths, AX labels, foreign identities or saved data.
    private func trace(_ event: String, detail: String = "none", operation: NSDragOperation? = nil,
                       state: MacDockNativeProbeState? = nil) {
        eventNumber += 1
        let metadata = "session=\(sessionNumber) event=\(eventNumber) action=\(event) detail=\(detail)"
            + " status=\(statusCode) phase=\(phase.rawValue) seed=\(seedRequired) mode=\(mode.rawValue)"
            + " fresh=\(beganFreshSession) nativeStarted=\(nativeDragStarted) initial=\(initial != nil)"
            + " recovery=\(recoveryRequired) close=\(closeRequested) busy=\(mover.busy) readingPrepare=\(readingPreparation)"
            + " pending=\(MacDockRegistrationCleanup.nativeURLProbePending) window=\(window?.windowNumber ?? -1)"
            + " visible=\(window?.isVisible ?? false) key=\(window?.isKeyWindow ?? false) appActive=\(NSApp.isActive)"
            + " operation=\(operation?.rawValue ?? 0) own=\(state?.items.compactMap(\.metric).count ?? -1) pins=\(state?.ownPinnedMetrics.count ?? -1)"
        Self.log.notice("\(metadata, privacy: .public)")
    }

    fileprivate func traceSource(_ event: String) { trace(event) }

    private func startPreparationWatchdog() {
        stopPreparationWatchdog()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.phase == .preparing, self.preparationID != nil else { return }
                if NSEvent.pressedMouseButtons & 1 == 0 {
                    self.trace("prepare.watchdog-released")
                    self.cancelPreparation()
                } else if !self.readingPreparation, let ready = self.preparationReadyAt,
                          ProcessInfo.processInfo.systemUptime - ready > 0.75 {
                    self.trace("prepare.watchdog-expired")
                    self.cancelPreparation()
                    self.updateStatus("prepare.expired", L10n.text("確認から時間が経ったため、ドラッグ準備を取り消しました。もう一度丸を掴んで動かしてください。",
                        "The prepared state expired. Grab and move the circle again to retry."))
                }
            }
        }
        preparationWatchdog = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopPreparationWatchdog() {
        preparationWatchdog?.invalidate()
        preparationWatchdog = nil
    }

    private var readFailure: String {
        let message = L10n.text("Dockの状態を読み取れませんでした。「状態を再確認」で再試行できます。",
                               "The Dock state could not be read. Use Recheck State to retry.")
        guard let detail = mover.lastURLDragInspectionFailure else { return message }
        return message + "\n" + L10n.text("確認箇所: ", "Inspection detail: ") + detail
    }

    private func inspect(_ purpose: String) async -> MacDockNativeProbeState? {
        trace("inspect.started", detail: purpose)
        let began = ProcessInfo.processInfo.systemUptime
        let state: MacDockNativeProbeState? = await withCheckedContinuation { continuation in
            mover.inspectURLDrag(metrics: metrics, edge: edge) { [self] state in
                // This callback trace distinguishes backend completion from a
                // continuation waiting to re-enter the MainActor/run loop.
                trace("inspect.callback", detail: purpose, state: state)
                continuation.resume(returning: state)
            }
        }
        let elapsed = Int((ProcessInfo.processInfo.systemUptime - began) * 1_000)
        let detail = state == nil ? (mover.lastURLDragInspectionFailure ?? "unavailable") : "matched"
        lastInspection = "\(purpose): \(detail) (\(elapsed) ms)"
        trace("inspect.resumed", detail: lastInspection, state: state)
        return state
    }

    private func settledInspection() async -> MacDockNativeProbeState? {
        var previous: MacDockNativeProbeState?
        for delay: UInt64 in [350_000_000, 450_000_000, 650_000_000] {
            try? await Task.sleep(nanoseconds: delay)
            guard let state = await inspect("settle") else { previous = nil; continue }
            if let previous, previous.sameEnvironment(as: state),
               previous.orderedIdentities == state.orderedIdentities,
               previous.ownPinnedMetrics == state.ownPinnedMetrics,
               previous.foreignSavedRecords == state.foreignSavedRecords { return state }
            previous = state
        }
        return nil
    }

    private static func isEmpty(_ state: MacDockNativeProbeState) -> Bool {
        state.ownPinnedMetrics.isEmpty && state.items.allSatisfy { $0.metric == nil }
    }

    private static func isComplete(_ state: MacDockNativeProbeState) -> Bool {
        let own = state.items.compactMap(\.metric)
        guard own == state.metrics, Set(own).count == 6,
              state.ownPinnedMetrics == Set(state.metrics),
              let first = state.items.firstIndex(where: { $0.metric != nil }),
              first + own.count <= state.items.count else { return false }
        return state.items[first..<(first + own.count)].compactMap(\.metric) == state.metrics
    }

    private static func insertion(at point: NSPoint, state: MacDockNativeProbeState) -> Int? {
        guard point.x.isFinite, point.y.isFinite, state.edge != .top else { return nil }
        let foreign = state.items.filter { $0.metric == nil }
        guard !foreign.isEmpty else { return nil }
        let band = state.items.reduce(NSRect.null) { $0.union($1.frame) }
        guard !band.isNull, band.insetBy(dx: -24, dy: -24).contains(point) else { return nil }
        let horizontal = state.edge == .bottom
        let value = horizontal ? point.x : -point.y
        let preceding = foreign.prefix { (horizontal ? $0.frame.midX : -$0.frame.midY) <= value }.count
        return min(max(preceding, 1), foreign.count)
    }

    private func makeImage() -> NSImage? {
        let model = MacAppModel.shared
        guard let metric = metrics.first else { return nil }
        let presentation = MacSystemDockPresentation(
            snapshot: TimeProgressCalculator.snapshot(for: metric, profile: model.store.profile),
            accent: MacWidgetStyle.accent(for: metric, theme: model.store.profile.widgetTheme,
                                         customColors: model.preferences.customColors))
        let renderer = ImageRenderer(content: MacSystemDockTileView(presentation: presentation))
        renderer.scale = 2
        return renderer.nsImage
    }
}

@MainActor
private struct MacDockNativeURLDragProbeView: View {
    @ObservedObject var probe: MacDockNativeURLDragProbe
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text("6個の検証アイコンを一度にドラッグ", "Drag Six Test Icons in One Native Session"))
                .font(.title2.weight(.semibold))
            Text(L10n.text("本物のDaysYetの丸とは別の「Group Test 1〜6」を使います。最初はコピーで追加し、次に既存6個の移動を試します。通常の自動並べ替えは、片付けが終わるまで停止します。",
                           "Uses disposable Group Test 1–6 icons, separate from your real DaysYet circles. First add them using Copy, then test moving the existing six. Normal automatic ordering stays paused until cleanup finishes."))
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Picker(L10n.text("移動時のモード", "Operation for Existing Icons"), selection: $probe.mode) {
                ForEach(MacDockNativeURLDragMode.allCases) { Text($0.title).tag($0) }
            }
            .disabled(probe.seedRequired || !probe.canDrag)
            if probe.seedRequired {
                Text(L10n.text("モードは、最初のCopyで6個の追加を確認できるまで選べません。",
                               "Modes become available after the first Copy is verified to have added all six icons."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                MacDockNativeURLDragSource(probe: probe).frame(width: 92, height: 92)
                VStack(alignment: .leading, spacing: 6) {
                    Text(probe.seedRequired
                         ? L10n.text("① Dockへドラッグして6個追加（Copy固定）", "1. Drag into the Dock to add six icons (Copy)")
                         : L10n.text("② 丸をDockの別の位置へドラッグ", "2. Drag the circle to another Dock position"))
                        .font(.headline)
                    Text(L10n.text("押したまま確認を待ってから動かしてください。Dock外には置かないでください。",
                                   "Hold briefly for inspection, then move. Keep the drop inside the Dock."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(probe.status).font(.callout).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            if !probe.lastInspection.isEmpty {
                Text(probe.lastInspection).font(.caption.monospaced()).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if let result = probe.lastResult {
                Text(L10n.text("前回の結果: ", "Previous result: ") + result)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled)
            }
            Spacer(minLength: 0)
            HStack {
                if probe.phase == .blocked {
                    Button(L10n.text("状態を再確認", "Recheck State")) { probe.retryInspection() }
                    Button(L10n.text("検証アイコンを片付けて閉じる", "Clean Up Test Icons and Close")) { probe.recoverAndClose() }
                }
                Spacer()
                Button(L10n.text("終了して片付ける", "Finish and Clean Up")) { probe.requestClose() }
                    .disabled(probe.phase == .cleaning)
            }
        }
        .padding(24).frame(width: 600, height: 590)
    }
}

@MainActor
private struct MacDockNativeURLDragSource: NSViewRepresentable {
    let probe: MacDockNativeURLDragProbe
    func makeNSView(context: Context) -> SourceView { SourceView(probe: probe) }
    func updateNSView(_ nsView: SourceView, context: Context) { nsView.needsDisplay = true }

    @MainActor
    final class SourceView: NSView, NSDraggingSource {
        let probe: MacDockNativeURLDragProbe
        private var press: NSPoint?
        private var lastDrag: NSEvent?
        private var prepared: MacDockNativeURLDragProbe.PreparedDrag?
        private var active: MacDockNativeURLDragProbe.PreparedDrag?
        private var gesture = UUID()
        private var reportedDrag = false

        init(probe: MacDockNativeURLDragProbe) {
            self.probe = probe
            super.init(frame: .zero)
            setAccessibilityElement(true)
            setAccessibilityLabel(L10n.text("6個の検証アイコンをDockへドラッグ", "Drag six test icons into the Dock"))
        }
        required init?(coder: NSCoder) { nil }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func draw(_ dirtyRect: NSRect) {
            probe.image?.draw(in: bounds.insetBy(dx: 10, dy: 10), from: .zero, operation: .sourceOver,
                              fraction: probe.canDrag || press != nil ? 1 : 0.4)
        }
        override func mouseDown(with event: NSEvent) {
            probe.traceSource("source.down")
            guard probe.canDrag, active == nil else { probe.traceSource("source.down-ignored"); return }
            gesture = UUID()
            reportedDrag = false
            let id = gesture
            press = convert(event.locationInWindow, from: nil)
            lastDrag = nil
            prepared = nil
            probe.prepareDrag { [weak self] ready in
                guard let self, gesture == id, press != nil, NSEvent.pressedMouseButtons & 1 != 0 else {
                    self?.probe.traceSource("source.preparation-rejected")
                    self?.probe.cancelPreparation()
                    return
                }
                probe.traceSource(ready == nil ? "source.preparation-unavailable" : "source.preparation-delivered")
                prepared = ready
                startIfReady()
            }
        }
        override func mouseDragged(with event: NSEvent) {
            if !reportedDrag {
                reportedDrag = true
                probe.traceSource("source.first-drag")
            }
            guard press != nil, active == nil else { return }
            lastDrag = event
            startIfReady()
        }
        override func mouseUp(with event: NSEvent) {
            probe.traceSource("source.up")
            guard active == nil else { return }
            gesture = UUID()
            press = nil
            prepared = nil
            lastDrag = nil
            probe.cancelPreparation()
            needsDisplay = true
        }
        private func startIfReady() {
            guard active == nil, let prepared, let press, let event = lastDrag else { return }
            let point = convert(event.locationInWindow, from: nil)
            guard hypot(point.x - press.x, point.y - press.y) >= 4, probe.beginDrag(prepared) else { return }
            active = prepared
            self.prepared = nil
            let size: CGFloat = 40
            let frame = NSRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
            let transparent = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in true }
            let items = prepared.urls.enumerated().map { index, url in
                let item = NSDraggingItem(pasteboardWriter: url as NSURL)
                item.setDraggingFrame(frame, contents: index == 0 ? prepared.image : transparent)
                return item
            }
            let session = beginDraggingSession(with: items, event: event, source: self)
            probe.traceSource("source.native-session-created")
            session.draggingFormation = .none
            session.draggingLeaderIndex = 0
            session.animatesToStartingPositionsOnCancelOrFail = true
        }
        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            active?.operation ?? []
        }
        func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            probe.traceSource("source.native-session-ended")
            guard let active else { return }
            self.active = nil
            press = nil
            prepared = nil
            lastDrag = nil
            gesture = UUID()
            probe.dragEnded(active, point: screenPoint, operation: operation)
            needsDisplay = true
        }
    }
}
#endif
