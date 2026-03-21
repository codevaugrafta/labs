import AppKit
import Darwin
import SwiftData
import SwiftUI

@main
struct LoveApp: App {
    @NSApplicationDelegateAdaptor(LoveAppDelegate.self) var appDelegate
    @State private var engine = LoveEngine()

    static let modelContainer: ModelContainer = {
        LoveDataMigration.migrateLegacyApplicationSupportIfNeeded()

        let schema = Schema([
            TaskSection.self,
            MustDoItem.self,
            CaptureCategory.self,
            LaterCapture.self
        ])
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Love", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let storeURL = dir.appendingPathComponent("Love.store")
        let config = ModelConfiguration("Love", schema: schema, url: storeURL)

        defer {
            let path = storeURL.path
            if FileManager.default.fileExists(atPath: path) {
                chmod(path, 0o600)
                chmod(path + "-wal", 0o600)
                chmod(path + "-shm", 0o600)
            }
        }

        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Failed to create Love database: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            AppBootstrapView(engine: engine, appDelegate: appDelegate)
                .frame(minWidth: 520, minHeight: 480)
        }
        .modelContainer(Self.modelContainer)
        .defaultSize(width: 640, height: 560)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Quick capture") {
                    NotificationCenter.default.post(name: .loveQuickCapture, object: nil)
                }
                .keyboardShortcut("l", modifiers: [.control, .option])
            }
        }

        Settings {
            LoveSettingsView()
        }
    }
}

struct AppBootstrapView: View {
    @Environment(\.modelContext) private var modelContext
    let engine: LoveEngine
    let appDelegate: LoveAppDelegate

    var body: some View {
        ContentView(engine: engine)
            .onAppear {
                engine.configure(with: modelContext)
                appDelegate.wireUp(engine: engine, modelContainer: LoveApp.modelContainer)
            }
    }
}
