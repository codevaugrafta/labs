# Review gates — Pomodoro seven-loop polish

Date: 2026-03-20 (local branch work). Optional Cursor `/code-review` + `gh` PR flow: **skipped** — no open PR for this changeset (`gh pr view` on `main`).

## Gate 1 — Code review (correctness, readability)

- **Timer / multi-tab**: No engine or lease logic changed; phase UI is presentational.
- **Persistence**: No changes to `LocalStore` write paths beyond existing hydration.
- **Readability**: Phase affordances extracted to [phase-affordances.tsx](../src/components/pomodoro/phase-affordances.tsx).

**Result:** Pass.

## Gate 2 — Adversarial review (diff mindset)

- **a11y**: Live region unchanged (phase transitions only); cheatsheet table has `aria-label`; task row focus ring explicit.
- **Silent catches**: Pre-existing `catch { }` in persistence paths unchanged; no new swallow sites added.
- **Timer edge cases**: `foreignLease` still blocks keyboard shortcuts; phase border does not replace lease banner.
- **Export**: Disabled when empty avoids empty CSV confusion; still valid when sessions exist.

**Result:** Pass (tracked follow-up: optional Playwright assertion for disabled export — not required for this slice).

## Gate 3 — Checklist

| Check | Status |
| ----- | ------ |
| Tests (`npm test`) | Pass |
| Lint + build | Pass |
| E2E (`npm run verify`) | Pass |
| Focus / keyboard | Manual spot-check; cheatsheet documents S/Space/R |
| Contrast / non-color cues | Label + icon + border width/style per phase |
| Secrets | None added |
| Error handling | No new failure modes introduced |

**Result:** Pass.

---

## Loop 7 — Short retro (COE)

- **Worked**: PRD stories 44–49 map cleanly to one UI module plus CSS; `npm run verify` caught regressions before handoff.
- **Automate next**: Optional Playwright cases for export-disabled and Today row highlight when task titles overlap edge cases.
- **Don’t repeat**: Large single-file UI edits without extracting affordances first—extract early (as in `phase-affordances.tsx`).
