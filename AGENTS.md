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

### Adhan (macOS Prayer Times)
- **Path**: `Adhan/`
- **Stack**: Swift 6.2+ (swift-tools-version 6.2), SwiftUI, SwiftData, adhan-swift (pinned revision), AVFoundation, UserNotifications
- **Tests**: `cd Adhan && swift test` — 16 tests (PrayerTimesEngine, PrayerTimeEntry + Iqamah, Hijri, mosque URL, recitation fallback)
- **Build app**: `cd Adhan && ./build-app.sh` → `build/Adhan.app` (release)
- **Logs**: Console filter `subsystem:com.adhan.prayer-times`
- **“Update Swift + app” (Adhan only — not Tiempo)**:
  1. **Swift / SPM**: Keep `Adhan/Package.swift` `swift-tools-version` in sync with your Xcode Swift; run `cd Adhan && swift package update`.
  2. **App bundle**: Bump `Adhan/Sources/Resources/Info.plist` `CFBundleShortVersionString` and `CFBundleVersion` when shipping user-visible changes.
  3. **Ship**: `cd Adhan && swift test && ./build-app.sh`, then replace `Adhan.app` in `/Applications/` (quit Adhan first).
  4. **Do not use `swift run` to verify menu-bar / notification behavior** — `Bundle.main` points at `.build/…`, not `Adhan.app`. Use `./run-app.sh` or `open build/Adhan.app` (or `/Applications/Adhan.app`). The menu’s first row shows version and `Adhan.app` vs `debug / swift run`.

### SyncReader (Tauri + Svelte)
- **Path**: `syncreader/`
- **Stack**: Tauri, Svelte 5, TypeScript

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
- Run `swift test` after changes — all 50 tests must pass
- Never break existing tests
- Conventional commits: `feat(phase-N):`, `fix:`, `refactor:`
- Small changes (<100 lines per commit)

## Current Status
- Phases 1-8 complete (local-only, no Supabase sync yet)
- Phase 9 (Sync Engine) and Phase 10 (Polish) remaining
- App runs locally via `swift build -c release`
