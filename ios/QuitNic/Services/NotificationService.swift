import UserNotifications

enum NotificationService {
    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    static func scheduleDaily(hour: Int) async throws {
        let center = UNUserNotificationCenter.current()
        let allowed = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        guard allowed else { return }
        center.removePendingNotificationRequests(withIdentifiers: ["daily-check-in"])
        let content = UNMutableNotificationContent(); content.title = "How are you doing?"; content.body = "Take a moment to check in with your quit plan."
        let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: hour), repeats: true)
        try await center.add(UNNotificationRequest(identifier: "daily-check-in", content: content, trigger: trigger))
    }
    static func removeAll() { UNUserNotificationCenter.current().removeAllPendingNotificationRequests() }
}
