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

### SyncReader (Tauri + Svelte)
- **Path**: `syncreader/`
- **Stack**: Tauri, Svelte 5, TypeScript

### Pomodoro (Web focus timer)
- **Path**: `pomodoro/`
- **Stack**: Next.js 16, React 19, TypeScript, shadcn/ui, Geist, IndexedDB (`idb`), Vitest, Playwright
- **PRD**: `PRD-POMODORO.md`
- **Plan**: `plans/pomodoro.md`
- **Design / polish contract**: `pomodoro/docs/design-contract.md` (typography, phase affordances, motion, keyboard map)
- **Agent-driven UI testing**: `pomodoro/docs/agent-testing.md` — prefer **Cursor IDE Browser** MCP (`cursor-ide-browser`) when present in the project MCP descriptors; Playwright + `npm run verify` stay the repeatable CI-style gate; avoid relying on one unbounded agent terminal run.
- **Tests**: `cd pomodoro && npm test` (unit) · `cd pomodoro && npm run test:e2e:install` once · `npm run verify:e2e` (Playwright + prod server; **8 e2e tests** — smoke, user journey, exhaustive settings/timer/export clicks; script picks a free port and checks `<title>Pomodoro</title>` so a busy `:3000` cannot silently test the wrong app)
- **Full gate**: `cd pomodoro && npm run verify` (lint + unit + build + e2e script)
- **Split gate** (agent-friendly): `npm run verify:static` then `SKIP_E2E_BUILD=1 npm run verify:e2e`
- **Dev**: `cd pomodoro && npm run dev`

## Learned User Preferences
- Prefer running commands and automated tests in the repo over giving instructions-only replies when the environment allows shell access.
- When discussing interactive UI verification, distinguish this chat’s tool surface from Cursor Agent Browser, Playwright in CI, and long-running cloud agents unless the user’s plan explicitly includes those.
- Before stating that a capability is unavailable in-session, check workspace MCP tool descriptors (e.g. `cursor-ide-browser`) rather than relying only on the short server list in a system prompt.
- When the user reports no visible change in a macOS app, verify whether they are using `/Applications/…`, `swift run`, or a freshly built `.app`, and align with the rebuild/install notes in this file.

## Learned Workspace Facts
- Pomodoro `scripts/run-e2e-with-server.sh` defaults to an ephemeral listen port and requires `<title>Pomodoro</title>` in the response so e2e cannot pass against an unrelated process on a fixed port.
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
