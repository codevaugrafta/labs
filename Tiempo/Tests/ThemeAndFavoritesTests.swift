import Testing
import Foundation
import SwiftData
@testable import Tiempo

@Suite("Theme & Favorites")
struct ThemeAndFavoritesTests {

    @MainActor
    private func makeEngine() throws -> (TimeEntryEngine, ModelContext) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Category.self, TimeEntry.self, Tag.self,
            ScheduleTemplate.self, ScheduledBlock.self, Goal.self,
            configurations: config
        )
        let context = ModelContext(container)
        let engine = TimeEntryEngine()
        engine.configure(with: context)
        return (engine, context)
    }

    // MARK: - Favorites

    @Test("Toggle favorite on a category")
    @MainActor
    func toggleFavorite() throws {
        let (engine, context) = try makeEngine()
        let category = Category(name: "Work", color: "#4A90D9")
        context.insert(category)
        try context.save()

        #expect(!category.isFavorite)
        engine.toggleFavorite(category)
        #expect(category.isFavorite)
        engine.toggleFavorite(category)
        #expect(!category.isFavorite)
    }

    @Test("favoriteCategories returns only favorites, excluding archived/deleted")
    @MainActor
    func favoriteCategoriesFiltering() throws {
        let (engine, context) = try makeEngine()

        let work = Category(name: "Work", color: "#4A90D9")
        work.isFavorite = true
        let exercise = Category(name: "Exercise", color: "#2ECC71")
        exercise.isFavorite = true
        let archived = Category(name: "Old", color: "#888")
        archived.isFavorite = true
        archived.isArchived = true
        let deleted = Category(name: "Gone", color: "#999")
        deleted.isFavorite = true
        deleted.deletedAt = Date()
        let notFav = Category(name: "Study", color: "#F39C12")

        for cat in [work, exercise, archived, deleted, notFav] {
            context.insert(cat)
        }
        try context.save()

        let favorites = engine.favoriteCategories
        #expect(favorites.count == 2)
        let names = Set(favorites.map(\.name))
        #expect(names.contains("Work"))
        #expect(names.contains("Exercise"))
    }

    // MARK: - Theme Engine

    @Test("All 3 themes are available")
    @MainActor
    func allThemesAvailable() {
        let themes = ThemeManager.allThemes
        #expect(themes.count == 3)
        let ids = Set(themes.map(\.id))
        #expect(ids.contains("standard"))
        #expect(ids.contains("standard-dark"))
        #expect(ids.contains("signature"))
    }

    @Test("ThemeManager cycles through themes")
    @MainActor
    func cycleTheme() {
        let manager = ThemeManager.shared
        let startId = manager.current.id
        manager.cycleTheme()
        #expect(manager.current.id != startId)
        // Cycle back to start
        manager.cycleTheme()
        manager.cycleTheme()
        #expect(manager.current.id == startId)
    }

    @Test("setTheme changes current theme")
    @MainActor
    func setTheme() {
        let manager = ThemeManager.shared
        manager.setTheme("signature")
        #expect(manager.current.id == "signature")
        manager.setTheme("standard-dark")
        #expect(manager.current.id == "standard-dark")
        // Reset to standard for other tests
        manager.setTheme("standard")
    }

    @Test("Theme entries match available themes")
    @MainActor
    func themeEntries() {
        let entries = ThemeManager.themeEntries
        #expect(entries.count == 3)
        #expect(entries[0].id == "standard")
        #expect(entries[1].id == "standard-dark")
        #expect(entries[2].id == "signature")
    }

    @Test("Signature theme has custom layout and dark appearance")
    @MainActor
    func signatureThemeProperties() {
        let sig = SignatureTheme()
        let std = StandardTheme()

        #expect(sig.usesCustomLayout == true)
        #expect(std.usesCustomLayout == false)
        #expect(sig.forcedAppearance == "dark")
        #expect(std.forcedAppearance == nil)
        #expect(sig.timerPulseSpeed > std.timerPulseSpeed) // Slower breathing
    }

    @Test("Default schedule covers 24 hours")
    @MainActor
    func scheduleCovers24h() {
        let schedule = ThemeManager.defaultSchedule
        // Verify all 24 hours are covered
        for hour in 0..<24 {
            let matched = schedule.contains { rule in
                if rule.startHour <= rule.endHour {
                    return hour >= rule.startHour && hour < rule.endHour
                } else {
                    return hour >= rule.startHour || hour < rule.endHour
                }
            }
            #expect(matched, "Hour \(hour) not covered by schedule")
        }
    }

    // MARK: - ScheduledBlock durationMinutes (regression)

    @Test("durationMinutes still clamped to 0 for inverted times")
    @MainActor
    func durationMinutesRegression() throws {
        let cal = Calendar.current
        let startTime = cal.date(bySettingHour: 14, minute: 0, second: 0, of: Date())!
        let endTime = cal.date(bySettingHour: 10, minute: 0, second: 0, of: Date())!

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Category.self, TimeEntry.self, Tag.self,
            ScheduleTemplate.self, ScheduledBlock.self, Goal.self,
            configurations: config
        )
        let context = ModelContext(container)
        let category = Category(name: "Work", color: "#4A90D9")
        context.insert(category)

        let block = ScheduledBlock(
            category: category, weekStart: Date(), dayOfWeek: 1,
            startTime: startTime, endTime: endTime
        )
        context.insert(block)
        #expect(block.durationMinutes == 0)
    }
}
