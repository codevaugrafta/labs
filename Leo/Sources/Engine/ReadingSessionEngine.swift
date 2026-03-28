import Foundation
import SwiftData

/// Manages reading session tracking — timer, position, word counting, comprehension.
/// Manual start/stop by the user.
@MainActor
final class ReadingSessionEngine: ObservableObject {
    @Published var isActive = false
    @Published var elapsedTime: TimeInterval = 0
    @Published var currentSession: ReadingSessionRecord?

    private var timer: Timer?
    private var modelContext: ModelContext?

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Session Control

    /// Start a new reading session.
    func startSession(bookTitle: String) {
        guard !isActive else { return }

        let session = ReadingSessionRecord(bookTitle: bookTitle)
        modelContext?.insert(session)
        currentSession = session
        isActive = true
        elapsedTime = 0

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isActive else { return }
                self.elapsedTime = self.currentSession?.duration ?? 0
            }
        }
    }

    /// Stop the current reading session and save stats.
    func stopSession(wordsRead: Int = 0, charsRead: Int = 0, pagesRead: Int = 0,
                     newWords: Int = 0, comprehension: Double = 0) {
        guard isActive, let session = currentSession else { return }

        session.endedAt = Date()
        session.wordsRead = wordsRead
        session.charsRead = charsRead
        session.pagesRead = pagesRead
        session.newWordsEncountered = newWords
        session.comprehensionPct = comprehension
        try? modelContext?.save()

        timer?.invalidate()
        timer = nil
        isActive = false
    }

    /// Format elapsed time as "HH:MM:SS" or "MM:SS".
    var formattedTime: String {
        let total = Int(elapsedTime)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}
