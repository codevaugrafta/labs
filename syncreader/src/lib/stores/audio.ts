import type { PlaybackSpeed } from '$lib/types';

class AudioPlayer {
  private audio: HTMLAudioElement | null = null;

  currentTime = $state(0);
  duration = $state(0);
  playing = $state(false);
  speed = $state<PlaybackSpeed>(1.0);
  volume = $state(1.0);
  loaded = $state(false);

  load(src: string): void {
    if (this.audio) {
      this.audio.pause();
      this.audio.removeEventListener('timeupdate', this.onTimeUpdate);
      this.audio.removeEventListener('loadedmetadata', this.onLoaded);
      this.audio.removeEventListener('ended', this.onEnded);
    }
    this.audio = new Audio(src);
    this.audio.addEventListener('timeupdate', this.onTimeUpdate);
    this.audio.addEventListener('loadedmetadata', this.onLoaded);
    this.audio.addEventListener('ended', this.onEnded);
    this.loaded = false;
    this.playing = false;
    this.currentTime = 0;
    this.duration = 0;
  }

  private onTimeUpdate = (): void => {
    if (this.audio) this.currentTime = this.audio.currentTime;
  };

  private onLoaded = (): void => {
    if (this.audio) {
      this.duration = this.audio.duration;
      this.audio.playbackRate = this.speed;
      this.audio.volume = this.volume;
      this.loaded = true;
    }
  };

  private onEnded = (): void => {
    this.playing = false;
  };

  async play(): Promise<void> {
    if (this.audio && this.loaded) {
      try {
        await this.audio.play();
        this.playing = true;
      } catch (err) {
        this.playing = false;
        console.error('[AudioPlayer] play() failed:', err);
      }
    }
  }

  pause(): void {
    if (this.audio) {
      this.audio.pause();
      this.playing = false;
    }
  }

  async togglePlay(): Promise<void> {
    if (this.playing) this.pause();
    else await this.play();
  }

  seek(time: number): void {
    if (this.audio) {
      const clamped = Math.max(0, Math.min(time, this.duration));
      this.audio.currentTime = clamped;
      this.currentTime = clamped;
    }
  }

  setSpeed(speed: PlaybackSpeed): void {
    this.speed = speed;
    if (this.audio) this.audio.playbackRate = speed;
  }

  setVolume(vol: number): void {
    this.volume = Math.max(0, Math.min(1, vol));
    if (this.audio) this.audio.volume = this.volume;
  }

  destroy(): void {
    if (this.audio) {
      this.audio.pause();
      this.audio.removeEventListener('timeupdate', this.onTimeUpdate);
      this.audio.removeEventListener('loadedmetadata', this.onLoaded);
      this.audio.removeEventListener('ended', this.onEnded);
      this.audio.src = '';
      this.audio = null;
    }
    this.loaded = false;
    this.playing = false;
    this.currentTime = 0;
    this.duration = 0;
  }
}

export const audioPlayer = new AudioPlayer();
