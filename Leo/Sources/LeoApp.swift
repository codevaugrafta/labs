import SwiftUI
import SwiftData

@main
struct LeoApp: App {
    let modelContainer: ModelContainer

    init() {
        let schema = Schema([
            Book.self,
            VocabularyEntry.self,
            FSRSCard.self,
            ReadingSessionRecord.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)

        Settings {
            SettingsView()
        }
    }
}
