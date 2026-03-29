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
    lineHeight: 1.8,
    textDirection: 'horizontal',
    showPinyin: false,
    showHighlights: true,
}
window.__leoShowHighlights = true
window.__leoShowPinyin = false

const LEO_FONT_STACK = '"PingFang SC", "Hiragino Sans GB", "Source Han Serif SC", "Noto Serif SC", sans-serif'

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

// Apply light/dark/sepia colors; typography comes from applyReadingPreferences.
window.setTheme = function(themeP) {
    const bg = themeP.bg ?? window._leoLastTheme.bg
    const fg = themeP.fg ?? window._leoLastTheme.fg
    window._leoLastTheme = { bg, fg }
    document.documentElement.style.setProperty('--bg', bg)
    document.documentElement.style.setProperty('--fg', fg)
    document.body.style.background = bg
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

// Called from Swift after dictionary lookup completes.
// data = { word, pinyin, definitions, frequencyTier, frequencyColor, hskLevel, familiarityLabel }
window.showPopup = function(x, y, data) {
    hidePopup()

    const POP_WIDTH        = 320
    const POP_APPROX_HEIGHT = 260
    const MARGIN           = 12
    const vw = window.innerWidth
    const vh = window.innerHeight

    let left = x - POP_WIDTH / 2
    left = Math.max(MARGIN, Math.min(left, vw - POP_WIDTH - MARGIN))

    // y = bottom edge of the tapped character. Show below; flip above if near bottom.
    let top = y + 10
    if (top + POP_APPROX_HEIGHT > vh - MARGIN) top = y - POP_APPROX_HEIGHT - 10
    top = Math.max(MARGIN, top)

    const canMarkKnown = data.canMarkKnown !== false
    const alreadyInReview = data.alreadyInReview === true

    // Root card
    const popup = document.createElement('div')
    popup.id = 'leo-popup'
    Object.assign(popup.style, {
        position: 'fixed', left: left + 'px', top: top + 'px', width: POP_WIDTH + 'px',
        zIndex: '9999', background: 'rgba(28,28,30,0.97)', color: '#F2F2F7',
        borderRadius: '14px', padding: '14px 16px 12px',
        boxShadow: '0 8px 32px rgba(0,0,0,.45),0 2px 8px rgba(0,0,0,.3)',
        fontFamily: '-apple-system,"PingFang SC",sans-serif', fontSize: '14px',
        lineHeight: '1.4', border: '1px solid rgba(255,255,255,.12)',
        pointerEvents: 'auto', userSelect: 'none', boxSizing: 'border-box',
    })

    // --- Header row ---
    const header = document.createElement('div')
    Object.assign(header.style, { display: 'flex', alignItems: 'baseline',
        justifyContent: 'space-between', marginBottom: '6px' })

    const wordGroup = document.createElement('div')
    Object.assign(wordGroup.style, { display: 'flex', alignItems: 'baseline',
        flexWrap: 'wrap', gap: '0', flex: '1' })

    const wordEl = document.createElement('span')
    wordEl.textContent = data.word ?? ''
    Object.assign(wordEl.style, { fontSize: '26px', fontWeight: '500',
        letterSpacing: '-0.5px', marginRight: '10px', lineHeight: '1.1' })
    wordGroup.appendChild(wordEl)

    const pinyinEl = document.createElement('span')
    pinyinEl.textContent = data.pinyin ?? ''
    Object.assign(pinyinEl.style, { fontSize: '15px', color: '#FF9F0A', fontWeight: '400' })
    wordGroup.appendChild(pinyinEl)

    if (data.frequencyTier) {
        const badge = document.createElement('span')
        badge.textContent = data.frequencyTier
        const c = data.frequencyColor ?? '#6b7280'
        Object.assign(badge.style, {
            display: 'inline-block', fontSize: '10px', fontWeight: '600',
            padding: '2px 7px', borderRadius: '20px', marginLeft: '8px',
            background: c + '22', color: c, border: '1px solid ' + c + '44',
            verticalAlign: 'middle',
        })
        wordGroup.appendChild(badge)
    }

    if (data.hskLevel) {
        const badge = document.createElement('span')
        badge.textContent = 'HSK ' + String(data.hskLevel)
        Object.assign(badge.style, {
            display: 'inline-block', fontSize: '10px', fontWeight: '600',
            padding: '2px 7px', borderRadius: '20px', marginLeft: '6px',
            background: '#3b82f622', color: '#3b82f6', border: '1px solid #3b82f644',
            verticalAlign: 'middle',
        })
        wordGroup.appendChild(badge)
    }

    header.appendChild(wordGroup)

    const closeBtn = document.createElement('button')
    closeBtn.textContent = '×'
    closeBtn.setAttribute('aria-label', 'Close')
    Object.assign(closeBtn.style, {
        background: 'none', border: 'none', cursor: 'pointer',
        color: 'rgba(242,242,247,0.4)', fontSize: '18px', lineHeight: '1',
        padding: '0 0 0 8px', flexShrink: '0', alignSelf: 'flex-start',
    })
    header.appendChild(closeBtn)
    popup.appendChild(header)

    const metaRow = document.createElement('div')
    Object.assign(metaRow.style, {
        display: 'flex',
        flexWrap: 'wrap',
        gap: '6px',
        marginBottom: '10px',
    })

    if (data.familiarityLabel) {
        const famChip = document.createElement('span')
        famChip.textContent = `Familiarity: ${data.familiarityLabel}`
        Object.assign(famChip.style, {
            fontSize: '11px',
            color: 'rgba(242,242,247,0.65)',
            background: 'rgba(255,255,255,0.06)',
            border: '1px solid rgba(255,255,255,0.08)',
            borderRadius: '999px',
            padding: '3px 8px',
        })
        metaRow.appendChild(famChip)
    }

    if (data.frequencyTier) {
        const freqChip = document.createElement('span')
        freqChip.textContent = `Frequency: ${data.frequencyTier}`
        Object.assign(freqChip.style, {
            fontSize: '11px',
            color: 'rgba(242,242,247,0.65)',
            background: 'rgba(255,255,255,0.06)',
            border: '1px solid rgba(255,255,255,0.08)',
            borderRadius: '999px',
            padding: '3px 8px',
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
        borderTop: '1px solid rgba(255,255,255,.1)',
        paddingTop: '8px', marginBottom: '10px', fontSize: '13.5px',
    })

    const defs = (data.definitions ?? []).slice(0, 4)
    if (defs.length === 0) {
        const empty = document.createElement('p')
        empty.textContent = 'No dictionary entry yet. Leo can still track this word while you keep reading.'
        Object.assign(empty.style, { color: 'rgba(242,242,247,0.45)',
            margin: '0' })
        defsSection.appendChild(empty)
    } else {
        defs.forEach((def, i) => {
            const row = document.createElement('div')
            Object.assign(row.style, { display: 'flex', gap: '8px', marginBottom: '4px' })

            const num = document.createElement('span')
            num.textContent = (i + 1) + '.'
            Object.assign(num.style, {
                color: 'rgba(242,242,247,0.4)', minWidth: '16px',
                textAlign: 'right', flexShrink: '0',
            })

            const text = document.createElement('span')
            text.textContent = def
            text.style.color = '#F2F2F7'

            row.appendChild(num)
            row.appendChild(text)
            defsSection.appendChild(row)
        })
    }
    popup.appendChild(defsSection)

    // --- Action buttons ---
    const actions = document.createElement('div')
    Object.assign(actions.style, {
        display: 'flex', gap: '8px',
        borderTop: '1px solid rgba(255,255,255,.1)', paddingTop: '10px',
    })

    let knowBtn = null
    if (canMarkKnown) {
        knowBtn = document.createElement('button')
        knowBtn.textContent = 'I know this'
        Object.assign(knowBtn.style, {
            flex: '1', padding: '7px 0', borderRadius: '8px', border: 'none',
            cursor: 'pointer', background: 'rgba(52,199,89,0.18)',
            color: '#34C759', fontSize: '12px', fontWeight: '600',
        })
        actions.appendChild(knowBtn)
    }

    let srsBtn = null
    if (!alreadyInReview) {
        srsBtn = document.createElement('button')
        srsBtn.textContent = 'Add to review'
        Object.assign(srsBtn.style, {
            flex: '1', padding: '7px 0', borderRadius: '8px', border: 'none',
            cursor: 'pointer', background: 'rgba(10,132,255,0.18)',
            color: '#0A84FF', fontSize: '12px', fontWeight: '600',
        })
        actions.appendChild(srsBtn)
    } else {
        const status = document.createElement('div')
        status.textContent = 'Already in review'
        Object.assign(status.style, {
            flex: '1',
            padding: '7px 10px',
            borderRadius: '8px',
            background: 'rgba(10,132,255,0.10)',
            color: 'rgba(200,220,255,0.92)',
            fontSize: '12px',
            fontWeight: '600',
            textAlign: 'center',
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
    let el = document.getElementById('leo-context')
    if (!el) {
        el = document.createElement('div')
        el.id = 'leo-context'
        Object.assign(el.style, {
            borderTop: '1px solid rgba(255,255,255,.08)',
            paddingTop: '8px', marginBottom: '8px', fontSize: '12.5px',
            color: 'rgba(200,220,255,0.95)', lineHeight: '1.35',
        })
        const label = document.createElement('div')
        label.textContent = 'Context'
        Object.assign(label.style, {
            fontSize: '10px',
            fontWeight: '700',
            letterSpacing: '0.06em',
            textTransform: 'uppercase',
            color: 'rgba(200,220,255,0.55)',
            marginBottom: '4px',
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

function hidePopup() {
    if (_activePopup) {
        _activePopup.remove()
        _activePopup = null
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
