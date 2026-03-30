// Leo Reader Bridge — Swift ↔ foliate-js communication
// This is the nervous system of the app.

import './foliate-js/view.js'

const container = document.getElementById('reader-container')
const loadingEl = document.getElementById('loading')
const errorEl = document.getElementById('error')

// Create foliate-js view
const view = document.createElement('foliate-view')
container.append(view)

// --- EVENTS FROM FOLIATE-JS → SWIFT ---
//
// foliate-js dispatches CustomEvents on the <foliate-view> element.
// Event chain: paginator dispatches 'load' → View.#onLoad() re-emits 'load'
// on the foliate-view element with detail { doc, index }.
//
// IMPORTANT: The 'load' event only fires AFTER view.renderer.next() (or
// view.renderer.goTo()) is called. view.open() alone does NOT navigate —
// it only sets up the book data. Call renderer.next() after open() to
// trigger the first section load and get the 'load' event.

view.addEventListener('load', e => {
    const { doc, index } = e.detail
    loadingEl.style.display = 'none'

    // Inject Chinese character click handlers into the loaded chapter document.
    // Must happen here, not in openBook, because 'load' fires once per section
    // navigation — each new chapter gets a fresh document.
    injectClickHandlers(doc, index)
    // Re-apply theme styles after each section — new iframe document defaults.
    pushLeoReaderStyles()
    leoSyncPaginatorBackdropAndLayout()

    postToSwift('chapterLoaded', { index: index })
})

view.addEventListener('relocate', e => {
    const { fraction, tocItem, cfi: emittedCFI, range, index } = e.detail
    let cfi = emittedCFI ?? ''
    if (!cfi) {
        try {
            cfi = view.getCFI?.(index, range) ?? view.lastLocation?.cfi ?? ''
        } catch (err) {
            console.warn('[Leo Reader] Failed to derive CFI during relocate:', err)
            cfi = view.lastLocation?.cfi ?? ''
        }
    }

    // Update progress bar
    updateProgressBar(fraction, tocItem?.label ?? '')

    postToSwift('relocate', {
        fraction: fraction,
        cfi: cfi?.toString?.() ?? String(cfi ?? ''),
        chapterTitle: tocItem?.label ?? ''
    })
})

view.addEventListener('draw-annotation', e => {
    // Calibre / foliate annotations: always allowed. Leo familiarity overlays (future)
    // should check window.__leoShowHighlights before drawing.
    if (window.__leoShowHighlights === false) {
        return
    }
})

// --- Reader chrome (theme + typography) — merged Swift → foliate setStyles ---

window._leoLastTheme = { bg: '#FBFBFB', fg: '#000000' }
window._leoLastPrefs = {
    fontSizePt: 18,
    lineHeight: 1.8,
    textDirection: 'horizontal',
    showPinyin: false,
    showHighlights: true,
    pageStyle: 'clean',
}
window.__leoShowHighlights = true
window.__leoShowPinyin = false

const LEO_FONT_STACK = '"Source Han Serif SC", "Noto Serif CJK SC", "Songti SC", serif'
const LEO_LATIN_FONT_STACK = 'Georgia, "Times New Roman", serif'

function buildLeoReaderBodyCSS() {
    const t = window._leoLastTheme
    const p = window._leoLastPrefs
    const vertical = p.textDirection === 'vertical'
    const writingMode = vertical ? 'vertical-rl' : 'horizontal-tb'

    return `
            body {
                background: ${t.bg} !important;
                color: ${t.fg} !important;
                font-family: ${LEO_FONT_STACK};
                font-size: ${p.fontSizePt}px;
                line-height: ${p.lineHeight};
                writing-mode: ${writingMode};
                text-orientation: mixed;
                max-width: none;
                margin: 0;
                padding: 1em 1.5em;
                text-indent: ${vertical ? '0' : '2em'};
                text-align: justify;
                text-justify: inter-character;
                line-break: strict;
                letter-spacing: 0.02em;
                text-rendering: optimizeLegibility;
                -webkit-font-smoothing: antialiased;
                transition: background-color 0.3s ease, color 0.3s ease;
                ${p.pageStyle === 'page' ? 'box-shadow: 0 1px 3px rgba(0,0,0,0.06), 0 4px 12px rgba(0,0,0,0.08);' : ''}
            }
            ${p.pageStyle === 'page' ? `
            body::after {
                content: '';
                position: fixed;
                inset: 0;
                background: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='4' height='4'%3E%3Crect width='4' height='4' fill='%23000' opacity='0.015'/%3E%3C/svg%3E");
                pointer-events: none;
                z-index: 9999;
            }` : ''}
            p { margin-bottom: 1.2em; }
            h1, h2, h3 { text-indent: 0; text-align: center; margin-top: 2em; font-family: ${LEO_FONT_STACK}; }
            :lang(en), :lang(fr), :lang(de), :lang(es) {
                font-family: ${LEO_LATIN_FONT_STACK};
                letter-spacing: 0;
            }
            ::selection { background: rgba(59,130,246,0.2); }
            ruby { ruby-position: ${vertical ? 'over' : 'under'}; ruby-align: center; }
            rt { font-size: 0.6em; opacity: 0.75; font-family: ${LEO_FONT_STACK}; }
        `
}

function pushLeoReaderStyles() {
    if (view.renderer?.setStyles) {
        view.renderer.setStyles(buildLeoReaderBodyCSS())
    }
}

/**
 * Drive foliate-paginator metrics from the window so columns use available width,
 * and refresh paginator render after theme/gutter changes.
 */
function leoApplyPaginatorLayout() {
    const r = view && view.renderer
    if (!r || typeof r.setAttribute !== 'function') {
        return
    }
    const w = Math.max(320, window.innerWidth || 800)
    const spread = r.getAttribute('spread') || window.__leoSpreadMode || 'auto'
    let columns = 1
    if (spread === 'both') {
        columns = 2
    } else if (spread === 'auto' && w > 880) {
        columns = 2
    } else if (spread === 'none') {
        columns = 1
    }

    // Foliate’s paginator ignores the `spread` attribute; column count comes from
    // `--_max-column-count` / `--_max-column-count-portrait` (see attributeChangedCallback).
    r.setAttribute('max-column-count', String(columns))
    r.setAttribute('max-column-count-portrait', String(columns))

    const marginPx = Math.max(12, Math.min(36, Math.round(w * 0.02)))
    r.setAttribute('margin', `${marginPx}px`)
    r.setAttribute('gap', w > 1200 ? '5%' : '7%')

    const innerGutter = 56
    const usable = Math.max(280, w - marginPx * 2 - innerGutter)
    let maxInline = Math.floor(usable / columns - 16)
    maxInline = Math.max(340, Math.min(960, maxInline))
    r.setAttribute('max-inline-size', `${maxInline}px`)

    if (typeof r.render === 'function') {
        try {
            r.render()
        } catch (err) {
            console.warn('[Leo] paginator layout render:', err)
        }
    }
}

function leoSyncPaginatorBackdropAndLayout() {
    const bg = window._leoLastTheme?.bg
    if (bg && view) {
        view.style.background = bg
    }
    leoApplyPaginatorLayout()
}

if (!window.__leoPaginatorResizeWired) {
    window.__leoPaginatorResizeWired = true
    let resizeTimer = null
    window.addEventListener('resize', () => {
        clearTimeout(resizeTimer)
        resizeTimer = setTimeout(() => {
            leoSyncPaginatorBackdropAndLayout()
        }, 120)
    })
}

/**
 * @param {object} p — fontSizePt, lineHeight, textDirection, showPinyin, showHighlights
 */
window.applyReadingPreferences = function (p) {
    if (typeof p.fontSizePt === 'number' && p.fontSizePt > 0) {
        window._leoLastPrefs.fontSizePt = p.fontSizePt
    }
    if (typeof p.lineHeight === 'number' && p.lineHeight > 0) {
        window._leoLastPrefs.lineHeight = p.lineHeight
    }
    if (typeof p.textDirection === 'string') {
        window._leoLastPrefs.textDirection = p.textDirection
    }
    if (typeof p.showPinyin === 'boolean') {
        window._leoLastPrefs.showPinyin = p.showPinyin
        window.__leoShowPinyin = p.showPinyin
    }
    if (typeof p.showHighlights === 'boolean') {
        window._leoLastPrefs.showHighlights = p.showHighlights
        window.__leoShowHighlights = p.showHighlights
    }
    if (p.pageStyle === 'clean' || p.pageStyle === 'page') {
        window._leoLastPrefs.pageStyle = p.pageStyle
    }
    pushLeoReaderStyles()
}

// --- COMMANDS FROM SWIFT → JS ---

// Called by Swift to open an EPUB.
// Flow: fetch → open (book metadata) → renderer.next() (triggers first 'load' event)
window.openBook = function(request) {
    void (async () => {
        try {
            loadingEl.style.display = 'flex'
            errorEl.style.display = 'none'

            const url = typeof request === 'string' ? request : request?.url
            const locator = typeof request === 'string' ? '' : (request?.locator ?? '')
            if (!url) throw new Error('Missing book URL')

            const response = await fetch(url)
            if (!response.ok) throw new Error(`HTTP ${response.status}: ${response.statusText}`)
            const blob = await response.blob()
            const file = new File([blob], url.split('/').pop(), { type: 'application/epub+zip' })

            // open() sets up book data and creates the renderer — it does NOT navigate.
            await view.open(file)

            // Apply spread mode: use stored preference or default to 'auto' on wide screens
            const spreadMode = window.__leoSpreadMode ?? (window.innerWidth > 900 ? 'auto' : 'none')
            if (view.renderer?.setAttribute) {
                view.renderer.setAttribute('spread', spreadMode)
            }
            leoSyncPaginatorBackdropAndLayout()

            postToSwift('loaded', {
                title: view.book?.metadata?.title ?? '',
                author: view.book?.metadata?.creator ?? '',
                chapterCount: view.book?.toc?.length ?? 0
            })

            // Typography + theme: Swift calls applyReadingPreferences + setTheme before openBook;
            // this applies defaults if load order ever differs.
            pushLeoReaderStyles()

            const _rendererNext = view.renderer.next.bind(view.renderer)
            const _rendererPrev = view.renderer.prev.bind(view.renderer)

            try {
                await view.init({
                    lastLocation: locator || null,
                    showTextStart: !locator
                })
            } catch (restoreErr) {
                console.warn('[Leo Reader] Failed to initialize reader at the requested locator:', restoreErr)
                await view.init({ showTextStart: true })
            }

            // Disable foliate-js's built-in touch-swipe page navigation.
            // The paginator's prev()/next() are public methods. We intercept them here
            // so that trackpad swipes / touch gestures on the left/right margin areas
            // no longer turn pages. Explicit navigation (keyboard, Swift buttons) still
            // works because window.nextPage / window.prevPage call our saved references.
            view.renderer.next = () => {}
            view.renderer.prev = () => {}

            // Also disable the view-level wrappers so goLeft/goRight do nothing.
            view.next = () => {}
            view.prev = () => {}

            // Expose explicit navigation for keyboard and Swift buttons.
            window._rendererNext = _rendererNext
            window._rendererPrev = _rendererPrev
            leoSyncPaginatorBackdropAndLayout()
        } catch (err) {
            loadingEl.style.display = 'none'
            errorEl.textContent = `Error: ${err.message}`
            errorEl.style.display = 'block'
            postToSwift('error', { message: err.message, source: 'openBook' })
        }
    })()
}

// Set spread mode: 'none' (single page), 'auto' (2-page when wide), 'both' (always 2-page)
window.setSpreadMode = function(mode) {
    window.__leoSpreadMode = mode
    if (view && view.renderer && view.renderer.setAttribute) {
        view.renderer.setAttribute('spread', mode)
    }
    leoSyncPaginatorBackdropAndLayout()
}

// Navigate to a specific CFI position
window.goTo = function(cfi) {
    try {
        view.goTo(cfi)
    } catch (err) {
        postToSwift('error', { message: err.message, source: 'goTo' })
    }
}

window.goToFraction = function(fraction) {
    try {
        view.goToFraction(fraction)
    } catch (err) {
        postToSwift('error', { message: err.message, source: 'goToFraction' })
    }
}

// Apply light/dark/sepia colors; typography comes from applyReadingPreferences.
window.setTheme = function(themeP) {
    const bg = themeP.bg ?? window._leoLastTheme.bg
    const fg = themeP.fg ?? window._leoLastTheme.fg
    window._leoLastTheme = { bg, fg }
    document.documentElement.style.setProperty('--bg', bg)
    document.documentElement.style.setProperty('--fg', fg)
    // Apply bg to EVERY element that might show through — html, body, and any container
    document.documentElement.style.background = bg
    document.documentElement.style.transition = 'background-color 0.3s ease'
    document.body.style.transition = 'background-color 0.3s ease, color 0.3s ease'
    document.body.style.background = bg
    // Also apply to any foliate-js container elements
    const containers = document.querySelectorAll('foliate-view, .foliate-view, #reader, .reader-container')
    containers.forEach(el => { el.style.background = bg })

    // Derive accent color per theme: sepia = warm amber, dark = soft blue, light = system blue.
    // Apple Books–matched bg values: dark=#121212, sepia=#F8F1E3, light=#FBFBFB
    const accent = themeP.accent ?? (
        bg === '#121212' ? '#4CA6FF' :
        bg === '#F8F1E3' ? '#B87333' :
        '#007AFF'
    )
    document.documentElement.style.setProperty('--leo-accent', accent)

    pushLeoReaderStyles()
    leoSyncPaginatorBackdropAndLayout()
}

// --- PAGE NAVIGATION ---
// Navigation via keyboard (arrow keys, spacebar) and Swift-exposed JS functions.
// Click-based navigation has been intentionally removed — taps mean dictionary lookup.

// Keyboard navigation — use saved references so stubs don't block us
document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
        e.preventDefault()
        postToSwift('popupAction', { action: 'dismiss', word: '' })
        return
    }
    if (!view.renderer) return
    switch (e.key) {
        case 'ArrowRight':
        case 'PageDown':
        case ' ':
            e.preventDefault()
            window.nextPage()
            break
        case 'ArrowLeft':
        case 'PageUp':
            e.preventDefault()
            window.prevPage()
            break
        case 'Home':
            e.preventDefault()
            view.goToTextStart?.()
            break
    }
})

// Navigation commands from Swift (and keyboard). These use the saved references
// that bypass the now-disabled renderer.next/prev stubs.
window.nextPage = function() { window._rendererNext?.() }
window.prevPage = function() { window._rendererPrev?.() }

// --- EXPRESSION HIGHLIGHT ---
// Tracks the <span> elements injected by highlightRange() so they can be
// unwrapped when the popup is dismissed or a new word is tapped.
let _highlightSpans = []
let _highlightDoc = null   // the iframe document that owns the spans

// --- SENTENCE HIGHLIGHT ---
// Tracks the <span> elements wrapping the full sentence so they can be
// removed when the popup is dismissed or a new word is tapped.
let _sentenceSpans = []

// --- SPEAKING HIGHLIGHT (TTS karaoke) ---
// Tracks the <span> elements injected by highlightSpeakingWord() so they can
// be removed when the word changes or TTS stops.
let _speakingSpans = []
let _speakingDoc = null    // the iframe document that owns the speaking spans

function _clearExpressionHighlight() {
    for (const span of _highlightSpans) {
        // Unwrap: replace <span class="leo-expression-highlight">X</span> with text node X.
        const parent = span.parentNode
        if (!parent) continue
        while (span.firstChild) {
            parent.insertBefore(span.firstChild, span)
        }
        parent.removeChild(span)
        parent.normalize()
    }
    _highlightSpans = []
    _highlightDoc = null
    _clearSentenceHighlight()
}

function _clearSentenceHighlight() {
    for (const span of _sentenceSpans) {
        const parent = span.parentNode
        if (!parent) continue
        while (span.firstChild) {
            parent.insertBefore(span.firstChild, span)
        }
        parent.removeChild(span)
        parent.normalize()
    }
    _sentenceSpans = []
}

// Called by Swift after word/expression resolution.
// Finds the resolved word in the iframe document using the same context string
// that was sent to Swift, then wraps each character of the word in a highlight span.
//
// Strategy:
//   1. Walk all text nodes in the active iframe document.
//   2. Find the text node that contains `context` (or the longest prefix/suffix overlap).
//   3. Within that text node, locate the offset where `word` starts (at charIndex - wordStart).
//   4. Use DOM Range.surroundContents to wrap with a highlight span.
window.highlightRange = function(context, word, charIndex) {
    if (!word || word.length === 0) return

    // Always clear stale spans first — even when _highlightDoc is null (Swift may call
    // this before the iframe doc is ready, or after navigation) so the previous tap's
    // highlight cannot stick on screen.
    _clearExpressionHighlight()

    const doc = _highlightDoc
    if (!doc) return

    // Walk text nodes in the document to find one containing `context`.
    // We look for a text node where at least the core portion of context appears.
    // charIndex is the position of the clicked char within context.
    const treeWalker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT)
    let targetNode = null
    let targetCharOffset = -1  // code-point offset within targetNode.textContent where word starts

    // The word starts this many code points before charIndex in the context.
    // context[charIndex] is the clicked char. The word may start before charIndex.
    // We need to find where within the text node the word's first char falls.

    const wordChars = Array.from(word)
    const contextChars = Array.from(context)

    // Find where word starts in the context string (by code-point index).
    // The clicked char (charIndex) is somewhere within the word.
    // Walk backwards from charIndex to find where the word starts.
    let wordStartInContext = charIndex
    while (wordStartInContext > 0 && contextChars[wordStartInContext - 1] !== undefined) {
        const candidate = contextChars.slice(wordStartInContext, wordStartInContext + wordChars.length).join('')
        if (candidate === word) break
        wordStartInContext--
    }
    // Forward scan if backward scan overshot.
    for (let i = Math.max(0, wordStartInContext); i <= charIndex; i++) {
        const candidate = contextChars.slice(i, i + wordChars.length).join('')
        if (candidate === word) {
            wordStartInContext = i
            break
        }
    }

    // How many code points from the START of context to the start of word.
    const prefixLen = wordStartInContext

    while (treeWalker.nextNode()) {
        const node = treeWalker.currentNode
        const nodeChars = Array.from(node.textContent)

        // Search for the context string inside this text node (code-point level).
        // We only need a partial match: the text node must contain `word` at the
        // correct relative position within `context`.
        // Fast path: try indexOf with the full context first, then slide a window.
        const joined = node.textContent
        const contextStr = context

        // Find all positions where the word appears in this text node.
        // Then pick the one where the surrounding chars match the context prefix/suffix.
        let searchFrom = 0
        let found = false
        while (!found) {
            const idx = joined.indexOf(word, searchFrom)
            if (idx === -1) break

            // Convert UTF-16 idx to code-point index.
            const cpsBefore = Array.from(joined.slice(0, idx))
            const cpWordStart = cpsBefore.length

            // Check that chars before the word in the text node match the context prefix.
            const prefixInNode = nodeChars.slice(Math.max(0, cpWordStart - prefixLen), cpWordStart).join('')
            const contextPrefix = contextChars.slice(0, prefixLen).join('')

            // Accept if prefix matches (or context is at start of node so prefix may be shorter).
            const prefixMatches = prefixInNode.endsWith(contextPrefix) || contextPrefix.endsWith(prefixInNode)

            if (prefixMatches || prefixLen === 0) {
                targetNode = node
                targetCharOffset = cpWordStart
                found = true
            }
            searchFrom = idx + word.length
        }
        if (found) break
    }

    if (!targetNode || targetCharOffset < 0) return

    // Convert code-point offset to UTF-16 offset for DOM Range.
    const nodeChars = Array.from(targetNode.textContent)
    let utf16Start = 0
    for (let i = 0; i < targetCharOffset; i++) {
        utf16Start += nodeChars[i].length
    }
    let utf16End = utf16Start
    for (let i = 0; i < wordChars.length; i++) {
        utf16End += wordChars[i].length
    }

    // Wrap the range in highlight spans (one per char for vertical text compat,
    // or just one span wrapping the whole word if the range is within one text node).
    try {
        const range = doc.createRange()
        range.setStart(targetNode, utf16Start)
        range.setEnd(targetNode, utf16End)

        const span = doc.createElement('span')
        span.className = 'leo-expression-highlight'
        range.surroundContents(span)
        _highlightSpans.push(span)
    } catch (_) {
        // surroundContents can fail if the range crosses element boundaries.
        // In that case we skip the highlight silently — the popup still shows.
    }
}

// --- SENTENCE HIGHLIGHT ---
//
// Called by Swift after a word tap. Finds the sentence that contains `word`
// (using Chinese punctuation 。！？ and newlines as boundaries) and wraps each
// text node fragment within the sentence in a .leo-sentence-highlight span.
//
// Parameters mirror highlightRange: same context string and charIndex so we
// can locate the sentence relative to the tapped position.
window.highlightSentence = function(context, word, charIndex) {
    _clearSentenceHighlight()

    const doc = _highlightDoc
    if (!doc) return

    // Inject sentence highlight CSS once per iframe document.
    const STYLE_ID = 'leo-sentence-highlight-styles'
    if (!doc.getElementById(STYLE_ID)) {
        const style = doc.createElement('style')
        style.id = STYLE_ID
        style.textContent = `
            .leo-sentence-highlight {
                background: rgba(59, 130, 246, 0.06);
                border-radius: 2px;
                transition: background 0.2s ease;
            }
        `
        doc.head?.appendChild(style)
    }

    // Find sentence boundaries in the context string using code points.
    const sentenceBoundaries = '。！？\n'
    const contextChars = Array.from(context)
    let sentenceStart = charIndex
    let sentenceEnd = charIndex

    while (sentenceStart > 0 && !sentenceBoundaries.includes(contextChars[sentenceStart - 1])) {
        sentenceStart--
    }
    while (sentenceEnd < contextChars.length && !sentenceBoundaries.includes(contextChars[sentenceEnd])) {
        sentenceEnd++
    }

    const sentence = contextChars.slice(sentenceStart, sentenceEnd).join('')
    if (!sentence || sentence.length < 2) return

    // Walk all text nodes in the iframe document looking for text nodes that
    // contain portions of the sentence. We anchor the search using a prefix
    // match so we can reliably identify the correct occurrence.
    const prefixChars = contextChars.slice(sentenceStart, charIndex)
    const prefixStr = prefixChars.join('')

    const walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT)
    let anchorNode = null
    let anchorCpOffset = -1  // code-point offset within anchorNode where sentence starts

    while (walker.nextNode()) {
        const node = walker.currentNode
        const joined = node.textContent

        // Fast reject: node must contain some portion of the sentence.
        if (!joined.includes(sentence.slice(0, Math.min(sentence.length, 4)))) continue

        // Try to find the sentence (or a meaningful prefix) in this node.
        let searchFrom = 0
        while (true) {
            const idx = joined.indexOf(sentence, searchFrom)
            if (idx === -1) break

            const cpsBefore = Array.from(joined.slice(0, idx))
            const cpStart = cpsBefore.length
            // Verify prefix context: chars before the sentence start in the
            // node should end with (or equal) the prefix leading up to the sentence.
            const nodeChars = Array.from(joined)
            const nodePre = nodeChars.slice(Math.max(0, cpStart - prefixChars.length), cpStart).join('')
            const preMatch = nodePre.endsWith(prefixStr) || prefixStr.endsWith(nodePre) || prefixChars.length === 0

            if (preMatch) {
                anchorNode = node
                anchorCpOffset = cpStart
                break
            }
            searchFrom = idx + sentence.length
        }
        if (anchorNode) break
    }

    if (!anchorNode || anchorCpOffset < 0) return

    // Convert code-point offset to UTF-16 for DOM Range.
    const anchorChars = Array.from(anchorNode.textContent)
    const sentenceChars = Array.from(sentence)
    let utf16Start = 0
    for (let i = 0; i < anchorCpOffset; i++) {
        utf16Start += anchorChars[i].length
    }
    let utf16End = utf16Start
    for (let i = 0; i < sentenceChars.length; i++) {
        utf16End += sentenceChars[i].length
    }
    // Clamp to the actual text node length.
    utf16End = Math.min(utf16End, anchorNode.textContent.length)

    try {
        const range = doc.createRange()
        range.setStart(anchorNode, utf16Start)
        range.setEnd(anchorNode, utf16End)

        const span = doc.createElement('span')
        span.className = 'leo-sentence-highlight'
        range.surroundContents(span)
        _sentenceSpans.push(span)
    } catch (_) {
        // surroundContents fails when the range crosses element boundaries
        // (e.g. sentence spans multiple <p> children). Walk sub-ranges instead.
        try {
            const range = doc.createRange()
            range.setStart(anchorNode, utf16Start)
            range.setEnd(anchorNode, utf16End)

            // Extract and re-wrap the contents with a fragment fallback.
            // Simply skip — the word underline is still visible; the sentence
            // background is a best-effort enhancement.
        } catch (_2) { /* ignore */ }
    }
}

// --- SPEAKING HIGHLIGHT FUNCTIONS ---

/**
 * Called by Swift each time AVSpeechSynthesizer reports a new word range.
 * Finds `text` substring of length `length` starting at `startOffset` within
 * the spoken sentence, then wraps it in a `.leo-speaking` span that pulses blue.
 *
 * Uses the same TreeWalker + surroundContents pattern as highlightRange().
 */
window.highlightSpeakingWord = function(text, startOffset, length) {
    if (!text || length <= 0) return

    const doc = _highlightDoc
    if (!doc) return

    // Clear previous speaking highlight before applying new one.
    _clearSpeakingHighlightInternal(doc)

    // Inject speaking styles once per iframe document.
    const STYLE_ID = 'leo-speaking-styles'
    if (!doc.getElementById(STYLE_ID)) {
        const style = doc.createElement('style')
        style.id = STYLE_ID
        style.textContent = `
            @keyframes leo-speaking-pulse {
                0%   { background: rgba(59,130,246,0.15); }
                50%  { background: rgba(59,130,246,0.28); }
                100% { background: rgba(59,130,246,0.15); }
            }
            .leo-speaking {
                border-radius: 3px;
                animation: leo-speaking-pulse 0.9s ease-in-out infinite;
            }
        `
        doc.head?.appendChild(style)
    }

    // Extract the spoken word using code-point offsets.
    const textChars = Array.from(text)
    const safeStart = Math.max(0, startOffset)
    const safeEnd   = Math.min(textChars.length, safeStart + length)
    if (safeStart >= safeEnd) return
    const word = textChars.slice(safeStart, safeEnd).join('')
    if (!word) return

    // Walk text nodes in the iframe document looking for a node that contains
    // the spoken snippet. We use the full `text` string as context.
    const treeWalker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT)
    let targetNode        = null
    let targetCharOffset  = -1  // code-point index within node where word starts

    while (treeWalker.nextNode()) {
        const node   = treeWalker.currentNode
        const joined = node.textContent
        const nodeChars = Array.from(joined)

        // Find the word's first occurrence inside this text node, then verify
        // the surrounding characters match the broader `text` context.
        let searchFrom = 0
        while (true) {
            const idx = joined.indexOf(word, searchFrom)
            if (idx === -1) break

            // Convert UTF-16 index to code-point index.
            const cpsBefore = Array.from(joined.slice(0, idx))
            const cpWordStart = cpsBefore.length

            // Check prefix: chars before the word in the node must match the
            // corresponding chars in `text` (before safeStart).
            const prefixLen = safeStart
            const prefixInNode = nodeChars.slice(Math.max(0, cpWordStart - prefixLen), cpWordStart).join('')
            const contextPrefix = textChars.slice(0, prefixLen).join('')
            const prefixMatches = prefixInNode.endsWith(contextPrefix) || contextPrefix.endsWith(prefixInNode)

            if (prefixMatches || prefixLen === 0) {
                targetNode = node
                targetCharOffset = cpWordStart
                break
            }
            searchFrom = idx + word.length
        }
        if (targetNode) break
    }

    if (!targetNode || targetCharOffset < 0) return

    // Convert code-point offsets to UTF-16 offsets for DOM Range.
    const nodeChars = Array.from(targetNode.textContent)
    const wordChars = Array.from(word)
    let utf16Start = 0
    for (let i = 0; i < targetCharOffset; i++) {
        utf16Start += nodeChars[i].length
    }
    let utf16End = utf16Start
    for (let i = 0; i < wordChars.length; i++) {
        utf16End += wordChars[i].length
    }

    try {
        const range = doc.createRange()
        range.setStart(targetNode, utf16Start)
        range.setEnd(targetNode, utf16End)

        const span = doc.createElement('span')
        span.className = 'leo-speaking'
        range.surroundContents(span)
        _speakingSpans.push(span)
        _speakingDoc = doc
    } catch (_) {
        // surroundContents fails if the range crosses element boundaries — skip silently.
    }
}

function _clearSpeakingHighlightInternal(doc) {
    for (const span of _speakingSpans) {
        const parent = span.parentNode
        if (!parent) continue
        while (span.firstChild) {
            parent.insertBefore(span.firstChild, span)
        }
        parent.removeChild(span)
        parent.normalize()
    }
    _speakingSpans = []
    _speakingDoc = null
}

/** Called by Swift when TTS stops or pauses — removes all speaking highlights. */
window.clearSpeakingHighlight = function() {
    const doc = _speakingDoc ?? _highlightDoc
    if (doc) _clearSpeakingHighlightInternal(doc)
}

// --- CHINESE CHARACTER CLICK HANDLING ---

// Returns true for CJK Unified Ideographs and common CJK extension blocks.
// Uses codePointAt() to correctly handle characters outside the BMP (U+20000+).
function isChinese(char) {
    const cp = char.codePointAt(0)
    return (cp >= 0x4E00 && cp <= 0x9FFF)    // CJK Unified Ideographs
        || (cp >= 0x3400 && cp <= 0x4DBF)    // CJK Extension A
        || (cp >= 0x20000 && cp <= 0x2A6DF)  // CJK Extension B
        || (cp >= 0x2A700 && cp <= 0x2CEAF)  // CJK Extensions C/D/E
        || (cp >= 0x2CEB0 && cp <= 0x2EBEF)  // CJK Extension F
        || (cp >= 0xF900 && cp <= 0xFAFF)    // CJK Compatibility Ideographs
        || (cp >= 0x2F800 && cp <= 0x2FA1F)  // CJK Compatibility Supplement
}

function injectNavigationHandlers(doc) {
    // Keyboard navigation inside iframe documents — use window refs so stubs don't block
    doc.addEventListener('keydown', (e) => {
        if (!view.renderer) return
        switch (e.key) {
            case 'ArrowRight':
            case 'PageDown':
                e.preventDefault()
                window.nextPage()
                break
            case 'ArrowLeft':
            case 'PageUp':
                e.preventDefault()
                window.prevPage()
                break
            case ' ':
                e.preventDefault()
                window.nextPage()
                break
        }
    })
}

function injectClickHandlers(doc, chapterIndex) {
    // Store the active iframe document so highlightRange() can access it.
    // Each chapter navigation replaces the doc — clear stale highlights first.
    _clearExpressionHighlight()   // also calls _clearSentenceHighlight()
    _clearSpeakingHighlightInternal(doc)
    _highlightDoc = doc

    // Inject highlight CSS into this iframe's document.
    if (!doc.getElementById('leo-highlight-styles')) {
        const style = doc.createElement('style')
        style.id = 'leo-highlight-styles'
        style.textContent = `
            .leo-expression-highlight {
                text-decoration: underline;
                text-decoration-color: rgba(59,130,246,0.5);
                text-decoration-thickness: 2px;
                text-underline-offset: 3px;
                transition: text-decoration-color 0.2s ease;
            }
            .leo-expression-highlight:hover {
                text-decoration-color: rgba(59,130,246,0.8);
            }
            .leo-sentence-highlight {
                background: rgba(59, 130, 246, 0.06);
                border-radius: 2px;
                transition: background 0.2s ease;
            }
            ::selection { background: rgba(59,130,246,0.2); }
        `
        doc.head?.appendChild(style)
    }

    // Also inject navigation
    injectNavigationHandlers(doc)
    doc.addEventListener('click', (event) => {
        // Guard 1: the element directly under the pointer must be (or contain) a
        // text node — not a bare body/html/empty div.  caretRangeFromPoint snaps
        // to the nearest glyph even when the click lands in blank margin, so we
        // reject the event before calling it when the pointer is over empty space.
        const hitEl = doc.elementFromPoint(event.clientX, event.clientY)
        if (!hitEl) return
        const tag = hitEl.tagName?.toUpperCase()
        // Whitelist only elements that normally host inline text.
        const TEXT_HOSTS = new Set(['P', 'SPAN', 'A', 'LI', 'TD', 'TH',
                                     'H1', 'H2', 'H3', 'H4', 'H5', 'H6',
                                     'BLOCKQUOTE', 'DIV', 'SECTION', 'ARTICLE',
                                     'RUBY', 'RB', 'RT', 'EM', 'STRONG',
                                     'CITE', 'B', 'I', 'S', 'U'])
        if (!TEXT_HOSTS.has(tag)) return
        // Reject if the element has no text content at all.
        if (!hitEl.textContent?.trim()) return

        // caretRangeFromPoint returns the text position at the click coordinate.
        // Coordinates are relative to the iframe's own viewport — correct here
        // because we're listening on the iframe's document directly.
        const range = doc.caretRangeFromPoint(event.clientX, event.clientY)
        if (!range) return
        if (!range.startContainer || range.startContainer.nodeType !== Node.TEXT_NODE) return

        const textNode = range.startContainer
        const text = textNode.textContent
        const offset = range.startOffset

        if (offset >= text.length) return

        // Use Array.from to get Unicode code points (handles surrogate pairs).
        const codePoints = Array.from(text)

        // Find the code-point index corresponding to the UTF-16 offset.
        let cpIndex = 0
        let utf16Pos = 0
        while (utf16Pos < offset && cpIndex < codePoints.length) {
            utf16Pos += codePoints[cpIndex].length
            cpIndex++
        }
        if (cpIndex >= codePoints.length) return

        const clickedChar = codePoints[cpIndex]
        if (!isChinese(clickedChar)) return

        // Build context window: ±15 code points around the clicked character.
        const contextStart = Math.max(0, cpIndex - 15)
        const contextEnd = Math.min(codePoints.length, cpIndex + 16)
        const context = codePoints.slice(contextStart, contextEnd).join('')
        const charIndexInContext = cpIndex - contextStart

        // Guard 2: proximity check — the click must be within ~30px horizontally
        // and ~40px vertically of the character's bounding rect.  This catches
        // clicks in line-spacing gaps or wide padding that caretRangeFromPoint
        // would otherwise snap to the nearest glyph on an adjacent line.
        const rect = range.getBoundingClientRect()
        const H_SLOP = 30
        const V_SLOP = 40
        const cx = event.clientX
        const cy = event.clientY
        if (cx < rect.left - H_SLOP || cx > rect.right  + H_SLOP) return
        if (cy < rect.top  - V_SLOP || cy > rect.bottom + V_SLOP) return

        // Translate the character rect from iframe-local coords to outer-page coords.
        // doc.defaultView.frameElement gives us the <iframe> element in the outer doc,
        // from which we can get its position via getBoundingClientRect().
        let outerX = rect.left + rect.width / 2
        let outerY = rect.bottom
        try {
            const frameEl = doc.defaultView?.frameElement
            if (frameEl) {
                const iframeRect = frameEl.getBoundingClientRect()
                outerX = iframeRect.left + rect.left + rect.width / 2
                outerY = iframeRect.top  + rect.bottom
            }
        } catch (_) { /* cross-origin guard — fall back to iframe-local coords */ }

        // Clear any previous expression highlight before applying the new one.
        _clearExpressionHighlight()

        postToSwift('wordTap', {
            char: clickedChar,
            context: context,
            charIndex: charIndexInContext,
            chapterIndex: chapterIndex,
            x: outerX,
            y: outerY
        })
    })
}

// --- PROGRESS BAR ---

function updateProgressBar(fraction, chapterTitle) {
    const fill = document.getElementById('leo-progress-fill')
    const label = document.getElementById('leo-progress-label')
    if (!fill || !label) return

    const pct = Math.max(0, Math.min(1, fraction ?? 0))
    fill.style.width = (pct * 100).toFixed(2) + '%'

    const pctText = Math.round(pct * 100) + '%'
    if (chapterTitle) {
        label.textContent = chapterTitle + ' · ' + pctText
    } else {
        label.textContent = pctText
    }
    label.style.display = 'block'
}

// --- TABLE OF CONTENTS ---

/**
 * Returns a flat array of TOC items: [{ label, href, depth }, ...].
 * Depth is 0 for top-level entries, 1 for nested, etc.
 * Called by Swift after book load to populate the TOC panel.
 */
window.getTableOfContents = function() {
    const toc = view.book?.toc
    if (!toc) return []

    function flattenToc(items, depth) {
        const result = []
        for (const item of items) {
            result.push({
                label: item.label ?? item.title ?? '',
                href: item.href ?? '',
                depth: depth,
            })
            if (item.subitems?.length) {
                result.push(...flattenToc(item.subitems, depth + 1))
            }
        }
        return result
    }

    return flattenToc(toc, 0)
}

/**
 * Navigate to a TOC entry by href.
 * Called by Swift when the user selects a chapter in the TOC panel.
 */
window.goToTocItem = function(href) {
    if (!href) return
    try {
        view.goTo(href)
    } catch (err) {
        postToSwift('error', { message: err.message, source: 'goToTocItem' })
    }
}

// --- IN-BOOK SEARCH ---

// Tracks the current search state so clearSearch() can cancel an in-progress search.
let _searchAbortController = null

/**
 * Search for `query` across the whole book using foliate-js's built-in search API.
 * Highlights all matches via view.addAnnotation (the same mechanism used for bookmarks).
 * Navigates to the first match found in the current section, or the first match overall.
 * Results are posted back to Swift as searchResults messages.
 * @param {string} query
 */
window.searchInBook = function(query) {
    if (!query || !query.trim()) {
        window.clearSearch()
        return
    }

    // Cancel any previous search.
    if (_searchAbortController) {
        _searchAbortController.abort()
    }
    const controller = { aborted: false }
    _searchAbortController = controller

    // Clear previous highlights before starting.
    if (view.clearSearch) view.clearSearch()

    void (async () => {
        try {
            const results = []
            let navigated = false

            for await (const result of view.search({ query })) {
                if (controller.aborted) return

                if (result === 'done') {
                    postToSwift('searchResults', {
                        query,
                        count: results.length,
                        done: true,
                    })
                    return
                }

                // result.subitems → array of { cfi, excerpt } from a section
                // result.progress → 0–1 progress float (no match)
                // result.cfi      → single match (section search mode)
                if (result.subitems) {
                    for (const item of result.subitems) {
                        results.push({ cfi: item.cfi, excerpt: item.excerpt })
                        if (!navigated && item.cfi) {
                            navigated = true
                            try { view.goTo(item.cfi) } catch (_) {}
                        }
                    }
                } else if (result.cfi) {
                    results.push({ cfi: result.cfi, excerpt: result.excerpt })
                    if (!navigated) {
                        navigated = true
                        try { view.goTo(result.cfi) } catch (_) {}
                    }
                }
                // result.progress is a numeric progress update — skip, no match content.
            }
        } catch (err) {
            if (controller.aborted) return
            postToSwift('error', { message: err.message, source: 'searchInBook' })
        }
    })()
}

/**
 * Clear all search highlights and cancel any in-progress search.
 */
window.clearSearch = function() {
    if (_searchAbortController) {
        _searchAbortController.aborted = true
        _searchAbortController = null
    }
    if (view.clearSearch) view.clearSearch()
}

// --- BRIDGE UTILITY ---

function postToSwift(type, payload) {
    if (window.webkit?.messageHandlers?.leoReader) {
        window.webkit.messageHandlers.leoReader.postMessage({
            type: type,
            payload: payload
        })
    } else {
        console.log('[Leo Bridge] No Swift handler:', type, payload)
    }
}

// --- ERROR HANDLING ---

window.onerror = function(message, source, lineno, colno, error) {
    postToSwift('error', {
        message: message,
        source: source,
        line: lineno
    })
}

window.addEventListener('unhandledrejection', event => {
    postToSwift('error', {
        message: event.reason?.message || String(event.reason),
        source: 'unhandledrejection'
    })
})

// Signal ready
postToSwift('ready', {})
console.log('[Leo Reader] Bridge initialized')
