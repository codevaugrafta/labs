import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            ReadingSettingsTab()
                .tabItem {
                    Label("Reading", systemImage: "book")
                }
        }
        .frame(width: 450, height: 300)
    }
}

struct GeneralSettingsTab: View {
    var body: some View {
        Form {
            Text("Leo Settings")
                .font(.headline)
            Text("Settings will be expanded as features are added.")
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

struct ReadingSettingsTab: View {
    var body: some View {
        Form {
            Text("Reading Preferences")
                .font(.headline)
            Text("Font, theme, and layout options coming soon.")
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
