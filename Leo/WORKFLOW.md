# Leo Workflow

## Canonical Branches

- Active Leo implementation branch: `leo/v1.0-digital-vellum`
- Stable fallback checkpoint: `leo/v0.2-consolidation`
- Treat commit `0a905ff` on `leo/v1.0-digital-vellum` as the integrated Digital Vellum Phase 1 baseline.

## Start Every Leo Session Here

Run the branch gate before any Leo work:

```bash
./Leo/scripts/verify-branch-gate.sh
```

This gate enforces:

- current branch is `leo/v1.0-digital-vellum`
- `git status --short Leo` is clean
- the authoritative Leo delta remains `leo/v0.2-consolidation..leo/v1.0-digital-vellum`

## Commit Discipline

- All new Leo feature work lands on `leo/v1.0-digital-vellum`
- Do not continue Leo feature work on `main`, `leo/v0.2-consolidation`, `claude/*`, or `codex/leo*`
- Stage only `Leo/` for Leo commits
- Never use repo-wide `git add .` while unrelated monorepo changes exist
- Scratch branches are allowed only as short-lived private workspaces and must be integrated back into `leo/v1.0-digital-vellum` before handoff

## Verification Gate

Run these checks for each Leo checkpoint:

```bash
cd Leo && swift test
cd Leo && ./scripts/ui-smoke.sh
cd Leo && ./scripts/run-ux-tests.sh
```

Use the UX test gate whenever reader UI, overlays, selection logic, or TTS interactions changed.

## Handoff Gate

Before closing a Leo handoff:

- `git status --short Leo` is clean
- the summary references only `leo/v1.0-digital-vellum`
- no next-step instruction points active Leo work to another branch
- any scratch branch is integrated or discarded
