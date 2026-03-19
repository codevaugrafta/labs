<script lang="ts">
  import { onDestroy } from 'svelte';
  import { invoke } from '@tauri-apps/api/core';
  import TextRenderer from '$lib/components/TextRenderer.svelte';
  import AudioControls from '$lib/components/AudioControls.svelte';
  import ImportDialog from '$lib/components/ImportDialog.svelte';
  import { audioPlayer } from '$lib/stores/audio';
  import { syncEngine } from '$lib/stores/sync';
  import type { WordTimestamp, SentenceBoundary } from '$lib/types';
  import '$lib/styles/global.css';

  type View = 'import' | 'reader';

  let view = $state<View>('import');
  let timestamps = $state<WordTimestamp[]>([]);
  let sentences = $state<SentenceBoundary[]>([]);
  let aligning = $state(false);
  let alignProgress = $state('');
  let alignError = $state<string | null>(null);

  async function handleImport(inputText: string, audioPath: string | null) {
    alignError = null;

    if (audioPath) {
      aligning = true;
      alignProgress = 'Loading audio...';

      try {
        // Ask the Rust backend to convert the file path to a safe asset URL
        const assetUrl = await invoke<string>('get_asset_url', { path: audioPath });
        audioPlayer.load(assetUrl);

        alignProgress = 'Aligning audio with text...';
        const result = await invoke<{ timestamps: WordTimestamp[]; sentences: SentenceBoundary[] }>(
          'align_audio',
          { audioPath, text: inputText }
        );

        timestamps = result.timestamps;
        sentences = result.sentences;
        syncEngine.setData(timestamps, sentences);
        view = 'reader';
      } catch (e) {
        alignError = `Alignment failed: ${e}`;
        alignProgress = '';
      } finally {
        aligning = false;
      }
    } else {
      // Text-only — parse locally into sentences for display
      const parsed = parseTextIntoSentences(inputText);
      timestamps = parsed.timestamps;
      sentences = parsed.sentences;
      syncEngine.setData(timestamps, sentences);
      view = 'reader';
    }
  }

  /**
   * Splits raw text into WordTimestamp and SentenceBoundary structures
   * without any timing information (timing = 0 until audio alignment runs).
   * Supports [Speaker]: text label format.
   */
  function parseTextIntoSentences(text: string): {
    timestamps: WordTimestamp[];
    sentences: SentenceBoundary[];
  } {
    const lines = text.split('\n').filter((l) => l.trim().length > 0);
    const allTimestamps: WordTimestamp[] = [];
    const allSentences: SentenceBoundary[] = [];
    let wordIndex = 0;
    let sentenceIndex = 0;

    for (const line of lines) {
      // Optional [Speaker]: prefix
      const speakerMatch = line.match(/^\[([^\]]+)\]:\s*(.*)/);
      const speaker = speakerMatch ? speakerMatch[1] : undefined;
      const content = speakerMatch ? speakerMatch[2] : line;

      if (!content.trim()) continue;

      // Split content into sentences on . ! ? boundaries
      const sentenceTexts = content.match(/[^.!?]+[.!?]+|[^.!?]+$/g) ?? [content];

      for (const sentText of sentenceTexts) {
        const words = sentText.trim().split(/\s+/).filter((w) => w.length > 0);
        if (words.length === 0) continue;

        const startWordIndex = wordIndex;

        for (const word of words) {
          allTimestamps.push({
            word,
            start: 0,
            end: 0,
            sentenceIndex,
          });
          wordIndex++;
        }

        allSentences.push({
          index: sentenceIndex,
          startWordIndex,
          endWordIndex: wordIndex - 1,
          start: 0,
          end: 0,
          speaker,
        });
        sentenceIndex++;
      }
    }

    return { timestamps: allTimestamps, sentences: allSentences };
  }

  function goBack() {
    audioPlayer.pause();
    alignError = null;
    view = 'import';
  }

  onDestroy(() => {
    audioPlayer.destroy();
  });
</script>

{#if view === 'import'}
  <ImportDialog onImport={handleImport} />

  {#if alignError}
    <div class="global-error" role="alert">
      {alignError}
      <button onclick={() => (alignError = null)} aria-label="Dismiss error">&#x2715;</button>
    </div>
  {/if}
{:else}
  {#if aligning}
    <div class="aligning-overlay" role="status" aria-live="polite">
      <div class="spinner" aria-hidden="true"></div>
      <p>{alignProgress}</p>
    </div>
  {/if}

  <div class="reader-layout">
    <header class="toolbar">
      <button class="back-btn" onclick={goBack} aria-label="Back to import">
        &#x2190; Back
      </button>
      <div class="toolbar-spacer"></div>
    </header>

    <main class="reader-body">
      <TextRenderer {timestamps} {sentences} />
    </main>

    {#if audioPlayer.loaded}
      <AudioControls />
    {:else if !aligning && sentences.length > 0}
      <div class="no-audio-bar">
        No audio loaded — open a file or generate audio from this text.
      </div>
    {/if}
  </div>
{/if}

<style>
  .reader-layout {
    height: 100vh;
    display: flex;
    flex-direction: column;
    background: var(--bg-primary);
  }

  .toolbar {
    display: flex;
    align-items: center;
    padding: 0.5rem 1rem;
    border-bottom: 1px solid var(--border);
    background: var(--bg-secondary);
    /* Allow window dragging on the toolbar area */
    -webkit-app-region: drag;
    min-height: 40px;
    flex-shrink: 0;
  }

  .back-btn {
    /* Exclude the button itself from the drag region */
    -webkit-app-region: no-drag;
    background: none;
    border: none;
    color: var(--text-secondary);
    cursor: pointer;
    font-size: 0.85rem;
    font-family: inherit;
    padding: 0.25rem 0.5rem;
    border-radius: var(--radius);
    transition: color var(--transition-fast);
    line-height: 1;
  }

  .back-btn:hover {
    color: var(--text-primary);
  }

  .back-btn:focus-visible {
    outline: 2px solid var(--accent);
    outline-offset: 2px;
  }

  .toolbar-spacer {
    flex: 1;
  }

  .reader-body {
    flex: 1;
    overflow: hidden;
    display: flex;
    flex-direction: column;
  }

  /* Overlay while running audio alignment */
  .aligning-overlay {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.75);
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    z-index: 200;
    gap: 1rem;
  }

  .aligning-overlay p {
    color: var(--text-secondary);
    font-size: 0.9rem;
  }

  .spinner {
    width: 32px;
    height: 32px;
    border: 3px solid var(--border);
    border-top-color: var(--accent);
    border-radius: 50%;
    animation: spin 0.75s linear infinite;
  }

  @keyframes spin {
    to {
      transform: rotate(360deg);
    }
  }

  /* Thin status bar shown when text is loaded but no audio is present */
  .no-audio-bar {
    position: fixed;
    bottom: 0;
    left: 0;
    right: 0;
    padding: 0.6rem 1.5rem;
    background: var(--bg-secondary);
    border-top: 1px solid var(--border);
    font-size: 0.8rem;
    color: var(--text-muted);
    text-align: center;
  }

  /* Global error toast (shown on import view after failed alignment) */
  .global-error {
    position: fixed;
    bottom: 1.5rem;
    left: 50%;
    transform: translateX(-50%);
    background: rgba(239, 68, 68, 0.12);
    border: 1px solid rgba(239, 68, 68, 0.35);
    color: #f87171;
    padding: 0.65rem 1rem;
    border-radius: var(--radius);
    font-size: 0.85rem;
    display: flex;
    align-items: center;
    gap: 0.75rem;
    z-index: 300;
    max-width: 480px;
    width: calc(100% - 3rem);
  }

  .global-error button {
    background: none;
    border: none;
    color: inherit;
    cursor: pointer;
    font-size: 1rem;
    padding: 0;
    line-height: 1;
    opacity: 0.7;
    flex-shrink: 0;
  }

  .global-error button:hover {
    opacity: 1;
  }
</style>
