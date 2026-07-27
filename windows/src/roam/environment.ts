// Environment sensing: monitor work area + enumeration of other application
// windows. All geometry is returned in logical pixels so the rest of the roam
// subsystem can stay DPI-agnostic.

import { currentMonitor, type Monitor } from "@tauri-apps/api/window";
import { invoke } from "@tauri-apps/api/core";
import type { Environment, Rect, SystemWindow } from "./types";

/// Raw shape returned by the Rust `list_system_windows` command. Coordinates
/// are physical pixels; we convert to logical in `fetchEnvironment`.
interface RawSystemWindow {
  title: string;
  x: number;
  y: number;
  width: number;
  height: number;
}

function toLogicalRect(rect: RawSystemWindow, sf: number): SystemWindow {
  return {
    title: rect.title,
    rect: {
      left: rect.x / sf,
      top: rect.y / sf,
      right: (rect.x + rect.width) / sf,
      bottom: (rect.y + rect.height) / sf,
    },
  };
}

// 500ms monitor cache: the monitor rarely changes (only when the user drags
// the pet to another display), and currentMonitor() is an IPC call. Without
// this, N roaming pets fire 2×N×33 IPC calls/sec just for monitor info.
const MONITOR_CACHE_MS = 500;
let monitorCache: { mon: Monitor | null; ts: number } | null = null;

async function cachedMonitor(): Promise<Monitor | null> {
  const now = Date.now();
  if (monitorCache && now - monitorCache.ts < MONITOR_CACHE_MS) {
    return monitorCache.mon;
  }
  try {
    const m = await currentMonitor();
    monitorCache = { mon: m, ts: now };
    return m;
  } catch {
    return null;
  }
}

async function fetchSystemWindows(sf: number): Promise<SystemWindow[]> {
  try {
    const raw = await invoke<RawSystemWindow[]>("list_system_windows");
    if (!Array.isArray(raw)) return [];
    return raw
      .filter((w) => w.width > 40 && w.height > 40)
      .map((w) => toLogicalRect(w, sf));
  } catch {
    return [];
  }
}

export async function fetchEnvironment(): Promise<Environment | null> {
  try {
    // Single currentMonitor() call (cached) instead of the previous two.
    const m = await cachedMonitor();
    if (!m || !m.workArea) return null;
    const sf = m.scaleFactor || 1;
    const wa = m.workArea;
    const workArea: Rect = {
      left: wa.position.x / sf,
      top: wa.position.y / sf,
      right: (wa.position.x + wa.size.width) / sf,
      bottom: (wa.position.y + wa.size.height) / sf,
    };

    const windows = await fetchSystemWindows(sf);
    return { workArea, windows };
  } catch (e) {
    void invoke("log_debug", { msg: `roam: environment error: ${e}` }).catch(() => {});
    return null;
  }
}
