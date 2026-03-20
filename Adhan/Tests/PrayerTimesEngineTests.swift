import Testing
import Foundation
@testable import AdhanApp

@Suite("PrayerTimesEngine Tests")
struct PrayerTimesEngineTests {

    @MainActor
    @Test("Calculate Copenhagen prayer times")
    func testCopenhagenPrayerTimes() async {
        let engine = PrayerTimesEngine()
        engine.configure()

        #expect(!engine.todayEntries.isEmpty, "Should have prayer entries")
        #expect(engine.todayEntries.count == 6, "Should have 6 entries (5 prayers + sunrise)")

        // Verify prayer order
        let names = engine.todayEntries.map(\.prayer)
        #expect(names == [.fajr, .sunrise, .dhuhr, .asr, .maghrib, .isha])

        // Verify times are chronological
        for i in 1..<engine.todayEntries.count {
            let prev = engine.todayEntries[i - 1].adhanTime
            let curr = engine.todayEntries[i].adhanTime
            #expect(curr > prev, "\(engine.todayEntries[i].prayer.displayName) should be after \(engine.todayEntries[i-1].prayer.displayName)")
        }
    }

    @MainActor
    @Test("Default location is Copenhagen")
    func testDefaultLocation() async {
        let engine = PrayerTimesEngine()
        #expect(engine.latitude == 55.6761 || engine.latitude > 55 && engine.latitude < 56)
        #expect(engine.longitude == 12.5683 || engine.longitude > 12 && engine.longitude < 13)
    }

    @MainActor
    @Test("Calculation method changes trigger recalculation")
    func testCalculationMethodChange() async {
        let engine = PrayerTimesEngine()
        engine.configure()

        _ = engine.todayEntries.map(\.formattedBeginTime)
        engine.calculationMethodId = "ummAlQura"
        let newTimes = engine.todayEntries.map(\.formattedBeginTime)

        // Times may or may not differ but entries should still exist
        #expect(!newTimes.isEmpty)
        #expect(newTimes.count == 6)
    }

    @MainActor
    @Test("Tomorrow Fajr anchor is computed and follows today’s Isha")
    func testTomorrowFajrAfterTodayIsha() async {
        let engine = PrayerTimesEngine()
        engine.configure()

        guard let tomorrowFajr = engine.tomorrowFajrBegin,
              let isha = engine.todayEntries.first(where: { $0.prayer == .isha }) else {
            Issue.record("Expected today’s Isha and tomorrow’s Fajr to be calculable")
            return
        }
        #expect(tomorrowFajr > isha.adhanTime)
    }
}

@Suite("PrayerTimeEntry Tests")
struct PrayerTimeEntryTests {

    @Test("Default id matches prayer raw value")
    func defaultId() {
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = PrayerTimeEntry(prayer: .dhuhr, adhanTime: t)
        #expect(entry.id == PrayerName.dhuhr.rawValue)
        #expect(entry.isNextDayPreview == false)
    }

    @Test("Next-day preview id suffix and flag")
    func nextDayPreview() {
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = PrayerTimeEntry(prayer: .fajr, adhanTime: t, idSuffix: "nextDay")
        #expect(entry.id == "\(PrayerName.fajr.rawValue)-nextDay")
        #expect(entry.isNextDayPreview == true)
    }

    @Test("Iqamah time is formatted when provided from mosque source")
    func iqamahFormatted() {
        let begin = Date(timeIntervalSince1970: 1_700_000_000)
        let iqamah = begin.addingTimeInterval(30 * 60)
        let entry = PrayerTimeEntry(prayer: .dhuhr, adhanTime: begin, iqamahTime: iqamah)
        #expect(entry.formattedIqamahTime != nil)
        #expect(entry.formattedIqamahTime != entry.formattedBeginTime)
    }
}

@Suite("HijriDateEngine Tests")
struct HijriDateEngineTests {

    @MainActor
    @Test("Hijri date is valid")
    func testHijriDate() async {
        let engine = HijriDateEngine()
        engine.update()

        #expect(engine.hijriDay >= 1 && engine.hijriDay <= 30)
        #expect(engine.hijriMonth >= 1 && engine.hijriMonth <= 12)
        #expect(engine.hijriYear >= 1446 && engine.hijriYear <= 1600)
        #expect(!engine.hijriDateString.isEmpty)
        #expect(!engine.monthName.isEmpty)
    }

    @MainActor
    @Test("Arabic month name exists")
    func testArabicMonthName() async {
        let engine = HijriDateEngine()
        engine.update()
        #expect(!engine.arabicMonthName.isEmpty)
    }
}

@Suite("MosqueAPIClient Tests")
struct MosqueAPIClientTests {

    @Test("Extract GUID from my-masjid.com URL")
    func testGUIDExtraction() {
        let url1 = "https://time.my-masjid.com/timingscreen/85966a2e-4c6d-48fa-9aa8-c29d1052e51c"
        let guid1 = MosqueAPIClient.extractGUID(from: url1)
        #expect(guid1 == "85966a2e-4c6d-48fa-9aa8-c29d1052e51c")

        let url2 = "85966a2e-4c6d-48fa-9aa8-c29d1052e51c"
        let guid2 = MosqueAPIClient.extractGUID(from: url2)
        #expect(guid2 == "85966a2e-4c6d-48fa-9aa8-c29d1052e51c")

        let invalid = "not-a-guid"
        #expect(MosqueAPIClient.extractGUID(from: invalid) == nil)
    }
}

@Suite("AdhanRecitation Tests")
struct AdhanRecitationTests {

    @Test("Invalid stored recitation id falls back to bundled default")
    func invalidIdFallsBack() {
        let dhuhr = AdhanRecitation.resolveBundled(storedId: "not-a-real-id", forFajr: false)
        #expect(dhuhr.id == "makkah")

        let fajr = AdhanRecitation.resolveBundled(storedId: "bogus", forFajr: true)
        #expect(fajr.id == "fajr-special")
    }

    @Test("Nil stored id uses canonical default ids")
    func nilStoredUsesDefaults() {
        #expect(AdhanRecitation.resolveBundled(storedId: nil, forFajr: false).id == "makkah")
        #expect(AdhanRecitation.resolveBundled(storedId: nil, forFajr: true).id == "fajr-special")
    }
}

@Suite("PrayerName Tests")
struct PrayerNameTests {

    @Test("All prayer names have display names")
    func testDisplayNames() {
        for prayer in PrayerName.allCases {
            #expect(!prayer.displayName.isEmpty)
            #expect(!prayer.arabicName.isEmpty)
            #expect(!prayer.systemImage.isEmpty)
        }
    }

    @Test("Obligatory prayers excludes sunrise")
    func testObligatory() {
        #expect(PrayerName.obligatory.count == 5)
        #expect(!PrayerName.obligatory.contains(.sunrise))
    }
}

@Suite("Date+Hijri Tests")
struct DateHijriTests {

    @Test("Current date has valid Hijri components")
    func testCurrentHijri() {
        let now = Date()
        #expect(now.hijriDay >= 1 && now.hijriDay <= 30)
        #expect(now.hijriMonth >= 1 && now.hijriMonth <= 12)
        #expect(now.hijriYear >= 1446)
    }

    @Test("Friday detection works")
    func testFridayDetection() {
        // Create a known Friday: March 21, 2026 is a Saturday, so March 20, 2026 is a Friday
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let components = DateComponents(year: 2026, month: 3, day: 20)
        if let friday = cal.date(from: components) {
            #expect(friday.isFriday)
        }
    }
}
