# IMI (macOS)

Menu-bar-first macOS app for live voice sessions via **ElevenLabs Conversational AI** (Swift SDK + LiveKit).  
Swift package folder: `VoiceTutor/`; **product name:** **IMI**.

## Quick start

0. **Find your Agent ID** (API key only in your terminal, never in the app or chat):  
   `export ELEVENLABS_API_KEY='xi-…'` then `python3 scripts/list_convai_agents.py`

1. **Public agent** (marked public in the ElevenLabs dashboard): In **Settings**, enter that agent’s **Agent ID**, turn **Use token broker** off, then **Start session** from the menu bar popover or main window. No API key in the app.

2. **Private agent**: Run the token broker locally (see [docs/TOKEN_BROKER.md](docs/TOKEN_BROKER.md)), enable **Use token broker** in Settings, set **Broker base URL** (default `http://127.0.0.1:8787` — no `/token` suffix; the app adds it).

**Brand:** [docs/BRAND_IMI.md](docs/BRAND_IMI.md) · vector mark: [docs/assets/imi-mark.svg](docs/assets/imi-mark.svg) · Gemini (Nano Banana 2) app icon: `python3 scripts/generate_imi_brand_gemini.py` with `GEMINI_API_KEY` set, then `./build-app.sh`.

## Build

```bash
cd VoiceTutor
swift test
./build-app.sh
```

The packaged app **includes** `LiveKitWebRTC.framework` next to the executable (required for ElevenLabs / LiveKit). If you only copy `VoiceTutor` without `build-app.sh`, the app will **quit immediately** with a dyld error.

**`/Applications`:** `./build-app.sh` **copies `IMI.app` to `/Applications` by default** (quits a running IMI first). Set **`SKIP_IMI_APPLICATIONS_INSTALL=1`** to skip (e.g. sandboxed agents). **`CI`** also skips the copy.

```bash
open build/IMI.app    # or: open -a IMI   (after install)
```

To build, install, and **launch** in one step:

```bash
./scripts/install-to-applications.sh
```

Product outcome and acceptance notes: [plans/voice-tutor-outcome.md](../plans/voice-tutor-outcome.md) (repo root).

## Project layout

- `Sources/VoiceTutor/` — SwiftUI app, menu bar, session controller (module `VoiceTutor`)
- `scripts/elevenlabs_token_broker.py` — localhost token minting for private agents
- `docs/` — broker setup, manual test matrix, custom-stack spike notes
