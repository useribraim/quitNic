import UserNotifications

enum NotificationService {
    enum NotificationError: Error { case permissionDenied }
    private static let dailyIdentifier = "daily-check-in"
    private static let inactivityIdentifier = "inactivity-nudge"
    private static let milestoneScheduleSignatureKey = "notification.milestoneScheduleSignature"
    private static let inactivityScheduleDayKey = "notification.inactivityScheduleDay"

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Foreground maintenance shares one cross-process permission lookup. Calling the
    /// two scheduling paths separately used to ask notificationd the same question twice.
    static func refreshForeground(
        streakStart: Date,
        nicotineType: NicotineType,
        now: Date = .now
    ) async {
        guard await authorizationStatus() == .authorized else { return }
        await refreshMilestones(
            streakStart: streakStart,
            nicotineType: nicotineType,
            now: now,
            authorizationConfirmed: true
        )
        await scheduleInactivityNudge(authorizationConfirmed: true)
    }

    static func scheduleDaily(hour: Int) async throws {
        let center = UNUserNotificationCenter.current()
        let allowed = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        guard allowed else { throw NotificationError.permissionDenied }
        center.removePendingNotificationRequests(withIdentifiers: [dailyIdentifier])
        let content = UNMutableNotificationContent()
        content.title = "How are you doing?"
        content.body = "Take a moment to check in with your quit plan."
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: hour), repeats: true)
        try await center.add(UNNotificationRequest(identifier: dailyIdentifier, content: content, trigger: trigger))
    }

    /// How long before a milestone the "almost there" heads-up fires.
    private static let headsUpLeadTime: TimeInterval = 2 * 3_600

    /// Celebration pings at each upcoming milestone, plus a heads-up ~2 hours before each
    /// one — a craving right before a milestone is easy to mistake for "this never gets
    /// better," so the reminder that it is a wave, not a permanent state, is timed for
    /// exactly when that misreading is most likely. Never prompts for permission — it only
    /// schedules when the person has already allowed notifications — and it is safe to call
    /// repeatedly: a compact schedule signature skips unchanged work, while a changed quit
    /// date or a slip that moves the streak start still lays down accurate reminders.
    /// How many upcoming checkpoints to actually lay down. Every checkpoint would mean
    /// dozens of sequential `add` round-trips to the notification daemon on every single
    /// foreground, which is real launch cost for pings that may be a year away. This runs
    /// again on each foreground, so the far ones get scheduled long before they matter.
    private static let scheduledMilestoneHorizon = 4

    static func refreshMilestones(streakStart: Date, nicotineType: NicotineType, now: Date = .now) async {
        await refreshMilestones(
            streakStart: streakStart,
            nicotineType: nicotineType,
            now: now,
            authorizationConfirmed: false
        )
    }

    private static func refreshMilestones(
        streakStart: Date,
        nicotineType: NicotineType,
        now: Date,
        authorizationConfirmed: Bool
    ) async {
        let center = UNUserNotificationCenter.current()
        if !authorizationConfirmed {
            guard await authorizationStatus() == .authorized else { return }
        }
        let milestones = ProgressCalculator.milestones(for: nicotineType)
        let upcoming = Array(milestones
            .filter { streakStart.addingTimeInterval(TimeInterval($0.hours) * 3_600) > now }
            .prefix(scheduledMilestoneHorizon))
        let signature = [
            String(Int(streakStart.timeIntervalSince1970)),
            nicotineType.storedValue,
            upcoming.map { String($0.hours) }.joined(separator: ",")
        ].joined(separator: "|")
        guard UserDefaults.standard.string(forKey: milestoneScheduleSignatureKey) != signature else { return }
        let identifiers = milestones.flatMap {
            [milestoneIdentifier($0.hours), headsUpIdentifier($0.hours)]
        }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        var scheduledSuccessfully = true
        for milestone in upcoming {
            let fireDate = streakStart.addingTimeInterval(TimeInterval(milestone.hours) * 3_600)
            let interval = fireDate.timeIntervalSince(now)
            // Skip anything already reached or so close it would fire mid-schedule.
            if interval > 60 {
                let content = UNMutableNotificationContent()
                content.title = "🎉 \(milestone.title) nicotine-free"
                content.body = "\(milestone.detail). Open QuitNic to see how much you have saved."
                content.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
                do {
                    try await center.add(UNNotificationRequest(
                        identifier: milestoneIdentifier(milestone.hours),
                        content: content,
                        trigger: trigger
                    ))
                } catch { scheduledSuccessfully = false }
            }

            let headsUpInterval = interval - headsUpLeadTime
            if headsUpInterval > 60 {
                let content = UNMutableNotificationContent()
                content.title = "Almost there"
                content.body = "About 2 hours to your \(milestone.title) milestone. Cravings are like swings — they come and go. You won't feel like this constantly."
                content.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: headsUpInterval, repeats: false)
                do {
                    try await center.add(UNNotificationRequest(
                        identifier: headsUpIdentifier(milestone.hours),
                        content: content,
                        trigger: trigger
                    ))
                } catch { scheduledSuccessfully = false }
            }
        }
        if scheduledSuccessfully {
            UserDefaults.standard.set(signature, forKey: milestoneScheduleSignatureKey)
        }
    }

    /// A single gentle nudge if the app goes untouched. Rescheduled every foreground so it
    /// only ever fires after a real stretch of silence, not while somebody is using the app.
    static func scheduleInactivityNudge(after hours: Double = 48) async {
        await scheduleInactivityNudge(after: hours, authorizationConfirmed: false)
    }

    private static func scheduleInactivityNudge(
        after hours: Double = 48,
        authorizationConfirmed: Bool
    ) async {
        let center = UNUserNotificationCenter.current()
        if !authorizationConfirmed {
            guard await authorizationStatus() == .authorized else { return }
        }
        let today = Int(Calendar.current.startOfDay(for: .now).timeIntervalSince1970)
        guard UserDefaults.standard.integer(forKey: inactivityScheduleDayKey) != today else { return }
        center.removePendingNotificationRequests(withIdentifiers: [inactivityIdentifier])
        let content = UNMutableNotificationContent()
        content.title = "Still with you"
        content.body = "A quick check-in keeps your momentum going. One small step is enough."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: hours * 3_600, repeats: false)
        do {
            try await center.add(UNNotificationRequest(identifier: inactivityIdentifier, content: content, trigger: trigger))
            UserDefaults.standard.set(today, forKey: inactivityScheduleDayKey)
        } catch {}
    }

    private static func milestoneIdentifier(_ hours: Int) -> String { "milestone-\(hours)" }
    private static func headsUpIdentifier(_ hours: Int) -> String { "milestone-heads-up-\(hours)" }

    static func removeDailyCheckIn() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [dailyIdentifier])
    }

    static func removeAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UserDefaults.standard.removeObject(forKey: milestoneScheduleSignatureKey)
        UserDefaults.standard.removeObject(forKey: inactivityScheduleDayKey)
    }
}
