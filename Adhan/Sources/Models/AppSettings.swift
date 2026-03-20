import Foundation

/// Central @AppStorage key constants for the Adhan app.
enum AppSettings {
    // MARK: - Location
    static let latitudeKey = "adhan_latitude"
    static let longitudeKey = "adhan_longitude"
    static let locationNameKey = "adhan_locationName"

    // MARK: - Calculation
    static let calculationMethodKey = "adhan_calculationMethod"
    static let madhabKey = "adhan_madhab"

    // MARK: - Display
    static let menuBarDisplayModeKey = "adhan_menuBarDisplayMode"
    /// Menu bar dropdown: show Hijri date row (default on).
    static let menuBarShowHijriDateKey = "adhan_menuBar_showHijriDate"
    /// Menu bar dropdown: show location row (default on).
    static let menuBarShowLocationKey = "adhan_menuBar_showLocation"
    /// Menu bar dropdown: show prayer timetable, preview, and “Next:” summary (default on).
    static let menuBarShowPrayerTimetableKey = "adhan_menuBar_showPrayerTimetable"
    /// When true, menu bar jumps to the next prayer’s **begin** time after Adhan (legacy). When false/absent, count down to **Iqamah** first when mosque data provides it.
    static let menuBarSkipIqamahCountdownKey = "adhan_menuBar_skipIqamahCountdown"

    /// `nil` in UserDefaults means “default true” for existing users.
    static func menuBarShowsHijriDate() -> Bool {
        guard UserDefaults.standard.object(forKey: menuBarShowHijriDateKey) != nil else { return true }
        return UserDefaults.standard.bool(forKey: menuBarShowHijriDateKey)
    }

    static func menuBarShowsLocation() -> Bool {
        guard UserDefaults.standard.object(forKey: menuBarShowLocationKey) != nil else { return true }
        return UserDefaults.standard.bool(forKey: menuBarShowLocationKey)
    }

    static func menuBarShowsPrayerTimetable() -> Bool {
        guard UserDefaults.standard.object(forKey: menuBarShowPrayerTimetableKey) != nil else { return true }
        return UserDefaults.standard.bool(forKey: menuBarShowPrayerTimetableKey)
    }

    /// `nil` / false → show Iqamah countdown after Adhan when available (default).
    static func menuBarSkipsIqamahCountdown() -> Bool {
        UserDefaults.standard.bool(forKey: menuBarSkipIqamahCountdownKey)
    }
    /// Main window text: 0 = Medium, 1 = Large (default), 2 = XLarge, 3 = XXLarge (DynamicTypeSize).
    static let mainWindowTextSizeKey = "adhan_mainWindowTextSize"
    static let floatingPanelSizeKey = "adhan_floatingPanelSize"
    static let floatingPanelModeKey = "adhan_floatingPanelMode"
    static let selectedThemeKey = "adhan_selectedTheme"

    // MARK: - Mosque
    static let mosqueGuidKey = "adhan_mosqueGuid"
    static let mosqueNameKey = "adhan_mosqueName"

    // MARK: - Audio
    static let adhanVolumeKey = "adhan_volume"
    static let preReminderMinutesKey = "adhan_preReminderMinutes"
    static let fajrRecitationKey = "adhan_fajrRecitation"
    static let defaultRecitationKey = "adhan_defaultRecitation"

    // MARK: - Defaults
    static let defaultLatitude: Double = 55.6761    // Copenhagen
    static let defaultLongitude: Double = 12.5683
    static let defaultLocationName = "Copenhagen, Denmark"
    static let defaultCalculationMethod = "moonsightingCommittee"
    static let defaultMadhab = "shafi"
    static let defaultVolume: Float = 0.7
    static let defaultPreReminderMinutes: Int = 15

    // User's mosque — auto-connect on first launch
    static let defaultMosqueGuid = "85966a2e-4c6d-48fa-9aa8-c29d1052e51c"
}

/// Menu bar display modes.
enum MenuBarDisplayMode: Int, CaseIterable, Sendable {
    case countdown = 0    // "Maghrib in 2:34:15"
    case exactTime = 1    // "Maghrib 18:34"
    case iconOnly = 2     // Just the crescent icon

    var label: String {
        switch self {
        case .countdown: return "Countdown"
        case .exactTime: return "Exact Time"
        case .iconOnly:  return "Icon Only"
        }
    }
}
