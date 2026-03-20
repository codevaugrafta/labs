import Foundation

extension Date {
    private static let hijriCalendar = Calendar(identifier: .islamicUmmAlQura)

    /// Hijri date components for this date.
    var hijriComponents: DateComponents {
        Self.hijriCalendar.dateComponents([.day, .month, .year], from: self)
    }

    /// Hijri day of the month.
    var hijriDay: Int { hijriComponents.day ?? 1 }

    /// Hijri month (1-12).
    var hijriMonth: Int { hijriComponents.month ?? 1 }

    /// Hijri year.
    var hijriYear: Int { hijriComponents.year ?? 1446 }

    /// Whether this date falls in Ramadan (month 9).
    var isRamadan: Bool { hijriMonth == 9 }

    /// Whether this date is the first day of Ramadan.
    var isFirstDayOfRamadan: Bool { hijriMonth == 9 && hijriDay == 1 }

    /// Whether this date is Eid al-Fitr (1 Shawwal).
    var isEidAlFitr: Bool { hijriMonth == 10 && hijriDay == 1 }

    /// Whether this date is Eid al-Adha (10 Dhul Hijjah).
    var isEidAlAdha: Bool { hijriMonth == 12 && hijriDay == 10 }

    /// Whether this date is a Friday.
    var isFriday: Bool {
        Calendar.current.component(.weekday, from: self) == 6
    }

    /// Whether this date is in the last ten nights of Ramadan.
    var isLastTenNightsOfRamadan: Bool {
        hijriMonth == 9 && hijriDay >= 21
    }

    /// Days until next Ramadan (0 if currently Ramadan).
    var daysUntilRamadan: Int {
        if isRamadan { return 0 }
        // Approximate — Hijri calendar shifts ~11 days/year
        var components = hijriComponents
        if hijriMonth >= 9 {
            components.year = (components.year ?? 1446) + 1
        }
        components.month = 9
        components.day = 1
        if let ramadanStart = Self.hijriCalendar.date(from: components) {
            return Calendar.current.dateComponents([.day], from: self, to: ramadanStart).day ?? 0
        }
        return 0
    }
}
