# Rollout / dogfood — Pomodoro polish

## Preview / local ship

1. `cd pomodoro && npm run build && npm start` (or `npm run dev` for informal use).
2. Open the printed URL; confirm `<title>Pomodoro</title>` matches the app under test (see `scripts/run-e2e-with-server.sh` rationale in [agent-testing.md](./agent-testing.md)).

## Dogfood checklist (5 minutes)

- [ ] Timer tab: start → pause → resume; phase border + icon track work / short / long break after skips if needed.
- [ ] Open second tab: lease banner appears; take over restores control.
- [ ] Today: add task, Enter; click row sets timer task; matching row shows highlight.
- [ ] History: empty copy is clear; Export disabled until at least one session exists.
- [ ] Settings: keyboard table matches behavior; toggle **Reduce** motion and confirm phase card transitions flatten (global `data-reduce-motion`).

## When Playwright fails in CI

- Inspect `test-results/` artifacts (screenshots, traces).
- Re-run locally: `cd pomodoro && npm run test:e2e:install` once, then `npm run verify:e2e`.
- Ensure no other server is squatting the port the script selects; the waiter checks app HTML, not just TCP open.

## Production deploy

Out of scope unless explicitly requested; Vercel CLI is optional per workspace notes.
