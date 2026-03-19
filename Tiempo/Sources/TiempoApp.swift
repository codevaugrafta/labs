import SwiftUI
import SwiftData

@main
struct TiempoApp: App {
    @State private var engine = TimeEntryEngine()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(engine)
        }
        .modelContainer(for: [Category.self, TimeEntry.self])
    }
}
