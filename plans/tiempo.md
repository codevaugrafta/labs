# Plan: Tiempo — Personal Time Tracking & Schedule Accountability App

> Source PRD: `/Users/franciscodilussor/Documents/002/PRD-TIEMPO.md`

## Architectural Decisions

Durable decisions that apply across all phases:

- **Platform**: Native macOS app, Swift 6 strict concurrency, SwiftUI
- **Minimum target**: macOS 15 Sequoia (Tahoe features behind `@available`)
- **Data layer**: SwiftData with `@Model` classes, `ModelContainer` at app entry point
- **Schema**: 7 tables — `categories`, `tags`, `time_entries`, `time_entry_tags`, `schedule_templates`, `scheduled_blocks`, `goals`
- **ID strategy**: UUID on all models, generated client-side
- **Soft delete**: `deletedAt: Date?` on all models — no hard deletes except tombstone purging (90 days)
- **Auth**: Supabase Auth — Sign in with Apple (OAuth) + email/password. Optional — app works offline without auth.
- **Sync pattern**: SwiftData (local source of truth) + Supabase (cloud mirror) + DIY SyncEngine with `syncStatus` enum per record. LWW conflict resolution on server-side `updatedAt`.
- **Navigation**: 6-tab `TabView` — Tracking, Schedule (Plan|Compare segmented), Events, Timeline, Goals, Settings
- **Presentation surfaces**: Menu bar app + main window + floating widget — shared state via SwiftData `@Query`
- **Key models**: `Category`, `Tag`, `TimeEntry`, `ScheduleTemplate`, `ScheduledBlock`, `Goal`
- **Subcategories**: Max 1 level. Time rolls up to parent for goals/analytics.
- **Recurring schedules**: Template + materialized instances. 4-week horizon. Sticky exceptions.
- **Accountability formula**: Per-block adherence = min(actual/planned, 1.0). Daily = average of blocks. N/A for unplanned days.
- **No overlapping scheduled blocks** — enforced at creation time.

---

## Phase 1: First Timer

**User stories**: US-1, 2, 3 (partial), 6, 13, 14, 42 (basic)

### What to build

The minimum viable loop: create a category with a name and color → tap it in a grid to start a timer → see the timer ticking with elapsed time → tap again to stop → see the completed entry in a chronological events list. SwiftData models for `Category` and `TimeEntry` with all fields defined (including sync fields like `syncStatus`, `updatedAt`, `deletedAt`) even if sync isn't wired yet. The main window with 6 tabs stubbed out, but only Tracking and Events functional.

### Acceptance criteria

- [ ] Can create a category with custom name and color
- [ ] Tracking tab shows a grid of category tiles
- [ ] Tapping a tile starts a timer — tile shows elapsed time updating every second
- [ ] Tapping the active tile stops the timer and creates a TimeEntry
- [ ] Events tab shows a chronological list of completed entries with category, duration, start/end times
- [ ] Data persists across app relaunch (SwiftData)
- [ ] All 6 tabs exist in the tab bar (4 show placeholder empty states)
- [ ] SwiftData models include all fields from the schema (sync fields, soft delete) even if unused

---

## Phase 2: Sync Spike

**User stories**: US-55, 56, 57, 58, 59

### What to build

Prove the sync architecture end-to-end with categories only. Set up the Supabase project, create the `categories` table with RLS, configure Sign in with Apple and email auth. Build the SyncEngine prototype: upload pending local changes to Supabase, subscribe to Realtime for incoming changes, apply LWW conflict resolution. Create a second SwiftData container in a test to simulate a "second device" pulling data. This phase is a 2-3 day spike — the goal is proving the architecture, not building a production sync engine.

### Acceptance criteria

- [ ] Supabase project created with `categories` table + RLS policies (`user_id = auth.uid()`)
- [ ] Sign in with Apple OAuth configured in Supabase + Apple Developer account
- [ ] Email/password auth works as fallback
- [ ] App can sign in and sign out
- [ ] Creating a category locally sets `syncStatus = .pendingCreate`
- [ ] SyncEngine pushes pending categories to Supabase when online
- [ ] SyncEngine receives Realtime changes and inserts into local SwiftData
- [ ] LWW conflict resolution works (later `updatedAt` wins)
- [ ] App works fully offline — timer and categories functional with no network
- [ ] Unsigned-in state shows "Sign in to enable sync" — app is usable without auth

---

## Phase 3: Full Tracking

**User stories**: US-1a, 7, 8, 9, 10, 11, 12, 15, 16, 17, 18, 19, 19a

### What to build

Complete the tracking experience. Retroactive entry creation (pick category, set start/end time manually). Edit any entry (change times, category, notes). Delete entries (soft delete). Notes field on entries. Tags system (CRUD, assign to entries, junction model). Subcategories (parent_id, 1-level max, display as grouped/nested in the tracking grid). Category archive, reorder (drag in grid), icon assignment (emoji picker). Concurrent timer toggle (setting that allows/prevents multiple running timers). Timer crash recovery (detect orphaned running timers on launch, prompt user). Block category deletion when entries exist (suggest archive).

### Acceptance criteria

- [ ] Can add retroactive entries with manual start/end time and category
- [ ] Can edit any past entry (times, category, notes)
- [ ] Can delete entries (soft delete — disappears from UI, `deletedAt` set)
- [ ] Can add text notes to any entry
- [ ] Can create/manage tags and assign them to entries
- [ ] Can create subcategories (Work → Deep Focus) — max 1 level
- [ ] Subcategories display grouped under parent in tracking grid
- [ ] Can archive categories (hidden from grid, data preserved)
- [ ] Can reorder categories in the grid via drag
- [ ] Can assign emoji icons to categories
- [ ] Concurrent timer toggle works (on: multiple timers allowed, off: starting new stops current)
- [ ] On launch, if a timer was running during a crash, user is prompted to keep or trim it
- [ ] Deleting a category with existing entries is blocked — archive suggested instead

---

## Phase 4: macOS Chrome

**User stories**: US-4, 5, 50, 51, 52, 68

### What to build

The three presentation surfaces beyond the main window. Menu bar: persistent icon showing active timer's category color dot + elapsed time, click to expand dropdown with start/stop button and recent 5 categories for quick switching. Floating widget: small always-on-top `NSPanel` window showing active timer with category name, color, and elapsed time — draggable, dismissible, reappears on timer start. Global keyboard shortcuts: configurable hotkeys for start/stop current timer, registered via `NSEvent.addGlobalMonitorForEvents` with Accessibility permission. Launch-at-login via `SMAppService`. First-launch flow for Accessibility permission with clear explanation.

### Acceptance criteria

- [ ] Menu bar icon shows category color dot + elapsed time when timer is running
- [ ] Menu bar dropdown lists recent categories for one-click start
- [ ] Menu bar dropdown has stop button for current timer
- [ ] Floating widget appears as always-on-top window with active timer info
- [ ] Floating widget is draggable and dismissible
- [ ] Global hotkey starts/stops timer from any app
- [ ] Accessibility permission prompt is explained clearly on first trigger
- [ ] Launch-at-login toggle works via SMAppService
- [ ] All three surfaces (menu bar, widget, main window) stay in sync via SwiftData @Query

---

## Phase 5: Weekly Planner

**User stories**: US-20, 21, 22, 23, 24, 25, 26, 27, 28, 74

### What to build

The schedule planning system — the app's biggest technical challenge. SwiftData models for `ScheduleTemplate` and `ScheduledBlock`. A calendar-like day/week view built with custom SwiftUI `Canvas` or `GeometryReader` where blocks are colored rectangles that can be created by click-drag, moved by drag, and resized by dragging edges. Each block has a category, start/end time, and objectives (description text field or checklist with add/remove/check items). Recurring templates: create a template, toggle "repeat weekly", system materializes blocks for 4 weeks forward. Edit a single block → detaches as exception (`is_exception = true`). Schedule tab with segmented control: Plan mode (create/edit) and Compare mode (placeholder for Phase 6). Week navigation (prev/next week arrows). Keyboard accessibility: arrow keys to move blocks, shift+arrows to resize.

### Acceptance criteria

- [ ] Schedule tab shows a day/week calendar grid with time slots
- [ ] Can create blocks by click-dragging on empty time slots
- [ ] Can move blocks by dragging them
- [ ] Can resize blocks by dragging their edges
- [ ] Overlapping blocks are rejected with visual feedback
- [ ] Each block shows category color, name, and time range
- [ ] Can set block objectives as description or checklist
- [ ] Checklist items can be added, removed, and checked off
- [ ] Can create a recurring template — blocks repeat weekly
- [ ] Editing a single recurring block detaches it as an exception
- [ ] 4-week materialization horizon maintained on app launch
- [ ] Week navigation works (prev/next)
- [ ] Schedule tab has Plan|Compare segmented control (Compare is placeholder)
- [ ] Keyboard navigation works for block creation and manipulation

---

## Phase 6: Plan vs. Actual (★★ The Differentiator)

**User stories**: US-29, 30, 31, 32, 33, 34, 35, 35a, 35b, 35c

### What to build

The accountability engine — the reason this app exists. Implement the accountability score formula from the PRD spec (per-block adherence, daily average, N/A for unplanned days). Build the Compare mode in the Schedule tab with three sub-views: side-by-side (planned blocks on left, actual entries on right for a given day), overlay (planned blocks as outlined rectangles, actual time as filled color within them), and score card (daily score + block-by-block status labels: on track, partial, skipped, late start, early end, exceeded). Weekly accountability trend line chart. Midnight boundary splitting (view-layer — entries crossing midnight are logically split for daily views). Unscheduled time display. Miscellaneous toggle for unassigned time.

### Acceptance criteria

- [ ] Compare mode shows three sub-views: Side-by-side, Overlay, Score Card
- [ ] Side-by-side view displays planned blocks alongside actual tracked entries for a day
- [ ] Overlay view shows planned blocks as outlines with actual time filled in
- [ ] Daily accountability score is calculated per the PRD formula
- [ ] Block status labels are correct: On track, Partial, Skipped, Late start, Early end, Exceeded
- [ ] Late start / Early end thresholds use user-configurable minutes (default 10)
- [ ] Weekly accountability trend shows as a line chart
- [ ] Days with no schedule show "No plan for this day" with score = N/A
- [ ] N/A days are excluded from weekly average
- [ ] Entries crossing midnight are split at 00:00 for daily views
- [ ] Unscheduled tracked time appears labeled as "Unscheduled"
- [ ] Miscellaneous toggle assigns unscheduled time to a designated category

---

## Phase 7: Analytics & Charts

**User stories**: US-43, 44, 45, 46, 47, 48, 49

### What to build

The visualization layer. Horizontal timeline view: custom `Canvas`-based view showing colored blocks for each entry in a day, scrollable across days/weeks (similar to Timelines app's timeline view). Pie chart: time distribution across categories for a selected date range (Swift Charts `SectorMark`). Stacked bar chart: daily/weekly totals stacked by category (Swift Charts `BarMark`). Date range selector: day, week, month, custom range picker. Category and tag filter controls. CSV export: all entries in the selected range as a CSV file with columns (id, category, subcategory, tags, started_at, ended_at, duration_minutes, note). PDF export: formatted report of the current visualization view.

### Acceptance criteria

- [ ] Horizontal timeline shows colored blocks per day, scrollable
- [ ] Pie chart shows category time distribution for selected range
- [ ] Stacked bar chart shows daily totals by category
- [ ] Date range picker works: day, week, month, custom
- [ ] Category filter: toggle categories on/off in all charts
- [ ] Tag filter: filter entries by tag
- [ ] CSV export produces a valid CSV with all entry fields
- [ ] PDF export produces a formatted report of the current view
- [ ] All charts update reactively when new entries are added

---

## Phase 8: Goals

**User stories**: US-36, 37, 38, 39, 40, 41

### What to build

Goal definition and progress tracking. Goal CRUD: create a goal with a target category, target minutes, and period (daily/weekly/monthly). Goals tab shows active goals with progress bars. Progress calculation: sum tracked minutes for the goal's category (including subcategories rolling up to parent) within the current period. Period boundaries respect the user's first-day-of-week setting. Percentage display. Checkmark/visual indicator when goal is met (>= 100%). Exceeded goals show the actual amount.

### Acceptance criteria

- [ ] Can create daily, weekly, and monthly goals for any category
- [ ] Goals tab shows all active goals with progress bars
- [ ] Progress bar fills based on actual tracked time vs. target
- [ ] Percentage is displayed (e.g., "65% of 30 min")
- [ ] Subcategory time rolls up to parent category for goal progress
- [ ] Weekly goals respect the configured first-day-of-week
- [ ] Goals met (>= 100%) show a checkmark indicator
- [ ] Can edit and delete goals
- [ ] Goals persist and survive app relaunch

---

## Phase 9: Full Sync Engine

**User stories**: US-59a, 59b, 59c

### What to build

Expand the Phase 2 sync spike to production quality across all 7 tables. Batch initial sync for new devices (pull all records on first sign-in). Running timer sync: when a timer starts on one device, other devices see it as running with live elapsed time via Realtime subscription. Stop-from-another-device: stopping a running timer from any device applies correctly everywhere. Tombstone purging: on app launch, hard-delete records where `deletedAt` > 90 days ago from both local and remote. Sleep/wake reconnection: subscribe to `NSWorkspace` notifications, reconnect Realtime WebSocket on wake, run incremental sync. Retry with exponential backoff (1s, 2s, 4s, 8s, max 60s). Server-side `updated_at` via Supabase `DEFAULT now()` for canonical timestamps.

### Acceptance criteria

- [ ] All 7 tables sync bidirectionally (categories, tags, time_entries, time_entry_tags, schedule_templates, scheduled_blocks, goals)
- [ ] New device initial sync pulls all historical data on first sign-in
- [ ] Running timer appears as running on other devices with live elapsed time
- [ ] Stopping a timer from any device stops it everywhere (no phantom timers)
- [ ] Tombstone purging runs on launch — records deleted > 90 days are hard-deleted
- [ ] Sleep/wake cycle reconnects Realtime and runs incremental sync
- [ ] Offline changes queue correctly and sync on reconnection
- [ ] Exponential backoff on network failures (observable in logs)
- [ ] No data loss under any tested network condition (airplane mode toggle, sleep/wake, force-quit)

---

## Phase 10: Polish & Ship

**User stories**: US-53, 54, 60, 61, 62, 63, 64, 65, 66, 67, 69, 70, 71, 72, 73

### What to build

Everything that makes the app feel complete. Settings panel: first day of week, default launch tab, notification preferences, concurrent timer toggle, appearance override (system/dark/light), late start/early end thresholds. Onboarding: first-launch welcome with 5 starter categories, skip option. Empty states: contextual CTAs on all 6 tabs when empty. Cmd+Z undo for destructive actions (delete entry, move block, detach exception). Schedule reminders: macOS notifications N minutes before a scheduled block starts. VoiceOver support across all views. Keyboard navigation in the tracking grid. Keyboard alternative for schedule drag-resize. System appearance respect + dark mode override toggle.

### Acceptance criteria

- [ ] Settings panel with all configurable options (first-day, default tab, notifications, concurrent toggle, appearance, thresholds)
- [ ] First-launch onboarding creates 5 starter categories with colors
- [ ] Skip option bypasses onboarding
- [ ] All 6 tabs show contextual empty states with CTAs when empty
- [ ] Cmd+Z undoes: delete entry, move block, resize block, detach exception
- [ ] Schedule reminders fire as macOS notifications before block start time
- [ ] VoiceOver reads all interactive elements correctly
- [ ] Tracking grid is navigable via arrow keys + Enter/Space
- [ ] Schedule calendar supports keyboard block creation/movement/resize
- [ ] Appearance follows system by default, with dark mode override option
- [ ] App feels native — no custom chrome, SF Pro/Mono typography, SF Symbols throughout
