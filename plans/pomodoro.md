# Plan: Pomodoro (`pomodoro/`)

**PRD:** [PRD-POMODORO.md](../PRD-POMODORO.md)  
**Issue:** https://github.com/codevaugrafta/labs/issues/1

Vertical slices; each phase is demoable and test-backed where noted.

---

## Phase 1 — Scaffold

**Outcome:** `pnpm dev` runs; lint + test + build green.

**Acceptance criteria**

- [ ] Next.js 16 App Router, TypeScript strict, Tailwind, ESLint
- [ ] shadcn/ui initialized; Geist fonts via `geist` / `next/font`
- [ ] Vitest configured for unit tests (`pnpm test`)
- [ ] README with scripts

---

## Phase 2 — PomodoroEngine + tests

**Outcome:** Pure state machine with no DOM; time advances via injected deltas.

**Acceptance criteria**

- [ ] States: idle, running (work/short/long), paused
- [ ] Events: start, pause, resume, skip, reset, tick(deltaSeconds)
- [ ] Config: work/short/long lengths, cycles before long break, auto-advance flag
- [ ] On phase complete, engine exposes `phaseCompleted` for consumer to record history
- [ ] Vitest covers transitions, pause/resume, skip chain, long break insertion

---

## Phase 3 — Shell UI + a11y

**Outcome:** Focus layout; keyboard cheatsheet; live region on phase change only.

**Acceptance criteria**

- [ ] Large timer, phase label (work/break) with non-color cue (text + icon)
- [ ] SSR-safe: no countdown until client hydrated
- [ ] Theme: light/dark/system; reduced motion respects preference + setting
- [ ] Shortcuts: start/pause, skip, reset (documented in settings panel)
- [ ] `aria-live="polite"` updates only on phase transition, not every second

---

## Phase 4 — LocalStore + TabCoordinator

**Outcome:** IndexedDB persistence; single timer lease across tabs.

**Acceptance criteria**

- [ ] Versioned schema: settings, session snapshot, tasks, history rows
- [ ] Storage quota errors surface UI message
- [ ] “Forget this device” clears IDB
- [ ] Second tab: detect active lease; offer take-over; no double-running timers
- [ ] Unit tests for serialization; TabCoordinator with mocked `BroadcastChannel`

---

## Phase 5 — Audio + NotificationPolicy

**Outcome:** Phase complete always visible + audible without notification permission.

**Acceptance criteria**

- [ ] Optional chime (Web Audio or HTMLAudioElement) with mute + volume
- [ ] Notification permission requested only from settings button
- [ ] `NotificationPolicy` tests: denied / granted / unsupported paths

---

## Phase 6 — History, stats, streaks, CSV

**Outcome:** Completed work sessions listed; daily summary; streak; export.

**Acceptance criteria**

- [ ] Record completed **work** phases with `session_id`, timestamps, task, duration
- [ ] Streak: local calendar days with ≥1 completed work pomodoro
- [ ] Midnight split for aggregates only (session record unchanged)
- [ ] Retention prune (per PRD caps)
- [ ] CSV download with frozen columns from PRD

---

## Phase 7 — Polish

**Acceptance criteria**

- [ ] Empty states for no history
- [ ] Performance: no unnecessary re-renders (memo/client boundaries)
- [ ] `pnpm build` production bundle sanity

---

## Phase 8 — Supabase sync (deferred)

See `pomodoro/docs/pomodoro-phase2-supabase.md` (repo root relative) for schema, RLS, merge, and idempotency. Not in v1 build scope.

---

## Award-caliber polish — vertical slices (tracer bullets)

Design contract: [pomodoro/docs/design-contract.md](../pomodoro/docs/design-contract.md). PRD stories: 44–49 + verification checklist.

### Slice A — Timer hero + phase affordances

**Outcome:** Countdown dominates; phase label + icon + left-border pattern per phase; subtle phase transition on container when motion allowed.

**Acceptance**

- [ ] Maps to PRD 44, 45, 46; lease banner still primary when `foreignLease`
- [ ] `npm run verify:static` green after change set

### Slice B — Today tab + task link

**Outcome:** Clear empty state; row matching `taskTitle` visually distinct.

**Acceptance**

- [ ] Maps to PRD 47, 49
- [ ] `verify:static` green

### Slice C — History + export

**Outcome:** Empty history copy with next steps; export disabled (with explanation) when there is nothing to export.

**Acceptance**

- [ ] Maps to PRD 47, 29
- [ ] `verify:static` green

### Slice D — Settings density + a11y

**Outcome:** Keyboard cheatsheet table in Settings; motion copy unchanged in behavior.

**Acceptance**

- [ ] Maps to PRD 32, 48
- [ ] `verify:static` green

### Slice E — Motion + reduced-motion (verification)

**Outcome:** Phase surface transition respects `data-reduce-motion` / OS preference.

**Acceptance**

- [ ] Maps to PRD 31, 46; global CSS remains authoritative for reduce path
- [ ] `npm run verify` (incl. e2e where applicable) green before ship
