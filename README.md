# Labs Monorepo

This repo holds multiple active apps. `main` is the clean shared trunk and should track `origin/main`. New work belongs on feature branches in dedicated worktrees under `.claude/worktrees/<app>/<task>`.

## Working Rules

- Do not develop directly on `main`.
- Create new task lanes with `./scripts/new-worktree.sh <app> <task> [base]`.
- Keep app-specific PRDs and plans inside the owning app folder.
- Use root `plans/` only for cross-project research, comparisons, and repo-level planning.
- Keep local session notes in `SESSION.md` inside the worktree root. They are local workflow state, not product docs.

## Projects

| Project | Path | Purpose | Build / Run | Verify |
| --- | --- | --- | --- | --- |
| Tiempo | `Tiempo/` | macOS time tracker | `cd Tiempo && swift build` or `./build-app.sh` | `cd Tiempo && swift test` |
| Adhan | `Adhan/` | macOS prayer times | `cd Adhan && ./build-app.sh` | `cd Adhan && swift test` |
| Love | `Love/` | macOS must-do + later drawer | `cd Love && swift build` or `./build-app.sh` | `cd Love && swift test` |
| Leo | `Leo/` | macOS Chinese immersive reader | `cd Leo && ./build-app.sh` | `cd Leo && swift test && ./scripts/run-ux-tests.sh && ./scripts/ui-smoke.sh` |
| IMI / VoiceTutor | `VoiceTutor/` | macOS menu-bar voice companion | `cd VoiceTutor && ./build-app.sh` | `cd VoiceTutor && swift test` |
| SyncReader | `syncreader/` | Tauri + Svelte reader | `cd syncreader && npm run dev` | project-local npm checks |
| Pomodoro | `pomodoro/` | reference web timer | `cd pomodoro && npm run dev` | `cd pomodoro && npm run verify` |
| Focus Node | `focus-node/` | merged focus product | `cd focus-node && npm run dev` | `cd focus-node && npm run verify` |

## Repo Helpers

- `./scripts/new-worktree.sh <app> <task> [base]`
- `./scripts/repo-status.sh`
- `./scripts/rescue-project.sh <app> <branch>`

More detail lives in [`docs/repo-workflow.md`](docs/repo-workflow.md).
