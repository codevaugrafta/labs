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
    const { fraction, tocItem, cfi } = e.detail
    postToSwift('relocate', {
        fraction: fraction,
        cfi: cfi?.toString() ?? '',
        chapterTitle: tocItem?.label ?? ''
    })
})

view.addEventListener('draw-annotation', e => {
    // Future: familiarity color overlays
})

// --- COMMANDS FROM SWIFT → JS ---

// Called by Swift to open an EPUB.
// Flow: fetch → open (book metadata) → renderer.next() (triggers first 'load' event)
window.openBook = async function(url) {
    try {
        loadingEl.style.display = 'flex'
        errorEl.style.display = 'none'

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

        // Apply default styles before navigating so they take effect on first render.
        view.renderer?.setStyles?.(`
            body {
                font-family: "PingFang SC", "Hiragino Sans GB", "Source Han Serif SC",
                             "Noto Serif SC", sans-serif;
                font-size: 18px;
                line-height: 1.7;
                max-width: 35em;
                margin: 0 auto;
                padding: 2em 3em;
                text-indent: 2em;
                text-align: justify;
                text-justify: inter-character;
                line-break: strict;
            }
            p { margin-bottom: 1em; }
            h1, h2, h3 { text-indent: 0; text-align: center; margin-top: 2em; }
        `)

        // Navigate to the first page — this triggers the first 'load' event.
        view.renderer.next()
    } catch (err) {
        loadingEl.style.display = 'none'
        errorEl.textContent = `Error: ${err.message}`
        errorEl.style.display = 'block'
        postToSwift('error', { message: err.message, source: 'openBook' })
    }
}

// Navigate to a specific CFI position
window.goTo = function(cfi) {
    try {
        view.goTo(cfi)
    } catch (err) {
        postToSwift('error', { message: err.message, source: 'goTo' })
    }
}

// Apply theme — setStyles() takes a plain CSS string, not an object.
window.setTheme = function(theme) {
    const { bg, fg, fontFamily, fontSize, lineHeight } = theme
    document.documentElement.style.setProperty('--bg', bg)
    document.documentElement.style.setProperty('--fg', fg)
    document.body.style.background = bg

    if (view.renderer) {
        view.renderer.setStyles(`
            body {
                background: ${bg} !important;
                color: ${fg} !important;
                font-family: ${fontFamily || '"PingFang SC", "Hiragino Sans GB", "Source Han Serif SC", "Noto Serif SC", sans-serif'};
                font-size: ${fontSize || '18px'};
                line-height: ${lineHeight || '1.7'};
                max-width: 35em;
                margin: 0 auto;
                padding: 2em 3em;
                text-indent: 2em;
                text-align: justify;
                text-justify: inter-character;
                line-break: strict;
            }
            p { margin-bottom: 1em; }
            h1, h2, h3 { text-indent: 0; text-align: center; margin-top: 2em; }
        `)
    }
}

// --- PAGE NAVIGATION ---
// Navigation via keyboard (arrow keys, spacebar) and Swift-exposed JS functions.
// Click-based navigation has been intentionally removed — taps mean dictionary lookup.

// Keyboard navigation
document.addEventListener('keydown', (e) => {
    if (!view.renderer) return
    switch (e.key) {
        case 'ArrowRight':
        case 'PageDown':
        case ' ':
            e.preventDefault()
            view.renderer.next()
            break
        case 'ArrowLeft':
        case 'PageUp':
            e.preventDefault()
            view.renderer.prev()
            break
        case 'Home':
            e.preventDefault()
            view.goToTextStart?.()
            break
    }
})

// Navigation commands from Swift
window.nextPage = function() { view.renderer?.next() }
window.prevPage = function() { view.renderer?.prev() }

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
    // Keyboard navigation inside iframe documents
    doc.addEventListener('keydown', (e) => {
        if (!view.renderer) return
        switch (e.key) {
            case 'ArrowRight':
            case 'PageDown':
                e.preventDefault()
                view.renderer.next()
                break
            case 'ArrowLeft':
            case 'PageUp':
                e.preventDefault()
                view.renderer.prev()
                break
            case ' ':
                e.preventDefault()
                view.renderer.next()
                break
        }
    })
}

function injectClickHandlers(doc, chapterIndex) {
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

        postToSwift('wordTap', {
            char: clickedChar,
            context: context,
            charIndex: charIndexInContext,
            chapterIndex: chapterIndex,
            x: rect.left,
            y: rect.bottom
        })
    })
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
