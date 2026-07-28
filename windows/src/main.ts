import { listen, emit } from "@tauri-apps/api/event";
import { invoke } from "@tauri-apps/api/core";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { Pet } from "./pet";
import { SessionStore, aggregateMood, basename, type AgentEventPayload } from "./state";
import { BubbleRenderer } from "./bubble";
import { loadCatalog, savedSlug, saveSlug, getLibrary, libraryUrlForSlug } from "./catalog";
import { t, setLang, type Lang } from "./i18n";
import { bubbleLines, PET_CHAT } from "./activity";
import * as care from "./care";
import * as sync from "./sync";
import * as usage from "./usage";
import * as history from "./history";
import * as reactive from "./reactive";
import * as projectpets from "./projectpets";
import { initRoam, setDragging, setMood, getRoamMode } from "./roam";

// Which project THIS pet window represents. `null` = the main window (the
// default single pet). Split-pet spawns extra windows with `?project=<id>`.
const MY_PROJECT = new URLSearchParams(location.search).get("project");
const IS_MAIN = MY_PROJECT === null;

// Pure-decoration pet window: spawned by Settings → "Spawn extra pet". Such a
// window loads `?extra=<slug>` and short-circuits ALL agent/care/tray logic ,
// it just floats and roams. Multiple may be open at once.
const EXTRA_SLUG = new URLSearchParams(location.search).get("extra");
const IS_EXTRA = EXTRA_SLUG !== null;

// This window's Tauri label (pet, pet-<project>, pet-extra-<slug>-<n>). Used
// for per-window hit-rect registration and per-window config overrides.
const MY_LABEL = getCurrentWindow().label;

// A project window sets this the moment its project is un-split, so it stops
// feeding during the brief async gap before Rust closes it (else the main window
// , which now owns the project , and this dying window would both feed one event).
let windowDead = false;

/// Does this window own a session (feed its pet, count it, notify)? Split off:
/// the main window owns everything. Split on: a project window owns only its
/// project; the main window owns every unconfigured project.
function ownsProject(path: string): boolean {
  if (windowDead) return false;
  if (!projectpets.splitEnabled()) return IS_MAIN;
  const id = usage.projectId(path || "");
  if (MY_PROJECT) return id === MY_PROJECT;
  return !projectpets.configuredProjectIds().includes(id);
}

/// The pet slug this window raises (a project window uses its mapped pet).
function myPetSlug(): string | null {
  if (MY_PROJECT && projectpets.splitEnabled()) return projectpets.petForProject(MY_PROJECT) || savedSlug();
  return savedSlug();
}

/// Reconcile the per-project pet windows with the current config (main only).
function syncProjectWindows() {
  const ids = projectpets.splitEnabled() ? projectpets.configuredProjectIds() : [];
  void invoke("sync_project_windows", { projects: ids });
}
import { sendNotification, isPermissionGranted, requestPermission } from "@tauri-apps/plugin-notification";
import { check } from "@tauri-apps/plugin-updater";
import { relaunch } from "@tauri-apps/plugin-process";

// Auto-update on launch (no-op offline / when no signed release is published).
// Main window only , the per-project windows share the same binary.
if (IS_MAIN) (async () => {
  try {
    const update = await check();
    if (update) {
      await update.downloadAndInstall();
      await relaunch();
    }
  } catch {}
})();

const canvas = document.getElementById("pet") as HTMLCanvasElement;
const bubbleEl = document.getElementById("bubble") as HTMLDivElement;
const pet = new Pet(canvas);
const store = new SessionStore();
const bubble = new BubbleRenderer(bubbleEl);
initRoam(pet);

// --- bubble appearance (theme / opacity / fonts) ------------------------------
const FONT_FAMILIES: Record<string, string> = {
  system: '"Segoe UI", system-ui, sans-serif',
  rounded: '"Segoe UI Rounded", "Nunito", "Segoe UI", sans-serif',
  mono: 'Consolas, "Courier New", monospace',
};

function applyBubble() {
  let theme = localStorage.getItem("ap_theme") || "dark";
  if (theme === "system") theme = matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark";
  const op = (parseInt(localStorage.getItem("ap_opacity") || "92", 10) || 92) / 100;
  const r = document.documentElement.style;
  if (theme === "light") {
    r.setProperty("--bubble-bg", `rgba(255,255,255,${op})`);
    r.setProperty("--bubble-fg", "#1a1d2e");
    r.setProperty("--bubble-border", "rgba(0,0,0,0.08)");
  } else {
    r.setProperty("--bubble-bg", `rgba(22,24,38,${op})`);
    r.setProperty("--bubble-fg", "#ffffff");
    r.setProperty("--bubble-border", "rgba(255,255,255,0.10)");
  }
  r.setProperty("--bubble-font-size", `${parseInt(localStorage.getItem("ap_font_size") || "12", 10) || 12}px`);
  r.setProperty("--bubble-font-family", FONT_FAMILIES[localStorage.getItem("ap_font_family") || "system"] ?? FONT_FAMILIES.system);
}
applyBubble();

// Pet size + idle bob FX. Sized via layout (not transform) so the bubble
// always sits above the sprite instead of being painted over by it. Per-window
// override (`ap_win_<label>_pet_size`) wins over the global setting, so each
// extra pet can have its own size independently.
function applyPet() {
  const winSize = localStorage.getItem(`ap_win_${MY_LABEL}_pet_size`);
  const size = (parseInt(winSize || localStorage.getItem("ap_pet_size") || "100", 10) || 100) / 100;
  canvas.style.width = `${Math.round(160 * size)}px`;
  canvas.style.height = `${Math.round(180 * size)}px`;
  canvas.classList.toggle("bob", localStorage.getItem("ap_fx") === "1");
}
applyPet();

// Simple synthesized chimes (no audio assets needed). Per-event enable, like
// the macOS SoundSettings (done = high glass-ish, waiting = lower submarine).
let audioCtx: AudioContext | null = null;
function chime(event: "done" | "waiting") {
  const key = event === "done" ? "ap_sound_done" : "ap_sound_waiting";
  const legacy = localStorage.getItem("ap_sound"); // pre-split toggle
  const enabled = localStorage.getItem(key) ?? (legacy === "0" ? "0" : "1");
  if (enabled === "0") return;
  // Custom uploaded sound wins (mac SoundSettings custom file).
  const data = localStorage.getItem(`ap_sound_${event}_data`);
  if (data) {
    try { void new Audio(data).play(); return; } catch {}
  }
  try {
    audioCtx = audioCtx || new AudioContext();
    const o = audioCtx.createOscillator();
    const g = audioCtx.createGain();
    o.type = "sine";
    o.frequency.value = event === "done" ? 880 : 560;
    g.gain.value = 0.05;
    o.connect(g);
    g.connect(audioCtx.destination);
    o.start();
    o.stop(audioCtx.currentTime + 0.13);
  } catch {}
}

// --- pick + load a pet sprite -------------------------------------------------
(async () => {
  // Pure-decoration window: load the slug the user picked in Settings. The
  // library is in localStorage so it's available immediately.
  if (IS_EXTRA && EXTRA_SLUG) {
    const lib = getLibrary();
    const p = lib.find((x) => x.slug === EXTRA_SLUG);
    if (p?.url) { pet.load(p.url); return; }
    // Library entry vanished (user removed it) , nothing to render.
    return;
  }
  // A project window raises its mapped pet; the main window the selected one.
  if (MY_PROJECT) {
    const slug = projectpets.petForProject(MY_PROJECT);
    const url = slug ? projectpets.libUrlForSlug(slug) : null;
    if (url) { pet.load(url); return; }
  }
  // Library selection (Browse/Create) wins; legacy ap_pet_custom still honoured.
  const customUrl = localStorage.getItem("ap_pet_custom");
  if (customUrl) { pet.load(customUrl); return; }
  const explicitUrl = localStorage.getItem("ap_pet_url") || libraryUrlForSlug(savedSlug());
  if (explicitUrl) { pet.load(explicitUrl); return; }
  // First run / user cleared selection: pick a starter from the catalog and
  // persist it so Settings shows the same default instead of a blank choice.
  for (;;) {
    const pets = await loadCatalog();
    if (pets.length) {
      const slug = savedSlug();
      const chosen = pets.find((p) => p.slug === slug) ?? pets[Math.floor(pets.length / 2)];
      saveSlug(chosen.slug);
      localStorage.setItem("ap_pet_url", chosen.spritesheetUrl);
      pet.load(chosen.spritesheetUrl);
      return;
    }
    await new Promise((r) => setTimeout(r, 15000));
  }
})();

// --- mood + render loop --------------------------------------------------------
// Port of PetController: aggregate mood, 3s celebrate burst on entering done,
// a persistent idle line (re-picked on mood transitions, not blinking), and
// the structured multi-agent bubble while agents are active.
let lastResolved = "idle";
let celebrateUntil = 0;
let wasCelebrating = false;
let prevSimpleMood = "";
let moodLine = ""; // the single-bubble line for idle/done/celebrate
let reactiveLine = "";
let reactiveUntil = 0;

// Quick bubble: a short-lived message shown when the user clicks a pet or
// sends from the floating ball. Overrides the mood bubble for ~4s, then the
// normal render loop takes over again.
const QUICK_BUBBLE_MS = 4000;
const QUICK_KEY = "ap_quick_bubbles";
let quickBubbleText = "";
let quickBubbleUntil = 0;

function readQuickPresets(): string[] {
  try {
    const v = JSON.parse(localStorage.getItem(QUICK_KEY) || "[]");
    return Array.isArray(v) ? v.filter((x: unknown) => typeof x === "string" && x.trim()) : [];
  } catch { return []; }
}
function randomPreset(): string | null {
  const list = readQuickPresets();
  if (!list.length) return null;
  return list[Math.floor(Math.random() * list.length)];
}
function showQuickBubble(text: string) {
  quickBubbleText = text;
  quickBubbleUntil = Date.now() + QUICK_BUBBLE_MS;
  render();
}
/// Does this pet window belong to the given broadcast target?
/// - "all": every pet window (main, project-split, extra)
/// - "main": non-extra windows (the agent-tracking pets)
/// - "extra": pure-decoration extra pet windows only
function matchesTarget(target: "all" | "main" | "extra"): boolean {
  if (target === "all") return true;
  if (target === "extra") return IS_EXTRA;
  return !IS_EXTRA;
}

/// Show a reactive comment for a few seconds (mac PetController.flashReactiveLine).
function flashReactive(line: string | null) {
  if (!line) return;
  reactiveLine = line;
  reactiveUntil = Date.now() + 5000;
}

/// Evaluate the care-driven reactive metrics after a feed / meal / hunger tick.
function evaluateCareMetrics() {
  const slug = myPetSlug();
  if (!slug) return;
  const s = care.stateFor(slug);
  flashReactive(reactive.evaluate("dailyTokens", s.tokensToday));
  flashReactive(reactive.evaluate("streak", s.streakDays));
  flashReactive(reactive.evaluate("dailyMeals", s.mealsToday));
  flashReactive(reactive.evaluate("hunger", care.hunger(s)));
}

function pickMoodLine(mood: string) {
  // Custom/system pools; working/waiting fall back to the PetChat lines so the
  // simple-bubble mode (multi-agent off) always has something to say.
  let pool = bubbleLines(null, mood);
  if (!pool.length) pool = PET_CHAT[mood] ?? [];
  moodLine = pool.length ? pool[Math.floor(Math.random() * pool.length)] : "";
}

function render() {
  if (IS_EXTRA) { renderExtra(); return; }
  // Quick bubble overrides everything for a few seconds after the user sends
  // a message from the floating ball or clicks the pet.
  if (Date.now() < quickBubbleUntil) {
    bubble.renderLine(quickBubbleText);
    snugBubble();
    reportHitRect();
    return;
  }
  const sessions = store.active().filter((s) => ownsProject(s.project));
  const resolved = aggregateMood(sessions);

  if (resolved === "done" && lastResolved !== "done") {
    celebrateUntil = Date.now() + 3000; // celebrate burst, like macOS
    pickMoodLine("celebrate");
  }
  if (resolved !== lastResolved && Date.now() >= celebrateUntil) {
    if (resolved === "idle") pickMoodLine("idle");
    else if (resolved === "done") pickMoodLine("done");
  }
  lastResolved = resolved;

  const celebrating = Date.now() < celebrateUntil;
  if (wasCelebrating && !celebrating) {
    // The 3s burst ended , settle into the actual mood's line (mac
    // settleAfterCelebrate re-picks on the celebrate→done transition).
    pickMoodLine(resolved === "idle" ? "idle" : "done");
  }
  wasCelebrating = celebrating;
  const mood = celebrating ? "celebrate" : resolved;
  pet.setState(mood);
  // Keep the roam engine in sync: pause on waiting/celebrate, doze on idle.
  setMood(mood);

  // A reactive comment briefly overrides the quiet single-line moods (not the
  // multi-agent working bubble, not the celebrate burst).
  const reactiveActive = Date.now() < reactiveUntil && !!reactiveLine;

  const multi = localStorage.getItem("ap_multi") !== "0";
  if ((mood === "working" || mood === "waiting") && !multi) {
    // Simple-bubble mode (mac: multi-agent off) , one plain chat line.
    if (resolved !== prevSimpleMood) { pickMoodLine(mood); prevSimpleMood = resolved; }
    if (!moodLine) pickMoodLine(mood);
    bubble.renderLine(reactiveActive ? reactiveLine : moodLine);
  } else if (mood === "working" || mood === "waiting") {
    bubble.render(sessions.filter((s) => s.state !== "idle" && s.state !== "registered"));
  } else if (mood === "celebrate") {
    bubble.renderLine(moodLine || t("Done"));
  } else if (mood === "done") {
    if (!moodLine) pickMoodLine("done");
    bubble.renderLine(reactiveActive ? reactiveLine : moodLine);
  } else {
    // idle: a persistent quiet line (mac shows it continuously, no blinking)
    if (reactiveActive) {
      bubble.renderLine(reactiveLine);
    } else if (localStorage.getItem("ap_idle") !== "0") {
      if (!moodLine) pickMoodLine("idle");
      bubble.renderLine(moodLine);
    } else {
      bubble.hide();
    }
  }

  snugBubble();
  reportHitRect();
  // One global tray icon , the main window reports it, counting ALL sessions
  // (not just this window's owned subset).
  if (IS_MAIN) reportTrayStatus(store.active());
}

/// Pure-decoration window render: idle mood, no bubble, no tray report. The
/// roam engine (initialized below) handles all movement independently.
function renderExtra(): void {
  pet.setState("idle");
  setMood("idle");
  if (Date.now() < quickBubbleUntil) {
    bubble.renderLine(quickBubbleText);
  } else {
    bubble.hide();
  }
  snugBubble();
  reportHitRect();
}
setInterval(render, 500);
// Hunger decays over time, so evaluate it on a timer (not only after feeding,
// when the pet is always full) , matching macOS's state-republish trigger.
setInterval(() => {
  const slug = myPetSlug();
  if (slug) flashReactive(reactive.evaluate("hunger", care.hunger(care.stateFor(slug))));
}, 60_000);
// Carousel advance / fold clicks request a prompt repaint.
setInterval(() => { if (bubble.dirty) { bubble.dirty = false; render(); } }, 120);
// Live elapsed clocks tick every second.
setInterval(() => bubble.tickClocks(), 1000);

// Pull the bubble down over the canvas's empty headroom so it sits right
// above the pet's head (the sprite rarely fills the whole canvas height).
function snugBubble() {
  const gap = Math.max(0, canvas.clientHeight * pet.headroom - 4);
  bubbleEl.style.transform = `translateY(${gap}px)`;
}

// Tray tooltip mirrors the macOS menu bar count (N working / N waiting).
let lastTray = "";
function reportTrayStatus(sessions: ReturnType<SessionStore["active"]>) {
  const working = sessions.filter((s) => s.state === "working").length;
  const waiting = sessions.filter((s) => s.state === "waiting").length;
  const sig = `${working}/${waiting}`;
  if (sig === lastTray) return;
  lastTray = sig;
  invoke("set_tray_status", { working, waiting }).catch(() => {});
}

// --- notifications ------------------------------------------------------------
let notifyReady = false;
(async () => {
  try { notifyReady = (await isPermissionGranted()) || (await requestPermission()) === "granted"; } catch {}
})();
const lastState = new Map<string, string>();
const sessionStarts = new Map<string, number>();
function maybeNotify(e: AgentEventPayload) {
  const key = `${e.agent}:${e.session}`;
  const prev = lastState.get(key);
  lastState.set(key, e.state);
  if (!sessionStarts.has(key) && (e.state === "working" || e.state === "registered")) {
    sessionStarts.set(key, Date.now());
  }
  if (e.state === prev) return;
  // A finished session is a "meal" for THIS window's pet , only the window that
  // owns the project records it, so split pets never double-feed.
  if (e.state === "done" && ownsProject(e.project)) {
    const slug = myPetSlug();
    if (slug) { care.mutate(slug, (s) => care.recordMeal(s)); emit("care-updated"); sync.schedulePush(); evaluateCareMetrics(); }
    if (e.project) usage.recordSession(e.project, e.agent);
    const now = Date.now();
    history.log({
      id: e.session, agent: e.agent, project: e.project ? basename(e.project) : "",
      title: e.title || "", startedAt: sessionStarts.get(key) ?? now, endedAt: now,
    });
  }
  // Chimes + notifications fire once , the main window only.
  if (!IS_MAIN) return;
  if (e.state !== "done" && e.state !== "waiting") return;
  chime(e.state === "done" ? "done" : "waiting");
  if (!notifyReady || localStorage.getItem("ap_notify") === "0") return;
  const proj = (e.project ? basename(e.project) : "") || e.agent;
  // Same copy as the macOS notifications.
  const title = e.state === "done" ? `${proj} ${t("finished")}` : `${proj} ${t("needs input")}`;
  const body = e.state === "done"
    ? t("Agent completed its turn")
    : (e.message || t("Waiting for you"));
  try { sendNotification({ title, body }); } catch {}
}

// --- agent events from the Rust listener -------------------------------------
// Pure-decoration windows skip all of this , they don't track agents or feed.
if (!IS_EXTRA) {
listen<AgentEventPayload>("agent-event", (e) => {
  maybeNotify(e.payload);
  store.update(e.payload);
  const owned = store.active().filter((s) => ownsProject(s.project)).length;
  flashReactive(reactive.evaluate("sessionCount", owned));
  render();
});
// Approval gate: the daemon parked a gated PreToolUse , show Allow/Deny.
listen<{ id: string; session: string; tool: string; summary: string }>("agent-approval", (e) => {
  const p = e.payload;
  store.setApproval(p.session, { id: p.id, tool: p.tool, summary: p.summary });
  render();
});
listen<{ id: string; session: string }>("agent-approval-resolved", (e) => {
  store.clearApproval(e.payload.session);
  render();
});
listen<string>("agent-end", (e) => {
  for (const k of [...lastState.keys()]) if (k.endsWith(`:${e.payload}`)) lastState.delete(k);
  for (const k of [...sessionStarts.keys()]) if (k.endsWith(`:${e.payload}`)) sessionStarts.delete(k);
  store.remove(e.payload);
  render();
});
// Tokens burned by an agent feed THIS window's pet , only the owning window, so
// split pets never double-feed the same tokens.
listen<{ agent: string; session: string; project: string; tokens: number; cost?: number }>("agent-tokens", (e) => {
  const n = e.payload?.tokens || 0;
  if (n <= 0) return;
  const p = e.payload;
  if (!ownsProject(p.project)) return;
  if (p.project) usage.recordTokens(p.project, p.agent, n, p.cost || 0);
  const slug = myPetSlug();
  if (!slug) return;
  care.mutate(slug, (s) => care.feedTokens(s, n));
  emit("care-updated");
  sync.schedulePush();
  evaluateCareMetrics();
});

// On launch: pull any cloud progress, then keep pushing in the background. The
// main window owns cloud sync (care state is shared across windows).
if (IS_MAIN && sync.signedIn()) {
  sync.restore().then(() => { emit("care-updated"); sync.schedulePush(5000); }).catch(() => {});
  usage.schedulePush(8000);
}
// Split-pet: the main window spawns/closes the per-project pet windows, and
// re-syncs whenever Settings changes the config.
if (IS_MAIN) {
  syncProjectWindows();
  listen("split-changed", () => syncProjectWindows());
} else {
  // A project window: once split is off or its project is no longer configured,
  // it's about to be closed , stop owning events immediately to avoid a
  // double-feed with the main window during teardown.
  listen("split-changed", () => {
    if (!projectpets.splitEnabled() || (MY_PROJECT && !projectpets.configuredProjectIds().includes(MY_PROJECT))) {
      windowDead = true;
    }
  });
}
// Settings window: dismiss one session / clear all (mac popover actions).
listen<string>("session-dismiss", (e) => { store.removeKey(e.payload); render(); });
listen("sessions-clear", () => { store.clear(); render(); });
// A freshly opened Settings window asks for the current sessions.
listen("sessions-request", () => {
  for (const s of store.snapshot()) emit("session-snapshot", s);
});
// Pet changed from the Settings window.
listen<{ slug: string | null; url: string | null }>("set-pet", async (e) => {
  if (e.payload.url) {
    pet.load(e.payload.url);
    if (e.payload.slug) saveSlug(e.payload.slug);
    localStorage.setItem("ap_pet_url", e.payload.url);
    return;
  }
  // User cleared the explicit choice: reload the catalog default so the window
  // never ends up with no sprite.
  localStorage.removeItem("ap_pet_url");
  localStorage.removeItem("ap_pet_custom");
  for (;;) {
    const pets = await loadCatalog();
    if (pets.length) {
      const slug = savedSlug();
      const chosen = pets.find((p) => p.slug === slug) ?? pets[Math.floor(pets.length / 2)];
      saveSlug(chosen.slug);
      localStorage.setItem("ap_pet_url", chosen.spritesheetUrl);
      pet.load(chosen.spritesheetUrl);
      return;
    }
    await new Promise((r) => setTimeout(r, 15000));
  }
});
} // end if (!IS_EXTRA)
// Language changed from Settings , re-render the bubble in the new language.
listen<Lang>("lang-changed", (e) => { setLang(e.payload); render(); });
// Bubble theme / opacity / messages changed from Settings.
listen("bubble-changed", () => { applyBubble(); applyPet(); moodLine = ""; render(); });

// Floating ball broadcast: show the same message on every matching pet window
// for a few seconds. target=all/main/extra filters which pets respond.
listen<{ text: string; target: "all" | "main" | "extra" }>("quick-bubble", (e) => {
  if (!matchesTarget(e.payload.target)) return;
  showQuickBubble(e.payload.text);
});

// --- interactions ------------------------------------------------------------
// Drag works only when grabbing the PET SPRITE itself or the bubble , clicks
// on the transparent area beside the pet fall through (like the macOS panel,
// where transparent pixels never catch the mouse).
//
// Click vs drag: we don't startDragging on mousedown immediately. Instead we
// wait for the cursor to move > 4px , only then start the OS drag. If the
// mouse is released before moving, it's a click and we trigger a quick bubble
// (configurable via `ap_left_click_action`). This is necessary because Tauri's
// startDragging swallows the mouseup, so a `click` event never fires.
const LEFT_CLICK_KEY = "ap_left_click_action";
let pendingDrag = false;
let downX = 0;
let downY = 0;

function onPetClick() {
  const action = (localStorage.getItem(LEFT_CLICK_KEY) || "none") as "none" | "self" | "all";
  if (action === "none") return;
  const text = randomPreset();
  if (!text) return;
  if (action === "self") {
    showQuickBubble(text);
  } else {
    emit("quick-bubble", { text, target: "all" });
  }
}

canvas.addEventListener("mousedown", (e) => {
  if (e.button !== 0) return;
  // While the sheet is still loading there is no sprite rect yet , allow the
  // drag anyway so the pet is never untouchable.
  if (pet.spriteRect && !pet.hitTest(e.offsetX, e.offsetY)) return;
  emit("popover-close", null);
  pendingDrag = true;
  downX = e.screenX;
  downY = e.screenY;
});
window.addEventListener("mousemove", (e) => {
  if (!pendingDrag) return;
  if (Math.abs(e.screenX - downX) <= 4 && Math.abs(e.screenY - downY) <= 4) return;
  pendingDrag = false;
  setDragging(true);
  getCurrentWindow().startDragging().finally(() => setDragging(false));
});
window.addEventListener("mouseup", () => {
  if (!pendingDrag) return;
  pendingDrag = false;
  onPetClick();
});
bubbleEl.addEventListener("mousedown", async (e) => {
  if (e.button !== 0) return;
  emit("popover-close", null);
  setDragging(true);
  try {
    await getCurrentWindow().startDragging();
  } finally {
    setDragging(false);
  }
});
canvas.addEventListener("contextmenu", (e) => {
  e.preventDefault();
  // No hitTest here: if the event fired at all, the cursor is on an opaque
  // region (Rust's click-through makes transparent areas pass-through). The
  // sprite may have moved during roaming, so hitTest would be unreliable and
  // would make right-click miss while the pet is wandering.
  if (IS_EXTRA) showExtraCtxMenu(e.clientX, e.clientY);
  else invoke("open_popover").catch(() => {});
});
bubbleEl.addEventListener("contextmenu", (e) => {
  e.preventDefault();
  if (IS_EXTRA) showExtraCtxMenu(e.clientX, e.clientY);
  else invoke("open_popover").catch(() => {});
});

// --- extra-pet right-click context menu --------------------------------------
// Extra pets have no popover (no agent state to show). Instead, right-click
// gives quick per-pet controls: close, roam mode, size. Each setting is stored
// per-window so one extra pet can wander while another stays, etc.
let ctxMenu: HTMLDivElement | null = null;

function hideCtxMenu(): void {
  if (ctxMenu) { ctxMenu.remove(); ctxMenu = null; }
}

function showExtraCtxMenu(x: number, y: number): void {
  hideCtxMenu();
  const m = document.createElement("div");
  m.className = "ctx-menu";

  const closeBtn = document.createElement("button");
  closeBtn.className = "ctx-item ctx-close";
  closeBtn.textContent = "✕ Close";
  closeBtn.onclick = () => { hideCtxMenu(); getCurrentWindow().close(); };
  m.appendChild(closeBtn);

  m.appendChild(sep());

  const roamHead = document.createElement("div");
  roamHead.className = "ctx-label";
  roamHead.textContent = "Roam";
  m.appendChild(roamHead);
  const currentMode = getRoamMode();
  for (const [mode, label] of [
    ["stay", "Stay"], ["wander", "Wander"], ["cursor", "Follow cursor"], ["climb", "Climb"],
  ] as const) {
    const btn = document.createElement("button");
    btn.className = "ctx-item";
    if (mode === currentMode) btn.classList.add("sel");
    btn.textContent = label;
    btn.onclick = () => {
      localStorage.setItem(`ap_win_${MY_LABEL}_roam_mode`, mode);
      hideCtxMenu();
    };
    m.appendChild(btn);
  }

  m.appendChild(sep());

  const sizeHead = document.createElement("div");
  sizeHead.className = "ctx-label";
  sizeHead.textContent = "Size";
  m.appendChild(sizeHead);
  const currentSize = parseInt(
    localStorage.getItem(`ap_win_${MY_LABEL}_pet_size`) || localStorage.getItem("ap_pet_size") || "100",
    10,
  );
  for (const [val, label] of [["80", "S"], ["100", "M"], ["125", "L"]] as const) {
    const btn = document.createElement("button");
    btn.className = "ctx-item";
    if (parseInt(val) === currentSize) btn.classList.add("sel");
    btn.textContent = label;
    btn.onclick = () => {
      localStorage.setItem(`ap_win_${MY_LABEL}_pet_size`, val);
      applyPet();
      reportHitRect();
      hideCtxMenu();
    };
    m.appendChild(btn);
  }

  // Position at cursor, clamped so the menu never overflows the window.
  m.style.left = `${Math.min(x, window.innerWidth - 180)}px`;
  m.style.top = `${Math.min(y, window.innerHeight - 320)}px`;
  document.body.appendChild(m);
  ctxMenu = m;

  // Dismiss on click outside or Escape. The setTimeout avoids the very
  // contextmenu event that opened the menu from immediately closing it.
  // The `ctxMenu === m` guard prevents a stale listener (from a previous
  // menu) from closing a newer menu that replaced it.
  setTimeout(() => {
    const onDown = (ev: MouseEvent) => {
      if (ctxMenu === m && !m.contains(ev.target as Node)) hideCtxMenu();
      document.removeEventListener("mousedown", onDown);
    };
    document.addEventListener("mousedown", onDown);
  }, 0);
  const onKey = (ev: KeyboardEvent) => {
    if (ev.key === "Escape" && ctxMenu === m) hideCtxMenu();
    document.removeEventListener("keydown", onKey);
  };
  document.addEventListener("keydown", onKey);
}

function sep(): HTMLDivElement {
  const d = document.createElement("div");
  d.className = "ctx-sep";
  return d;
}

// Report the interactive region (physical px) for Windows click-through: the
// union of the SPRITE's true bounds and the visible bubble , not the whole
// canvas, so the empty space beside the pet passes clicks to apps below.
// Every pet window (main, project, extra) registers under its own label so
// the Rust loop can manage click-through independently per window.
const petRoot = document.getElementById("pet-root") as HTMLElement;
let lastHitSig = "";
function reportHitRect() {
  const d = window.devicePixelRatio || 1;
  const rects: { left: number; top: number; right: number; bottom: number }[] = [];
  if (!bubbleEl.hidden) {
    const b = bubbleEl.getBoundingClientRect();
    if (b.width > 0) rects.push({ left: b.left, top: b.top, right: b.right, bottom: b.bottom });
  }
  const cr = canvas.getBoundingClientRect();
  const sr = pet.spriteRect;
  if (sr && canvas.width > 0) {
    const kx = cr.width / canvas.width;
    const ky = cr.height / canvas.height;
    rects.push({
      left: cr.left + sr.x * kx,
      top: cr.top + sr.y * ky,
      right: cr.left + (sr.x + sr.w) * kx,
      bottom: cr.top + (sr.y + sr.h) * ky,
    });
  } else {
    rects.push({ left: cr.left, top: cr.top, right: cr.right, bottom: cr.bottom });
  }
  const left = Math.min(...rects.map((r) => r.left));
  const top = Math.min(...rects.map((r) => r.top));
  const right = Math.max(...rects.map((r) => r.right));
  const bottom = Math.max(...rects.map((r) => r.bottom));
  const sig = [left, top, right, bottom].map((v) => Math.round(v)).join(",");
  if (sig === lastHitSig) return;
  lastHitSig = sig;
  invoke("set_hit_rect", { label: MY_LABEL, x: left * d, y: top * d, w: (right - left) * d, h: (bottom - top) * d })
    .catch((err) => invoke("log_debug", { msg: `set_hit_rect failed: ${err}` }).catch(() => {}));
}
new ResizeObserver(reportHitRect).observe(petRoot);
window.addEventListener("resize", reportHitRect);
reportHitRect();

render();
