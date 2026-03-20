import SwiftUI
import AppKit
import Observation

@MainActor
@Observable
final class AdhanThemeManager {
    static let shared = AdhanThemeManager()

    private(set) var current: any AdhanTheme = EmeraldTheme()
    private(set) var themeVersion: Int = 0

    // Resolved concrete properties for SwiftUI observation
    private(set) var background: Color = Color.black
    private(set) var surface: Color = Color.black
    private(set) var surfaceHover: Color = Color.black
    private(set) var border: Color = Color.clear
    private(set) var accent: Color = Color.green
    private(set) var accentSecondary: Color = Color.yellow
    private(set) var textPrimary: Color = Color.white
    private(set) var textSecondary: Color = Color.gray
    private(set) var textTertiary: Color = Color.gray.opacity(0.5)
    private(set) var prayerHighlight: Color = Color.green
    private(set) var destructive: Color = Color.red
    private(set) var success: Color = Color.green
    private(set) var cornerRadius: CGFloat = 12
    private(set) var springResponse: Double = 0.5
    private(set) var springDamping: Double = 0.7
    private(set) var pulseSpeed: Double = 2.5
    private(set) var showsGeometricPattern: Bool = true
    private(set) var patternOpacity: Double = 0.04

    var selectedThemeId: String {
        get { UserDefaults.standard.string(forKey: AppSettings.selectedThemeKey) ?? "emerald" }
        set {
            UserDefaults.standard.set(newValue, forKey: AppSettings.selectedThemeKey)
            applyTheme(theme(for: newValue))
        }
    }

    // MARK: All Themes

    static let allThemes: [any AdhanTheme] = [
        EmeraldTheme(),
        MidnightTheme(),
        RamadanTheme()
    ]

    struct ThemeEntry: Identifiable {
        let id: String
        let name: String
        let accent: Color
    }

    static let themeEntries: [ThemeEntry] = allThemes.map {
        ThemeEntry(id: $0.id, name: $0.displayName, accent: $0.accent)
    }

    private var currentSound: NSSound?

    // MARK: Init

    private init() {
        // Auto-switch to Ramadan theme during Ramadan
        if Date().isRamadan && selectedThemeId != "ramadan" {
            applyTheme(theme(for: "ramadan"))
        } else {
            applyTheme(theme(for: selectedThemeId))
        }
    }

    /// Check and auto-apply Ramadan theme if in Ramadan.
    func checkRamadanAutoSwitch() {
        if Date().isRamadan && current.id != "ramadan" {
            selectedThemeId = "ramadan"
        }
    }

    // MARK: - Public

    func cycleTheme() {
        let ids = Self.allThemes.map(\.id)
        guard let idx = ids.firstIndex(of: current.id) else { return }
        let nextIdx = (idx + 1) % ids.count
        selectedThemeId = ids[nextIdx]
        playHaptic(.levelChange)
    }

    func setTheme(_ id: String) {
        selectedThemeId = id
        playHaptic(.levelChange)
    }

    func color(for prayer: PrayerName) -> Color {
        current.color(for: prayer)
    }

    // MARK: - Feedback

    func playPrayerFeedback() {
        if current.hapticOnPrayer { playHaptic(.generic) }
        playSound(current.transitionSound)
    }

    func playTransitionFeedback() {
        playHaptic(.levelChange)
        playSound(current.transitionSound)
    }

    // MARK: - Private

    private func applyTheme(_ t: any AdhanTheme) {
        current = t
        background = t.background
        surface = t.surface
        surfaceHover = t.surfaceHover
        border = t.border
        accent = t.accent
        accentSecondary = t.accentSecondary
        textPrimary = t.textPrimary
        textSecondary = t.textSecondary
        textTertiary = t.textTertiary
        prayerHighlight = t.prayerHighlight
        destructive = t.destructive
        success = t.success
        cornerRadius = t.cornerRadius
        springResponse = t.springResponse
        springDamping = t.springDamping
        pulseSpeed = t.pulseSpeed
        showsGeometricPattern = t.showsGeometricPattern
        patternOpacity = t.patternOpacity
        themeVersion += 1

        applyWindowAppearance(t.forcedAppearance)
    }

    private func applyWindowAppearance(_ appearance: String?) {
        let nsAppearance: NSAppearance?
        switch appearance {
        case "dark":  nsAppearance = NSAppearance(named: .darkAqua)
        case "light": nsAppearance = NSAppearance(named: .aqua)
        default:      nsAppearance = nil
        }
        for window in NSApplication.shared.windows {
            window.appearance = nsAppearance
        }
        NSApplication.shared.appearance = nsAppearance
    }

    private func theme(for id: String) -> any AdhanTheme {
        Self.allThemes.first { $0.id == id } ?? EmeraldTheme()
    }

    private func playHaptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .default)
    }

    private func playSound(_ name: String?) {
        guard let name, let sound = NSSound(named: name) else { return }
        currentSound?.stop()
        currentSound = sound
        currentSound?.play()
    }
}
