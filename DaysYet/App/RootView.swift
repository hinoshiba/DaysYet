import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: ProfileStore
    @State private var selectedTab: Int

    init() {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let initialTab = arguments.contains("--screenshot-settings")
            ? 2
            : arguments.contains("--screenshot-times") ? 1 : 0
        _selectedTab = State(initialValue: initialTab)
#else
        _selectedTab = State(initialValue: 0)
#endif
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                WidgetStudioView()
            }
            .tabItem { Label(L10n.text("ウィジェット", "Widget"), systemImage: "square.grid.2x2") }
            .tag(0)

            NavigationStack {
                TimeLibraryView()
            }
            .tabItem { Label(L10n.text("時間", "Times"), systemImage: "circle.dotted") }
            .tag(1)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label(L10n.text("設定", "Settings"), systemImage: "slider.horizontal.3") }
            .tag(2)
        }
        .fullScreenCover(isPresented: onboardingPresented) {
            OnboardingView()
                .environmentObject(store)
        }
    }

    private var onboardingPresented: Binding<Bool> {
        Binding(
            get: { !store.profile.isConfigured },
            set: { _ in }
        )
    }
}
