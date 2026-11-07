import SwiftUI

enum AppRoute: Hashable {
    case appInfo
    case usageGuide
    case widgetColors
    case timelineColor(MetricKind)
}

struct RootView: View {
    @EnvironmentObject private var store: ProfileStore
    @State private var selectedTab: Int
    @State private var widgetPath: [AppRoute]
    @State private var timePath: [AppRoute]
#if DEBUG
    @State private var screenshotMetricSettingsPresented: Bool
#endif

    init() {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let editsMetric = arguments.contains("--screenshot-edit-times") || arguments.contains("--screenshot-study-days")
        let opensAppInfo = arguments.contains("--screenshot-app-info") || arguments.contains("--screenshot-settings")
        let initialTab = arguments.contains("--screenshot-times") || editsMetric || opensAppInfo ? 1 : 0
        _selectedTab = State(initialValue: initialTab)
        _widgetPath = State(initialValue: arguments.contains("--screenshot-colors") ? [.widgetColors] : [])
        _timePath = State(initialValue: opensAppInfo && !editsMetric ? [.appInfo] : [])
        _screenshotMetricSettingsPresented = State(initialValue: editsMetric)
#else
        _selectedTab = State(initialValue: 0)
        _widgetPath = State(initialValue: [])
        _timePath = State(initialValue: [])
#endif
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $widgetPath) {
                WidgetStudioView(openTimeLibrary: openTimeLibrary)
                    .navigationDestination(for: AppRoute.self, destination: destination)
            }
            .tabItem { Label(L10n.text("ウィジェット", "Widget"), systemImage: "square.grid.2x2") }
            .tag(0)

            NavigationStack(path: $timePath) {
                TimeLibraryView(openColorSettings: { timePath.append(.timelineColor($0)) })
                    .navigationDestination(for: AppRoute.self, destination: destination)
#if DEBUG
                    .sheet(isPresented: $screenshotMetricSettingsPresented) {
                        MetricSettingsView(kind: screenshotMetricKind)
                    }
#endif
            }
            .tabItem { Label(L10n.text("時間", "Times"), systemImage: "circle.dotted") }
            .tag(1)
        }
        .fullScreenCover(isPresented: onboardingPresented) {
            OnboardingView()
                .environmentObject(store)
        }
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .appInfo: AppInfoView(resetData: resetData)
        case .usageGuide: UsageGuideView()
        case .widgetColors: WidgetColorSettingsView(layout: store.profile.widgetLayout)
        case .timelineColor(let metric): TimelineColorSettingsView(metric: metric)
        }
    }

    private func openTimeLibrary() {
        timePath.removeAll()
        selectedTab = 1
    }

    private func resetData() {
        // Clear both tabs so onboarding returns to their lists after a reset.
        widgetPath.removeAll()
        timePath.removeAll()
        store.reset()
    }

#if DEBUG
    private var screenshotMetricKind: MetricKind {
        ProcessInfo.processInfo.arguments.contains("--screenshot-study-days") ? .study : .workday
    }
#endif

    private var onboardingPresented: Binding<Bool> {
        Binding(
            get: { !store.profile.isConfigured },
            set: { _ in }
        )
    }
}
