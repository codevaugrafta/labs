export type PhaseKind = "work" | "shortBreak" | "longBreak";

export type TimerMode = "idle" | "running" | "paused";

export interface PomodoroConfig {
  workSeconds: number;
  shortBreakSeconds: number;
  longBreakSeconds: number;
  /** After this many completed work phases, next break is long. */
  longBreakEvery: number;
  autoStartNextPhase: boolean;
}

export interface PomodoroEngineState {
  mode: TimerMode;
  phase: PhaseKind;
  remainingSeconds: number;
  /** Completed work phases since last long break (0..longBreakEvery-1). */
  workStretchCount: number;
  config: PomodoroConfig;
}

export type EngineEffect = {
  type: "phaseCompleted";
  phase: PhaseKind;
  plannedDurationSeconds: number;
};

export interface TickResult {
  state: PomodoroEngineState;
  effects: EngineEffect[];
  /** Seconds not applied because only one phase transition is processed per tick. */
  carryOverSeconds: number;
}

export const DEFAULT_CONFIG: PomodoroConfig = {
  workSeconds: 25 * 60,
  shortBreakSeconds: 5 * 60,
  longBreakSeconds: 15 * 60,
  longBreakEvery: 4,
  autoStartNextPhase: false,
};

export function createInitialState(
  config: PomodoroConfig = DEFAULT_CONFIG,
): PomodoroEngineState {
  return {
    mode: "idle",
    phase: "work",
    remainingSeconds: config.workSeconds,
    workStretchCount: 0,
    config,
  };
}
