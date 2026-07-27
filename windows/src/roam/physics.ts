// Drag-release throw physics and gravity-driven fall. Both operate in logical
// pixels per second and are decoupled from the window API so they can be unit
// tested without a live Tauri window.

import { invoke } from "@tauri-apps/api/core";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { LogicalPosition } from "@tauri-apps/api/dpi";
import type { Pet } from "../pet";
import type { Point, Rect } from "./types";
import {
  PHYSICS_FRICTION,
  PHYSICS_GRAVITY,
  PHYSICS_MIN_SPEED,
  SAMPLE_WINDOW_MS,
  sleep,
} from "./types";

const win = getCurrentWindow();

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

async function setLogical(pos: Point): Promise<void> {
  await win.setPosition(new LogicalPosition(pos.x, pos.y));
}

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

    let nx: number = pos.x + vx * 0.03;
    let ny: number = pos.y + vy * 0.03;
    [vx, nx] = bounceX(vx, nx, bounds);
    [vy, ny] = bounceY(vy, ny, bounds);

    pos = { x: nx, y: ny };
    try { await setLogical(pos); }
    catch (e) { void invoke("log_debug", { msg: `roam: throw error: ${e}` }).catch(() => {}); break; }

    pet?.setRow(vx > 0 ? 1 : 2);
    await sleep(30);
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
    vy += PHYSICS_GRAVITY * 0.03;
    const nx: number = pos.x + vx * 0.03;
    let ny: number = pos.y + vy * 0.03;

    const floorY = findFloor(pos.x, nx, bounds, surfaces);
    if (ny >= floorY) {
      ny = floorY;
      throwing = false;
    }

    pos = { x: Math.max(bounds.left, Math.min(bounds.right - 1, nx)), y: ny };
    try { await setLogical(pos); }
    catch (e) { void invoke("log_debug", { msg: `roam: fall error: ${e}` }).catch(() => {}); break; }

    pet?.setRow(vx > 0 ? 1 : 2);
    await sleep(30);
  }

  throwing = false;
  pet?.clearRow();
}

function bounceX(vx: number, nx: number, bounds: Rect): [number, number] {
  if (nx < bounds.left || nx > bounds.right - 1) {
    return [-vx * 0.5, Math.max(bounds.left, Math.min(bounds.right - 1, nx))];
  }
  return [vx, nx];
}

function bounceY(vy: number, ny: number, bounds: Rect): [number, number] {
  if (ny < bounds.top || ny > bounds.bottom - 1) {
    return [-vy * 0.5, Math.max(bounds.top, Math.min(bounds.bottom - 1, ny))];
  }
  return [vy, ny];
}

/// Find the Y of the highest surface (window top edge or work-area bottom)
/// under the pet's horizontal range [x1, x2].
function findFloor(x1: number, x2: number, bounds: Rect, surfaces: Rect[]): number {
  let floor = bounds.bottom - 1;
  for (const s of surfaces) {
    if (x2 < s.left || x1 > s.right) continue;
    if (s.top < floor && s.top >= bounds.top) floor = s.top;
  }
  return floor;
}

async function currentLogicalPos(): Promise<Point | null> {
  try {
    const sf = await win.scaleFactor();
    const p = await win.outerPosition();
    return { x: p.x / sf, y: p.y / sf };
  } catch { return null; }
}
