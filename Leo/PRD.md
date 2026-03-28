# Leo — Chinese Immersive Reader

## Problem Statement

There is no native macOS app for immersive Chinese reading. Every competitor (Pleco, LingQ, Du Chinese, Migaku, Kimchi Reader, The Chairman's Bao) is web-only, iOS-only, or Android-only. Chinese learners who read on their MacBook must cobble together separate tools for reading (iBooks), dictionary lookup (Pleco on phone), word segmentation (manual), vocabulary tracking (Anki), and TTS (browser extensions). The friction between reading and learning is enormous — every unknown word breaks flow.

The Chinese NLP parsing problem is the core technical challenge. Chinese has no spaces between words. "我不得不去" could be segmented as 我/不得不/去 (correct: "I had no choice but to go") or 我/不/得/不/去 (wrong). Every competitor fails at expression-level detection — they segment words but miss collocations, grammar patterns, and multi-word expressions. This means learners see individual characters but not the linguistic units that actually carry meaning.

## Solution

Leo is a native macOS reading app (iOS later) that combines:

1. **EPUB/PDF reader** with the clean aesthetic of Apple Books
2. **Elite Chinese parser** that segments at character, word, AND expression level — detecting collocations, grammar patterns (把/被/越...越), and multi-word expressions, not just word boundaries
3. **5-state word familiarity system** (Unknown → Seen → Learning → Familiar → Known) with precise, data-driven transition algorithms — no state flickering
4. **TTS with word-level highlighting** synced to audio via InWorld TTS-1.5 Max — click anywhere in text to jump audio to that position
5. **Built-in FSRS v5 spaced repetition** — one-click from unknown word to SRS schedule
6. **Anki integration** — import existing decks to bootstrap known words, export new cards with context
7. **Multi-corpus frequency engine** — TUBELEX-ZH (modern spoken), SUBTLEX-CH (film/TV), BCC (15B char comprehensive) powering comprehension scores and word importance ranking
8. **Reading session tracking** — manual timer, position markers, words/chars/pages read, comprehension trends

No macOS native app exists in this space. Leo is the first.

## User Stories

1. As a Chinese learner, I want to import any EPUB or PDF book, so that I can read my own content with full language support
2. As a reader, I want a clean iBooks-style reading interface, so that reading feels natural and distraction-free
3. As a reader, I want to choose between horizontal and vertical text layout, so that I can read in whichever orientation I prefer
4. As a reader, I want dark mode, light mode, and sepia themes, so that I can read comfortably in any lighting
5. As a reader, I want to customize font size, line height, and margins, so that the reading experience fits my preferences
6. As a Chinese learner, I want unknown words highlighted while reading, so that I can immediately see what I don't know
7. As a Chinese learner, I want known words to appear clean (no highlighting), so that reading flows naturally for acquired vocabulary
8. As a Chinese learner, I want to toggle all highlighting on/off, so that I can switch between study mode and pure reading mode
9. As a Chinese learner, I want to see a comprehension score per page, so that I know how much of the text I actually understand
10. As a Chinese learner, I want to tap/click any word for an instant popup definition, so that I never break reading flow
11. As a Chinese learner, I want the popup to show pinyin, definition, HSK level, and example sentences, so that I get complete information in one glance
12. As a Chinese learner, I want to hold a modifier key and hover over words for instant lookup, so that I can scan quickly without clicking
13. As a Chinese learner, I want the lookup popup to appear floating near the word by default, so that my eyes stay close to the reading position
14. As a Chinese learner, I want the option to show lookups in a sidebar or bottom drawer instead, so that I can choose what works best for me
15. As a Chinese learner, I want the parser to detect multi-word expressions (不得不, 一边...一边) as single units, so that I learn real linguistic chunks, not isolated characters
16. As a Chinese learner, I want grammar patterns (把 constructions, 被 passive, 越...越) highlighted as structures, so that I recognize grammatical patterns in context
17. As a Chinese learner, I want both character-level and word-level selection modes with a toggle, so that I can interact with text at whichever granularity I need
18. As a Chinese learner, I want to toggle pinyin display on/off (interlinear above characters), so that I can choose when to see pronunciation aids
19. As a Chinese learner, I want to toggle an English overlay/underlay for unknown lemmas only, so that I get translation help only where I need it
20. As a Chinese learner, I want to add any unknown word to my SRS schedule with one click, so that the friction between reading and learning is near zero
21. As a Chinese learner, I want flashcards to automatically include the word, pinyin, definition, source sentence, and audio clip, so that cards have rich context without manual effort
22. As a Chinese learner, I want FSRS v5 to schedule my reviews optimally, so that I retain vocabulary with minimal review time
23. As a Chinese learner, I want to review due cards inside the app, so that I don't need to switch to a separate tool
24. As a Chinese learner, I want to import my existing Anki deck to bootstrap known words, so that the app knows what I already know from day one
25. As a Chinese learner, I want the import to read ALL Anki card states (new, learning, review, mature), so that my familiarity levels are accurately mapped
26. As a Chinese learner, I want to export cards to Anki-compatible .apkg format, so that I can use my vocabulary in other tools
27. As a reader, I want TTS to read the text aloud with word-by-word highlighting synced to audio, so that I can follow along and improve listening comprehension
28. As a reader, I want to click anywhere in the text and have TTS jump to that position, so that I can re-listen to specific passages instantly
29. As a reader, I want adjustable TTS playback speed, so that I can match the pace to my comprehension level
30. As a reader, I want TTS audio pre-generated per chapter with word timestamps, so that seeking within audio is instant
31. As a reader, I want a shadow reading mode, so that I can practice speaking along with the TTS
32. As a reader, I want a dictation mode with a blur effect over the page while TTS plays, so that I can test my listening comprehension by writing what I hear
33. As a reader, I want to start a reading session with a keybinding, so that tracking begins without interrupting my reading
34. As a reader, I want to place a start marker overlay on the text where I began, so that I can visually see my reading range
35. As a reader, I want to select my stop point and see the highlighted range, so that I know exactly what I covered
36. As a reader, I want to see words read, characters read, pages read, and time spent per session, so that I can track my progress quantitatively
37. As a reader, I want to see reading speed (characters/minute) and comprehension trends over time, so that I can measure improvement
38. As a reader, I want the session timer to be toggleable (visible/hidden while reading), so that it doesn't distract when I don't want it
39. As a Chinese learner, I want word familiarity to progress through 5 precise states (Unknown → Seen → Learning → Familiar → Known), so that my vocabulary knowledge is tracked with granularity
40. As a Chinese learner, I want state transitions driven by a precise data-driven algorithm (not arbitrary thresholds), so that words don't flicker between states
41. As a Chinese learner, I want context-aware definitions powered by LLM (via OpenRouter — Qwen 3.5 Plus, DeepSeek, GLM, Kimi, etc.), so that I understand words in their specific sentence context
42. As a Chinese learner, I want word frequency data from multiple corpora (TUBELEX-ZH, SUBTLEX-CH, BCC), so that I know how common each word is in different registers
43. As a reader, I want the app to have a hidden/showing side panel, so that I can access vocabulary lists and settings without leaving the reader
44. As a reader, I want keyboard shortcuts for all major actions, so that I can operate the app efficiently
45. As a reader, I want the app to remember my reading position per book, so that I always pick up where I left off
46. As a reader, I want a menu bar integration showing current book and quick stats, so that I can see reading info at a glance

## Implementation Decisions

### Architecture: 11 Deep Modules

**1. ContentIngestion** — Parses EPUB via Readium Swift Toolkit and PDF via Apple PDFKit into a unified `Publication` model. Extracts raw text for the NLP pipeline. Single interface: file URL in, structured content out.

**2. ChineseParser** — The core differentiator. Three-layer architecture:
- Layer 1 (on-device, instant): Apple NLTagger for word boundary detection — good enough for tap-to-select
- Layer 2 (offline, dictionary-based): CC-CEDICT + curated MWE dictionary for expression detection — 成语, 惯用语, grammatical patterns
- Layer 3 (online, contextual): OpenRouter LLM for ambiguous segmentations — sends sentence, gets expression boundaries back
- Output: `[Token]` array where each token has character spans, word spans, expression spans, POS tags

**3. FrequencyEngine** — Embeds three corpora behind a unified lookup:
- TUBELEX-ZH (YouTube subtitles, modern spoken Chinese)
- SUBTLEX-CH (film/TV subtitles, 46.8M characters)
- BCC (BLCU, 15B characters, news + literature + blogs + classical)
- Returns composite frequency score, register breakdown, and rarity ranking

**4. FamiliarityTracker** — 5-state machine with precise transition algorithm:
- Unknown (red) → Seen (orange) → Learning (yellow) → Familiar (light) → Known (invisible)
- Transitions driven by: encounter count, FSRS stability, FSRS difficulty, time since last encounter, active review performance
- "Moneyball" principle: no single metric drives transitions, weighted composite scoring
- Anti-flickering: state can only move UP (toward Known), never backward unless explicit user override

**5. FSRSEngine** — Built-in FSRS v5 implementation:
- 19 tunable parameters
- Scheduling: card + rating → next review date + updated stability/difficulty
- Integrates with FamiliarityTracker to drive Learning → Familiar → Known transitions
- Reference: open-spaced-repetition/py-fsrs adapted to Swift

**6. DictionaryEngine** — Dual-layer:
- Offline: CC-CEDICT embedded (130K entries) with pinyin, English definitions, HSK 3.0 tagging
- Online: OpenRouter LLM for contextual definitions (sends word + sentence, gets nuanced explanation)
- Collocation data from CLAD (Chinese Lexical Association Database)

**7. TTSEngine** — Provider abstraction:
- Primary: InWorld TTS-1.5 Max ($10/1M chars, #1 Artificial Analysis, Chinese supported, word-level timestamps via `timestampType: WORD`)
- Fallback: Azure/Edge TTS (free, word boundary metadata)
- Architecture: pre-generate chapter audio → store with timestamp map → seek instantly via timestamp lookup
- Note: InWorld Chinese timestamps are "experimental" — requires early testing and fallback

**8. ReadingSession** — Pure logic, no UI:
- Manual start/stop via keybinding
- Tracks: start position, stop position, words/chars/pages read, elapsed time
- Visual modes: pin marker at start + highlighted range between start/stop
- Comprehension % = (known + familiar tokens) / total tokens on visible page

**9. SyncEngine** — Dual backend with redundancy:
- iCloud/CloudKit: reading position, app settings, book library metadata
- Supabase: vocabulary database, FSRS card states, reading history, frequency data
- Conflict resolution: last-write-wins for position, merge for vocabulary (union of known words)
- Offline-first: all data in SwiftData locally, sync when online

**10. AnkiExporter** — Bidirectional:
- Import: parse .apkg → extract cards + states → map to FamiliarityTracker states
- Export: generate .apkg with word + pinyin + definition + context sentence + audio clip
- Mapping: Anki "new" → Unknown, "learning" → Learning, "young" → Familiar, "mature" → Known

**11. ReaderView** — SwiftUI + Readium Navigator:
- iBooks-clean default layout
- Readium WKWebView for EPUB rendering with decoration API for highlights
- PDFKit view for PDF with overlay annotations
- Configurable: side panel (hidden/showing), lookup position (floating/sidebar/drawer)
- Platform: macOS first, iOS later (shared domain layer)
- Blur overlay for dictation mode

### Tech Stack
- Swift 6.2, SPM, SwiftUI
- Readium Swift Toolkit (EPUB)
- Apple PDFKit (PDF)
- Apple NLTagger (on-device Chinese NLP)
- SwiftData (local persistence)
- InWorld TTS API (primary TTS)
- OpenRouter API (LLM definitions)
- Supabase (cloud sync)
- iCloud/CloudKit (position sync)

### Data Model (SwiftData)
- `Book`: id, title, author, format, filePath, lastPosition, addedAt
- `Token`: id, text, pinyin, bookId, chapterIndex, startOffset, endOffset, tokenType (character/word/expression)
- `VocabularyEntry`: id, text, pinyin, definition, familiarityState, encounterCount, firstSeenAt, lastSeenAt, sourceBookId, sourceSentence
- `FSRSCard`: id, vocabularyEntryId, stability, difficulty, dueDate, lastReviewDate, reviewCount, lapseCount
- `ReadingSession`: id, bookId, startPosition, endPosition, startedAt, endedAt, wordsRead, charsRead, comprehensionPct
- `FrequencyData`: word, tubelexRank, subtlexRank, bccRank, compositeScore

## Testing Decisions

### What Makes a Good Test
- Tests verify **external behavior** through module interfaces, not internal implementation
- Tests survive refactors — changing how a module works internally shouldn't break tests
- Each test has one logical assertion about one behavior
- Tests are independent — no shared state, no ordering dependencies

### Modules to Test (Priority Order)

1. **ChineseParser** — Critical. Test: word segmentation accuracy, expression detection, character-level tokenization, mixed Chinese/English text, classical vs modern Chinese, edge cases (numbers, punctuation, URLs in text)
2. **FamiliarityTracker** — Critical. Test: state transitions are monotonic (no backward movement), composite scoring produces stable states, bulk encounter simulation doesn't cause flickering, edge cases at state boundaries
3. **FSRSEngine** — Critical. Test: scheduling matches reference FSRS v5 implementation, stability/difficulty updates are correct, parameter optimization produces valid values
4. **FrequencyEngine** — Important. Test: corpus data integrity, known words return expected frequency ranks, unknown words return appropriate defaults, composite scoring weights register correctly
5. **DictionaryEngine** — Important. Test: CC-CEDICT lookup returns correct pinyin/definitions, multi-character word boundaries handled, fallback when LLM unavailable
6. **ContentIngestion** — Important. Test: EPUB text extraction completeness, PDF text extraction, metadata parsing, chapter ordering
7. **ReadingSession** — Important. Test: timer accuracy, word counting, comprehension calculation, session persistence
8. **AnkiExporter** — Moderate. Test: .apkg format validity, card state mapping accuracy, bidirectional roundtrip

### Test Prior Art
- Existing test patterns in `VoiceTutor/Tests/`, `Adhan/Tests/`, `Love/Tests/`, `Tiempo/Tests/`
- All use Swift Testing framework with SPM test targets
- Pattern: `Sources/` for production code, `Tests/` for test code

## Out of Scope (v1)

- iOS app (build after macOS is complete and stable)
- Curated content library / graded readers
- Web clipper / browser extension
- Community features (leaderboards, shared vocabulary)
- Multi-language support (Japanese, Korean, Arabic) — Chinese only for v1
- OCR for scanned PDFs (native text PDFs only)
- DRM-protected EPUB
- Voice cloning for TTS
- Content difficulty pre-scoring
- Sentence mining to external tools (beyond Anki)

## Further Notes

### Competitive Advantage
No macOS native app exists in this space. Full competitive analysis in `plans/chinese-reading-app-competitive-analysis.md`. Key gaps Leo fills:
- Pleco: best dictionary but no reading experience, no known-word tracking, no macOS
- LingQ: Chinese segmentation "sometimes inaccurate", ebook imports break formatting
- Du Chinese: best TTS sync but no content import, no macOS
- Migaku: no dedicated ebook reader, no macOS
- None use FSRS. None combine parsing + reading + TTS sync + SRS.

### First Test Content
活着 (Huǒ Zhe / To Live) by Yu Hua — intermediate-advanced literary novel. Tests: literary Chinese parsing, long-form reading, expression detection in narrative prose.

### Pricing Model (Future)
One-time purchase for core app + optional subscription for cloud TTS features. Market is subscription-fatigued; Pleco's one-time model is beloved.

### Key Risk
InWorld TTS Chinese word-level timestamps are marked "experimental" in their docs. Must test early. Fallback: Edge TTS has proven Chinese word boundary metadata via Python `edge-tts` library — would need a local Python bridge or reimplementation.
