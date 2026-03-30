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
    static let leoToggleTOC = Notification.Name("leoToggleTOC")
    static let leoTogglePinyin = Notification.Name("leoTogglePinyin")
    static let leoToggleSearch = Notification.Name("leoToggleSearch")
    /// Posted by floating action button to open the library sidebar.
    static let leoShowLibrary = Notification.Name("leoShowLibrary")
    /// Posted by floating action button to open the vocabulary sheet.
    static let leoShowVocabulary = Notification.Name("leoShowVocabulary")
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
            // Navigation
            CommandGroup(after: .toolbar) {
                Button("Toggle Sidebar") {
                    // macOS standard sidebar toggle
                    NSApp.keyWindow?.firstResponder?.tryToPerform(
                        #selector(NSSplitViewController.toggleSidebar(_:)),
                        with: nil
                    )
                }
                .keyboardShortcut("s", modifiers: [.command, .control])

                Button("Toggle Table of Contents") {
                    NotificationCenter.default.post(name: .leoToggleTOC, object: nil)
                }
                .keyboardShortcut("t", modifiers: .command)
            }
            // Reading
            CommandGroup(after: .textEditing) {
                Button("Toggle Pinyin") {
                    NotificationCenter.default.post(name: .leoTogglePinyin, object: nil)
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Button("Find in Book") {
                    NotificationCenter.default.post(name: .leoToggleSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
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
