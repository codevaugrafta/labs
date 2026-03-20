import Testing
import Foundation
@testable import Tiempo

/// Regression: Plan mode uses `dayOfWeek` 0=Sun…6=Sat with Monday `weekStart`; Compare must use the same calendar date.
@Suite("Schedule calendar mapping")
struct ScheduleCalendarMappingTests {

    @Test("dayOffsetFromWeekMonday maps UI day index to correct weekday for a Monday anchor")
    @MainActor
    func dayOffsetMatchesCalendarWeekday() throws {
        let cal = Calendar.current
        var comps = DateComponents()
        comps.year = 2025
        comps.month = 3
        comps.day = 10
        let monday = try #require(cal.date(from: comps))
        #expect(cal.component(.weekday, from: monday) == 2) // Monday

        for dayIdx in 0..<7 {
            let offset = ScheduleView.dayOffsetFromWeekMonday(selectedDayIndex: dayIdx)
            let date = try #require(cal.date(byAdding: .day, value: offset, to: monday))
            let uiIdx = cal.component(.weekday, from: date) - 1
            #expect(uiIdx == dayIdx)
        }
    }

    @Test("Old bug: adding raw selectedDay to Monday shifted Compare one day for Mon–Sat")
    @MainActor
    func rawAddWasWrongForMonday() throws {
        let cal = Calendar.current
        var comps = DateComponents()
        comps.year = 2025
        comps.month = 3
        comps.day = 10
        let monday = try #require(cal.date(from: comps))
        let wrongTuesday = try #require(cal.date(byAdding: .day, value: 1, to: monday))
        let correctMonday = try #require(cal.date(byAdding: .day, value: 0, to: monday))
        #expect(ScheduleView.dayOffsetFromWeekMonday(selectedDayIndex: 1) == 0)
        let fixed = try #require(cal.date(byAdding: .day, value: ScheduleView.dayOffsetFromWeekMonday(selectedDayIndex: 1), to: monday))
        #expect(fixed == correctMonday)
        #expect(fixed != wrongTuesday)
    }
}
