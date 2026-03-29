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

window._leoLastTheme = { bg: '#FFFFFF', fg: '#1A1A1A' }
window._leoLastPrefs = {
    fontSizePt: 18,
    lineHeight: 1.7,
    textDirection: 'horizontal',
    showPinyin: false,
    showHighlights: true,
}
window.__leoShowHighlights = true
window.__leoShowPinyin = false

const LEO_FONT_STACK = '"Source Han Serif SC", "Noto Serif SC", "PingFang SC", "Hiragino Sans GB", serif'

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
                max-width: ${vertical ? 'none' : '35em'};
                margin: 0 auto;
                padding: 2em 3em;
                text-indent: ${vertical ? '0' : '2em'};
                text-align: justify;
                text-justify: inter-character;
                line-break: strict;
            }
            p { margin-bottom: 1em; }
            h1, h2, h3 { text-indent: 0; text-align: center; margin-top: 2em; }
        `
}

function pushLeoReaderStyles() {
    if (view.renderer?.setStyles) {
        view.renderer.setStyles(buildLeoReaderBodyCSS())
    }
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
        } catch (err) {
            loadingEl.style.display = 'none'
            errorEl.textContent = `Error: ${err.message}`
            errorEl.style.display = 'block'
            postToSwift('error', { message: err.message, source: 'openBook' })
        }
    })()
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
    document.body.style.background = bg

    // Derive accent color per theme: sepia uses warm amber, dark uses a
    // softer blue, light uses the system blue.
    const accent = themeP.accent ?? (
        bg === '#1E1E1E' ? '#4CA6FF' :
        bg === '#F5EDDC' ? '#B87333' :
        '#007AFF'
    )
    document.documentElement.style.setProperty('--leo-accent', accent)

    pushLeoReaderStyles()
}

// --- PAGE NAVIGATION ---
// Navigation via keyboard (arrow keys, spacebar) and Swift-exposed JS functions.
// Click-based navigation has been intentionally removed — taps mean dictionary lookup.

// Keyboard navigation — use saved references so stubs don't block us
document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
        if (_activePopup) {
            e.preventDefault()
            hidePopup()
            postToSwift('popupAction', { action: 'dismiss', word: '' })
        }
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

    // Find the most recently loaded iframe doc — stored in _highlightDoc by injectClickHandlers.
    const doc = _highlightDoc
    if (!doc) return

    _clearExpressionHighlight()

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
    _clearExpressionHighlight()
    _highlightDoc = doc

    // Inject highlight CSS into this iframe's document.
    if (!doc.getElementById('leo-highlight-styles')) {
        const style = doc.createElement('style')
        style.id = 'leo-highlight-styles'
        style.textContent = `
            .leo-expression-highlight {
                border-bottom: 2px solid rgba(230, 126, 34, 0.6);
                transition: border-color 0.2s ease;
            }
            .leo-expression-highlight:hover {
                border-bottom-color: rgba(230, 126, 34, 0.9);
            }
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

// --- DICTIONARY POPUP (rendered in JS, floats near tapped word) ---

let _activePopup = null

// Inject popup keyframe animation once into the page <head>.
// Also injects button hover styles via CSS classes since inline styles
// cannot express :hover pseudo-state.
;(function _injectPopupStyles() {
    if (document.getElementById('leo-popup-styles')) return
    const style = document.createElement('style')
    style.id = 'leo-popup-styles'
    style.textContent = `
        @keyframes leoPopupIn {
            from { opacity: 0; transform: scale(0.95) translateY(4px); }
            to   { opacity: 1; transform: scale(1)    translateY(0px); }
        }
        @keyframes leoPopupOut {
            from { opacity: 1; transform: scale(1)    translateY(0px); }
            to   { opacity: 0; transform: scale(0.95) translateY(4px); }
        }
        #leo-popup {
            animation: leoPopupIn 0.18s cubic-bezier(0.34, 1.2, 0.64, 1) both;
        }
        #leo-popup.leo-hiding {
            animation: leoPopupOut 0.14s ease-in both;
        }
        .leo-btn-know {
            flex: 1; padding: 8px 0; border-radius: 8px; border: none;
            cursor: pointer; background: rgba(52,199,89,0.18);
            color: #34C759; font-size: 13px; font-weight: 600;
            transition: background 0.15s, transform 0.1s;
        }
        .leo-btn-know:hover  { background: rgba(52,199,89,0.30); transform: translateY(-1px); }
        .leo-btn-know:active { background: rgba(52,199,89,0.40); transform: translateY(0); }
        .leo-btn-srs {
            flex: 1; padding: 8px 0; border-radius: 8px; border: none;
            cursor: pointer; background: rgba(10,132,255,0.18);
            color: #0A84FF; font-size: 13px; font-weight: 600;
            transition: background 0.15s, transform 0.1s;
        }
        .leo-btn-srs:hover  { background: rgba(10,132,255,0.30); transform: translateY(-1px); }
        .leo-btn-srs:active { background: rgba(10,132,255,0.40); transform: translateY(0); }
        .leo-btn-close {
            background: none; border: none; cursor: pointer;
            font-size: 20px; line-height: 1; padding: 0 0 0 8px;
            flex-shrink: 0; align-self: flex-start;
            transition: opacity 0.15s;
        }
        .leo-btn-close:hover  { opacity: 1 !important; }
        .leo-btn-close:active { opacity: 0.6 !important; }
    `
    document.head.appendChild(style)
})()

// Derive popup colors from the active theme set via setTheme().
// Returns { bg, fg, border, divider, mutedFg, chipBg, chipBorder }
function _popupThemeColors() {
    const themeBg = window._leoLastTheme?.bg ?? '#FFFFFF'

    // Dark theme
    if (themeBg === '#1E1E1E' || themeBg.startsWith('#1') && themeBg.length === 7) {
        return {
            bg:          'rgba(45,45,45,0.97)',
            fg:          '#F2F2F7',
            border:      'rgba(255,255,255,0.12)',
            divider:     'rgba(255,255,255,0.10)',
            mutedFg:     'rgba(242,242,247,0.45)',
            numFg:       'rgba(242,242,247,0.35)',
            chipBg:      'rgba(255,255,255,0.06)',
            chipBorder:  'rgba(255,255,255,0.10)',
            chipFg:      'rgba(242,242,247,0.65)',
            grammarBg:   'rgba(255,255,255,0.05)',
            closeFg:     'rgba(242,242,247,0.35)',
            contextFg:   'rgba(200,220,255,0.95)',
            labelFg:     'rgba(200,220,255,0.55)',
            alreadyBg:   'rgba(10,132,255,0.10)',
            alreadyFg:   'rgba(200,220,255,0.92)',
        }
    }
    // Sepia theme
    if (themeBg === '#F5EDDC' || themeBg.startsWith('#F5')) {
        return {
            bg:          'rgba(245,237,220,0.98)',
            fg:          '#3B2A1A',
            border:      'rgba(139,90,43,0.20)',
            divider:     'rgba(139,90,43,0.15)',
            mutedFg:     'rgba(59,42,26,0.50)',
            numFg:       'rgba(59,42,26,0.35)',
            chipBg:      'rgba(139,90,43,0.08)',
            chipBorder:  'rgba(139,90,43,0.15)',
            chipFg:      'rgba(59,42,26,0.65)',
            grammarBg:   'rgba(139,90,43,0.06)',
            closeFg:     'rgba(59,42,26,0.35)',
            contextFg:   '#3B2A1A',
            labelFg:     'rgba(59,42,26,0.50)',
            alreadyBg:   'rgba(139,90,43,0.10)',
            alreadyFg:   'rgba(59,42,26,0.80)',
        }
    }
    // Light theme (default)
    return {
        bg:          'rgba(255,255,255,0.98)',
        fg:          '#1A1A1A',
        border:      'rgba(0,0,0,0.10)',
        divider:     'rgba(0,0,0,0.08)',
        mutedFg:     'rgba(26,26,26,0.45)',
        numFg:       'rgba(26,26,26,0.35)',
        chipBg:      'rgba(0,0,0,0.04)',
        chipBorder:  'rgba(0,0,0,0.08)',
        chipFg:      'rgba(26,26,26,0.60)',
        grammarBg:   'rgba(0,0,0,0.03)',
        closeFg:     'rgba(26,26,26,0.30)',
        contextFg:   '#1A1A1A',
        labelFg:     'rgba(26,26,26,0.45)',
        alreadyBg:   'rgba(0,122,255,0.08)',
        alreadyFg:   'rgba(0,60,180,0.80)',
    }
}

// Called from Swift after dictionary lookup completes.
// data = { word, pinyin, definitions, frequencyTier, frequencyColor, hskLevel, familiarityLabel }
window.showPopup = function(x, y, data) {
    hidePopup()

    const POP_WIDTH         = 380
    const POP_APPROX_HEIGHT = 280
    const MARGIN            = 12
    const vw = window.innerWidth
    const vh = window.innerHeight

    let left = x - POP_WIDTH / 2
    left = Math.max(MARGIN, Math.min(left, vw - POP_WIDTH - MARGIN))

    // y = bottom edge of the tapped character. Show below; flip above if near bottom.
    let top = y + 10
    if (top + POP_APPROX_HEIGHT > vh - MARGIN) top = y - POP_APPROX_HEIGHT - 10
    top = Math.max(MARGIN, top)

    const canMarkKnown  = data.canMarkKnown  !== false
    const alreadyInReview = data.alreadyInReview === true
    const tc = _popupThemeColors()

    // Root card
    const popup = document.createElement('div')
    popup.id = 'leo-popup'
    Object.assign(popup.style, {
        position:       'fixed',
        left:           left + 'px',
        top:            top + 'px',
        width:          POP_WIDTH + 'px',
        maxWidth:       POP_WIDTH + 'px',
        zIndex:         '9999',
        background:     tc.bg,
        color:          tc.fg,
        borderRadius:   '12px',
        padding:        '16px',
        boxShadow:      '0 8px 32px rgba(0,0,0,0.20), 0 2px 8px rgba(0,0,0,0.12)',
        backdropFilter: 'blur(12px)',
        WebkitBackdropFilter: 'blur(12px)',
        fontFamily:     '-apple-system,"PingFang SC",sans-serif',
        fontSize:       '14px',
        lineHeight:     '1.5',
        border:         '1px solid ' + tc.border,
        pointerEvents:  'auto',
        userSelect:     'none',
        boxSizing:      'border-box',
    })

    // --- Header row (word + pinyin + badges + close button) ---
    const header = document.createElement('div')
    Object.assign(header.style, {
        display:        'flex',
        alignItems:     'flex-start',
        justifyContent: 'space-between',
        marginBottom:   '10px',
        gap:            '8px',
    })

    const wordGroup = document.createElement('div')
    Object.assign(wordGroup.style, {
        display:  'flex',
        flexWrap: 'wrap',
        alignItems: 'baseline',
        gap:      '8px',
        flex:     '1',
        minWidth: '0',
    })

    const wordEl = document.createElement('span')
    wordEl.textContent = data.word ?? ''
    Object.assign(wordEl.style, {
        fontSize:      '28px',
        fontWeight:    '600',
        letterSpacing: '-0.5px',
        lineHeight:    '1.1',
        color:         tc.fg,
    })
    wordGroup.appendChild(wordEl)

    const pinyinEl = document.createElement('span')
    pinyinEl.textContent = data.pinyin ?? ''
    Object.assign(pinyinEl.style, {
        fontSize:   '16px',
        color:      '#E67E22',
        fontWeight: '400',
        lineHeight: '1.2',
    })
    wordGroup.appendChild(pinyinEl)

    // Badges row (frequency + HSK) — inline with pinyin baseline
    const badgeGroup = document.createElement('div')
    Object.assign(badgeGroup.style, {
        display:    'flex',
        alignItems: 'center',
        gap:        '6px',
        flexWrap:   'wrap',
    })

    if (data.frequencyTier) {
        const badge = document.createElement('span')
        badge.textContent = data.frequencyTier
        const c = data.frequencyColor ?? '#6b7280'
        Object.assign(badge.style, {
            display:      'inline-flex',
            alignItems:   'center',
            fontSize:     '11px',
            fontWeight:   '600',
            padding:      '2px 8px',
            borderRadius: '999px',
            background:   c + '22',
            color:        c,
            border:       '1px solid ' + c + '44',
            lineHeight:   '1.4',
        })
        badgeGroup.appendChild(badge)
    }

    if (data.hskLevel) {
        const badge = document.createElement('span')
        badge.textContent = 'HSK\u00A0' + String(data.hskLevel)
        Object.assign(badge.style, {
            display:      'inline-flex',
            alignItems:   'center',
            fontSize:     '11px',
            fontWeight:   '600',
            padding:      '2px 8px',
            borderRadius: '999px',
            background:   '#3b82f622',
            color:        '#3b82f6',
            border:       '1px solid #3b82f644',
            lineHeight:   '1.4',
        })
        badgeGroup.appendChild(badge)
    }

    if (badgeGroup.childElementCount > 0) {
        wordGroup.appendChild(badgeGroup)
    }

    header.appendChild(wordGroup)

    const closeBtn = document.createElement('button')
    closeBtn.textContent = '\u00D7'
    closeBtn.setAttribute('aria-label', 'Close')
    closeBtn.className = 'leo-btn-close'
    Object.assign(closeBtn.style, {
        color:      tc.closeFg,
        opacity:    '0.7',
        marginTop:  '2px',
    })
    header.appendChild(closeBtn)
    popup.appendChild(header)

    // --- Meta chips (familiarity + frequency) ---
    const metaRow = document.createElement('div')
    Object.assign(metaRow.style, {
        display:      'flex',
        flexWrap:     'wrap',
        gap:          '6px',
        marginBottom: '10px',
    })

    if (data.familiarityLabel) {
        const famChip = document.createElement('span')
        famChip.textContent = 'Familiarity: ' + data.familiarityLabel
        Object.assign(famChip.style, {
            fontSize:     '11px',
            color:        tc.chipFg,
            background:   tc.chipBg,
            border:       '1px solid ' + tc.chipBorder,
            borderRadius: '999px',
            padding:      '3px 9px',
            lineHeight:   '1.4',
        })
        metaRow.appendChild(famChip)
    }

    if (data.frequencyTier) {
        const freqChip = document.createElement('span')
        freqChip.textContent = 'Frequency: ' + data.frequencyTier
        Object.assign(freqChip.style, {
            fontSize:     '11px',
            color:        tc.chipFg,
            background:   tc.chipBg,
            border:       '1px solid ' + tc.chipBorder,
            borderRadius: '999px',
            padding:      '3px 9px',
            lineHeight:   '1.4',
        })
        metaRow.appendChild(freqChip)
    }

    if (metaRow.childElementCount > 0) {
        popup.appendChild(metaRow)
    }

    // --- Definitions ---
    const defsSection = document.createElement('div')
    defsSection.id = 'leo-defs'
    Object.assign(defsSection.style, {
        borderTop:    '1px solid ' + tc.divider,
        paddingTop:   '10px',
        marginBottom: '10px',
        fontSize:     '14px',
        lineHeight:   '1.55',
    })

    const defs = (data.definitions ?? []).slice(0, 4)
    if (defs.length === 0) {
        const empty = document.createElement('p')
        empty.textContent = 'No dictionary entry yet. Leo can still track this word while you keep reading.'
        Object.assign(empty.style, { color: tc.mutedFg, margin: '0', lineHeight: '1.5' })
        defsSection.appendChild(empty)
    } else {
        defs.forEach((def, i) => {
            const row = document.createElement('div')
            Object.assign(row.style, {
                display:      'flex',
                gap:          '8px',
                marginBottom: i < defs.length - 1 ? '6px' : '0',
            })

            const num = document.createElement('span')
            num.textContent = (i + 1) + '.'
            Object.assign(num.style, {
                color:     tc.numFg,
                minWidth:  '18px',
                textAlign: 'right',
                flexShrink: '0',
                paddingTop: '1px',
                fontSize:  '13px',
            })

            const text = document.createElement('span')
            text.textContent = def
            text.style.color = tc.fg

            row.appendChild(num)
            row.appendChild(text)
            defsSection.appendChild(row)
        })
    }
    popup.appendChild(defsSection)

    // --- Grammar patterns ---
    const grammarPatterns = data.grammar
    if (Array.isArray(grammarPatterns) && grammarPatterns.length > 0) {
        const grammarSection = document.createElement('div')
        grammarSection.id = 'leo-grammar'
        Object.assign(grammarSection.style, {
            borderTop:    '1px solid ' + tc.divider,
            paddingTop:   '10px',
            marginBottom: '10px',
        })

        const grammarLabel = document.createElement('div')
        grammarLabel.textContent = 'Grammar'
        Object.assign(grammarLabel.style, {
            fontSize:      '10px',
            fontWeight:    '700',
            letterSpacing: '0.07em',
            textTransform: 'uppercase',
            color:         tc.labelFg,
            marginBottom:  '8px',
        })
        grammarSection.appendChild(grammarLabel)

        for (const pat of grammarPatterns) {
            const card = document.createElement('div')
            Object.assign(card.style, {
                background:   tc.grammarBg,
                borderRadius: '8px',
                padding:      '8px 12px',
                marginBottom: '6px',
            })

            // Level badge + title row
            const titleRow = document.createElement('div')
            Object.assign(titleRow.style, {
                display:      'flex',
                alignItems:   'center',
                gap:          '6px',
                marginBottom: '4px',
            })

            const levelBadge = document.createElement('span')
            levelBadge.textContent = pat.level ?? ''
            const levelColor = _grammarLevelColor(pat.level)
            Object.assign(levelBadge.style, {
                fontSize:     '10px',
                fontWeight:   '700',
                padding:      '1px 6px',
                borderRadius: '999px',
                background:   levelColor + '22',
                color:        levelColor,
                border:       '1px solid ' + levelColor + '44',
                flexShrink:   '0',
            })
            titleRow.appendChild(levelBadge)

            const titleEl = document.createElement('span')
            titleEl.textContent = pat.title ?? ''
            Object.assign(titleEl.style, {
                fontSize:   '12px',
                fontWeight: '600',
                color:      tc.fg,
            })
            titleRow.appendChild(titleEl)
            card.appendChild(titleRow)

            // Structure line
            if (pat.structure) {
                const structEl = document.createElement('div')
                structEl.textContent = pat.structure
                Object.assign(structEl.style, {
                    fontSize:   '12px',
                    color:      '#E67E22',
                    fontFamily: 'ui-monospace, monospace',
                    marginTop:  '3px',
                })
                card.appendChild(structEl)
            }

            // Short description
            if (pat.description) {
                const descEl = document.createElement('div')
                descEl.textContent = pat.description
                Object.assign(descEl.style, {
                    fontSize:   '12px',
                    color:      tc.mutedFg,
                    marginTop:  '4px',
                    lineHeight: '1.45',
                })
                card.appendChild(descEl)
            }

            grammarSection.appendChild(card)
        }

        popup.appendChild(grammarSection)
    }

    // --- Action buttons ---
    const actions = document.createElement('div')
    Object.assign(actions.style, {
        display:    'flex',
        gap:        '8px',
        borderTop:  '1px solid ' + tc.divider,
        paddingTop: '12px',
    })

    let knowBtn = null
    if (canMarkKnown) {
        knowBtn = document.createElement('button')
        knowBtn.textContent = 'I know this'
        knowBtn.className = 'leo-btn-know'
        actions.appendChild(knowBtn)
    }

    let srsBtn = null
    if (!alreadyInReview) {
        srsBtn = document.createElement('button')
        srsBtn.textContent = 'Add to review'
        srsBtn.className = 'leo-btn-srs'
        actions.appendChild(srsBtn)
    } else {
        const status = document.createElement('div')
        status.textContent = 'Already in review'
        Object.assign(status.style, {
            flex:         '1',
            padding:      '8px 10px',
            borderRadius: '8px',
            background:   tc.alreadyBg,
            color:        tc.alreadyFg,
            fontSize:     '13px',
            fontWeight:   '600',
            textAlign:    'center',
        })
        actions.appendChild(status)
    }

    if (actions.childElementCount > 0) {
        popup.appendChild(actions)
    }

    document.body.appendChild(popup)
    _activePopup = popup

    // Button actions post back to Swift
    closeBtn.onclick = (e) => {
        e.stopPropagation()
        hidePopup()
        postToSwift('popupAction', { action: 'dismiss', word: data.word })
    }
    if (knowBtn) {
        knowBtn.onclick = (e) => {
            e.stopPropagation()
            hidePopup()
            postToSwift('popupAction', { action: 'markKnown', word: data.word })
        }
    }
    if (srsBtn) {
        srsBtn.onclick = (e) => {
            e.stopPropagation()
            hidePopup()
            postToSwift('popupAction', { action: 'addToSRS', word: data.word })
        }
    }

    // Dismiss on outside click (small delay so the current tap doesn't immediately close it)
    const outsideHandler = (e) => {
        if (_activePopup && !_activePopup.contains(e.target)) {
            hidePopup()
            postToSwift('popupAction', { action: 'dismiss', word: data.word })
            document.removeEventListener('click', outsideHandler, true)
        }
    }
    setTimeout(() => document.addEventListener('click', outsideHandler, true), 50)
}

window.hidePopup = function() { hidePopup() }

// Contextual gloss from OpenRouter (async; Swift calls after initial popup).
window.updatePopupContext = function(text) {
    if (!text) return
    const popup = document.getElementById('leo-popup')
    if (!popup) return
    const tc = _popupThemeColors()
    let el = document.getElementById('leo-context')
    if (!el) {
        el = document.createElement('div')
        el.id = 'leo-context'
        Object.assign(el.style, {
            borderTop:    '1px solid ' + tc.divider,
            paddingTop:   '10px',
            marginBottom: '8px',
            fontSize:     '13px',
            color:        tc.contextFg,
            lineHeight:   '1.45',
        })
        const label = document.createElement('div')
        label.textContent = 'Context'
        Object.assign(label.style, {
            fontSize:      '10px',
            fontWeight:    '700',
            letterSpacing: '0.07em',
            textTransform: 'uppercase',
            color:         tc.labelFg,
            marginBottom:  '5px',
        })
        el.appendChild(label)

        const body = document.createElement('div')
        body.id = 'leo-context-body'
        el.appendChild(body)
        const defs = document.getElementById('leo-defs')
        if (defs) {
            defs.insertAdjacentElement('afterend', el)
        } else {
            popup.appendChild(el)
        }
    }
    const body = document.getElementById('leo-context-body')
    if (body) {
        body.textContent = text
    }
}

// Plays a brief fade-out animation then removes the popup.
// Also removes any active expression highlight from the text.
function hidePopup() {
    _clearExpressionHighlight()
    if (!_activePopup) return
    const el = _activePopup
    _activePopup = null
    el.classList.add('leo-hiding')
    // Duration matches the leoPopupOut animation (0.14s)
    setTimeout(() => { el.remove() }, 150)
}

// Returns a hex color for a CEFR/HSK level badge in the grammar section.
function _grammarLevelColor(level) {
    switch (level) {
        case 'A1': return '#22c55e'  // green
        case 'A2': return '#3b82f6'  // blue
        case 'B1': return '#8b5cf6'  // purple
        case 'B2': return '#f59e0b'  // amber
        case 'C1': return '#ef4444'  // red
        case 'C2': return '#ec4899'  // pink
        default:   return '#6b7280'  // gray
    }
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
