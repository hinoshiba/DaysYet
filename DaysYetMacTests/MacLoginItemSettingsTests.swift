import ServiceManagement
import XCTest
@testable import DaysYetMac

final class MacLoginItemSettingsTests: XCTestCase {
    @MainActor
    func testInitializationOnlyReadsTheSystemStatus() {
        for status in [SMAppService.Status.notRegistered, .enabled, .requiresApproval, .notFound] {
            let service = LoginItemServiceStub(status: status)
            let settings = service.makeSettings()

            XCTAssertEqual(settings.status, status)
            XCTAssertEqual(settings.isEnabled, status == .enabled)
            XCTAssertEqual(settings.requiresApproval, status == .requiresApproval)
            XCTAssertNil(settings.errorMessage)
            XCTAssertEqual(service.registerCalls, 0)
            XCTAssertEqual(service.unregisterCalls, 0)
            XCTAssertEqual(service.openSettingsCalls, 0)
        }
    }

    @MainActor
    func testEnablingRegistersAnUnregisteredOrMissingService() {
        for status in [SMAppService.Status.notRegistered, .notFound] {
            let service = LoginItemServiceStub(status: status)
            let settings = service.makeSettings()

            settings.setEnabled(true)

            XCTAssertEqual(service.registerCalls, 1)
            XCTAssertEqual(service.unregisterCalls, 0)
            XCTAssertTrue(settings.isEnabled)
            XCTAssertFalse(settings.requiresApproval)
            XCTAssertNil(settings.errorMessage)
        }
    }

    @MainActor
    func testSuccessfulRegistrationUsesTheReportedStatusInsteadOfAssumingEnabled() {
        let service = LoginItemServiceStub(status: .notRegistered)
        service.onRegister = { service.status = .requiresApproval }
        let settings = service.makeSettings()

        settings.setEnabled(true)

        XCTAssertFalse(settings.isEnabled)
        XCTAssertTrue(settings.requiresApproval)
        XCTAssertNil(settings.errorMessage)

        settings.setEnabled(true)

        XCTAssertEqual(service.registerCalls, 1)
        XCTAssertEqual(service.openSettingsCalls, 1)
        XCTAssertTrue(settings.requiresApproval)

        service.status = .enabled
        settings.refresh()

        XCTAssertTrue(settings.isEnabled)
        XCTAssertFalse(settings.requiresApproval)
    }

    @MainActor
    func testDisablingUnregistersBothEnabledAndAwaitingApprovalServices() {
        for status in [SMAppService.Status.enabled, .requiresApproval] {
            let service = LoginItemServiceStub(status: status)
            let settings = service.makeSettings()

            settings.setEnabled(false)

            XCTAssertEqual(service.unregisterCalls, 1)
            XCTAssertEqual(service.registerCalls, 0)
            XCTAssertEqual(settings.status, .notRegistered)
            XCTAssertFalse(settings.isEnabled)
            XCTAssertFalse(settings.requiresApproval)
            XCTAssertNil(settings.errorMessage)
        }
    }

    @MainActor
    func testRegistrationFailureShowsAnErrorAndReadsTheActualStatus() {
        let service = LoginItemServiceStub(status: .notRegistered)
        service.onRegister = {
            service.status = .requiresApproval
            throw TestError.unavailable
        }
        let settings = service.makeSettings()

        settings.setEnabled(true)

        XCTAssertNotNil(settings.errorMessage)
        XCTAssertFalse(settings.isEnabled)
        XCTAssertTrue(settings.requiresApproval)

        settings.setEnabled(true)

        XCTAssertNil(settings.errorMessage)
        XCTAssertEqual(service.registerCalls, 1)
        XCTAssertEqual(service.openSettingsCalls, 1)
    }

    @MainActor
    func testUnregistrationFailureKeepsTheActualEnabledStatusAndCanBeRetried() {
        let service = LoginItemServiceStub(status: .enabled)
        service.onUnregister = { throw TestError.unavailable }
        let settings = service.makeSettings()

        settings.setEnabled(false)

        XCTAssertNotNil(settings.errorMessage)
        XCTAssertTrue(settings.isEnabled)

        service.onUnregister = nil
        settings.setEnabled(false)

        XCTAssertNil(settings.errorMessage)
        XCTAssertFalse(settings.isEnabled)
        XCTAssertEqual(service.unregisterCalls, 2)
    }

    @MainActor
    func testExternalCorrectionClearsAStaleRegistrationError() {
        let service = LoginItemServiceStub(status: .notRegistered)
        service.onRegister = { throw TestError.unavailable }
        let settings = service.makeSettings()
        settings.setEnabled(true)
        XCTAssertNotNil(settings.errorMessage)
        XCTAssertFalse(settings.isEnabled)

        service.status = .enabled
        settings.refresh()

        XCTAssertTrue(settings.isEnabled)
        XCTAssertNil(settings.errorMessage)
        XCTAssertEqual(service.registerCalls, 1)
    }

    @MainActor
    func testRefreshReflectsChangesMadeInSystemSettingsWithoutMutatingRegistration() {
        let service = LoginItemServiceStub(status: .enabled)
        let settings = service.makeSettings()

        service.status = .requiresApproval
        settings.refresh()

        XCTAssertFalse(settings.isEnabled)
        XCTAssertTrue(settings.requiresApproval)

        service.status = .notRegistered
        settings.refresh()

        XCTAssertEqual(settings.status, .notRegistered)
        XCTAssertFalse(settings.requiresApproval)
        XCTAssertEqual(service.registerCalls, 0)
        XCTAssertEqual(service.unregisterCalls, 0)
        XCTAssertEqual(service.openSettingsCalls, 0)
    }

    @MainActor
    func testEnablingRefreshesStaleStateBeforeChoosingWhetherToRegister() {
        let service = LoginItemServiceStub(status: .enabled)
        let settings = service.makeSettings()

        service.status = .notRegistered
        settings.setEnabled(true)

        XCTAssertEqual(service.registerCalls, 1)
        XCTAssertTrue(settings.isEnabled)

        service.status = .requiresApproval
        settings.setEnabled(true)

        XCTAssertEqual(service.registerCalls, 1)
        XCTAssertEqual(service.openSettingsCalls, 1)
        XCTAssertTrue(settings.requiresApproval)
    }

    @MainActor
    func testAlreadySatisfiedRequestsDoNotMutateRegistrationEvenWithStaleState() {
        let service = LoginItemServiceStub(status: .notRegistered)
        let settings = service.makeSettings()

        service.status = .enabled
        settings.setEnabled(true)
        XCTAssertTrue(settings.isEnabled)

        for status in [SMAppService.Status.notRegistered, .notFound] {
            service.status = status
            settings.setEnabled(false)
            XCTAssertEqual(settings.status, status)
            XCTAssertFalse(settings.isEnabled)
        }

        XCTAssertEqual(service.registerCalls, 0)
        XCTAssertEqual(service.unregisterCalls, 0)
        XCTAssertEqual(service.openSettingsCalls, 0)
    }

    @MainActor
    func testDisablingRefreshesStaleStateBeforeUnregistering() {
        let service = LoginItemServiceStub(status: .notRegistered)
        let settings = service.makeSettings()

        service.status = .enabled
        settings.setEnabled(false)

        XCTAssertEqual(service.unregisterCalls, 1)
        XCTAssertEqual(settings.status, .notRegistered)
        XCTAssertFalse(settings.isEnabled)
    }

    @MainActor
    func testOpenSystemSettingsUsesTheInjectedAction() {
        let service = LoginItemServiceStub(status: .requiresApproval)
        let settings = service.makeSettings()

        settings.openSystemSettings()

        XCTAssertEqual(service.openSettingsCalls, 1)
        XCTAssertEqual(service.registerCalls, 0)
        XCTAssertEqual(service.unregisterCalls, 0)
    }

    private enum TestError: Error {
        case unavailable
    }
}

@MainActor
private final class LoginItemServiceStub {
    var status: SMAppService.Status
    var registerCalls = 0
    var unregisterCalls = 0
    var openSettingsCalls = 0
    var onRegister: (() throws -> Void)?
    var onUnregister: (() throws -> Void)?

    init(status: SMAppService.Status) {
        self.status = status
    }

    func makeSettings() -> MacLoginItemSettings {
        // Every system interaction is injected so tests cannot change the
        // user's login items or open System Settings on the build machine.
        MacLoginItemSettings(
            readStatus: { self.status },
            register: {
                self.registerCalls += 1
                if let onRegister = self.onRegister {
                    try onRegister()
                } else {
                    self.status = .enabled
                }
            },
            unregister: {
                self.unregisterCalls += 1
                if let onUnregister = self.onUnregister {
                    try onUnregister()
                } else {
                    self.status = .notRegistered
                }
            },
            openSystemSettings: { self.openSettingsCalls += 1 }
        )
    }
}
