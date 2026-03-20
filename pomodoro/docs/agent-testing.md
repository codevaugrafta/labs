# How people actually test (and fix) with AI agents

This is the **operating model** that matches Cursor’s product design and what teams document publicly—not “run one giant shell command inside the agent and hope it never times out.”

## 1. Cursor’s **native Browser** (primary loop)

Cursor ships a **built-in browser** for Agent: navigate, click, type, screenshot, **console logs**, and (in Agent layout) **network**—without installing Playwright MCP. See [Cursor Docs → Browser](https://cursor.com/docs/agent/browser).

**Why this is the “indefinite” loop:** the agent isn’t blocked by a 2–5 minute **terminal tool timeout**. It issues discrete browser actions; you approve them (or auto-approve safe ones). Each turn: observe UI/console → patch code → refresh or re-navigate → repeat.

**What you should configure (once):**

| Setting | Why |
|--------|-----|
| **Cursor Settings → Chat → Auto-Run** | Use *manual approval*, *allow-listed actions*, or *auto-run* for trusted localhost only. Auto-run on untrusted sites is dangerous. |
| **Browser origin allowlist** (Enterprise) | Allow `http://127.0.0.1:3000` (and `http://localhost:3000` if you use it) so the agent can drive your app. |
| **Dev server** | Run `npm run dev` in a **normal terminal** (or let the agent start it). Cursor prompts the agent to notice existing dev servers and ports. |

**Prompt pattern:** use `@browser` (or the Browser entry in the UI) with concrete steps, e.g. “Open the app, go to Settings, confirm Durations visible, click Start then Pause, report any console errors.”

That is how people get **continuous** test-and-fix: **many short tool calls**, not one endless `npm test`.

## 2. **Playwright MCP** (optional second path)

Teams also wire **Playwright as an MCP server** so the agent can run real Playwright primitives from chat. Examples in the wild use packages like `@playwright/mcp` / Playwright MCP installers (see [egghead — Playwright MCP in Cursor](https://egghead.io/autofix-browser-errors-with-the-playwright-mcp-in-cursor~lq4dr), [TestDino — Playwright + Cursor MCP](https://testdino.com/blog/playwright-tests-with-cursor/)).

**Use when:** you want the agent to align with **checked-in** `e2e/*.spec.ts` or to drive the same selectors as CI.

**Install:** Cursor Settings → MCP → add a server (commonly `npx` + `@playwright/mcp` or similar—follow the package’s current README).

## 3. **Headless CI / regression** (this repo)

For **repeatable** gates, not for “click around until it feels fine”:

```bash
cd pomodoro
npm run verify:static    # lint + unit + next build — fast, agent-friendly
npm run verify:e2e       # Playwright + production server (see scripts/run-e2e-with-server.sh)
```

**Port / wrong-server gotcha (fixed in-repo):** `run-e2e-with-server.sh` picks a **free ephemeral port** by default so a busy `:3000` cannot make Playwright hit some other app while `next start` fails with `EADDRINUSE`. Override with `E2E_PORT=3000` when you want a fixed port. Readiness requires `<title>Pomodoro</title>` in the HTML response.

**Important:** long headless runs can still hit **agent terminal limits**. The reliable pattern is:

- Agent **edits code** and runs **`verify:static`** often.
- You (or CI) run **`verify` / `verify:e2e`** in a **real terminal** or **GitHub Actions** (see `.github/workflows/pomodoro.yml`).

## 4. **Why “agent terminal forever” fails** (and isn’t how Cursor is designed)

- Shell tool **blocks then backgrounds** long processes → logs look frozen.
- **Piping** `playwright test | tail` can **deadlock** (full pipe buffer).
- **Subprocess** `webServer` + mishandled stdio can **block Next.js** (we mitigated with `ignore` and an external server script).

So: **Browser MCP / native Browser = many short calls;** **headless = bounded scripts in CI or your terminal.**

## 5. **Loop hygiene** (avoid “infinite agent” failure mode)

Practitioners who run agents for a long time recommend **smaller tasks**, **clear exit criteria**, and **resetting context** when the model spins—see e.g. [Dre Dyson — Cursor endless loops case study](https://dredyson.com/how-i-fixed-cursors-endless-agent-loops-a-6-month-case-study-from-real-world-development/). For testing, translate that to: *one user journey per loop*, *stop when console is clean and screenshots match intent*.

## Summary

| Goal | Best tool |
|------|-----------|
| Click, see UI, read console, fix, repeat | **Cursor Browser** (`@browser`) + dev server |
| Align with Playwright code / heal tests | **Playwright MCP** + `e2e/*.spec.ts` |
| Fast regression, agent-safe | `npm run verify:static` |
| Full gate | Your terminal or **GitHub Actions** → `npm run verify` |
| Click-through regression | `e2e/user-journey.spec.ts` (tabs, Today → Timer task link, skip → history → export, Space guard in inputs) |

**This repo “works” when:** CI runs the workflow, local `verify:static` passes, and **you** (or Agent with Browser) drive `http://127.0.0.1:3000` for interactive polish—not when a single sandbox shell runs forever.

**See also:** [rollout-dogfood.md](./rollout-dogfood.md) (preview + dogfood checklist), [review-gates.md](./review-gates.md) (release QA gates), [design-contract.md](./design-contract.md) (UI tokens).
