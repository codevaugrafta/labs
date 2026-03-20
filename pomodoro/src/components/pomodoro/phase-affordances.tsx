import { cn } from "@/lib/utils";
import type { PhaseKind } from "@/lib/pomodoro/types";
import { Armchair, Briefcase, Coffee } from "lucide-react";

export function phaseLabel(p: PhaseKind): string {
  switch (p) {
    case "work":
      return "Focus";
    case "shortBreak":
      return "Short break";
    case "longBreak":
      return "Long break";
    default: {
      const _e: never = p;
      return _e;
    }
  }
}

/** Outer card: left rail + optional shadow (stacked with ribbon for obvious phase changes). */
export function phaseSurfaceClass(phase: PhaseKind): string {
  switch (phase) {
    case "work":
      return "border-l-[6px] border-l-solid border-l-primary shadow-md";
    case "shortBreak":
      return "border-l-[6px] border-l-dashed border-l-muted-foreground shadow-sm";
    case "longBreak":
      return "border-l-[10px] border-l-solid border-l-muted-foreground/80 shadow-sm";
    default: {
      const _e: never = phase;
      return _e;
    }
  }
}

/** Full-width strip: layout + non–hue-only cues (pattern, weight, label, icon). */
export function phaseRibbonClass(phase: PhaseKind): string {
  switch (phase) {
    case "work":
      return "border-b-2 border-b-solid border-b-primary bg-primary/12";
    case "shortBreak":
      return "border-b-2 border-b-dashed border-b-muted-foreground bg-muted/35";
    case "longBreak":
      return "border-b-4 border-b-solid border-b-muted-foreground bg-muted/55";
    default: {
      const _e: never = phase;
      return _e;
    }
  }
}

export function PhaseGlyph({
  phase,
  className,
}: {
  phase: PhaseKind;
  className?: string;
}) {
  const icon = "size-5 shrink-0 text-foreground/80";
  switch (phase) {
    case "work":
      return <Briefcase aria-hidden className={cn(icon, className)} />;
    case "shortBreak":
      return <Coffee aria-hidden className={cn(icon, className)} />;
    case "longBreak":
      return <Armchair aria-hidden className={cn(icon, className)} />;
    default: {
      const _e: never = phase;
      return _e;
    }
  }
}
