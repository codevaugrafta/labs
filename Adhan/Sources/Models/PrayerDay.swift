import Foundation
import SwiftData

/// Cached mosque prayer times for a single day.
/// Fetched from my-masjid.com and stored locally for offline access.
@Model
final class PrayerDay {
    var date: Date
    var mosqueName: String
    var mosqueGuid: String

    // Iqamah times from API (`iqamah_*`) stored as "HH:mm" — SwiftData property names unchanged for migration.
    var fajrJamaah: String?
    var dhuhrJamaah: String?
    var asrJamaah: String?
    var maghribJamaah: String?
    var ishaJamaah: String?

    // Begin times from mosque (may differ from calculated)
    var fajrBegins: String?
    var sunrise: String?
    var dhuhrBegins: String?
    var asrBegins: String?
    var maghribBegins: String?
    var ishaBegins: String?

    // Jumu'ah times
    var jummah1: String?
    var jummah2: String?

    var fetchedAt: Date
    var updatedAt: Date

    init(date: Date, mosqueName: String, mosqueGuid: String) {
        self.date = date
        self.mosqueName = mosqueName
        self.mosqueGuid = mosqueGuid
        self.fetchedAt = Date()
        self.updatedAt = Date()
    }

    /// Iqamah time string from the mosque timetable for this prayer, if present.
    func iqamahTimeString(for prayer: PrayerName) -> String? {
        switch prayer {
        case .fajr:    return fajrJamaah
        case .dhuhr:   return dhuhrJamaah
        case .asr:     return asrJamaah
        case .maghrib: return maghribJamaah
        case .isha:    return ishaJamaah
        case .sunrise: return nil
        }
    }

    /// Parsed Iqamah `Date` on this cached day.
    func iqamahDate(for prayer: PrayerName) -> Date? {
        guard let timeStr = iqamahTimeString(for: prayer) else { return nil }
        return Self.parseTime(timeStr, on: date)
    }

    /// Get the mosque's begin (Adhan) time string for a specific prayer.
    func beginTimeString(for prayer: PrayerName) -> String? {
        switch prayer {
        case .fajr:    return fajrBegins
        case .sunrise: return sunrise
        case .dhuhr:   return dhuhrBegins
        case .asr:     return asrBegins
        case .maghrib: return maghribBegins
        case .isha:    return ishaBegins
        }
    }

    /// Parse the mosque's begin time into a Date for this day.
    func beginDate(for prayer: PrayerName) -> Date? {
        guard let timeStr = beginTimeString(for: prayer) else { return nil }
        return Self.parseTime(timeStr, on: date)
    }

    static func parseTime(_ timeStr: String, on date: Date) -> Date? {
        let parts = timeStr.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else { return nil }

        var cal = Calendar.current
        cal.timeZone = TimeZone.current
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: date)
    }
}
