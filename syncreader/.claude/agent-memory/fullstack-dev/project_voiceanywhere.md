---
name: voiceanywhere_project
description: VoiceAnywhere native macOS menu bar TTS app — project context and Swift 6 lessons learned
type: project
---

VoiceAnywhere is a native macOS menu bar app (no Dock icon) that reads selected text aloud using cloud TTS APIs (Inworld, ElevenLabs, Gemini). Lives at /Users/franciscodilussor/Documents/002/voiceanywhere/.

**Why:** System-wide TTS via hotkey (Option+S), with language auto-detection and per-language voice routing.

**Stack:** Swift 6, SwiftUI, AppKit, AXUIElement, AVAudioEngine, KeyboardShortcuts package, macOS 14+.

**Swift 6 concurrency lessons from this project:**

- `kAXTrustedCheckOptionPrompt` (CF extern) is flagged as non-Sendable shared mutable state; workaround is to use the raw string `"AXTrustedCheckOptionPrompt"` instead of the C global.
- `NSAnimationContext` completion handlers run off the main thread — must `Task { @MainActor in }` inside them when touching `@MainActor` state.
- `AVAudioPlayerNode.scheduleBuffer` completion callbacks fire on arbitrary threads — same pattern: `Task { @MainActor [weak self] in }` inside.
- Classes that own AppKit panels/windows should be `@MainActor` to avoid actor isolation warnings.
- `TTSClient` must be `@MainActor` because it reads from `AppSettings` (an `ObservableObject` on the main actor).

**How to apply:** When writing Swift 6 + AppKit code, annotate any class that touches UI or AppKit objects with `@MainActor`. For CF constant globals from C headers that are non-Sendable, use string literals when the value is documented (as with AX constants).
