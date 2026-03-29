---
name: Leo EPUB Reader Bridge Patterns
description: JS↔Swift bridge architecture for Leo's foliate-js reader, progress bar + TOC navigation feature design
type: project
---

Leo uses a `WKWebView` (FoliateReaderView) hosting a foliate-js reader served from localhost (LocalServer).

**Bridge pattern**: JS calls `window.webkit.messageHandlers.leoReader.postMessage({type, payload})`. Swift calls back via `webView.evaluateJavaScript(...)`.

**Coordinator access**: `ReaderCoordinatorBridge` is a `@StateObject ObservableObject` holding a `weak var coordinator`. FoliateReaderView accepts `onCoordinatorReady: ((Coordinator) -> Void)?` and calls it in `makeNSView`. This gives ReaderView imperative access to call `requestTOC()` / `goToTocItem()` without a full architecture change.

**Progress bar**: Pure JS/CSS in `reader.html` + `reader.js`. `updateProgressBar(fraction, chapterTitle)` is called from the `relocate` event. Elements: `#leo-progress-fill` (3px bar, `--leo-accent` CSS var), `#leo-progress-label` (chapter + %). Accent color is theme-aware (light=#007AFF, dark=#4CA6FF, sepia=#B87333).

**TOC**: `window.getTableOfContents()` flattens `view.book.toc` recursively into `[{label, href, depth}]`. `window.goToTocItem(href)` calls `view.goTo(href)`. Swift side: `requestTOC()` calls `JSON.stringify(window.getTableOfContents())` and parses back into `[TOCItem]`.

**Why:** Needed reading progress visibility and chapter navigation without altering the foliate-js view layer.
