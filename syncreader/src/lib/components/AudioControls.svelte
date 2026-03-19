<script lang="ts">
  import { audioPlayer } from '$lib/stores/audio';
  import { syncEngine } from '$lib/stores/sync';
  import type { PlaybackSpeed, LoopMode } from '$lib/types';

  type LoopModeEntry = { mode: LoopMode; label: string; icon: string };

  const speeds: PlaybackSpeed[] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
  const loopModes: LoopModeEntry[] = [
    { mode: 'off', label: 'No Loop', icon: '\u27F3' },
    { mode: 'sentence', label: 'Sentence', icon: 'S' },
    { mode: 'paragraph', label: 'Paragraph', icon: '\u00B6' },
    { mode: 'ab', label: 'A\u2013B', icon: 'AB' },
  ];

  let settingAB = $state<'none' | 'a' | 'b'>('none');

  function formatTime(seconds: number): string {
    if (!isFinite(seconds) || isNaN(seconds)) return '0:00';
    const m = Math.floor(seconds / 60);
    const s = Math.floor(seconds % 60);
    return `${m}:${s.toString().padStart(2, '0')}`;
  }

  function handleProgressClick(e: MouseEvent) {
    const bar = e.currentTarget as HTMLDivElement;
    const rect = bar.getBoundingClientRect();
    const ratio = (e.clientX - rect.left) / rect.width;
    audioPlayer.seek(ratio * audioPlayer.duration);
  }

  function handleProgressKeydown(e: KeyboardEvent) {
    if (e.key === 'ArrowLeft') {
      e.preventDefault();
      audioPlayer.seek(audioPlayer.currentTime - 5);
    } else if (e.key === 'ArrowRight') {
      e.preventDefault();
      audioPlayer.seek(audioPlayer.currentTime + 5);
    }
  }

  function cycleSpeed() {
    const idx = speeds.indexOf(audioPlayer.speed);
    const next = speeds[(idx + 1) % speeds.length];
    audioPlayer.setSpeed(next);
  }

  function cycleLoop() {
    const modes: LoopMode[] = ['off', 'sentence', 'paragraph', 'ab'];
    const idx = modes.indexOf(syncEngine.loop.mode);
    const next = modes[(idx + 1) % modes.length];
    syncEngine.setLoopMode(next);
    if (next === 'ab') {
      settingAB = 'a';
    } else {
      settingAB = 'none';
    }
  }

  function setABPoint() {
    if (settingAB === 'a') {
      syncEngine.loop = { ...syncEngine.loop, abStart: audioPlayer.currentTime };
      settingAB = 'b';
    } else if (settingAB === 'b') {
      const abStart = syncEngine.loop.abStart ?? 0;
      syncEngine.setABPoints(abStart, audioPlayer.currentTime);
      settingAB = 'none';
    }
  }

  function skipPrev() {
    const si = syncEngine.activeSentenceIndex;
    const sentences = syncEngine.sentences;
    if (si > 0) {
      audioPlayer.seek(sentences[si - 1].start);
    } else if (sentences.length > 0) {
      audioPlayer.seek(sentences[0].start);
    }
  }

  function skipNext() {
    const si = syncEngine.activeSentenceIndex;
    const sentences = syncEngine.sentences;
    if (si < sentences.length - 1) {
      audioPlayer.seek(sentences[si + 1].start);
    }
  }

  // Global keyboard shortcuts
  function handleKeydown(e: KeyboardEvent) {
    // Ignore shortcuts when a text input/textarea is focused
    const tag = (e.target as HTMLElement).tagName;
    if (tag === 'INPUT' || tag === 'TEXTAREA') return;

    if (e.code === 'Space') {
      e.preventDefault();
      audioPlayer.togglePlay();
    } else if (e.code === 'ArrowLeft') {
      e.preventDefault();
      skipPrev();
    } else if (e.code === 'ArrowRight') {
      e.preventDefault();
      skipNext();
    } else if (e.code === 'ArrowUp') {
      e.preventDefault();
      const idx = speeds.indexOf(audioPlayer.speed);
      const next = speeds[Math.min(idx + 1, speeds.length - 1)];
      audioPlayer.setSpeed(next);
    } else if (e.code === 'ArrowDown') {
      e.preventDefault();
      const idx = speeds.indexOf(audioPlayer.speed);
      const next = speeds[Math.max(idx - 1, 0)];
      audioPlayer.setSpeed(next);
    } else if (e.code === 'KeyL') {
      e.preventDefault();
      cycleLoop();
    }
  }

  const progressPercent = $derived(
    audioPlayer.duration > 0 ? (audioPlayer.currentTime / audioPlayer.duration) * 100 : 0
  );

  const loopRegionLeft = $derived(
    syncEngine.loop.abStart !== undefined && audioPlayer.duration > 0
      ? (syncEngine.loop.abStart / audioPlayer.duration) * 100
      : 0
  );

  const loopRegionWidth = $derived(
    syncEngine.loop.abStart !== undefined &&
      syncEngine.loop.abEnd !== undefined &&
      audioPlayer.duration > 0
      ? ((syncEngine.loop.abEnd - syncEngine.loop.abStart) / audioPlayer.duration) * 100
      : 0
  );

  const currentLoopIcon = $derived(
    loopModes.find((l) => l.mode === syncEngine.loop.mode)?.icon ?? '\u27F3'
  );
</script>

<svelte:window onkeydown={handleKeydown} />

<div class="controls">
  <!-- Progress bar -->
  <div
    class="progress-container"
    onclick={handleProgressClick}
    onkeydown={handleProgressKeydown}
    role="slider"
    tabindex="0"
    aria-label="Seek audio position"
    aria-valuemin={0}
    aria-valuemax={audioPlayer.duration}
    aria-valuenow={audioPlayer.currentTime}
  >
    <div class="progress-bg">
      <div class="progress-fill" style="width: {progressPercent}%"></div>
      {#if syncEngine.loop.mode === 'ab' && syncEngine.loop.abStart !== undefined && syncEngine.loop.abEnd !== undefined}
        <div
          class="loop-region"
          style="left: {loopRegionLeft}%; width: {loopRegionWidth}%"
        ></div>
      {/if}
    </div>
    <div class="time-display">
      <span>{formatTime(audioPlayer.currentTime)}</span>
      <span>{formatTime(audioPlayer.duration)}</span>
    </div>
  </div>

  <!-- Main controls -->
  <div class="main-controls">
    <button
      class="ctrl-btn speed-btn"
      onclick={cycleSpeed}
      title="Playback speed (Up/Down arrows)"
      aria-label="Playback speed: {audioPlayer.speed}x"
    >
      {audioPlayer.speed}x
    </button>

    <button
      class="ctrl-btn skip-btn"
      onclick={skipPrev}
      title="Previous sentence (Left arrow)"
      aria-label="Previous sentence"
    >
      &#x23EE;
    </button>

    <button
      class="ctrl-btn play-btn"
      onclick={() => audioPlayer.togglePlay()}
      title="Play / Pause (Space)"
      aria-label={audioPlayer.playing ? 'Pause' : 'Play'}
    >
      {#if audioPlayer.playing}
        &#x23F8;
      {:else}
        &#x25B6;
      {/if}
    </button>

    <button
      class="ctrl-btn skip-btn"
      onclick={skipNext}
      title="Next sentence (Right arrow)"
      aria-label="Next sentence"
    >
      &#x23ED;
    </button>

    <button
      class="ctrl-btn loop-btn"
      class:active={syncEngine.loop.mode !== 'off'}
      onclick={cycleLoop}
      title="Loop mode (L)"
      aria-label="Loop: {loopModes.find((l) => l.mode === syncEngine.loop.mode)?.label}"
    >
      {currentLoopIcon}
    </button>

    {#if syncEngine.loop.mode === 'ab' && settingAB !== 'none'}
      <button class="ctrl-btn ab-btn" onclick={setABPoint} aria-label="Set {settingAB.toUpperCase()} point">
        Set {settingAB.toUpperCase()}
      </button>
    {/if}
  </div>
</div>

<style>
  .controls {
    position: fixed;
    bottom: 0;
    left: 0;
    right: 0;
    background: var(--bg-secondary);
    border-top: 1px solid var(--border);
    padding: 0.75rem 1.5rem;
    backdrop-filter: blur(20px);
    -webkit-backdrop-filter: blur(20px);
  }

  .progress-container {
    cursor: pointer;
    padding: 4px 0;
    margin-bottom: 0.5rem;
  }

  .progress-bg {
    position: relative;
    height: 4px;
    background: var(--bg-tertiary);
    border-radius: 2px;
    overflow: hidden;
    transition: height var(--transition-fast);
  }

  .progress-container:hover .progress-bg,
  .progress-container:focus-visible .progress-bg {
    height: 6px;
  }

  .progress-container:focus-visible {
    outline: none;
  }

  .progress-fill {
    height: 100%;
    background: var(--accent);
    border-radius: 2px;
    transition: width 50ms linear;
  }

  .loop-region {
    position: absolute;
    top: 0;
    height: 100%;
    background: rgba(59, 130, 246, 0.3);
    border-left: 2px solid var(--accent);
    border-right: 2px solid var(--accent);
  }

  .time-display {
    display: flex;
    justify-content: space-between;
    font-size: 0.7rem;
    color: var(--text-muted);
    margin-top: 4px;
    font-variant-numeric: tabular-nums;
    font-family: 'SF Mono', 'Menlo', monospace;
  }

  .main-controls {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 0.75rem;
  }

  .ctrl-btn {
    background: none;
    border: 1px solid var(--border);
    color: var(--text-primary);
    border-radius: var(--radius);
    cursor: pointer;
    transition:
      background-color var(--transition-fast),
      border-color var(--transition-fast),
      color var(--transition-fast);
    font-size: 0.8rem;
    padding: 0.4rem 0.75rem;
    font-family: inherit;
    line-height: 1;
  }

  .ctrl-btn:hover {
    background: var(--bg-tertiary);
    border-color: var(--text-muted);
  }

  .ctrl-btn:focus-visible {
    outline: 2px solid var(--accent);
    outline-offset: 2px;
  }

  .play-btn {
    width: 48px;
    height: 48px;
    border-radius: 50%;
    font-size: 1.2rem;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 0;
    border-color: var(--accent);
  }

  .play-btn:hover {
    background: var(--accent-dim);
  }

  .loop-btn.active {
    background: var(--accent-dim);
    border-color: var(--accent);
    color: var(--accent);
  }

  .speed-btn {
    font-variant-numeric: tabular-nums;
    min-width: 3rem;
    font-family: 'SF Mono', 'Menlo', monospace;
    text-align: center;
  }

  .ab-btn {
    background: var(--accent-dim);
    border-color: var(--accent);
    color: var(--accent);
    animation: pulse 1s ease-in-out infinite;
  }

  @keyframes pulse {
    0%,
    100% {
      opacity: 1;
    }
    50% {
      opacity: 0.55;
    }
  }
</style>
