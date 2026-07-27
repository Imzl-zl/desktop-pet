// Public API for the roam subsystem. Re-exports the engine lifecycle and
// config accessors so callers (main.ts, settings.ts) keep using the same
// imports as before, while the implementation is split across the roam/
// directory.

import type { Pet } from "../pet";
import { destroyEngine, initEngine, setDragging } from "./engine";
import {
  ROAM_KEY,
  ROAM_MODE_KEY,
  ROAM_SPEED_KEY,
  VALID_MODES,
  loadConfig,
} from "./types";
import type { RoamMode } from "./types";

export { setDragging };
export { ROAM_KEY, ROAM_MODE_KEY, ROAM_SPEED_KEY };

export function initRoam(pet: Pet): void {
  initEngine(pet);
}

export function destroyRoam(): void {
  destroyEngine();
}

export function isRoamingEnabled(): boolean {
  return localStorage.getItem(ROAM_KEY) !== "0";
}

export function setRoamEnabled(enabled: boolean): void {
  localStorage.setItem(ROAM_KEY, enabled ? "1" : "0");
}

export function getRoamMode(): RoamMode {
  return loadConfig().mode;
}

export function setRoamMode(mode: RoamMode): void {
  if (VALID_MODES.includes(mode)) {
    localStorage.setItem(ROAM_MODE_KEY, mode);
  }
}

export function getRoamSpeed(): number {
  return loadConfig().speed;
}

export function setRoamSpeed(speed: number): void {
  localStorage.setItem(ROAM_SPEED_KEY, String(Math.max(1, Math.min(10, speed))));
}
