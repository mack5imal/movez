import Foundation
import ServiceManagement

/// Registering movez to start with the user's session.
///
/// Behind a protocol because `SMAppService` talks to a system daemon: it cannot be exercised in a
/// test, and on an ad-hoc-signed Debug build it can legitimately refuse. What the tests check is
/// that the refusal reaches the user instead of being swallowed.
@MainActor
protocol LaunchAtLoginService: AnyObject {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

/// The real thing.
@MainActor
final class SystemLaunchAtLogin: LaunchAtLoginService {
    var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

/// The stand-in the tests drive, and the one the snapshots render against.
@MainActor
final class FakeLaunchAtLogin: LaunchAtLoginService {
    private(set) var isEnabled: Bool
    private(set) var calls: [Bool] = []
    /// Set to make the next `setEnabled` fail, the way an unsigned build does.
    var failure: Error?

    init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
    }

    func setEnabled(_ enabled: Bool) throws {
        calls.append(enabled)
        if let failure { throw failure }
        isEnabled = enabled
    }
}

/// What the settings row says when registration is refused.
struct LaunchAtLoginError: LocalizedError, Equatable {
    var reason: String

    var errorDescription: String? { reason }

    static let unsigned = LaunchAtLoginError(reason: "macOS refused the login item")
}
