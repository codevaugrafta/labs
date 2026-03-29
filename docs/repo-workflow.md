# Repo Workflow

## Trunk Model

- `main` is the clean shared trunk and tracks `origin/main`.
- Active work lives on feature branches named `{agent}/{app}-{task}`.
- Rescue branches preserve mixed local work until it is intentionally split or landed.

## Worktree Layout

- Default location: `.claude/worktrees/<app>/<task>`
- Example: `.claude/worktrees/leo/design-parity`
- Create new lanes with `./scripts/new-worktree.sh <app> <task> [base]`
- Each active worktree keeps a local `SESSION.md` note at its root. The helper script creates it and adds it to local excludes so it stays out of git.

## Rescue Flow

1. Move the dirty source checkout off `main`.
2. Create one rescue branch/worktree per dirty lane.
3. Copy only that lane’s source files into its rescue worktree.
4. Commit the snapshot locally with a rescue message.
5. Reset `main` back to the clean trunk and continue work from dedicated feature worktrees.

The rescue helper is:

```bash
./scripts/rescue-project.sh <app> <branch>
```

It copies one app directory into a worktree, stages it, and creates a local rescue commit.

## Document Placement

- App-specific PRDs, plans, threat models, and design notes belong inside the owning app directory.
- Root `plans/` is reserved for cross-project research, comparisons, and repo-level planning.
- Existing root PRD files can stay in place until there is a deliberate migration pass.

## Verification Matrix

There is no single root `npm run typecheck|lint|test|build|vibe:gate` for this monorepo. Verification is project-local:

| Project | Verification |
| --- | --- |
| Tiempo | `cd Tiempo && swift test` |
| Adhan | `cd Adhan && swift test` |
| Love | `cd Love && swift test` |
| Leo | `cd Leo && swift test && ./scripts/run-ux-tests.sh && ./scripts/ui-smoke.sh` |
| VoiceTutor | `cd VoiceTutor && swift test` |
| Pomodoro | `cd pomodoro && npm run verify` |
| Focus Node | `cd focus-node && npm run verify` |
| SyncReader | run the closest project-local npm checks available |

## Cleanliness Rules

- Do not commit generated `.app` bundles, `.build/`, `.next/`, `dist/`, `node_modules/`, or Playwright artifacts.
- Keep build scripts and source generators out of ignored output directories.
- Use `./scripts/repo-status.sh` to see grouped dirty state before branching, rescuing, or reviewing.
