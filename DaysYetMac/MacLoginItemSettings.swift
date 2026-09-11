import Combine
import ServiceManagement

@MainActor
final class MacLoginItemSettings: ObservableObject {
    @Published private(set) var status: SMAppService.Status
    @Published private(set) var errorMessage: String?

    private let readStatus: () -> SMAppService.Status
    private let register: () throws -> Void
    private let unregister: () throws -> Void
    private let showSystemSettings: () -> Void

    var isEnabled: Bool { status == .enabled }
    var requiresApproval: Bool { status == .requiresApproval }

    init(
        readStatus: @escaping () -> SMAppService.Status = { SMAppService.mainApp.status },
        register: @escaping () throws -> Void = { try SMAppService.mainApp.register() },
        unregister: @escaping () throws -> Void = { try SMAppService.mainApp.unregister() },
        openSystemSettings: @escaping () -> Void = { SMAppService.openSystemSettingsLoginItems() }
    ) {
        self.readStatus = readStatus
        self.register = register
        self.unregister = unregister
        self.showSystemSettings = openSystemSettings
        status = readStatus()
    }

    func refresh() {
        let currentStatus = readStatus()
        if currentStatus != status { errorMessage = nil }
        status = currentStatus
    }

    func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        refresh()
        // System Settings owns this state; never persist an optimistic toggle.
        do {
            if enabled {
                if requiresApproval {
                    openSystemSettings()
                } else if !isEnabled {
                    try register()
                }
            } else if isEnabled || requiresApproval {
                try unregister()
            }
            refresh()
        } catch {
            refresh()
            errorMessage = L10n.text(
                "ログイン時の起動設定を変更できませんでした。ログイン項目の設定を確認して、もう一度お試しください。",
                "Couldn’t change launch at login. Check Login Items in System Settings and try again."
            )
        }
    }

    func openSystemSettings() {
        showSystemSettings()
    }
}
