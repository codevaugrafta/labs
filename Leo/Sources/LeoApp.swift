import SwiftUI
import SwiftData
import Darwin

extension Notification.Name {
    static let leoImportBook = Notification.Name("leoImportBook")
    static let leoImportAnki = Notification.Name("leoImportAnki")
    /// Broadcast after an Anki import completes. `object` is a `String` summary message.
    static let leoAnkiImportResult = Notification.Name("leoAnkiImportResult")
    /// `object` is the PDF `Book`'s `UUID`; main window runs conversion.
    static let leoRequestPDFConvert = Notification.Name("leoRequestPDFConvert")
    /// Posted by the Coordinator after OpenRouter enriches a word lookup.
    /// `userInfo`: ["word": String, "context": String]
    static let leoContextualDefinitionReady = Notification.Name("leoContextualDefinitionReady")
}

@main
struct LeoApp: App {
    let runtime: LeoRuntime
    let modelContainer: ModelContainer

    init() {
        NSLog("[Leo] App starting...")
        LeoSecretMigrator.migrateLegacyDefaults()

        let runtime = LeoRuntime()
        self.runtime = runtime
        runtime.startEmbeddedReader()

        let schema = Schema([
            Book.self,
            VocabularyEntry.self,
            FSRSCard.self,
            ReadingSessionRecord.self,
        ])
        let config = ModelConfiguration("Leo", schema: schema, url: runtime.storeURL)
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [config])
            secureStoreFiles(at: runtime.storeURL)
            NSLog("[Leo] ModelContainer created successfully")
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(runtime)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .modelContainer(modelContainer)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Import Book...") {
                    NotificationCenter.default.post(name: .leoImportBook, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(after: .importExport) {
                Button("Import Anki Deck…") {
                    NotificationCenter.default.post(name: .leoImportAnki, object: nil)
                }
            }
        }

        Settings {
            SettingsView()
        }
        .modelContainer(modelContainer)
    }

    private func secureStoreFiles(at storeURL: URL) {
        let base = storeURL.path
        for path in [base, base + "-wal", base + "-shm"] where FileManager.default.fileExists(atPath: path) {
            chmod(path, 0o600)
        }
    }
}
