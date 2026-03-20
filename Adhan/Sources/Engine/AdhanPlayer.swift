import Foundation
import AVFoundation
import AppKit

/// Manages Adhan audio playback with fade-in/out and independent volume control.
@MainActor
@Observable
final class AdhanPlayer {
    private(set) var isPlaying = false
    private(set) var currentRecitation: AdhanRecitation?
    /// Last playback failure (cleared on successful `play`).
    private(set) var lastPlaybackError: String?
    private var audioPlayer: AVAudioPlayer?
    private var fadeTimer: Timer?

    var volume: Float {
        get { UserDefaults.standard.object(forKey: AppSettings.adhanVolumeKey) as? Float ?? AppSettings.defaultVolume }
        set {
            UserDefaults.standard.set(newValue, forKey: AppSettings.adhanVolumeKey)
            audioPlayer?.volume = newValue
        }
    }

    // MARK: - Playback

    /// Play an Adhan recitation with smooth fade-in.
    func play(recitation: AdhanRecitation, fadeInDuration: TimeInterval = 3.0) {
        stop()
        lastPlaybackError = nil

        guard let url = audioURL(for: recitation) else {
            let msg = "Missing audio file: \(recitation.filename)"
            lastPlaybackError = msg
            AdhanLog.player.error("\(msg, privacy: .public)")
            NSSound(named: "Glass")?.play()
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = 0
            player.prepareToPlay()
            player.play()

            audioPlayer = player
            currentRecitation = recitation
            isPlaying = true

            // Fade in
            fadeVolume(from: 0, to: volume, duration: fadeInDuration)
        } catch {
            let msg = error.localizedDescription
            lastPlaybackError = msg
            AdhanLog.player.error("AVAudioPlayer failed: \(msg, privacy: .public)")
            NSSound(named: "Glass")?.play()
        }
    }

    /// Play a short chime sound for pre-reminders.
    func playChime() {
        guard let url = audioURL(for: AdhanRecitation.gentleChime) else {
            // Fallback to system sound
            NSSound(named: "Tink")?.play()
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = volume
            player.prepareToPlay()
            player.play()
            audioPlayer = player
        } catch {
            AdhanLog.player.error("Chime AVAudioPlayer failed: \(error.localizedDescription, privacy: .public)")
            NSSound(named: "Tink")?.play()
        }
    }

    /// Stop playback with smooth fade-out.
    func stop(fadeOutDuration: TimeInterval = 2.0) {
        guard let player = audioPlayer, player.isPlaying else {
            cleanup()
            return
        }

        fadeVolume(from: player.volume, to: 0, duration: fadeOutDuration) { [weak self] in
            Task { @MainActor in
                self?.cleanup()
            }
        }
    }

    /// Immediately stop without fade.
    func stopImmediately() {
        cleanup()
    }

    // MARK: - Audio File Resolution

    private func audioURL(for recitation: AdhanRecitation) -> URL? {
        if recitation.isBundled {
            let baseName = recitation.filename.replacingOccurrences(of: ".m4a", with: "").replacingOccurrences(of: ".caf", with: "")
            let ext = recitation.filename.hasSuffix(".caf") ? "caf" : "m4a"
            // `build-app.sh` copies into Contents/Resources/Audio/
            if let url = Bundle.main.url(forResource: baseName, withExtension: ext, subdirectory: "Audio") {
                return url
            }
            if let bundlePath = Bundle.main.path(forResource: baseName, ofType: ext) {
                return URL(fileURLWithPath: bundlePath)
            }

            // Check Application Support directory
            let appSupport = applicationSupportURL()
            let fileURL = appSupport.appendingPathComponent(recitation.filename)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                return fileURL
            }

            return nil
        } else {
            // Custom audio file in Application Support
            let appSupport = applicationSupportURL()
            let fileURL = appSupport.appendingPathComponent(recitation.filename)
            return FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
        }
    }

    private func applicationSupportURL() -> URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Adhan")
        try? fm.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport
    }

    // MARK: - Fade Control

    private func fadeVolume(from startVol: Float, to endVol: Float, duration: TimeInterval, completion: (@Sendable () -> Void)? = nil) {
        fadeTimer?.invalidate()

        let steps = 30
        let interval = duration / Double(steps)
        let delta = (endVol - startVol) / Float(steps)
        let stepBox = StepCounter()

        fadeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
            let current = stepBox.increment()
            let newVolume = startVol + delta * Float(current)
            let isDone = current >= steps

            Task { @MainActor in
                self?.audioPlayer?.volume = isDone ? endVol : newVolume

                if isDone {
                    self?.fadeTimer?.invalidate()
                    self?.fadeTimer = nil
                    completion?()
                }
            }
        }
    }

    /// Thread-safe step counter for fade timer.
    private final class StepCounter: @unchecked Sendable {
        private var value = 0
        private let lock = NSLock()

        func increment() -> Int {
            lock.lock()
            defer { lock.unlock() }
            value += 1
            return value
        }
    }

    private func cleanup() {
        fadeTimer?.invalidate()
        fadeTimer = nil
        audioPlayer?.stop()
        audioPlayer = nil
        currentRecitation = nil
        isPlaying = false
    }
}
