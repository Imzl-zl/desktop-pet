// The floating ball: an independent always-on-top ball that sits on the desktop
// so the user has a stable click target when the pets are roaming. Left-click
// opens a small menu (type or pick a bubble, choose target pets), right-click
// opens Settings. The ball is draggable and snaps to the nearest screen edge
// when released (position persisted by Rust).

import { invoke } from "@tauri-apps/api/core";
import { emit, listen } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { t, setLang, type Lang } from "./i18n";

const QUICK_KEY = "ap_quick_bubbles";
const TARGET_KEY = "ap_ball_target";
const MAX_PRESETS = 12;

function readPresets(): string[] {
  try {
    const v = JSON.parse(localStorage.getItem(QUICK_KEY) || "[]");
    return Array.isArray(v) ? v.filter((x: unknown) => typeof x === "string" && x.trim()).slice(0, MAX_PRESETS) : [];
  } catch { return []; }
}
function writePresets(list: string[]) {
  localStorage.setItem(QUICK_KEY, JSON.stringify(list.slice(0, MAX_PRESETS)));
}
function readTarget(): "all" | "main" | "extra" {
  const v = localStorage.getItem(TARGET_KEY);
  return v === "main" || v === "extra" ? v : "all";
}
function writeTarget(v: "all" | "main" | "extra") {
  localStorage.setItem(TARGET_KEY, v);
}

const ball = document.getElementById("ball") as HTMLDivElement;
const menu = document.getElementById("ball-menu") as HTMLDivElement;
const input = document.getElementById("bm-input") as HTMLInputElement;
const presetsEl = document.getElementById("bm-presets") as HTMLDivElement;
const sendBtn = document.getElementById("bm-send") as HTMLButtonElement;
const cancelBtn = document.getElementById("bm-cancel") as HTMLButtonElement;
const targetEl = document.getElementById("bm-target") as HTMLDivElement;

let selectedPreset = -1;
let dragging = false;
let dragMoved = false;
let downX = 0;
let downY = 0;

function syncTargetButtons() {
  const cur = readTarget();
  targetEl.querySelectorAll<HTMLButtonElement>("button").forEach((b) => {
    b.classList.toggle("sel", b.dataset.v === cur);
  });
}

function paintPresets() {
  const list = readPresets();
  presetsEl.innerHTML = "";
  if (!list.length) {
    presetsEl.style.display = "none";
    return;
  }
  presetsEl.style.display = "";
  list.forEach((line, i) => {
    const btn = document.createElement("button");
    btn.className = "bm-preset";
    btn.textContent = line;
    btn.title = t("Send to selected") + " · " + t("Shift-click to delete");
    btn.onclick = (ev) => {
      if (ev.shiftKey) {
        const next = readPresets().filter((_, j) => j !== i);
        writePresets(next);
        selectedPreset = -1;
        paintPresets();
        syncSend();
        return;
      }
      selectedPreset = i;
      input.value = line;
      paintPresets();
      syncSend();
    };
    if (selectedPreset === i) btn.classList.add("sel");
    presetsEl.appendChild(btn);
  });
}

function syncSend() {
  sendBtn.disabled = !input.value.trim();
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

function showMenu() {
  if (menu.hidden) {
    menu.hidden = false;
    input.value = "";
    selectedPreset = -1;
    syncTargetButtons();
    paintPresets();
    syncSend();
    requestAnimationFrame(() => input.focus());
  } else {
    hideMenu();
  }
}

function hideMenu() {
  menu.hidden = true;
}

// ---- drag + snap -----------------------------------------------------------
// Click vs drag: don't startDragging on mousedown. Instead wait for the cursor
// to move > 4px, only then start the OS drag (and snap on release). If the
// mouse is released before moving, it's a click → open the bubble menu. This
// is necessary because startDragging swallows mouseup, so click never fires.

ball.addEventListener("mousedown", (e) => {
  if (e.button !== 0) return;
  if (!menu.hidden) { hideMenu(); return; }
  dragging = true;
  dragMoved = false;
  downX = e.screenX;
  downY = e.screenY;
});

window.addEventListener("mousemove", (e) => {
  if (!dragging || dragMoved) return;
  if (Math.abs(e.screenX - downX) <= 4 && Math.abs(e.screenY - downY) <= 4) return;
  dragMoved = true;
  dragging = false;
  getCurrentWindow().startDragging().finally(() => {
    // After the OS drag ends, snap to edge + persist.
    invoke("snap_floating_ball").catch(() => {});
  });
});

window.addEventListener("mouseup", () => {
  if (!dragging) return;
  dragging = false;
  showMenu();
});

ball.addEventListener("contextmenu", (e) => {
  e.preventDefault();
  hideMenu();
  invoke("open_settings").catch(() => {});
});

// ---- menu interactions -----------------------------------------------------
input.addEventListener("input", () => { selectedPreset = -1; paintPresets(); syncSend(); });
input.addEventListener("keydown", (e) => {
  if (e.key === "Enter" && input.value.trim()) { e.preventDefault(); send(); }
  else if (e.key === "Escape") { hideMenu(); }
});

targetEl.querySelectorAll<HTMLButtonElement>("button").forEach((b) => {
  b.onclick = () => {
    writeTarget((b.dataset.v as "all" | "main" | "extra"));
    syncTargetButtons();
  };
});

cancelBtn.onclick = () => hideMenu();
sendBtn.onclick = () => send();

function send() {
  const text = input.value.trim();
  if (!text) return;
  // Save as a new preset (dedupe, most-recent-first).
  const next = [text, ...readPresets().filter((x) => x !== text)];
  writePresets(next);
  const target = readTarget();
  void emit("quick-bubble", { text, target });
  hideMenu();
}

// Dismiss menu on outside click / Escape.
document.addEventListener("mousedown", (e) => {
  if (menu.hidden) return;
  if (!menu.contains(e.target as Node) && !ball.contains(e.target as Node)) hideMenu();
});
window.addEventListener("keydown", (e) => { if (e.key === "Escape" && !menu.hidden) hideMenu(); });

// ---- live updates ----------------------------------------------------------
listen("bubble-changed", () => paintPresets());
listen<Lang>("lang-changed", (e) => { setLang(e.payload); applyLangStrings(); paintPresets(); });

applyLangStrings();
syncTargetButtons();
paintPresets();
syncSend();
