# Leo — Implementation Plan

## Tracer Bullet Phases

Each phase is a thin vertical slice through ALL layers (model → logic → UI → tests).
Each phase is demoable on its own. macOS only — iOS deferred.

---

## Phase 1: Skeleton — Read a Book
**Goal:** Open an EPUB file and render it in a clean SwiftUI window.
**Demo:** Launch Leo → File > Open → see 活着 rendered in an iBooks-clean reader.

### Acceptance Criteria
- [ ] SPM project compiles and runs on macOS 15+
- [ ] Readium Swift Toolkit integrated as dependency
- [ ] File picker opens and accepts .epub files
- [ ] EPUB renders in a WKWebView via Readium Navigator
- [ ] Clean reading layout: horizontal text, comfortable margins, system font
- [ ] Page navigation (next/previous) works
- [ ] Reading position persisted per book (SwiftData)
- [ ] Book model: id, title, author, filePath, lastPosition
- [ ] Dark/light/sepia theme toggle
- [ ] Window remembers size/position

### Modules Touched
- ContentIngestion (EPUB only)
- ReaderView (basic)
- SwiftData models (Book)

---

## Phase 2: The Parser — Tap a Word, See a Definition
**Goal:** Tap any Chinese word and see a dictionary popup.
**Demo:** Reading 活着 → tap 虽然 → floating popup shows: suīrán, "although; even though", HSK 3

### Acceptance Criteria
- [ ] Chinese text segmented into word-level tokens via NLTagger
- [ ] Tap/click any word highlights it and shows floating popup
- [ ] Popup shows: word, pinyin, English definition, HSK level
- [ ] CC-CEDICT dictionary embedded in app bundle (~5MB)
- [ ] Dictionary lookup returns results in <50ms
- [ ] Popup dismisses on tap elsewhere or Escape key
- [ ] Character-level selection mode toggle (tap individual characters)
- [ ] Word boundaries visualized on hover (subtle underline)
- [ ] Modifier key + hover = instant lookup without click

### Modules Touched
- ChineseParser (Layer 1: NLTagger)
- DictionaryEngine (CC-CEDICT only)
- ReaderView (tap handling, popup overlay)

---

## Phase 3: Know Thyself — Word Familiarity Tracking
**Goal:** Words you know are invisible. Words you don't know are highlighted.
**Demo:** Reading 活着 → unknown words highlighted in red/orange → tap "I know this" → word becomes invisible → comprehension % updates.

### Acceptance Criteria
- [ ] VocabularyEntry model persisted in SwiftData
- [ ] 5 familiarity states implemented: Unknown, Seen, Learning, Familiar, Known
- [ ] All words start as Unknown for new users
- [ ] Reading a page auto-transitions encountered words Unknown → Seen
- [ ] Manual "Mark as Known" action (right-click or button)
- [ ] Familiarity state colors rendered as text decorations in Readium
- [ ] Per-page comprehension score displayed (known+familiar / total)
- [ ] Toggle: show/hide all familiarity highlighting
- [ ] Pinyin interlinear toggle (show above unknown words only, or all, or none)
- [ ] English overlay toggle for unknown lemmas
- [ ] FamiliarityTracker transition algorithm: weighted composite of encounter count + manual marking

### Modules Touched
- FamiliarityTracker
- ReaderView (decoration overlays)
- SwiftData models (VocabularyEntry)

---

## Phase 4: Frequency Intelligence — How Common Is This Word?
**Goal:** Every word has a frequency rank from real Chinese corpora.
**Demo:** Tap 虽然 → popup now shows "Frequency: Top 500 (very common)" with register breakdown.

### Acceptance Criteria
- [ ] SUBTLEX-CH word frequency data embedded (~2MB compressed)
- [ ] TUBELEX-ZH frequency data embedded
- [ ] BCC frequency data embedded (subset: top 50K words)
- [ ] FrequencyEngine returns composite score + per-corpus rank
- [ ] Comprehension score now weighted by frequency (missing a common word hurts more)
- [ ] Dictionary popup shows frequency tier (Top 500 / Top 2000 / Top 5000 / Rare)
- [ ] FamiliarityTracker uses frequency in transition weighting (common words promoted faster)

### Modules Touched
- FrequencyEngine
- DictionaryEngine (extended popup)
- FamiliarityTracker (frequency-weighted transitions)

---

## Phase 5: Remember — FSRS Spaced Repetition
**Goal:** One-click from unknown word to SRS schedule. Review cards inside Leo.
**Demo:** Tap unknown word → "Add to Review" button → card created → Review tab shows due cards with FSRS scheduling.

### Acceptance Criteria
- [ ] FSRSCard model in SwiftData linked to VocabularyEntry
- [ ] FSRS v5 algorithm implemented in Swift (schedule, stability, difficulty)
- [ ] "Add to Review" action in word popup creates an FSRSCard
- [ ] Card automatically includes: word, pinyin, definition, source sentence
- [ ] Review interface: show front (word in sentence context) → user rates (Again/Hard/Good/Easy)
- [ ] FSRS schedules next review based on rating
- [ ] FamiliarityTracker transitions Learning → Familiar → Known based on FSRS stability thresholds
- [ ] Due cards count shown in sidebar or menu bar
- [ ] Review session with card queue

### Modules Touched
- FSRSEngine
- FamiliarityTracker (FSRS-driven transitions)
- ReaderView (Add to Review action)
- New: ReviewView

---

## Phase 6: Listen — TTS with Word Highlighting
**Goal:** Press play, hear the text read aloud, see words highlighted in sync.
**Demo:** Reading 活着 → press Play → InWorld TTS reads the page → each word highlights as it's spoken → click a word, audio jumps there.

### Acceptance Criteria
- [ ] InWorld TTS API integrated (API key in Keychain)
- [ ] Pre-generate audio for current page/chapter with word timestamps
- [ ] Audio playback with word-by-word highlight sync
- [ ] Click any word to seek TTS to that position
- [ ] Playback speed control (0.5x–2.0x)
- [ ] Play/pause/stop controls
- [ ] Edge TTS fallback when InWorld unavailable
- [ ] Loading indicator while audio generates
- [ ] Audio cached per chapter to avoid re-generation
- [ ] Shadow reading mode (TTS plays, user reads along)

### Modules Touched
- TTSEngine
- ReaderView (highlight sync, audio controls)

---

## Phase 7: Track — Reading Sessions & Analytics
**Goal:** Know exactly how much you read and for how long.
**Demo:** Press Cmd+R to start session → read → press Cmd+R to stop → see: "Read 2,341 characters in 23 minutes, 87% comprehension, 12 new words."

### Acceptance Criteria
- [ ] Start/stop session via keybinding (Cmd+R or configurable)
- [ ] Start marker overlay appears on text at session start position
- [ ] Stop action lets user select exact stop position
- [ ] Highlighted range between start and stop markers
- [ ] Session stats: words, characters, pages, time, new words encountered, comprehension %
- [ ] Reading speed: characters/minute
- [ ] Session history persisted in SwiftData
- [ ] Stats panel in sidebar showing cumulative stats + per-session breakdown
- [ ] Timer visible/hidden toggle during reading

### Modules Touched
- ReadingSession
- ReaderView (markers, stats panel)
- SwiftData models (ReadingSession)

---

## Phase 8: Bridge — Anki Import/Export
**Goal:** Import existing Anki knowledge, export new cards.
**Demo:** Import Chinese Anki deck → 3,000 words auto-marked as Known → reading 活着 now shows far fewer highlights. Export new words back to Anki.

### Acceptance Criteria
- [ ] Import .apkg files (Anki package format: SQLite + media)
- [ ] Parse card states and map to FamiliarityTracker: new→Unknown, learning→Learning, young→Familiar, mature→Known
- [ ] Bulk update VocabularyEntry states from import
- [ ] Export selected vocabulary to .apkg with: word, pinyin, definition, context sentence, audio
- [ ] Export preserves Anki note type compatibility
- [ ] Import/export accessible from Settings or File menu

### Modules Touched
- AnkiExporter
- FamiliarityTracker (bulk import)

---

## Phase 9: Expressions — Multi-Word Detection
**Goal:** Detect and highlight multi-word expressions, collocations, and grammar patterns.
**Demo:** Reading 活着 → "不得不" highlighted as one expression (not three characters) → popup shows the expression meaning, not individual character meanings.

### Acceptance Criteria
- [ ] Curated MWE dictionary embedded (成语, 惯用语, common collocations)
- [ ] Parser Layer 2: dictionary-based expression detection
- [ ] Grammar pattern recognition: 把, 被, 越...越, 一边...一边, etc.
- [ ] Expressions rendered as single highlightable units in reader
- [ ] Expression popup shows: full expression, pinyin, meaning, pattern explanation
- [ ] Parser Layer 3 (optional): OpenRouter LLM contextual chunking for ambiguous cases
- [ ] Expression familiarity tracked same as word familiarity (5-state)

### Modules Touched
- ChineseParser (Layers 2 + 3)
- DictionaryEngine (expression definitions)
- FamiliarityTracker (expression tracking)

---

## Phase 10: PDF — Support the Second Format
**Goal:** Everything that works for EPUB also works for PDF.
**Demo:** Open a PDF of a Chinese textbook → same tap-to-define, highlighting, TTS, and tracking.

### Acceptance Criteria
- [ ] PDF rendering via Apple PDFKit
- [ ] Text extraction from native-text PDFs
- [ ] Same overlay system for word highlights, familiarity colors, pinyin
- [ ] Same tap-to-define, TTS, session tracking
- [ ] ContentIngestion handles both EPUB and PDF through unified interface

### Modules Touched
- ContentIngestion (PDF path)
- ReaderView (PDFKit integration)

---

## Phase 11: Polish — Dictation, Sync, Menu Bar
**Goal:** Ship-quality app with all remaining features.
**Demo:** Full app with blur dictation mode, cloud sync, menu bar integration, keyboard shortcuts for everything.

### Acceptance Criteria
- [ ] Dictation mode: blur overlay + TTS plays + user writes what they hear
- [ ] SyncEngine: iCloud for position/settings, Supabase for vocabulary/SRS
- [ ] Conflict resolution: last-write-wins for position, union for vocabulary
- [ ] Menu bar integration: current book, reading stats, quick actions
- [ ] Full keyboard shortcut coverage
- [ ] Settings window: TTS provider, API keys, theme, font, shortcuts
- [ ] App icon and branding
- [ ] build-app.sh following existing project patterns
- [ ] Entitlements: network, file access, keychain

### Modules Touched
- SyncEngine
- TTSEngine (dictation mode)
- ReaderView (blur overlay)
- MenuBarManager
- SettingsView

---

## Dependency Graph

```
Phase 1 (Skeleton)
  └→ Phase 2 (Parser + Dictionary)
       └→ Phase 3 (Familiarity Tracking)
            ├→ Phase 4 (Frequency Intelligence)
            ├→ Phase 5 (FSRS SRS)
            └→ Phase 9 (Expressions)
       └→ Phase 6 (TTS)
  └→ Phase 7 (Reading Sessions) [independent after Phase 1]
  └→ Phase 10 (PDF) [independent after Phase 1]
Phase 3 + 5 → Phase 8 (Anki)
All phases → Phase 11 (Polish)
```

## Build Sequence (Recommended)

1. Phase 1 → 2 → 3 (core reading loop: open book → tap word → track knowledge)
2. Phase 4 + 5 in parallel (frequency + SRS both extend Phase 3)
3. Phase 6 (TTS — independent from SRS)
4. Phase 7 (sessions — can start after Phase 1)
5. Phase 8 (Anki — needs Phase 3 + 5)
6. Phase 9 (expressions — extends parser)
7. Phase 10 (PDF)
8. Phase 11 (polish + ship)
