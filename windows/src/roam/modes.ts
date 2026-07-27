// Movement strategies. Each mode is a pure function: given the current
// position and environment, return the next position (and animate the pet).
// The engine drives the tick loop; modes stay stateless where possible.

import { cursorPosition } from "@tauri-apps/api/window";
import type { Pet } from "../pet";
import type { Environment, Point, Rect, RoamMode } from "./types";
import {
  DT_SEC,
  IDLE_MS_MAX,
  IDLE_MS_MIN,
  MARGIN,
  WIN_H,
  WIN_W,
  clampToBounds,
  loadConfig,
  pxPerSec,
  sleep,
} from "./types";

const ROW_RIGHT = 1;
const ROW_LEFT = 2;

export interface ModeContext {
  env: Environment;
  pos: Point;
  pet: Pet | null;
  stop: () => boolean;
}

/// Dispatches to the active mode and returns the next position (or the
/// unchanged position if the mode didn't move). Each mode handles its own
/// animation row; if no movement happens, the caller clears the row.
export async function runMode(mode: RoamMode, ctx: ModeContext): Promise<Point> {
  switch (mode) {
    case "stay": return ctx.pos;
    case "cursor": return followCursor(ctx);
    case "climb": return climb(ctx);
    case "wander":
    default: return wander(ctx);
  }
}

/// Chase the mouse cursor. Stops beside it so it doesn't cover the pointer.
async function followCursor(ctx: ModeContext): Promise<Point> {
  const { env, pos, pet } = ctx;
  try {
    const sf = (await import("@tauri-apps/api/window")).getCurrentWindow();
    const factor = await sf.scaleFactor();
    const cur = await cursorPosition();
    const target = {
      x: cur.x / factor - WIN_W / 2,
      y: cur.y / factor - WIN_H + 20,
    };
    return moveToward(target, pos, env.workArea, pet);
  } catch {
    return pos;
  }
}

/// Random walk within the work area. Picks a target, walks to it, idles,
/// then picks another. Returns after each step so the engine stays responsive.
async function wander(ctx: ModeContext): Promise<Point> {
  const { env, pos, pet, stop } = ctx;
  const target = randomTarget(env.workArea);

  while (!stop()) {
    if (loadConfig().mode !== "wander") return pos;
    const dx = target.x - pos.x;
    const dy = target.y - pos.y;
    const dist = Math.hypot(dx, dy);

    if (dist < 6) {
      pet?.clearRow();
      await sleep(IDLE_MS_MIN + Math.random() * (IDLE_MS_MAX - IDLE_MS_MIN));
      return pos;
    }
    return moveToward(target, pos, env.workArea, pet);
  }
  return pos;
}

/// Climb along the top edges of visible application windows, like Shimeji.
/// Walks horizontally until reaching the edge of a window, then either drops
/// to the next surface below or idles before reversing direction.
async function climb(ctx: ModeContext): Promise<Point> {
  const { env, pos, pet } = ctx;
  if (env.windows.length === 0) return wander(ctx);

  const surface = findSurfaceBelow(pos, env);
  if (!surface) return pos;

  const dir = pickClimbDirection(pos, surface, env);
  const step = pxPerSec(loadConfig().speed) * DT_SEC;
  const nextX = pos.x + dir * step;
  const onEdge = nextX < surface.rect.left - 2 || nextX > surface.rect.right + 2;

  if (onEdge) {
    pet?.clearRow();
    await sleep(IDLE_MS_MIN + Math.random() * (IDLE_MS_MAX - IDLE_MS_MIN));
    return pos;
  }

  const next = clampToBounds(
    { x: nextX, y: surface.rect.top - WIN_H },
    env.workArea,
  );
  pet?.setRow(dir > 0 ? ROW_RIGHT : ROW_LEFT);
  return next;
}

function moveToward(target: Point, pos: Point, bounds: Rect, pet: Pet | null): Point {
  const dx = target.x - pos.x;
  const dy = target.y - pos.y;
  const dist = Math.hypot(dx, dy);
  if (dist < 8) { pet?.clearRow(); return pos; }
  const speed = pxPerSec(loadConfig().speed);
  const move = Math.min(dist, speed * DT_SEC);
  const next = clampToBounds(
    { x: pos.x + (dx / dist) * move, y: pos.y + (dy / dist) * move },
    bounds,
  );
  pet?.setRow(dx > 0 ? ROW_RIGHT : ROW_LEFT);
  return next;
}

function randomTarget(bounds: Rect): Point {
  const x = bounds.left + MARGIN + Math.random() * Math.max(1, bounds.right - bounds.left - WIN_W - MARGIN * 2);
  const y = bounds.top + MARGIN + Math.random() * Math.max(1, bounds.bottom - bounds.top - WIN_H - MARGIN * 2);
  return { x, y };
}

interface SurfaceInfo { rect: Rect; isWindow: boolean }

function findSurfaceBelow(pos: Point, env: Environment): SurfaceInfo | null {
  let best: SurfaceInfo | null = { rect: env.workArea, isWindow: false };
  let bestTop = env.workArea.bottom;
  const centerX = pos.x + WIN_W / 2;
  for (const w of env.windows) {
    if (centerX < w.rect.left || centerX > w.rect.right) continue;
    if (w.rect.top >= pos.y + WIN_H && w.rect.top < bestTop) {
      bestTop = w.rect.top;
      best = { rect: w.rect, isWindow: true };
    }
  }
  return best;
}

function pickClimbDirection(pos: Point, surface: SurfaceInfo, _env: Environment): number {
  const center = pos.x + WIN_W / 2;
  const surfaceCenter = (surface.rect.left + surface.rect.right) / 2;
  if (Math.abs(center - surfaceCenter) < 10) return Math.random() < 0.5 ? -1 : 1;
  return center < surfaceCenter ? 1 : -1;
}
