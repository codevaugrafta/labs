# PRD: SyncReader & VoiceAnywhere

## Problem Statement

Language learners who generate high-quality TTS audio from dialogues and narratives have no way to experience that audio as an interactive reading tool on macOS. Existing solutions either lock you into their ecosystem (Kindle Whispersync), have poor alignment accuracy (LingQ), or require you to leave your current context to use TTS (Speechify, NaturalReader). The user needs two things: (1) a dedicated reading app that syncs their pre-generated audio with text at word-level precision, and (2) a system-wide utility that reads any highlighted text aloud using premium cloud TTS voices without switching windows.

## Solution

Two separate native macOS applications:

**SyncReader** — A Tauri 2.x desktop app that accepts audio files + text (or generates audio via cloud TTS APIs), performs forced alignment to produce word-level timestamps, and presents an interactive reading experience with karaoke-style word highlighting, click-to-seek, multiple loop modes, and playback speed control.

**VoiceAnywhere** — A native Swift menu bar app that captures highlighted text from any application via macOS Accessibility APIs, sends it to a cloud TTS provider (Inworld, ElevenLabs, or Gemini), and streams the audio back seamlessly without stealing focus or opening windows.

Both apps share a design language: minimal, clean, premium Apple aesthetic with exceptional UX, haptic feedback, and pleasing interactions.

## User Stories

### SyncReader

1. As a language learner, I want to load a text file and an audio file so that I can study them together
2. As a language learner, I want to paste text directly into the app so that I don't need to create files for short content
3. As a language learner, I want the app to automatically sync my audio with my text at word-level precision so that I can follow along as it plays
4. As a language learner, I want each word highlighted as it is being spoken so that I can track exactly where in the text the audio is
5. As a language learner, I want the current sentence visually distinguished from the current word so that I have both micro and macro context
6. As a language learner, I want to click on any word and have the audio jump to that word's position so that I can re-listen to specific parts
7. As a language learner, I want to click on a sentence and have the audio jump to the beginning of that sentence so that I can re-listen to complete thoughts
8. As a language learner, I want to loop a single sentence so that I can practice hearing it repeatedly
9. As a language learner, I want to loop a paragraph so that I can study a passage repeatedly
10. As a language learner, I want A-B repeat where I select a custom start and end point so that I can loop any arbitrary section
11. As a language learner, I want playback speed control (0.5x, 0.75x, 1x, 1.25x, 1.5x, 2x) so that I can slow down difficult passages or speed up easy ones
12. As a language learner, I want to generate audio directly in the app using ElevenLabs so that I get perfect timestamps without alignment
13. As a language learner, I want to generate audio using Gemini 2.5 Pro TTS so that I can use the most expressive voices
14. As a language learner, I want to generate audio using Inworld TTS so that I can use the highest-quality voices at the best price
15. As a language learner, I want the app to support text with speaker labels ([Tutor]: ... / [Student]: ...) so that dialogues are visually distinguished
16. As a language learner, I want to save my text+audio+timestamps as a project so that I can return to it later
17. As a language learner, I want to open previously saved projects so that I can continue studying
18. As a language learner, I want keyboard shortcuts for play/pause, next sentence, previous sentence, and loop toggle so that I can control playback without the mouse
19. As a language learner, I want the app to feel premium with smooth animations, clean typography, and Apple-native aesthetics so that studying is a pleasure
20. As a language learner, I want dark mode as the default with optional light mode so that I can study comfortably at any time

### VoiceAnywhere

21. As a macOS user, I want to highlight text in any application and press a hotkey to hear it read aloud so that I don't have to switch apps
22. As a macOS user, I want the audio to play immediately without opening any window so that my workflow is uninterrupted
23. As a macOS user, I want the app to auto-detect the language of the highlighted text and use the appropriate voice so that I don't need to manually switch languages
24. As a macOS user, I want to configure which voice is used for each language so that I always hear my preferred voice
25. As a macOS user, I want Inworld TTS as the default provider so that I get the best quality-to-price ratio
26. As a macOS user, I want to switch between Inworld, ElevenLabs, and Gemini TTS so that I can compare voices
27. As a macOS user, I want streaming audio playback so that speech starts within 100-300ms of pressing the hotkey
28. As a macOS user, I want a minimal, aesthetically pleasing indicator that shows when audio is playing so that I know the app is working
29. As a macOS user, I want to press the hotkey again to stop playback so that I can cancel reading mid-sentence
30. As a macOS user, I want to configure the global hotkey in settings so that I can choose a shortcut that doesn't conflict with other apps
31. As a macOS user, I want the app to live in the menu bar with no Dock icon so that it's always available but never in the way
32. As a macOS user, I want a clear onboarding flow that guides me through granting Accessibility permission so that setup is painless
33. As a macOS user, I want my API keys stored securely in the macOS Keychain so that they're protected
34. As a macOS user, I want the indicator to show a subtle waveform animation during playback so that it feels alive and premium
35. As a macOS user, I want haptic feedback (trackpad) when playback starts and stops so that interactions feel tactile

## Implementation Decisions

### SyncReader (Tauri 2.x)

**Framework**: Tauri 2.x with a Svelte frontend and Rust backend. HTML/CSS is the natural fit for dynamic word-level text highlighting (spans, classes, CSS transitions). SwiftUI lacks good per-word dynamic styling support. Tauri produces ~5MB bundles vs Electron's ~250MB.

**Alignment Engine** (deep module):
- Interface: `align(audioPath: string, text: string, lang: string) → WordTimestamp[]`
- When audio is generated via ElevenLabs: uses the character-level timestamps returned by the `/v1/text-to-speech/{voice_id}/with-timestamps` endpoint — zero alignment error
- When audio comes from Gemini, Inworld, or user-uploaded files: runs forced alignment via a Python sidecar process using `stable-ts` (Whisper-based, MIT license, `align()` function accepts known text + audio)
- Falls back to Montreal Forced Aligner (MFA) for languages where stable-ts performs poorly
- Output format: JSON array of `{word: string, start: number, end: number}` with sentence boundary markers

**TTS Generator** (deep module):
- Interface: `generate(text: string, provider: string, voice: string, options?: object) → {audioPath: string, timestamps?: WordTimestamp[]}`
- ElevenLabs: uses `/v1/text-to-speech/{voice_id}/with-timestamps` for audio + timestamps in one call. Streaming via SSE.
- Gemini 2.5 Pro TTS: uses Google's Gemini API with TTS mode. Returns raw PCM audio, no timestamps. Post-processing alignment required.
- Inworld TTS 1.5 Max: WebSocket streaming. Returns audio chunks, no timestamps. Post-processing alignment required.
- Audio saved as MP3 or WAV to the project directory
- API keys stored in a local config file (personal use)

**Text Renderer** (deep module):
- Implements the Hyperaudio pattern: each word is a `<span>` with `data-start` and `data-end` attributes
- A `requestAnimationFrame` loop (throttled to 20fps) binary-searches the timestamp array to find the current word
- Current word gets `.active-word` class (highlight color), current sentence gets `.active-sentence` class (subtle background)
- Click on any word → `audio.currentTime = word.start`
- Auto-scroll keeps the active region centered in the viewport
- Speaker labels rendered as styled headers above their dialogue sections
- Supports both plain text (auto-split into paragraphs/sentences) and speaker-labeled text (parsed by `[Name]:` pattern)

**Loop Controller**:
- Modes: Off, Sentence, Paragraph, A-B Custom
- Sentence mode: on `timeupdate`, if `currentTime >= sentenceEnd`, set `currentTime = sentenceStart`
- Paragraph mode: same logic at paragraph granularity
- A-B mode: user clicks "Set A" then "Set B" to define arbitrary loop points
- Visual indicator on the progress bar showing the active loop region

**Audio Player**:
- Wraps HTML5 `<audio>` element
- Speed control via `audio.playbackRate` (0.5, 0.75, 1.0, 1.25, 1.5, 2.0)
- Emits `timeupdate` events consumed by Text Renderer and Loop Controller
- Keyboard shortcuts: Space (play/pause), Left/Right (prev/next sentence), Up/Down (speed), L (cycle loop mode)

**Project Store**:
- Projects saved as `.syncreader` JSON files containing: text, timestamps array, audio file path (relative), metadata (language, speaker labels, creation date)
- Audio files stored alongside the project file
- Recent projects list persisted in Tauri's app data directory

**UI/UX**:
- Dark mode default (zinc/neutral palette), optional light mode
- Geist-inspired typography: clean sans-serif for text, monospace for timestamps/metadata
- Smooth CSS transitions on word highlighting (background-color, 100ms ease)
- Progress bar with waveform visualization
- Minimal chrome — the text is the hero

### VoiceAnywhere (Native Swift)

**Framework**: Swift 6 + SwiftUI for settings UI, AppKit for menu bar integration. `LSUIElement = YES` (no Dock icon).

**Text Capture** (deep module):
- Interface: `captureSelectedText() async → String?`
- Chain of responsibility:
  1. `AXUIElementCreateSystemWide()` → `kAXFocusedUIElementAttribute` → `kAXSelectedTextAttribute`
  2. Fallback: save clipboard → simulate Cmd+C via CGEvent → read NSPasteboard → restore clipboard
- Returns nil if no text selected (with user notification)
- Requires Accessibility permission — app checks via `AXIsProcessTrustedWithOptions` on launch and guides user through granting it

**Language Detector**:
- Uses `NLLanguageRecognizer` from Natural Language framework
- Maps detected language to the user's configured voice for that language
- Fallback: user's default voice if language detection confidence is low

**TTS Client** (deep module):
- Interface: `speak(text: String, voice: Voice) → AsyncStream<Data>` (PCM chunks)
- Inworld TTS 1.5 Max (default): WebSocket connection to Inworld API, receives PCM frames
- ElevenLabs Flash v2.5: WebSocket to `/v1/text-to-speech/{voice_id}/stream-input`, receives MP3 frames, decoded to PCM
- Gemini TTS: HTTP streaming, receives PCM L16 chunks
- Provider abstraction: `TTSProvider` protocol with `func stream(text: String, voice: Voice) -> AsyncStream<Data>`
- Persistent WebSocket connections (opened on app launch, reconnected on failure) for lowest latency

**Audio Streamer** (deep module):
- `AVAudioEngine` + `AVAudioPlayerNode`
- Push model: schedule `AVAudioPCMBuffer` objects as chunks arrive from TTS API
- Pre-buffer 2 chunks before starting playback for smooth audio
- Plays through default output device without stealing focus
- Stop: `playerNode.stop()` + `engine.stop()` — immediate silence

**Hotkey Manager**:
- Uses `sindresorhus/KeyboardShortcuts` Swift package (MIT, production-proven)
- Default: Option+S (configurable in settings)
- Toggle behavior: press to start reading, press again to stop
- Second shortcut for "repeat last" (reads the same text again)

**Status Indicator**:
- Small floating NSPanel (non-activating, `NSPanel.StyleMask.nonactivatingPanel`)
- Positioned near the menu bar icon
- Shows: subtle waveform animation (3-bar audio visualizer) during playback
- Fades in on start (200ms), fades out on stop (300ms)
- Follows system appearance (dark/light)

**Haptic Feedback**:
- `NSHapticFeedbackManager.defaultPerformer.perform(.alignment)` on playback start
- `NSHapticFeedbackManager.defaultPerformer.perform(.levelChange)` on playback stop
- Only on MacBooks with Force Touch trackpad (no-op on external trackpad/mouse)

**API Key Storage**:
- macOS Keychain via Security framework (`SecItemAdd`, `SecItemCopyMatching`)
- Keys stored per-provider: `com.voiceanywhere.inworld-api-key`, etc.
- Settings UI: password fields that read/write Keychain

**Distribution**:
- Developer ID signed + notarized (direct distribution, not Mac App Store)
- DMG installer with drag-to-Applications
- Sparkle framework for auto-updates (personal use, can add later)

## Testing Decisions

**What makes a good test**: Tests verify external behavior through the module's public interface. They should survive internal refactors. Mock only at system boundaries (network, filesystem, audio hardware), never internal modules.

**Modules to test**:

1. **Alignment Engine** (SyncReader):
   - Given known text + audio with known word positions, verify output timestamps are within acceptable tolerance (±50ms)
   - Test ElevenLabs timestamp parser against sample API responses
   - Test sentence boundary detection across multiple languages
   - Test handling of edge cases: empty text, single word, very long text

2. **Text Renderer sync logic** (SyncReader):
   - Given a timestamps array and a currentTime, verify the correct word index is returned (binary search correctness)
   - Test boundary conditions: time before first word, after last word, exactly on a word boundary
   - Test click-to-seek: clicking word N sets audio time to word N's start time

3. **Loop Controller** (SyncReader):
   - Verify sentence loop resets to sentence start when currentTime exceeds sentence end
   - Verify A-B loop respects custom boundaries
   - Verify loop mode transitions (off → sentence → paragraph → AB → off)

4. **Text Capture** (VoiceAnywhere):
   - Test AXUIElement path returns selected text when available
   - Test clipboard fallback is invoked when AXUIElement returns nil
   - Test clipboard is properly restored after fallback

5. **Language Detector** (VoiceAnywhere):
   - Test correct language detection for Arabic, English, Spanish, French, German, Japanese
   - Test fallback to default voice when confidence is below threshold
   - Test mixed-language text (should detect dominant language)

6. **TTS Client** (VoiceAnywhere):
   - Test provider protocol conformance for all three providers
   - Test WebSocket reconnection on connection failure
   - Test streaming produces valid PCM buffer format

## Out of Scope

- iOS/iPadOS versions (future consideration — Tauri 2.x supports mobile, Swift is portable)
- Dictionary/vocabulary lookup integration
- Spaced repetition / flashcard generation
- Speech recognition / pronunciation scoring
- Cloud sync between devices
- Multi-user / account system
- Mac App Store distribution (blocked by sandbox requirements for VoiceAnywhere)
- Web version of either app
- Windows/Linux ports (future consideration for SyncReader via Tauri)

## Further Notes

- **Cost estimates for personal use**: At ~500 words/day via VoiceAnywhere, Inworld costs ~$0.03/day ($0.90/month). ElevenLabs Starter plan ($5/mo) gives 30K chars/month. Gemini TTS is token-priced. All very affordable for personal use.
- **Alignment accuracy**: Research (INTERSPEECH 2024) shows MFA outperforms WhisperX and MMS for forced alignment. For MVP, stable-ts is pragmatic (simpler setup, decent accuracy). Can upgrade to MFA per-language as needed.
- **The Python sidecar**: Tauri supports sidecar processes. The alignment Python script will be bundled with the app. For personal use, we can assume Python is installed (it is). For distribution, we'd need to bundle a Python runtime or use a compiled alternative.
- **Security**: API keys stored locally (config file for SyncReader, Keychain for VoiceAnywhere). No keys transmitted except to the respective TTS provider APIs over HTTPS. No analytics, no telemetry, no phoning home.
- **Haptic feedback**: Only available on MacBooks with Force Touch trackpad. The app detects capability and gracefully degrades on unsupported hardware.
