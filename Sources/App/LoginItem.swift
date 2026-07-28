import Foundation
import ServiceManagement

/// Launch-at-login toggle backed by `SMAppService` (macOS 13+). Works only for
/// the bundled `DesktopPet.app`; a no-op when run as a bare binary.
enum LoginItem {
    /// True once registered. `.requiresApproval` counts as on: registration
    /// succeeded and macOS is just waiting for the user to approve it in
    /// System Settings, so the toggle should stay on rather than snap back.
    static var isEnabled: Bool {
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Ignore: typically fails only when not running from a bundle.
        }
    }
}
