import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        TabView {
            TrackingView()
                .tabItem {
                    Label("Tracking", systemImage: "timer")
                }

            ScheduleView()
                .tabItem {
                    Label("Schedule", systemImage: "calendar")
                }

            EventsView()
                .tabItem {
                    Label("Events", systemImage: "list.bullet.clipboard")
                }

            TimelineView()
                .tabItem {
                    Label("Timeline", systemImage: "chart.bar.xaxis")
                }

            GoalsView()
                .tabItem {
                    Label("Goals", systemImage: "target")
                }
        }
        .frame(minWidth: 700, minHeight: 500)
        .background(ThemeManager.shared.background)
        .animation(.easeInOut(duration: 0.4), value: ThemeManager.shared.themeVersion)
    }
}

