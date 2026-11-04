#if DAYSYET_DIRECT_DOCK_DRAG && DAYSYET_DOCK_NATIVE_REORDER
import AppKit
import SwiftUI

@MainActor
struct MacDockSnapshotSettings: View {
    @ObservedObject var preferences: MacWidgetPreferences

    @State private var permissionGranted = false
    @State private var showConsent = false
    @State private var requestAfterConsent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(L10n.text("Dockの移動をまとめて見せる", "Show Dock moves as one transition"),
                   isOn: enabledBinding)
            if preferences.dockVisualHandoffEnabled {
                if permissionGranted {
                    Label(L10n.text("画面収録は許可済みです", "Screen Recording is allowed"),
                          systemImage: "checkmark.circle")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(L10n.text("画面収録の許可待ちです。許可されるまでは通常の表示で移動します。",
                                   "Waiting for Screen Recording permission. Until then, Dock moves use the usual appearance."))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(L10n.text("画面収録の設定を開く…", "Open Screen Recording Settings…"),
                           action: openSystemSettings)
                        .controlSize(.small)
                }
            } else {
                Text(L10n.text("有効にする前に、見せ方と画像を取得する範囲を説明します。",
                               "Review the effect and the captured area before enabling it."))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear(perform: refreshPermission)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermission()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            // The settings window can be reused after permission changes.
            refreshPermission()
        }
        .sheet(isPresented: $showConsent, onDismiss: consentDidDismiss) {
            MacDockSnapshotConsent(onEnable: enableAfterConsent, onCancel: cancelConsent)
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(get: { preferences.dockVisualHandoffEnabled }, set: { enabled in
            if enabled {
                // Opening an explanation is not consent to capture or prompt.
                requestAfterConsent = false
                refreshPermission()
                showConsent = true
            } else {
                requestAfterConsent = false
                preferences.dockVisualHandoffEnabled = false
                showConsent = false
            }
        })
    }

    private func refreshPermission() {
        permissionGranted = MacDockSnapshotCapture.isGranted()
    }

    private func enableAfterConsent() {
        preferences.dockVisualHandoffEnabled = true
        requestAfterConsent = true
        showConsent = false
    }

    private func cancelConsent() {
        requestAfterConsent = false
        preferences.dockVisualHandoffEnabled = false
        showConsent = false
    }

    private func consentDidDismiss() {
        guard requestAfterConsent else { return }
        requestAfterConsent = false
        guard preferences.dockVisualHandoffEnabled else { return }
        // Only the affirmative consent action can reach this request. Wait for
        // our explanation sheet to close before macOS presents its own prompt.
        _ = MacDockSnapshotCapture.requestAccess()
        refreshPermission()
    }

    private func openSystemSettings() {
        // Opening System Settings never requests capture permission by itself.
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        if !NSWorkspace.shared.open(url),
           let settings = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") {
            NSWorkspace.shared.openApplication(at: settings, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

@MainActor
private struct MacDockSnapshotConsent: View {
    let onEnable: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(L10n.text("Dockの移動をまとめて見せる", "Show Dock moves as one transition"))
                        .font(.title2.weight(.semibold))
                    Text(L10n.text(
                        "丸を離したあと、Dock内の並べ替え途中を一時的な画像で覆い、配置が揃ってからまとめて表示します。",
                        "After you release a circle, a temporary image covers the Dock while its icons are rearranged. The finished layout is then revealed together."
                    ))
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    MacDockSnapshotIllustration()

                    explanation(
                        L10n.text("画像を取得する範囲", "Captured area"),
                        L10n.text("Dockと、そのすぐ周囲だけを取得します。Dock周辺の壁紙や、同じ帯にある他アプリの表示も画像に含まれます。",
                                  "Only the Dock and a small area immediately around it are captured. Wallpaper and other apps visible in that same strip are also included.")
                    )
                    explanation(
                        L10n.text("画像の扱い", "How the image is used"),
                        L10n.text("画像は移動の間だけメモリに保持し、処理が終わると破棄します。ファイルへの保存、ネットワークへの送信、音声の取得は行いません。",
                                  "The image stays in temporary memory during the move and is discarded afterward. It is never saved to a file or sent over the network. No audio is captured.")
                    )
                    explanation(
                        L10n.text("macOSの「画面収録」許可が必要です", "macOS Screen Recording permission is required"),
                        L10n.text("システム設定の「プライバシーとセキュリティ」で、画面収録のDaysYetをオンにしてください。macOSから開き直すよう案内された場合は、DaysYetを開き直してください。",
                                  "In System Settings → Privacy & Security, allow DaysYet under Screen Recording. If macOS asks you to reopen DaysYet, do so before using this effect.")
                    )
                }
                .padding(24)
            }
            Divider()
            HStack(spacing: 12) {
                Button(L10n.text("今はしない", "Not Now"), role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(L10n.text("有効にして許可を設定", "Enable and Set Up Permission"), action: onEnable)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 520, height: 590)
    }

    private func explanation(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.callout.weight(.semibold))
            Text(detail).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct MacDockSnapshotIllustration: View {
    var body: some View {
        HStack(spacing: 18) {
            VStack(spacing: 10) {
                ring(progress: 0.7, size: 27)
                Text(L10n.text("ドラッグ中", "While dragging"))
            }
            .frame(maxWidth: .infinity)
            Image(systemName: "arrow.right").foregroundStyle(.secondary)
            VStack(spacing: 10) {
                HStack(spacing: 5) {
                    ForEach(0..<6) { index in
                        ring(progress: 0.3 + Double(index) * 0.1, size: 20)
                    }
                }
                .frame(height: 27)
                Text(L10n.text("離すとまとめて配置", "Release to reveal the group"))
            }
            .frame(maxWidth: .infinity)
        }
        .font(.caption).foregroundStyle(.secondary)
        .padding(.horizontal, 12).padding(.vertical, 16)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.text("ドラッグ中は1つの丸。離すと、すべての丸が一緒に展開します。",
                                      "One circle while dragging. After release, all circles unfold together."))
    }

    private func ring(progress: Double, size: CGFloat) -> some View {
        Circle().strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 2.5)
            .overlay {
                Circle().trim(from: 0, to: progress)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .padding(1.25).rotationEffect(.degrees(-90))
            }
            .frame(width: size, height: size)
    }
}
#endif
