import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: ProfileStore
    @AppStorage("widget.editor.layout") private var rememberedWidgetLayout = WidgetEditorLayout.rows.rawValue
    @State private var selectedTab: Int
    @State private var widgetNavigationID = UUID()
#if DEBUG
    @State private var screenshotMetricSettingsPresented: Bool
    @State private var screenshotColorsPresented: Bool
    @State private var screenshotWidgetLayout: WidgetEditorLayout
#endif

    init() {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let editsMetric = arguments.contains("--screenshot-edit-times") || arguments.contains("--screenshot-study-days")
        let initialTab = arguments.contains("--screenshot-settings")
            ? 2
            : arguments.contains("--screenshot-times") || editsMetric ? 1 : 0
        _selectedTab = State(initialValue: initialTab)
        _screenshotMetricSettingsPresented = State(initialValue: editsMetric)
        _screenshotColorsPresented = State(initialValue: arguments.contains("--screenshot-colors"))
        _screenshotWidgetLayout = State(initialValue: arguments.contains("--screenshot-circles") ? .circles : .rows)
#else
        _selectedTab = State(initialValue: 0)
#endif
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                WidgetStudioView(layout: widgetLayoutBinding)
#if DEBUG
                    .navigationDestination(isPresented: $screenshotColorsPresented) {
                        WidgetColorSettingsView(layout: .circles)
                    }
#endif
            }
            .id(widgetNavigationID)
            .tabItem { Label(L10n.text("ウィジェット", "Widget"), systemImage: "square.grid.2x2") }
            .tag(0)

            NavigationStack {
                TimeLibraryView()
#if DEBUG
                    .navigationDestination(isPresented: $screenshotMetricSettingsPresented) {
                        MetricSettingsView(kind: screenshotMetricKind)
                    }
#endif
            }
            .tabItem { Label(L10n.text("時間", "Times"), systemImage: "circle.dotted") }
            .tag(1)

            NavigationStack {
                SettingsView(openWidgetSettings: openWidgetSettings, resetWidgetEditor: resetWidgetEditor)
            }
            .tabItem { Label(L10n.text("設定", "Settings"), systemImage: "slider.horizontal.3") }
            .tag(2)
        }
        .fullScreenCover(isPresented: onboardingPresented) {
            OnboardingView()
                .environmentObject(store)
        }
    }

    private var widgetLayoutBinding: Binding<WidgetEditorLayout> {
        Binding(
            get: {
#if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--screenshot-mode") {
                    return screenshotWidgetLayout
                }
#endif
                return WidgetEditorLayout(rawValue: rememberedWidgetLayout) ?? .rows
            },
            set: { layout in
#if DEBUG
                // UI-review data must not overwrite the person's last editor.
                if ProcessInfo.processInfo.arguments.contains("--screenshot-mode") {
                    screenshotWidgetLayout = layout
                    return
                }
#endif
                rememberedWidgetLayout = layout.rawValue
            }
        )
    }

    private func resetWidgetEditor() {
        // Reset the binding synchronously with the explicit deletion action;
        // do not wait for a view change while onboarding is being presented.
        widgetLayoutBinding.wrappedValue = .rows
#if DEBUG
        if !ProcessInfo.processInfo.arguments.contains("--screenshot-mode") {
            UserDefaults.standard.removeObject(forKey: "widget.editor.layout")
        }
#else
        UserDefaults.standard.removeObject(forKey: "widget.editor.layout")
#endif
        widgetNavigationID = UUID()
    }

    private func openWidgetSettings() {
#if DEBUG
        screenshotColorsPresented = false
#endif
        // An explicit Settings route always returns to the layout chooser,
        // including when the widget tab previously opened a color editor.
        widgetNavigationID = UUID()
        selectedTab = 0
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
