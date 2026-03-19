<script lang="ts">
  import { syncEngine } from '$lib/stores/sync.svelte';
  import { audioPlayer } from '$lib/stores/audio.svelte';
  import type { WordTimestamp, SentenceBoundary } from '$lib/types';

  let {
    timestamps,
    sentences,
  }: {
    timestamps: WordTimestamp[];
    sentences: SentenceBoundary[];
  } = $props();

  let containerEl: HTMLDivElement | undefined = $state();
  let animationFrame: number | undefined;

  // Group words by sentence for rendering. Recomputed reactively when props change.
  const sentenceGroups = $derived(
    sentences.map((sentence) => ({
      sentence,
      words: timestamps
        .map((w, i) => ({ ...w, globalIndex: i }))
        .filter((w) => w.sentenceIndex === sentence.index),
    }))
  );

  // Animation loop — starts/stops with audioPlayer.playing
  $effect(() => {
    if (!audioPlayer.playing) {
      if (animationFrame !== undefined) {
        cancelAnimationFrame(animationFrame);
        animationFrame = undefined;
      }
      return;
    }

    function tick() {
      const seekTarget = syncEngine.update(audioPlayer.currentTime);
      if (seekTarget !== null) {
        audioPlayer.seek(seekTarget);
      }

      // Auto-scroll active word into view without causing layout thrash
      if (containerEl) {
        const activeEl = containerEl.querySelector<HTMLElement>('.word-active');
        if (activeEl) {
          const container = containerEl;
          const elTop = activeEl.offsetTop - container.offsetTop;
          const elBottom = elTop + activeEl.offsetHeight;
          const scrollTop = container.scrollTop;
          const viewHeight = container.clientHeight;

          // Only scroll if the word is outside the middle third of the viewport
          const zoneTop = scrollTop + viewHeight * 0.3;
          const zoneBottom = scrollTop + viewHeight * 0.7;
          if (elTop < zoneTop || elBottom > zoneBottom) {
            activeEl.scrollIntoView({ behavior: 'smooth', block: 'center' });
          }
        }
      }

      animationFrame = requestAnimationFrame(tick);
    }

    animationFrame = requestAnimationFrame(tick);

    return () => {
      if (animationFrame !== undefined) {
        cancelAnimationFrame(animationFrame);
        animationFrame = undefined;
      }
    };
  });

  function handleWordClick(word: WordTimestamp & { globalIndex: number }) {
    audioPlayer.seek(word.start);
    if (!audioPlayer.playing) audioPlayer.play();
  }

  function handleSentenceClick(sentence: SentenceBoundary) {
    audioPlayer.seek(sentence.start);
    if (!audioPlayer.playing) audioPlayer.play();
  }

  function handleWordKeydown(e: KeyboardEvent, word: WordTimestamp & { globalIndex: number }) {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      handleWordClick(word);
    }
  }

  function handleSentenceKeydown(e: KeyboardEvent, sentence: SentenceBoundary) {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      handleSentenceClick(sentence);
    }
  }
</script>

<div class="text-renderer" bind:this={containerEl}>
  {#each sentenceGroups as { sentence, words } (sentence.index)}
    {#if sentence.speaker}
      <div class="speaker-label">{sentence.speaker}</div>
    {/if}
    <span
      class="sentence"
      class:sentence-active={syncEngine.activeSentenceIndex === sentence.index}
      onclick={() => handleSentenceClick(sentence)}
      onkeydown={(e) => handleSentenceKeydown(e, sentence)}
      role="button"
      tabindex="0"
    >
      {#each words as word (word.globalIndex)}
        <span
          class="word"
          class:word-active={syncEngine.activeWordIndex === word.globalIndex}
          onclick={(e) => { e.stopPropagation(); handleWordClick(word); }}
          onkeydown={(e) => handleWordKeydown(e, word)}
          role="button"
          tabindex="0"
        >{word.word}</span>{' '}
      {/each}
    </span>
  {/each}
</div>

<style>
  .text-renderer {
    padding: 2rem 3rem;
    max-height: calc(100vh - 160px);
    overflow-y: auto;
    scroll-behavior: smooth;
    line-height: 2;
    font-size: 1.25rem;
    letter-spacing: 0.01em;
    color: var(--text-primary);
  }

  .text-renderer::-webkit-scrollbar {
    width: 6px;
  }

  .text-renderer::-webkit-scrollbar-track {
    background: transparent;
  }

  .text-renderer::-webkit-scrollbar-thumb {
    background: var(--border);
    border-radius: 3px;
  }

  .speaker-label {
    display: block;
    font-size: 0.75rem;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--accent);
    margin-top: 1.5rem;
    margin-bottom: 0.25rem;
    opacity: 0.8;
  }

  .sentence {
    display: inline;
    border-radius: 4px;
    padding: 2px 0;
    transition: background-color var(--transition-fast);
    cursor: pointer;
  }

  .sentence:focus-visible {
    outline: 2px solid var(--accent);
    outline-offset: 2px;
  }

  .sentence-active {
    background-color: var(--sentence-active-bg);
  }

  .word {
    display: inline;
    border-radius: 3px;
    padding: 1px 2px;
    cursor: pointer;
    transition:
      background-color var(--transition-fast),
      color var(--transition-fast);
  }

  .word:hover {
    background-color: var(--bg-tertiary);
  }

  .word:focus-visible {
    outline: 2px solid var(--accent);
    outline-offset: 1px;
  }

  .word-active {
    background-color: var(--word-active-bg);
    color: var(--word-active);
    font-weight: 500;
  }
</style>
