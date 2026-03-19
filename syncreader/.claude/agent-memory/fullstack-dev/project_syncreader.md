---
name: SyncReader project context
description: What SyncReader is, its stack, and which agents own which layers
type: project
---

SyncReader is a Tauri 2.x desktop app (SvelteKit + Svelte 5 frontend, Rust backend) for language learning by syncing TTS audio with text — highlights words as they are spoken, like Kindle Whispersync for custom audio.

**Why:** Language learning use case; user wants a premium, minimal Apple-aesthetic desktop app with precise word-level audio sync.

**How to apply:** The frontend lives in `src/` (SvelteKit, adapter-static, SPA mode). The Rust backend lives in `src-tauri/`. The two layers communicate exclusively via Tauri `invoke()` commands. Frontend agent owns everything under `src/`; a separate backend agent owns `src-tauri/`.

Rust backend is fully implemented. All eight Tauri commands are registered in `src-tauri/src/lib.rs`:
- `select_file(filter)` — shim; actual dialog opened from frontend via `@tauri-apps/plugin-dialog`
- `read_text_file(path)` — reads UTF-8 file
- `get_asset_url(path)` — converts fs path to `asset://localhost/…` URL
- `align_audio(audioPath, text)` — spawns `scripts/align.py` (stable-ts), returns `{ timestamps, sentences }`
- `generate_tts(text, provider, voice, apiKey, outputDir)` — provider: "elevenlabs" | "gemini" | "inworld"
- `save_project(project)` / `load_project(id)` / `list_projects()` — persist to `~/Library/Application Support/syncreader/projects/`

Rust modules: `commands.rs`, `alignment.rs`, `tts.rs`, `project.rs`.
Python sidecar: `scripts/align.py` (auto-installs stable-ts on first run).
Plugins registered: `tauri-plugin-dialog`, `tauri-plugin-fs`, `tauri-plugin-opener`.
App identifier changed to `com.syncreader.app`; window is 900x700 with native decorations.

ElevenLabs returns character-level timestamps that are converted to word-level in `tts.rs`.
Gemini and Inworld return no timestamps — caller must invoke `align_audio` afterwards.

Dev server runs on port 1420 (strictPort, configured in vite.config.js).
