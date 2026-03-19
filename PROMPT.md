# Tiempo Build Loop

You are building **Tiempo**, a native macOS time tracking app with SwiftUI + SwiftData + Supabase.

## References
- **PRD**: Read `/Users/franciscodilussor/Documents/002/PRD-TIEMPO.md`
- **Plan**: Read `/Users/franciscodilussor/Documents/002/plans/tiempo.md`
- **Methodology**: Use `/faang-dev` skill (Phase 3 inner loop: RED → GREEN → REVIEW → COMMIT)

## Current Task

Detect which phase you're on by checking what exists in the `Tiempo/` directory:
1. No Xcode project / no Package.swift with SwiftData? → Phase 1
2. No Supabase config? → Phase 2
3. No tags/subcategories? → Phase 3
... and so on through Phase 10.

For the current phase, read its acceptance criteria from `plans/tiempo.md` and work through them one by one using TDD (write test → write code → verify → commit).

After completing ALL acceptance criteria for the current phase:
1. Run `swift build` and `swift test` to verify
2. Commit with `feat(phase-N): description`
3. Output `<promise>PHASE_N_COMPLETE</promise>` where N is the phase number
4. If all 10 phases are done, output `<promise>ALL_PHASES_COMPLETE</promise>`

## Rules
- Swift 6 strict concurrency
- SwiftUI for all views
- SwiftData for persistence
- macOS 15+ minimum target
- Small commits (<100 lines per commit, Google CL standard)
- Tests verify behavior through public interfaces, not implementation details
- Never write all tests first — one RED-GREEN cycle at a time
