import Foundation
import UserNotifications

/// Posts native notifications when an agent needs attention or finishes.
///
/// `UNUserNotificationCenter` requires a bundled, identified app; when run as a
/// bare binary (`swift run`) there is no bundle id, so we no-op to avoid a
/// crash. Notifications work once launched as `DesktopPet.app`.
@MainActor
final class NotificationManager {
    static let shared = NotificationManager()

    /// UserDefaults key for the in-app "show notifications" toggle (independent
    /// of the macOS permission): users who granted permission can still mute.
    static let enabledKey = "desktoppet.notificationsEnabled"

    /// `UNUserNotificationCenter` needs a real bundle id; false under `swift run`.
    var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    private var available: Bool { isAvailable }

    /// Whether the user wants notifications shown (defaults to on).
    var userEnabled: Bool {
        (UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool) ?? true
    }

    func notify(title: String, body: String) {
        guard available, userEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        // Sound is handled by SoundSettings (configurable per event).
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
