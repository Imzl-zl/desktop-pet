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

/// Tick delay when the pet is resting / sleeping / stationary. The active
/// TICK_MS (30ms) is only needed while the pet is actually moving — resting
/// states (restUntil, sleep, stay mode) only need to check periodically whether
/// to wake up. 200ms cuts IPC calls from 33/sec to 5/sec while idle, with no
/// visible change (the pet resumes walking within one idle-tick of restUntil
/// expiring, imperceptible for a desktop companion).
const IDLE_TICK_MS = 200;

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
/// Returns true when the pet is actively moving/interacting and needs the fast
/// (30ms) tick; false when resting/sleeping/stationary so the loop can use the
/// idle (200ms) tick and skip most IPC calls.
async function tick(): Promise<boolean> {
  if (isThrowing()) return true;
  if (dragging) {
    const pos = await currentLogicalPos();
    if (pos) recordSample(pos);
    return true;
  }
  if (releasePending) {
    releasePending = false;
    const vel = releaseVelocity();
    clearSamples();
    if (vel && Math.hypot(vel.vx, vel.vy) > THROW_MIN_SPEED) {
      wake();
      await handleDragRelease(vel);
      return true;
    }
  }

  // Mood-driven freeze: keep the pet still while the user needs to see the
  // bubble or the celebrate burst. Throws and drags above still work.
  if (MOOD_PAUSES_ROAM.has(mood)) {
    wake();
    petRef?.clearRow();
    return false;
  }

  const cfg = loadConfig();
  if (!cfg.enabled || cfg.mode === "stay") {
    handleStationary();
    return false;
  }

  wake();
  const moved = await stepMode(cfg.mode);
  if (!moved && mood === "idle" && Date.now() - lastMoveTs > SLEEP_AFTER_MS) {
    enterSleep();
  }
  return moved;
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
    const active = await tick();
    await sleep(active ? TICK_MS : IDLE_TICK_MS);
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
