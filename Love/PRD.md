# Love — Product Requirements (v1)

> Use this document as the body of a GitHub issue, or paste into a new issue when filing.

## Problem Statement

I start days without clear structure, bounce between tasks without finishing any with full presence, and lose mental bandwidth to random ideas, links, and articles that appear while I am trying to focus. I need a minimal macOS companion that holds **what I must do** in **honest order**, shows **one current focus** where my attention should be, and gives me a **trusted place to park distractions** so I can return to them later without breaking flow.

## Solution

**Love** is a menu-bar-first macOS app with:

1. **Must-do list** — Flat tasks grouped into **sections** (v1 hierarchy model: sections + ordered items, not an arbitrary deep tree).
2. **Current focus** — At most one task is “focused”; its title appears in the **menu bar** (truncated with full title in tooltip).
3. **Later drawer** — Quick captures (text, pasted URLs) organized by **user-defined categories** (e.g. “AI”), with **Promote to must-do** and **Archive** so the drawer does not become a junk inbox.
4. **Light planning** — Each task has a **planning bucket**: *Backlog*, *Today*, or *This week* (no full calendar grid, no time blocks in v1).

**North-star loop:** *Capture → (optional) triage → one visible focus → complete or explicitly defer → repeat.*

## User Stories

1. As a user, I want to add a short title for something I must do, so that it is recorded without friction.
2. As a user, I want to group tasks into named sections, so that I can separate areas of life (e.g. work vs personal) without a complex tree.
3. As a user, I want to reorder tasks within a section by drag-and-drop, so that priority reflects my real sequence.
4. As a user, I want to mark one task as my current focus, so that I commit to one thing at a time.
5. As a user, I want to see my current focus in the menu bar, so that I am reminded without opening the main window.
6. As a user, I want the menu bar title to truncate long tasks with a tooltip for the full title, so that the bar stays usable.
7. As a user, I want to complete the focused task from the menu bar, so that I can close a loop quickly.
8. As a user, I want to advance to the “next” incomplete task after completing focus, so that I keep momentum.
9. As a user, I want to clear focus without completing, so that I can pause or reprioritize.
10. As a user, I want a **Later** place to paste a URL or type a thought in seconds, so that distractions do not derail deep work.
11. As a user, I want to assign a category to a capture, so that later review is grouped by theme.
12. As a user, I want to create and rename categories, so that the taxonomy matches my mental model.
13. As a user, I want to promote a capture to the must-do list, so that a real commitment is created from a parked idea.
14. As a user, I want to archive captures, so that the inbox stays honest and small.
15. As a user, I want to filter must-dos by **Today**, **This week**, or **Backlog**, so that I see what I claimed matters for the period.
16. As a user, I want to set a task’s planning bucket from the main UI, so that planning stays lightweight.
17. As a user, I want **Defer to tomorrow** on a task, so that I can reschedule without deleting.
18. As a user, I want optional short sound feedback on capture and complete, so that actions feel satisfying (with an off switch).
19. As a user, I want the app to respect **Reduce Motion**, so that animations are accessible.
20. As a user, I want to open the main window from the menu bar, so that I can work in the full UI when needed.
21. As a user, I want the app to run as a menu bar accessory (no Dock icon), so that it stays out of the way like my other utilities.
22. As a first-time user, I want a sensible default section, so that I am not blocked by empty structure.
23. As a user, I want deleting the focused task to clear focus automatically, so that the menu bar never points at a ghost.
24. As a user, I want completed tasks hidden from the default list (or filterable), so that the view stays forward-looking.
25. As a user, I want **Quick capture** via a global shortcut (after granting Accessibility), so that I can capture from any app.
26. As a user, I want Settings for sound and shortcut hints, so that I understand behavior and privacy implications.

*(Stories 27–35 — edge cases)*  
27. As a user, with no focus set, I want the menu bar to show a neutral label (e.g. “Love”), so that the UI is honest.  
28. As a user, I want empty states with clear CTAs, so that I know what to do first.  
29. As a user, I want captures to detect pasted URLs as text, so that I do not need a separate field.  
30. As a user, I want to edit task titles, so that wording can be refined.  
31. As a user, I want to delete sections (with tasks moved or prevented), so that structure can evolve — *v1: prevent delete if non-empty or move tasks to default section*.  
32. As a user, I want local-only storage by default, so that my commitments stay on my Mac until I opt into sync later.  
33. As a user, I want no iPhone requirement in v1, so that the product does not pretend to sync.  
34. As a product, we commit to **no Obsidian-style graph** in v1, so that scope stays coherent.  
35. As a product, we commit to **no hour-granularity calendar**, so that we do not imply scheduling precision we do not support.

## Implementation Decisions

- **Hierarchy (v1):** **Sections + flat ordered tasks** inside each section (not a deep parent/child tree). Easier reorder and clearer mental model than competing metaphors.
- **Focus:** At most one focused task; stored by ID in `UserDefaults` for simplicity; engine enforces clearing focus when that task is deleted or completed (configurable: complete can auto-advance to next incomplete in section).
- **Snooze / defer:** **Defer to tomorrow** sets planning bucket to **Today** with an internal **deferredUntil** start-of-day — or simpler: set bucket to **Backlog** and set a `deferDate` — *implementation:* `deferToNextCalendarDay()` sets `planningBucket` to `.today` and `deferUntilStartOfDay` to tomorrow’s start; filter hides until that day. *Simpler v1:* `deferToTomorrow()` sets bucket to `.backlog` and stores `nextReviewDay` as Date startOfDay — actually simplest: **`deferToTomorrow()`** = set `planningBucket = .today` and `effectiveDate` optional — Let’s use: **`snoozeUntil: Date?`** — if `Date() < snoozeUntil`, task excluded from Today/Week active lists. Clear on complete.
- **Planning buckets:** Enum persisted as `Int` on `MustDoItem`: `backlog`, `today`, `thisWeek`.
- **Capture lifecycle:** New → (optional promote → `MustDoItem`) or **Archive** (`archivedAt` set). Archived hidden from default drawer view; optional “Show archived” later — v1: toggle in drawer.
- **Menu bar:** `NSStatusItem` + `NSMenu`; title = focus title truncated (~40 chars) or app name.
- **Feedback:** Central `FeedbackPolicy` — `NSSound` for subtle ticks; respect user default sound off; `accessibilityReduceMotion` reduces SwiftUI animation.
- **Global shortcut:** `NSEvent.addGlobalMonitorForEvents` for ⌃⌥L (Control+Option+L) when Accessibility / event tap allows; menu bar always works without it.
- **Persistence:** SwiftData store under Application Support `Love/Love.store`, chmod 600 after create (mirror Tiempo). Upgrades from the pre-rename app copy `FocusPath/FocusPath.store` into `Love/` on first launch if `Love.store` is absent.
- **Placement:** Standalone app in monorepo; optional future hook to start Tiempo timer for focus — **out of v1 code**.

## Testing Decisions

- **Good tests** assert **observable behavior** (order, focus ID, bucket filters, promote creates item, archive hides) — not SwiftUI view internals.
- **Modules tested:** `LoveEngine` (or equivalent) with in-memory `ModelContainer`.
- **Prior art:** Tiempo / Adhan `@Suite` + Swift Testing patterns (`@Test`, `#expect`).

## Out of Scope (v1)

- Graph / neural view of links.
- Full calendar week grid with time blocks.
- iCloud / multi-device sync.
- iOS / iPadOS app.
- Deep Tiempo integration (documented as future idea only).

## Further Notes

- Adversarial review asked for **one ontology** and **explicit capture rules** — addressed by sections + buckets + promote/archive.
- **Haptics on Mac** are limited; v1 emphasizes **sound + visual** micro-feedback, not marketing-heavy haptic claims.
- **Tiempo:** Same machine may run both; user accepts two menu bar icons or hides one; merging products is a future product decision.

---

## GitHub issue filing

Run from repo root (requires `gh` auth):

```bash
gh issue create --title "PRD: Love v1 (must-do + later drawer)" --body-file Love/PRD.md
```
