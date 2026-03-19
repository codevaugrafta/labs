export type WordTimestamp = {
  word: string;
  start: number;
  end: number;
  sentenceIndex: number;
};

export type SentenceBoundary = {
  index: number;
  startWordIndex: number;
  endWordIndex: number;
  start: number;
  end: number;
  speaker?: string;
};

export type LoopMode = 'off' | 'sentence' | 'paragraph' | 'ab';

export type LoopState = {
  mode: LoopMode;
  abStart?: number;
  abEnd?: number;
};

export type PlaybackSpeed = 0.5 | 0.75 | 1.0 | 1.25 | 1.5 | 2.0;

export type Project = {
  id: string;
  title: string;
  text: string;
  timestamps: WordTimestamp[];
  sentences: SentenceBoundary[];
  audioPath: string;
  language: string;
  createdAt: string;
  updatedAt: string;
};

export type TTSProvider = 'elevenlabs' | 'gemini' | 'inworld';

export type Settings = {
  apiKeys: Record<TTSProvider, string>;
  defaultProvider: TTSProvider;
  defaultVoice: Record<TTSProvider, string>;
  theme: 'dark' | 'light' | 'system';
};
