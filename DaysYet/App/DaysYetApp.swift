import SwiftUI

@main
struct DaysYetApp: App {
    @StateObject private var store = ProfileStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(store.profile.widgetTheme.palette.accent)
        }
    }
}
