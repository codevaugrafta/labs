# Voice Tutor — outcome (Phase 0)

Personal macOS menu-bar companion for voice tutoring with a hosted conversational agent (ElevenLabs first). This doc is the north-star for v1; scope changes get a short addendum here first.

## What you see when it works

- A **menu bar icon** opens a **popover**: connection status, last error (if any), **Start session** / **End session**, **Mute mic**, and a **scrollable transcript** of recent turns.
- **Start session** connects to your configured ElevenLabs agent (public agent ID, or conversation token from a local token broker for private agents).
- While connected, state reads clearly: **connecting**, **active**, **ended**, or **error** — no silent failures.
- **Settings** (standard app Settings window): agent ID, optional **token broker URL** (default `http://127.0.0.1:8787`), checkbox **use token broker** when the agent is private.
- Optional **⌘O** (or menu) opens a minimal main window with the same controls if you want a larger surface than the popover.

## Languages and content

- v1 does **not** hard-code a language; the **agent configuration** in the ElevenLabs dashboard (system prompt, knowledge base, voice) defines tutoring style and languages.
- Local client **tools** can be extended later (flashcards, vocabulary); v1 ships with a **no-op / echo** tool handler wired so the pipeline is proven.

## Memory and records

- **Cloud**: conversation memory follows whatever the hosted agent provides.
- **Local**: v1 stores **preferences only** (agent ID, broker URL, use-broker flag) in `UserDefaults`. **No** local transcript persistence in v1 unless added in a later phase.

## Privacy and network

- **Microphone** is used only while a session is active; explain purpose in `NSMicrophoneUsageDescription`.
- **Network**: required for hosted agent; no offline mode in v1.
- **Secrets**: ElevenLabs **API key** never ships in the `.app`; private agents use a **short-lived token** from [TOKEN_BROKER.md](../VoiceTutor/docs/TOKEN_BROKER.md) (local script).

## Non-goals (v1)

- Pronunciation scoring / phoneme-level feedback.
- Replacing the hosted agent with a custom STT→LLM→TTS stack (documented separately as a spike).
- App Store packaging or multi-user accounts.

## Acceptance checklist

- [ ] Popover starts and ends a session against a **public** agent ID without a broker.
- [ ] With broker running and API key in environment, session starts with **private** agent via token.
- [ ] Mute toggles without crashing; end session cleans up.
- [ ] User-visible error string on connection failure (not only console).
