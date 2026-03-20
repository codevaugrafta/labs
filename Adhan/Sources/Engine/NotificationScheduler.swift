import Foundation
@preconcurrency import UserNotifications

/// Schedules macOS notification banners for prayer times as a backup to the in-app scheduler.
@MainActor
final class NotificationScheduler {
    private weak var engine: PrayerTimesEngine?

    private var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    func setup(engine: PrayerTimesEngine) {
        self.engine = engine
        requestPermission()
    }

    // MARK: - Permission

    private func requestPermission() {
        guard isAvailable else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                AdhanLog.notifications.error("Notification permission error: \(error.localizedDescription, privacy: .public)")
            } else if !granted {
                AdhanLog.notifications.warning("Notification permission denied — system backup alerts may not fire")
            }
        }
    }

    // MARK: - Schedule Notifications

    func scheduleAll() {
        guard isAvailable else { return }
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        guard let engine else { return }

        for entry in engine.todayEntries {
            guard entry.prayer != .sunrise else { continue }
            guard entry.isFuture else { continue }

            schedulePrayerNotification(entry)

            let preMinutes = UserDefaults.standard.object(forKey: AppSettings.preReminderMinutesKey) as? Int
                ?? AppSettings.defaultPreReminderMinutes
            schedulePreReminderNotification(entry, minutesBefore: preMinutes)
        }

        // After the last prayer of the day, next obligation is tomorrow's Fajr (not in `todayEntries`).
        if let next = engine.nextPrayer, next.isNextDayPreview {
            schedulePrayerNotification(next)
            let preMinutes = UserDefaults.standard.object(forKey: AppSettings.preReminderMinutesKey) as? Int
                ?? AppSettings.defaultPreReminderMinutes
            schedulePreReminderNotification(next, minutesBefore: preMinutes)
        }

        if engine.isFriday {
            scheduleFridayReminders()
        }
    }

    // MARK: - Friday Reminders

    private func scheduleFridayReminders() {
        guard let engine else { return }

        if let fajr = engine.todayEntries.first(where: { $0.prayer == .fajr }) {
            let kahfDate = fajr.adhanTime.addingTimeInterval(30 * 60)
            scheduleOneShot(
                identifier: "friday-kahf",
                title: "Jumu'ah Mubarak \u{2728}",
                body: "It's Friday — read Surah Al-Kahf and send Salawat upon the Prophet \u{FDFA}",
                category: "FRIDAY_REMINDER",
                fireAt: kahfDate
            )
        }

        if let dhuhr = engine.todayEntries.first(where: { $0.prayer == .dhuhr }) {
            let salawatDate = dhuhr.adhanTime.addingTimeInterval(-60 * 60)
            scheduleOneShot(
                identifier: "friday-salawat",
                title: "Salawat Reminder",
                body: "Increase your Salawat upon the Prophet \u{FDFA} — the best day the sun rises on is Friday",
                category: "FRIDAY_REMINDER",
                fireAt: salawatDate
            )
        }
    }

    private func schedulePrayerNotification(_ entry: PrayerTimeEntry) {
        guard let trigger = intervalTrigger(fromNowUntil: entry.adhanTime) else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(entry.prayer.displayName) - \(entry.prayer.arabicName)"
        content.body = "It's time for \(entry.prayer.displayName) prayer (\(entry.formattedBeginTime))"
        content.sound = .default
        content.categoryIdentifier = "PRAYER_TIME"

        let idSuffix = entry.isNextDayPreview ? "-nextDay" : ""
        let request = UNNotificationRequest(
            identifier: "prayer-\(entry.prayer.rawValue)\(idSuffix)",
            content: content,
            trigger: trigger
        )
        deliver(request)
    }

    private func schedulePreReminderNotification(_ entry: PrayerTimeEntry, minutesBefore: Int) {
        let reminderDate = entry.adhanTime.addingTimeInterval(-TimeInterval(minutesBefore * 60))
        guard reminderDate > Date(), let trigger = intervalTrigger(fromNowUntil: reminderDate) else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(entry.prayer.displayName) in \(minutesBefore) minutes"
        content.body = "\(entry.prayer.displayName) prayer begins at \(entry.formattedBeginTime)"
        content.sound = .default
        content.categoryIdentifier = "PRAYER_REMINDER"

        let idSuffix = entry.isNextDayPreview ? "-nextDay" : ""
        let request = UNNotificationRequest(
            identifier: "reminder-\(entry.prayer.rawValue)\(idSuffix)",
            content: content,
            trigger: trigger
        )
        deliver(request)
    }

    private func scheduleOneShot(identifier: String, title: String, body: String, category: String, fireAt: Date) {
        guard fireAt > Date(), let trigger = intervalTrigger(fromNowUntil: fireAt) else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
        deliver(request)
    }

    /// Uses time-interval triggers so the fire time is exact for “today” and survives DST better than hour/minute-only calendar matching.
    private func intervalTrigger(fromNowUntil date: Date) -> UNNotificationTrigger? {
        let interval = date.timeIntervalSinceNow
        guard interval > 1 else { return nil }
        return UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
    }

    private func deliver(_ request: UNNotificationRequest) {
        let identifier = request.identifier
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                AdhanLog.notifications.error("Schedule failed \(identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
