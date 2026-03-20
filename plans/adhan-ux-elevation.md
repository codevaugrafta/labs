# Adhan — UX / motion / branding elevation (PRD-lite)

## Problem statement

Users want a stronger visual identity (logo/mark), and a more polished, calm feel: motion, transitions, haptic and light sound feedback, without distracting from prayer times.

## Solution (shipped in this slice)

- **In-app brand**: Vector **crescent + eight-point star** mark with theme-aware gradients and a subtle breathing glow; **wordmark** row (“Adhan” / “Prayer Times”) in the main window header. Dock/menu **AppIcon** remains `AppIcon.icns` — replacing it needs asset export (`iconutil`) or design tooling (see `Adhan/docs/BRAND-ICON.md` if present).
- **Main window**: Theme-aligned **gradient + optional geometric pattern**; **SF Symbol** effects on Hijri row; **spring transitions** for banners and next-prayer card; **numeric content transitions** on countdowns; **Recalculate** triggers short haptic + system **Pop** sound.
- **Floating panel**: **Fade-in** (ease-out) on show; **haptic** on reveal (no extra sound to clash with Adhan).
- **Motion utilities**: `adhanSpring(value:)` / `adhanEaseTransition(value:)` drive off real `Equatable` state (removed ineffective `UUID()`-based animations).

## User stories (selected)

1. As a user, I want the app to feel **recognizable and calm**, so that I enjoy opening it daily.
2. As a user, I want **countdowns to update smoothly**, so that the UI feels alive without jitter.
3. As a user, I want **light feedback** when I trigger actions, so that the app feels responsive on a Mac trackpad.
4. As a user, I want **branding aligned with my chosen theme**, so that Emerald / Midnight / Ramadan feel cohesive.

## Implementation decisions

- **macOS constraints**: Full **iPhone-style haptics** are not available; use `NSHapticFeedbackManager` where supported.
- **Sound**: Use short **system** sounds (`Pop`, existing theme `Tink`) — no new bundled audio for UI ticks.
- **Performance**: Avoid stacking heavy effects on the same control; next-prayer header uses **symbol** animation only (no duplicate pulse modifier).

## Testing decisions

- No snapshot tests for animation; rely on **compile + existing engine tests**.
- Optional follow-up: unit test `AdhanFeedback` does not crash when `Pop` is missing (nil-safe already).

## Out of scope (this slice)

- New **.icns** / App Store icon pipeline.
- Redesign of **Settings** tab layout beyond minor motion.
- **User-toggle** to disable motion/sound (accessibility) — recommended follow-up.

## Further notes

- **Reduce Motion**: main window gates repeating symbol effects and brand glow; floating panel skips fade when `NSWorkspace.accessibilityDisplayShouldReduceMotion` is on.
- Optional: user-facing **Settings** toggle to silence UI sounds independently of system sounds.
