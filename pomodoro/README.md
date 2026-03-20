# Pomodoro

Next.js 16 focus timer: guest-first, IndexedDB persistence, optional browser notifications, single-tab lease across windows.

**PRD:** [../PRD-POMODORO.md](../PRD-POMODORO.md) · **Plan:** [../plans/pomodoro.md](../plans/pomodoro.md)

**Testing with Cursor Agent (Browser vs terminal):** [docs/agent-testing.md](docs/agent-testing.md)

## Scripts

```bash
npm run dev           # dev server
npm run build         # production build
npm run start         # serve production (after build)
npm run test          # Vitest (engine, history, tab coordinator, notifications)
npm run lint          # ESLint

# E2E (Playwright + Chromium) — first time on a machine:
npm run test:e2e:install

# Local: starts Next dev automatically (reuses server if port is free)
npm run test:e2e

# CI-style: run `npm run build` first, then uses `next start` (see playwright.config.ts)
CI=true npx playwright test

# Full gate (build once, then e2e)
npm run verify

# Split (useful when an AI agent times out on one long shell command)
npm run verify:static   # lint + unit + build
npm run verify:e2e      # Playwright only — needs prior `npm run build` (or run after `verify:static`)

# Override bind URL (use loopback for baseURL — avoid E2E_HOST=0.0.0.0 in the browser)
E2E_PORT=3005 npm run test:e2e

## E2E + Cursor / AI agents — why things look “stuck”

Several unrelated issues stack together:

1. **Agent timeouts** — Long commands (`verify`, Playwright + Chromium + Next) are often **stopped waiting** after a few minutes and **moved to the background**. The log stops updating even though work may still be running.
2. **`spawn Aborted`** — Heavy or nested spawns (npm → npx → Playwright → browser) are sometimes **killed or never started** in a constrained runner.
3. **Playwright `webServer` + pipes** — If the child’s `stdout`/`stderr` are piped and not drained, the buffer fills and **Next.js blocks**; we use `ignore` here.
4. **`github` reporter off-GitHub** — Can misbehave locally; we only attach it when `GITHUB_ACTIONS` is set.
5. **Piping Playwright** — Don’t run `playwright test | tail`; the pipe can **deadlock** when the buffer fills.

**What we did about it:** `npm run verify:e2e` runs [`scripts/run-e2e-with-server.sh`](scripts/run-e2e-with-server.sh): it starts `next start` in the background, **waits with `curl`**, sets `PLAYWRIGHT_TEST_BASE_URL`, then runs Playwright **without** its `webServer` helper. That path matches **GitHub Actions** (`SKIP_E2E_BUILD=1` after `npm run build`).

**Reliable in Cursor:** `npm run verify:static` (no browser). For full e2e, use your **system terminal** or accept that the agent may time out before Chromium finishes.

# Debug
npm run test:e2e:ui
npm run test:e2e:headed
```

## Security note

v1 stores tasks and history only in the browser. For production hosting, add a strict **Content-Security-Policy** and keep task titles plain text (no HTML) — see PRD.

## Phase 2

Supabase sync is specified in `docs/pomodoro-phase2-supabase.md` (not implemented in v1).
