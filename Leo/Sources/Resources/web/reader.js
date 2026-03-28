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

view.addEventListener('relocate', e => {
    const { fraction, location, tocItem, cfi } = e.detail
    postToSwift('relocate', {
        fraction: fraction,
        cfi: cfi?.toString() ?? '',
        chapterTitle: tocItem?.label ?? ''
    })
})

view.addEventListener('load', e => {
    const { doc, index } = e.detail
    loadingEl.style.display = 'none'

    // Inject Chinese character click handlers into the loaded chapter document
    injectClickHandlers(doc, index)

    postToSwift('chapterLoaded', { index: index })
})

view.addEventListener('draw-annotation', e => {
    // Future: familiarity color overlays
})

// --- COMMANDS FROM SWIFT → JS ---

// Called by Swift to open an EPUB
window.openBook = async function(url) {
    try {
        loadingEl.style.display = 'flex'
        errorEl.style.display = 'none'

        const response = await fetch(url)
        const blob = await response.blob()
        const file = new File([blob], url.split('/').pop(), { type: 'application/epub+zip' })

        await view.open(file)
        loadingEl.style.display = 'none'

        postToSwift('loaded', {
            title: view.book?.metadata?.title ?? '',
            author: view.book?.metadata?.creator ?? '',
            chapterCount: view.book?.toc?.length ?? 0
        })
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

// Apply theme
window.setTheme = function(theme) {
    const { bg, fg, fontFamily, fontSize, lineHeight } = theme
    document.documentElement.style.setProperty('--bg', bg)
    document.documentElement.style.setProperty('--fg', fg)
    document.body.style.background = bg

    // Apply to foliate-js renderer
    if (view.renderer) {
        view.renderer.setStyles({
            style: `
                body {
                    background: ${bg} !important;
                    color: ${fg} !important;
                    font-family: ${fontFamily || '"Source Han Serif SC", "Noto Serif SC", "PingFang SC", sans-serif'};
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
            `
        })
    }
}

// --- CHINESE CHARACTER CLICK HANDLING ---

function isChinese(char) {
    const code = char.charCodeAt(0)
    return (code >= 0x4E00 && code <= 0x9FFF)
        || (code >= 0x3400 && code <= 0x4DBF)
        || (code >= 0xF900 && code <= 0xFAFF)
}

function injectClickHandlers(doc, chapterIndex) {
    // Listen for clicks on the chapter document
    doc.addEventListener('click', (event) => {
        // Use caretRangeFromPoint to find exactly what was clicked
        const range = doc.caretRangeFromPoint(event.clientX, event.clientY)
        if (!range || !range.startContainer || range.startContainer.nodeType !== Node.TEXT_NODE) return

        const textNode = range.startContainer
        const text = textNode.textContent
        const offset = range.startOffset

        if (offset >= text.length) return
        const clickedChar = text[offset]

        // Only handle Chinese characters
        if (!isChinese(clickedChar)) return

        // Build context window (±15 chars)
        const start = Math.max(0, offset - 15)
        const end = Math.min(text.length, offset + 16)
        const context = text.substring(start, end)
        const charIndex = offset - start

        // Get position for popup
        const rect = range.getBoundingClientRect()

        postToSwift('wordTap', {
            char: clickedChar,
            context: context,
            charIndex: charIndex,
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
