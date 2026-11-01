import AppKit
import Combine
import SwiftUI

struct MacSystemDockPresentation {
    let snapshot: MetricSnapshot
    let accent: Color
    var opacity: Double = 1
}

/// One live macOS Dock tile for every configured circle, owned by short-lived helpers.
@MainActor
final class MacSystemDockController {
    private let store: ProfileStore
    private let preferences: MacWidgetPreferences
    private let presenter: (([MacSystemDockPresentation]) -> Void)?
    private let openSettings: () -> Void
    private let openGroup: () -> Void
    private let readDockEdge: () -> MacWidgetEdge?
    private let isChangingPlacement: () -> Bool
    private var subscriptions = Set<AnyCancellable>()
    private var timer: Timer?
    private var locationTimer: Timer?
    private var started = false
    private var isPresenting = false
    private var isDragging = false
    private var isLanding = false
    private lazy var host = MacDockTileProcessHost(action: { [weak self] action in
        self?.handle(action)
    }, failed: { [weak self] in self?.handleFailure() })

    init(store: ProfileStore, preferences: MacWidgetPreferences,
         openSettings: @escaping () -> Void,
         openGroup: @escaping () -> Void = {},
         readDockEdge: @escaping () -> MacWidgetEdge? = { nil },
         isChangingPlacement: @escaping () -> Bool = { false },
         present: (([MacSystemDockPresentation]) -> Void)? = nil) {
        self.store = store
        self.preferences = preferences
        self.openSettings = openSettings
        self.openGroup = openGroup
        self.readDockEdge = readDockEdge
        self.isChangingPlacement = isChangingPlacement
        self.presenter = present
        preferences.objectWillChange.receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &subscriptions)
        store.$profile.dropFirst().receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &subscriptions)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &subscriptions)
    }

    func start() {
        guard !started else { return }
        started = true
        refresh()
        // A Dock can move while DaysYet is on another edge. Check its location
        // independently of the 30-second tile redraw timer.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.started else { return }
                self.synchronizeLocation()
            }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        locationTimer = timer
    }

    func stop() {
        started = false
        timer?.invalidate()
        timer = nil
        locationTimer?.invalidate()
        locationTimer = nil
        if isPresenting { present([]) }
        isPresenting = false
    }

    func refresh(now: Date = .now) {
        guard started else { return }
        synchronizeLocation()
        guard preferences.isVisible, preferences.isInSystemDock else {
            timer?.invalidate()
            timer = nil
            if isPresenting { present([]) }
            isPresenting = false
            return
        }
        let presentations = store.profile.macDashboardMetrics.map { kind in
            MacSystemDockPresentation(snapshot: TimeProgressCalculator.snapshot(for: kind, profile: store.profile, now: now),
                accent: MacWidgetStyle.accent(for: kind, theme: store.profile.widgetTheme, customColors: preferences.customColors),
                opacity: isLanding ? 0 : (isDragging ? 0.22 : 1))
        }
        isPresenting = true
        present(presentations)
        guard preferences.isInSystemDock else { return }
        if timer == nil {
            let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            timer.tolerance = 3
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    func returnToEdge() {
        preferences.returnToScreenEdge()
        refresh()
    }

    func synchronizeLocation() {
        // Held previews and landing animations own their geometry until they
        // finish. Never turn a preview into a committed move mid-gesture.
        guard !isChangingPlacement(), let edge = readDockEdge() else { return }
        preferences.reconcileDockLocation(edge)
    }

    func setDragging(_ dragging: Bool) {
        guard isDragging != dragging else { return }
        isDragging = dragging
        refresh()
    }

    func setLanding(_ landing: Bool) {
        guard isLanding != landing else { return }
        isLanding = landing
        refresh()
    }

    func handle(_ action: MacDockTileAction) {
        switch action {
        case .openGroup: if preferences.isVisible && preferences.isInSystemDock { openGroup() }
        case .settings: openSettings()
        case .returnToEdge: returnToEdge()
        case .quit: NSApp.terminate(nil)
        }
    }

    private func present(_ presentations: [MacSystemDockPresentation]) {
        if let presenter {
            presenter(presentations)
            return
        }
        do {
            if presentations.isEmpty { host.stop() }
            else { try host.update(presentations) }
        } catch {
            handleFailure()
        }
    }

    private func handleFailure() {
        host.stop()
        isPresenting = false
        timer?.invalidate()
        timer = nil
        preferences.returnToScreenEdge()
        preferences.systemDockError = L10n.text(
            "Dockに表示できなかったため、画面の端に戻しました。DaysYetを開き直してから、もう一度お試しください。",
            "The Dock display could not start, so the widget returned to the screen edge. Reopen DaysYet and try again."
        )
        openSettings()
    }

    deinit {
        timer?.invalidate()
        locationTimer?.invalidate()
    }
}

struct MacSystemDockTileView: View {
    let presentation: MacSystemDockPresentation

    var body: some View {
        let snapshot = presentation.snapshot
        ZStack {
            Circle().fill(.black)
                .frame(width: 116, height: 116)
            Circle().strokeBorder(.white.opacity(0.10), lineWidth: 4)
                .frame(width: 102, height: 102)
            if snapshot.remainingFraction > 0, !snapshot.isOff {
                Circle().trim(from: 1 - snapshot.remainingFraction, to: 1)
                    .stroke(presentation.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 98, height: 98)
            }
            VStack(spacing: 1) {
                Text(snapshot.isOff ? "Off" : RemainingPercentage.compactText(for: snapshot.remainingFraction))
                    .font(.system(size: 31, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(snapshot.kind == .healthyLife ? snapshot.kind.shortTitle : snapshot.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.white.opacity(0.65))
            }
            .frame(width: 80)
            .foregroundStyle(.white.opacity(0.95))
        }
        .frame(width: 128, height: 128)
        .opacity(presentation.opacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(snapshot.accessibilitySummary)
    }
}
