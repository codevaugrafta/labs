import type {
  EngineEffect,
  PhaseKind,
  PomodoroConfig,
  PomodoroEngineState,
  TickResult,
} from "./types";
import { createInitialState } from "./types";

function durationForPhase(
  phase: PhaseKind,
  config: PomodoroConfig,
): number {
  switch (phase) {
    case "work":
      return config.workSeconds;
    case "shortBreak":
      return config.shortBreakSeconds;
    case "longBreak":
      return config.longBreakSeconds;
    default: {
      const _exhaustive: never = phase;
      return _exhaustive;
    }
  }
}

function nextPhaseAfterCompletion(
  state: PomodoroEngineState,
): { phase: PhaseKind; workStretchCount: number } {
  const { config, phase, workStretchCount } = state;
  if (phase === "work") {
    const nextStretch = workStretchCount + 1;
    if (nextStretch >= config.longBreakEvery) {
      return { phase: "longBreak", workStretchCount: 0 };
    }
    return { phase: "shortBreak", workStretchCount: nextStretch };
  }
  if (phase === "shortBreak" || phase === "longBreak") {
    return { phase: "work", workStretchCount };
  }
  const _e: never = phase;
  return _e;
}

function applyPhaseTransition(
  state: PomodoroEngineState,
): { state: PomodoroEngineState; effects: EngineEffect[] } {
  const planned = durationForPhase(state.phase, state.config);
  const effects: EngineEffect[] = [
    {
      type: "phaseCompleted",
      phase: state.phase,
      plannedDurationSeconds: planned,
    },
  ];
  const { phase: nextPhase, workStretchCount } = nextPhaseAfterCompletion(state);
  const nextDuration = durationForPhase(nextPhase, state.config);
  const nextMode: PomodoroEngineState["mode"] = state.config.autoStartNextPhase
    ? "running"
    : "paused";
  return {
    state: {
      ...state,
      mode: nextMode,
      phase: nextPhase,
      remainingSeconds: nextDuration,
      workStretchCount,
    },
    effects,
  };
}

export function start(state: PomodoroEngineState): PomodoroEngineState {
  if (state.mode === "running") return state;
  if (state.mode === "idle") {
    return {
      ...state,
      mode: "running",
      phase: "work",
      remainingSeconds: durationForPhase("work", state.config),
    };
  }
  return { ...state, mode: "running" };
}

export function pause(state: PomodoroEngineState): PomodoroEngineState {
  if (state.mode !== "running") return state;
  return { ...state, mode: "paused" };
}

export function resume(state: PomodoroEngineState): PomodoroEngineState {
  if (state.mode !== "paused") return state;
  return { ...state, mode: "running" };
}

export function skipPhase(
  state: PomodoroEngineState,
): { state: PomodoroEngineState; effects: EngineEffect[] } {
  if (state.mode === "idle") {
    return { state, effects: [] };
  }
  return applyPhaseTransition(state);
}

export function reset(
  state: PomodoroEngineState,
): PomodoroEngineState {
  return createInitialState(state.config);
}

export function setConfig(
  state: PomodoroEngineState,
  config: PomodoroConfig,
): PomodoroEngineState {
  const next = { ...state, config };
  if (state.mode === "idle") {
    return {
      ...next,
      remainingSeconds: durationForPhase("work", config),
      workStretchCount: 0,
      phase: "work",
    };
  }
  return next;
}

/**
 * Advances the running timer by `deltaSeconds`, completing at most **one** phase
 * so callers can implement “max one transition per wake” by looping with carry-over.
 */
export function tickSeconds(
  state: PomodoroEngineState,
  deltaSeconds: number,
): TickResult {
  if (deltaSeconds <= 0) {
    return { state, effects: [], carryOverSeconds: 0 };
  }
  if (state.mode !== "running") {
    return { state, effects: [], carryOverSeconds: deltaSeconds };
  }
  const nextRemaining = state.remainingSeconds - deltaSeconds;
  if (nextRemaining > 0) {
    return {
      state: { ...state, remainingSeconds: nextRemaining },
      effects: [],
      carryOverSeconds: 0,
    };
  }
  const carryOverSeconds = -nextRemaining;
  const { state: transitioned, effects } = applyPhaseTransition(state);
  return { state: transitioned, effects, carryOverSeconds };
}
