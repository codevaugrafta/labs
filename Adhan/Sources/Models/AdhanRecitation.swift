import Foundation

/// Metadata for an Adhan audio recitation (bundled or custom).
struct AdhanRecitation: Identifiable, Sendable, Codable {
    let id: String
    let displayName: String
    let filename: String       // e.g., "community-adhan-wikimedia.m4a"
    let durationSeconds: Int   // approximate
    let isBundled: Bool
    let isForFajr: Bool        // Fajr-specific recitation

    /// All bundled recitations — **honest labels** for shipped open-license audio (see `Resources/Audio/ATTRIBUTION.md`).
    /// Legacy UserDefaults ids (`makkah`, `madinah`, …) still resolve via `resolveBundled`.
    static let bundled: [AdhanRecitation] = [
        AdhanRecitation(
            id: "wikimedia-andrewler",
            displayName: "Community Adhan (Wikimedia, CC BY-SA 4.0)",
            filename: "community-adhan-wikimedia.m4a",
            durationSeconds: 183,
            isBundled: true,
            isForFajr: false
        ),
        AdhanRecitation(
            id: "wikimedia-andrewler-fajr",
            displayName: "Fajr — same community recording",
            filename: "community-adhan-wikimedia.m4a",
            durationSeconds: 183,
            isBundled: true,
            isForFajr: true
        ),
    ]

    /// Older builds stored misleading ids; map them to the shipped open-license track.
    private static let legacyBundledIdAliases: [String: String] = [
        "makkah": "wikimedia-andrewler",
        "madinah": "wikimedia-andrewler",
        "mishary": "wikimedia-andrewler",
        "fajr-special": "wikimedia-andrewler-fajr",
    ]

    /// Canonical id for Settings pickers and `UserDefaults` (migrates legacy stored values).
    static func canonicalBundledStoredId(_ stored: String?, forFajr: Bool) -> String {
        let fallback = forFajr ? "wikimedia-andrewler-fajr" : "wikimedia-andrewler"
        let raw: String = {
            guard let s = stored, !s.isEmpty else { return fallback }
            return s
        }()
        let mapped = legacyBundledIdAliases[raw] ?? raw
        if bundled.contains(where: { $0.id == mapped }) {
            return mapped
        }
        return fallback
    }

    /// System sound used for pre-reminders.
    static let gentleChime = AdhanRecitation(
        id: "gentle-chime",
        displayName: "Gentle Chime",
        filename: "gentle-chime.m4a",
        durationSeconds: 5,
        isBundled: true,
        isForFajr: false
    )

    /// Default recitation for regular prayers.
    static let defaultRecitation = bundled.first { $0.id == "wikimedia-andrewler" }!

    /// Default recitation for Fajr.
    static let defaultFajrRecitation = bundled.first { $0.id == "wikimedia-andrewler-fajr" }!

    /// Resolve a bundled recitation from UserDefaults id, falling back to defaults if missing or unknown.
    static func resolveBundled(storedId: String?, forFajr: Bool) -> AdhanRecitation {
        let id = canonicalBundledStoredId(storedId, forFajr: forFajr)
        if let match = bundled.first(where: { $0.id == id }) {
            return match
        }
        AdhanLog.player.warning("Unknown recitation id '\(storedId ?? "nil", privacy: .public)'; using default")
        return forFajr ? defaultFajrRecitation : defaultRecitation
    }
}
