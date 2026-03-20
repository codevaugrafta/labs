import Foundation
import Observation
import Adhan

/// Core prayer times engine — calculates daily prayer times using adhan-swift,
/// manages next-prayer tracking, and provides merged begin + mosque Iqamah entries.
@MainActor
@Observable
final class PrayerTimesEngine {

    // MARK: - Published State

    private(set) var todayEntries: [PrayerTimeEntry] = []
    private(set) var nextPrayer: PrayerTimeEntry?
    private(set) var currentPrayerName: PrayerName?
    private(set) var lastError: String?

    /// Calculated Fajr for the next Gregorian day (used when today's obligatory prayers have all begun).
    private(set) var tomorrowFajrBegin: Date?

    let hijriEngine = HijriDateEngine()

    // MARK: - Configuration

    var latitude: Double {
        get { UserDefaults.standard.double(forKey: AppSettings.latitudeKey).nonZero ?? AppSettings.defaultLatitude }
        set { UserDefaults.standard.set(newValue, forKey: AppSettings.latitudeKey); recalculate() }
    }

    var longitude: Double {
        get { UserDefaults.standard.double(forKey: AppSettings.longitudeKey).nonZero ?? AppSettings.defaultLongitude }
        set { UserDefaults.standard.set(newValue, forKey: AppSettings.longitudeKey); recalculate() }
    }

    var locationName: String {
        get { UserDefaults.standard.string(forKey: AppSettings.locationNameKey) ?? AppSettings.defaultLocationName }
        set { UserDefaults.standard.set(newValue, forKey: AppSettings.locationNameKey) }
    }

    var calculationMethodId: String {
        get { UserDefaults.standard.string(forKey: AppSettings.calculationMethodKey) ?? AppSettings.defaultCalculationMethod }
        set { UserDefaults.standard.set(newValue, forKey: AppSettings.calculationMethodKey); recalculate() }
    }

    var madhabId: String {
        get { UserDefaults.standard.string(forKey: AppSettings.madhabKey) ?? AppSettings.defaultMadhab }
        set { UserDefaults.standard.set(newValue, forKey: AppSettings.madhabKey); recalculate() }
    }

    // MARK: - Mosque Integration

    var mosqueGuid: String? {
        get { UserDefaults.standard.string(forKey: AppSettings.mosqueGuidKey) ?? AppSettings.defaultMosqueGuid }
        set { UserDefaults.standard.set(newValue, forKey: AppSettings.mosqueGuidKey) }
    }

    var mosqueName: String? {
        get { UserDefaults.standard.string(forKey: AppSettings.mosqueNameKey) }
        set { UserDefaults.standard.set(newValue, forKey: AppSettings.mosqueNameKey) }
    }

    private var mosqueCache: MosqueCacheManager?

    // MARK: - Lifecycle

    func configure(mosqueCache: MosqueCacheManager? = nil) {
        self.mosqueCache = mosqueCache
        recalculate()
        hijriEngine.update()
    }

    /// Called every second by the menu bar timer to refresh next-prayer tracking.
    func tick() {
        updateNextPrayer()
    }

    /// Full recalculation of today's prayer times.
    func recalculate() {
        let coords = Coordinates(latitude: latitude, longitude: longitude)
        let cal = Calendar(identifier: .gregorian)
        let dateComponents = cal.dateComponents([.year, .month, .day], from: Date())

        var params = resolveCalculationMethod().params
        params.madhab = madhabId == "hanafi" ? .hanafi : .shafi

        guard let prayers = PrayerTimes(coordinates: coords, date: dateComponents, calculationParameters: params) else {
            lastError = "Failed to calculate prayer times"
            todayEntries = []
            nextPrayer = nil
            tomorrowFajrBegin = nil
            return
        }

        lastError = nil

        let calculatedTomorrowFajr = Self.tomorrowFajrDate(
            coordinates: coords,
            calendar: cal,
            calculationParameters: params
        )
        if let guid = mosqueGuid,
           let tomorrowDate = cal.date(byAdding: .day, value: 1, to: Date()),
           let mosqueTomorrow = mosqueCache?.dayCache(guid: guid, for: tomorrowDate),
           let mosqueFajr = mosqueTomorrow.beginDate(for: .fajr) {
            tomorrowFajrBegin = mosqueFajr
        } else {
            tomorrowFajrBegin = calculatedTomorrowFajr
        }

        // Build entries — prefer mosque begin times over calculated times when available
        let mosqueDay: PrayerDay? = {
            guard let guid = mosqueGuid else { return nil }
            return mosqueCache?.todayCache(guid: guid)
        }()

        let calculatedTimes: [(PrayerName, Date)] = [
            (.fajr, prayers.fajr), (.sunrise, prayers.sunrise), (.dhuhr, prayers.dhuhr),
            (.asr, prayers.asr), (.maghrib, prayers.maghrib), (.isha, prayers.isha),
        ]

        let entries: [PrayerTimeEntry] = calculatedTimes.map { prayer, calculated in
            // Use mosque begin time if available, fall back to calculated
            let adhanTime = mosqueDay?.beginDate(for: prayer) ?? calculated
            var entry = PrayerTimeEntry(prayer: prayer, adhanTime: adhanTime)
            entry.iqamahTime = mosqueDay?.iqamahDate(for: prayer)
            return entry
        }

        todayEntries = entries
        updateNextPrayer()
        hijriEngine.update()
    }

    // MARK: - Calculation Method Resolution

    private func resolveCalculationMethod() -> CalculationMethod {
        switch calculationMethodId {
        case "muslimWorldLeague":     return .muslimWorldLeague
        case "egyptian":              return .egyptian
        case "karachi":               return .karachi
        case "ummAlQura":             return .ummAlQura
        case "dubai":                 return .dubai
        case "qatar":                 return .qatar
        case "kuwait":                return .kuwait
        case "moonsightingCommittee": return .moonsightingCommittee
        case "singapore":             return .singapore
        case "northAmerica":          return .northAmerica
        case "other":                 return .other
        default:                      return .moonsightingCommittee
        }
    }

    /// All available calculation methods for the settings UI.
    static let availableCalculationMethods: [(id: String, name: String)] = [
        ("moonsightingCommittee", "Moonsighting Committee"),
        ("muslimWorldLeague", "Muslim World League"),
        ("egyptian", "Egyptian General Authority"),
        ("karachi", "University of Islamic Sciences, Karachi"),
        ("ummAlQura", "Umm al-Qura University, Makkah"),
        ("dubai", "Dubai"),
        ("qatar", "Qatar"),
        ("kuwait", "Kuwait"),
        ("singapore", "Singapore"),
        ("northAmerica", "ISNA (North America)"),
    ]

    static let availableMadhabs: [(id: String, name: String)] = [
        ("shafi", "Shafi'i / Maliki / Hanbali"),
        ("hanafi", "Hanafi"),
    ]

    // MARK: - Mosque API

    /// Fetch mosque times from my-masjid.com and cache them.
    func fetchMosqueTimes() async {
        guard let guid = mosqueGuid, !guid.isEmpty else { return }

        let client = MosqueAPIClient()
        do {
            let (name, timings) = try await client.fetchTimings(guid: guid)
            mosqueName = name
            if mosqueCache?.cacheTimings(timings, mosqueName: name, guid: guid) == false {
                lastError = "Could not save mosque times locally."
            } else {
                lastError = nil
            }
            recalculate()
        } catch {
            lastError = "Mosque API: \(error.localizedDescription)"
        }
    }

    /// Set mosque from a my-masjid.com URL.
    func setMosqueFromURL(_ urlString: String) async -> Bool {
        guard let guid = MosqueAPIClient.extractGUID(from: urlString) else {
            lastError = "Could not extract mosque ID from URL"
            return false
        }
        mosqueGuid = guid
        await fetchMosqueTimes()
        return lastError == nil
    }

    // MARK: - Friday / Ramadan

    /// Whether today is Friday (Jumu'ah).
    var isFriday: Bool { Date().isFriday }

    /// Whether we are currently in Ramadan.
    var isRamadan: Bool { Date().isRamadan }

    /// Jumu'ah time from mosque cache (if available).
    var jummahTime: String? {
        guard let guid = mosqueGuid,
              let cached = mosqueCache?.todayCache(guid: guid) else { return nil }
        return cached.jummah1
    }

    // MARK: - Private

    private func updateNextPrayer() {
        // Find the current prayer (most recent one that has passed)
        let passed = todayEntries.filter { $0.hasPassed && $0.prayer != .sunrise }
        currentPrayerName = passed.last?.prayer

        // Next slot today (includes Sunrise between Fajr and Dhuhr), else tomorrow's Fajr.
        let future = todayEntries.filter { $0.isFuture }
        if let nextToday = future.first {
            nextPrayer = nextToday
        } else if let tf = tomorrowFajrBegin {
            nextPrayer = PrayerTimeEntry(prayer: .fajr, adhanTime: tf, idSuffix: "nextDay")
        } else {
            nextPrayer = nil
        }
    }

    private static func tomorrowFajrDate(
        coordinates: Coordinates,
        calendar: Calendar,
        calculationParameters: CalculationParameters
    ) -> Date? {
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) else { return nil }
        let dc = calendar.dateComponents([.year, .month, .day], from: tomorrow)
        guard let dayPrayers = PrayerTimes(coordinates: coordinates, date: dc, calculationParameters: calculationParameters) else {
            return nil
        }
        return dayPrayers.fajr
    }
}

// MARK: - Double Extension

private extension Double {
    var nonZero: Double? {
        self == 0 ? nil : self
    }
}
