# Readium Swift toolkit — macOS feasibility (Leo)

**Date:** 2026-03-30  
**Verdict (default):** **NO-GO** for replacing Foliate-js in Leo on a short horizon via Readium Swift **as a native macOS SwiftPM library**. A **time-boxed spike** may re-open this if UIKit-on-Mac (Catalyst) or an upstream macOS story lands.

**Primary code today:** [`Sources/Views/FoliateReaderView.swift`](Sources/Views/FoliateReaderView.swift) (WKWebView + loopback HTTP + `leoReader` bridge).

---

## Verified constraints (re-check when re-evaluating)

| Fact | Source | As of |
|------|--------|--------|
| `readium/swift-toolkit` **Package.swift** declares **`platforms: [.iOS("15.0")]`** only (tag **3.8.0**) | [raw Package.swift 3.8.0](https://raw.githubusercontent.com/readium/swift-toolkit/3.8.0/Package.swift) | 2026-03-30 |
| **ReadiumShared** links **UIKit** | same file, `ReadiumShared` `linkerSettings` | 2026-03-30 |
| **Swift Package Index:** **iOS** builds **succeeded**; **macOS (SPM)** and **macOS (Xcode)** builds **failed** for 3.8.0 / develop on listed Swift 6.x rows | [SPI builds](https://swiftpackageindex.com/readium/swift-toolkit/builds) | 2026-03-30 |
| Readium Mobile page mentions **macOS** + **Apple silicon** | [readium.org/mobile](https://readium.org/mobile/) | 2026-03-30 |

**Interpretation:** Official docs still mention macOS, but the **published SPM manifest is iOS-first** and **SPI does not show a green macOS package build**. For Leo’s **AppKit + SwiftUI macOS executable**, treat integration as **unproven** until a local Xcode/SPM experiment compiles and runs.

---

## Leo feature parity checklist (must hold for any replacement)

Use this in a spike; tick **Pass / Fail / N/A** with notes.

### Rendering & navigation

- [ ] Reflow EPUB with user font size, line height, theme, spread mode (see `LeoReadingChromePreferences` in FoliateReaderView).
- [ ] **Horizontal / vertical** text direction (`textDirection`).
- [ ] Restore **position** from `BookLocator` on open; emit **relocate** events for progress.
- [ ] **TOC** load and navigation.
- [ ] **In-book search** (Foliate exposes search API; coordinator forwards queries).

### Dictionary & learning loop

- [ ] **Word tap** → resolve segment → coordinates for popup placement.
- [ ] **Popup actions:** mark known, add to SRS, set familiarity — wired to `FamiliarityTracker` / FSRS (see `PopupAction`).
- [ ] **Familiarity / review-card badges** in popup (`familiarityForWord`, `hasReviewCardForWord`).
- [ ] Optional: **expression / MWE** handling if/when implemented in Foliate bridge (future parity).

### Audio & tests

- [ ] **Read aloud** path comparable to current (InWorld / system speech); word-level sync is a **nice-to-have** with explicit gap acceptance.
- [ ] **UI tests:** locator capture, dictionary AX hooks (`LEO_UI_TEST_*` env vars in ReaderView) — either preserved or consciously redesigned.

### Infra & security

- [ ] **Loopback-only** server story or elimination of extra HTTP surface (see [`leo-threat-model.md`](leo-threat-model.md)).
- [ ] **PDF:** today PDF may be **reflowed to EPUB** for Foliate; native Readium **PDF navigator** is a separate path — decide explicitly.

---

## Integration paths (if revisiting)

1. **UIKit on Mac (Catalyst)**  
   Host Readium **Navigator** inside a `UIViewController` bridged into SwiftUI. **Risk:** App identity, windowing, and SwiftUI embedding complexity; still **verify** on Apple Silicon with Leo’s minimum OS.

2. **Fork / patch swift-toolkit** for macOS  
   **Risk:** Ongoing merge burden; only if team commits long-term.

3. **Keep Foliate-js; optionally evaluate Readium Web (TS)** inside WKWebView  
   Still a **web renderer**; migration cost for **Leo-specific** `reader.js` / `leoReader` bridge — not “native win,” only standards alignment.

---

## GO / NO-GO criteria

| Outcome | Condition |
|---------|-----------|
| **GO (pilot)** | SPM (or Xcode) **links** ReadiumNavigator into Leo-style app on **macOS 15+**; **parity checklist** passes for **must-have** rows; performance acceptable on **large Chinese EPUBs** you care about. |
| **NO-GO** | No clean **macOS** link; or parity failures on **selection / locator / TOC / search** within agreed time box. |

**Default:** **NO-GO** until a spike changes the evidence.

---

## References

- [readium/swift-toolkit](https://github.com/readium/swift-toolkit)  
- [Swift Package Index — Readium](https://swiftpackageindex.com/readium/swift-toolkit)  
- [foliate-js README (stability)](https://github.com/johnfactotum/foliate-js/blob/main/README.md)  
- [Foliate upstream pin](docs/foliate-upstream.md)
