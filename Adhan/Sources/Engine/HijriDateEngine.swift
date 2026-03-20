import Foundation

/// Hijri (Islamic) date calculations using Foundation's built-in Islamic calendar.
@MainActor
@Observable
final class HijriDateEngine {
    private(set) var hijriDateString: String = ""
    private(set) var hijriDay: Int = 1
    private(set) var hijriMonth: Int = 1
    private(set) var hijriYear: Int = 1446

    private let hijriCalendar = Calendar(identifier: .islamicUmmAlQura)

    private static let hijriMonthNames: [Int: String] = [
        1: "Muharram",
        2: "Safar",
        3: "Rabi\u{02BB} al-Awwal",
        4: "Rabi\u{02BB} al-Thani",
        5: "Jumada al-Ula",
        6: "Jumada al-Thani",
        7: "Rajab",
        8: "Sha\u{02BB}ban",
        9: "Ramadan",
        10: "Shawwal",
        11: "Dhu al-Qi\u{02BB}dah",
        12: "Dhu al-Hijjah"
    ]

    private static let hijriMonthNamesArabic: [Int: String] = [
        1: "\u{0645}\u{062D}\u{0631}\u{0651}\u{0645}",
        2: "\u{0635}\u{0641}\u{0631}",
        3: "\u{0631}\u{0628}\u{064A}\u{0639} \u{0627}\u{0644}\u{0623}\u{0648}\u{0651}\u{0644}",
        4: "\u{0631}\u{0628}\u{064A}\u{0639} \u{0627}\u{0644}\u{062B}\u{0627}\u{0646}\u{064A}",
        5: "\u{062C}\u{0645}\u{0627}\u{062F}\u{0649} \u{0627}\u{0644}\u{0623}\u{0648}\u{0644}\u{0649}",
        6: "\u{062C}\u{0645}\u{0627}\u{062F}\u{0649} \u{0627}\u{0644}\u{062B}\u{0627}\u{0646}\u{064A}\u{0629}",
        7: "\u{0631}\u{062C}\u{0628}",
        8: "\u{0634}\u{0639}\u{0628}\u{0627}\u{0646}",
        9: "\u{0631}\u{0645}\u{0636}\u{0627}\u{0646}",
        10: "\u{0634}\u{0648}\u{0651}\u{0627}\u{0644}",
        11: "\u{0630}\u{0648} \u{0627}\u{0644}\u{0642}\u{0639}\u{062F}\u{0629}",
        12: "\u{0630}\u{0648} \u{0627}\u{0644}\u{062D}\u{062C}\u{0651}\u{0629}"
    ]

    func update(for date: Date = Date()) {
        let components = hijriCalendar.dateComponents([.day, .month, .year], from: date)
        hijriDay = components.day ?? 1
        hijriMonth = components.month ?? 1
        hijriYear = components.year ?? 1446

        let monthName = Self.hijriMonthNames[hijriMonth] ?? "Unknown"
        hijriDateString = "\(hijriDay) \(monthName) \(hijriYear) AH"
    }

    /// Returns the Arabic month name for the current Hijri month.
    var arabicMonthName: String {
        Self.hijriMonthNamesArabic[hijriMonth] ?? ""
    }

    /// Returns the English month name for the current Hijri month.
    var monthName: String {
        Self.hijriMonthNames[hijriMonth] ?? "Unknown"
    }

    /// Check if the current Hijri month is Ramadan.
    var isRamadan: Bool {
        hijriMonth == 9
    }

    /// Check if today is Friday (Jumu'ah).
    var isFriday: Bool {
        Calendar.current.component(.weekday, from: Date()) == 6
    }
}
