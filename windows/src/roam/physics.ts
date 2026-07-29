// Drag-release throw physics and gravity-driven fall. Both operate in logical
// pixels per second and are decoupled from the window API so they can be unit
// tested without a live Tauri window.

import { invoke } from "@tauri-apps/api/core";
import type { Pet } from "../pet";
import type { Point, Rect } from "./types";
import {
  DT_SEC,
  PHYSICS_FRICTION,
  PHYSICS_GRAVITY,
  PHYSICS_MIN_SPEED,
  SAMPLE_WINDOW_MS,
  TICK_MS,
  WIN_H,
  WIN_W,
  sleep,
} from "./types";
import { currentLogicalPos, setLogical } from "./window";

interface Sample { t: number; x: number; y: number }
const samples: Sample[] = [];

export function recordSample(pos: Point): void {
  const now = performance.now();
  samples.push({ t: now, x: pos.x, y: pos.y });
  while (samples.length && now - samples[0].t > SAMPLE_WINDOW_MS) samples.shift();
}

export function releaseVelocity(): { vx: number; vy: number } | null {
  if (samples.length < 2) return null;
  const first = samples[0];
  const last = samples[samples.length - 1];
  const dt = last.t - first.t;
  if (dt < 20) return null;
  return {
    vx: ((last.x - first.x) / dt) * 1000,
    vy: ((last.y - first.y) / dt) * 1000,
  };
}

export function clearSamples(): void {
  samples.length = 0;
}

let throwing = false;
export function isThrowing(): boolean { return throwing; }
export function cancelThrow(): void { throwing = false; }

/// Inertia after a drag release. Friction decays velocity each tick; hitting a
/// screen edge reflects velocity at 50% to feel bouncy without escaping.
export async function applyThrow(
  vx: number,
  vy: number,
  bounds: Rect,
  pet: Pet | null,
  stop: () => boolean,
): Promise<void> {
  throwing = true;
  let pos = await currentLogicalPos();
  if (!pos) { throwing = false; return; }

  while (!stop() && throwing) {
    if (Math.hypot(vx, vy) < PHYSICS_MIN_SPEED) break;

    vx *= PHYSICS_FRICTION;
    vy *= PHYSICS_FRICTION;

    let nx: number = pos.x + vx * DT_SEC;
    let ny: number = pos.y + vy * DT_SEC;
    [vx, nx] = bounceX(vx, nx, bounds);
    [vy, ny] = bounceY(vy, ny, bounds);

    pos = { x: nx, y: ny };
    try { await setLogical(pos); }
    catch (e) { void invoke("log_debug", { msg: `roam: throw error: ${e}` }).catch(() => {}); break; }

    pet?.setRow(vx > 0 ? 1 : 2);
    await sleep(TICK_MS);
  }

  throwing = false;
  pet?.clearRow();
}

/// Gravity fall after drag release (Shimeji-style). Pet accelerates downward
/// until it lands on a surface (work area bottom or a window top edge).
export async function applyFall(
  vx: number,
  bounds: Rect,
  surfaces: Rect[],
  pet: Pet | null,
  stop: () => boolean,
): Promise<void> {
  throwing = true;
  let pos = await currentLogicalPos();
  if (!pos) { throwing = false; return; }

  let vy = 0;
  while (!stop() && throwing) {
    vy += PHYSICS_GRAVITY * DT_SEC;
    const nx: number = pos.x + vx * DT_SEC;
    let ny: number = pos.y + vy * DT_SEC;

    const floorY = findFloor(pos.x, nx, bounds, surfaces);
    if (ny >= floorY) {
      ny = floorY;
      throwing = false;
    }

    pos = { x: Math.max(bounds.left, Math.min(bounds.right - WIN_W, nx)), y: ny };
    try { await setLogical(pos); }
    catch (e) { void invoke("log_debug", { msg: `roam: fall error: ${e}` }).catch(() => {}); break; }

    pet?.setRow(vx > 0 ? 1 : 2);
    await sleep(TICK_MS);
  }

  throwing = false;
  pet?.clearRow();
}

function bounceX(vx: number, nx: number, bounds: Rect): [number, number] {
  if (nx < bounds.left || nx > bounds.right - WIN_W) {
    return [-vx * 0.5, Math.max(bounds.left, Math.min(bounds.right - WIN_W, nx))];
  }
  return [vx, nx];
}

function bounceY(vy: number, ny: number, bounds: Rect): [number, number] {
  if (ny < bounds.top || ny > bounds.bottom - WIN_H) {
    return [-vy * 0.5, Math.max(bounds.top, Math.min(bounds.bottom - WIN_H, ny))];
  }
  return [vy, ny];
}

/// Find the highest surface (window top edge or work-area bottom) under the
/// pet's horizontal range [x1, x2], returned as the pet's TOP-Y when resting on
/// it. `pos.y` is the window's top-left, so landing = top at `surface.top - WIN_H`.
function findFloor(x1: number, x2: number, bounds: Rect, surfaces: Rect[]): number {
  let floor = bounds.bottom - WIN_H;
  for (const s of surfaces) {
    if (x2 < s.left || x1 > s.right) continue;
    const top = s.top - WIN_H;
    if (top < floor && top >= bounds.top) floor = top;
  }
  return floor;
}
