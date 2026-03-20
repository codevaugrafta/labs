import SwiftUI
import ServiceManagement
import UserNotifications
import AppKit

struct SettingsView: View {
    @Environment(PrayerTimesEngine.self) private var engine
    @Environment(\.adhanPlayer) private var adhanPlayer
    @Environment(\.openURL) private var openURL
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var mosqueURLInput = ""
    @State private var isFetchingMosque = false
    @State private var fetchStatus = ""
    @State private var notificationStatusSummary = "Checking…"
    @AppStorage(AppSettings.mainWindowTextSizeKey) private var mainWindowTextSize: Int = 1
    @AppStorage(AppSettings.adhanVolumeKey) private var adhanVolumeStorage: Double = Double(AppSettings.defaultVolume)

    var body: some View {
        TabView {
            locationTab
                .tabItem { Label("Location", systemImage: "location") }
            calculationTab
                .tabItem { Label("Calculation", systemImage: "function") }
            mosqueTab
                .tabItem { Label("Mosque", systemImage: "building.columns") }
            audioTab
                .tabItem { Label("Audio", systemImage: "speaker.wave.3") }
            generalTab
                .tabItem { Label("General", systemImage: "gear") }
        }
        .frame(width: 520, height: 480)
        .task {
            await refreshNotificationAuthorizationSummary()
            migrateRecitationKeysToCanonicalIds()
        }
    }

    /// One-time normalize so SwiftUI Pickers match `UserDefaults` after legacy ids.
    private func migrateRecitationKeysToCanonicalIds() {
        let d = AdhanRecitation.canonicalBundledStoredId(
            UserDefaults.standard.string(forKey: AppSettings.defaultRecitationKey),
            forFajr: false
        )
        if UserDefaults.standard.string(forKey: AppSettings.defaultRecitationKey) != d {
            UserDefaults.standard.set(d, forKey: AppSettings.defaultRecitationKey)
        }
        let f = AdhanRecitation.canonicalBundledStoredId(
            UserDefaults.standard.string(forKey: AppSettings.fajrRecitationKey),
            forFajr: true
        )
        if UserDefaults.standard.string(forKey: AppSettings.fajrRecitationKey) != f {
            UserDefaults.standard.set(f, forKey: AppSettings.fajrRecitationKey)
        }
    }

    // MARK: - Location Tab

    private var locationTab: some View {
        Form {
            Section("Location") {
                HStack {
                    Text("City")
                    Spacer()
                    TextField("City name", text: Binding(
                        get: { engine.locationName },
                        set: { engine.locationName = $0 }
                    ))
                    .frame(width: 200)
                    .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Text("Latitude")
                    Spacer()
                    TextField("55.6761", value: Binding(
                        get: { engine.latitude },
                        set: { engine.latitude = $0 }
                    ), format: .number.precision(.fractionLength(4)))
                    .frame(width: 120)
                    .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Text("Longitude")
                    Spacer()
                    TextField("12.5683", value: Binding(
                        get: { engine.longitude },
                        set: { engine.longitude = $0 }
                    ), format: .number.precision(.fractionLength(4)))
                    .frame(width: 120)
                    .textFieldStyle(.roundedBorder)
                }
            }

            Section {
                Text("Copenhagen, Denmark: 55.6761\u{00B0}N, 12.5683\u{00B0}E")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Calculation Tab

    private var calculationTab: some View {
        Form {
            Section("Calculation Method") {
                Picker("Method", selection: Binding(
                    get: { engine.calculationMethodId },
                    set: { engine.calculationMethodId = $0 }
                )) {
                    ForEach(PrayerTimesEngine.availableCalculationMethods, id: \.id) { method in
                        Text(method.name).tag(method.id)
                    }
                }

                Text("Moonsighting Committee is recommended for high-latitude locations like Copenhagen (55.67\u{00B0}N).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Madhab (Asr Calculation)") {
                Picker("Madhab", selection: Binding(
                    get: { engine.madhabId },
                    set: { engine.madhabId = $0 }
                )) {
                    ForEach(PrayerTimesEngine.availableMadhabs, id: \.id) { madhab in
                        Text(madhab.name).tag(madhab.id)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Mosque Tab

    private var mosqueTab: some View {
        Form {
            Section("Mosque (my-masjid.com)") {
                if let name = engine.mosqueName {
                    HStack {
                        Image(systemName: "building.columns.fill")
                            .foregroundStyle(.secondary)
                        Text(name)
                            .font(.headline)
                    }
                }

                HStack {
                    TextField("Paste my-masjid.com URL or GUID", text: $mosqueURLInput)
                        .textFieldStyle(.roundedBorder)

                    Button(isFetchingMosque ? "Fetching..." : "Connect") {
                        connectMosque()
                    }
                    .disabled(mosqueURLInput.isEmpty || isFetchingMosque)
                }

                if !fetchStatus.isEmpty {
                    Text(fetchStatus)
                        .font(.caption)
                        .foregroundStyle(fetchStatus.contains("Error") ? .red : .green)
                }

                if engine.mosqueGuid != nil {
                    Button("Disconnect Mosque") {
                        engine.mosqueGuid = nil
                        engine.mosqueName = nil
                        engine.recalculate()
                        fetchStatus = ""
                    }
                    .foregroundStyle(.red)
                }
            }

            Section {
                Text("Paste your mosque’s my-masjid.com timing URL to load begin (Adhan) and Iqamah times from the same source.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Example: https://time.my-masjid.com/timingscreen/85966a2e-4c6d-48fa-9aa8-c29d1052e51c")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
    }

    private func connectMosque() {
        isFetchingMosque = true
        fetchStatus = ""

        Task {
            let success = await engine.setMosqueFromURL(mosqueURLInput)
            isFetchingMosque = false
            if success {
                fetchStatus = "Connected to \(engine.mosqueName ?? "mosque")"
                mosqueURLInput = ""
            } else {
                fetchStatus = "Error: \(engine.lastError ?? "Failed to connect")"
            }
        }
    }

    // MARK: - Audio Tab

    private var audioTab: some View {
        Form {
            Section("Adhan Recitation") {
                Picker("Default Adhan", selection: Binding(
                    get: {
                        AdhanRecitation.canonicalBundledStoredId(
                            UserDefaults.standard.string(forKey: AppSettings.defaultRecitationKey),
                            forFajr: false
                        )
                    },
                    set: { UserDefaults.standard.set($0, forKey: AppSettings.defaultRecitationKey) }
                )) {
                    ForEach(AdhanRecitation.bundled.filter { !$0.isForFajr }, id: \.id) { rec in
                        Text(rec.displayName).tag(rec.id)
                    }
                }

                Picker("Fajr Adhan", selection: Binding(
                    get: {
                        AdhanRecitation.canonicalBundledStoredId(
                            UserDefaults.standard.string(forKey: AppSettings.fajrRecitationKey),
                            forFajr: true
                        )
                    },
                    set: { UserDefaults.standard.set($0, forKey: AppSettings.fajrRecitationKey) }
                )) {
                    ForEach(AdhanRecitation.bundled, id: \.id) { rec in
                        Text(rec.displayName).tag(rec.id)
                    }
                }
            }

            Section("Volume") {
                HStack {
                    Text("Adhan volume")
                    Spacer()
                    Text("\(Int(adhanVolumeStorage * 100))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: Binding(
                    get: { adhanVolumeStorage },
                    set: { newValue in
                        adhanVolumeStorage = newValue
                        adhanPlayer?.volume = Float(newValue)
                    }
                ), in: 0...1) {
                    Text("Adhan Volume")
                }

                HStack {
                    Button("Preview default Adhan") {
                        let stored = UserDefaults.standard.string(forKey: AppSettings.defaultRecitationKey)
                        let rec = AdhanRecitation.resolveBundled(storedId: stored, forFajr: false)
                        adhanPlayer?.play(recitation: rec)
                    }
                    .disabled(adhanPlayer == nil)

                    Button("Preview Fajr Adhan") {
                        let stored = UserDefaults.standard.string(forKey: AppSettings.fajrRecitationKey)
                        let rec = AdhanRecitation.resolveBundled(storedId: stored, forFajr: true)
                        adhanPlayer?.play(recitation: rec)
                    }
                    .disabled(adhanPlayer == nil)
                }

                if let url = Bundle.main.url(forResource: "ATTRIBUTION", withExtension: "md", subdirectory: "Audio") {
                    Button("Show audio credits (ATTRIBUTION.md)…") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }

                Text("Independent of system volume. Bundled Adhan is CC BY-SA 4.0 — credits live inside the app: Adhan.app → Contents → Resources → Audio → ATTRIBUTION.md.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Reminders") {
                Picker("Pre-reminder", selection: Binding(
                    get: { UserDefaults.standard.object(forKey: AppSettings.preReminderMinutesKey) as? Int ?? AppSettings.defaultPreReminderMinutes },
                    set: { UserDefaults.standard.set($0, forKey: AppSettings.preReminderMinutesKey) }
                )) {
                    Text("5 minutes before").tag(5)
                    Text("10 minutes before").tag(10)
                    Text("15 minutes before").tag(15)
                    Text("20 minutes before").tag(20)
                    Text("30 minutes before").tag(30)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = !newValue
                        }
                    }
            }

            Section("Menu Bar") {
                Picker("Display Mode", selection: Binding(
                    get: {
                        MenuBarDisplayMode(rawValue: UserDefaults.standard.integer(forKey: AppSettings.menuBarDisplayModeKey)) ?? .countdown
                    },
                    set: {
                        UserDefaults.standard.set($0.rawValue, forKey: AppSettings.menuBarDisplayModeKey)
                    }
                )) {
                    ForEach(MenuBarDisplayMode.allCases, id: \.rawValue) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
            }

            Section("Main window") {
                Picker("Text size", selection: Binding(
                    get: { min(max(mainWindowTextSize, 0), 3) },
                    set: { mainWindowTextSize = $0 }
                )) {
                    Text("Smaller").tag(0)
                    Text("Default").tag(1)
                    Text("Larger").tag(2)
                    Text("Largest").tag(3)
                }
                Text("Resizes relative text in the main prayer window. Drag the window edge to resize the window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Notifications") {
                Text(notificationStatusSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Open Notification Settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                        openURL(url)
                    }
                }
            }

            Section("Theme") {
                Picker("Theme", selection: Binding(
                    get: { AdhanThemeManager.shared.selectedThemeId },
                    set: { AdhanThemeManager.shared.setTheme($0) }
                )) {
                    ForEach(AdhanThemeManager.themeEntries) { entry in
                        Text(entry.name).tag(entry.id)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    @MainActor
    private func refreshNotificationAuthorizationSummary() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        notificationStatusSummary = Self.summary(for: settings.authorizationStatus)
    }

    private static func summary(for status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return "macOS allows alerts for Adhan. Banners may still be suppressed by Focus or per-notification settings."
        case .denied:
            return "Notifications are denied for Adhan. Enable them in System Settings so scheduled prayer alerts can appear."
        case .notDetermined:
            return "Permission not decided yet — Adhan will request access when it schedules alerts."
        @unknown default:
            return "Notification permission state could not be read."
        }
    }
}
