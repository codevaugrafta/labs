import Foundation

/// DTOs for the my-masjid.com API response.
/// Endpoint: /api/TimingsInfoScreen/GetMasjidTimings?GuidId={guid}

struct MyMasjidResponse: Codable, Sendable {
    let model: MyMasjidModel
}

struct MyMasjidModel: Codable, Sendable {
    let masjidDetails: MyMasjidDetails?
    let salahTimings: [MyMasjidTiming]?
}

struct MyMasjidDetails: Codable, Sendable {
    let name: String?
    let guidId: String?
}

struct MyMasjidTiming: Codable, Sendable {
    // Begin (Adhan) times — lowercase keys
    let fajr: String?
    let shouruq: String?
    let zuhr: String?
    let asr: String?
    let maghrib: String?
    let isha: String?

    // Day/month as integers (no year — assumes current year)
    let day: Int
    let month: Int

    // Iqamah times — API keys `iqamah_Fajr`, etc.
    let iqamahFajr: String?
    let iqamahZuhr: String?
    let iqamahAsr: String?
    let iqamahMaghrib: String?
    let iqamahIsha: String?

    enum CodingKeys: String, CodingKey {
        case fajr, shouruq, zuhr, asr, maghrib, isha
        case day, month
        case iqamahFajr = "iqamah_Fajr"
        case iqamahZuhr = "iqamah_Zuhr"
        case iqamahAsr = "iqamah_Asr"
        case iqamahMaghrib = "iqamah_Maghrib"
        case iqamahIsha = "iqamah_Isha"
    }

    /// Get the begin (Adhan) time for a prayer.
    func beginTime(for prayer: PrayerName) -> String? {
        switch prayer {
        case .fajr:    return fajr
        case .sunrise: return shouruq
        case .dhuhr:   return zuhr
        case .asr:     return asr
        case .maghrib: return maghrib
        case .isha:    return isha
        }
    }

    /// Iqamah time string for a prayer from the API.
    func iqamahTime(for prayer: PrayerName) -> String? {
        switch prayer {
        case .fajr:    return iqamahFajr
        case .dhuhr:   return iqamahZuhr
        case .asr:     return iqamahAsr
        case .maghrib: return iqamahMaghrib
        case .isha:    return iqamahIsha
        case .sunrise: return nil
        }
    }

    /// Build a Date for this timing entry (uses current year).
    func parsedDate() -> Date? {
        let year = Calendar.current.component(.year, from: Date())
        let dateStr = String(format: "%04d-%02d-%02d", year, month, day)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: dateStr)
    }
}
