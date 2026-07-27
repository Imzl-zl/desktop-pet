// Environment sensing: monitor work area + enumeration of other application
// windows. All geometry is returned in logical pixels so the rest of the roam
// subsystem can stay DPI-agnostic.

import { currentMonitor } from "@tauri-apps/api/window";
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

async function fetchMonitorWorkArea(sf: number): Promise<Rect | null> {
  try {
    const m = await currentMonitor();
    if (!m || !m.workArea) return null;
    const wa = m.workArea;
    return {
      left: wa.position.x / sf,
      top: wa.position.y / sf,
      right: (wa.position.x + wa.size.width) / sf,
      bottom: (wa.position.y + wa.size.height) / sf,
    };
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
    const m = await currentMonitor();
    const sf = m?.scaleFactor || 1;

    const workArea = await fetchMonitorWorkArea(sf);
    if (!workArea) return null;

    const windows = await fetchSystemWindows(sf);
    return { workArea, windows };
  } catch (e) {
    void invoke("log_debug", { msg: `roam: environment error: ${e}` }).catch(() => {});
    return null;
  }
}
