// Shared window-position helpers. Both the engine (tick loop) and the physics
// module (throw/fall) need to read and write the pet window's logical position;
// centralizing it keeps the DPI conversion in one place and avoids two copies
// of the same `outerPosition / scaleFactor` dance drifting apart.

import { getCurrentWindow } from "@tauri-apps/api/window";
import { LogicalPosition } from "@tauri-apps/api/dpi";
import type { Point } from "./types";

const win = getCurrentWindow();

/// Current window position in LOGICAL pixels (DPI-divided). Returns null if the
/// window or scaleFactor can't be read (e.g. window closing).
export async function currentLogicalPos(): Promise<Point | null> {
  try {
    const sf = await win.scaleFactor();
    const p = await win.outerPosition();
    return { x: p.x / sf, y: p.y / sf };
  } catch {
    return null;
  }
}

/// Move the window to a logical-pixel position. Caller is responsible for
/// clamping to the work area first.
export async function setLogical(pos: Point): Promise<void> {
  await win.setPosition(new LogicalPosition(pos.x, pos.y));
}
