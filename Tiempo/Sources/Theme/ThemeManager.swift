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

    private(set) var current: any TiempoTheme = NativeTheme()

    var autoScheduleEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "themeAutoSchedule") }
        set {
            UserDefaults.standard.set(newValue, forKey: "themeAutoSchedule")
            if newValue { applySchedule() }
        }
    }

    var selectedThemeId: String {
        get { UserDefaults.standard.string(forKey: "selectedThemeId") ?? "native" }
        set {
            UserDefaults.standard.set(newValue, forKey: "selectedThemeId")
            if !autoScheduleEnabled {
                current = theme(for: newValue)
            }
        }
    }

    /// Schedule rules stored as JSON in UserDefaults
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
        NativeTheme(),
        ZenTheme(),
        WarmLuxuryTheme(),
        BoldEditorialTheme()
    ]

    /// Lightweight value type for ForEach compatibility (avoids protocol existential issues)
    struct ThemeEntry: Identifiable {
        let id: String
        let name: String
        let accent: Color
    }

    static let themeEntries: [ThemeEntry] = allThemes.map {
        ThemeEntry(id: $0.id, name: $0.displayName, accent: $0.accent)
    }

    static let defaultSchedule: [ThemeScheduleRule] = [
        ThemeScheduleRule(themeId: "native", startHour: 6, endHour: 9),      // Morning: Native
        ThemeScheduleRule(themeId: "bold-editorial", startHour: 9, endHour: 17), // Work: Editorial
        ThemeScheduleRule(themeId: "zen", startHour: 17, endHour: 21),       // Evening: Zen
        ThemeScheduleRule(themeId: "warm-luxury", startHour: 21, endHour: 6) // Night: Luxury
    ]

    // MARK: Init

    private init() {
        if autoScheduleEnabled {
            applySchedule()
        } else {
            current = theme(for: selectedThemeId)
        }
    }

    // MARK: - Public

    func cycleTheme() {
        let ids = Self.allThemes.map(\.id)
        guard let idx = ids.firstIndex(of: current.id) else { return }
        let nextIdx = (idx + 1) % ids.count
        selectedThemeId = ids[nextIdx]
        current = Self.allThemes[nextIdx]
        playHaptic(.levelChange)
    }

    func setTheme(_ id: String) {
        selectedThemeId = id
        current = theme(for: id)
        playHaptic(.levelChange)
    }

    func applySchedule() {
        let hour = Calendar.current.component(.hour, from: Date())
        for rule in scheduleRules {
            if rule.startHour <= rule.endHour {
                // Same-day range (e.g., 9-17)
                if hour >= rule.startHour && hour < rule.endHour {
                    current = theme(for: rule.themeId)
                    return
                }
            } else {
                // Wraps midnight (e.g., 21-6)
                if hour >= rule.startHour || hour < rule.endHour {
                    current = theme(for: rule.themeId)
                    return
                }
            }
        }
        // Fallback
        current = theme(for: selectedThemeId)
    }

    // MARK: - Feedback

    func playStartFeedback() {
        if current.hapticOnStart { playHaptic(.generic) }
        playSound(current.startSound)
    }

    func playStopFeedback() {
        if current.hapticOnStop { playHaptic(.alignment) }
        playSound(current.stopSound)
    }

    func playCompleteFeedback() {
        playHaptic(.levelChange)
        playSound(current.completeSound)
    }

    // MARK: - Private

    private func theme(for id: String) -> any TiempoTheme {
        Self.allThemes.first { $0.id == id } ?? NativeTheme()
    }

    private func playHaptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .default)
    }

    private func playSound(_ name: String?) {
        guard let name, let sound = NSSound(named: name) else { return }
        sound.play()
    }
}
