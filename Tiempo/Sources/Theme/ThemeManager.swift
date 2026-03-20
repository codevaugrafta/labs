import SwiftUI
import AppKit
import Observation

// MARK: - Theme Schedule Rule

struct ThemeScheduleRule: Codable, Sendable {
    let themeId: String
    let startHour: Int   // 0-23
    let endHour: Int     // 0-23 (exclusive)
}

// MARK: - Theme Manager

@MainActor
@Observable
final class ThemeManager {
    static let shared = ThemeManager()

    // WORKAROUND: `any TiempoTheme` existential defeats @Observable KeyPath tracking.
    // SwiftUI never re-renders when `current` changes because the observation system
    // can't track mutations to existential-typed properties reliably.
    // Solution: keep `current` for internal use, but expose a concrete `themeVersion` Int
    // that views observe. Bump it on every theme change.
    private(set) var current: any TiempoTheme = StandardTheme()

    /// Concrete stored property that SwiftUI CAN observe. Increments on every theme change.
    private(set) var themeVersion: Int = 0

    // Resolved theme colors as concrete stored properties for SwiftUI observation
    private(set) var background: Color = Color(.windowBackgroundColor)
    private(set) var surface: Color = Color(.controlBackgroundColor)
    private(set) var surfaceHover: Color = Color(.selectedContentBackgroundColor).opacity(0.1)
    private(set) var border: Color = Color(.separatorColor)
    private(set) var accent: Color = Color.accentColor
    private(set) var textPrimary: Color = Color(.labelColor)
    private(set) var textSecondary: Color = Color(.secondaryLabelColor)
    private(set) var textTertiary: Color = Color(.tertiaryLabelColor)
    private(set) var destructive: Color = Color(.systemRed)
    private(set) var success: Color = Color(.systemGreen)
    private(set) var cornerRadius: CGFloat = 8
    private(set) var tileCornerRadius: CGFloat = 8
    private(set) var springResponse: Double = 0.5
    private(set) var springDamping: Double = 0.7
    private(set) var timerPulseSpeed: Double = 2.0
    private(set) var timerText: Color = Color(.labelColor)
    private(set) var timerFont: Font = Font.system(size: 28, weight: .medium, design: .monospaced)
    private(set) var headingFont: Font = Font.system(size: 22, weight: .bold)
    private(set) var labelFont: Font = Font.system(size: 11, weight: .medium)
    private(set) var labelLetterSpacing: CGFloat = 0.5
    private(set) var usesCustomLayout: Bool = false

    private enum FeedbackKeys {
        static let sound = "tiempoFeedbackSoundEnabled"
        static let haptic = "tiempoFeedbackHapticEnabled"
    }

    /// User preference: timer/theme sounds (`NSSound`). Default on when unset.
    var feedbackSoundEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: FeedbackKeys.sound) == nil { return true }
            return UserDefaults.standard.bool(forKey: FeedbackKeys.sound)
        }
        set { UserDefaults.standard.set(newValue, forKey: FeedbackKeys.sound) }
    }

    /// User preference: haptics (NSHapticFeedbackManager). Default on when unset.
    var feedbackHapticEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: FeedbackKeys.haptic) == nil { return true }
            return UserDefaults.standard.bool(forKey: FeedbackKeys.haptic)
        }
        set { UserDefaults.standard.set(newValue, forKey: FeedbackKeys.haptic) }
    }

    var autoScheduleEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "themeAutoSchedule") }
        set {
            UserDefaults.standard.set(newValue, forKey: "themeAutoSchedule")
            if newValue { applySchedule() }
        }
    }

    var selectedThemeId: String {
        get {
            let raw = UserDefaults.standard.string(forKey: "selectedThemeId") ?? "standard"
            return raw == "signature" ? "standard-dark" : raw
        }
        set {
            let id = newValue == "signature" ? "standard-dark" : newValue
            UserDefaults.standard.set(id, forKey: "selectedThemeId")
            if !autoScheduleEnabled {
                applyTheme(theme(for: id))
            }
        }
    }

    var scheduleRules: [ThemeScheduleRule] {
        get {
            guard let data = UserDefaults.standard.data(forKey: "themeScheduleRules"),
                  let rules = try? JSONDecoder().decode([ThemeScheduleRule].self, from: data)
            else { return Self.defaultSchedule }
            return rules
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            UserDefaults.standard.set(data, forKey: "themeScheduleRules")
            if autoScheduleEnabled { applySchedule() }
        }
    }

    // MARK: All available themes

    static let allThemes: [any TiempoTheme] = [
        StandardTheme(),
        StandardDarkTheme()
    ]

    struct ThemeEntry: Identifiable {
        let id: String
        let name: String
        let accent: Color
    }

    static let themeEntries: [ThemeEntry] = allThemes.map {
        ThemeEntry(id: $0.id, name: $0.displayName, accent: $0.accent)
    }

    static let defaultSchedule: [ThemeScheduleRule] = [
        ThemeScheduleRule(themeId: "standard", startHour: 6, endHour: 18),
        ThemeScheduleRule(themeId: "standard-dark", startHour: 18, endHour: 22),
        ThemeScheduleRule(themeId: "standard-dark", startHour: 22, endHour: 6)
    ]

    // MARK: - Sound retention (prevent ARC dealloc before playback completes)
    private var currentSound: NSSound?

    // MARK: Init

    private init() {
        if UserDefaults.standard.string(forKey: "selectedThemeId") == "signature" {
            UserDefaults.standard.set("standard-dark", forKey: "selectedThemeId")
        }
        let t: any TiempoTheme
        if autoScheduleEnabled {
            t = resolveScheduledTheme()
        } else {
            t = theme(for: selectedThemeId)
        }
        applyTheme(t)
    }

    // MARK: - Public

    func cycleTheme() {
        let ids = Self.allThemes.map(\.id)
        guard let idx = ids.firstIndex(of: current.id) else { return }
        let nextIdx = (idx + 1) % ids.count
        selectedThemeId = ids[nextIdx]
        applyTheme(Self.allThemes[nextIdx])
        if feedbackHapticEnabled { playHaptic(.levelChange) }
    }

    func setTheme(_ id: String) {
        selectedThemeId = id
        applyTheme(theme(for: id))
        if feedbackHapticEnabled { playHaptic(.levelChange) }
    }

    func applySchedule() {
        applyTheme(resolveScheduledTheme())
    }

    // MARK: - Feedback

    func playStartFeedback() {
        if feedbackHapticEnabled && current.hapticOnStart {
            // Stronger than `.generic` so timer taps register on supported trackpads.
            playHaptic(.levelChange)
        }
        if feedbackSoundEnabled { playSound(current.startSound) }
    }

    func playStopFeedback() {
        if feedbackHapticEnabled && current.hapticOnStop {
            playHaptic(.alignment)
            playHaptic(.generic)
        }
        if feedbackSoundEnabled { playSound(current.stopSound) }
    }

    func playCompleteFeedback() {
        if feedbackHapticEnabled { playHaptic(.levelChange) }
        if feedbackSoundEnabled { playSound(current.completeSound) }
    }

    // MARK: - Private

    /// Resolves all concrete observable properties from a theme.
    /// This is the key fix: bumping `themeVersion` and setting concrete Color/CGFloat
    /// properties ensures SwiftUI re-renders views that read these.
    private func applyTheme(_ t: any TiempoTheme) {
        current = t
        background = t.background
        surface = t.surface
        surfaceHover = t.surfaceHover
        border = t.border
        accent = t.accent
        textPrimary = t.textPrimary
        textSecondary = t.textSecondary
        textTertiary = t.textTertiary
        timerText = t.timerText
        destructive = t.destructive
        success = t.success
        cornerRadius = t.cornerRadius
        tileCornerRadius = t.tileCornerRadius
        springResponse = t.springResponse
        springDamping = t.springDamping
        timerPulseSpeed = t.timerPulseSpeed
        timerFont = t.timerFont
        headingFont = t.headingFont
        labelFont = t.labelFont
        labelLetterSpacing = t.labelLetterSpacing
        usesCustomLayout = t.usesCustomLayout
        themeVersion += 1

        // Force window appearance for dark themes
        applyWindowAppearance(t.forcedAppearance)
    }

    private func applyWindowAppearance(_ appearance: String?) {
        let nsAppearance: NSAppearance?
        switch appearance {
        case "dark":
            nsAppearance = NSAppearance(named: .darkAqua)
        case "light":
            nsAppearance = NSAppearance(named: .aqua)
        default:
            nsAppearance = nil // Follow system
        }
        // Apply to all windows
        for window in NSApplication.shared.windows {
            window.appearance = nsAppearance
        }
        NSApplication.shared.appearance = nsAppearance
    }

    private func resolveScheduledTheme() -> any TiempoTheme {
        let hour = Calendar.current.component(.hour, from: Date())
        for rule in scheduleRules {
            if rule.startHour <= rule.endHour {
                if hour >= rule.startHour && hour < rule.endHour {
                    return theme(for: rule.themeId)
                }
            } else {
                if hour >= rule.startHour || hour < rule.endHour {
                    return theme(for: rule.themeId)
                }
            }
        }
        return theme(for: selectedThemeId)
    }

    private func theme(for id: String) -> any TiempoTheme {
        if id == "signature" { return StandardDarkTheme() }
        return Self.allThemes.first { $0.id == id } ?? StandardTheme()
    }

    private func playHaptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .default)
    }

    /// Loads macOS system `.aiff` sounds. `NSSound(named:)` often fails for SwiftPM apps; file URLs are reliable.
    private static let systemSoundsDirectory = URL(fileURLWithPath: "/System/Library/Sounds", isDirectory: true)

    private func playSound(_ name: String?) {
        guard feedbackSoundEnabled, let name, !name.isEmpty else { return }
        currentSound?.stop()

        let fileURL = Self.systemSoundsDirectory.appendingPathComponent("\(name).aiff", isDirectory: false)
        if let sound = NSSound(contentsOf: fileURL, byReference: true) {
            sound.volume = 1.0
            currentSound = sound
            sound.play()
            return
        }

        if let sound = NSSound(named: NSSound.Name(name)) {
            sound.volume = 1.0
            currentSound = sound
            sound.play()
            return
        }

        NSSound.beep()
    }
}
