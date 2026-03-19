import Testing
import Foundation
@testable import Tiempo

@Suite("Category Model")
struct CategoryTests {

    @Test("Category initializes with correct defaults")
    func categoryDefaults() {
        let category = Category(name: "Work", color: "#4A90D9")

        #expect(category.name == "Work")
        #expect(category.color == "#4A90D9")
        #expect(category.icon == nil)
        #expect(category.parentId == nil)
        #expect(!category.isArchived)
        #expect(category.sortOrder == 0)
        #expect(category.syncStatus == .pendingCreate)
        #expect(category.deletedAt == nil)
    }

    @Test("Category stores custom color and icon")
    func categoryCustomFields() {
        let category = Category(name: "Exercise", color: "#2ECC71", icon: "figure.run")

        #expect(category.color == "#2ECC71")
        #expect(category.icon == "figure.run")
    }
}
