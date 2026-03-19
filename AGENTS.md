# Labs Monorepo — Agent Instructions

This file is read by both Cursor and Claude Code agents.

## Projects

### Tiempo (macOS Time Tracker)
- **Path**: `Tiempo/`
- **Stack**: Swift 6, SwiftUI, SwiftData, Swift Charts
- **PRD**: `PRD-TIEMPO.md` (82 user stories, reviewed 3x)
- **Plan**: `plans/tiempo.md` (10 phases, 8 complete locally)
- **Tests**: `cd Tiempo && swift test` — 50 tests across 7 suites
- **Build**: `cd Tiempo && swift build`
- **Run**: `cd Tiempo && swift build -c release && open .build/release/Tiempo`

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
