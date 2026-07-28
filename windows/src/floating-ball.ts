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
const MENU_W = 260;
const MENU_H = 340;
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
  const logicalY = pos.y / sf;
  const workBottom = work ? (work.position.y + work.size.height) / sf : logicalY + MENU_H;
  if (logicalY + MENU_H > workBottom) {
    // Ball is too close to the bottom: slide the window up so the menu fits.
    void win.setPosition(new LogicalPosition(pos.x / sf, workBottom - MENU_H));
  }

  menu.hidden = false;
  void win.setSize(new LogicalSize(MENU_W, MENU_H));
  requestAnimationFrame(() => input.focus());
}

function hideMenu() {
  if (menu.hidden) return;
  menu.hidden = true;
  shrinkToBall();
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

window.addEventListener("mouseup", () => {
  ball.classList.remove("pressed");
  if (!mayBeClick) return;
  mayBeClick = false;
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
applyLangStrings();
syncTargetButtons();
paintPresets();
syncSend();
void listen("bubble-changed", () => paintPresets());
void listen<Lang>("lang-changed", (e) => { setLang(e.payload); applyLangStrings(); paintPresets(); });
