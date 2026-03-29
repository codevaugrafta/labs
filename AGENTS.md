# Labs Monorepo — Agent Instructions

This file is read by both Cursor and Claude Code agents.

## Projects

### Tiempo (macOS Time Tracker)
- **Path**: `Tiempo/`
- **Stack**: Swift 6.2+ (swift-tools-version 6.2), SwiftUI, SwiftData, Swift Charts
- **PRD**: `PRD-TIEMPO.md` (82 user stories, reviewed 3x)
- **Plan**: `plans/tiempo.md` (10 phases, 8 complete locally)
- **Tests**: `cd Tiempo && swift test` — 78 tests across 10 suites
- **Build**: `cd Tiempo && swift build`
- **Run (dev binary, always matches last compile)**: `cd Tiempo && swift run Tiempo`
- **Run (.app bundle)**: `cd Tiempo && ./build-app.sh && open build/Tiempo.app`
- **Install to /Applications** (quit Tiempo first): `./Tiempo/scripts/install-to-applications.sh` or `cp -R Tiempo/build/Tiempo.app /Applications/`
- **If the UI “didn’t change”**: you’re opening an old copy. `swift test` does not update `/Applications/Tiempo.app` — rebuild with `./build-app.sh`, replace the app, quit fully (⌘Q), reopen.
- **Dock**: `LSUIElement` is **true** in `packaging/Info.plist` — Tiempo does **not** appear in the Dock; use the **menu bar** icon and windows. **Do not** call `NSApp.setActivationPolicy(.regular)` (it overrides the plist and brings back the Dock); use `.accessory` in `TiempoAppDelegate`.

### Adhan (macOS Prayer Times)
- **Path**: `Adhan/`
- **Stack**: Swift 6.2+ (swift-tools-version 6.2), SwiftUI, SwiftData, adhan-swift (pinned revision), AVFoundation, UserNotifications
- **Tests**: `cd Adhan && swift test` — 24 tests (PrayerTimesEngine, PrayerTimeEntry + Iqamah, Hijri, mosque URL, recitation fallback, menu bar / AppSettings)
- **Build app**: `cd Adhan && ./build-app.sh` → `build/Adhan.app` (release)
- **Logs**: Console filter `subsystem:com.adhan.prayer-times`
- **Dock**: `LSUIElement` is **true** in `Sources/Resources/Info.plist` — Adhan does **not** appear in the Dock; use the **menu bar** icon. **Do not** call `NSApp.setActivationPolicy(.regular)` (it overrides the plist); use `.accessory` in `AdhanAppDelegate`.
- **“Update Swift + app” (Adhan only — not Tiempo)**:
  1. **Swift / SPM**: Keep `Adhan/Package.swift` `swift-tools-version` in sync with your Xcode Swift; run `cd Adhan && swift package update`.
  2. **App bundle**: Bump `Adhan/Sources/Resources/Info.plist` `CFBundleShortVersionString` and `CFBundleVersion` when shipping user-visible changes.
  3. **Ship**: `cd Adhan && swift test && ./build-app.sh`, then replace `Adhan.app` in `/Applications/` (quit Adhan first).
  4. **Do not use `swift run` to verify menu-bar / notification behavior** — `Bundle.main` points at `.build/…`, not `Adhan.app`. Use `./run-app.sh` or `open build/Adhan.app` (or `/Applications/Adhan.app`). The menu’s first row shows version and `Adhan.app` vs `debug / swift run`.

### Love (macOS must-do + later drawer)
- **Path**: `Love/`
- **Stack**: Swift 6.2+ (swift-tools-version 6.2), SwiftUI, SwiftData, menu bar `NSStatusItem`
- **PRD**: `Love/PRD.md` (filed as GitHub issue from that document)
- **Tests**: `cd Love && swift test` — engine tests (focus, buckets, captures, snooze)
- **Build**: `cd Love && swift build`
- **Run (.app bundle)**: `cd Love && ./build-app.sh && open build/Love.app` — the app lives under **`Love/build/`** in the repo until you install it; it is **not** in `/Applications/` until you copy it there.
- **Install to /Applications** (shows in Launchpad / Spotlight “Applications”): quit Love, then `./Love/scripts/install-to-applications.sh` or `cp -R Love/build/Love.app /Applications/` and `open -a Love`.
- **Dock**: `LSUIElement` is **true** — Love **does not appear in the Dock** (same pattern as Tiempo/Adhan). After launch, use the **menu bar** (right side) **heart** icon; **Show main window** is **⌘O** from that menu. `LoveAppDelegate` uses `.accessory` — do not force `.regular` if you want to keep the Dock hidden.
- **Global quick capture**: ⌃⌥L via `NSEvent.addGlobalMonitorForEvents` — may require **Accessibility** for Love in System Settings.
- **Bundle id**: `com.franciscodilussor.love` — distinct from any prior `focuspath` bundle; on-disk store migrates from `Application Support/FocusPath/` when `Love.store` is missing. Failed migration is **logged** (`subsystem:com.franciscodilussor.love`, category `migration`) and surfaces a **one-shot alert**; save failures show **`LoveSaveErrorBanner`** in the **main window** and **Quick capture** (panel stays open on failed save so text isn’t lost; dismiss calls `clearLastError()`).
- **Optional app icon (Gemini)**: `cd Love && export GEMINI_API_KEY=... && python3 scripts/generate_app_icon_gemini.py` writes `build/AppIcon.icns`; `./build-app.sh` copies it into the bundle when present. Offline fallback: `swift scripts/create-icon.swift` + `iconutil` (as in `build-app.sh`).

### IMI (macOS menu-bar voice companion)
- **Path**: `VoiceTutor/` (Swift module `VoiceTutor`; **product name IMI**)
- **Stack**: Swift 6.2+ (swift-tools-version 6.2), SwiftUI, [ElevenLabs Swift SDK](https://github.com/elevenlabs/elevenlabs-swift-sdk) (LiveKit WebRTC), menu bar **`MenuBarExtra`** (`.window` style — not tied to main-window `onAppear`)
- **Outcome doc**: `plans/voice-tutor-outcome.md`
- **Tests**: `cd VoiceTutor && swift test`
- **Build**: `cd VoiceTutor && swift build`
- **Run (.app bundle)**: `cd VoiceTutor && ./build-app.sh` — **`build-app.sh` must copy `LiveKitWebRTC.framework` into `Contents/MacOS/`** or the app **exits immediately** (dyld). **`build-app.sh` also copies `IMI.app` to `/Applications` by default** (so Spotlight/Launchpad match `build/`); set **`SKIP_IMI_APPLICATIONS_INSTALL=1`** or run in **`CI`** to skip. **`./VoiceTutor/scripts/install-to-applications.sh`** = build + guaranteed install + **`open -a IMI`**. Same **LSUIElement** pattern as Love: **no Dock icon**; use the **menu bar**; **⌘O** opens the main window from the **IMI** menu.
- **Private agents**: do **not** embed `xi-api-key` in the app; run `python3 scripts/elevenlabs_token_broker.py` with `ELEVENLABS_API_KEY` set — see `VoiceTutor/docs/TOKEN_BROKER.md`.
- **SDK docs alignment**: optional **Settings → Advanced → Environment** maps to `ConversationConfig.environment` (regional routing when ElevenLabs documents it). Debug builds use SDK **`.debug`** logging — Console filter **`com.elevenlabs.sdk`** (upstream `Documentation/Usage.md`).
- **Manual QA**: `VoiceTutor/docs/MANUAL-TEST-MATRIX.md` · **Custom stack spike notes**: `VoiceTutor/docs/voice-tutor-custom-stack-spike.md`

### Leo (macOS Chinese immersive reader)
- **Path**: `Leo/`
- **Dock / windows**: Standard app — **`LSUIElement` is not set** in [`Leo/Sources/Resources/Info.plist`](Leo/Sources/Resources/Info.plist); Leo appears in the **Dock** and uses a main **`WindowGroup`** (not menu-bar-only like Tiempo/Adhan/Love/IMI).
- **Stack**: Swift 6.2+, SwiftUI, SwiftData, Foliate-js in WKWebView, local HTTP (Swifter), optional OpenRouter + InWorld TTS; **Read aloud** falls back to **macOS `AVSpeechSynthesizer`** when no InWorld key or when **Settings → Voice → “Use macOS voices”** is on (no word-level sync on system speech).
- **PRD / plan**: `Leo/PRD.md`, `Leo/PLAN.md` (includes **shipped vs stub** matrix)
- **Workflow**: `Leo/WORKFLOW.md` — canonical Leo implementation branch is **`leo/v1.0-digital-vellum`**; stable fallback is **`leo/v0.2-consolidation`**
- **Threat model**: `Leo/leo-threat-model.md` (loopback bind, CORS scope)
- **Branch gate**: run **`./Leo/scripts/verify-branch-gate.sh`** before any Leo work; it fails if the current branch is not `leo/v1.0-digital-vellum` or if `git status --short Leo` is dirty
- **Commit discipline**: stage only **`Leo/`** for Leo commits; never use repo-wide `git add .` while unrelated monorepo changes exist; keep scratch Leo branches private and reintegrate them into `leo/v1.0-digital-vellum` before handoff
- **Tests**: **`cd Leo && swift test`** — SPM unit / logic tests only (no SwiftUI windows); includes **PDF → reflow EPUB** pipeline tests (`PDFConverterPipelineTests`). Same tests via Xcode after opening the package once:
  `xcodebuild test -workspace Leo/.swiftpm/xcode/package.xcworkspace -scheme Leo -destination 'platform=macOS'`.
- **UX tests (XCUITest)**: **`cd Leo && ./scripts/run-ux-tests.sh`** — runs **`build-app.sh`** then **`xcodebuild test`** on **`Leo/XcodeUX/LeoUX.xcodeproj`** (scheme **`LeoUX`**). Launches **`Leo/build/Leo.app`** by path; grant **Accessibility** to the test runner if macOS blocks automation.
- **UX tests via Xcode MCP** (when Cursor **Xcode** server is enabled, e.g. **`project-0-002-xcode`**): open **`Leo/XcodeUX/LeoUX.xcodeproj`** in Xcode, select scheme **`LeoUX`**, then use MCP tools **`RunAllTests`** / **`RunSomeTests`** (pass the workspace **`tabIdentifier`** from your Xcode window). Use **`GetBuildLog`** and the reported **`fullSummaryPath`** for failures—same tests as the CLI script, richer summaries and breakpoints.
- **UI-test-only launch env** (used by XCUITests): **`LEO_UI_TEST_BOOK_PATH`** — absolute path to **EPUB or PDF** to copy into the library and select; **`LEO_UI_TEST_SHOW_LOOKUP`** = `1` plus optional **`LEO_UI_TEST_LOOKUP_WORD`** (default `你好`) sets **`leo.reader.dictionarySmoke`** for **EPUB only** (PDF ignores it); **`LEO_UI_TEST_SEED_FSRS_CARD`** = `1` plus optional **`LEO_UI_TEST_FSRS_WORD`** seeds or refreshes a **due** `FSRSCard` for review-flow UI tests. Regenerate **`Leo/XcodeUX/LeoUITests/Fixtures/smoke.pdf`** with **`Leo/scripts/gen-smoke-pdf.swift`** if needed.
- **Build app**: `cd Leo && ./build-app.sh` → `Leo/build/Leo.app` (open that build, not only `swift run`, for real `Bundle.main` + embedded `web/`)
- **UI smoke** (fast gate — launch + process; optional window count via Accessibility): `cd Leo && ./scripts/ui-smoke.sh` — set `LEO_UI_SMOKE_SKIP_AX=1` for process-only if System Events is blocked.
- **WKWebView**: In debug, **Safari → Develop** shows the Foliate page when **`isInspectable`** is enabled (`FoliateReaderView`).
- **Autonomous verify loop**: (1) `cd Leo && swift test`; (2) `cd Leo && ./scripts/run-ux-tests.sh` or **Xcode MCP `RunAllTests`** on **`LeoUX`** when UI changed; (3) **`./scripts/ui-smoke.sh`** for a quick process launch; (4) triage → polish SwiftUI / **`accessibilityIdentifier`** → repeat.
- **Note**: PDF format is view-only; EPUB has full dictionary popup, Read aloud (TTS), reading layout popover in the reader toolbar, and Anki import/export (File menu + Settings → Anki)

### SyncReader (Tauri + Svelte)
- **Path**: `syncreader/`
- **Stack**: Tauri, Svelte 5, TypeScript

### Pomodoro (Reference web timer)
- **Path**: `pomodoro/`
- **Stack**: Next.js 16, React 19, TypeScript, shadcn/ui, Geist, IndexedDB (`idb`), Vitest, Playwright
- **Status**: Reference / donor app for timer architecture, persistence patterns, and e2e structure. New merged product work should go into `focus-node/`, not a parallel second focus app.
- **PRD**: `PRD-POMODORO.md`
- **Plan**: `plans/pomodoro.md`
- **Design / polish contract**: `pomodoro/docs/design-contract.md` (typography, phase affordances, motion, keyboard map)
- **Agent-driven UI testing**: `pomodoro/docs/agent-testing.md` — prefer **Cursor IDE Browser** MCP (`cursor-ide-browser`) when present in the project MCP descriptors; Playwright + `npm run verify` stay the repeatable CI-style gate; avoid relying on one unbounded agent terminal run.
- **Tests**: `cd pomodoro && npm test` (unit) · `cd pomodoro && npm run test:e2e:install` once · `npm run verify:e2e` (Playwright + prod server; **8 e2e tests** — smoke, user journey, exhaustive settings/timer/export clicks; script picks a free port and checks `<title>Pomodoro</title>` so a busy `:3000` cannot silently test the wrong app)
- **Full gate**: `cd pomodoro && npm run verify` (lint + unit + build + e2e script)
- **Split gate** (agent-friendly): `npm run verify:static` then `SKIP_E2E_BUILD=1 npm run verify:e2e`
- **Dev**: `cd pomodoro && npm run dev`

### Focus Node (Merged focus product)
- **Path**: `focus-node/`
- **Stack**: Vite 6, React 19, TypeScript, Tailwind CSS 4, `motion/react`, D3, Vitest, Playwright
- **Purpose**: Single merged focus product that absorbs the Pomodoro engine / test patterns into the former Google AI Studio Focus Node prototype.
- **Tests**: `cd focus-node && npm test` (Vitest engine tests) · `npm run test:e2e -- e2e/smoke.spec.ts e2e/focus-flow.spec.ts` (Playwright desktop + mobile flow checks)
- **Full gate**: `cd focus-node && npm run verify`
- **Dev**: `cd focus-node && npm run dev` (port `3001`)
- **Product boundary**: Keep the app centered on task planning, Pomodoro focus sessions, and browser-tested UX. The Gemini-powered `ThinkingMode` panel was intentionally removed because it distracted from the core app.

## Learned User Preferences
- Prefer running commands and automated tests in the repo over giving instructions-only replies when the environment allows shell access.
- For web apps, verify UX in a real browser when MCP browser tools are available; native macOS app targets (Tiempo, Adhan, Love, IMI, Leo) are not driven by browser automation in chat—combine `swift test` / local `.app` builds with **Xcode MCP** (when configured), XCUITest, Peekaboo, or manual UI review instead of implying click-through coverage from the browser MCP alone.
- For **Leo** UX verification and polish, use **Xcode MCP** (when available) and XCUITest to exercise **distinct** surfaces—EPUB and PDF paths, dictionary lookup, overlays, and FSRS—not repetitive clicks on the same elements; looping shallow actions is not sufficient coverage.
- Before stating that a capability is unavailable in-session, check workspace MCP tool descriptors (e.g. `cursor-ide-browser`) rather than relying only on the short server list in a system prompt.
- When the user reports no visible change in a macOS app, or cannot find or run the app, verify whether they are using `/Applications/…`, `swift run`, or a freshly built `.app`. **Leo** is a normal Dock app; **Tiempo, Adhan, Love, IMI** use `LSUIElement` and stay off the Dock—use their menu-bar icons. Align with rebuild/install notes per project in this file.
- When disabling or interrupting TTS on macOS (including Claude Code settings such as `CLAUDE_TTS_ENABLED`), stop in-flight playback explicitly (for example terminate `afplay` and related player processes) before or alongside changing settings; toggling configuration alone does not stop audio that is already playing.

## Learned Workspace Facts
- **Cursor + Xcode MCP:** This repo includes [`.cursor/mcp.json`](.cursor/mcp.json) registering the **`xcode`** server (`xcrun mcpbridge`, per [Apple’s guide](https://developer.apple.com/documentation/Xcode/giving-agentic-coding-tools-access-to-xcode)). In **Xcode → Settings → Intelligence**, turn on **Allow external agents to use Xcode tools**. Open the relevant project or package in **Xcode** before expecting MCP tools to drive builds/tests; Cursor loads project-level MCP when this workspace is open.
- `Leo/` — see **Leo (macOS Chinese immersive reader)** under Projects for commands and verification; threat model `Leo/leo-threat-model.md`.
- Pomodoro `scripts/run-e2e-with-server.sh` defaults to an ephemeral listen port and requires `<title>Pomodoro</title>` in the response so e2e cannot pass against an unrelated process on a fixed port.
- Pomodoro / Next.js allows only one `next dev` per project directory; a second instance can print a URL and then exit, so kill stale servers first and trust the still-running process.
- `focus-node/` is the merged successor for current focus-product work; use `pomodoro/` as a reference implementation, not as a second live app to evolve in parallel.
- Cursor documents long-running and background agents separately from a normal in-editor agent chat; access and behavior depend on plan and product surface, not a single universal mode.

## Architecture (Tiempo)

```
Tiempo/Sources/
  Engine/          — Business logic (@Observable, @MainActor)
    TimeEntryEngine.swift    — Timer start/stop/edit/delete
    ScheduleEngine.swift     — Weekly planner, blocks, templates
    AccountabilityEngine.swift — Plan vs actual scoring
    GoalsEngine.swift        — Goal progress calculation
  Models/          — SwiftData @Model classes
    Category.swift, TimeEntry.swift, Tag.swift,
    ScheduleTemplate.swift, ScheduledBlock.swift, Goal.swift
    SyncStatus.swift         — Enum for future Supabase sync
  Views/           — SwiftUI views (6 tabs)
    TrackingView.swift       — Category grid, active timer
    ScheduleView.swift       — Weekly planner + compare
    EventsView.swift         — Chronological entry list
    TimelineView.swift       — Charts (bar, pie, timeline)
    GoalsView.swift          — Goal progress bars
    CompareView.swift        — Plan vs actual (3 modes)
    MenuBarManager.swift     — macOS status bar
    FloatingTimerPanel.swift — Always-on-top timer
  Extensions/
    Color+Hex.swift
```

## Rules
- Read file before modifying it
- Run `swift test` after Tiempo/Adhan changes — all tests in the touched project must pass (Tiempo: see count under that project above)
- Never break existing tests
- Conventional commits: `feat(phase-N):`, `fix:`, `refactor:`
- Small changes (<100 lines per commit)

## Current Status
- Phases 1-8 complete (local-only, no Supabase sync yet)
- Phase 9 (Sync Engine) and Phase 10 (Polish) remaining
- App runs locally via `swift build -c release`
