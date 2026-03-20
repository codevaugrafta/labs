# Pomodoro design contract (v1)

Single-product rules for `pomodoro/`. Supersedes ad-hoc styling decisions when this doc and the PRD disagree—escalate to PRD.

## Typography (Geist)

- **App shell**: `font-sans` (Geist Sans) for headings, body, labels.
- **Timer digits**: `font-mono` + `tabular-nums` for `MM:SS`; scale **larger** than `text-base` card titles (target: `text-5xl`–`text-6xl` on the hero card).
- **Muted meta**: `text-sm text-muted-foreground` for streaks, hints, cheatsheet notes.

## Spacing rhythm

- **Vertical sections**: `gap-6` between major blocks; `space-y-4`–`space-y-6` inside tab roots.
- **Card innards**: `CardHeader` / `CardContent` use shadcn defaults; keep primary actions in a single row with `flex-wrap gap-2`.

## Phase semantics (non–color-only)

| Phase        | Label (copy) | Icon (decorative) | Left rail (card)     | Top ribbon (inside card)        |
| ------------ | ------------ | ----------------- | -------------------- | ------------------------------- |
| Work         | Focus        | Briefcase         | Solid 6px primary    | Solid bottom border + primary wash |
| Short break  | Short break  | Coffee            | Dashed 6px muted   | Dashed bottom + muted wash    |
| Long break   | Long break   | Armchair          | Solid 10px muted   | Thick solid bottom + stronger muted wash |

The **phase ribbon** (`data-testid="pomo-phase-ribbon"`) carries large type (`text-xl` / `text-2xl`) and `size-11`–`14` icons so phase is obvious at a glance. Hue may reinforce but must not be the only cue; icons use `aria-hidden` (phase is already in text + live region).

## Motion

- **Phase container**: Optional `border-color` / `box-shadow` transition on the timer hero card class `pomo-phase-surface` when `html[data-reduce-motion="off"]`.
- **Reduced motion**: `html[data-reduce-motion="on"]` (from app settings + `prefers-reduced-motion`) forces near-zero transition duration globally per [globals.css](../src/app/globals.css)—do not fight it with `!important` overrides.
- **No** continuous decorative animation on the running countdown.

## Keyboard map (Timer tab, global listener)

| Key    | Action        | When disabled                          |
| ------ | ------------- | -------------------------------------- |
| `Space`| Start/pause/resume | `foreignLease`, or focus in `INPUT`/`TEXTAREA` |
| `S`    | Skip phase    | `foreignLease`, idle, or text field focus |
| `R`    | Open reset dialog | `foreignLease` or text field focus  |

Documented again in Settings → Keyboard cheatsheet.

## Focus and tabs

- **Tabs**: Radix `TabsList` / `TabsTrigger`—rely on library roving focus; do not trap focus inside task list.
- **Custom rows**: Task buttons use full-width hit targets and visible focus ring (default ring from theme).

## References

- [PRD-POMODORO.md](../../PRD-POMODORO.md) stories 8, 31–32, 36–38, 44–49.
- [agent-testing.md](./agent-testing.md) for verify commands.
