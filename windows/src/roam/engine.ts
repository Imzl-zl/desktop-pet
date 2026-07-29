// Movement engine: owns the tick loop, coordinates drag sampling, throw/fall
// physics, and dispatches to the active movement mode.

import { invoke } from "@tauri-apps/api/core";
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
import type { RoamMode } from "./types";
import {
  SLEEP_AFTER_MS,
  SLEEP_ROW_DEFAULT,
  THROW_MIN_SPEED,
  TICK_MS,
  clampToBounds,
  loadConfig,
  sleep,
} from "./types";
import { currentLogicalPos, setLogical } from "./window";

let petRef: Pet | null = null;
let dragging = false;
let releasePending = false;
let stopRequested = false;

/// Mood drives two behaviors: pause roaming while the user needs to read the
/// bubble (waiting / celebrate), and let the pet doze off when idle.
let mood: string = "idle";
let lastMoveTs = Date.now();
let sleeping = false;

/// Moods that freeze the pet so the bubble / celebration animation stays readable.
const MOOD_PAUSES_ROAM = new Set(["waiting", "celebrate"]);

function stop(): boolean { return stopRequested; }

/// Called from main.ts after each mood evaluation. Non-idle moods wake the pet.
export function setMood(m: string): void {
  mood = m;
  if (m !== "idle") wake();
}

function wake(): void {
  if (!sleeping) return;
  sleeping = false;
  petRef?.clearRow();
}

function enterSleep(): void {
  if (sleeping) return;
  sleeping = true;
  const bound = parseInt(localStorage.getItem("ap_bind_sleep") ?? "", 10);
  const row = Number.isFinite(bound) && bound >= 0 ? bound : SLEEP_ROW_DEFAULT;
  petRef?.setRow(row);
}

/// One engine tick. Priority: throw > drag-sample > drag-release > mood-pause > sleep > mode.
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
    if (vel && Math.hypot(vel.vx, vel.vy) > THROW_MIN_SPEED) {
      wake();
      await handleDragRelease(vel);
      return;
    }
  }

  // Mood-driven freeze: keep the pet still while the user needs to see the
  // bubble or the celebrate burst. Throws and drags above still work.
  if (MOOD_PAUSES_ROAM.has(mood)) {
    wake();
    petRef?.clearRow();
    return;
  }

  const cfg = loadConfig();
  if (!cfg.enabled || cfg.mode === "stay") {
    handleStationary();
    return;
  }

  wake();
  const moved = await stepMode(cfg.mode);
  if (!moved && mood === "idle" && Date.now() - lastMoveTs > SLEEP_AFTER_MS) {
    enterSleep();
  }
}

/// Run one mode step and apply it. Returns true if the pet actually moved.
async function stepMode(mode: RoamMode): Promise<boolean> {
  const env = await fetchEnvironment();
  if (!env) return false;
  const pos = await currentLogicalPos();
  if (!pos) return false;

  const next = await runMode(mode, { env, pos, pet: petRef });
  const clamped = clampToBounds(next, env.workArea);
  if (Math.abs(clamped.x - pos.x) < 0.5 && Math.abs(clamped.y - pos.y) < 0.5) {
    return false;
  }
  lastMoveTs = Date.now();
  try { await setLogical(clamped); }
  catch (e) { void invoke("log_debug", { msg: `roam: setPosition error: ${e}` }).catch(() => {}); }
  return true;
}

/// Pet is stationary (mode is stay or roaming disabled): maybe doze off.
function handleStationary(): void {
  if (mood === "idle" && Date.now() - lastMoveTs > SLEEP_AFTER_MS) {
    enterSleep();
  } else {
    wake();
    petRef?.clearRow();
  }
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
  lastMoveTs = Date.now();
  mood = "idle";
  sleeping = false;
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
    wake();
    releasePending = false;
  } else if (petRef) {
    releasePending = true;
  }
}
