"use client";

import { useTheme } from "next-themes";
import {
  useCallback,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
  useSyncExternalStore,
} from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Separator } from "@/components/ui/separator";
import { Slider } from "@/components/ui/slider";
import { Switch } from "@/components/ui/switch";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import {
  PhaseGlyph,
  phaseLabel,
  phaseRibbonClass,
  phaseSurfaceClass,
} from "@/components/pomodoro/phase-affordances";
import { cn } from "@/lib/utils";
import { playPhaseChime } from "@/lib/pomodoro/chime";
import {
  completedWorkCountToday,
  computeStreak,
  exportHistoryCsv,
  focusedMinutesToday,
  type PomodoroSessionRecord,
} from "@/lib/pomodoro/history";
import {
  appendSession,
  clearAllLocalData,
  clearTimerSnapshot,
  loadSessions,
  loadSettings,
  loadTasks,
  loadTimerSnapshot,
  saveSettings,
  saveTasks,
  saveTimerSnapshot,
  type AppSettings,
} from "@/lib/pomodoro/local-store";
import {
  getNotificationSupport,
  shouldShowBrowserNotification,
} from "@/lib/pomodoro/notification-policy";
import { TabCoordinator } from "@/lib/pomodoro/tab-coordinator";
import {
  pause,
  reset,
  resume,
  skipPhase,
  start,
  tickSeconds,
} from "@/lib/pomodoro/engine";
import type { EngineEffect, PhaseKind, PomodoroEngineState } from "@/lib/pomodoro/types";
import { createInitialState, DEFAULT_CONFIG, type PomodoroConfig } from "@/lib/pomodoro/types";

const TASK_MAX = 200;

const emptySubscribe = () => () => {};

function useIsClient(): boolean {
  return useSyncExternalStore(
    emptySubscribe,
    () => true,
    () => false,
  );
}

const DEFAULT_APP_SETTINGS: AppSettings = {
  config: DEFAULT_CONFIG,
  theme: "dark",
  soundEnabled: true,
  soundVolume: 0.6,
  notificationOptIn: false,
  reducedMotionOverride: null,
};

function formatClock(totalSeconds: number): string {
  const s = Math.max(0, Math.floor(totalSeconds));
  const m = Math.floor(s / 60);
  const r = s % 60;
  return `${String(m).padStart(2, "0")}:${String(r).padStart(2, "0")}`;
}

function snapshotFromEngine(
  engine: PomodoroEngineState,
  task: string,
): import("@/lib/pomodoro/local-store").PersistedTimerSnapshot {
  return {
    engine: {
      mode: engine.mode,
      phase: engine.phase,
      remainingSeconds: engine.remainingSeconds,
      workStretchCount: engine.workStretchCount,
    },
    currentTaskTitle: task,
    updatedAt: new Date().toISOString(),
  };
}

function engineFromSnapshot(
  snap: import("@/lib/pomodoro/local-store").PersistedTimerSnapshot | null,
  config: PomodoroConfig,
): PomodoroEngineState {
  if (!snap?.engine) return createInitialState(config);
  const mode = snap.engine.mode as PomodoroEngineState["mode"];
  const phase = snap.engine.phase as PhaseKind;
  if (mode !== "idle" && mode !== "running" && mode !== "paused") {
    return createInitialState(config);
  }
  if (phase !== "work" && phase !== "shortBreak" && phase !== "longBreak") {
    return createInitialState(config);
  }
  return {
    mode,
    phase,
    remainingSeconds: Math.max(0, snap.engine.remainingSeconds),
    workStretchCount: Math.max(0, snap.engine.workStretchCount),
    config,
  };
}

export function PomodoroApp() {
  const isClient = useIsClient();
  if (!isClient) {
    return (
      <div className="flex min-h-[60vh] items-center justify-center text-muted-foreground">
        Loading…
      </div>
    );
  }
  return <PomodoroAppInner />;
}

function PomodoroAppInner() {
  const { setTheme } = useTheme();
  const [settings, setSettings] = useState<AppSettings>(DEFAULT_APP_SETTINGS);
  const [hydrated, setHydrated] = useState(false);
  const [engine, setEngine] = useState<PomodoroEngineState>(() =>
    createInitialState(),
  );
  const [taskTitle, setTaskTitle] = useState("");
  const [tasks, setTasks] = useState<string[]>([]);
  const [sessions, setSessions] = useState<PomodoroSessionRecord[]>([]);
  const [announcement, setAnnouncement] = useState("");
  const [foreignLease, setForeignLease] = useState(false);
  const [resetOpen, setResetOpen] = useState(false);
  const [forgetOpen, setForgetOpen] = useState(false);

  const engineRef = useRef(engine);
  const settingsRef = useRef(settings);
  const taskRef = useRef(taskTitle);
  const phaseStartRef = useRef<number>(0);
  const lastTickRef = useRef<number | null>(null);
  const coordRef = useRef<TabCoordinator | null>(null);
  const prevPhaseRef = useRef<PhaseKind | null>(null);

  const coordinator = useMemo(() => {
    if (typeof window === "undefined") return null;
    return TabCoordinator.create();
  }, []);

  useEffect(() => {
    coordRef.current = coordinator;
    return () => {
      coordinator?.release();
      coordinator?.close();
    };
  }, [coordinator]);

  useEffect(() => {
    phaseStartRef.current = Date.now();
  }, []);

  useLayoutEffect(() => {
    engineRef.current = engine;
    settingsRef.current = settings;
    taskRef.current = taskTitle;
  }, [engine, settings, taskTitle]);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const [rs, rSnap, rTasks, rSessions] = await Promise.allSettled([
          loadSettings(),
          loadTimerSnapshot(),
          loadTasks(),
          loadSessions(),
        ]);
        if (cancelled) return;
        const s =
          rs.status === "fulfilled" ? rs.value : DEFAULT_APP_SETTINGS;
        const snap = rSnap.status === "fulfilled" ? rSnap.value : null;
        const t = rTasks.status === "fulfilled" ? rTasks.value : [];
        const h = rSessions.status === "fulfilled" ? rSessions.value : [];
        setSettings(s);
        setEngine(engineFromSnapshot(snap, s.config));
        setTasks(t);
        setSessions(h);
        if (snap?.currentTaskTitle) {
          setTaskTitle(snap.currentTaskTitle.slice(0, TASK_MAX));
        }
        phaseStartRef.current = Date.now();
        setHydrated(true);
      } catch {
        if (!cancelled) {
          setHydrated(true);
        }
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    setTheme(settings.theme === "system" ? "system" : settings.theme);
  }, [settings, setTheme]);

  useEffect(() => {
    const reduce =
      settings.reducedMotionOverride === true ||
      (settings.reducedMotionOverride === null &&
        typeof window !== "undefined" &&
        window.matchMedia("(prefers-reduced-motion: reduce)").matches);
    document.documentElement.dataset.reduceMotion = reduce ? "on" : "off";
  }, [settings.reducedMotionOverride]);

  useEffect(() => {
    if (typeof window === "undefined") return;
    if (settings.reducedMotionOverride !== null) return;
    const mq = window.matchMedia("(prefers-reduced-motion: reduce)");
    const fn = () => {
      const reduce =
        settingsRef.current.reducedMotionOverride === true ||
        (settingsRef.current.reducedMotionOverride === null && mq.matches);
      document.documentElement.dataset.reduceMotion = reduce ? "on" : "off";
    };
    mq.addEventListener("change", fn);
    return () => mq.removeEventListener("change", fn);
  }, [settings.reducedMotionOverride]);

  const persistEngine = useCallback(
    async (next: PomodoroEngineState, task: string) => {
      try {
        await saveTimerSnapshot(snapshotFromEngine(next, task));
      } catch {
        // ignore persistence errors
      }
    },
    [],
  );

  useEffect(() => {
    if (!hydrated) return;
    void persistEngine(engine, taskTitle);
  }, [engine, taskTitle, hydrated, persistEngine]);

  const handleEffects = useCallback(
    async (effects: EngineEffect[]) => {
      const s = settingsRef.current;
      for (const e of effects) {
        const ended = new Date().toISOString();
        const started = new Date(phaseStartRef.current).toISOString();
        const row: PomodoroSessionRecord = {
          sessionId:
            typeof crypto !== "undefined" && crypto.randomUUID
              ? crypto.randomUUID()
              : `sess-${Date.now()}`,
          startedAt: started,
          endedAt: ended,
          phaseType: e.phase,
          durationSeconds: e.plannedDurationSeconds,
          taskTitle: taskRef.current.slice(0, TASK_MAX),
          completedWork: e.phase === "work",
        };
        try {
          await appendSession(row);
          const all = await loadSessions();
          setSessions(all);
        } catch {
          // quota / idb
        }
        const label = phaseLabel(e.phase);
        setAnnouncement(`${label} complete`);
        if (s.soundEnabled) {
          void playPhaseChime(s.soundVolume);
        }
        const sup = getNotificationSupport();
        if (
          shouldShowBrowserNotification(sup, s.notificationOptIn) &&
          typeof document !== "undefined" &&
          document.visibilityState === "hidden"
        ) {
          try {
            new Notification("Pomodoro", {
              body: `${label} finished`,
            });
          } catch {
            // ignore
          }
        }
        phaseStartRef.current = Date.now();
      }
    },
    [],
  );

  useEffect(() => {
    const onVis = () => {
      if (document.visibilityState === "visible") {
        lastTickRef.current = null;
      }
    };
    document.addEventListener("visibilitychange", onVis);
    return () => document.removeEventListener("visibilitychange", onVis);
  }, []);

  useEffect(() => {
    const id = window.setInterval(() => {
      const coord = coordRef.current;
      if (!coord) return;
      const acquired = coord.tryAcquireLease();
      if (!acquired) {
        setForeignLease(true);
        return;
      }
      setForeignLease(false);
      coord.heartbeat();

      const e = engineRef.current;
      if (e.mode !== "running") {
        lastTickRef.current = null;
        return;
      }

      const now = performance.now();
      if (lastTickRef.current === null) lastTickRef.current = now;
      let delta = (now - lastTickRef.current) / 1000;
      lastTickRef.current = now;
      delta = Math.min(delta, 120);

      setEngine((prev) => {
        if (prev.mode !== "running") return prev;
        let state = prev;
        let carry = delta;
        const effects: EngineEffect[] = [];
        let guard = 0;
        while (carry > 0 && state.mode === "running" && guard < 24) {
          guard += 1;
          const r = tickSeconds(state, carry);
          effects.push(...r.effects);
          state = r.state;
          carry = r.carryOverSeconds;
          if (r.effects.length === 0) break;
        }
        if (effects.length > 0) {
          void handleEffects(effects);
        }
        return state;
      });
    }, 250);
    return () => window.clearInterval(id);
  }, [handleEffects]);

  useEffect(() => {
    const p = engine.phase;
    if (prevPhaseRef.current !== p) {
      prevPhaseRef.current = p;
      phaseStartRef.current = Date.now();
      queueMicrotask(() => {
        setAnnouncement(`${phaseLabel(p)} phase`);
      });
    }
  }, [engine.phase]);

  useEffect(() => {
    const onKey = (ev: KeyboardEvent) => {
      const tag = (ev.target as HTMLElement)?.tagName;
      if (tag === "INPUT" || tag === "TEXTAREA") return;
      if (foreignLease) return;
      if (ev.code === "Space") {
        ev.preventDefault();
        setEngine((prev) => {
          if (prev.mode === "running") return pause(prev);
          if (prev.mode === "paused") return resume(prev);
          return start(prev);
        });
      }
      if (ev.key === "s" || ev.key === "S") {
        ev.preventDefault();
        setEngine((prev) => {
          const { state, effects } = skipPhase(prev);
          if (effects.length) void handleEffects(effects);
          return state;
        });
      }
      if (ev.key === "r" || ev.key === "R") {
        ev.preventDefault();
        setResetOpen(true);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [foreignLease, handleEffects]);

  const updateSettings = async (next: AppSettings) => {
    setSettings(next);
    setEngine((prev) => {
      const merged = { ...prev, config: next.config };
      if (merged.mode === "idle" && merged.phase === "work") {
        return {
          ...merged,
          remainingSeconds: next.config.workSeconds,
        };
      }
      return merged;
    });
    try {
      await saveSettings(next);
    } catch {
      // ignore
    }
  };

  const takeOver = () => {
    coordRef.current?.takeOver();
    setForeignLease(false);
  };

  const exportCsv = () => {
    const csv = exportHistoryCsv(sessions);
    const blob = new Blob([csv], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = "pomodoro-history.csv";
    a.click();
    URL.revokeObjectURL(url);
  };

  const streak = computeStreak(sessions);
  const todayCount = completedWorkCountToday(sessions);
  const todayMin = focusedMinutesToday(sessions);

  return (
    <div className="mx-auto flex w-full max-w-3xl flex-col gap-6 px-4 py-10">
      <header className="space-y-1 text-center">
        <h1 className="text-3xl font-semibold tracking-tight">Pomodoro</h1>
        <p className="text-sm text-muted-foreground">
          Calm focus, keyboard-first, local-first.
        </p>
      </header>

      <div
        role="status"
        aria-live="polite"
        aria-atomic="true"
        className="sr-only"
      >
        {announcement}
      </div>

      {foreignLease ? (
        <Card className="border-amber-500/40 bg-amber-500/5">
          <CardHeader>
            <CardTitle className="text-base">Timer active in another tab</CardTitle>
            <CardDescription>
              Only one tab drives the clock. Take over here or close the other
              tab.
            </CardDescription>
          </CardHeader>
          <CardContent>
            <Button type="button" onClick={takeOver}>
              Take over here
            </Button>
          </CardContent>
        </Card>
      ) : null}

      <Tabs defaultValue="timer" className="w-full">
        <TabsList className="grid w-full grid-cols-4">
          <TabsTrigger value="timer">Timer</TabsTrigger>
          <TabsTrigger value="today">Today</TabsTrigger>
          <TabsTrigger value="history">History</TabsTrigger>
          <TabsTrigger value="settings">Settings</TabsTrigger>
        </TabsList>

        <TabsContent value="timer" className="mt-6 space-y-6">
          <Card
            data-phase={engine.phase}
            className={cn(
              "pomo-phase-surface overflow-hidden border-border/80",
              phaseSurfaceClass(engine.phase),
            )}
          >
            <div
              className={cn(
                "flex flex-col gap-3 px-4 py-4 sm:flex-row sm:items-center sm:justify-between sm:px-6",
                phaseRibbonClass(engine.phase),
              )}
              data-testid="pomo-phase-ribbon"
            >
              <div className="flex items-center gap-4">
                <PhaseGlyph
                  phase={engine.phase}
                  className="size-11 sm:size-14 text-foreground"
                />
                <div className="min-w-0">
                  <p className="text-xl font-semibold tracking-tight sm:text-2xl">
                    {phaseLabel(engine.phase)}
                  </p>
                  <p className="text-sm text-muted-foreground">
                    {engine.mode === "idle"
                      ? "Idle — start when ready"
                      : engine.mode === "paused"
                        ? "Paused"
                        : "Timer running"}
                  </p>
                </div>
              </div>
              <Badge
                variant="outline"
                className="w-fit shrink-0 border-border/80 text-xs font-normal sm:self-center"
              >
                Streak {streak}d · {todayCount} today · {todayMin}m
              </Badge>
            </div>
            <CardHeader className="space-y-3 pt-6 pb-2">
              <CardTitle className="font-mono text-6xl tabular-nums tracking-tight sm:text-7xl md:text-8xl">
                {formatClock(engine.remainingSeconds)}
              </CardTitle>
              <CardDescription className="text-base">
                {engine.mode === "idle"
                  ? "Press Start or Space to begin a focus block."
                  : engine.mode === "paused"
                    ? "Space to resume, S to skip, R to reset."
                    : "Space to pause · keyboard shortcuts in Settings."}
              </CardDescription>
            </CardHeader>
            <CardContent className="flex flex-wrap gap-2 pb-6">
              <Button
                type="button"
                disabled={foreignLease}
                onClick={() =>
                  setEngine((prev) => {
                    if (prev.mode === "running") return pause(prev);
                    if (prev.mode === "paused") return resume(prev);
                    return start(prev);
                  })
                }
              >
                {engine.mode === "running"
                  ? "Pause"
                  : engine.mode === "paused"
                    ? "Resume"
                    : "Start"}
              </Button>
              <Button
                type="button"
                variant="secondary"
                disabled={foreignLease || engine.mode === "idle"}
                onClick={() =>
                  setEngine((prev) => {
                    const { state, effects } = skipPhase(prev);
                    if (effects.length) void handleEffects(effects);
                    return state;
                  })
                }
              >
                Skip phase
              </Button>
              <Button
                type="button"
                variant="outline"
                disabled={foreignLease}
                onClick={() => setResetOpen(true)}
              >
                Reset
              </Button>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle className="text-base">Current task</CardTitle>
              <CardDescription>
                Optional label for this focus block (max {TASK_MAX} chars).
              </CardDescription>
            </CardHeader>
            <CardContent className="space-y-2">
              <Input
                value={taskTitle}
                maxLength={TASK_MAX}
                onChange={(e) =>
                  setTaskTitle(e.target.value.slice(0, TASK_MAX))
                }
                placeholder="e.g. Draft PRD section"
              />
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="today" className="mt-6 space-y-4">
          <Card>
            <CardHeader>
              <CardTitle className="text-base">Today queue</CardTitle>
              <CardDescription>
                Add tasks below; click a row to copy it into the timer’s current
                task.
              </CardDescription>
            </CardHeader>
            <CardContent className="space-y-3">
              <div className="flex gap-2">
                <Input
                  id="new-task"
                  placeholder="Type a task, then Enter"
                  aria-label="New task for today queue"
                  onKeyDown={async (e) => {
                    if (e.key !== "Enter") return;
                    const v = e.currentTarget.value.trim().slice(0, TASK_MAX);
                    if (!v) return;
                    const next = [...tasks, v];
                    setTasks(next);
                    e.currentTarget.value = "";
                    try {
                      await saveTasks(next);
                    } catch {
                      // ignore
                    }
                  }}
                />
              </div>
              <ScrollArea className="h-48 rounded-md border">
                <ul className="divide-y p-2">
                  {tasks.length === 0 ? (
                    <li className="p-3 text-sm text-muted-foreground">
                      Your queue is empty. Type a task in the field above and
                      press Enter to add the first item.
                    </li>
                  ) : (
                    tasks.map((t) => {
                      const active = t === taskTitle.trim();
                      return (
                        <li key={t}>
                          <button
                            type="button"
                            className={cn(
                              "w-full rounded-md px-2 py-2 text-left text-sm hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background",
                              active &&
                                "bg-accent/45 ring-1 ring-ring/50 ring-inset",
                            )}
                            title={
                              active
                                ? "Matches the timer’s current task label"
                                : undefined
                            }
                            onClick={() => setTaskTitle(t)}
                          >
                            {t}
                          </button>
                        </li>
                      );
                    })
                  )}
                </ul>
              </ScrollArea>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="history" className="mt-6 space-y-4">
          <div className="flex flex-wrap gap-2">
            <Button
              type="button"
              variant="secondary"
              disabled={sessions.length === 0}
              title={
                sessions.length === 0
                  ? "Complete a phase to build history before exporting"
                  : undefined
              }
              onClick={exportCsv}
            >
              Export CSV
            </Button>
          </div>
          <ScrollArea className="h-72 rounded-md border">
            <ul className="divide-y p-2 text-sm">
              {sessions.length === 0 ? (
                <li className="p-3 text-muted-foreground">
                  No completed sessions yet. Finish a focus or break phase on
                  the Timer tab, then return here. Export becomes available once
                  there is at least one row.
                </li>
              ) : (
                [...sessions]
                  .sort((a, b) => b.endedAt.localeCompare(a.endedAt))
                  .map((r) => (
                    <li key={r.sessionId} className="py-2">
                      <div className="font-medium">{r.phaseType}</div>
                      <div className="text-muted-foreground text-xs">
                        {new Date(r.startedAt).toLocaleString()} ·{" "}
                        {r.durationSeconds}s
                        {r.taskTitle ? ` · ${r.taskTitle}` : ""}
                      </div>
                    </li>
                  ))
              )}
            </ul>
          </ScrollArea>
        </TabsContent>

        <TabsContent value="settings" className="mt-6 space-y-6">
          <Card>
            <CardHeader>
              <CardTitle className="text-base">Durations</CardTitle>
            </CardHeader>
            <CardContent className="grid gap-4 sm:grid-cols-2">
              <div className="space-y-2">
                <Label>Work (minutes)</Label>
                <Input
                  type="number"
                  min={1}
                  value={Math.round(settings.config.workSeconds / 60)}
                  onChange={(e) => {
                    const m = Number(e.target.value);
                    if (!Number.isFinite(m) || m < 1) return;
                    void updateSettings({
                      ...settings,
                      config: { ...settings.config, workSeconds: m * 60 },
                    });
                  }}
                />
              </div>
              <div className="space-y-2">
                <Label>Short break (minutes)</Label>
                <Input
                  type="number"
                  min={1}
                  value={Math.round(settings.config.shortBreakSeconds / 60)}
                  onChange={(e) => {
                    const m = Number(e.target.value);
                    if (!Number.isFinite(m) || m < 1) return;
                    void updateSettings({
                      ...settings,
                      config: {
                        ...settings.config,
                        shortBreakSeconds: m * 60,
                      },
                    });
                  }}
                />
              </div>
              <div className="space-y-2">
                <Label>Long break (minutes)</Label>
                <Input
                  type="number"
                  min={1}
                  value={Math.round(settings.config.longBreakSeconds / 60)}
                  onChange={(e) => {
                    const m = Number(e.target.value);
                    if (!Number.isFinite(m) || m < 1) return;
                    void updateSettings({
                      ...settings,
                      config: {
                        ...settings.config,
                        longBreakSeconds: m * 60,
                      },
                    });
                  }}
                />
              </div>
              <div className="space-y-2">
                <Label>Long break every N work sessions</Label>
                <Input
                  type="number"
                  min={1}
                  value={settings.config.longBreakEvery}
                  onChange={(e) => {
                    const n = Number(e.target.value);
                    if (!Number.isFinite(n) || n < 1) return;
                    void updateSettings({
                      ...settings,
                      config: { ...settings.config, longBreakEvery: n },
                    });
                  }}
                />
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle className="text-base">Behavior</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="flex items-center justify-between gap-4">
                <div>
                  <div className="font-medium">Auto-start next phase</div>
                  <p className="text-muted-foreground text-sm">
                    When off, you confirm each new phase with Start.
                  </p>
                </div>
                <Switch
                  checked={settings.config.autoStartNextPhase}
                  onCheckedChange={(v) =>
                    void updateSettings({
                      ...settings,
                      config: { ...settings.config, autoStartNextPhase: v },
                    })
                  }
                />
              </div>
              <Separator />
              <div className="flex items-center justify-between gap-4">
                <div>
                  <div className="font-medium">Sound</div>
                  <p className="text-muted-foreground text-sm">
                    Short chime when a phase ends.
                  </p>
                </div>
                <Switch
                  checked={settings.soundEnabled}
                  onCheckedChange={(v) =>
                    void updateSettings({ ...settings, soundEnabled: v })
                  }
                />
              </div>
              {settings.soundEnabled ? (
                <div className="space-y-2">
                  <Label>Volume</Label>
                  <Slider
                    value={[settings.soundVolume]}
                    min={0}
                    max={1}
                    step={0.05}
                    onValueChange={([v]) =>
                      void updateSettings({
                        ...settings,
                        soundVolume: v ?? 0,
                      })
                    }
                  />
                </div>
              ) : null}
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle className="text-base">Notifications</CardTitle>
              <CardDescription>
                Optional. In-tab feedback always works without permission.
              </CardDescription>
            </CardHeader>
            <CardContent className="space-y-3">
              <div className="flex items-center justify-between gap-4">
                <span className="text-sm">Enable browser notifications</span>
                <Switch
                  checked={settings.notificationOptIn}
                  onCheckedChange={(v) =>
                    void updateSettings({
                      ...settings,
                      notificationOptIn: v,
                    })
                  }
                />
              </div>
              <Button
                type="button"
                variant="outline"
                size="sm"
                onClick={async () => {
                  if (typeof Notification === "undefined") return;
                  await Notification.requestPermission();
                }}
              >
                Request permission
              </Button>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle className="text-base">Appearance</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="space-y-2">
                <Label>Theme</Label>
                <div className="flex flex-wrap gap-2">
                  {(["light", "dark", "system"] as const).map((t) => (
                    <Button
                      key={t}
                      type="button"
                      size="sm"
                      variant={settings.theme === t ? "default" : "outline"}
                      onClick={() =>
                        void updateSettings({ ...settings, theme: t })
                      }
                    >
                      {t}
                    </Button>
                  ))}
                </div>
              </div>
              <div className="space-y-2">
                <Label>Motion</Label>
                <p className="text-muted-foreground text-xs">
                  System follows OS preference; Reduce limits transitions.
                </p>
                <div className="flex flex-wrap gap-2">
                  <Button
                    type="button"
                    size="sm"
                    variant={
                      settings.reducedMotionOverride === null
                        ? "default"
                        : "outline"
                    }
                    onClick={() =>
                      void updateSettings({
                        ...settings,
                        reducedMotionOverride: null,
                      })
                    }
                  >
                    System
                  </Button>
                  <Button
                    type="button"
                    size="sm"
                    variant={
                      settings.reducedMotionOverride === true
                        ? "default"
                        : "outline"
                    }
                    onClick={() =>
                      void updateSettings({
                        ...settings,
                        reducedMotionOverride: true,
                      })
                    }
                  >
                    Reduce
                  </Button>
                  <Button
                    type="button"
                    size="sm"
                    variant={
                      settings.reducedMotionOverride === false
                        ? "default"
                        : "outline"
                    }
                    onClick={() =>
                      void updateSettings({
                        ...settings,
                        reducedMotionOverride: false,
                      })
                    }
                  >
                    Full
                  </Button>
                </div>
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle className="text-base">Keyboard</CardTitle>
              <CardDescription>
                Timer tab — shortcuts are off while focus is in a text field, or
                when the clock runs in another tab (take over first).
              </CardDescription>
            </CardHeader>
            <CardContent>
              <table
                className="w-full border-collapse text-sm"
                aria-label="Timer keyboard shortcuts"
              >
                <thead>
                  <tr className="border-b text-left text-muted-foreground">
                    <th scope="col" className="py-2 pr-4 font-medium">
                      Key
                    </th>
                    <th scope="col" className="py-2 font-medium">
                      Action
                    </th>
                  </tr>
                </thead>
                <tbody>
                  <tr className="border-b border-border/60">
                    <td className="py-2 pr-4 font-mono text-xs">Space</td>
                    <td className="py-2">Start, pause, or resume</td>
                  </tr>
                  <tr className="border-b border-border/60">
                    <td className="py-2 pr-4 font-mono text-xs">S</td>
                    <td className="py-2">Skip to the next phase</td>
                  </tr>
                  <tr>
                    <td className="py-2 pr-4 font-mono text-xs">R</td>
                    <td className="py-2">Open reset confirmation</td>
                  </tr>
                </tbody>
              </table>
            </CardContent>
          </Card>

          <Card className="border-destructive/40">
            <CardHeader>
              <CardTitle className="text-base text-destructive">
                Danger zone
              </CardTitle>
            </CardHeader>
            <CardContent className="flex flex-wrap gap-2">
              <Button
                type="button"
                variant="destructive"
                onClick={() => setForgetOpen(true)}
              >
                Forget this device
              </Button>
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>

      <Dialog open={resetOpen} onOpenChange={setResetOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Reset session?</DialogTitle>
            <DialogDescription>
              Stops the timer and returns to idle. History is kept.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => setResetOpen(false)}>
              Cancel
            </Button>
            <Button
              type="button"
              onClick={() => {
                setEngine((prev) => reset(prev));
                void clearTimerSnapshot();
                setResetOpen(false);
              }}
            >
              Reset
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={forgetOpen} onOpenChange={setForgetOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Forget this device?</DialogTitle>
            <DialogDescription>
              Clears local tasks, timer state, settings, and history in this
              browser.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => setForgetOpen(false)}>
              Cancel
            </Button>
            <Button
              type="button"
              variant="destructive"
              onClick={async () => {
                await clearAllLocalData();
                setTasks([]);
                setSessions([]);
                setTaskTitle("");
                setEngine(createInitialState(DEFAULT_CONFIG));
                setSettings({ ...DEFAULT_APP_SETTINGS });
                setForgetOpen(false);
              }}
            >
              Erase local data
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
