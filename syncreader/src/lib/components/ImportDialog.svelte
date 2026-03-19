<script lang="ts">
  import { invoke } from '@tauri-apps/api/core';
  import { open } from '@tauri-apps/plugin-dialog';
  import { readTextFile } from '@tauri-apps/plugin-fs';

  let {
    onImport,
  }: {
    onImport: (text: string, audioPath: string | null) => void;
  } = $props();

  let textInput = $state('');
  let textFile = $state<string | null>(null);
  let audioFile = $state<string | null>(null);
  let mode = $state<'paste' | 'file'>('paste');
  let loadingText = $state(false);
  let error = $state<string | null>(null);

  function basename(path: string): string {
    return path.split('/').pop() ?? path;
  }

  async function selectTextFile() {
    error = null;
    try {
      const selected = await open({
        multiple: false,
        filters: [{ name: 'Text', extensions: ['txt', 'md', 'srt', 'vtt'] }],
      });
      if (selected) {
        const path = typeof selected === 'string' ? selected : selected;
        textFile = path;
        loadingText = true;
        const content = await readTextFile(path);
        textInput = content;
      }
    } catch (e) {
      error = `Could not read text file: ${e}`;
    } finally {
      loadingText = false;
    }
  }

  async function selectAudioFile() {
    error = null;
    try {
      const selected = await open({
        multiple: false,
        filters: [{ name: 'Audio', extensions: ['mp3', 'wav', 'm4a', 'ogg', 'flac'] }],
      });
      if (selected) {
        audioFile = typeof selected === 'string' ? selected : selected;
      }
    } catch (e) {
      error = `Could not open audio file: ${e}`;
    }
  }

  function handleImport() {
    if (textInput.trim()) {
      onImport(textInput.trim(), audioFile);
    }
  }

  function handleKeydown(e: KeyboardEvent) {
    if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) {
      handleImport();
    }
  }

  const canImport = $derived(textInput.trim().length > 0);

  const importLabel = $derived(
    audioFile ? 'Open with Audio' : 'Open Text (Generate Audio Later)'
  );
</script>

<div class="import-dialog" role="main">
  <div class="dialog-header">
    <h1>SyncReader</h1>
    <p class="subtitle">Sync audio with text for language learning</p>

    <div class="tab-bar" role="tablist">
      <button
        class:active={mode === 'paste'}
        onclick={() => { mode = 'paste'; error = null; }}
        role="tab"
        aria-selected={mode === 'paste'}
      >
        Paste Text
      </button>
      <button
        class:active={mode === 'file'}
        onclick={() => { mode = 'file'; error = null; }}
        role="tab"
        aria-selected={mode === 'file'}
      >
        Load File
      </button>
    </div>
  </div>

  <div class="dialog-body">
    {#if mode === 'paste'}
      <textarea
        class="text-area"
        placeholder="Paste your text here...&#10;&#10;Supports plain text and speaker labels like:&#10;[Tutor]: Hello, let's begin today's lesson.&#10;[Student]: I'm ready!"
        bind:value={textInput}
        rows="12"
        onkeydown={handleKeydown}
        aria-label="Input text"
      ></textarea>
    {:else}
      <div class="file-section">
        <label class="file-label" for="text-file-btn">Text File</label>
        <button
          id="text-file-btn"
          class="file-btn"
          class:has-file={textFile !== null}
          onclick={selectTextFile}
          disabled={loadingText}
        >
          {#if loadingText}
            Loading...
          {:else if textFile}
            {basename(textFile)}
          {:else}
            Choose .txt or .md file...
          {/if}
        </button>
      </div>

      {#if textInput && textFile}
        <div class="file-preview">
          <span class="preview-label">Preview</span>
          <p class="preview-text">{textInput.slice(0, 200)}{textInput.length > 200 ? '...' : ''}</p>
        </div>
      {/if}
    {/if}

    <div class="file-section">
      <label class="file-label" for="audio-file-btn">
        Audio File
        <span class="label-hint">(optional — or generate after opening)</span>
      </label>
      <button
        id="audio-file-btn"
        class="file-btn"
        class:has-file={audioFile !== null}
        onclick={selectAudioFile}
      >
        {audioFile ? basename(audioFile) : 'Choose .mp3, .wav, or .m4a file...'}
      </button>
    </div>

    {#if error}
      <div class="error-message" role="alert">{error}</div>
    {/if}
  </div>

  <div class="dialog-footer">
    <p class="hint">Tip: press Cmd+Enter to open</p>
    <button
      class="primary-btn"
      onclick={handleImport}
      disabled={!canImport}
      aria-disabled={!canImport}
    >
      {importLabel}
    </button>
  </div>
</div>

<style>
  .import-dialog {
    max-width: 600px;
    margin: 8vh auto 0;
    padding: 2.5rem 2rem;
  }

  .dialog-header h1 {
    font-size: 1.75rem;
    font-weight: 700;
    letter-spacing: -0.02em;
    color: var(--text-primary);
    margin-bottom: 0.25rem;
  }

  .subtitle {
    font-size: 0.875rem;
    color: var(--text-secondary);
    margin-bottom: 1.5rem;
  }

  .tab-bar {
    display: flex;
    gap: 0.5rem;
    margin-bottom: 1.5rem;
  }

  .tab-bar button {
    background: var(--bg-tertiary);
    border: 1px solid var(--border);
    color: var(--text-secondary);
    padding: 0.45rem 1rem;
    border-radius: var(--radius);
    cursor: pointer;
    font-size: 0.85rem;
    font-family: inherit;
    transition:
      background-color var(--transition-fast),
      border-color var(--transition-fast),
      color var(--transition-fast);
  }

  .tab-bar button:hover {
    color: var(--text-primary);
    border-color: var(--text-muted);
  }

  .tab-bar button.active {
    background: var(--accent-dim);
    border-color: var(--accent);
    color: var(--accent);
  }

  .tab-bar button:focus-visible {
    outline: 2px solid var(--accent);
    outline-offset: 2px;
  }

  .text-area {
    width: 100%;
    background: var(--bg-secondary);
    border: 1px solid var(--border);
    border-radius: var(--radius);
    color: var(--text-primary);
    padding: 0.875rem 1rem;
    font-size: 0.95rem;
    line-height: 1.6;
    resize: vertical;
    font-family: inherit;
    transition: border-color var(--transition-fast);
  }

  .text-area::placeholder {
    color: var(--text-muted);
    white-space: pre-wrap;
  }

  .text-area:focus {
    outline: none;
    border-color: var(--accent);
  }

  .file-section {
    margin-top: 1.25rem;
  }

  .file-label {
    display: block;
    font-size: 0.8rem;
    font-weight: 500;
    color: var(--text-secondary);
    margin-bottom: 0.4rem;
  }

  .label-hint {
    font-weight: 400;
    color: var(--text-muted);
    margin-left: 0.35rem;
  }

  .file-btn {
    width: 100%;
    background: var(--bg-secondary);
    border: 1px dashed var(--border);
    color: var(--text-muted);
    padding: 0.75rem 1rem;
    border-radius: var(--radius);
    cursor: pointer;
    text-align: left;
    font-size: 0.85rem;
    font-family: inherit;
    transition:
      border-color var(--transition-fast),
      color var(--transition-fast),
      background-color var(--transition-fast);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .file-btn:hover {
    border-color: var(--accent);
    color: var(--text-primary);
  }

  .file-btn:focus-visible {
    outline: 2px solid var(--accent);
    outline-offset: 2px;
  }

  .file-btn:disabled {
    cursor: not-allowed;
    opacity: 0.5;
  }

  .file-btn.has-file {
    border-style: solid;
    border-color: var(--border);
    color: var(--text-primary);
  }

  .file-preview {
    margin-top: 0.75rem;
    padding: 0.75rem 1rem;
    background: var(--bg-secondary);
    border: 1px solid var(--border);
    border-radius: var(--radius);
  }

  .preview-label {
    font-size: 0.7rem;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: var(--text-muted);
    display: block;
    margin-bottom: 0.4rem;
  }

  .preview-text {
    font-size: 0.85rem;
    color: var(--text-secondary);
    line-height: 1.5;
    white-space: pre-wrap;
    word-break: break-word;
  }

  .error-message {
    margin-top: 1rem;
    padding: 0.65rem 0.875rem;
    background: rgba(239, 68, 68, 0.1);
    border: 1px solid rgba(239, 68, 68, 0.3);
    border-radius: var(--radius);
    color: #f87171;
    font-size: 0.85rem;
  }

  .dialog-footer {
    margin-top: 1.75rem;
    display: flex;
    align-items: center;
    justify-content: flex-end;
    gap: 1rem;
  }

  .hint {
    font-size: 0.75rem;
    color: var(--text-muted);
  }

  .primary-btn {
    background: var(--accent);
    color: white;
    border: none;
    padding: 0.6rem 1.5rem;
    border-radius: var(--radius);
    cursor: pointer;
    font-size: 0.9rem;
    font-weight: 500;
    font-family: inherit;
    transition: opacity var(--transition-fast);
    white-space: nowrap;
  }

  .primary-btn:hover:not(:disabled) {
    opacity: 0.9;
  }

  .primary-btn:focus-visible {
    outline: 2px solid var(--accent);
    outline-offset: 3px;
  }

  .primary-btn:disabled {
    opacity: 0.35;
    cursor: not-allowed;
  }
</style>
