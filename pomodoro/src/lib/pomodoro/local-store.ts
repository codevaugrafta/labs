import { openDB, type DBSchema, type IDBPDatabase } from "idb";
import type { PomodoroConfig } from "./types";
import { DEFAULT_CONFIG } from "./types";
import type { PomodoroSessionRecord } from "./history";
import { pruneHistory } from "./history";

const DB_NAME = "pomodoro-db";
const DB_VERSION = 1;

export type ThemePreference = "light" | "dark" | "system";

export interface AppSettings {
  config: PomodoroConfig;
  theme: ThemePreference;
  soundEnabled: boolean;
  soundVolume: number;
  /** User wants browser notifications when permitted */
  notificationOptIn: boolean;
  reducedMotionOverride: boolean | null;
}

export interface PersistedTimerSnapshot {
  engine: {
    mode: string;
    phase: string;
    remainingSeconds: number;
    workStretchCount: number;
  };
  currentTaskTitle: string;
  updatedAt: string;
}

interface PomodoroDB extends DBSchema {
  meta: {
    key: string;
    value: unknown;
  };
  sessions: {
    key: string;
    value: PomodoroSessionRecord;
    indexes: { "by-ended": string };
  };
}

const DEFAULT_SETTINGS: AppSettings = {
  config: DEFAULT_CONFIG,
  theme: "dark",
  soundEnabled: true,
  soundVolume: 0.6,
  notificationOptIn: false,
  reducedMotionOverride: null,
};

export const RETENTION = { maxRows: 10_000, maxAgeDays: 365 };

let dbPromise: Promise<IDBPDatabase<PomodoroDB>> | null = null;

export function getDb(): Promise<IDBPDatabase<PomodoroDB>> {
  if (typeof indexedDB === "undefined") {
    return Promise.reject(new Error("IndexedDB unavailable"));
  }
  if (!dbPromise) {
    dbPromise = openDB<PomodoroDB>(DB_NAME, DB_VERSION, {
      upgrade(db) {
        if (!db.objectStoreNames.contains("meta")) {
          db.createObjectStore("meta");
        }
        if (!db.objectStoreNames.contains("sessions")) {
          const s = db.createObjectStore("sessions", { keyPath: "sessionId" });
          s.createIndex("by-ended", "endedAt");
        }
      },
    });
  }
  return dbPromise;
}

export async function loadSettings(): Promise<AppSettings> {
  try {
    const db = await getDb();
    const v = await db.get("meta", "settings");
    if (v && typeof v === "object") {
      return { ...DEFAULT_SETTINGS, ...(v as AppSettings) };
    }
  } catch {
    // fall through
  }
  return { ...DEFAULT_SETTINGS };
}

export async function saveSettings(settings: AppSettings): Promise<void> {
  const db = await getDb();
  await db.put("meta", settings, "settings");
}

export async function loadTimerSnapshot(): Promise<PersistedTimerSnapshot | null> {
  try {
    const db = await getDb();
    const v = await db.get("meta", "timer");
    if (v && typeof v === "object") return v as PersistedTimerSnapshot;
  } catch {
    // ignore
  }
  return null;
}

export async function saveTimerSnapshot(
  snap: PersistedTimerSnapshot,
): Promise<void> {
  const db = await getDb();
  await db.put("meta", snap, "timer");
}

export async function clearTimerSnapshot(): Promise<void> {
  const db = await getDb();
  await db.delete("meta", "timer");
}

export async function loadTasks(): Promise<string[]> {
  try {
    const db = await getDb();
    const v = await db.get("meta", "tasks");
    if (Array.isArray(v)) return v.filter((x) => typeof x === "string");
  } catch {
    // ignore
  }
  return [];
}

export async function saveTasks(tasks: string[]): Promise<void> {
  const db = await getDb();
  await db.put("meta", tasks, "tasks");
}

export async function loadSessions(): Promise<PomodoroSessionRecord[]> {
  try {
    const db = await getDb();
    return await db.getAll("sessions");
  } catch {
    return [];
  }
}

export async function appendSession(
  row: PomodoroSessionRecord,
): Promise<void> {
  const db = await getDb();
  const all = await db.getAll("sessions");
  const merged = pruneHistory([...all, row], RETENTION);
  const tx = db.transaction("sessions", "readwrite");
  await tx.store.clear();
  for (const r of merged) {
    await tx.store.put(r);
  }
  await tx.done;
}

export async function clearAllLocalData(): Promise<void> {
  try {
    const db = await getDb();
    const tx = db.transaction(["meta", "sessions"], "readwrite");
    await tx.objectStore("meta").clear();
    await tx.objectStore("sessions").clear();
    await tx.done;
  } catch {
    // ignore
  }
}
