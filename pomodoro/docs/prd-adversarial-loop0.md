# PRD adversarial pass (Loop 0)

Second read of [PRD-POMODORO.md](../../PRD-POMODORO.md) after adding **Polish and perception quality bar** stories 44–49.

## Contradictions / risks flagged

1. **Story 45 vs timer correctness**: Border/icon treatment must not obscure the countdown or imply phase when `foreignLease` is true—lease banner remains the source of truth for “who drives the clock.”
2. **Story 46 vs global CSS**: `html[data-reduce-motion="on"]` already short-circuits transitions app-wide; phase transitions must not rely on animation for meaning (only reinforcement).
3. **Story 48 vs story 32**: Cheatsheet duplicates shortcut docs; both stay aligned with the same key map (`Space` / `S` / `R`, input exclusions).
4. **Verification checklist vs CI**: Focus/contrast checks remain manual unless/until Playwright assertions are added; unit tests still target engine/store/policy.

## Resolution

- UI implements 45–49 without changing engine contracts.
- Design tokens and motion scope documented in [design-contract.md](./design-contract.md).
