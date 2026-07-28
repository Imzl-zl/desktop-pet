import { listen, emit } from "@tauri-apps/api/event";
import { invoke } from "@tauri-apps/api/core";
import { Pet } from "./pet";
import { SessionStore, aggregateMood, basename, type AgentEventPayload, type Session } from "./state";
import { BubbleRenderer, invalidateBubbleConfig, elapsedString } from "./bubble";
import { loadCatalog, savedSlug, saveSlug, getLibrary, libraryUrlForSlug } from "./catalog";
import { t, setLang, type Lang } from "./i18n";
import { bubbleLines, PET_CHAT } from "./activity";
import * as care from "./care";
import * as sync from "./sync";
import * as usage from "./usage";
import * as history from "./history";
import * as reactive from "./reactive";
import * as projectpets from "./projectpets";
import { getRoamMode, type RoamMode } from "./roam";
import { agentIconUrl } from "./icons";
import { sendNotification, isPermissionGranted, requestPermission } from "@tauri-apps/plugin-notification";
import { check } from "@tauri-apps/plugin-updater";
import { relaunch, exit } from "@tauri-apps/plugin-process";

const petsLayer = document.getElementById("pets-layer")!;
const ballLayer = document.getElementById("ball-layer")!;
const popoverLayer = document.getElementById("popover-layer")!;

/// True while the stage overlay is on screen. When the pet is hidden (tray
/// toggle / occluded), the high-frequency loops below stop touching the DOM or
/// crossing the IPC bridge so a hidden overlay costs ~nothing.
let stageVisible = true;

const FONT_FAMILIES: Record<string, string> = {
  system: '"Segoe UI", system-ui, sans-serif',
  rounded: '"Segoe UI Rounded", "Nunito", "Segoe UI", sans-serif',
  mono: 'Consolas, "Courier New", monospace',
};

function applyBubble(root: HTMLElement) {
  let theme = localStorage.getItem("ap_theme") || "dark";
  if (theme === "system") theme = matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark";
  const op = (parseInt(localStorage.getItem("ap_opacity") || "92", 10) || 92) / 100;
  const r = root.style;
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

let audioCtx: AudioContext | null = null;
function chime(event: "done" | "waiting") {
  const key = event === "done" ? "ap_sound_done" : "ap_sound_waiting";
  const legacy = localStorage.getItem("ap_sound");
  const enabled = localStorage.getItem(key) ?? (legacy === "0" ? "0" : "1");
  if (enabled === "0") return;
  const data = localStorage.getItem(`ap_sound_${event}_data`);
  if (data) { try { void new Audio(data).play(); return; } catch {} }
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

interface PetEntity {
  id: string;
  root: HTMLDivElement;
  canvas: HTMLCanvasElement;
  bubbleEl: HTMLDivElement;
  pet: Pet;
  bubble: BubbleRenderer;
  x: number;
  y: number;
  store: SessionStore;
  label: string;
  isMain: boolean;
  projectId: string | null;
  extraSlug: string | null;
  moodLine: string;
  reactiveLine: string;
  reactiveUntil: number;
  quickText: string;
  quickUntil: number;
  celebrateUntil: number;
  wasCelebrating: boolean;
  lastResolved: string;
  prevSimpleMood: string;
  renderSig: string;
  lastHitSig: string;
  dragging: boolean;
  roamMode: RoamMode;
  roamVx: number;
  roamVy: number;
  roamTargetX: number;
  roamTargetY: number;
  roamNextChange: number;
  cursorX: number;
  cursorY: number;
}

function createPetEntity(id: string, opts: { x: number; y: number; label: string; isMain?: boolean; projectId?: string | null; extraSlug?: string | null }): PetEntity {
  const root = document.createElement("div");
  root.className = "pet-entity";
  root.style.position = "absolute";
  root.style.left = `${opts.x}px`;
  root.style.top = `${opts.y}px`;
  root.style.display = "flex";
  root.style.flexDirection = "column";
  root.style.alignItems = "center";
  root.style.gap = "4px";

  const bubbleEl = document.createElement("div");
  bubbleEl.className = "bubble";
  bubbleEl.hidden = true;

  const canvas = document.createElement("canvas");
  canvas.width = 160;
  canvas.height = 180;
  canvas.id = `pet-${id}`;
  canvas.style.imageRendering = "pixelated";
  canvas.style.cursor = "grab";

  root.appendChild(bubbleEl);
  root.appendChild(canvas);
  petsLayer.appendChild(root);

  applyBubble(root);

  const entity: PetEntity = {
    id,
    root,
    canvas,
    bubbleEl,
    pet: new Pet(canvas),
    bubble: new BubbleRenderer(bubbleEl),
    x: opts.x,
    y: opts.y,
    store: new SessionStore(),
    label: opts.label,
    isMain: opts.isMain ?? false,
    projectId: opts.projectId ?? null,
    extraSlug: opts.extraSlug ?? null,
    moodLine: "",
    reactiveLine: "",
    reactiveUntil: 0,
    quickText: "",
    quickUntil: 0,
    celebrateUntil: 0,
    wasCelebrating: false,
    lastResolved: "idle",
    prevSimpleMood: "",
    renderSig: "",
    lastHitSig: "",
    dragging: false,
    roamMode: getRoamMode(opts.label),
    roamVx: 0,
    roamVy: 0,
    roamTargetX: opts.x,
    roamTargetY: opts.y,
    roamNextChange: 0,
    cursorX: opts.x,
    cursorY: opts.y,
  };

  setupPetInteractions(entity);
  loadPetSprite(entity);
  applyPetSize(entity);
  entity.pet.setVisible(stageVisible);
  return entity;
}

function ownsProject(entity: PetEntity, path: string): boolean {
  if (entity.extraSlug) return false;
  const id = usage.projectId(path || "");
  if (entity.isMain) {
    // When split is off the main pet owns everything. When split is on the
    // main pet only owns projects that have no dedicated project pet.
    return !projectpets.splitEnabled() || !projectpets.configuredProjectIds().includes(id);
  }
  return id === entity.projectId;
}

function myPetSlug(entity: PetEntity): string | null {
  if (entity.extraSlug) return entity.extraSlug;
  if (entity.projectId && projectpets.splitEnabled()) {
    return projectpets.petForProject(entity.projectId) || savedSlug();
  }
  const customUrl = localStorage.getItem("ap_pet_custom");
  if (customUrl) return null; // handled by URL
  return savedSlug();
}

async function loadPetSprite(entity: PetEntity) {
  if (entity.extraSlug) {
    const lib = getLibrary();
    const p = lib.find((x) => x.slug === entity.extraSlug);
    if (p?.url) { entity.pet.load(p.url); return; }
    return;
  }
  if (entity.projectId && projectpets.splitEnabled()) {
    const slug = projectpets.petForProject(entity.projectId);
    const url = slug ? projectpets.libUrlForSlug(slug) : null;
    if (url) { entity.pet.load(url); return; }
  }
  const customUrl = localStorage.getItem("ap_pet_custom");
  if (customUrl) { entity.pet.load(customUrl); return; }
  const explicitUrl = localStorage.getItem("ap_pet_url") || libraryUrlForSlug(savedSlug());
  if (explicitUrl) { entity.pet.load(explicitUrl); return; }
  for (;;) {
    const pets = await loadCatalog();
    if (pets.length) {
      const slug = savedSlug();
      const chosen = pets.find((p) => p.slug === slug) ?? pets[Math.floor(pets.length / 2)];
      saveSlug(chosen.slug);
      localStorage.setItem("ap_pet_url", chosen.spritesheetUrl);
      entity.pet.load(chosen.spritesheetUrl);
      return;
    }
    await new Promise((r) => setTimeout(r, 15000));
  }
}

function applyPetSize(entity: PetEntity) {
  const winSize = localStorage.getItem(`ap_win_${entity.label}_pet_size`);
  const size = (parseInt(winSize || localStorage.getItem("ap_pet_size") || "100", 10) || 100) / 100;
  entity.canvas.style.width = `${Math.round(160 * size)}px`;
  entity.canvas.style.height = `${Math.round(180 * size)}px`;
}

function pickMoodLine(entity: PetEntity, mood: string) {
  let pool = bubbleLines(null, mood);
  if (!pool.length) pool = PET_CHAT[mood] ?? [];
  entity.moodLine = pool.length ? pool[Math.floor(Math.random() * pool.length)] : "";
}

function flashReactive(entity: PetEntity, line: string | null) {
  if (!line) return;
  entity.reactiveLine = line;
  entity.reactiveUntil = Date.now() + 5000;
}

function evaluateCareMetrics(entity: PetEntity) {
  const slug = myPetSlug(entity);
  if (!slug || entity.extraSlug) return;
  const s = care.stateFor(slug);
  flashReactive(entity, reactive.evaluate("dailyTokens", s.tokensToday));
  flashReactive(entity, reactive.evaluate("streak", s.streakDays));
  flashReactive(entity, reactive.evaluate("dailyMeals", s.mealsToday));
  flashReactive(entity, reactive.evaluate("hunger", care.hunger(s)));
}

function showQuickBubble(entity: PetEntity, text: string) {
  entity.quickText = text;
  entity.quickUntil = Date.now() + 4000;
  renderEntity(entity);
}

function renderEntity(entity: PetEntity) {
  if (entity.extraSlug) {
    entity.pet.setState("idle");
    if (Date.now() < entity.quickUntil) {
      entity.bubble.renderLine(entity.quickText);
    } else {
      entity.bubble.hide();
    }
    snugBubble(entity);
    reportHitRegions();
    return;
  }

  const now = Date.now();
  if (now < entity.quickUntil) {
    entity.bubble.renderLine(entity.quickText);
    snugBubble(entity);
    reportHitRegions();
    return;
  }

  const sessions = entity.store.active().filter((s) => ownsProject(entity, s.project));
  const resolved = aggregateMood(sessions);

  if (resolved === "done" && entity.lastResolved !== "done") {
    entity.celebrateUntil = now + 3000;
    pickMoodLine(entity, "celebrate");
  }
  if (resolved !== entity.lastResolved && now >= entity.celebrateUntil) {
    if (resolved === "idle") pickMoodLine(entity, "idle");
    else if (resolved === "done") pickMoodLine(entity, "done");
  }
  entity.lastResolved = resolved;

  const celebrating = now < entity.celebrateUntil;
  if (entity.wasCelebrating && !celebrating) {
    pickMoodLine(entity, resolved === "idle" ? "idle" : "done");
  }
  entity.wasCelebrating = celebrating;
  const mood = celebrating ? "celebrate" : resolved;
  entity.pet.setState(mood);

  const reactiveActive = now < entity.reactiveUntil && !!entity.reactiveLine;
  const multi = localStorage.getItem("ap_multi") !== "0";

  const sig = [
    sessions.map((s) => `${s.agent}:${s.state}:${s.updatedAt}:${s.stateSince}:${s.pendingApproval?.id ?? ""}:${s.title}:${s.live}:${s.project}:${s.terminalFocusUrl}`).join(","),
    mood,
    entity.moodLine,
    reactiveActive ? entity.reactiveLine : "",
    celebrating,
    reactiveActive,
    localStorage.getItem("ap_idle") !== "0",
  ].join("|");

  if (sig !== entity.renderSig) {
    entity.renderSig = sig;
    if ((mood === "working" || mood === "waiting") && !multi) {
      if (resolved !== entity.prevSimpleMood) { pickMoodLine(entity, mood); entity.prevSimpleMood = resolved; }
      if (!entity.moodLine) pickMoodLine(entity, mood);
      entity.bubble.renderLine(reactiveActive ? entity.reactiveLine : entity.moodLine);
    } else if (mood === "working" || mood === "waiting") {
      entity.bubble.render(sessions.filter((s) => s.state !== "idle" && s.state !== "registered"));
    } else if (mood === "celebrate") {
      entity.bubble.renderLine(entity.moodLine || t("Done"));
    } else if (mood === "done") {
      if (!entity.moodLine) pickMoodLine(entity, "done");
      entity.bubble.renderLine(reactiveActive ? entity.reactiveLine : entity.moodLine);
    } else {
      if (reactiveActive) {
        entity.bubble.renderLine(entity.reactiveLine);
      } else if (localStorage.getItem("ap_idle") !== "0") {
        if (!entity.moodLine) pickMoodLine(entity, "idle");
        entity.bubble.renderLine(entity.moodLine);
      } else {
        entity.bubble.hide();
      }
    }
    if (entity.isMain) reportTrayStatus(entity.store.active());
  }

  snugBubble(entity);
  reportHitRegions();
}

let lastSnugGap = new Map<string, number>();
function snugBubble(entity: PetEntity) {
  const gap = Math.floor(Math.max(0, entity.canvas.clientHeight * entity.pet.headroom - 4));
  const prev = lastSnugGap.get(entity.id);
  if (prev === gap) return;
  lastSnugGap.set(entity.id, gap);
  entity.bubbleEl.style.transform = `translateY(${gap}px)`;
}

let lastTray = "";
function reportTrayStatus(sessions: Session[]) {
  const working = sessions.filter((s) => s.state === "working").length;
  const waiting = sessions.filter((s) => s.state === "waiting").length;
  const sig = `${working}/${waiting}`;
  if (sig === lastTray) return;
  lastTray = sig;
  invoke("set_tray_status", { working, waiting }).catch(() => {});
}

function setupPetInteractions(entity: PetEntity) {
  let pendingDrag = false;
  let downX = 0;
  let downY = 0;

  entity.canvas.addEventListener("mousedown", (e) => {
    if (e.button !== 0) return;
    if (entity.pet.spriteRect && !entity.pet.hitTest(e.offsetX, e.offsetY)) return;
    emit("popover-close", null);
    pendingDrag = true;
    downX = e.screenX;
    downY = e.screenY;
  });
  window.addEventListener("mousemove", (e) => {
    if (!pendingDrag) return;
    if (Math.abs(e.screenX - downX) <= 4 && Math.abs(e.screenY - downY) <= 4) return;
    pendingDrag = false;
    entity.dragging = true;
    setDragLock(true);
    const startX = entity.x;
    const startY = entity.y;

    const onMove = (ev: MouseEvent) => {
      entity.x = startX + (ev.screenX - downX);
      entity.y = startY + (ev.screenY - downY);
      entity.root.style.left = `${entity.x}px`;
      entity.root.style.top = `${entity.y}px`;
      reportHitRegions();
    };
    const onUp = () => {
      window.removeEventListener("mousemove", onMove);
      window.removeEventListener("mouseup", onUp);
      entity.dragging = false;
      setDragLock(false);
      if (entity.isMain) saveMainPetPos(entity.x, entity.y);
    };
    window.addEventListener("mousemove", onMove);
    window.addEventListener("mouseup", onUp);
  });
  window.addEventListener("mouseup", () => {
    if (!pendingDrag) return;
    pendingDrag = false;
    onPetClick(entity);
  });
  entity.bubbleEl.addEventListener("mousedown", (e) => {
    if (e.button !== 0) return;
    emit("popover-close", null);
    entity.dragging = true;
    setDragLock(true);
    const startX = entity.x;
    const startY = entity.y;
    const onMove = (ev: MouseEvent) => {
      entity.x = startX + (ev.screenX - downX);
      entity.y = startY + (ev.screenY - downY);
      entity.root.style.left = `${entity.x}px`;
      entity.root.style.top = `${entity.y}px`;
      reportHitRegions();
    };
    const onUp = () => {
      window.removeEventListener("mousemove", onMove);
      window.removeEventListener("mouseup", onUp);
      entity.dragging = false;
      setDragLock(false);
      if (entity.isMain) saveMainPetPos(entity.x, entity.y);
    };
    window.addEventListener("mousemove", onMove);
    window.addEventListener("mouseup", onUp);
  });
  entity.canvas.addEventListener("contextmenu", (e) => {
    e.preventDefault();
    if (entity.extraSlug) showExtraCtxMenu(entity, e.clientX + entity.x, e.clientY + entity.y);
    else showPopover();
  });
  entity.bubbleEl.addEventListener("contextmenu", (e) => {
    e.preventDefault();
    if (entity.extraSlug) showExtraCtxMenu(entity, e.clientX + entity.x, e.clientY + entity.y);
    else showPopover();
  });
}

function onPetClick(entity: PetEntity) {
  const action = (localStorage.getItem("ap_left_click_action") || "none") as "none" | "self" | "all";
  if (action === "none") return;
  const text = randomPreset();
  if (!text) return;
  if (action === "self") showQuickBubble(entity, text);
  else emit("quick-bubble", { text, target: "all" });
}

function randomPreset(): string | null {
  try {
    const v = JSON.parse(localStorage.getItem("ap_quick_bubbles") || "[]");
    const list = Array.isArray(v) ? v.filter((x: unknown) => typeof x === "string" && x.trim()) : [];
    return list.length ? list[Math.floor(Math.random() * list.length)] : null;
  } catch { return null; }
}

function saveMainPetPos(x: number, y: number) {
  invoke("save_main_pet_pos", { x, y }).catch(() => {});
}

// Hold the whole stage interactive for the duration of a drag. Without this a
// fast drag can outrun the hit-region update (DOM move → IPC → Rust poll, ~60ms+
// latency); the cursor briefly sits outside the reported region, Rust flips the
// window to click-through, and the drag dies mid-flight. The lock makes the hit
// loop skip its region test and stay interactive until the pointer is released.
function setDragLock(locked: boolean) {
  invoke("set_drag_lock", { locked }).catch(() => {});
}

// ---- entities ----------------------------------------------------------------

const mainPet = createPetEntity("main", { x: 0, y: 0, label: "pet", isMain: true });
const entities = new Map<string, PetEntity>([["main", mainPet]]);

// Load saved position via Rust.
invoke<{ x: number; y: number } | null>("read_main_pet_pos").then((pos) => {
  if (pos) {
    mainPet.x = pos.x;
    mainPet.y = pos.y;
    mainPet.root.style.left = `${pos.x}px`;
    mainPet.root.style.top = `${pos.y}px`;
  }
}).catch(() => {});

listen<{ text: string; target: "all" | "main" | "extra" }>("quick-bubble", (e) => {
  for (const ent of entities.values()) {
    if (e.payload.target === "all") showQuickBubble(ent, e.payload.text);
    else if (e.payload.target === "main" && !ent.extraSlug) showQuickBubble(ent, e.payload.text);
    else if (e.payload.target === "extra" && ent.extraSlug) showQuickBubble(ent, e.payload.text);
  }
});

// ---- agent events ------------------------------------------------------------

const lastState = new Map<string, string>();
const sessionStarts = new Map<string, number>();
let notifyReady = false;
(async () => { try { notifyReady = (await isPermissionGranted()) || (await requestPermission()) === "granted"; } catch {} })();

function maybeNotify(e: AgentEventPayload, ent: PetEntity) {
  const key = `${e.agent}:${e.session}`;
  const prev = lastState.get(key);
  lastState.set(key, e.state);
  if (!sessionStarts.has(key) && (e.state === "working" || e.state === "registered")) sessionStarts.set(key, Date.now());
  if (e.state === prev) return;
  if (e.state === "done" && ownsProject(ent, e.project)) {
    const slug = myPetSlug(ent);
    if (slug) { care.mutate(slug, (s) => care.recordMeal(s)); emit("care-updated"); sync.schedulePush(); evaluateCareMetrics(ent); }
    if (e.project) usage.recordSession(e.project, e.agent);
    const now = Date.now();
    history.log({
      id: e.session, agent: e.agent, project: e.project ? basename(e.project) : "",
      title: e.title || "", startedAt: sessionStarts.get(key) ?? now, endedAt: now,
    });
  }
  if (!ent.isMain) return;
  if (e.state !== "done" && e.state !== "waiting") return;
  chime(e.state === "done" ? "done" : "waiting");
  if (!notifyReady || localStorage.getItem("ap_notify") === "0") return;
  const proj = (e.project ? basename(e.project) : "") || e.agent;
  const title = e.state === "done" ? `${proj} ${t("finished")}` : `${proj} ${t("needs input")}`;
  const body = e.state === "done" ? t("Agent completed its turn") : (e.message || t("Waiting for you"));
  try { sendNotification({ title, body }); } catch {}
}

listen<AgentEventPayload>("agent-event", (e) => {
  for (const ent of entities.values()) {
    if (ent.extraSlug) continue;
    ent.store.update(e.payload);
    maybeNotify(e.payload, ent);
    const owned = ent.store.active().filter((s) => ownsProject(ent, s.project)).length;
    flashReactive(ent, reactive.evaluate("sessionCount", owned));
    renderEntity(ent);
  }
});
listen<{ id: string; session: string; tool: string; summary: string }>("agent-approval", (e) => {
  for (const ent of entities.values()) { if (!ent.extraSlug) ent.store.setApproval(e.payload.session, { id: e.payload.id, tool: e.payload.tool, summary: e.payload.summary }); renderEntity(ent); }
});
listen<{ id: string; session: string }>("agent-approval-resolved", (e) => {
  for (const ent of entities.values()) { if (!ent.extraSlug) ent.store.clearApproval(e.payload.session); renderEntity(ent); }
});
listen<string>("agent-end", (e) => {
  for (const k of [...lastState.keys()]) if (k.endsWith(`:${e.payload}`)) lastState.delete(k);
  for (const k of [...sessionStarts.keys()]) if (k.endsWith(`:${e.payload}`)) sessionStarts.delete(k);
  for (const ent of entities.values()) { if (!ent.extraSlug) ent.store.remove(e.payload); renderEntity(ent); }
});
listen<{ agent: string; session: string; project: string; tokens: number; cost?: number }>("agent-tokens", (e) => {
  for (const ent of entities.values()) {
    if (ent.extraSlug) continue;
    const n = e.payload?.tokens || 0;
    if (n <= 0) continue;
    if (!ownsProject(ent, e.payload.project)) continue;
    if (e.payload.project) usage.recordTokens(e.payload.project, e.payload.agent, n, e.payload.cost || 0);
    const slug = myPetSlug(ent);
    if (!slug) continue;
    care.mutate(slug, (s) => care.feedTokens(s, n));
    emit("care-updated");
    sync.schedulePush();
    evaluateCareMetrics(ent);
  }
});
listen<string>("session-dismiss", (e) => { for (const ent of entities.values()) { if (!ent.extraSlug) ent.store.removeKey(e.payload); renderEntity(ent); } });
listen("sessions-clear", () => { for (const ent of entities.values()) { if (!ent.extraSlug) ent.store.clear(); renderEntity(ent); } });
listen("sessions-request", () => { for (const ent of entities.values()) { if (ent.isMain) for (const s of ent.store.snapshot()) emit("session-snapshot", s); } });
listen<{ slug: string | null; url: string | null }>("set-pet", async (e) => {
  if (e.payload.url) {
    for (const ent of entities.values()) {
      if (ent.extraSlug) continue;
      ent.pet.load(e.payload.url);
    }
    if (e.payload.slug) saveSlug(e.payload.slug);
    localStorage.setItem("ap_pet_url", e.payload.url);
    return;
  }
  localStorage.removeItem("ap_pet_url");
  localStorage.removeItem("ap_pet_custom");
  for (;;) {
    const pets = await loadCatalog();
    if (pets.length) {
      const slug = savedSlug();
      const chosen = pets.find((p) => p.slug === slug) ?? pets[Math.floor(pets.length / 2)];
      saveSlug(chosen.slug);
      localStorage.setItem("ap_pet_url", chosen.spritesheetUrl);
      for (const ent of entities.values()) { if (!ent.extraSlug) ent.pet.load(chosen.spritesheetUrl); }
      return;
    }
    await new Promise((r) => setTimeout(r, 15000));
  }
});
listen<Lang>("lang-changed", (e) => { setLang(e.payload); for (const ent of entities.values()) renderEntity(ent); });
listen("bubble-changed", () => {
  invalidateBubbleConfig();
  for (const ent of entities.values()) {
    applyBubble(ent.root);
    applyPetSize(ent);
    ent.moodLine = "";
    renderEntity(ent);
  }
});

if (sync.signedIn()) {
  sync.restore().then(() => { emit("care-updated"); sync.schedulePush(5000); }).catch(() => {});
  usage.schedulePush(8000);
}

setInterval(() => { if (stageVisible) for (const ent of entities.values()) renderEntity(ent); }, 500);
setInterval(() => {
  const slug = myPetSlug(mainPet);
  if (slug) flashReactive(mainPet, reactive.evaluate("hunger", care.hunger(care.stateFor(slug))));
}, 60_000);
setInterval(() => { if (stageVisible) for (const ent of entities.values()) if (ent.bubble.dirty) { ent.bubble.dirty = false; renderEntity(ent); } }, 120);
setInterval(() => { for (const ent of entities.values()) ent.bubble.tickClocks(); }, 1000);

// ---- floating ball -----------------------------------------------------------

const ball = document.createElement("div");
ball.id = "ball";
ball.innerHTML = `<div class="ball-orb"></div>`;
ballLayer.appendChild(ball);

const BALL_SIZE = 56;
let ballX = 0, ballY = 0;
let ballMayBeClick = false;
let ballIsDragging = false;
let ballDragStartX = 0, ballDragStartY = 0, ballDragStartTime = 0;

function initFloatingBall() {
  invoke<{ x: number; y: number } | null>("read_ball_pos").then((pos) => {
    ballX = pos?.x ?? 0;
    ballY = pos?.y ?? 0;
    ball.style.transform = `translate(${ballX}px, ${ballY}px)`;
  }).catch(() => {});

  ball.addEventListener("mousedown", (e) => {
    if (e.button !== 0) return;
    ballMayBeClick = true;
    ballIsDragging = false;
    ballDragStartX = e.screenX;
    ballDragStartY = e.screenY;
    ballDragStartTime = performance.now();
    ball.classList.add("pressed");
  });
  window.addEventListener("mousemove", (e) => {
    if (!ballMayBeClick || ballIsDragging) return;
    const dx = Math.abs(e.screenX - ballDragStartX);
    const dy = Math.abs(e.screenY - ballDragStartY);
    if (dx <= 4 && dy <= 4) return;
    ballMayBeClick = false;
    ballIsDragging = true;
    setDragLock(true);
    ball.classList.remove("pressed");
    ball.classList.add("dragging");
    const startX = ballX, startY = ballY;
    const onMove = (ev: MouseEvent) => {
      ballX = startX + (ev.screenX - ballDragStartX);
      ballY = startY + (ev.screenY - ballDragStartY);
      ball.style.transform = `translate(${ballX}px, ${ballY}px)`;
      reportHitRegions();
    };
    const onUp = () => {
      window.removeEventListener("mousemove", onMove);
      window.removeEventListener("mouseup", onUp);
      ballIsDragging = false;
      setDragLock(false);
      ball.classList.remove("dragging");
      invoke("snap_stage_ball", { x: ballX, y: ballY }).catch(() => {});
    };
    window.addEventListener("mousemove", onMove);
    window.addEventListener("mouseup", onUp);
  });
  window.addEventListener("mouseup", (e) => {
    ball.classList.remove("pressed");
    if (!ballMayBeClick) return;
    ballMayBeClick = false;
    const dx = Math.abs(e.screenX - ballDragStartX);
    const dy = Math.abs(e.screenY - ballDragStartY);
    if (dx > 4 || dy > 4) return;
    if (performance.now() - ballDragStartTime <= 280) showBallMenu();
  });
  ball.addEventListener("contextmenu", (e) => { e.preventDefault(); hideBallMenu(); invoke("open_settings").catch(() => {}); });
}
initFloatingBall();

// ---- ball menu ---------------------------------------------------------------

const menu = document.createElement("div");
menu.id = "ball-menu";
menu.className = "ball-menu";
menu.hidden = true;
ballLayer.appendChild(menu);

let selectedPreset = -1;
function paintBallMenu() {
  const presets = randomPresetList();
  menu.innerHTML = `
    <input id="bm-input" class="bm-input" placeholder="${t("Type a bubble message…")}" />
    <div id="bm-presets" class="bm-presets">${presets.map((p, i) => `<button class="bm-preset ${i === selectedPreset ? "sel" : ""}" data-i="${i}">${p}</button>`).join("")}</div>
    <div id="bm-target" class="bm-target"><button data-v="all" class="sel">${t("All")}</button><button data-v="main">${t("Main")}</button><button data-v="extra">${t("Extra")}</button></div>
    <div class="bm-actions"><button id="bm-cancel">${t("Cancel")}</button><button id="bm-send">${t("Send")}</button></div>
  `;
  const input = menu.querySelector("#bm-input") as HTMLInputElement;
  const sendBtn = menu.querySelector("#bm-send") as HTMLButtonElement;
  const cancelBtn = menu.querySelector("#bm-cancel") as HTMLButtonElement;
  input.addEventListener("input", () => { selectedPreset = -1; paintBallMenu(); });
  input.addEventListener("keydown", (e) => { if (e.key === "Enter" && input.value.trim()) sendBallMenu(); else if (e.key === "Escape") hideBallMenu(); });
  sendBtn.onclick = sendBallMenu;
  cancelBtn.onclick = hideBallMenu;
  sendBtn.disabled = !input.value.trim();
  menu.querySelectorAll(".bm-preset").forEach((b) => {
    b.addEventListener("click", (ev) => {
      const i = parseInt((ev.target as HTMLElement).dataset.i!);
      if ((ev as MouseEvent).shiftKey) {
        const next = randomPresetList().filter((_, j) => j !== i);
        localStorage.setItem("ap_quick_bubbles", JSON.stringify(next.slice(0, 12)));
        selectedPreset = -1;
        emit("bubble-changed", null);
        paintBallMenu();
        return;
      }
      selectedPreset = i;
      input.value = randomPresetList()[i];
      paintBallMenu();
      input.focus();
    });
  });
  menu.querySelectorAll("#bm-target button").forEach((b) => {
    b.addEventListener("click", () => {
      localStorage.setItem("ap_ball_target", (b as HTMLElement).dataset.v!);
      paintBallMenu();
    });
  });
}

function randomPresetList(): string[] {
  try {
    const v = JSON.parse(localStorage.getItem("ap_quick_bubbles") || "[]");
    return Array.isArray(v) ? v.filter((x: unknown) => typeof x === "string" && x.trim()).slice(0, 12) : [];
  } catch { return []; }
}

function ballTarget(): "all" | "main" | "extra" {
  const v = localStorage.getItem("ap_ball_target");
  return v === "main" || v === "extra" ? v : "all";
}

function sendBallMenu() {
  const input = menu.querySelector("#bm-input") as HTMLInputElement;
  const text = input.value.trim();
  if (!text) return;
  const next = [text, ...randomPresetList().filter((x) => x !== text)];
  localStorage.setItem("ap_quick_bubbles", JSON.stringify(next.slice(0, 12)));
  emit("quick-bubble", { text, target: ballTarget() });
  hideBallMenu();
}

const MENU_W = 300;
const MENU_H = 420;
function showBallMenu() {
  if (!menu.hidden) return;
  selectedPreset = -1;
  paintBallMenu();
  menu.hidden = false;
  const x = Math.min(ballX, window.innerWidth - MENU_W);
  const y = Math.min(ballY + BALL_SIZE + 8, window.innerHeight - MENU_H);
  menu.style.transform = `translate(${x}px, ${y}px)`;
  reportHitRegions();   // register the menu as an opaque region right away
  requestAnimationFrame(() => (menu.querySelector("#bm-input") as HTMLInputElement)?.focus());
}
function hideBallMenu() { menu.hidden = true; reportHitRegions(); }

window.addEventListener("keydown", (e) => { if (e.key === "Escape" && !menu.hidden) hideBallMenu(); });

// ---- popover -----------------------------------------------------------------

let popoverVisible = false;
const popStore = new SessionStore();
let popLastH = 0;

function esc(s: string) { return s.replace(/[&<>]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" }[c] || c)); }
function cap(s: string) { return s.charAt(0).toUpperCase() + s.slice(1); }
function popTimeString(s: Session) { return s.state === "done" ? new Date(s.updatedAt).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }) : elapsedString(s.stateSince); }

function paintPopover() {
  const sessions = popStore.active().filter((s) => s.state !== "idle" && s.state !== "registered");
  const running = sessions.filter((s) => s.state === "working").length;
  const sub = sessions.length ? `${sessions.length} ${sessions.length === 1 ? t("agent") : t("agents")}${running > 0 ? ` · ${running} ${t("running")}` : ""}` : t("No agents running");
  const list = sessions.map((s) => {
    const icon = agentIconUrl(s.agent);
    return `<div class="pop-agent" data-state="${s.state}"><span class="sess-dot"></span><span class="pop-ameta"><b>${esc(s.project ? basename(s.project) : s.session)}</b><span class="cap">${esc(s.title || s.live || t(cap(s.state)))}</span></span>${icon ? `<img class="dp-icon" src="${icon}" alt="">` : ""}<span class="sess-time">${popTimeString(s)}</span></div>`;
  }).join("");
  const checked = localStorage.getItem("ap_pet_visible") !== "0";
  popoverLayer.innerHTML = `
    <div class="pop-card">
      <div class="pop-header"><span id="t-pop-agents">${t("AGENTS")}</span><button id="pop-clear" ${sessions.length ? "" : "hidden"}>${t("Clear all")}</button></div>
      <div id="pop-sub" class="pop-sub">${sub}</div>
      <div id="pop-empty" class="pop-empty" ${sessions.length ? "hidden" : ""}>${t("Nothing running right now.")}</div>
      <div id="pop-list" class="pop-list">${list}</div>
      <div class="pop-controls"><label><input type="checkbox" id="pop-showpet" ${checked ? "checked" : ""}> <span id="t-pop-showpet">${t("Show pet")}</span></label><label><span id="t-pop-size">${t("Pet size")}</span><input type="range" id="pop-size" min="80" max="125" value="${localStorage.getItem("ap_pet_size") || "100"}"></label></div>
      <div class="pop-footer"><button id="pop-settings">${t("Settings")}</button><button id="pop-updates">${t("Updates")}</button><button id="pop-quit">${t("Quit")}</button></div>
    </div>
  `;
  popoverLayer.querySelector("#pop-clear")?.addEventListener("click", () => { popStore.clear(); emit("sessions-clear", null); paintPopover(); fitPopover(); });
  const showPet = popoverLayer.querySelector("#pop-showpet") as HTMLInputElement;
  showPet?.addEventListener("change", () => { invoke("set_pet_visible", { visible: showPet.checked }).catch(() => {}); });
  const size = popoverLayer.querySelector("#pop-size") as HTMLInputElement;
  size?.addEventListener("input", () => { localStorage.setItem("ap_pet_size", size.value); emit("bubble-changed", null); });
  popoverLayer.querySelector("#pop-settings")?.addEventListener("click", () => { invoke("open_settings").catch(() => {}); hidePopover(); });
  popoverLayer.querySelector("#pop-quit")?.addEventListener("click", () => exit(0));
  popoverLayer.querySelector("#pop-updates")?.addEventListener("click", async () => {
    const label = popoverLayer.querySelector("#t-pop-updates")!;
    label.textContent = t("Checking…");
    try {
      const update = await check();
      if (update) { label.textContent = t("Installing…"); await update.downloadAndInstall(); await relaunch(); }
      else { label.textContent = t("Up to date"); setTimeout(() => label.textContent = t("Updates"), 2500); }
    } catch { label.textContent = t("Up to date"); setTimeout(() => label.textContent = t("Updates"), 2500); }
  });
  fitPopover();
}

function fitPopover() {
  const card = popoverLayer.querySelector(".pop-card") as HTMLElement;
  if (!card) return;
  const h = Math.min(560, Math.max(220, card.scrollHeight + 20));
  if (Math.abs(h - popLastH) < 2) return;
  popLastH = h;
  popoverLayer.style.height = `${h}px`;
}

function showPopover() {
  popoverVisible = true;
  popoverLayer.hidden = false;
  const ent = mainPet;
  const x = Math.min(ent.x + 170, window.innerWidth - 340);
  const y = Math.min(ent.y, window.innerHeight - 280);
  popoverLayer.style.transform = `translate(${Math.max(8, x)}px, ${Math.max(8, y)}px)`;
  emit("sessions-request", null);
  paintPopover();
  reportHitRegions();   // register the popover card as an opaque region
}
function hidePopover() { popoverVisible = false; popoverLayer.hidden = true; reportHitRegions(); }

listen<AgentEventPayload>("agent-event", (e) => { popStore.update(e.payload); if (popoverVisible) paintPopover(); });
listen<string>("agent-end", (e) => { popStore.remove(e.payload); if (popoverVisible) paintPopover(); });
listen<Session>("session-snapshot", (e) => { popStore.seed(e.payload); if (popoverVisible) paintPopover(); });
listen("popover-close", () => hidePopover());
listen("popover-shown", () => { if (!popoverVisible) showPopover(); });
setInterval(() => { if (popoverVisible) paintPopover(); }, 1000);

// ---- extra-pet context menu --------------------------------------------------

let ctxMenu: HTMLDivElement | null = null;
function hideCtxMenu() { if (ctxMenu) { ctxMenu.remove(); ctxMenu = null; } }
function showExtraCtxMenu(ent: PetEntity, x: number, y: number) {
  hideCtxMenu();
  const m = document.createElement("div");
  m.className = "ctx-menu";
  const closeBtn = document.createElement("button"); closeBtn.className = "ctx-item ctx-close"; closeBtn.textContent = "✕ Close"; closeBtn.onclick = () => { hideCtxMenu(); ent.root.remove(); entities.delete(ent.id); reportHitRegions(); };
  m.appendChild(closeBtn);
  m.appendChild(document.createElement("div")).className = "ctx-sep";
  const roamHead = document.createElement("div"); roamHead.className = "ctx-label"; roamHead.textContent = "Roam"; m.appendChild(roamHead);
  const currentMode = localStorage.getItem(`ap_win_${ent.label}_roam_mode`) || "stay";
  for (const [mode, label] of [["stay", "Stay"], ["wander", "Wander"], ["cursor", "Follow cursor"], ["climb", "Climb"]] as const) {
    const btn = document.createElement("button"); btn.className = "ctx-item"; if (mode === currentMode) btn.classList.add("sel"); btn.textContent = label; btn.onclick = () => { localStorage.setItem(`ap_win_${ent.label}_roam_mode`, mode); hideCtxMenu(); }; m.appendChild(btn);
  }
  m.appendChild(document.createElement("div")).className = "ctx-sep";
  const sizeHead = document.createElement("div"); sizeHead.className = "ctx-label"; sizeHead.textContent = "Size"; m.appendChild(sizeHead);
  const currentSize = parseInt(localStorage.getItem(`ap_win_${ent.label}_pet_size`) || localStorage.getItem("ap_pet_size") || "100", 10);
  for (const [val, label] of [["80", "S"], ["100", "M"], ["125", "L"]] as const) {
    const btn = document.createElement("button"); btn.className = "ctx-item"; if (parseInt(val) === currentSize) btn.classList.add("sel"); btn.textContent = label; btn.onclick = () => { localStorage.setItem(`ap_win_${ent.label}_pet_size`, val); applyPetSize(ent); reportHitRegions(); hideCtxMenu(); }; m.appendChild(btn);
  }
  m.style.left = `${Math.min(x, window.innerWidth - 180)}px`;
  m.style.top = `${Math.min(y, window.innerHeight - 320)}px`;
  document.body.appendChild(m);
  ctxMenu = m;
  setTimeout(() => {
    const onDown = (ev: MouseEvent) => { if (ctxMenu === m && !m.contains(ev.target as Node)) hideCtxMenu(); document.removeEventListener("mousedown", onDown); };
    document.addEventListener("mousedown", onDown);
  }, 0);
  const onKey = (ev: KeyboardEvent) => { if (ev.key === "Escape" && ctxMenu === m) hideCtxMenu(); document.removeEventListener("keydown", onKey); };
  document.addEventListener("keydown", onKey);
}

// ---- hit regions -------------------------------------------------------------

let lastHitSig = "";
function reportHitRegions() {
  const d = window.devicePixelRatio || 1;
  const regions: { x: number; y: number; w: number; h: number }[] = [];
  // pets: getBoundingClientRect already includes the root's absolute offset.
  for (const ent of entities.values()) {
    const rects: { left: number; top: number; right: number; bottom: number }[] = [];
    if (!ent.bubbleEl.hidden) {
      const b = ent.bubbleEl.getBoundingClientRect();
      if (b.width > 0) rects.push({ left: b.left, top: b.top, right: b.right, bottom: b.bottom });
    }
    const cr = ent.canvas.getBoundingClientRect();
    const sr = ent.pet.spriteRect;
    if (sr && ent.canvas.width > 0) {
      const kx = cr.width / ent.canvas.width;
      const ky = cr.height / ent.canvas.height;
      rects.push({
        left: cr.left + sr.x * kx,
        top: cr.top + sr.y * ky,
        right: cr.left + (sr.x + sr.w) * kx,
        bottom: cr.top + (sr.y + sr.h) * ky,
      });
    } else {
      rects.push({ left: cr.left, top: cr.top, right: cr.right, bottom: cr.bottom });
    }
    if (!rects.length) continue;
    regions.push({
      x: Math.min(...rects.map((r) => r.left)) * d,
      y: Math.min(...rects.map((r) => r.top)) * d,
      w: (Math.max(...rects.map((r) => r.right)) - Math.min(...rects.map((r) => r.left))) * d,
      h: (Math.max(...rects.map((r) => r.bottom)) - Math.min(...rects.map((r) => r.top))) * d,
    });
  }
  // ball
  if (ballX >= 0 && ballY >= 0) {
    regions.push({ x: ballX * d, y: ballY * d, w: BALL_SIZE * d, h: BALL_SIZE * d });
  }
  // ball menu
  if (!menu.hidden) {
    const r = menu.getBoundingClientRect();
    regions.push({ x: r.left * d, y: r.top * d, w: r.width * d, h: r.height * d });
  }
  // popover
  if (popoverVisible && !popoverLayer.hidden) {
    const r = popoverLayer.getBoundingClientRect();
    regions.push({ x: r.left * d, y: r.top * d, w: r.width * d, h: r.height * d });
  }
  // Skip the IPC bridge when the opaque geometry is unchanged. The bubble's
  // typing animation and the elapsed clock repaint text constantly but do not
  // resize the outer box (max-width + nowrap + ellipsis), so the region set is
  // usually identical tick over tick.
  const sig = regions.map((r) => `${r.x.toFixed(1)},${r.y.toFixed(1)},${r.w.toFixed(1)},${r.h.toFixed(1)}`).join(";");
  if (sig === lastHitSig) return;
  lastHitSig = sig;
  invoke("set_stage_hit_regions", { regions }).catch(() => {});
}

// ---- resize / reduce motion --------------------------------------------------

function applyReduceMotion() {
  document.body.classList.toggle("reduce-motion", localStorage.getItem("ap_reduce_motion") === "1");
}
applyReduceMotion();
window.addEventListener("storage", (e) => { if (e.key === "ap_reduce_motion") applyReduceMotion(); });

// ---- visibility gating -------------------------------------------------------
// Pause the sprite frame loops + high-frequency render/roam ticks whenever the
// stage overlay isn't on screen (tray-hidden, or the WebView is backgrounded).
// A hidden transparent overlay that keeps redrawing its canvas still forces the
// compositor to recomposite the whole screen — gating it drops idle cost to ~0.
function applyStageVisible(visible: boolean) {
  if (visible === stageVisible) return;
  stageVisible = visible;
  for (const ent of entities.values()) ent.pet.setVisible(visible);
  if (visible) {
    for (const ent of entities.values()) renderEntity(ent);
    reportHitRegions();
  }
}

// Rust flips this on the tray show/hide toggle (see set_pet_visible). This is
// the ONLY source of truth for stage visibility. We deliberately do NOT listen
// to `document.visibilitychange`: a full-screen transparent click-through
// overlay frequently reports itself as `hidden` in WebView2 even while fully on
// screen, which would wrongly freeze every loop (pet undraggable, menus dead,
// roaming stopped).
listen<boolean>("stage-visibility", (e) => applyStageVisible(e.payload));

listen<boolean>("stage-ball-visible", (e) => {
  ball.style.display = e.payload ? "" : "none";
  reportHitRegions();
});
listen<{ x: number; y: number }>("stage-ball-snap", (e) => {
  ballX = e.payload.x;
  ballY = e.payload.y;
  ball.style.transform = `translate(${ballX}px, ${ballY}px)`;
  reportHitRegions();
});
listen<string[]>("stage-sync-projects", (e) => {
  const wanted = new Set(e.payload);
  const margin = 80;
  // Remove project pets whose project is no longer configured.
  for (const [label, ent] of entities) {
    if (!ent.projectId) continue;
    if (!wanted.has(ent.projectId)) {
      ent.root.remove();
      entities.delete(label);
    }
  }
  // Create project pets for new projects.
  let idx = 0;
  for (const id of wanted) {
    if ([...entities.values()].some((ent) => ent.projectId === id)) continue;
    const x = margin + idx * 60;
    const y = margin + idx * 40;
    const label = `pet-project-${id}`;
    entities.set(label, createPetEntity(label, { x, y, label, projectId: id }));
    idx++;
  }
  reportHitRegions();
});
listen<{ slug: string; label: string; x: number; y: number }>("stage-spawn-extra", (e) => {
  const p = e.payload;
  const ent = createPetEntity(p.label, { x: p.x, y: p.y, label: p.label, extraSlug: p.slug });
  entities.set(p.label, ent);
  reportHitRegions();
});
listen<{ label: string }>("stage-close-extra", (e) => {
  const ent = entities.get(e.payload.label);
  if (ent) { ent.root.remove(); entities.delete(e.payload.label); reportHitRegions(); }
});

// ---- roaming -----------------------------------------------------------------

function syncRoamMode(ent: PetEntity) {
  // The main pet's roam mode is configured on the Settings → Pet screen, which
  // writes the "default" key (ap_roam_mode). Project/extra pets keep their own
  // per-window key. Reading ent.label for the main pet ("pet") pointed at a key
  // Settings never wrote, so the main pet's roam selection silently did nothing.
  ent.roamMode = getRoamMode(ent.isMain ? "default" : ent.label);
}

function randomRoamTarget(ent: PetEntity): { x: number; y: number } {
  const pad = 60;
  const maxX = Math.max(pad, window.innerWidth - pad);
  const maxY = Math.max(pad, window.innerHeight - pad);
  return {
    x: pad + Math.random() * (maxX - pad),
    y: pad + Math.random() * (maxY - pad),
  };
}

function setRoamAnimation(ent: PetEntity, moving: boolean, dx: number) {
  if (moving) {
    ent.pet.setRow(dx > 0 ? 1 : 2); // run right / left
  } else {
    ent.pet.clearRow();
    ent.pet.setState("idle");
  }
}

function tickRoam(ent: PetEntity): boolean {
  if (ent.dragging) return false;
  syncRoamMode(ent);
  if (ent.roamMode === "stay") {
    setRoamAnimation(ent, false, 0);
    return false;
  }

  const speedBase = parseInt(localStorage.getItem("ap_roam_speed") || "50", 10) / 50; // 0.2 - 4
  const now = Date.now();

  if (ent.roamMode === "cursor") {
    const dx = ent.cursorX - ent.x;
    const dy = ent.cursorY - ent.y;
    const dist = Math.hypot(dx, dy) || 1;
    const followSpeed = 1.5 * speedBase;
    if (dist > 12) {
      ent.x += (dx / dist) * followSpeed;
      ent.y += (dy / dist) * followSpeed;
      setRoamAnimation(ent, true, dx);
    } else {
      setRoamAnimation(ent, false, 0);
      return false;
    }
  } else if (ent.roamMode === "wander" || ent.roamMode === "climb") {
    const tx = ent.roamTargetX;
    const ty = ent.roamTargetY;
    const dx = tx - ent.x;
    const dy = ty - ent.y;
    const dist = Math.hypot(dx, dy) || 1;
    const speed = 1.0 * speedBase;

    if (dist < 8 || now >= ent.roamNextChange) {
      const next = ent.roamMode === "climb"
        ? { x: ent.x, y: Math.random() * (window.innerHeight - 120) + 60 }
        : randomRoamTarget(ent);
      ent.roamTargetX = next.x;
      ent.roamTargetY = next.y;
      ent.roamNextChange = now + 2000 + Math.random() * 4000;
      setRoamAnimation(ent, false, 0);
      return false;
    }

    ent.x += (dx / dist) * speed;
    ent.y += (dy / dist) * speed;
    setRoamAnimation(ent, true, dx);
  }

  ent.root.style.left = `${ent.x}px`;
  ent.root.style.top = `${ent.y}px`;
  return true;
}

window.addEventListener("mousemove", (e) => {
  for (const ent of entities.values()) {
    ent.cursorX = e.clientX;
    ent.cursorY = e.clientY;
  }
});

setInterval(() => {
  if (!stageVisible) return;
  for (const ent of entities.values()) {
    // The main pet roams too when its mode isn't `stay` (pure-pet mode). In
    // `stay` it's positioned by the user, so we skip it — its drag handler
    // owns the position.
    if (ent.isMain && getRoamMode("default") === "stay") continue;
    tickRoam(ent);
  }
  // Always re-report; `reportHitRegions` itself skips the IPC bridge when the
  // opaque geometry is unchanged (signature dedupe). This keeps the click-
  // through mask correct for a STATIONARY pet too — the previous "only when a
  // pet moved" gate left a just-loaded / just-repositioned pet unclickable.
  reportHitRegions();
}, 50);

renderEntity(mainPet);
