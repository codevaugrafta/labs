import Foundation
import SwiftData

/// Fetches mosque prayer times from my-masjid.com REST API.
/// API: /api/TimingsInfoScreen/GetMasjidTimings?GuidId={guid}
actor MosqueAPIClient {
    private let session: URLSession
    private let baseURL = "https://time.my-masjid.com/api/TimingsInfoScreen/GetMasjidTimings"

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Fetch all prayer times for a mosque. Returns mosque name + full year of timings.
    func fetchTimings(guid: String) async throws -> (mosqueName: String, timings: [MyMasjidTiming]) {
        guard let url = URL(string: "\(baseURL)?GuidId=\(guid)") else {
            throw MosqueAPIError.invalidGUID
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MosqueAPIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw MosqueAPIError.httpError(httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(MyMasjidResponse.self, from: data)
        let name = decoded.model.masjidDetails?.name ?? "Unknown Mosque"
        let timings = decoded.model.salahTimings ?? []

        guard !timings.isEmpty else {
            throw MosqueAPIError.noData
        }

        return (name, timings)
    }

    /// Extract a GUID from a my-masjid.com URL or raw GUID string.
    static func extractGUID(from urlString: String) -> String? {
        let uuidPattern = #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#
        if let range = urlString.range(of: uuidPattern, options: .regularExpression) {
            return String(urlString[range])
        }
        return nil
    }
}

// MARK: - Errors

enum MosqueAPIError: LocalizedError, Sendable {
    case invalidGUID
    case invalidResponse
    case httpError(Int)
    case noData

    var errorDescription: String? {
        switch self {
        case .invalidGUID: return "Invalid mosque GUID"
        case .invalidResponse: return "Invalid response from my-masjid.com"
        case .httpError(let code): return "HTTP error \(code) from my-masjid.com"
        case .noData: return "No prayer time data available"
        }
    }
}

// MARK: - Cache Manager

@MainActor
final class MosqueCacheManager {
    private var modelContext: ModelContext?

    func configure(with context: ModelContext) {
        self.modelContext = context
    }

    /// Save fetched timings to SwiftData cache. Returns `false` if save failed.
    @discardableResult
    func cacheTimings(_ timings: [MyMasjidTiming], mosqueName: String, guid: String) -> Bool {
        guard let modelContext else { return false }

        for timing in timings {
            guard let date = timing.parsedDate() else { continue }

            let startOfDay = Calendar.current.startOfDay(for: date)
            let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
            let descriptor = FetchDescriptor<PrayerDay>(
                predicate: #Predicate { $0.date >= startOfDay && $0.date < endOfDay && $0.mosqueGuid == guid }
            )

            let day: PrayerDay
            if let existing = try? modelContext.fetch(descriptor).first {
                day = existing
            } else {
                day = PrayerDay(date: startOfDay, mosqueName: mosqueName, mosqueGuid: guid)
                modelContext.insert(day)
            }

            // Begin times
            day.fajrBegins = timing.fajr
            day.sunrise = timing.shouruq
            day.dhuhrBegins = timing.zuhr
            day.asrBegins = timing.asr
            day.maghribBegins = timing.maghrib
            day.ishaBegins = timing.isha

            // Iqamah (congregation) times — API keys iqamah_*
            day.fajrJamaah = timing.iqamahFajr
            day.dhuhrJamaah = timing.iqamahZuhr
            day.asrJamaah = timing.iqamahAsr
            day.maghribJamaah = timing.iqamahMaghrib
            day.ishaJamaah = timing.iqamahIsha

            day.updatedAt = Date()
        }

        do {
            try modelContext.save()
            return true
        } catch {
            AdhanLog.data.error("SwiftData save failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Get cached prayer times for today.
    func todayCache(guid: String) -> PrayerDay? {
        dayCache(guid: guid, for: Date())
    }

    /// Cached mosque day for the Gregorian day containing `referenceDate` (used for tomorrow Fajr after Isha).
    func dayCache(guid: String, for referenceDate: Date) -> PrayerDay? {
        guard let modelContext else { return nil }
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: referenceDate)
        let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay)!
        let descriptor = FetchDescriptor<PrayerDay>(
            predicate: #Predicate { $0.date >= startOfDay && $0.date < endOfDay && $0.mosqueGuid == guid }
        )
        return try? modelContext.fetch(descriptor).first
    }
}
