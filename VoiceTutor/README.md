# Voice Tutor (macOS)

Menu-bar-first macOS app for live voice tutoring via **ElevenLabs Conversational AI** (Swift SDK + LiveKit).

## Quick start

1. **Public agent**: In **Settings**, enter your **Agent ID**, leave **Use token broker** off, then **Start session** from the menu bar popover or main window.

2. **Private agent**: Run the token broker locally (see [docs/TOKEN_BROKER.md](docs/TOKEN_BROKER.md)), enable **Use token broker** in Settings, set **Broker URL** (default `http://127.0.0.1:8787`).

## Build

```bash
cd VoiceTutor
swift test
./build-app.sh
open build/VoiceTutor.app
```

Product outcome and acceptance notes: [plans/voice-tutor-outcome.md](../plans/voice-tutor-outcome.md) (repo root).

## Project layout

- `Sources/VoiceTutor/` — SwiftUI app, menu bar, session controller
- `scripts/elevenlabs_token_broker.py` — localhost token minting for private agents
- `docs/` — broker setup, manual test matrix, custom-stack spike notes
