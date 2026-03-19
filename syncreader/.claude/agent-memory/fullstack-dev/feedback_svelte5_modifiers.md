---
name: Svelte 5 does not support event modifier syntax
description: Svelte 5 dropped onclick|stopPropagation and similar modifier shorthands — use inline handlers instead
type: feedback
---

Svelte 5 removed the `on:event|modifier` (and `onevent|modifier`) syntax from Svelte 3/4. Writing `onclick|stopPropagation={handler}` produces a compile error: "not a valid attribute name".

**Why:** Breaking change in Svelte 5's event system — events are now plain DOM attributes, modifiers must be applied manually in the handler body.

**How to apply:** Any time stopPropagation, preventDefault, or other modifiers are needed in a Svelte 5 component, write an explicit inline handler:
- Instead of `onclick|stopPropagation={fn}` → `onclick={(e) => { e.stopPropagation(); fn(); }}`
- Instead of `onsubmit|preventDefault={fn}` → `onsubmit={(e) => { e.preventDefault(); fn(e); }}`
