import Foundation

/// Metadata for an Adhan audio recitation (bundled or custom).
struct AdhanRecitation: Identifiable, Sendable, Codable {
    let id: String
    let displayName: String
    let filename: String       // e.g., "makkah-adhan.m4a"
    let durationSeconds: Int   // approximate
    let isBundled: Bool
    let isForFajr: Bool        // Fajr-specific recitation

    /// All bundled recitations.
    static let bundled: [AdhanRecitation] = [
        AdhanRecitation(
            id: "makkah",
            displayName: "Makkah (Masjid al-Haram)",
            filename: "makkah-adhan.m4a",
            durationSeconds: 210,
            isBundled: true,
            isForFajr: false
        ),
        AdhanRecitation(
            id: "madinah",
            displayName: "Madinah (Masjid an-Nabawi)",
            filename: "madinah-adhan.m4a",
            durationSeconds: 195,
            isBundled: true,
            isForFajr: false
        ),
        AdhanRecitation(
            id: "mishary",
            displayName: "Mishary Rashid Alafasy",
            filename: "mishary-adhan.m4a",
            durationSeconds: 225,
            isBundled: true,
            isForFajr: false
        ),
        AdhanRecitation(
            id: "fajr-special",
            displayName: "Fajr Adhan (Traditional)",
            filename: "fajr-special.m4a",
            durationSeconds: 240,
            isBundled: true,
            isForFajr: true
        ),
    ]

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
    static let defaultRecitation = bundled.first { $0.id == "makkah" }!

    /// Default recitation for Fajr.
    static let defaultFajrRecitation = bundled.first { $0.isForFajr }!

    /// Resolve a bundled recitation from UserDefaults id, falling back to defaults if missing or unknown.
    static func resolveBundled(storedId: String?, forFajr: Bool) -> AdhanRecitation {
        let fallbackId = forFajr ? "fajr-special" : "makkah"
        let id = storedId ?? fallbackId
        if let match = bundled.first(where: { $0.id == id }) {
            return match
        }
        AdhanLog.player.warning("Unknown recitation id '\(id, privacy: .public)'; using default")
        return forFajr ? defaultFajrRecitation : defaultRecitation
    }
}
