// Roam configuration: movement mode + speed per pet. The actual per-frame
// movement is now handled by the single stage window (src/stage.ts); this
// module only owns the persisted settings and helpers used by Settings.

const ROAM_MODE_KEY = "ap_roam_mode";
const ROAM_SPEED_KEY = "ap_roam_speed";

export type RoamMode = "stay" | "wander" | "cursor" | "climb";

export function getRoamMode(label = "default"): RoamMode {
  const key = label === "default" ? ROAM_MODE_KEY : `ap_win_${label}_roam_mode`;
  const v = localStorage.getItem(key);
  return v === "wander" || v === "cursor" || v === "climb" ? v : "stay";
}

export function setRoamMode(mode: RoamMode, label = "default") {
  const key = label === "default" ? ROAM_MODE_KEY : `ap_win_${label}_roam_mode`;
  localStorage.setItem(key, mode);
}

export function getRoamSpeed(): number {
  const v = parseInt(localStorage.getItem(ROAM_SPEED_KEY) || "50", 10);
  return Number.isFinite(v) ? Math.max(10, Math.min(200, v)) : 50;
}

export function setRoamSpeed(v: number) {
  localStorage.setItem(ROAM_SPEED_KEY, String(Math.max(10, Math.min(200, v))));
}

// Legacy single-pet hooks kept for API compatibility with any remaining
// callers; they are no-ops because the stage owns movement now.
export function initRoam(_pet: unknown) {}
export function setDragging(_dragging: boolean) {}
export function setMood(_mood: string) {}
