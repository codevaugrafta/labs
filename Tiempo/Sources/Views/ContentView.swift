import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        TabView {
            TrackingView()
                .tabItem {
                    Label("Tracking", systemImage: "timer")
                }

            PlaceholderTab(title: "Schedule", icon: "calendar")
                .tabItem {
                    Label("Schedule", systemImage: "calendar")
                }

            EventsView()
                .tabItem {
                    Label("Events", systemImage: "list.bullet.clipboard")
                }

            PlaceholderTab(title: "Timeline", icon: "chart.bar.xaxis")
                .tabItem {
                    Label("Timeline", systemImage: "chart.bar.xaxis")
                }

            PlaceholderTab(title: "Goals", icon: "target")
                .tabItem {
                    Label("Goals", systemImage: "target")
                }

            PlaceholderTab(title: "Settings", icon: "gear")
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .frame(minWidth: 700, minHeight: 500)
    }
}

struct PlaceholderTab: View {
    let title: String
    let icon: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Coming soon")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
