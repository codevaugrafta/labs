import Foundation
import Observation
import AppKit
import OSLog
import UserNotifications

private let countdownNotificationLog = Logger(subsystem: "com.franciscodilussor.tiempo", category: "notifications")

/// A standalone countdown timer that runs alongside Tiempo's category tracking.
/// Set a target duration (e.g., 3 hours), start it, and it counts down to zero.
@MainActor
@Observable
final class CountdownTimer {
    static let shared = CountdownTimer()

    enum State: Equatable {
        case idle
        case running(targetSeconds: Int, startedAt: Date)
        case paused(targetSeconds: Int, elapsedBeforePause: TimeInterval)
        case finished
    }

    private(set) var state: State = .idle

    /// Current remaining seconds (updated by timer tick)
    var remainingSeconds: Int {
        switch state {
        case .idle, .finished:
            return 0
        case .running(let target, let startedAt):
            let elapsed = Int(Date().timeIntervalSince(startedAt))
            return max(0, target - elapsed)
        case .paused(let target, let elapsed):
            return max(0, target - Int(elapsed))
        }
    }

    var isActive: Bool {
        switch state {
        case .running, .paused: return true
        default: return false
        }
    }

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    var formattedRemaining: String {
        let total = remainingSeconds
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    var targetLabel: String {
        switch state {
        case .running(let target, _), .paused(let target, _):
            let h = target / 3600
            let m = (target % 3600) / 60
            if h > 0 { return "\(h)h \(m)m target" }
            return "\(m)m target"
        default:
            return ""
        }
    }

    // MARK: - Actions

    func start(hours: Int = 0, minutes: Int = 0, seconds: Int = 0) {
        let total = hours * 3600 + minutes * 60 + seconds
        guard total > 0 else { return }
        state = .running(targetSeconds: total, startedAt: Date())
        ThemeManager.shared.playStartFeedback()
    }

    func pause() {
        guard case .running(let target, let startedAt) = state else { return }
        let elapsed = Date().timeIntervalSince(startedAt)
        state = .paused(targetSeconds: target, elapsedBeforePause: elapsed)
    }

    func resume() {
        guard case .paused(let target, let elapsed) = state else { return }
        let adjustedStart = Date().addingTimeInterval(-elapsed)
        state = .running(targetSeconds: target, startedAt: adjustedStart)
    }

    func stop() {
        state = .idle
        ThemeManager.shared.playStopFeedback()
    }

    /// Called every second by the timer tick. Checks for completion.
    func tick() {
        if case .running = state, remainingSeconds <= 0 {
            state = .finished
            ThemeManager.shared.playCompleteFeedback()
            // Show macOS notification
            showCompletionNotification()
        }
    }

    private func showCompletionNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Tiempo"
        content.body = "Countdown finished!"
        if ThemeManager.shared.feedbackSoundEnabled {
            content.sound = .default
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                countdownNotificationLog.error("Countdown notification failed: \(error.localizedDescription)")
            }
        }
    }

    private init() {}
}
