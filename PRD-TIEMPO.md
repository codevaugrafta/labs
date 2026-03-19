# PRD: Tiempo — Personal Time Tracking & Schedule Accountability App

## Problem Statement

I track my time manually or not at all, which means I have no real understanding of where my day actually goes. Existing time tracking apps like Timelines ($10/month) charge a subscription for features that are fundamentally simple — start a timer, stop a timer, see where the time went.

More critically, no existing app solves my core problem: **I want to plan my day in advance as time-blocked segments and then track my actual time against that plan, seeing the disparity between intention and reality.** This is about accountability — knowing not just what I did, but how it compared to what I committed to doing.

I need this primarily on my MacBook (macOS 26 Tahoe), with future expansion to iPhone 15 Plus and Apple Watch. Timelines doesn't even have a native Mac app yet — it's still on their roadmap.

## Solution

**Tiempo** is a native macOS app built with SwiftUI that combines time tracking with schedule planning. It uses SwiftData for local-first persistence and Supabase for cloud sync across devices.

The app has three core modes of operation:

1. **Track** — Start/stop timers against color-coded categories with one click. Track from the menu bar, a floating widget, or the main window. Add retroactive entries for forgotten activities.

2. **Plan** — Create weekly schedules on Sunday (or any day) as time-blocked segments. Each block is assigned to a category with either a description or a checklist of objectives. Blocks can recur week-to-week.

3. **Compare** — See the difference between what was planned and what actually happened. Side-by-side view, overlay view, or a daily/weekly accountability score. This is the feature no competitor offers.

The app is personal-use, single-user, Apple-ecosystem. No teams, no invoicing, no billing integration.

## User Stories

### Core Tracking

1. As a user, I want to start a timer for a category with one click, so that tracking has near-zero friction.
1a. As a user, when I reopen the app after a crash or force-quit while a timer was running, I want to be prompted with "You were tracking [Category] — it's been running since [time]. Keep it or trim to [last-known-active]?" so that I don't lose data or get inaccurate entries.
2. As a user, I want to stop the current timer with one click, so that I don't forget to close it.
3. As a user, I want to see the currently running timer and its elapsed time at all times (menu bar, floating widget, main window), so that I'm always aware of what I'm tracking.
4. As a user, I want to start/stop timers from the macOS menu bar, so that I can track without switching away from my current app.
5. As a user, I want a floating always-on-top timer widget, so that I can see my active timer while working in other apps.
6. As a user, I want to track time from the main application window in a grid layout of category tiles, so that I can quickly select any category.
7. As a user, I want to add a retroactive time entry (e.g., "I exercised from 7am-8am"), so that I can record activities I forgot to track in real-time.
8. As a user, I want to edit any past time entry (change start/end time, category, notes), so that I can correct mistakes.
9. As a user, I want to delete time entries, so that I can remove erroneous data.
10. As a user, I want to toggle whether concurrent timers are allowed, so that I can track overlapping activities (e.g., Commuting + Studying) when it makes sense but prevent it when it doesn't.
11. As a user, I want to add a text note to any time entry, so that I can record what specifically I was doing.
12. As a user, I want to assign tags to time entries, so that I can add cross-cutting metadata (e.g., "deep-work", "urgent", "client-X") beyond the category.

### Categories & Organization

13. As a user, I want to create unlimited categories with custom names and colors, so that I can organize my time however I want.
14. As a user, I want to choose specific colors for each category from a palette, so that my tracking view is visually meaningful to me.
15. As a user, I want to create subcategories (e.g., Work → Meetings, Work → Deep Focus), so that I can track at a finer granularity without cluttering the top level. **Subcategory rules**: Nesting is limited to 1 level (no sub-subcategories). Time tracked to a subcategory automatically counts toward its parent for goals and analytics aggregation. Scheduled blocks and goals can target either a parent or a subcategory. A goal on "Work" includes all time from "Work → Meetings", "Work → Deep Focus", etc.
16. As a user, I want to create and manage tags, so that I can cross-reference entries across categories.
17. As a user, I want to archive unused categories (not delete), so that historical data is preserved but my active view stays clean.
18. As a user, I want to reorder categories in the tracking grid, so that my most-used categories are easiest to reach.
19. As a user, I want to assign icons to categories (emoji or SF Symbols), so that they're visually distinguishable at a glance.
19a. As a user, when I try to delete a category that has associated time entries, scheduled blocks, or goals, I want the app to block the deletion and suggest archiving instead, so that I don't accidentally orphan historical data.

### Schedule Planning (★ Differentiator)

20. As a user, I want to create a weekly schedule by defining time-blocked segments assigned to categories, so that I plan my week intentionally.
21. As a user, I want each scheduled block to have a start time, end time, and assigned category, so that my plan is specific and actionable.
22. As a user, I want to choose whether a scheduled block's objective is a description ("Deep work on the API") or a checklist (["Design the schema", "Write migration", "Test endpoints"]), so that I can define objectives in the format that fits.
23. As a user, I want to check off individual checklist items within a scheduled block as I complete them, so that I can track progress within a block.
24. As a user, I want to mark a recurring schedule that repeats week-to-week, so that I don't have to recreate my weekly template from scratch.
25. As a user, I want to edit individual blocks in a recurring schedule without affecting future weeks, so that I can handle exceptions.
26. As a user, I want to create my schedule for the upcoming week on Sunday, so that I start Monday with a clear plan.
27. As a user, I want to view my schedule for any day/week, so that I can review past plans.
28. As a user, I want to drag and resize blocks in a calendar-like view to adjust my schedule, so that planning is visual and intuitive.

### Plan vs. Actual Comparison (★★ Core Differentiator)

29. As a user, I want to see a side-by-side view of my planned schedule and my actual tracked time for any day, so that I can compare intention to reality.
30. As a user, I want to see an overlay view where planned blocks are outlines and actual time is filled in, so that I can see gaps and overlaps at a glance.
31. As a user, I want a daily accountability score (e.g., "78% adherence"), so that I can quantify how well I followed my plan.
32. As a user, I want to see weekly accountability trends, so that I can track whether my adherence is improving over time.
33. As a user, I want unscheduled time that was tracked to appear clearly labeled as "unscheduled", so that I can see time I spent on things I didn't plan.
34. As a user, I want to assign unscheduled time to a "miscellaneous" category via a toggle, so that all time in a day is accounted for.
35. As a user, I want to see which scheduled blocks I started late, ended early, skipped entirely, or exceeded, so that I can identify specific patterns in my schedule adherence.
35a. As a user, when a time entry crosses midnight (e.g., started 11:30pm, ended 1:00am), I want it split at the midnight boundary for daily views, so that each day's accountability score only counts time that occurred on that day.
35b. As a user, on days where I have no schedule defined, I want the Compare view to show "No plan for this day" with all tracked time listed as unscheduled, so that the view is never empty or confusing.
35c. As a user, I want the accountability score for days without a schedule to be N/A (not 0% or 100%), so that unplanned days don't distort my weekly trends.

### Goals

36. As a user, I want to define daily goals (e.g., "Exercise: 30 min/day"), so that I can set targets for how much time I spend on a category.
37. As a user, I want to define weekly goals (e.g., "Work: 30 hours/week"), so that I can set longer-horizon targets.
38. As a user, I want to define monthly goals, so that I can track long-term time allocation.
39. As a user, I want to see progress bars for each goal showing current vs. target, so that I know at a glance whether I'm on track.
40. As a user, I want to see percentage completion for each goal (e.g., "65% of 20 min"), so that the progress is quantified.
41. As a user, I want a checkmark or visual indicator when a goal is met or exceeded, so that I get positive reinforcement.

### Visualizations

42. As a user, I want an events log (chronological list of all time entries), so that I can see exactly what I tracked and when.
43. As a user, I want a horizontal timeline view showing colored blocks for each day's activities, so that I can see my day at a glance.
44. As a user, I want a pie chart showing time distribution across categories for any date range, so that I can see proportional allocation.
45. As a user, I want stacked bar charts showing daily/weekly totals broken down by category, so that I can see trends over time.
46. As a user, I want to filter all visualizations by category, subcategory, or tag, so that I can focus on what matters.
47. As a user, I want to select different date ranges (day, week, month, custom) for all visualizations, so that I can analyze any period.
48. As a user, I want to export my data as CSV, so that I can analyze it externally.
49. As a user, I want to export reports as PDF, so that I can share or archive them.

### macOS Integration

50. As a user, I want keyboard shortcuts to start/stop timers and switch categories, so that I can track without using the mouse.
51. As a user, I want the menu bar icon to show the currently active timer's category color and elapsed time, so that tracking status is always visible.
52. As a user, I want the app to launch at login optionally, so that tracking is always available.
53. As a user, I want macOS notifications when a scheduled block is about to start, so that I'm reminded to switch activities.
54. As a user, I want the app to respect macOS appearance (light/dark mode), so that it feels native.

### Sync & Data

55. As a user, I want my data to sync across all my Apple devices via Supabase, so that I can start a timer on my Mac and see it on my iPhone.
56. As a user, I want the app to work fully offline, so that tracking is not interrupted by network issues.
57. As a user, I want changes made offline to sync automatically when connectivity is restored, so that I never lose data.
58. As a user, I want to sign in with my Apple ID (via Sign in with Apple OAuth) or email/password, so that my data is tied to my identity. **Implementation note**: Sign in with Apple requires Apple Developer account configuration (associated domains, Service ID) and Supabase OAuth provider setup. The app can be used fully offline without signing in — auth is required only to enable sync. Unsigned-in state: all data is local-only, sync UI shows "Sign in to enable sync across devices."
59. As a user, I want all my data to be private and secured with row-level security, so that nobody else can access it.
59a. As a user, when I install the app on a new device and sign in, I want all my historical data to be pulled down automatically (initial bulk sync), so that the new device is immediately useful.
59b. As a user, when I start a timer on one device and open the app on another device, I want to see that timer as running with its live elapsed time, so that the experience is seamless across devices.
59c. As a user, when I stop a running timer from a different device than the one that started it, I want the stop to be applied correctly everywhere, so that there are no phantom running timers.

### Settings

60. As a user, I want to configure the first day of the week (Sunday or Monday), so that weekly views match my preference.
61. As a user, I want to configure the default view on launch (Tracking, Schedule, Events, Timeline, Goals), so that I see what's most relevant.
62. As a user, I want to configure notification preferences (reminders on/off, reminder lead time), so that I'm not overwhelmed.
63. As a user, I want to configure the concurrent timer toggle globally, so that it applies to all tracking.
64. As a user, I want to override the system appearance to force dark mode in Tiempo, so that I can use a dark dashboard aesthetic regardless of my macOS setting.
65. As a user, I want to configure the "late start" and "early end" thresholds (default 10 minutes) for the accountability score labels, so that I can adjust sensitivity to my workflow.

### Onboarding & Empty States

66. As a user, on first launch I want a brief welcome flow that creates 3-5 starter categories (Work, Exercise, Study, Personal, Break) with pre-assigned colors, so that I can start tracking immediately without setup friction.
67. As a user, I want the option to skip the welcome flow and create categories from scratch, so that I'm not forced into defaults.
68. As a user, on first launch I want the Accessibility permission prompt for global hotkeys to be explained clearly ("Tiempo needs Accessibility access to let you start/stop timers from any app"), so that I understand why I'm granting the permission.
69. As a user, on any empty tab (Schedule with no plan, Goals with no goals, Events with no entries, Timeline with no data), I want to see a contextual empty state with a call-to-action ("Create your first weekly plan", "Set a goal", etc.), so that I know what to do next.
70. As a user, I want Cmd+Z to undo the most recent destructive action (delete entry, move/resize block, detach from template), so that accidental changes are recoverable.

### Accessibility

71. As a user, I want full VoiceOver support across all views, so that the app is usable with screen readers.
72. As a user, I want keyboard navigation within the tracking grid (arrow keys to select, Enter/Space to start/stop), so that I can track without a mouse or trackpad.
73. As a user, I want the schedule calendar drag-resize view to have a keyboard alternative (select block, use arrow keys to move, Shift+arrow to resize), so that the planner is accessible without precise mouse control.

### Schedule Tab Internal Navigation

74. As a user, I want the Schedule tab to have a segmented control (Plan | Compare) at the top, so that I can clearly switch between creating/editing my schedule and reviewing plan-vs-actual.

## Implementation Decisions

### Tech Stack

- **Language**: Swift 6 with strict concurrency
- **UI Framework**: SwiftUI (macOS 26 Tahoe native)
- **Local Persistence**: SwiftData (SQLite under the hood)
- **Cloud Backend**: Supabase (PostgreSQL + Auth + Realtime)
- **Charts**: Swift Charts framework
- **Networking**: supabase-swift SDK (official)
- **Connectivity**: NWPathMonitor (Network framework)
- **Target**: macOS 15 Sequoia minimum (for App Store compatibility), macOS 26 Tahoe features behind `@available` checks. Apple Silicon only (M1 Pro and later).

### Accountability Score Formula (★★ Critical Specification)

The accountability score measures how closely actual tracked time matches the planned schedule for a given day. It is the average adherence across all scheduled blocks.

**Per-block adherence** is calculated as:

```
For each scheduled block B with planned category C, start S, end E:
  planned_minutes = E - S
  actual_minutes  = total time tracked to category C that overlaps [S, E]
  block_adherence = min(actual_minutes / planned_minutes, 1.0)
```

- A block **fully met** (worked the full planned duration in the correct category) scores **1.0** (100%).
- A block **partially met** (worked 45 of 60 planned minutes) scores **0.75** (75%).
- A block **skipped** (0 minutes tracked to that category in the block window) scores **0.0** (0%).
- A block **exceeded** is capped at **1.0** for the score calculation — no bonus for overtime. However, the raw actual_minutes value is preserved separately for the "Exceeded" status label (see below).
- Time tracked to a **different category** during a scheduled block does not count toward that block.
- **Unscheduled tracked time** is neutral — it does not penalize or bonus the score.

**Daily accountability score**:

```
daily_score = sum(block_adherence for all blocks) / count(blocks)
```

- If no blocks are scheduled for a day, the score is **N/A** (not 0%, not 100%).
- Weekly score is the average of all non-N/A daily scores in the week.

**Block status labels** (for US-35) — these are independent of the score and based on raw data:
- **On track**: block_adherence >= 0.9 AND actual_minutes <= planned_minutes * 1.1
- **Partial**: 0.1 <= block_adherence < 0.9
- **Skipped**: block_adherence < 0.1
- **Late start**: actual first tracked time for category C within [S, E] is > S + 10 minutes (threshold user-configurable in Settings)
- **Early end**: actual last tracked time for category C within [S, E] is < E - 10 minutes (threshold user-configurable in Settings)
- **Exceeded**: actual_minutes > planned_minutes * 1.1 (scores 1.0 for adherence, but displayed as "Exceeded" in the block detail view to distinguish from "On track")

Note: "On track" and "Exceeded" are both adherence >= 1.0, but the status label distinguishes them using the 110% threshold. This ensures the UI clearly separates "hit the target" from "went significantly over."

**Overlapping scheduled blocks**: The system prevents overlapping blocks at creation time. If a user tries to create or drag a block that overlaps an existing block on the same day, the action is rejected with a visual indicator. This avoids the double-counting problem in the accountability formula.

**Midnight boundary rule**: Time entries spanning midnight are logically split at 00:00 for daily views. Each fragment is attributed to its respective calendar day. The original entry is not modified — the split is a view-layer calculation.

### Recurring Schedule Data Model

Recurring schedules use a **template + materialized instances** pattern:

- A `schedule_template` defines a reusable weekly pattern (series of blocks that repeat).
- When the user creates a recurring schedule, the system materializes `scheduled_blocks` for each future week from the template.
- Editing a single instance detaches it from the template (`template_id` is set to NULL, `is_exception` = true). The template continues generating future weeks without that exception.
- Editing the template regenerates future un-materialized weeks. Already-materialized weeks where `is_exception = false` on ALL blocks are also regenerated. Weeks containing ANY block with `is_exception = true` are left untouched entirely.
- **Exception status is sticky**: once a block is manually edited (even if changed back to match the template), `is_exception = true` is permanent for that block. To "reset" an exception, the user explicitly deletes the block, and the template regenerates it fresh.
- **Materialization horizon**: 4 weeks forward from the current date. A weekly maintenance pass (on app launch) materializes new weeks as they come into the 4-week window and is safe against tombstone purging (90-day retention >> 4-week horizon).

This avoids the complexity of RFC 5545-style recurrence rules while supporting the core use case of "same schedule every week, with occasional exceptions."

### Architecture: Local-First with DIY Sync

- **SwiftData is the source of truth.** All UI reads from and writes to SwiftData. The app is fully functional offline.
- **Supabase is the cloud mirror.** A background Sync Engine pushes local changes to Supabase and pulls remote changes via Realtime subscriptions.
- **Each record carries a `syncStatus`** enum: `.synced`, `.pendingCreate`, `.pendingUpdate`, `.pendingDelete`.
- **Conflict resolution**: Last-write-wins using `updatedAt` timestamps. Sufficient for single-user multi-device.
- **Soft deletes** on all tables (`deleted_at` timestamp) to prevent sync issues with hard deletes.

### Deep Modules

1. **Time Entry Engine** — Manages the state machine of starting, stopping, and editing timers. Handles concurrent timer toggle. Interface: `start(category)`, `stop()`, `addRetroactive(category, start, end)`, `edit(entry, changes)`.

2. **Schedule Planner** — Creates and manages weekly time-blocked schedules. Handles recurring templates and per-block objectives (description or checklist). Produces plan-vs-actual diffs. Interface: `createWeekPlan(date, blocks)`, `getPlannedDay(date)`, `diffPlanVsActual(date)`.

3. **Category System** — CRUD for categories, subcategories, tags, and colors. Handles archive, sort order, icon assignment. Interface: standard CRUD.

4. **Analytics Engine** — Aggregates time entries into chart-ready data. Produces summaries, trends, distributions, and accountability scores. Interface: `summary(range, groupBy)`, `trends(range, granularity)`, `distribution(range)`, `accountabilityScore(date)`.

5. **Goals Tracker** — Manages goal definitions and calculates progress against tracked time entries. Interface: `createGoal(category, target, period)`, `progress(goal)`.

6. **SwiftData Persistence** — Local source of truth. Schema mirrors Supabase tables. All model definitions and migrations live here.

7. **Sync Engine** — The critical infrastructure module (~1,500-3,000 lines). Monitors connectivity (NWPathMonitor), manages the upload queue (pending changes → Supabase), processes the download stream (Realtime → SwiftData), handles conflict resolution (LWW on `updatedAt`), retry with exponential backoff, batch initial sync for new devices, tombstone purging (periodic cleanup of soft-deleted records older than 90 days), and sleep/wake WebSocket reconnection on macOS. Interface: `startSync()`, `stopSync()`, `forceSync()`, `syncStatus(for: record) → SyncStatus`. Requires careful Swift 6 actor isolation — background sync work runs on a dedicated `ModelActor`.

8. **Supabase Client** — Thin wrapper around the `supabase-swift` SDK. Configures URL/key, manages auth state, provides typed CRUD operations and Realtime channel management.

### Database Schema (Supabase PostgreSQL)

**Tables**: `categories`, `tags`, `time_entries`, `time_entry_tags`, `schedule_templates`, `scheduled_blocks`, `goals`

**Key schema decisions**:
- All tables have `user_id` FK to `auth.users` with RLS policies (`user_id = auth.uid()`)
- All tables have `created_at`, `updated_at`, `deleted_at` timestamps
- UUID primary keys on all tables for sync compatibility
- Soft deletes everywhere (`deleted_at` timestamp) — hard delete prohibited by convention
- `categories.parent_id` is a self-referencing FK for subcategories (max depth: 1 level — enforced by application logic, not DB constraint)
- `time_entries` has an `is_running` boolean and nullable `ended_at` — a running timer has `ended_at = NULL, is_running = true`
- `schedule_templates` stores the reusable weekly pattern: `id`, `user_id`, `name`, `is_active`, `created_at`, `updated_at`, `deleted_at`
- `scheduled_blocks` has `template_id` FK (nullable) → `schedule_templates`. When `template_id` is NULL, the block is a standalone or detached exception. `is_exception` boolean marks blocks edited away from their template.
- `scheduled_blocks.objectives` is JSONB: `[{text: string, completed: boolean}]` for checklists, `{text: string}` for descriptions
- `scheduled_blocks.objective_type` discriminates between 'checklist' and 'description'
- Junction table `time_entry_tags` for many-to-many tag relationships
- Goal `period` values ('daily', 'weekly', 'monthly') — weekly period respects the user's configured first-day-of-week setting (US-60) when calculating boundaries

### macOS Presentation

- **Main Window**: 6 tabs — Tracking (grid), Schedule (plan + compare), Events (log), Timeline (charts), Goals (progress), Settings. Schedule is the 2nd tab because it is the core differentiator and should be prominently placed next to Tracking.
- **Menu Bar**: Persistent icon showing active timer color + elapsed time. Click to expand dropdown with quick start/stop and recent categories.
- **Floating Widget**: Small always-on-top window showing active timer. Draggable, dismissible.
- **Keyboard Shortcuts**: Global hotkeys for start/stop, category switching.

### Sync Architecture

```
Device A (Mac) writes to SwiftData
  → SyncEngine detects pendingCreate/Update/Delete
  → Pushes to Supabase via REST API
  → Supabase updates PostgreSQL

Supabase Realtime broadcasts change
  → Device B (iPhone) SyncEngine receives via WebSocket
  → Writes to local SwiftData
  → UI updates reactively via SwiftData @Query
```

- **Initial sync (new device)**: On first sign-in, pull all records from Supabase where `deleted_at IS NULL`, ordered by `updated_at DESC`. Insert into local SwiftData. Mark all as `.synced`.
- **Incremental sync (app launch)**: Pull all records where `updated_at > last_sync_timestamp`. Apply to local SwiftData with LWW conflict resolution.
- **Continuous sync (running)**: Supabase Realtime subscriptions on all tables, filtered by `user_id`. Incoming changes are applied to SwiftData immediately.
- **Upload queue**: Pending local changes are pushed to Supabase via REST API. On success, `syncStatus` is updated to `.synced`. On failure, retry with exponential backoff (1s, 2s, 4s, 8s, max 60s).
- **Sleep/wake**: Subscribe to `NSWorkspace.willSleepNotification` and `didWakeNotification`. On wake, reconnect Realtime WebSocket and run an incremental sync to catch anything missed during sleep.
- **Tombstone purging**: Records with `deleted_at` older than 90 days are hard-deleted from both Supabase and local SwiftData during a periodic maintenance pass (runs once per app launch).
- **Clock skew mitigation**: `updated_at` is set server-side by Supabase (`DEFAULT now()`) on all writes. Local timestamps are used only for optimistic display; the server timestamp is canonical for conflict resolution.
- NWPathMonitor pauses sync when offline, resumes and triggers incremental sync when online

## Testing Decisions

### Testing Philosophy

Tests verify **behavior through public interfaces**, not implementation details. A good test reads like a specification — "user can start a timer for a category" tells you exactly what capability exists. Tests should survive refactors because they don't care about internal structure.

### Modules Under Test

1. **Time Entry Engine** — Test: starting timers, stopping timers, concurrent timer behavior, retroactive entry creation, editing entries, duration calculations, state transitions.

2. **Schedule Planner** — Test: creating weekly plans, querying a day's schedule, recurring schedule generation, plan-vs-actual diff calculation, accountability score accuracy, handling of unscheduled tracked time.

3. **Sync Engine** — Test: upload queue processing, conflict resolution (last-write-wins), offline queue persistence, Realtime message handling, retry behavior, sync status transitions.

4. **Analytics Engine** — Test: summary aggregation accuracy, trend calculations, distribution math, filtering by category/tag/date range, accountability score formula.

### Testing Approach

- Integration-style tests that exercise real SwiftData containers (in-memory) with real module code
- No mocking of internal collaborators — only mock at system boundaries (network for Supabase calls)
- Test factories for creating test data (categories, entries, scheduled blocks)
- TDD workflow: one test → one implementation → repeat (vertical slices, not horizontal)

## Out of Scope

- **iPhone app** — Future phase. Will share SwiftData models and Supabase backend.
- **Apple Watch app** — Future phase. Will share the same Supabase backend.
- **Team features** — No shared timers, no team dashboards, no collaboration. This is personal-use only.
- **Invoicing/billing** — No client billing, no hourly rates, no invoice generation.
- **Automatic time tracking** — No app-usage detection, no screen monitoring. All tracking is manual/intentional.
- **Apple Health import** — No importing of workouts, sleep, or meditation data. May be added later.
- **Siri Shortcuts / Automations** — Not in V1. May be added for quick timer start/stop.
- **Web app** — Not in V1. Supabase backend makes this possible later.
- **Widgets (macOS desktop widgets)** — Not in V1. The floating timer and menu bar cover this need.
- **Notifications beyond schedule reminders** — No goal completion celebrations, no streak notifications in V1.
- **Data import from Timelines or other apps** — Not in V1.

## Further Notes

### Why Supabase Over CloudKit

- **Portability**: Data lives in standard PostgreSQL, not locked into Apple's proprietary CloudKit.
- **Future flexibility**: A web dashboard, Android companion, or API access becomes trivial with Supabase.
- **Developer control**: Full SQL access, RLS policies, Edge Functions for future server-side logic.
- **Learning value**: Building the Sync Engine is educational and produces a reusable pattern.
- **Cost**: Supabase free tier (500MB DB, 5GB bandwidth) is more than sufficient for personal use indefinitely.

**Trade-off acknowledged**: The Sync Engine is estimated at 1,500-3,000 lines of production-quality Swift (including retry logic, batch initial sync, tombstone purging, sleep/wake reconnection, and tests). CloudKit + SwiftData gives equivalent sync for free with zero code. This trade-off is accepted for the portability and flexibility benefits.

### App Name

**Tiempo** — Spanish for "time." Clean, memorable, one word.

### Design Direction

- Native macOS aesthetic. No custom chrome — use system title bars, sidebars, and toolbars.
- Follows macOS system appearance (light/dark) by default, with an in-app override toggle for users who prefer to force dark mode. This respects US-54 while supporting the dashboard aesthetic preference.
- Category colors are the primary visual language — they appear everywhere (grid tiles, timeline blocks, chart segments, menu bar icon).
- SF Pro (system font) for UI text, SF Mono for durations/timestamps/data. No custom fonts to bundle — native macOS typography throughout.
- SF Symbols for icons throughout.

### Priority Order for Development

1. SwiftData models + Supabase schema (foundation)
2. Category System (everything depends on categories)
3. Time Entry Engine + Tracking UI (core value — start tracking immediately)
4. **Sync Spike** — Prove the sync architecture works end-to-end with ONE entity (categories). Mac → Supabase → simulated second device pull. Surface Swift 6 actor isolation issues, Realtime WebSocket lifecycle, and conflict resolution before building everything else on the assumption sync works. This is a 2-3 day investment that de-risks the entire project.
5. Menu Bar app + Floating Widget (macOS integration)
6. Events Log view
7. Schedule Planner + Plan vs Actual (differentiator — budget 3 weeks for the calendar drag-resize component)
8. Analytics Engine + Charts (Timeline view — note: horizontal timeline blocks require custom Canvas/GeometryReader, not Swift Charts. Swift Charts handles pie charts and bar charts only.)
9. Goals Tracker
10. Full Sync Engine (expand the spike from step 4 to cover all entities, batch initial sync for new devices, tombstone purging, sleep/wake reconnection)
11. Settings, export (CSV + PDF), polish

**Key risk notes**:
- Step 7 (Schedule Planner) includes the calendar drag-resize view (US-28), which is a custom SwiftUI component with no built-in equivalent. Budget 2-3 weeks for this alone.
- Step 10 (Full Sync Engine) is estimated at 1,500-3,000 lines. The spike in step 4 will validate the architecture early.
- Global keyboard shortcuts (US-50) require macOS Accessibility permission. First-launch UX must handle the permission prompt gracefully.
- macOS 15 Sequoia is the minimum deployment target for App Store compatibility. macOS 26 Tahoe-specific APIs can be feature-flagged with `@available(macOS 26, *)` where needed.
