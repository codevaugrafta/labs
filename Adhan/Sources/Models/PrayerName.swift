import Foundation
import Adhan

/// The five daily prayers plus sunrise, with display names and Arabic text.
enum PrayerName: String, CaseIterable, Sendable, Identifiable {
    case fajr
    case sunrise
    case dhuhr
    case asr
    case maghrib
    case isha

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fajr:    return "Fajr"
        case .sunrise: return "Sunrise"
        case .dhuhr:   return "Dhuhr"
        case .asr:     return "Asr"
        case .maghrib: return "Maghrib"
        case .isha:    return "Isha"
        }
    }

    var arabicName: String {
        switch self {
        case .fajr:    return "\u{0627}\u{0644}\u{0641}\u{062C}\u{0631}"      // الفجر
        case .sunrise: return "\u{0627}\u{0644}\u{0634}\u{0631}\u{0648}\u{0642}" // الشروق
        case .dhuhr:   return "\u{0627}\u{0644}\u{0638}\u{0647}\u{0631}"      // الظهر
        case .asr:     return "\u{0627}\u{0644}\u{0639}\u{0635}\u{0631}"      // العصر
        case .maghrib: return "\u{0627}\u{0644}\u{0645}\u{063A}\u{0631}\u{0628}" // المغرب
        case .isha:    return "\u{0627}\u{0644}\u{0639}\u{0634}\u{0627}\u{0621}" // العشاء
        }
    }

    var systemImage: String {
        switch self {
        case .fajr:    return "sunrise.fill"
        case .sunrise: return "sun.horizon.fill"
        case .dhuhr:   return "sun.max.fill"
        case .asr:     return "sun.min.fill"
        case .maghrib: return "sunset.fill"
        case .isha:    return "moon.stars.fill"
        }
    }

    /// Only the 5 obligatory prayers (excludes sunrise).
    static let obligatory: [PrayerName] = [.fajr, .dhuhr, .asr, .maghrib, .isha]

    /// Map from adhan-swift's Prayer enum.
    init?(adhanPrayer: Prayer) {
        switch adhanPrayer {
        case .fajr:    self = .fajr
        case .sunrise: self = .sunrise
        case .dhuhr:   self = .dhuhr
        case .asr:     self = .asr
        case .maghrib: self = .maghrib
        case .isha:    self = .isha
        }
    }
}
