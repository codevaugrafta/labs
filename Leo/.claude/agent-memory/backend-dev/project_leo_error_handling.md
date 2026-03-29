---
name: Leo error handling audit
description: try? policy decisions and reading position persistence flow for Leo macOS EPUB reader app
type: project
---

## Error handling policy (applied 2026-03-28)

**Critical paths — replaced with do/catch + NSLog:**
- `Book.locator` getter/setter: BookLocator JSON encode/decode
- `ReaderView.persistLocation`: modelContext.save() — lost save = lost reading position
- `ReaderView.markBookOpened`: modelContext.save()
- `ContentView.deleteBook`: removeItem (best-effort but logged) + modelContext.save()
- `ContentView.importBook`: pre-copy removeItem now logs; modelContext.save() was already do/catch
- `ContentView.importEnvironmentTestBookIfNeeded` / `seedUITestFSRSCardIfNeeded`: modelContext.save()
- `FoliateReaderView.Coordinator`: goToTocItem, openCurrentBook, pushReaderChrome, showPopupInJS, scheduleContextualLookup, requestTOC — all JSONSerialization calls

**Non-critical — kept as try? with comment:**
- `LeoRuntime.prepareDirectories`: createDirectory — directories may already exist; boot-time only
- `ContentView.convertPDFBookToReflowEPUB`: createDirectory before conversion — same reason

## Reading position persistence flow (verified complete)

1. JS `relocate` event fires on page turn/scroll
2. `reader.js` posts `{ type: 'relocate', payload: { cfi, fraction } }` to Swift
3. `FoliateReaderView.Coordinator.userContentController` case `"relocate"` builds `BookLocator` and calls `onRelocate`
4. `ReaderView.persistLocation` writes `book.locator = locator` (JSON-encodes to `book.lastLocator: Data`) + `modelContext.save()`
5. On next book open: `ReaderView` reads `book.locator` → passes as `initialLocator` to `FoliateReaderView`
6. Coordinator stores it; JS bridge `ready` fires → `openCurrentBook()` serializes `{ url, locator: cfi }` → JS `openBook(request)` → `view.init({ lastLocation: locator })` restores position inside foliate-js

No separate `goTo(cfi)` call is needed — `view.init()` handles restoration internally. Fallback `view.init({ showTextStart: true })` fires if the stored locator is invalid.

**Why:** localLocator on `Book` is `Data?` column in SwiftData. The `Book.locator` computed property is the only encode/decode point — keep it as the single source of truth.
