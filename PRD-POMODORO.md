# PRD: Pomodoro — Focus Timer (Web)

## Problem Statement

People who use the Pomodoro Technique need a timer that stays trustworthy across browser tabs, background tabs, and laptop sleep; surfaces completion without requiring notification permission; and keeps lightweight task context without friction. Most web timers break down on multi-tab races, throttle in background tabs, or treat notifications as the only feedback channel. Users also want history and streaks without forced accounts, with an optional path to sync later. Productivity apps often feel generic; this product should feel **calm, legible, and keyboard-first**—worthy of a polished daily driver.

## Solution

**Pomodoro** is a guest-first web app (new app in monorepo at `pomodoro/`) built with **Next.js 16**, **TypeScript**, **shadcn/ui**, and **Geist**. The core is a **pure timer state machine** driven by **monotonic elapsed time**, with **in-tab and audio as primary** phase-completion feedback and **Web Notifications as optional**. **Local persistence** (IndexedDB preferred, with explicit quota and migration strategy) holds settings, active session state, tasks, and completed session history. **Multi-tab coordination** ensures a **single active timer lease** across tabs via `BroadcastChannel` and `storage` events.

**Phase 2 (out of v1 build scope, specified here for contract completeness):** optional **Supabase Auth + Postgres** with **RLS**, **idempotent session upload**, **merge of guest data on first login**, **account deletion and export**, and **timezone preference** when authenticated.

## User Stories

### Core timer

1. As a user, I want to start a Pomodoro work phase with one clear primary action, so that I can enter focus with minimal friction.
2. As a user, I want to pause and resume the current phase, so that interruptions don’t force me to abandon the session.
3. As a user, I want to skip the current phase and move to the next (work → short break → work → … → long break per settings), so that I can recover from mistakes or changed plans.
4. As a user, I want to reset the current session to a clean idle state, so that I can abandon a bad run without polluting history (with a confirm if time > 0).
5. As a user, I want configurable durations for work, short break, and long break, so that I can match my personal rhythm.
6. As a user, I want to configure how many work cycles occur before a long break, so that I can follow classic or custom Pomodoro patterns.
7. As a user, I want an option to auto-start the next phase after one completes, so that I can stay in flow or disable it when I need manual control.
8. As a user, I want a large, readable countdown that does not rely on color alone to distinguish work vs break, so that I can parse state at a glance (labels + icons + text).
9. As a user, I want the timer UI to **hydrate without SSR clock drift** (placeholder until client mount), so that I never see a wrong time flash on load.

### Time correctness (background, sleep, throttling)

10. As a user, I want the timer to remain accurate when the tab is in the background, so that background throttling does not silently steal minutes.
11. As a user, I want the timer to correct after the device sleeps, with a defined cap on how much “catch-up” can run at once, so that behavior is predictable (spec: apply elapsed wall time up to a **max catch-up of one phase transition per wake**; if more time passed, advance one transition and recompute remaining, repeat on next tick until aligned—document exact algorithm in implementation).
12. As a user, I want visibility changes (`document.visibilitychange`) to trigger reconciliation of elapsed time, so that returning to the tab shows the true remaining time.

### Multi-tab

13. As a user, when I open the app in a second tab while a session is active elsewhere, I want to see that a timer is running in another tab and be offered **“Take over here”** or **“Stay read-only / view-only”**, so that two timers never run in parallel on the same browser profile.
14. As a user, when I take over in a new tab, I want the previous tab to stop driving the timer (lease transfer), so that only one tab mutates state.
15. As a user, I want cross-tab updates to reflect pause/resume/skip from any tab holding the lease, so that the experience feels connected.

### Tasks (minimal v1 model)

16. As a user, I want to attach an optional plain-text task label to the current session, so that I remember what I’m working on.
17. As a user, I want a minimal **Today** list of task titles (plain text, reorderable), so that I can queue what to do next without a full project management app.
18. As a user, I want to pick a task from Today to set as the current label, so that starting a Pomodoro is one or two clicks.
19. As a user, I want task titles limited to a reasonable length (e.g. 200 chars) with no rich HTML in v1, so that storage stays safe and XSS risk stays low.

### Feedback: audio and notifications

20. As a user, I want a distinct in-app visual and audio signal when a phase ends, so that **I never depend on notification permission** to know a phase completed.
21. As a user, I want to turn sounds on or off globally, so that I can work in shared spaces.
22. As a user, I want optional volume control when sound is on, so that I can tune distraction.
23. As a user, I want to opt in to **browser notifications** from a settings action (not on first landing), so that I’m not spam-prompted.
24. As a user, when notifications are denied or unsupported, I want the app to degrade gracefully to in-tab + sound, so that core value still works (incl. awareness of iOS Safari limitations).

### History, stats, streaks

25. As a user, I want completed work sessions recorded in history with start/end timestamps, phase type, and optional task label, so that I can review what I did.
26. As a user, I want a simple daily summary (e.g. count of completed work pomodoros, total focused minutes), so that I see progress at a glance.
27. As a user, I want a **streak** definition that is explicit: a streak day is a local-calendar day with **≥1 completed work pomodoro**; timezone is **local** for guests, so that streaks match my life.
28. As a user, I want sessions that **span local midnight** split for attribution: each calendar day receives the portion of focused minutes that fell on that day (for stats and streaks), without muting the underlying session record (implementation mirrors “view-layer split” pattern).
29. As a user, I want **CSV export** of history in v1 with **fixed columns** so that tests and integrations are stable: `session_id`, `started_at_iso`, `ended_at_iso`, `phase_type`, `duration_seconds`, `task_title`, `completed_work_boolean`.

### Settings and theming

30. As a user, I want light, dark, and system theme options, so that the app matches my environment.
31. As a user, I want a **reduced motion** setting that respects `prefers-reduced-motion` by default but can be overridden, so that animation is comfortable.
32. As a user, I want configurable keyboard shortcuts for start/pause, skip, reset (documented in a cheatsheet), so that I can stay keyboard-first; shortcuts apply when the document focus is appropriate and do not steal browser chrome keys without care.

### Local data, privacy, shared devices

33. As a user, I want **“Forget this device”** to clear all local tasks, history, and settings, so that I can safely use shared computers.
34. As a user, when storage quota is exceeded or storage is unavailable, I want a clear error and a path to export or prune old history, so that I’m not stuck silent-failing.
35. As a user, I want a **retention policy** (e.g. keep last 365 days of sessions or 10k rows, whichever is smaller—tunable) with automatic prune, so that the app stays within storage limits.

### Accessibility

36. As a screen reader user, I want phase transitions announced via a polite **`aria-live` region**, without announcing every second of the countdown, so that I get meaningful updates without noise.
37. As a keyboard-only user, I want all primary actions reachable and a visible focus ring, so that I can operate without a pointer.
38. As a user with low vision, I want sufficient contrast and non-color cues for work vs break, so that state is perceivable.

### Polish and perception quality bar (v1)

Measurable “daily driver” polish—no subjective awards language. Each item is testable in the shipped web UI or via documented manual checks.

44. As a user, I want the **countdown** to be the dominant typographic anchor on the Timer tab (larger than card titles and body copy), so that remaining time is parsed first.
45. As a user, I want **work**, **short break**, and **long break** distinguished by **visible label + icon + distinct left-border treatment** (solid vs dashed vs width), not by hue alone, so that phase is clear in grayscale.
46. As a user, I want **container styling** to transition subtly when the phase changes while reduced motion is off; when reduced motion is on (system or app setting), those transitions must not introduce noticeable decorative motion, so that animation stays respectful.
47. As a user, I want **empty states** on Today, History, and the task queue to name the **next action** (what to type, click, or run first), so that I am never stuck on a blank surface.
48. As a user, I want a **keyboard cheatsheet** in Settings (table or definition list) listing **Space**, **S**, and **R** with scope (“not while typing in a field”) and the owning tab, so that shortcuts are discoverable without leaving the app (extends story 32).
49. As a user, I want the **Today** task row that matches the current timer task label to be visually distinct, so that queue and timer stay mentally linked.

**Verification checklist (manual / release QA)**

- **Live region**: phase changes announce phase name (polite, atomic); countdown seconds are not announced every tick.
- **Focus**: all interactive controls in the Pomodoro shell show a visible `:focus-visible` ring; tab order is logical within each tab panel.
- **Keyboard**: Space / S / R behave as documented when focus is not in `INPUT` / `TEXTAREA`; shortcuts do not fire when another tab holds the timer lease (take-over state).
- **Contrast**: timer digits and phase label meet WCAG 2.2 AA against app background in light and dark theme.
- **CSV export**: UTF-8, header row, columns frozen per “CSV export (v1 frozen)” in this PRD.

### PWA (v1 scope decision)

39. As a user, I want **no service worker in v1** (defer PWA install/offline shell to post-v1), so that we avoid update-during-active-session complexity until core timer reliability ships. *(If product later enables PWA, PRD amendment required: SW update strategy during active timer.)*

### Phase 2 — Account and sync (specified, not v1)

40. As a signed-in user, I want my sessions to sync across devices, so that history follows me.
41. As a user signing in for the first time, I want **guest sessions merged** with **idempotent `session_id`** so duplicates never appear; conflicts use **server `received_at` + client `started_at`** rules documented in sync ADR.
42. As a signed-in user, I want **account deletion** and **data export**, so that I meet privacy expectations.
43. As a signed-in user, I want **RLS** so no other user can read my rows.

## Implementation Decisions

### Tech stack (v1)

- **Framework**: Next.js 16 App Router, React 19, TypeScript strict.
- **UI**: shadcn/ui, Tailwind CSS, Geist Sans/Mono via `next/font`.
- **Timer core**: `PomodoroEngine` — pure module, no DOM; inputs are events + monotonic/wall deltas as defined by tests.
- **Persistence**: IndexedDB via a thin `LocalStore` wrapper with **schema version**, migrations, and JSON serialization; fallback messaging if IDB unavailable.
- **Multi-tab**: `TabCoordinator` using `BroadcastChannel` primary, `storage` event fallback; **lease token** with random owner id; only lease holder writes timer ticks to storage (others read-only or takeover flow).
- **Notifications**: `NotificationPolicy` module — never required for correctness; prompt only from user gesture in settings.
- **Security**: Strict CSP headers as deployed; **plain text** task fields only in v1; sanitize display (React text nodes only); max lengths on all user strings.
- **Styling/a11y**: Dark-first layout; phase state duplicated in visible text; `aria-live` on phase change only; respect `prefers-reduced-motion`.

### Timer reconciliation (normative)

- On tick: `remaining = configuredPhaseSeconds - (elapsedMonotonicMs/1000)` with elapsed derived from `performance.now()` deltas while tab active; when tab hidden, on visibility visible recompute using `Date.now()` delta capped by policy in story 11.
- **Max backdate** for guest integrity: not security-critical; streaks are honor-system for guest mode.

### CSV export (v1 frozen)

- Columns exactly: `session_id`, `started_at_iso`, `ended_at_iso`, `phase_type`, `duration_seconds`, `task_title`, `completed_work_boolean`.
- UTF-8, header row, RFC-friendly quoting for titles.

### Streak and midnight

- **Streak**: consecutive local calendar days with ≥1 completed **work** pomodoro (not breaks).
- **Midnight split**: for stats only; persisted session keeps true `started_at` / `ended_at`; aggregations compute overlap minutes per day.

### Phase 2 sync (deferred implementation)

- Supabase Postgres + Auth; tables `profiles`, `pomodoro_sessions` with `user_id`, `session_id` UUID unique per user.
- Server validates payload shape; **idempotency** on `session_id`; reject sessions older than **30 days backdate** or with ends before starts.
- Merge on first login: upload all local sessions with client-generated `session_id`; server upserts on conflict.

## Testing Decisions

- **Good tests** assert **observable behavior** of modules (engine transitions, remaining time after events, CSV row format), not private implementation details.
- **Modules under test**: `PomodoroEngine`, `LocalStore` serialization/migration (mock IDB or in-memory), `NotificationPolicy` matrix, `TabCoordinator` with mocked `BroadcastChannel`.
- **Runner**: Vitest for unit tests; fast CI in `pomodoro/`.
- **E2E (recommended next increment)**: Playwright for two-tab lease and “take over” flow — not blocking v1 unit coverage.

## Out of Scope

- Native mobile/desktop wrappers in v1.
- Teams, shared rooms, social, or competitive leaderboards.
- Billing and subscriptions.
- Rich text / markdown in task titles in v1.
- PWA / service worker in v1.
- Full Supabase sync in v1 (specified for phase 2 only).
- Vanity redesigns or new surfaces that are not mapped to a user story in this PRD.
- Marketing claims (“award-winning,” etc.) without acceptance criteria in this document.

## Further Notes

- **GitHub product issue:** https://github.com/codevaugrafta/labs/issues/1
- **Telemetry**: If analytics are added later, require explicit PRD amendment: opt-in, no PII in events, document vendors.
- **Polish direction**: one primary focal card, generous whitespace, Geist scale, micro-motion only for phase-affordance transitions (honors reduced motion—see stories 31, 46), keyboard cheatsheet in Settings (stories 32, 48). Detailed tokens and motion rules: `pomodoro/docs/design-contract.md`.
- **Relation to Tiempo**: Separate product; no shared Swift codebase; conceptually both time-related but different jobs-to-be-done.
