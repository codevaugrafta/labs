import Foundation
import Testing
@testable import AdhanApp

@Suite("AppSettings menu bar visibility", .serialized)
struct AppSettingsMenuBarVisibilityTests {
    private let keys = [
        AppSettings.menuBarShowHijriDateKey,
        AppSettings.menuBarShowLocationKey,
        AppSettings.menuBarShowPrayerTimetableKey,
    ]

    @Test("Absent UserDefaults keys mean menu sections are shown")
    func absentKeysDefaultToTrue() {
        let d = UserDefaults.standard
        let snapshot = keys.map { ($0, d.object(forKey: $0)) }
        defer {
            for (key, value) in snapshot {
                if let value {
                    d.set(value, forKey: key)
                } else {
                    d.removeObject(forKey: key)
                }
            }
        }
        for key in keys {
            d.removeObject(forKey: key)
        }

        #expect(AppSettings.menuBarShowsHijriDate())
        #expect(AppSettings.menuBarShowsLocation())
        #expect(AppSettings.menuBarShowsPrayerTimetable())
    }

    @Test("Explicit false hides menu sections")
    func explicitFalseHides() {
        let d = UserDefaults.standard
        let snapshot = keys.map { ($0, d.object(forKey: $0)) }
        defer {
            for (key, value) in snapshot {
                if let value {
                    d.set(value, forKey: key)
                } else {
                    d.removeObject(forKey: key)
                }
            }
        }

        d.set(false, forKey: AppSettings.menuBarShowHijriDateKey)
        d.set(false, forKey: AppSettings.menuBarShowLocationKey)
        d.set(false, forKey: AppSettings.menuBarShowPrayerTimetableKey)

        #expect(!AppSettings.menuBarShowsHijriDate())
        #expect(!AppSettings.menuBarShowsLocation())
        #expect(!AppSettings.menuBarShowsPrayerTimetable())
    }

    @Test("Explicit true shows menu sections")
    func explicitTrueShows() {
        let d = UserDefaults.standard
        let snapshot = keys.map { ($0, d.object(forKey: $0)) }
        defer {
            for (key, value) in snapshot {
                if let value {
                    d.set(value, forKey: key)
                } else {
                    d.removeObject(forKey: key)
                }
            }
        }

        d.set(true, forKey: AppSettings.menuBarShowHijriDateKey)
        d.set(true, forKey: AppSettings.menuBarShowLocationKey)
        d.set(true, forKey: AppSettings.menuBarShowPrayerTimetableKey)

        #expect(AppSettings.menuBarShowsHijriDate())
        #expect(AppSettings.menuBarShowsLocation())
        #expect(AppSettings.menuBarShowsPrayerTimetable())
    }
}
