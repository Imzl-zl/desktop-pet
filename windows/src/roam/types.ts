// Shared types and constants for the roam subsystem.

import { getCurrentWindow } from "@tauri-apps/api/window";

export type RoamMode = "stay" | "wander" | "cursor" | "climb";

export type Point = { x: number; y: number };

export type Rect = {
  left: number;
  top: number;
  right: number;
  bottom: number;
};

export type SystemWindow = {
  title: string;
  rect: Rect;
};

export type Environment = {
  /// Work area of the current monitor (excludes taskbar), in logical pixels.
  workArea: Rect;
  /// Other application windows visible on screen, in logical pixels.
  /// Empty on platforms where enumeration is unavailable.
  windows: SystemWindow[];
};

export type Config = {
  enabled: boolean;
  mode: RoamMode;
  speed: number;
};

export const ROAM_KEY = "ap_roam";
export const ROAM_MODE_KEY = "ap_roam_mode";
export const ROAM_SPEED_KEY = "ap_roam_speed";

export const WIN_W = 260;
export const WIN_H = 320;
export const MARGIN = 40;

export const IDLE_MS_MIN = 1200;
export const IDLE_MS_MAX = 3500;

export const PHYSICS_FRICTION = 0.9;
export const PHYSICS_MIN_SPEED = 15;
export const PHYSICS_GRAVITY = 1800;
export const SAMPLE_WINDOW_MS = 120;

export const TICK_MS = 30;
/// Fixed dt (seconds) used by physics integration. Derived from TICK_MS so the
/// two can never drift apart. All `vx * 0.03` style computations use this.
export const DT_SEC = TICK_MS / 1000;

/// Below this drag-release speed (px/s), no throw is applied , the pet just stays.
export const THROW_MIN_SPEED = 15;

/// Pet falls asleep after this many ms idle with no movement (Oneko-style).
export const SLEEP_AFTER_MS = 30_000;
/// Default spritesheet row for the sleep pose. Row 5 ("Failed") is unused by any
/// mood in STATE_ROW, so it's free. Override with localStorage `ap_bind_sleep`.
export const SLEEP_ROW_DEFAULT = 5;

export const VALID_MODES: RoamMode[] = ["stay", "wander", "cursor", "climb"];

/// Per-window override key. Each pet window (main, project, extra) can have
/// its own roam mode / size, stored under `ap_win_<label>_<key>`. Falls back
/// to the global key if the per-window override is absent.
// Cache the label once at module load: getCurrentWindow() allocates a new
// WebviewWindow each call, and loadConfig() runs every 30ms tick.
const WIN_LABEL: string = (() => {
  try {
    return getCurrentWindow().label;
  } catch {
    return "";
  }
})();

function winOverride(key: string): string | null {
  if (!WIN_LABEL) return null;
  return localStorage.getItem(`ap_win_${WIN_LABEL}_${key}`);
}

export function loadConfig(): Config {
  // Per-window roam mode override wins over the global setting, so individual
  // extra pets can wander / stay / follow cursor independently.
  const stored = (winOverride(ROAM_MODE_KEY) || localStorage.getItem(ROAM_MODE_KEY)) as RoamMode | null;
  const mode: RoamMode = stored && VALID_MODES.includes(stored) ? stored : "wander";
  return {
    enabled: localStorage.getItem(ROAM_KEY) !== "0",
    mode,
    speed: Math.max(1, Math.min(10, parseInt(localStorage.getItem(ROAM_SPEED_KEY) || "5", 10))),
  };
}

export function clampToBounds(pos: Point, bounds: Rect): Point {
  return {
    x: Math.max(bounds.left, Math.min(bounds.right - WIN_W, pos.x)),
    y: Math.max(bounds.top, Math.min(bounds.bottom - WIN_H, pos.y)),
  };
}

export function pxPerSec(speed: number): number {
  return 40 + speed * 45;
}

export function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}
