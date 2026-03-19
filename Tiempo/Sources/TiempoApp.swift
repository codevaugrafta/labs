import SwiftUI
import SwiftData

@main
struct TiempoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Category.self, TimeEntry.self])
    }
}
