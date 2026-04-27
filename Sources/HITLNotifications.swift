import UserNotifications

// MARK: - HITL Notification Manager

/// Integrates with macOS Notification Center to surface critical HITL interceptions
/// as system notifications, ensuring time-sensitive decisions are not missed.
@MainActor
class HITLNotificationManager {
    static let shared = HITLNotificationManager()
    private var authorized = false

    private init() {}

    /// Request notification permission from the user. Call once at app launch.
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            Task { @MainActor in
                self.authorized = granted
            }
        }
    }

    /// Post a local notification for an HITL interception.
    /// Block-severity interceptions use the critical sound; others use default.
    func notifyInterception(_ interception: HITLInterception) {
        guard authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Engrave HITL: \(interception.toolName)"
        content.body = interception.reason
        content.sound = interception.severity == "block" ? .defaultCritical : .default
        content.categoryIdentifier = "HITL_INTERCEPTION"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(
            identifier: interception.id.uuidString,
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// Remove a delivered notification when its interception has been resolved.
    func removeNotification(id: UUID) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(
            withIdentifiers: [id.uuidString]
        )
    }
}
