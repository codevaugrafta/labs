import SwiftUI
import SwiftData

extension Notification.Name {
    static let leoImportBook = Notification.Name("leoImportBook")
}

@main
struct LeoApp: App {
    let modelContainer: ModelContainer

    init() {
        NSLog("[Leo] App starting...")

        // Start localhost server for foliate-js
        // Search for web resources in multiple locations
        let searchPaths = [
            Bundle.main.resourceURL?.appendingPathComponent("web").path,
            Bundle.main.resourceURL?.appendingPathComponent("Leo_Leo.bundle/web").path,
            Bundle.main.bundlePath + "/Contents/Resources/web",
            Bundle.main.bundlePath + "/Contents/Resources/Leo_Leo.bundle/web",
            // Development fallback
            (Bundle.main.bundlePath + "/../../Sources/Resources/web" as NSString).standardizingPath,
            "Sources/Resources/web",
        ].compactMap { $0 } as [String]

        var foundWebPath = false
        for path in searchPaths {
            if FileManager.default.fileExists(atPath: path + "/reader.html") {
                NSLog("[Leo] Found web resources at: \(path)")
                LocalServer.shared.start(webResourcesPath: path)
                foundWebPath = true
                break
            }
        }
        if !foundWebPath {
            NSLog("[Leo] WARNING: Could not find web resources. Searched: \(searchPaths)")
        }

        let schema = Schema([
            Book.self,
            VocabularyEntry.self,
            FSRSCard.self,
            ReadingSessionRecord.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [config])
            NSLog("[Leo] ModelContainer created successfully")
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Import Book...") {
                    NotificationCenter.default.post(name: .leoImportBook, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
        }
    }
}
