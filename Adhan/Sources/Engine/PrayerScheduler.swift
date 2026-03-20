import Foundation
import AppKit

/// 3-layer prayer time scheduler:
/// 1. DispatchSourceTimer — primary, precise timing
/// 2. UNNotification — backup, survives app suspension
/// 3. Sleep/wake recovery — NSWorkspace notifications
@MainActor
@Observable
final class PrayerScheduler {
    private(set) var scheduledPrayers: [PrayerName: Date] = [:]
    private var timers: [PrayerName: DispatchSourceTimer] = [:]
    private var preReminderTimers: [PrayerName: DispatchSourceTimer] = [:]

    weak var engine: PrayerTimesEngine?
    weak var adhanPlayer: AdhanPlayer?
    var onPrayerTime: ((PrayerName) -> Void)?

    var preReminderMinutes: Int {
        get { UserDefaults.standard.object(forKey: AppSettings.preReminderMinutesKey) as? Int ?? AppSettings.defaultPreReminderMinutes }
        set { UserDefaults.standard.set(newValue, forKey: AppSettings.preReminderMinutesKey); reschedule() }
    }

    // MARK: - Lifecycle

    func start() {
        reschedule()
        registerSleepWakeObservers()
    }

    func stop() {
        cancelAllTimers()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    /// Reschedule all prayer timers for today.
    func reschedule() {
        cancelAllTimers()

        guard let engine else { return }

        for entry in engine.todayEntries {
            guard entry.prayer != .sunrise else { continue } // Don't schedule for sunrise
            guard entry.isFuture else { continue }           // Skip past prayers

            schedulePrayer(entry.prayer, at: entry.adhanTime)
            schedulePreReminder(entry.prayer, prayerTime: entry.adhanTime)
        }

        if let next = engine.nextPrayer, next.isNextDayPreview {
            schedulePrayer(.fajr, at: next.adhanTime)
            schedulePreReminder(.fajr, prayerTime: next.adhanTime)
        }
    }

    // MARK: - Timer Scheduling

    private func schedulePrayer(_ prayer: PrayerName, at date: Date) {
        let interval = date.timeIntervalSinceNow
        guard interval > 0 else { return }

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + interval)
        timer.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.firePrayerTime(prayer)
            }
        }
        timer.resume()

        timers[prayer] = timer
        scheduledPrayers[prayer] = date
    }

    private func schedulePreReminder(_ prayer: PrayerName, prayerTime: Date) {
        let reminderInterval = TimeInterval(preReminderMinutes * 60)
        let reminderDate = prayerTime.addingTimeInterval(-reminderInterval)
        let interval = reminderDate.timeIntervalSinceNow
        guard interval > 0 else { return }

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + interval)
        timer.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.firePreReminder(prayer)
            }
        }
        timer.resume()

        preReminderTimers[prayer] = timer
    }

    // MARK: - Fire Events

    private func firePrayerTime(_ prayer: PrayerName) {
        timers[prayer]?.cancel()
        timers[prayer] = nil

        // Play Adhan (always resolve — unknown UserDefaults id falls back to defaults)
        let storedId: String?
        if prayer == .fajr {
            storedId = UserDefaults.standard.string(forKey: AppSettings.fajrRecitationKey)
        } else {
            storedId = UserDefaults.standard.string(forKey: AppSettings.defaultRecitationKey)
        }
        let recitation = AdhanRecitation.resolveBundled(storedId: storedId, forFajr: prayer == .fajr)
        adhanPlayer?.play(recitation: recitation)

        // Haptic feedback
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)

        // Notify callback
        onPrayerTime?(prayer)
    }

    private func firePreReminder(_ prayer: PrayerName) {
        preReminderTimers[prayer]?.cancel()
        preReminderTimers[prayer] = nil

        adhanPlayer?.playChime()
    }

    // MARK: - Sleep/Wake Recovery

    private func registerSleepWakeObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                // After wake, check if any prayer times were missed during sleep
                self?.engine?.recalculate()
                self?.reschedule()

                // Check if a prayer time occurred during sleep
                self?.checkMissedPrayers()
            }
        }
    }

    /// After sleep, replay Adhan for the **most recent** obligatory prayer that passed within this window.
    private static let missedPrayerReplayWindow: TimeInterval = 2 * 60 * 60 // 2 hours

    private func checkMissedPrayers() {
        guard let engine else { return }

        let now = Date()
        var best: PrayerTimeEntry?

        for entry in engine.todayEntries {
            guard entry.prayer != .sunrise else { continue }
            guard entry.hasPassed else { continue }

            let elapsed = now.timeIntervalSince(entry.adhanTime)
            guard elapsed > 0, elapsed <= Self.missedPrayerReplayWindow else { continue }

            if best == nil || entry.adhanTime > best!.adhanTime {
                best = entry
            }
        }

        if let best {
            AdhanLog.scheduler.notice("Wake: replaying missed prayer \(best.prayer.rawValue, privacy: .public) (within replay window)")
            firePrayerTime(best.prayer)
        }
    }

    // MARK: - Cleanup

    private func cancelAllTimers() {
        for (_, timer) in timers { timer.cancel() }
        timers.removeAll()
        for (_, timer) in preReminderTimers { timer.cancel() }
        preReminderTimers.removeAll()
        scheduledPrayers.removeAll()
    }
}
