# Foliate-js upstream pin (Leo)

**Repository:** [johnfactotum/foliate-js](https://github.com/johnfactotum/foliate-js)  
**Vendored copy:** [`Sources/Resources/web/foliate-js`](../Sources/Resources/web/foliate-js) (nested git checkout)

## Current pin

| Field | Value |
|--------|--------|
| **Commit** | `399248a67a8862ffb5e6463a33f9d52b317ca2eb` |
| **Short** | `399248a` |
| **Upstream date** | 2026-03-05 (author timezone +0800) |
| **Subject** | `Run eslint --fix` |

Verify locally:

```bash
git -C Leo/Sources/Resources/web/foliate-js rev-parse HEAD
```

Upstream notes the library is **not API-stable**; treat bumps as **merge + regression** work, not “drop in latest”.

## Bump process

1. **Branch** per Leo workflow (`leo/v1.0-digital-vellum` per AGENTS.md).
2. In the vendored repo:
   ```bash
   cd Leo/Sources/Resources/web/foliate-js
   git fetch origin
   git checkout <desired-commit-or-branch>
   ```
3. Reconcile **Leo-owned** files if any (e.g. `reader.js` / `reader.html` one level up under `web/` that import foliate-js) — diff for API breaks.
4. Run **`cd Leo && swift test`** and reader **`./scripts/run-ux-tests.sh`** when reader or AX behavior may change.
5. Update the **Current pin** table in this file.

## Why this file exists

Single place for **audit + support** (“which foliate-js revision ships?”) without spelunking nested `.git`.
