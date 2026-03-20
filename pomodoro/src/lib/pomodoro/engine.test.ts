import { describe, expect, it } from "vitest";
import {
  pause,
  reset,
  resume,
  skipPhase,
  start,
  tickSeconds,
} from "./engine";
import { createInitialState, DEFAULT_CONFIG } from "./types";

const short = {
  ...DEFAULT_CONFIG,
  workSeconds: 10,
  shortBreakSeconds: 3,
  longBreakSeconds: 5,
  longBreakEvery: 2,
};

describe("PomodoroEngine", () => {
  it("starts from idle into running work", () => {
    const s0 = createInitialState(short);
    expect(s0.mode).toBe("idle");
    const s = start(s0);
    expect(s.mode).toBe("running");
    expect(s.phase).toBe("work");
    expect(s.remainingSeconds).toBe(10);
  });

  it("ticks down while running", () => {
    const running = start(createInitialState(short));
    const r = tickSeconds(running, 4);
    expect(r.effects).toHaveLength(0);
    expect(r.state.remainingSeconds).toBe(6);
    expect(r.carryOverSeconds).toBe(0);
  });

  it("completes work once per tick and carries over extra seconds", () => {
    const running = start(createInitialState(short));
    const r = tickSeconds(running, 12);
    expect(r.effects).toHaveLength(1);
    expect(r.effects[0]?.phase).toBe("work");
    expect(r.state.phase).toBe("shortBreak");
    expect(r.state.remainingSeconds).toBe(3);
    expect(r.carryOverSeconds).toBe(2);
  });

  it("after two work phases schedules long break", () => {
    const cfg = { ...short, longBreakEvery: 2 };
    let s = start(createInitialState(cfg));
    s = tickSeconds(s, 10).state;
    s = resume(s);
    s = tickSeconds(s, 3).state;
    s = resume(s);
    const r = tickSeconds(s, 10);
    expect(r.state.phase).toBe("longBreak");
    expect(r.state.workStretchCount).toBe(0);
  });

  it("pause and resume preserve remaining", () => {
    let s = start(createInitialState(short));
    s = tickSeconds(s, 4).state;
    s = pause(s);
    expect(s.mode).toBe("paused");
    let r = tickSeconds(s, 999);
    expect(r.state.remainingSeconds).toBe(6);
    s = resume(r.state);
    r = tickSeconds(s, 6);
    expect(r.effects[0]?.phase).toBe("work");
  });

  it("autoStartNextPhase keeps running after transition", () => {
    const cfg = { ...short, autoStartNextPhase: true };
    const running = start(createInitialState(cfg));
    const r = tickSeconds(running, 10);
    expect(r.state.mode).toBe("running");
    expect(r.state.phase).toBe("shortBreak");
  });

  it("skip from paused still transitions", () => {
    let s = start(createInitialState(short));
    s = pause(s);
    const { state, effects } = skipPhase(s);
    expect(effects).toHaveLength(1);
    expect(state.phase).toBe("shortBreak");
  });

  it("reset returns to idle with fresh stretch", () => {
    let s = start(createInitialState(short));
    s = tickSeconds(s, 10).state;
    s = reset(s);
    expect(s.mode).toBe("idle");
    expect(s.workStretchCount).toBe(0);
  });
});
