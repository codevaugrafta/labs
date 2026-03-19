import type { WordTimestamp, SentenceBoundary, LoopState } from '$lib/types';

class SyncEngine {
  timestamps = $state<WordTimestamp[]>([]);
  sentences = $state<SentenceBoundary[]>([]);
  activeWordIndex = $state(-1);
  activeSentenceIndex = $state(-1);
  loop = $state<LoopState>({ mode: 'off' });

  setData(timestamps: WordTimestamp[], sentences: SentenceBoundary[]): void {
    this.timestamps = timestamps;
    this.sentences = sentences;
    this.activeWordIndex = -1;
    this.activeSentenceIndex = -1;
  }

  /**
   * Binary search for the active word at the given playback time.
   * Returns the index of the word whose window contains `time`,
   * or -1 if we are in a gap between words.
   */
  findWordAtTime(time: number): number {
    const ts = this.timestamps;
    if (ts.length === 0) return -1;

    let low = 0;
    let high = ts.length - 1;
    let result = -1;

    while (low <= high) {
      const mid = (low + high) >>> 1;
      if (ts[mid].start <= time) {
        result = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }

    // We found the last word that started before or at `time`.
    // Confirm it has not yet ended (guard against inter-word gaps).
    if (result >= 0 && ts[result].end < time) {
      return -1;
    }

    return result;
  }

  /**
   * Called on every animation frame while audio is playing.
   * Updates active word/sentence and returns a seek target if a loop
   * boundary has been crossed, otherwise returns null.
   */
  update(currentTime: number): number | null {
    const wordIdx = this.findWordAtTime(currentTime);
    this.activeWordIndex = wordIdx;

    if (wordIdx >= 0) {
      this.activeSentenceIndex = this.timestamps[wordIdx].sentenceIndex;
    }

    return this.enforceLoop(currentTime);
  }

  private enforceLoop(currentTime: number): number | null {
    const { mode, abStart, abEnd } = this.loop;

    if (mode === 'off') return null;

    if (mode === 'sentence' && this.activeSentenceIndex >= 0) {
      const sentence = this.sentences[this.activeSentenceIndex];
      if (sentence && currentTime >= sentence.end && sentence.end > 0) {
        return sentence.start;
      }
    }

    if (mode === 'ab' && abStart !== undefined && abEnd !== undefined) {
      if (currentTime >= abEnd) {
        return abStart;
      }
    }

    if (mode === 'paragraph' && this.activeSentenceIndex >= 0) {
      // Group every 3 sentences into a logical paragraph unless speaker labels change.
      const paragraphStart = Math.floor(this.activeSentenceIndex / 3) * 3;
      const paragraphEndIdx = Math.min(paragraphStart + 2, this.sentences.length - 1);
      const startTime = this.sentences[paragraphStart]?.start ?? 0;
      const endTime = this.sentences[paragraphEndIdx]?.end ?? Infinity;
      if (endTime > 0 && currentTime >= endTime) {
        return startTime;
      }
    }

    return null;
  }

  setLoopMode(mode: LoopState['mode']): void {
    this.loop = { ...this.loop, mode };
  }

  setABPoints(start: number, end: number): void {
    this.loop = { mode: 'ab', abStart: start, abEnd: end };
  }

  clearLoop(): void {
    this.loop = { mode: 'off' };
  }
}

export const syncEngine = new SyncEngine();
