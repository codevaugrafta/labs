export type HistoryPhaseType = "work" | "shortBreak" | "longBreak";

export interface PomodoroSessionRecord {
  sessionId: string;
  startedAt: string;
  endedAt: string;
  phaseType: HistoryPhaseType;
  durationSeconds: number;
  taskTitle: string;
  /** True only for completed work phases (for streaks / focus minutes). */
  completedWork: boolean;
}

const CSV_HEADER =
  "session_id,started_at_iso,ended_at_iso,phase_type,duration_seconds,task_title,completed_work_boolean";

export function toCsvRow(r: PomodoroSessionRecord): string {
  const title = r.taskTitle.replaceAll('"', '""');
  return [
    r.sessionId,
    r.startedAt,
    r.endedAt,
    r.phaseType,
    String(r.durationSeconds),
    `"${title}"`,
    r.completedWork ? "true" : "false",
  ].join(",");
}

export function exportHistoryCsv(rows: PomodoroSessionRecord[]): string {
  const body = rows.map(toCsvRow).join("\n");
  return `${CSV_HEADER}\n${body}\n`;
}

/** Local calendar day key yyyy-mm-dd */
export function localDayKey(d: Date): string {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

/**
 * Days with at least one completed work pomodoro, sorted ascending (oldest first).
 */
export function streakEligibleDays(rows: PomodoroSessionRecord[]): string[] {
  const set = new Set<string>();
  for (const r of rows) {
    if (!r.completedWork || r.phaseType !== "work") continue;
    const start = new Date(r.startedAt);
    if (Number.isNaN(start.getTime())) continue;
    set.add(localDayKey(start));
  }
  return [...set].sort();
}

/**
 * Current streak length ending today (local), requiring consecutive calendar days
 * with ≥1 completed work session.
 */
export function computeStreak(rows: PomodoroSessionRecord[], now = new Date()): number {
  const days = new Set(streakEligibleDays(rows));
  if (days.size === 0) return 0;
  let count = 0;
  const cursor = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  while (days.has(localDayKey(cursor))) {
    count += 1;
    cursor.setDate(cursor.getDate() - 1);
  }
  return count;
}

export function completedWorkCountToday(
  rows: PomodoroSessionRecord[],
  now = new Date(),
): number {
  const key = localDayKey(now);
  return rows.filter(
    (r) =>
      r.completedWork &&
      r.phaseType === "work" &&
      localDayKey(new Date(r.startedAt)) === key,
  ).length;
}

export function focusedMinutesToday(
  rows: PomodoroSessionRecord[],
  now = new Date(),
): number {
  const key = localDayKey(now);
  let sec = 0;
  for (const r of rows) {
    if (!r.completedWork || r.phaseType !== "work") continue;
    if (localDayKey(new Date(r.startedAt)) !== key) continue;
    sec += r.durationSeconds;
  }
  return Math.round(sec / 60);
}

/** PRD retention: max rows and optional age — applied before persist. */
export function pruneHistory(
  rows: PomodoroSessionRecord[],
  opts: { maxRows: number; maxAgeDays: number },
  now = new Date(),
): PomodoroSessionRecord[] {
  const cutoff = now.getTime() - opts.maxAgeDays * 24 * 60 * 60 * 1000;
  const filtered = rows.filter((r) => {
    const t = new Date(r.endedAt).getTime();
    return !Number.isNaN(t) && t >= cutoff;
  });
  if (filtered.length <= opts.maxRows) return filtered;
  return filtered
    .slice()
    .sort((a, b) => a.endedAt.localeCompare(b.endedAt))
    .slice(-opts.maxRows);
}
