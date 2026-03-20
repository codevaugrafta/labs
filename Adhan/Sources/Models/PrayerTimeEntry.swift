import Foundation

/// A single prayer time entry: Adhan (begin) time plus optional **Iqamah** from the mosque source (my-masjid.com `iqamah_*` fields).
struct PrayerTimeEntry: Identifiable, Sendable {
    let id: String
    let prayer: PrayerName
    let adhanTime: Date        // Prayer begins (mosque timetable or calculated)
    /// Congregation time from the mosque API (`iqamah_Fajr`, `iqamah_Zuhr`, …). Nil when no mosque data or not applicable (e.g. sunrise).
    var iqamahTime: Date?

    /// The primary display time — Adhan (begin) time.
    var beginTime: Date { adhanTime }

    /// Formatted begin time string (e.g., "05:34").
    var formattedBeginTime: String {
        Self.timeFormatter.string(from: adhanTime)
    }

    /// Formatted Iqamah time when the mosque source provides it.
    var formattedIqamahTime: String? {
        iqamahTime.map { Self.timeFormatter.string(from: $0) }
    }

    /// Time remaining until this prayer's Adhan time from now.
    var timeUntil: TimeInterval {
        adhanTime.timeIntervalSinceNow
    }

    /// Whether this prayer time is in the future.
    var isFuture: Bool {
        adhanTime > Date()
    }

    /// Whether this prayer time has passed.
    var hasPassed: Bool {
        adhanTime <= Date()
    }

    /// Formatted countdown string (e.g., "2:34:15") until **Adhan (begin)** time.
    var formattedCountdown: String {
        Self.formatCountdownInterval(max(0, timeUntil))
    }

    /// Countdown until Iqamah when `iqamahTime` is set; nil otherwise.
    func formattedCountdownToIqamah(now: Date = Date()) -> String? {
        guard let iq = iqamahTime else { return nil }
        return Self.formatCountdownInterval(max(0, iq.timeIntervalSince(now)))
    }

    /// Synthetic menu-bar entry uses id suffix `menuIqamah` while counting down to congregation time.
    var isMenuBarIqamahPhase: Bool {
        id.hasSuffix("-menuIqamah")
    }

    static func formatCountdownInterval(_ remaining: TimeInterval) -> String {
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        let seconds = Int(remaining) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale.current
        return f
    }()

    /// - Parameter idSuffix: When set, `id` becomes `"\(prayer.rawValue)-\(suffix)"` so the entry is distinct from today's same prayer (e.g. tomorrow's Fajr as "next" after Isha).
    init(prayer: PrayerName, adhanTime: Date, iqamahTime: Date? = nil, idSuffix: String? = nil) {
        if let idSuffix {
            self.id = "\(prayer.rawValue)-\(idSuffix)"
        } else {
            self.id = prayer.rawValue
        }
        self.prayer = prayer
        self.adhanTime = adhanTime
        self.iqamahTime = iqamahTime
    }

    /// True when this entry represents the next prayer on the following Gregorian day (not a row in today's list).
    var isNextDayPreview: Bool {
        id.hasSuffix("-nextDay")
    }
}
