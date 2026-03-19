import SwiftUI
import SwiftData

struct ContentView: View {
    private let tm = ThemeManager.shared

    var body: some View {
        Group {
            if tm.usesCustomLayout {
                SignatureContentView()
            } else {
                StandardContentView()
            }
        }
        .animation(.easeInOut(duration: 0.4), value: tm.themeVersion)
    }
}

/// Standard layout — system TabView
struct StandardContentView: View {
    var body: some View {
        TabView {
            TrackingView()
                .tabItem { Label("Tracking", systemImage: "timer") }
            ScheduleView()
                .tabItem { Label("Schedule", systemImage: "calendar") }
            EventsView()
                .tabItem { Label("Events", systemImage: "list.bullet.clipboard") }
            TimelineView()
                .tabItem { Label("Timeline", systemImage: "chart.bar.xaxis") }
            GoalsView()
                .tabItem { Label("Goals", systemImage: "target") }
        }
        .frame(minWidth: 700, minHeight: 500)
    }
}
