import AppKit
import SwiftUI
import KeyboardShortcuts

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    var statusItem: NSStatusItem!
    var settings = AppSettings()
    var textCapture = TextCapture()
    var ttsClient: TTSClient!
    var audioStreamer = AudioStreamer()
    var languageDetector = LanguageDetector()
    var statusIndicator: StatusIndicatorController?

    private var lastText: String?
    private var isPlaying = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupHotkeys()
        checkAccessibilityPermission()

        ttsClient = TTSClient(settings: settings)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "VoiceAnywhere")
            button.image?.size = NSSize(width: 18, height: 18)
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "VoiceAnywhere", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    private func setupHotkeys() {
        KeyboardShortcuts.onKeyUp(for: .speakSelection) { [weak self] in
            Task { @MainActor in
                await self?.handleSpeakSelection()
            }
        }

        KeyboardShortcuts.onKeyUp(for: .repeatLast) { [weak self] in
            Task { @MainActor in
                await self?.handleRepeatLast()
            }
        }
    }

    private func checkAccessibilityPermission() {
        // kAXTrustedCheckOptionPrompt is a non-sendable CF extern in Swift 6.
        // Use AXIsProcessTrusted() for the silent check here; the Settings view
        // surfaces an "Open Settings" button when access is not granted.
        // The prompt is shown via AXIsProcessTrustedWithOptions on a nonisolated
        // helper to avoid the shared-mutable-state error.
        let trusted = AXIsProcessTrusted()
        if !trusted {
            print("Accessibility permission not granted.")
            Self.requestAccessibilityPermission()
        }
    }

    /// Calls `AXIsProcessTrustedWithOptions` with the prompt flag.
    /// We use the raw string value of `kAXTrustedCheckOptionPrompt` to avoid
    /// importing the non-Sendable CF global into a Swift 6 concurrency context.
    private nonisolated static func requestAccessibilityPermission() {
        // "AXTrustedCheckOptionPrompt" is the documented string value of
        // kAXTrustedCheckOptionPrompt (HIServices/AXUIElement.h).
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options: CFDictionary = [key: kCFBooleanTrue as Any] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func handleSpeakSelection() async {
        if isPlaying {
            stopPlayback()
            return
        }

        guard let text = textCapture.captureSelectedText() else {
            showNoTextNotification()
            return
        }

        lastText = text
        await speakText(text)
    }

    func handleRepeatLast() async {
        if isPlaying {
            stopPlayback()
            return
        }

        guard let text = lastText else { return }
        await speakText(text)
    }

    private func speakText(_ text: String) async {
        let language = languageDetector.detect(text)
        let voice = settings.voiceForLanguage(language)

        isPlaying = true
        showStatusIndicator()
        provideHapticFeedback(.start)
        updateStatusIcon(playing: true)

        do {
            let stream = try await ttsClient.stream(text: text, voice: voice)

            audioStreamer.prepareToPlay()

            for try await chunk in stream {
                audioStreamer.scheduleBuffer(chunk)
            }

            await audioStreamer.waitForCompletion()
        } catch {
            print("TTS error: \(error)")
        }

        stopPlayback()
    }

    private func stopPlayback() {
        audioStreamer.stop()
        isPlaying = false
        hideStatusIndicator()
        provideHapticFeedback(.stop)
        updateStatusIcon(playing: false)
    }

    private func updateStatusIcon(playing: Bool) {
        if let button = statusItem.button {
            let symbolName = playing ? "waveform.circle.fill" : "waveform"
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "VoiceAnywhere")
            button.image?.size = NSSize(width: 18, height: 18)
        }
    }

    private func showStatusIndicator() {
        if statusIndicator == nil {
            statusIndicator = StatusIndicatorController()
        }
        statusIndicator?.show(near: statusItem)
    }

    private func hideStatusIndicator() {
        statusIndicator?.hide()
    }

    private func showNoTextNotification() {
        if let button = statusItem.button {
            let original = button.image
            button.image = NSImage(
                systemSymbolName: "exclamationmark.triangle",
                accessibilityDescription: "No text selected"
            )
            button.image?.size = NSSize(width: 18, height: 18)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                button.image = original
            }
        }
    }

    private func provideHapticFeedback(_ type: HapticType) {
        switch type {
        case .start:
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        case .stop:
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
        }
    }

    enum HapticType {
        case start, stop
    }

    @objc func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
