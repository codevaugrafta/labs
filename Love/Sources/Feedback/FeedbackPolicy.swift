import AppKit
import SwiftUI

/// Centralized sound and motion policy (macOS has limited haptics; favor sound + UI).
@MainActor
enum FeedbackPolicy {
    private static let soundKey = "Love.feedbackSoundEnabled"
    private static let legacySoundKey = "FocusPath.feedbackSoundEnabled"

    static var soundEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: soundKey) == nil,
               UserDefaults.standard.object(forKey: legacySoundKey) != nil {
                let v = UserDefaults.standard.bool(forKey: legacySoundKey)
                UserDefaults.standard.set(v, forKey: soundKey)
                UserDefaults.standard.removeObject(forKey: legacySoundKey)
            }
            if UserDefaults.standard.object(forKey: soundKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: soundKey)
        }
        set {
            UserDefaults.standard.removeObject(forKey: legacySoundKey)
            UserDefaults.standard.set(newValue, forKey: soundKey)
        }
    }

    static func playCaptureLanded() {
        playSystemNamed("Pop")
    }

    static func playTaskCompleted() {
        playSystemNamed("Glass")
    }

    static func playFocusSet() {
        playSystemNamed("Tink")
    }

    private static func playSystemNamed(_ name: String) {
        guard soundEnabled else { return }
        if let sound = NSSound(named: NSSound.Name(name)) {
            sound.play()
        } else {
            NSSound.beep()
        }
    }

    static func listTransition(reduceMotion: Bool) -> Animation {
        reduceMotion ? .linear(duration: 0.15) : .easeInOut(duration: 0.2)
    }
}
