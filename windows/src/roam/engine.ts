// Movement engine: owns the tick loop, coordinates drag sampling, throw/fall
// physics, and dispatches to the active movement mode.

import { invoke } from "@tauri-apps/api/core";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { LogicalPosition } from "@tauri-apps/api/dpi";
import type { Pet } from "../pet";
import { fetchEnvironment } from "./environment";
import { runMode } from "./modes";
import {
  applyFall,
  applyThrow,
  cancelThrow,
  clearSamples,
  isThrowing,
  recordSample,
  releaseVelocity,
} from "./physics";
import type { Point } from "./types";
import { TICK_MS, clampToBounds, loadConfig, sleep } from "./types";

const win = getCurrentWindow();

let petRef: Pet | null = null;
let dragging = false;
let releasePending = false;
let stopRequested = false;

function stop(): boolean { return stopRequested; }

async function currentLogicalPos(): Promise<Point | null> {
  try {
    const sf = await win.scaleFactor();
    const p = await win.outerPosition();
    return { x: p.x / sf, y: p.y / sf };
  } catch { return null; }
}

async function setLogical(pos: Point): Promise<void> {
  await win.setPosition(new LogicalPosition(pos.x, pos.y));
}

/// One engine tick. Priority: throw > drag-sample > drag-release > mode.
async function tick(): Promise<void> {
  if (isThrowing()) return;

  if (dragging) {
    const pos = await currentLogicalPos();
    if (pos) recordSample(pos);
    return;
  }

  if (releasePending) {
    releasePending = false;
    const vel = releaseVelocity();
    clearSamples();
    if (vel && Math.hypot(vel.vx, vel.vy) > 15) {
      await handleDragRelease(vel);
      return;
    }
  }

  const cfg = loadConfig();
  if (!cfg.enabled || cfg.mode === "stay") {
    petRef?.clearRow();
    return;
  }

  const env = await fetchEnvironment();
  if (!env) return;
  const pos = await currentLogicalPos();
  if (!pos) return;

  const next = await runMode(cfg.mode, { env, pos, pet: petRef, stop });
  const clamped = clampToBounds(next, env.workArea);
  if (Math.abs(clamped.x - pos.x) < 0.5 && Math.abs(clamped.y - pos.y) < 0.5) return;

  try { await setLogical(clamped); }
  catch (e) { void invoke("log_debug", { msg: `roam: setPosition error: ${e}` }).catch(() => {}); }
}

async function handleDragRelease(vel: { vx: number; vy: number }): Promise<void> {
  const env = await fetchEnvironment();
  if (!env) return;

  const cfg = loadConfig();
  if (cfg.mode === "climb" && env.windows.length > 0) {
    const surfaces = env.windows.map((w) => w.rect);
    await applyFall(vel.vx, env.workArea, surfaces, petRef, stop);
  } else {
    await applyThrow(vel.vx, vel.vy, env.workArea, petRef, stop);
  }
}

async function loop(): Promise<void> {
  while (!stopRequested) {
    await tick();
    await sleep(TICK_MS);
  }
  petRef?.clearRow();
}

export function initEngine(pet: Pet): void {
  if (petRef) return;
  petRef = pet;
  stopRequested = false;
  void loop();
}

export function destroyEngine(): void {
  stopRequested = true;
  cancelThrow();
  petRef = null;
}

export function setDragging(isDragging: boolean): void {
  dragging = isDragging;
  if (isDragging) {
    cancelThrow();
    clearSamples();
    releasePending = false;
  } else if (petRef) {
    releasePending = true;
  }
}
