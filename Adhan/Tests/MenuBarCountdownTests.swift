import Foundation
import Testing
@testable import AdhanApp

@Suite("Menu bar Iqamah countdown")
struct MenuBarCountdownTests {

    @Test("Between Adhan and Iqamah, menu bar focuses pseudo Iqamah entry when skip is off")
    func iqamahPhaseWhenSkipOff() {
        let cal = Calendar(identifier: .gregorian)
        var c = DateComponents()
        c.year = 2026
        c.month = 3
        c.day = 20
        c.hour = 12
        c.minute = 0
        c.second = 0
        guard let noon = cal.date(from: c) else {
            Issue.record("Could not build anchor date")
            return
        }
        let adhan = cal.date(byAdding: .minute, value: -10, to: noon)!
        let iqamah = cal.date(byAdding: .minute, value: 25, to: noon)!
        let asrBegin = cal.date(byAdding: .hour, value: 3, to: noon)!

        var dhuhr = PrayerTimeEntry(prayer: .dhuhr, adhanTime: adhan)
        dhuhr.iqamahTime = iqamah
        let asr = PrayerTimeEntry(prayer: .asr, adhanTime: asrBegin)

        let focus = PrayerTimesEngine.menuBarCountdownEntry(
            todayEntries: [dhuhr, asr],
            nextPrayer: asr,
            skipIqamahCountdown: false,
            now: noon
        )

        #expect(focus?.isMenuBarIqamahPhase == true)
        #expect(focus?.prayer == .dhuhr)
        #expect(focus?.adhanTime == iqamah)
    }

    @Test("Skip flag uses next prayer begin only")
    func skipIqamahUsesNextBegin() {
        let cal = Calendar(identifier: .gregorian)
        var c = DateComponents()
        c.year = 2026
        c.month = 3
        c.day = 20
        c.hour = 12
        c.minute = 0
        guard let noon = cal.date(from: c) else {
            Issue.record("Could not build anchor date")
            return
        }
        let adhan = cal.date(byAdding: .minute, value: -5, to: noon)!
        let iqamah = cal.date(byAdding: .minute, value: 20, to: noon)!
        let asrBegin = cal.date(byAdding: .hour, value: 3, to: noon)!

        var dhuhr = PrayerTimeEntry(prayer: .dhuhr, adhanTime: adhan)
        dhuhr.iqamahTime = iqamah
        let asr = PrayerTimeEntry(prayer: .asr, adhanTime: asrBegin)

        let focus = PrayerTimesEngine.menuBarCountdownEntry(
            todayEntries: [dhuhr, asr],
            nextPrayer: asr,
            skipIqamahCountdown: true,
            now: noon
        )

        #expect(focus?.id == asr.id)
        #expect(focus?.isMenuBarIqamahPhase == false)
    }

    @Test("Two overlapping Iqamah windows pick sooner congregation time")
    func twoEligiblePicksSoonerIqamah() {
        let cal = Calendar(identifier: .gregorian)
        var c = DateComponents()
        c.year = 2026
        c.month = 3
        c.day = 20
        c.hour = 12
        c.minute = 0
        guard let noon = cal.date(from: c) else {
            Issue.record("Could not build anchor date")
            return
        }
        let dhuhrAdhan = cal.date(byAdding: .minute, value: -90, to: noon)!
        let dhuhrIqamah = cal.date(byAdding: .minute, value: 40, to: noon)!
        let asrAdhan = cal.date(byAdding: .minute, value: -20, to: noon)!
        let asrIqamah = cal.date(byAdding: .minute, value: 15, to: noon)!
        let maghribBegin = cal.date(byAdding: .hour, value: 4, to: noon)!

        var dhuhr = PrayerTimeEntry(prayer: .dhuhr, adhanTime: dhuhrAdhan)
        dhuhr.iqamahTime = dhuhrIqamah
        var asr = PrayerTimeEntry(prayer: .asr, adhanTime: asrAdhan)
        asr.iqamahTime = asrIqamah
        let maghrib = PrayerTimeEntry(prayer: .maghrib, adhanTime: maghribBegin)

        let focus = PrayerTimesEngine.menuBarCountdownEntry(
            todayEntries: [dhuhr, asr, maghrib],
            nextPrayer: maghrib,
            skipIqamahCountdown: false,
            now: noon
        )

        #expect(focus?.prayer == .asr)
        #expect(focus?.adhanTime == asrIqamah)
    }

    @Test("No Iqamah data falls back to next prayer")
    func noIqamahFallsBack() {
        let cal = Calendar(identifier: .gregorian)
        var c = DateComponents()
        c.year = 2026
        c.month = 3
        c.day = 20
        c.hour = 12
        c.minute = 0
        guard let noon = cal.date(from: c) else {
            Issue.record("Could not build anchor date")
            return
        }
        let adhan = cal.date(byAdding: .minute, value: -5, to: noon)!
        let asrBegin = cal.date(byAdding: .hour, value: 3, to: noon)!

        var dhuhr = PrayerTimeEntry(prayer: .dhuhr, adhanTime: adhan)
        dhuhr.iqamahTime = nil
        let asr = PrayerTimeEntry(prayer: .asr, adhanTime: asrBegin)

        let focus = PrayerTimesEngine.menuBarCountdownEntry(
            todayEntries: [dhuhr, asr],
            nextPrayer: asr,
            skipIqamahCountdown: false,
            now: noon
        )

        #expect(focus?.id == asr.id)
    }
}
