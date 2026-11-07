import SwiftUI

/// Only the Times tab edits a time's content. Widgets keep references to it.
struct TimeEditor: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var draft: ProfileStore
    let metric: MetricKind
    let onSave: (UserProfile) -> Void
    private let originalProfile: UserProfile

    init(profile: UserProfile, metric: MetricKind, onSave: @escaping (UserProfile) -> Void) {
        self.metric = metric
        self.onSave = onSave
        originalProfile = profile
        _draft = StateObject(wrappedValue: ProfileStore(profile: profile, appliesLaunchArguments: false, saveProfile: { _ in }))
    }

    var body: some View {
        NavigationStack {
            MetricSettingsContent(kind: metric)
                .navigationTitle(metric.title(profile: draft.profile))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.text("キャンセル", "Cancel")) { dismiss() }
                            .accessibilityIdentifier("time.editor.cancel")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.text("保存", "Save")) {
                            onSave(draft.profile)
                            dismiss()
                        }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("time.editor.save")
                    }
                }
        }
        .environmentObject(draft)
        .interactiveDismissDisabled(draft.profile != originalProfile)
    }
}
