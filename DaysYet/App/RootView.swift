import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: ProfileStore
    @State private var selectedTab: Int
    @State private var showsAppInfo: Bool
    @State private var resetsDataAfterAppInfoDismissal = false
#if DEBUG
    @State private var screenshotMetricSettingsPresented: Bool
    @State private var screenshotColorsPresented: Bool
#endif

    init() {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let editsMetric = arguments.contains("--screenshot-edit-times") || arguments.contains("--screenshot-study-days")
        let opensAppInfo = arguments.contains("--screenshot-app-info") || arguments.contains("--screenshot-settings")
        let initialTab = arguments.contains("--screenshot-times") || editsMetric || opensAppInfo ? 1 : 0
        _selectedTab = State(initialValue: initialTab)
        _showsAppInfo = State(initialValue: opensAppInfo && !editsMetric)
        _screenshotMetricSettingsPresented = State(initialValue: editsMetric)
        _screenshotColorsPresented = State(initialValue: arguments.contains("--screenshot-colors"))
#else
        _selectedTab = State(initialValue: 0)
        _showsAppInfo = State(initialValue: false)
#endif
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                WidgetStudioView(openTimeLibrary: { selectedTab = 1 })
#if DEBUG
                    .navigationDestination(isPresented: $screenshotColorsPresented) {
                        WidgetColorSettingsView(layout: store.profile.widgetLayout)
                    }
#endif
            }
            .tabItem { Label(L10n.text("ウィジェット", "Widget"), systemImage: "square.grid.2x2") }
            .tag(0)

            NavigationStack {
                TimeLibraryView(openAppInfo: { showsAppInfo = true })
#if DEBUG
                    .sheet(isPresented: $screenshotMetricSettingsPresented) {
                        MetricSettingsView(kind: screenshotMetricKind)
                    }
#endif
            }
            .tabItem { Label(L10n.text("時間", "Times"), systemImage: "circle.dotted") }
            .tag(1)
        }
        .sheet(isPresented: $showsAppInfo, onDismiss: appInfoDidDismiss) {
            NavigationStack {
                AppInfoView(resetData: {
                    resetsDataAfterAppInfoDismissal = true
                    showsAppInfo = false
                })
            }
        }
        .fullScreenCover(isPresented: onboardingPresented) {
            OnboardingView()
                .environmentObject(store)
        }
    }

    private func appInfoDidDismiss() {
        guard resetsDataAfterAppInfoDismissal else { return }
        resetsDataAfterAppInfoDismissal = false
        // Present onboarding after the About sheet has finished dismissing.
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
