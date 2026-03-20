import { describe, expect, it } from "vitest";
import {
  computeStreak,
  exportHistoryCsv,
  focusedMinutesToday,
  localDayKey,
  pruneHistory,
  type PomodoroSessionRecord,
} from "./history";

function row(partial: Partial<PomodoroSessionRecord>): PomodoroSessionRecord {
  return {
    sessionId: "s1",
    startedAt: "2026-03-20T10:00:00.000Z",
    endedAt: "2026-03-20T10:25:00.000Z",
    phaseType: "work",
    durationSeconds: 1500,
    taskTitle: "a",
    completedWork: true,
    ...partial,
  };
}

describe("history", () => {
  it("exports CSV with header and frozen columns", () => {
    const csv = exportHistoryCsv([
      row({
        sessionId: "id-1",
        taskTitle: 'say "hi"',
        completedWork: true,
      }),
    ]);
    expect(csv).toContain("session_id,started_at_iso");
    expect(csv).toContain('"say ""hi"""');
  });

  it("computes streak for consecutive local days", () => {
    const now = new Date("2026-03-22T12:00:00");
    const rows: PomodoroSessionRecord[] = [
      row({
        startedAt: "2026-03-20T08:00:00",
        endedAt: "2026-03-20T08:25:00",
        completedWork: true,
      }),
      row({
        startedAt: "2026-03-21T09:00:00",
        endedAt: "2026-03-21T09:25:00",
        completedWork: true,
      }),
      row({
        startedAt: "2026-03-22T07:00:00",
        endedAt: "2026-03-22T07:25:00",
        completedWork: true,
      }),
    ];
    expect(computeStreak(rows, now)).toBe(3);
  });

  it("focused minutes today sums work durations", () => {
    const now = new Date("2026-03-20T15:00:00");
    const rows = [
      row({
        durationSeconds: 600,
        startedAt: "2026-03-20T10:00:00",
        endedAt: "2026-03-20T10:10:00",
      }),
      row({
        durationSeconds: 300,
        startedAt: "2026-03-20T11:00:00",
        endedAt: "2026-03-20T11:05:00",
      }),
    ];
    expect(focusedMinutesToday(rows, now)).toBe(15);
  });

  it("pruneHistory respects maxRows", () => {
    const many = Array.from({ length: 5 }, (_, i) =>
      row({
        sessionId: `x${i}`,
        endedAt: new Date(2026, 2, 20, i).toISOString(),
      }),
    );
    const p = pruneHistory(many, { maxRows: 3, maxAgeDays: 365 });
    expect(p.length).toBe(3);
  });

  it("localDayKey is stable", () => {
    expect(localDayKey(new Date("2026-01-05T23:00:00"))).toMatch(/^\d{4}-\d{2}-\d{2}$/);
  });
});
