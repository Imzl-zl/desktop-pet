// Floating ball: a draggable desktop orb. Left-click opens a bubble menu,
// right-click opens Settings, drag moves the window and snaps to the nearest
// edge on release.

import { invoke } from "@tauri-apps/api/core";
import { emit, listen } from "@tauri-apps/api/event";
import { getCurrentWindow, currentMonitor, LogicalPosition, LogicalSize } from "@tauri-apps/api/window";
import { t, setLang, type Lang } from "./i18n";

const QUICK_KEY = "ap_quick_bubbles";
const TARGET_KEY = "ap_ball_target";
const MAX_PRESETS = 12;

const WIN_SIZE = 80;        // window is larger than the 56px orb so shadows/scale fit
const MENU_W = 300;
const MENU_H = 420;
const DRAG_THRESHOLD_PX = 4;
const CLICK_MAX_MS = 280;

const ball = document.getElementById("ball") as HTMLDivElement;
const menu = document.getElementById("ball-menu") as HTMLDivElement;
const input = document.getElementById("bm-input") as HTMLInputElement;
const presetsEl = document.getElementById("bm-presets") as HTMLDivElement;
const sendBtn = document.getElementById("bm-send") as HTMLButtonElement;
const cancelBtn = document.getElementById("bm-cancel") as HTMLButtonElement;
const targetEl = document.getElementById("bm-target") as HTMLDivElement;

const win = getCurrentWindow();

let selectedPreset = -1;
let mayBeClick = false;
let isDragging = false;
let dragStartX = 0;
let dragStartY = 0;
let dragStartTime = 0;

function readPresets(): string[] {
  try {
    const v = JSON.parse(localStorage.getItem(QUICK_KEY) || "[]");
    return Array.isArray(v)
      ? v.filter((x: unknown) => typeof x === "string" && x.trim()).slice(0, MAX_PRESETS)
      : [];
  } catch { return []; }
}

function writePresets(list: string[]) {
  localStorage.setItem(QUICK_KEY, JSON.stringify(list.slice(0, MAX_PRESETS)));
  void emit("bubble-changed", null);
}

function readTarget(): "all" | "main" | "extra" {
  const v = localStorage.getItem(TARGET_KEY);
  return v === "main" || v === "extra" ? v : "all";
}

function writeTarget(v: "all" | "main" | "extra") {
  localStorage.setItem(TARGET_KEY, v);
}

function syncTargetButtons() {
  const cur = readTarget();
  targetEl.querySelectorAll<HTMLButtonElement>("button").forEach((b) => {
    b.classList.toggle("sel", b.dataset.v === cur);
  });
}

function syncSend() {
  sendBtn.disabled = !input.value.trim();
}

function createPresetButton(line: string, index: number) {
  const btn = document.createElement("button");
  btn.className = "bm-preset";
  btn.textContent = line;
  btn.title = t("Send to selected") + " · " + t("Shift-click to delete");
  btn.onclick = (ev) => {
    if (ev.shiftKey) {
      const next = readPresets().filter((_, j) => j !== index);
      writePresets(next);
      selectedPreset = -1;
      paintPresets();
      syncSend();
      return;
    }
    selectedPreset = index;
    input.value = line;
    paintPresets();
    syncSend();
    input.focus();
  };
  if (selectedPreset === index) btn.classList.add("sel");
  return btn;
}

function paintPresets() {
  const list = readPresets();
  presetsEl.innerHTML = "";
  if (!list.length) {
    presetsEl.style.display = "none";
    return;
  }
  presetsEl.style.display = "";
  list.forEach((line, i) => presetsEl.appendChild(createPresetButton(line, i)));
}

function applyLangStrings() {
  input.placeholder = t("Type a bubble message…");
  (document.getElementById("bm-target-all") as HTMLElement).textContent = t("All");
  (document.getElementById("bm-target-main") as HTMLElement).textContent = t("Main");
  (document.getElementById("bm-target-extra") as HTMLElement).textContent = t("Extra");
  cancelBtn.textContent = t("Cancel");
  sendBtn.textContent = t("Send");
  ball.title = t("Left-click: bubble · Right-click: settings · Drag to move");
}

function shrinkToBall() {
  void win.setSize(new LogicalSize(WIN_SIZE, WIN_SIZE));
}

/// Height delta between the menu window and the ball window.
const MENU_GROW = MENU_H - WIN_SIZE;

async function showMenu() {
  if (!menu.hidden) return;
  input.value = "";
  selectedPreset = -1;
  syncTargetButtons();
  paintPresets();
  syncSend();

  const pos = await win.outerPosition();
  const sf = await win.scaleFactor();
  const mon = await currentMonitor();
  const work = mon?.workArea;
  const logicalX = pos.x / sf;
  const logicalY = pos.y / sf;
  const workLeft = work ? work.position.x / sf : logicalX;
  const workTop = work ? work.position.y / sf : logicalY;
  const workRight = work ? (work.position.x + work.size.width) / sf : logicalX + MENU_W;
  const workBottom = work ? (work.position.y + work.size.height) / sf : logicalY + MENU_H;

  // If the menu would overflow the bottom, open UPWARD: the ball sticks to
  // the bottom of the window and the menu sits above it. The window's Y
  // moves up by MENU_GROW so the ball's screen position is preserved.
  const openAbove = logicalY + MENU_H > workBottom;
  // Adjust X so the wider menu window stays on-screen.
  let newX = logicalX;
  if (newX + MENU_W > workRight) newX = workRight - MENU_W;
  if (newX < workLeft) newX = workLeft;
  let newY = logicalY;
  if (openAbove) newY = logicalY - MENU_GROW;
  // Clamp Y so the window never starts above the work area.
  if (newY < workTop) newY = workTop;

  document.body.classList.toggle("menu-above", openAbove);
  if (Math.abs(newX - logicalX) > 0.5 || Math.abs(newY - logicalY) > 0.5) {
    void win.setPosition(new LogicalPosition(newX, newY));
  }
  // Resize FIRST, then reveal the menu, so the menu never appears clipped
  // inside the still-80×80 window for a frame.
  await win.setSize(new LogicalSize(MENU_W, MENU_H));
  menu.hidden = false;
  requestAnimationFrame(() => input.focus());
}

function hideMenu() {
  if (menu.hidden) return;
  menu.hidden = true;
  const wasAbove = document.body.classList.contains("menu-above");
  document.body.classList.remove("menu-above");
  shrinkToBall();
  if (wasAbove) {
    // Window was shifted up by MENU_GROW to open the menu above.
    // Move it back down so the ball returns to its original screen position.
    void (async () => {
      const pos = await win.outerPosition();
      const sf = await win.scaleFactor();
      void win.setPosition(new LogicalPosition(pos.x / sf, pos.y / sf + MENU_GROW));
    })();
  }
}

function send() {
  const text = input.value.trim();
  if (!text) return;
  const next = [text, ...readPresets().filter((x) => x !== text)];
  writePresets(next);
  void emit("quick-bubble", { text, target: readTarget() });
  hideMenu();
}

// ---- click vs drag ---------------------------------------------------------
// We do not use data-tauri-drag-region: it can be flaky on small Windows
// webviews and makes click detection unreliable. Instead, detect movement
// ourselves and call startDragging() once the cursor has moved enough.

ball.addEventListener("mousedown", (e) => {
  if (e.button !== 0) return;
  if (!menu.hidden) { hideMenu(); return; }
  mayBeClick = true;
  isDragging = false;
  dragStartX = e.screenX;
  dragStartY = e.screenY;
  dragStartTime = performance.now();
  ball.classList.add("pressed");
});

window.addEventListener("mousemove", (e) => {
  if (!mayBeClick || isDragging) return;
  const dx = Math.abs(e.screenX - dragStartX);
  const dy = Math.abs(e.screenY - dragStartY);
  if (dx <= DRAG_THRESHOLD_PX && dy <= DRAG_THRESHOLD_PX) return;

  mayBeClick = false;
  isDragging = true;
  ball.classList.remove("pressed");
  ball.classList.add("dragging");

  getCurrentWindow().startDragging().finally(() => {
    isDragging = false;
    ball.classList.remove("dragging");
    void invoke("snap_floating_ball");
  });
});

window.addEventListener("mouseup", (e) => {
  ball.classList.remove("pressed");
  if (!mayBeClick) return;
  mayBeClick = false;
  // Reject the click if the cursor moved beyond the drag threshold, even if
  // mousemove didn't fire in time to start the OS drag. This prevents the
  // menu from flashing open when the user intended to drag.
  const dx = Math.abs(e.screenX - dragStartX);
  const dy = Math.abs(e.screenY - dragStartY);
  if (dx > DRAG_THRESHOLD_PX || dy > DRAG_THRESHOLD_PX) return;
  const elapsed = performance.now() - dragStartTime;
  if (elapsed <= CLICK_MAX_MS) showMenu();
});

ball.addEventListener("contextmenu", (e) => {
  e.preventDefault();
  hideMenu();
  void invoke("open_settings");
});

// ---- menu interactions -----------------------------------------------------
input.addEventListener("input", () => { selectedPreset = -1; paintPresets(); syncSend(); });
input.addEventListener("keydown", (e) => {
  if (e.key === "Enter" && input.value.trim()) { e.preventDefault(); send(); }
  else if (e.key === "Escape") { hideMenu(); }
});

targetEl.querySelectorAll<HTMLButtonElement>("button").forEach((b) => {
  b.onclick = () => { writeTarget(b.dataset.v as "all" | "main" | "extra"); syncTargetButtons(); };
});

cancelBtn.onclick = () => hideMenu();
sendBtn.onclick = () => send();

// Dismiss menu on Escape or when the window loses focus.
window.addEventListener("keydown", (e) => { if (e.key === "Escape" && !menu.hidden) hideMenu(); });
window.addEventListener("blur", () => { if (!menu.hidden) hideMenu(); });

// ---- live updates ----------------------------------------------------------
function applyReduceMotion() {
  document.body.classList.toggle("reduce-motion", localStorage.getItem("ap_reduce_motion") === "1");
}
applyReduceMotion();
window.addEventListener("storage", (e) => { if (e.key === "ap_reduce_motion") applyReduceMotion(); });

applyLangStrings();
syncTargetButtons();
paintPresets();
syncSend();
void listen("bubble-changed", () => paintPresets());
void listen<Lang>("lang-changed", (e) => { setLang(e.payload); applyLangStrings(); paintPresets(); });
