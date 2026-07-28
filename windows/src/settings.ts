import { invoke } from "@tauri-apps/api/core";
import { emit, listen } from "@tauri-apps/api/event";
import { getVersion } from "@tauri-apps/api/app";
import { exit } from "@tauri-apps/plugin-process";
import { enable, disable, isEnabled } from "@tauri-apps/plugin-autostart";
import { loadCatalog, savedSlug, saveSlug, clearSlug, getLibrary, addToLibrary, removeFromLibrary, petDisplayName, renamePet, type Pet, type LibPet } from "./catalog";
import { t, getLang, setLang, type Lang } from "./i18n";
import { agentIconUrl, uiIcon } from "./icons";
import { LAYOUT_PRESETS, readBubbleConfig, type TokenItem, type BubbleToken } from "./bubble";
import { initDemo } from "./demo";
import { slice, type Rect } from "./pet";
import { getRoamMode, setRoamMode, getRoamSpeed, setRoamSpeed } from "./roam";

import * as care from "./care";
import * as usage from "./usage";
import * as projectpets from "./projectpets";
import * as sync from "./sync";
import * as history from "./history";

// ------------------------------------------------------------- segmented ----
// macOS-style segmented controls: <span class="seg" data-key data-default>.
function initSegs() {
  document.querySelectorAll<HTMLElement>(".seg[data-key]").forEach((seg) => {
    const key = seg.dataset.key!;
    const current = localStorage.getItem(key) || seg.dataset.default || "";
    const btns = seg.querySelectorAll<HTMLButtonElement>("button");
    btns.forEach((b) => {
      b.classList.toggle("sel", b.dataset.v === current);
      b.onclick = () => {
        localStorage.setItem(key, b.dataset.v!);
        btns.forEach((x) => x.classList.toggle("sel", x === b));
        emit("bubble-changed", null);
        document.dispatchEvent(new CustomEvent("seg-changed", { detail: key }));
      };
    });
  });
}

// ------------------------------------------------------------------ tabs ----
function initTabs() {
  const tabs = document.querySelectorAll<HTMLButtonElement>(".tabbar .tab");
  tabs.forEach((b) => {
    b.onclick = () => {
      tabs.forEach((x) => x.classList.toggle("sel", x === b));
      document.querySelectorAll<HTMLElement>(".page").forEach((p) => {
        p.classList.toggle("sel", p.dataset.page === b.dataset.tab);
      });
      if (b.dataset.tab === "care") { renderCare(); renderSync(); }
      if (b.dataset.tab === "advanced") renderHistory();
      if (b.dataset.tab === "pet") document.dispatchEvent(new CustomEvent("ap-pet-tab-shown"));
    };
  });
}

// ------------------------------------------------------------------ history ----
function renderHistory() {
  const listEl = document.getElementById("history-list");
  const emptyEl = document.getElementById("history-empty");
  const countEl = document.getElementById("history-count");
  if (!listEl) return;
  const items = history.list();
  if (countEl) countEl.textContent = items.length ? `${items.length}` : "";
  if (emptyEl) emptyEl.style.display = items.length ? "none" : "";
  const escH = (s: string) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));
  const fmtDur = (ms: number) => {
    const s = Math.max(0, Math.round(ms / 1000));
    if (s < 60) return `${s}s`;
    const m = Math.round(s / 60);
    return m < 60 ? `${m}m` : `${Math.round(m / 60)}h`;
  };
  const dayLabel = (t: number) => new Date(t).toLocaleDateString();
  const timeLabel = (t: number) => new Date(t).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
  let html = "", curDay = "";
  for (const e of items) {
    const d = dayLabel(e.endedAt);
    if (d !== curDay) { curDay = d; html += `<div class="hist-day">${escH(d)}</div>`; }
    const label = e.title || e.project || e.agent;
    html += `<div class="hist-row">
      <span class="hist-agent">${escH(e.agent)}</span>
      <span class="hist-title">${escH(label)}</span>
      <span class="hist-meta dim">${escH(e.project)} · ${fmtDur(e.endedAt - e.startedAt)} · ${timeLabel(e.endedAt)}</span>
    </div>`;
  }
  listEl.innerHTML = html;
}

// ------------------------------------------------------------------ care ----
function fmtNum(n: number): string {
  n = Number(n) || 0;
  if (n >= 1e9) return (n / 1e9).toFixed(1).replace(/\.0$/, "") + "B";
  if (n >= 1e6) return (n / 1e6).toFixed(1).replace(/\.0$/, "") + "M";
  if (n >= 1e3) return (n / 1e3).toFixed(1).replace(/\.0$/, "") + "K";
  return String(n);
}
function currentPetName(): string {
  const slug = savedSlug();
  if (!slug) return t("Your pet");
  const custom = petDisplayName(slug);
  if (custom !== slug) return custom;
  const hit = getLibrary().find((p) => p.slug === slug) || catalog.find((p) => p.slug === slug);
  return hit?.name || slug;
}
function renderCare() {
  const slug = savedSlug();
  if (!slug) return;
  const s = care.stateFor(slug);
  const internal = care.levelForXP(s.xp);
  const setTxt = (id: string, v: string) => { const el = document.getElementById(id); if (el) el.textContent = v; };
  setTxt("care-name", currentPetName());
  setTxt("care-level", `${t("Lv")} ${care.displayLevel(s.xp)}`);
  setTxt("care-stagename", t(care.stageName(internal)));
  setTxt("care-hunger", t(care.hunger(s)));
  const fill = document.getElementById("care-xpfill");
  if (fill) fill.style.width = `${Math.round(care.levelProgress(s.xp) * 100)}%`;
  setTxt("care-xp", `${s.xp} XP`);
  const toNext = care.tokensToNextLevel(s);
  setTxt("care-tonext", toNext > 0 ? `≈ ${fmtNum(toNext)} ${t("tokens to next level")}` : "");
  // achievements
  const unlocked = new Set(s.unlockedAchievements || []);
  setTxt("care-achcount", `${unlocked.size} / ${care.ACHIEVEMENTS.length}`);
  const badges = document.getElementById("care-badges");
  if (badges) badges.innerHTML = care.ACHIEVEMENTS
    .map((a) => `<span class="care-badge${unlocked.has(a) ? " on" : ""}" title="${t(care.ACH_NAME[a])}">${uiIcon(care.ACH_ICON[a])}</span>`)
    .join("");
  setTxt("care-today", fmtNum(s.tokensToday));
  setTxt("care-today-sub", `${s.mealsToday} ${t("sessions")}`);
  const money = (v: number) => `$${v.toFixed(2)}`;
  setTxt("care-cost", `${t("Today")} ${money(usage.todayCostUSD())} · ${t("Month")} ${money(usage.monthlyCostUSD())}`);
  setTxt("care-streak", String(s.streakDays));
  setTxt("care-lifetime", fmtNum(s.totalTokens));
  setTxt("care-sessions", String(s.totalMeals));
  const days = care.recentDays(s, 7);
  const max = Math.max(1, ...days.map((d) => d.tokens));
  setTxt("care-burntotal", fmtNum(days.reduce((a, d) => a + d.tokens, 0)));
  const chart = document.getElementById("care-chart");
  if (chart) chart.innerHTML = days
    .map((d) => `<div class="cbar-wrap" title="${fmtNum(d.tokens)}"><div class="cbar" style="height:${Math.max(3, Math.round((d.tokens / max) * 100))}%"></div><div class="cbar-lbl">${d.label}</div></div>`)
    .join("");
}
// Click the pet's name to rename it; Enter or blur saves (empty resets to the
// default). The custom name flows to the HUD, menubar, and web leaderboard.
function setupRename() {
  const nameEl = document.getElementById("care-name");
  const input = document.getElementById("care-rename") as HTMLInputElement | null;
  if (!nameEl || !input) return;
  const startEdit = () => {
    const slug = savedSlug();
    if (!slug) return;
    input.value = currentPetName();
    nameEl.style.display = "none";
    input.style.display = "";
    input.focus();
    input.select();
  };
  const commit = () => {
    const slug = savedSlug();
    if (slug) renamePet(slug, input.value);
    input.style.display = "none";
    nameEl.style.display = "";
    renderCare();
    emit("care-updated");
    sync.schedulePush();
  };
  nameEl.addEventListener("click", startEdit);
  input.addEventListener("blur", commit);
  input.addEventListener("keydown", (e) => {
    if (e.key === "Enter") { e.preventDefault(); input.blur(); }
    else if (e.key === "Escape") { input.value = currentPetName(); input.blur(); }
  });
}
setupRename();

// Refresh when the pet window feeds the pet, and periodically for the hunger clock.
listen("care-updated", () => { if (document.querySelector('.page[data-page="care"].sel')) renderCare(); });
setInterval(() => { if (document.querySelector('.page[data-page="care"].sel')) renderCare(); }, 30_000);

// ---- web profile / leaderboard sign-in ----
function renderSync() {
  const out = document.getElementById("sync-out");
  const inn = document.getElementById("sync-in");
  const status = document.getElementById("sync-status");
  if (!out || !inn) return;
  const on = sync.signedIn();
  out.style.display = on ? "none" : "";
  inn.style.display = on ? "" : "none";
  if (on && status) {
    const who = sync.login();
    status.textContent = who ? `${t("Connected as")} ${who}` : t("Connected to your profile");
  }
}
function initSync() {
  const codeEl = document.getElementById("sync-code") as HTMLInputElement | null;
  const msg = document.getElementById("sync-msg");
  document.getElementById("sync-connect")?.addEventListener("click", async () => {
    const c = (codeEl?.value || "").trim().toUpperCase();
    if (msg) msg.textContent = t("Connecting…");
    const r = await sync.pair(c);
    if (r.ok) {
      if (msg) msg.textContent = "";
      if (codeEl) codeEl.value = "";
      renderSync(); renderCare();
    } else if (msg) {
      msg.textContent = r.error === "expired" ? t("Code expired, get a new one.") : t("Could not connect.");
    }
  });
  document.getElementById("sync-restore")?.addEventListener("click", async () => {
    const msg2 = document.getElementById("sync-msg2");
    if (msg2) msg2.textContent = t("Restoring…");
    const n = await sync.restore();
    await sync.push();
    if (msg2) msg2.textContent = n > 0 ? `${t("Restored")} ${n}` : t("Already up to date.");
    renderCare();
  });
  document.getElementById("sync-disconnect")?.addEventListener("click", () => { sync.disconnect(); renderSync(); });
  renderSync();
}
initSync();

// ---------------------------------------------------------------- agents ----
interface AgentInfo {
  kind: string;
  display_name: string;
  installed: boolean;
  note: string | null;
}

const agentsRoot = document.getElementById("agents")!;
let agentsCache: AgentInfo[] = [];

async function loadAgents() {
  agentsCache = await invoke<AgentInfo[]>("list_agents");
  renderAgents();
}

function renderAgents() {
  agentsRoot.innerHTML = "";
  for (const a of agentsCache) {
    const row = document.createElement("div");
    row.className = "agent-row";

    const meta = document.createElement("div");
    meta.className = "meta";
    // Codex needs a one-time trust after install (mac shows it in orange).
    const status = a.kind === "codex" && a.installed
      ? `<div class="note warn">${esc(t("Installed , needs a one-time trust (tap ?)"))}</div>`
      : a.note
      ? `<div class="note">${esc(t(a.note))}</div>`
      : a.installed
      ? `<div class="ok">${esc(t("Hook installed"))}</div>`
      : "";
    meta.innerHTML = `<div class="name">${esc(a.display_name)}</div>${status}`;
    row.appendChild(meta);

    if (a.kind === "codex") {
      const help = document.createElement("button");
      help.className = "help-btn";
      help.textContent = "?";
      help.title = t("How to connect Codex");
      help.onclick = () => { (document.getElementById("codex-help") as HTMLElement).hidden = false; };
      row.appendChild(help);
    }

    const btn = document.createElement("button");
    btn.textContent = a.installed ? t("Remove") : t("Install");
    if (a.installed) btn.classList.add("remove");
    btn.onclick = async () => {
      btn.disabled = true;
      try { await invoke("toggle_install", { kind: a.kind }); } catch (e) { alert(String(e)); }
      await loadAgents();
    };
    row.appendChild(btn);
    agentsRoot.appendChild(row);
  }
}

// ------------------------------------------------------------------ pet ----
// macOS model: the pager shows your INSTALLED pets (library); the full catalog
// lives in the Browse dialog where "Get" adds a pet to the library.
const current = document.getElementById("pet-current") as HTMLDivElement;
const search = document.getElementById("pet-search") as HTMLInputElement;
const results = document.getElementById("pet-results") as HTMLDivElement;

let catalog: Pet[] = [];

function selectedPet(): LibPet | undefined {
  const slug = savedSlug();
  if (!slug) return undefined;
  return getLibrary().find((p) => p.slug === slug);
}

async function pick(p: LibPet) {
  saveSlug(p.slug);
  localStorage.setItem("ap_pet_url", p.url);
  localStorage.removeItem("ap_pet_custom"); // legacy key
  await emit("set-pet", { slug: p.slug, url: p.url });
  showCurrent();
  renderPage();
}

function showCurrent() {
  const sel = selectedPet();
  const deselectBtn = document.getElementById("pet-deselect") as HTMLButtonElement | null;
  if (sel) {
    current.textContent = sel.name;
    if (deselectBtn) {
      deselectBtn.textContent = t("Use default pet");
      deselectBtn.style.display = "";
    }
  } else {
    current.textContent = t("Default pet");
    if (deselectBtn) deselectBtn.style.display = "none";
  }
  const hero = document.getElementById("hero-thumb") as HTMLCanvasElement;
  const ctx = hero.getContext("2d");
  if (ctx) ctx.clearRect(0, 0, hero.width, hero.height);
  if (sel) drawThumb(hero, sel.url);
  loadHeroDescription(sel);
}

/// Clear the user's explicit pet choice and fall back to the catalog default.
function deselectPet() {
  clearSlug();
  localStorage.removeItem("ap_pet_url");
  localStorage.removeItem("ap_pet_custom");
  emit("set-pet", { slug: null, url: null });
  showCurrent();
  renderPage();
}

// The pet's own description (from its pet.json on the CDN), like the macOS
// hero card; falls back to the generic caption.
async function loadHeroDescription(sel: LibPet | undefined) {
  const el = document.getElementById("hero-desc");
  if (!el) return;
  if (!sel?.petJsonUrl) { el.textContent = t("Pick the companion that floats on your desktop."); return; }
  try {
    const j: any = await (await fetch(sel.petJsonUrl)).json();
    const desc = (j.description || j.about || "").toString().trim();
    el.textContent = desc || t("Pick the companion that floats on your desktop.");
  } catch {
    el.textContent = t("Pick the companion that floats on your desktop.");
  }
}

// Pet pager , 8 per page (4 × 2) over the LIBRARY, hover ✕ to remove.
const PER_PAGE = 8;
let page = 0;

const pgPrev = document.getElementById("pg-prev") as HTMLButtonElement;
const pgNext = document.getElementById("pg-next") as HTMLButtonElement;
const pgInd = document.getElementById("pg-ind") as HTMLElement;

function libraryView(): LibPet[] {
  const q = search.value.trim().toLowerCase();
  const lib = getLibrary();
  return q ? lib.filter((p) => p.name.toLowerCase().includes(q)) : lib;
}

function renderPage() {
  const lib = getLibrary();
  (document.getElementById("pet-search-wrap") as HTMLElement).style.display = lib.length > 4 ? "" : "none"; // mac shows search only when >4
  (document.getElementById("lib-empty") as HTMLElement).hidden = lib.length > 0;
  const view = libraryView();
  const totalPages = Math.max(1, Math.ceil(view.length / PER_PAGE));
  if (page >= totalPages) page = totalPages - 1;
  results.innerHTML = "";
  for (const p of view.slice(page * PER_PAGE, page * PER_PAGE + PER_PAGE)) {
    const item = document.createElement("button");
    item.className = "pet-item";
    item.dataset.slug = p.slug;
    if (p.slug === savedSlug()) item.classList.add("sel");
    const cv = document.createElement("canvas");
    cv.width = 48; cv.height = 48; cv.className = "pet-thumb";
    drawThumb(cv, p.url);
    const label = document.createElement("span");
    label.textContent = p.name;
    const del = document.createElement("span");
    del.className = "pet-del";
    del.textContent = "✕";
    del.title = t("Remove");
    del.onclick = (ev) => {
      ev.stopPropagation();
      removeFromLibrary(p.slug);
      if (p.slug === savedSlug()) {
        // Removing the active pet clears the explicit choice so the main window
        // falls back to the catalog default instead of silently switching to
        // whatever happens to be library[0].
        clearSlug();
        localStorage.removeItem("ap_pet_url");
        localStorage.removeItem("ap_pet_custom");
        emit("set-pet", { slug: null, url: null });
      }
      showCurrent();
      renderPage();
    };
    item.appendChild(del);
    item.appendChild(cv);
    item.appendChild(label);
    item.onclick = () => pick(p);
    results.appendChild(item);
  }
  const pager = document.getElementById("pet-pager") as HTMLElement;
  pager.style.display = view.length > PER_PAGE ? "" : "none";
  pgPrev.disabled = page === 0;
  pgNext.disabled = page >= totalPages - 1;
  pgInd.innerHTML = "";
  if (totalPages <= 8) {
    for (let i = 0; i < totalPages; i++) {
      const d = document.createElement("span");
      d.className = "pg-dot" + (i === page ? " sel" : "");
      d.onclick = () => { page = i; renderPage(); };
      pgInd.appendChild(d);
    }
  } else {
    pgInd.textContent = `${page + 1} / ${totalPages}`;
  }
}
pgPrev.onclick = () => { if (page > 0) { page--; renderPage(); } };
pgNext.onclick = () => { page++; renderPage(); };

// Draws frame 0 (first column of the Idle row) of an 8x9 spritesheet as a preview.
function drawThumb(cv: HTMLCanvasElement, url: string) {
  const ctx = cv.getContext("2d");
  if (!ctx) return;
  ctx.imageSmoothingEnabled = false;
  const img = new Image();
  img.onload = () => {
    const fw = img.naturalWidth / 8, fh = img.naturalHeight / 9;
    if (!fw || !fh) return;
    const sc = Math.min(cv.width / fw, cv.height / fh);
    const dw = fw * sc, dh = fh * sc;
    ctx.clearRect(0, 0, cv.width, cv.height);
    ctx.drawImage(img, 0, 0, fw, fh, (cv.width - dw) / 2, (cv.height - dh) / 2, dw, dh);
  };
  img.src = url;
}

// Toggle for showing/hiding the main pet window (so users can run only extra decoration pets).
async function initMainPetVisibility() {
  const box = document.getElementById("show-main-pet") as HTMLInputElement | null;
  if (!box) return;
  try {
    box.checked = await invoke("get_pet_visible");
  } catch {
    box.checked = true;
  }
  box.addEventListener("change", () => {
    invoke("set_pet_visible", { visible: box.checked }).catch(() => {});
  });
}

async function initPet() {
  search.addEventListener("input", () => { page = 0; renderPage(); });
  document.getElementById("pet-deselect")?.addEventListener("click", deselectPet);
  renderPage();
  showCurrent();
  initBrowse();
  initCreate();
  // Seed the library on first run: the currently shown pet (or the catalog
  // default) becomes the first installed pet, so the pager is never empty.
  for (;;) {
    catalog = await loadCatalog();
    if (catalog.length) break;
    current.textContent = t("Couldn't load pets , check your internet connection.");
    await new Promise((r) => setTimeout(r, 15000));
  }
  if (!getLibrary().length) {
    const slug = savedSlug();
    const c = catalog.find((p) => p.slug === slug) ?? catalog[Math.floor(catalog.length / 2)];
    if (c) {
      addToLibrary({ slug: c.slug, name: c.name, url: c.spritesheetUrl, petJsonUrl: c.petJsonUrl });
      // Keep the three selection stores in sync so the Settings hero, the main
      // window, and the per-project fallback all agree on the default pet.
      saveSlug(c.slug);
      localStorage.setItem("ap_pet_url", c.spritesheetUrl);
    }
  }
  renderPage();
  showCurrent();
}

// -------------------------------------------------------------- browse ----
// The macOS BrowsePetsView: community pets first, Petdex shuffled, category
// segmented filter, search, Get/Added per row, lazy thumbnails.
interface RemotePet { slug: string; name: string; url: string; petJsonUrl?: string; kind: string; author: string; community: boolean }
let browseAll: RemotePet[] = [];
let bwCat = "all";
let bwShown = 0;
const BW_CHUNK = 60;

function initBrowse() {
  const modal = document.getElementById("browse-modal") as HTMLElement;
  const list = document.getElementById("bw-list") as HTMLElement;
  const status = document.getElementById("bw-status") as HTMLElement;
  const searchEl = document.getElementById("bw-search") as HTMLInputElement;

  (document.getElementById("open-browse") as HTMLButtonElement).onclick = async () => {
    modal.hidden = false;
    if (!browseAll.length) {
      status.style.display = "";
      status.textContent = t("Loading pets…");
      browseAll = await loadBrowseSources();
      if (!browseAll.length) {
        status.textContent = t("Couldn't load the pet library. Check your connection.");
        return;
      }
    }
    status.style.display = "none";
    repaint();
  };
  (document.getElementById("browse-done") as HTMLButtonElement).onclick = () => { modal.hidden = true; renderPage(); showCurrent(); };

  document.querySelectorAll<HTMLButtonElement>("#bw-cat button").forEach((b) => {
    b.onclick = () => {
      bwCat = b.dataset.v!;
      document.querySelectorAll("#bw-cat button").forEach((x) => x.classList.toggle("sel", x === b));
      repaint();
    };
  });
  searchEl.addEventListener("input", () => repaint());

  const thumbIO = new IntersectionObserver((entries) => {
    for (const e of entries) {
      if (!e.isIntersecting) continue;
      const cv = e.target as HTMLCanvasElement;
      thumbIO.unobserve(cv);
      drawThumb(cv, cv.dataset.url!);
    }
  }, { root: list, rootMargin: "200px" });

  function filtered(): RemotePet[] {
    let v = browseAll;
    if (bwCat !== "all") v = v.filter((p) => p.kind === bwCat);
    const q = searchEl.value.trim().toLowerCase();
    if (q) v = v.filter((p) => p.name.toLowerCase().includes(q) || p.slug.includes(q));
    return v;
  }

  function repaint() {
    list.innerHTML = "";
    bwShown = 0;
    appendChunk();
  }

  function appendChunk() {
    const v = filtered();
    const installed = new Set(getLibrary().map((p) => p.slug));
    for (const p of v.slice(bwShown, bwShown + BW_CHUNK)) {
      const row = document.createElement("div");
      row.className = "bw-row";
      const cv = document.createElement("canvas");
      cv.width = 44; cv.height = 48; cv.className = "bw-thumb";
      cv.dataset.url = p.url;
      thumbIO.observe(cv);
      const meta = document.createElement("div");
      meta.className = "bw-meta";
      meta.innerHTML = `<span class="bw-name">${esc(p.name)}${p.community ? ` <span class="bw-badge">${t("Community")}</span>` : ""}</span>` +
        `<span class="cap">${t("by")} ${esc(p.author)}</span>`;
      const btn = document.createElement("button");
      if (installed.has(p.slug)) {
        btn.className = "bw-added";
        btn.textContent = `✓ ${t("Added")}`;
        btn.disabled = true;
      } else {
        btn.className = "mini";
        btn.textContent = t("Get");
        btn.onclick = () => {
          addToLibrary({ slug: p.slug, name: p.name, url: p.url, petJsonUrl: p.petJsonUrl });
          void pick({ slug: p.slug, name: p.name, url: p.url, petJsonUrl: p.petJsonUrl });
          btn.className = "bw-added";
          btn.textContent = `✓ ${t("Added")}`;
          btn.disabled = true;
        };
      }
      row.appendChild(cv);
      row.appendChild(meta);
      row.appendChild(btn);
      list.appendChild(row);
    }
    bwShown = Math.min(bwShown + BW_CHUNK, v.length);
  }

  list.addEventListener("scroll", () => {
    if (list.scrollTop + list.clientHeight > list.scrollHeight - 300) appendChunk();
  });
}

/// Community manifest first, Petdex library shuffled after, deduped by slug.
async function loadBrowseSources(): Promise<RemotePet[]> {
  const norm = (p: any, community: boolean): RemotePet | null => {
    if (!p?.slug || !p?.spritesheetUrl) return null;
    const author = (p.submittedBy || "").trim() || "community";
    return { slug: p.slug, name: p.displayName ?? p.slug, url: p.spritesheetUrl,
      petJsonUrl: p.petJsonUrl, kind: p.kind ?? "creature", author, community };
  };
  const fetchList = async (url: string, community: boolean): Promise<RemotePet[]> => {
    try {
      const j: any = await (await fetch(url)).json();
      return (j.pets ?? []).map((p: any) => norm(p, community)).filter(Boolean);
    } catch { return []; }
  };
  const [community, library] = await Promise.all([
    fetchList("https://agentpet.thenightwatcher.online/api/pets", true),
    fetchList("https://pets.thenightwatcher.online/manifest.json", false),
  ]);
  for (let i = library.length - 1; i > 0; i--) { // shuffle like macOS
    const j = Math.floor(Math.random() * (i + 1));
    [library[i], library[j]] = [library[j], library[i]];
  }
  const seen = new Set<string>();
  return [...community, ...library].filter((p) => seen.has(p.slug) ? false : (seen.add(p.slug), true));
}

// -------------------------------------------------------------- create ----
function initCreate() {
  const modal = document.getElementById("create-modal") as HTMLElement;
  const name = document.getElementById("cr-name") as HTMLInputElement;
  const desc = document.getElementById("cr-desc") as HTMLInputElement;
  const fileName = document.getElementById("cr-file-name") as HTMLElement;
  const err = document.getElementById("cr-error") as HTMLElement;
  const createBtn = document.getElementById("cr-create") as HTMLButtonElement;
  let dataUrl = "";

  const filePick = document.createElement("input");
  filePick.type = "file";
  filePick.accept = "image/png,image/webp,image/*";
  filePick.style.display = "none";
  document.body.appendChild(filePick);

  const sync = () => { createBtn.disabled = !(name.value.trim() && dataUrl); };
  name.addEventListener("input", sync);

  (document.getElementById("open-create") as HTMLButtonElement).onclick = () => {
    modal.hidden = false;
    name.value = ""; desc.value = ""; dataUrl = "";
    fileName.textContent = t("No image selected");
    err.hidden = true;
    sync();
  };
  (document.getElementById("create-cancel") as HTMLButtonElement).onclick = () => { modal.hidden = true; };
  (document.getElementById("cr-choose") as HTMLButtonElement).onclick = () => {
    filePick.onchange = () => {
      const f = filePick.files?.[0];
      if (!f) return;
      const reader = new FileReader();
      reader.onload = () => {
        const img = new Image();
        img.onload = () => { dataUrl = String(reader.result); fileName.textContent = f.name; err.hidden = true; sync(); };
        img.onerror = () => { err.textContent = t("Could not create this pet. Check that the image is a valid spritesheet."); err.hidden = false; };
        img.src = String(reader.result);
      };
      reader.readAsDataURL(f);
      filePick.value = "";
    };
    filePick.click();
  };
  createBtn.onclick = () => {
    const slug = `local-${Date.now()}`;
    addToLibrary({ slug, name: name.value.trim(), url: dataUrl, custom: true });
    void pick({ slug, name: name.value.trim(), url: dataUrl, custom: true });
    modal.hidden = true;
    renderPage();
    showCurrent();
  };
}

// ----------------------------------------------------------- extra pets ----
// Pure-decoration pet windows: spawn extra pets that just float and roam,
// ignoring agents/care/tray. Multiple may be open at once; each is closed
// from the grid below or by closing its window directly.
const EXTRA_PREFIX = "pet-extra-";
const MAX_EXTRA_PETS = 12;

function slugFromExtraLabel(label: string): string {
  const rest = label.slice(EXTRA_PREFIX.length);
  const i = rest.lastIndexOf("-");
  return i > 0 ? rest.slice(0, i) : rest;
}

function initExtraPets() {
  const grid = document.getElementById("extra-grid") as HTMLDivElement;
  const emptyMsg = document.getElementById("extra-empty") as HTMLElement;
  const capMsg = document.getElementById("extra-cap-msg") as HTMLElement;
  const desktopWrap = document.getElementById("extra-desktop-wrap") as HTMLElement;
  const countEl = document.getElementById("extra-count") as HTMLElement;
  const runningEl = document.getElementById("extra-running") as HTMLDivElement;
  const closeAllBtn = document.getElementById("extra-close-all") as HTMLButtonElement;

  // Build a thumbnail card for a library pet, used in the spawn grid.
  const spawnCard = (p: LibPet): HTMLButtonElement => {
    const item = document.createElement("button");
    item.className = "pet-item spawn";
    const cv = document.createElement("canvas");
    cv.width = 48; cv.height = 48; cv.className = "pet-thumb";
    drawThumb(cv, p.url);
    const label = document.createElement("span");
    label.textContent = p.name;
    item.appendChild(cv);
    item.appendChild(label);
    item.onclick = async () => {
      if (item.classList.contains("disabled")) return;
      item.disabled = true;
      try { await invoke("spawn_extra_pet", { slug: p.slug }); }
      catch (e) { alert(String(e)); return; }
      finally { setTimeout(() => { item.disabled = false; }, 350); }
      void renderRunning();
    };
    return item;
  };

  // Build a thumbnail card for an already-spawned window, with a close ✕.
  const runningCard = (label: string, p?: LibPet): HTMLDivElement => {
    const item = document.createElement("div");
    item.className = "pet-item running";
    const del = document.createElement("span");
    del.className = "pet-del";
    del.textContent = "✕";
    del.title = t("Close");
    del.onclick = async (ev) => {
      ev.stopPropagation();
      try { await invoke("close_extra_pet", { label }); }
      catch (e) { alert(String(e)); return; }
      void renderRunning();
    };
    const cv = document.createElement("canvas");
    cv.width = 48; cv.height = 48; cv.className = "pet-thumb";
    if (p?.url) drawThumb(cv, p.url);
    const name = document.createElement("span");
    name.textContent = p?.name ?? slugFromExtraLabel(label);
    item.appendChild(del);
    item.appendChild(cv);
    item.appendChild(name);
    return item;
  };

  const renderGrid = () => {
    const lib = getLibrary();
    grid.innerHTML = "";
    if (!lib.length) {
      emptyMsg.hidden = false;
      grid.style.display = "none";
      return;
    }
    emptyMsg.hidden = true;
    grid.style.display = "";
    for (const p of lib) grid.appendChild(spawnCard(p));
  };

  const renderRunning = async () => {
    let labels: string[] = [];
    try { labels = await invoke<string[]>("list_extra_pets"); } catch { return; }
    const count = labels.length;
    countEl.textContent = count ? `(${count}/${MAX_EXTRA_PETS})` : "";
    const atCap = count >= MAX_EXTRA_PETS;
    capMsg.hidden = !atCap;
    grid.querySelectorAll<HTMLButtonElement>(".pet-item.spawn").forEach((b) => {
      b.classList.toggle("disabled", atCap);
    });
    if (!count) { desktopWrap.hidden = true; return; }
    desktopWrap.hidden = false;
    const lib = getLibrary();
    runningEl.innerHTML = "";
    for (const label of labels) {
      const slug = slugFromExtraLabel(label);
      runningEl.appendChild(runningCard(label, lib.find((x) => x.slug === slug)));
    }
  };

  closeAllBtn.onclick = async () => {
    let labels: string[] = [];
    try { labels = await invoke<string[]>("list_extra_pets"); } catch { return; }
    if (!labels.length) return;
    closeAllBtn.disabled = true;
    await Promise.all(labels.map((l) => invoke("close_extra_pet", { label: l }).catch(() => {})));
    closeAllBtn.disabled = false;
    void renderRunning();
  };

  renderGrid();
  void renderRunning();
  // Poll: extra windows can be closed via the OS, and the library may change
  // from Browse/Create without a tab switch, so sync both every 2s.
  let lastLibLen = -1;
  setInterval(() => {
    const len = getLibrary().length;
    if (len !== lastLibLen) { lastLibLen = len; renderGrid(); }
    void renderRunning();
  }, 2000);
  document.addEventListener("ap-pet-tab-shown", () => { renderGrid(); void renderRunning(); });
}

// ---------------------------------------------------------------- bubble ----
const MSG_STATES: [string, string][] = [
  ["working", "Working"], ["waiting", "Needs you"], ["done", "Done"],
  ["celebrate", "Celebrate"], ["idle", "Idle"],
];
const MSG_AGENTS: [string, string][] = [
  ["all", "All agents"], ["claude", "Claude Code"], ["codex", "Codex"], ["gemini", "Gemini CLI"],
  ["cursor", "Cursor"], ["opencode", "opencode"], ["windsurf", "Windsurf"],
  ["antigravity", "Antigravity"], ["copilot", "GitHub Copilot"], ["kiro", "Kiro CLI"],
];

function initBubble() {
  const changed = () => { emit("bubble-changed", null); };
  const opacity = document.getElementById("opacity") as HTMLInputElement;
  const msgAgent = document.getElementById("msg-agent") as HTMLSelectElement;
  const editors = document.getElementById("msg-editors")!;

  opacity.value = localStorage.getItem("ap_opacity") || "92";
  opacity.oninput = () => {
    localStorage.setItem("ap_opacity", opacity.value);
    changed();
    document.dispatchEvent(new CustomEvent("seg-changed", { detail: "ap_opacity" }));
  };

  // Multi-agent bubble master toggle (mac BubbleSettings.multiAgentBubbleEnabled).
  const multi = document.getElementById("multi") as HTMLInputElement;
  multi.checked = localStorage.getItem("ap_multi") !== "0";
  multi.onchange = () => { localStorage.setItem("ap_multi", multi.checked ? "1" : "0"); changed(); };

  msgAgent.innerHTML = "";
  for (const [k, name] of MSG_AGENTS) {
    const o = document.createElement("option");
    o.value = k;
    o.textContent = k === "all" ? t("All agents") : name; // brand names stay
    msgAgent.appendChild(o);
  }

  const build = (agent: string) => {
    editors.innerHTML = "";
    for (const [st, label] of MSG_STATES) {
      const wrap = document.createElement("div");
      wrap.className = "msg-editor";
      const lbl = document.createElement("div");
      lbl.className = "msg-label";
      lbl.dataset.label = label;
      lbl.textContent = t(label) + (st === "working" ? ` ${t("(blank = live activity)")}` : "");
      const ta = document.createElement("textarea");
      const key = `ap_msg_${agent}_${st}`;
      ta.value = localStorage.getItem(key) || "";
      ta.addEventListener("input", () => { localStorage.setItem(key, ta.value); changed(); });
      wrap.appendChild(lbl);
      wrap.appendChild(ta);
      editors.appendChild(wrap);
    }
  };
  msgAgent.onchange = () => build(msgAgent.value);
  build("all");

  // System/custom source (segmented, saved by initSegs) + reset.
  const customWrap = document.getElementById("msg-custom-wrap") as HTMLElement;
  const syncSrc = () => { customWrap.style.display = (localStorage.getItem("ap_msg_src") || "system") === "custom" ? "" : "none"; };
  syncSrc();
  document.addEventListener("seg-changed", (e) => { if ((e as CustomEvent).detail === "ap_msg_src") syncSrc(); });
  (document.getElementById("msg-reset") as HTMLButtonElement).onclick = () => {
    for (const [st] of MSG_STATES) localStorage.removeItem(`ap_msg_${msgAgent.value}_${st}`);
    build(msgAgent.value);
    changed();
  };

  const phrases = document.getElementById("phrases") as HTMLSelectElement;
  const savedTheme = localStorage.getItem("ap_theme_phrases") || "chef";
  phrases.value = savedTheme === "off" ? "chef" : savedTheme; // pre-port "off" → chef
  phrases.onchange = () => { localStorage.setItem("ap_theme_phrases", phrases.value); changed(); };

  const idle = document.getElementById("idle") as HTMLInputElement;
  idle.checked = localStorage.getItem("ap_idle") !== "0";
  idle.onchange = () => { localStorage.setItem("ap_idle", idle.checked ? "1" : "0"); changed(); };

  const reactive = document.getElementById("reactive") as HTMLInputElement;
  reactive.checked = localStorage.getItem("ap_reactive") !== "0";
  reactive.onchange = () => { localStorage.setItem("ap_reactive", reactive.checked ? "1" : "0"); changed(); };

  const split = document.getElementById("split") as HTMLInputElement;
  const splitList = document.getElementById("split-list") as HTMLElement;
  const renderSplitList = () => {
    splitList.style.display = split.checked ? "" : "none";
    splitList.innerHTML = "";
    if (!split.checked) return;
    const lib = getLibrary();
    const map = projectpets.projectPetMap();
    const projects = usage.knownProjects();
    if (!projects.length) {
      const p = document.createElement("div");
      p.className = "cap";
      p.textContent = t("No projects yet. Use an agent in a project first.");
      splitList.appendChild(p);
      return;
    }
    for (const proj of projects) {
      const row = document.createElement("label");
      row.className = "row";
      const name = document.createElement("span");
      name.className = "rt";
      name.textContent = proj.name;
      const sel = document.createElement("select");
      const none = document.createElement("option");
      none.value = "";
      none.textContent = t("Merged");
      sel.appendChild(none);
      for (const p of lib) {
        const o = document.createElement("option");
        o.value = p.slug;
        o.textContent = p.name;
        if (map[proj.id] === p.slug) o.selected = true;
        sel.appendChild(o);
      }
      sel.onchange = () => { projectpets.setProjectPet(proj.id, sel.value); emit("split-changed"); };
      row.appendChild(name);
      row.appendChild(sel);
      splitList.appendChild(row);
    }
  };
  split.checked = projectpets.splitEnabled();
  split.onchange = () => { projectpets.setSplit(split.checked); renderSplitList(); emit("split-changed"); };
  renderSplitList();
}

// -------------------------------------------------- bubble display + layout ----
function initBubbleDisplay() {
  const changed = () => { emit("bubble-changed", null); };
  const bind = (id: string, key: string, dflt: string) => {
    const el = document.getElementById(id) as HTMLSelectElement;
    el.value = localStorage.getItem(key) || dflt;
    el.onchange = () => { localStorage.setItem(key, el.value); changed(); paintPreview(); };
  };
  bind("bub-filter", "ap_bub_filter", "all");

  // Detail captions + conditional rows, mirroring the macOS pickers.
  const MODE_DETAIL: Record<string, string> = {
    list: "Show every row at once, up to the max below.",
    carousel: "One row at a time. Auto-cycles every 3 s.",
    compact: "Summary header, first two rows, then fold the rest.",
  };
  const GROUP_DETAIL: Record<string, string> = {
    byKind: "One row per agent kind (×N when multiple)",
    all: "One row per session",
  };
  const syncDisplay = () => {
    const mode = localStorage.getItem("ap_bub_mode") || "carousel";
    const grouping = localStorage.getItem("ap_bub_grouping") || "byKind";
    (document.getElementById("bub-mode-detail") as HTMLElement).textContent = t(MODE_DETAIL[mode] ?? "");
    (document.getElementById("bub-grouping-detail") as HTMLElement).textContent = t(GROUP_DETAIL[grouping] ?? "");
    (document.getElementById("maxrows-row") as HTMLElement).style.display = mode === "carousel" ? "none" : "";
    (document.getElementById("sortkind-row") as HTMLElement).style.display = grouping === "all" ? "" : "none";
  };
  syncDisplay();
  const sortkind = document.getElementById("bub-sortkind") as HTMLInputElement;
  sortkind.checked = localStorage.getItem("ap_bub_sortkind") === "1";
  sortkind.onchange = () => { localStorage.setItem("ap_bub_sortkind", sortkind.checked ? "1" : "0"); changed(); };

  // Segmented controls (mode/grouping/sep/dot) save via initSegs; repaint the
  // preview row + captions when one changes.
  document.addEventListener("seg-changed", () => { paintPreview(); syncDisplay(); });

  const max = document.getElementById("bub-max") as HTMLInputElement;
  max.value = localStorage.getItem("ap_bub_max") || "5";
  max.oninput = () => { localStorage.setItem("ap_bub_max", max.value); changed(); };

  // Visible agents (hiddenKinds).
  const visRoot = document.getElementById("bub-visible")!;
  const hidden = new Set<string>(JSON.parse(localStorage.getItem("ap_bub_hidden") || "[]"));
  for (const [kind, name] of MSG_AGENTS.slice(1)) {
    const row = document.createElement("label");
    row.className = "row";
    const span = document.createElement("span");
    span.textContent = name;
    const box = document.createElement("input");
    box.type = "checkbox";
    box.checked = !hidden.has(kind);
    box.onchange = () => {
      if (box.checked) hidden.delete(kind); else hidden.add(kind);
      localStorage.setItem("ap_bub_hidden", JSON.stringify([...hidden]));
      changed();
    };
    row.appendChild(span);
    row.appendChild(box);
    visRoot.appendChild(row);
  }

  // Row content: colored chips (mac PaletteChip/CanvasChip) , a palette row
  // of addable tokens and an active row with removable ones, in order.
  const tokensRoot = document.getElementById("bub-tokens")!;
  const paletteRoot = document.getElementById("bub-palette")!;
  const readTokens = (): TokenItem[] => readBubbleConfig().tokens;
  const saveTokens = (tokens: TokenItem[]) => {
    localStorage.setItem("ap_bub_tokens", JSON.stringify(tokens));
    changed();
    paintTokens();
    paintPreview();
  };
  const TOKEN_META: Record<BubbleToken, { name: string; sym: string; color: string }> = {
    dot:        { name: "Dot",     sym: "circle",     color: "#ff9f0a" },
    icon:       { name: "Icon",    sym: "sparkle",    color: "#bf5af2" },
    title:      { name: "Title",   sym: "quote",      color: "#0a84ff" },
    project:    { name: "Project", sym: "folder",     color: "#30d158" },
    separator:  { name: "Sep",     sym: "arrowRight", color: "#98989d" },
    message:    { name: "Message", sym: "message",    color: "#5e5ce6" },
    stateLabel: { name: "State",   sym: "tag",        color: "#ffd60a" },
    elapsed:    { name: "Elapsed", sym: "clock",      color: "#40c8e0" },
  };
  function chip(tokenItem: TokenItem, active: boolean): HTMLButtonElement {
    const m = TOKEN_META[tokenItem.token];
    const b = document.createElement("button");
    b.className = "tok-chip2";
    b.style.setProperty("--tc", m.color);
    b.innerHTML = `<span class="tc-sym">${uiIcon(m.sym)}</span> ${t(m.name)} <span class="tc-act">${active ? "✕" : "＋"}</span>`;
    b.onclick = () => {
      const tokens = readTokens().map((x) =>
        x.token === tokenItem.token ? { ...x, isVisible: !active } : x);
      saveTokens(tokens);
    };
    return b;
  }
  function paintTokens() {
    tokensRoot.innerHTML = "";
    paletteRoot.innerHTML = "";
    for (const item of readTokens()) {
      (item.isVisible ? tokensRoot : paletteRoot).appendChild(chip(item, item.isVisible));
    }
    paletteRoot.style.display = paletteRoot.childElementCount ? "" : "none";
  }
  document.querySelectorAll<HTMLButtonElement>(".preset-btns button").forEach((b) => {
    b.onclick = () => saveTokens(LAYOUT_PRESETS[b.dataset.preset!]);
  });

  // Mock preview row (mac BubbleRowPreview).
  const preview = document.getElementById("bub-preview")!;
  function paintPreview() {
    const cfg = readBubbleConfig();
    preview.innerHTML = "";
    const row = document.createElement("div");
    row.className = "pv-row";
    for (const item of cfg.tokens) {
      if (!item.isVisible) continue;
      switch (item.token) {
        case "dot": { const d = document.createElement("span"); d.className = "pv-dot"; row.appendChild(d); break; }
        case "icon": {
          const img = document.createElement("img");
          img.className = "aicon"; img.src = agentIconUrl("claude") || ""; row.appendChild(img); break;
        }
        case "title": { const s = document.createElement("span"); s.className = "pv-strong"; s.textContent = "Fix login bug"; row.appendChild(s); break; }
        case "project": { const s = document.createElement("span"); s.className = "pv-strong"; s.textContent = "desktoppet"; row.appendChild(s); break; }
        case "separator": { const s = document.createElement("span"); s.className = "pv-dim"; s.textContent = cfg.separator; row.appendChild(s); break; }
        case "message": { const s = document.createElement("span"); s.textContent = "Editing SettingsModel.swift"; row.appendChild(s); break; }
        case "stateLabel": { const s = document.createElement("span"); s.className = "pv-dim"; s.textContent = t("Working"); row.appendChild(s); break; }
        case "elapsed": { const s = document.createElement("span"); s.className = "pv-dim"; s.textContent = "3m"; row.appendChild(s); break; }
      }
    }
    if (!row.childElementCount) { row.textContent = t("(empty)"); row.classList.add("pv-dim"); }
    row.style.fontSize = `${parseInt(localStorage.getItem("ap_font_size") || "12", 10) || 12}px`;
    row.style.opacity = String((parseInt(localStorage.getItem("ap_opacity") || "92", 10) || 92) / 100);
    preview.appendChild(row);
    row.style.display = "inline-flex";
  }

  paintTokens();
  paintPreview();
}

// ----------------------------------------------- pet size / fx / import ----
function initPetControls() {
  const changed = () => { emit("bubble-changed", null); };
  const size = document.getElementById("pet-size") as HTMLInputElement;
  size.value = localStorage.getItem("ap_pet_size") || "100";
  size.oninput = () => { localStorage.setItem("ap_pet_size", size.value); changed(); };
  document.querySelectorAll<HTMLButtonElement>(".size-presets button").forEach((b) => {
    b.onclick = () => {
      size.value = b.dataset.size!;
      localStorage.setItem("ap_pet_size", size.value);
      size.dispatchEvent(new Event("input"));
      changed();
    };
  });

  const roamMode = document.getElementById("roam-mode") as HTMLSelectElement;
  const roamSpeed = document.getElementById("roam-speed") as HTMLInputElement;
  const roamSpeedVal = document.getElementById("roam-speed-val") as HTMLSpanElement;
  roamMode.value = getRoamMode();
  roamSpeed.value = String(getRoamSpeed());
  roamSpeedVal.textContent = roamSpeed.value;
  roamMode.onchange = () => { setRoamMode(roamMode.value as "wander" | "cursor" | "stay" | "climb"); };
  roamSpeed.oninput = () => {
    const v = parseInt(roamSpeed.value, 10);
    setRoamSpeed(v);
    roamSpeedVal.textContent = String(v);
  };
}

// ------------------------------------------------------------- agent icons ----
// Per-agent icon override (mac BubbleSettings.iconChoices): brand logo of any
// agent, or a symbol. Stored as ap_icon_<kind> = "brand:<kind>" | "emoji:<char>".
const ICON_SYMBOLS = ["terminal","zap","star","heart","cloud","moon","sun","anchor","box","code","command","compass","cpu","gift","globe","layers","target","rocket"];

export function iconChoiceLabel(kind: string): { type: "brand"; kind: string } | { type: "sym"; v: string } {
  const raw = localStorage.getItem(`ap_icon_${kind}`);
  if (raw?.startsWith("sym:")) return { type: "sym", v: raw.slice(4) };
  if (raw?.startsWith("brand:")) return { type: "brand", kind: raw.slice(6) };
  return { type: "brand", kind };
}

function iconCellHtml(kind: string): string {
  const c = iconChoiceLabel(kind);
  if (c.type === "sym") return `<span class="ic-sym">${uiIcon(c.v)}</span>`;
  const url = agentIconUrl(c.kind);
  return url ? `<img class="aicon" src="${url}">` : "";
}

function initAgentIcons() {
  const root = document.getElementById("agent-icons")!;
  const modal = document.getElementById("icon-modal") as HTMLElement;
  const brands = document.getElementById("ic-brands") as HTMLElement;
  const symbols = document.getElementById("ic-symbols") as HTMLElement;
  let editing = "claude";

  const paintRows = () => {
    root.innerHTML = "";
    for (const [kind, name] of MSG_AGENTS.slice(1)) {
      const row = document.createElement("div");
      row.className = "row";
      row.innerHTML = `<span class="ic-cur">${iconCellHtml(kind)} ${esc(name)}</span>`;
      const btn = document.createElement("button");
      btn.className = "mini";
      btn.textContent = t("Change…");
      btn.onclick = () => { editing = kind; openPicker(name); };
      row.appendChild(btn);
      root.appendChild(row);
    }
  };

  const paintPicker = () => {
    const cur = localStorage.getItem(`ap_icon_${editing}`) ?? `brand:${editing}`;
    brands.innerHTML = "";
    for (const [kind] of MSG_AGENTS.slice(1)) {
      const url = agentIconUrl(kind);
      if (!url) continue;
      const cell = document.createElement("button");
      cell.className = "icon-cell" + (cur === `brand:${kind}` ? " sel" : "");
      cell.innerHTML = `<img class="aicon" src="${url}">`;
      cell.onclick = () => { localStorage.setItem(`ap_icon_${editing}`, `brand:${kind}`); finish(); };
      brands.appendChild(cell);
    }
    symbols.innerHTML = "";
    for (const sym of ICON_SYMBOLS) {
      const cell = document.createElement("button");
      cell.className = "icon-cell ic-sym" + (cur === `sym:${sym}` ? " sel" : "");
      cell.innerHTML = uiIcon(sym);
      cell.onclick = () => { localStorage.setItem(`ap_icon_${editing}`, `sym:${sym}`); finish(); };
      symbols.appendChild(cell);
    }
  };

  const openPicker = (name: string) => {
    (document.getElementById("icon-modal-title") as HTMLElement).textContent = `${t("Icon for")} ${name}`;
    paintPicker();
    modal.hidden = false;
  };
  const finish = () => {
    modal.hidden = true;
    paintRows();
    emit("bubble-changed", null);
  };
  (document.getElementById("icon-done") as HTMLButtonElement).onclick = () => { modal.hidden = true; };
  (document.getElementById("icon-reset") as HTMLButtonElement).onclick = () => {
    localStorage.removeItem(`ap_icon_${editing}`);
    finish();
  };
  paintRows();
}

// ------------------------------------------------------------ animations ----
// The macOS AnimationPicker: a segmented mood selector over a grid of clip
// thumbnails sliced from the current pet's sheet. Hover = animated preview.
// Non-idle moods use single-select binding (ap_bind_<mood>). The idle mood
// uses multi-select: the checked clips form a playlist cycled while idle.
const MOOD_DEFAULT_ROW: Record<string, number> = { idle: 0, working: 7, waiting: 6, done: 3, celebrate: 4 };

const IDLE_CLIPS_KEY = "ap_idle_clips";
const IDLE_MODE_KEY = "ap_idle_mode";
const IDLE_INTERVAL_KEY = "ap_idle_interval";
const DEFAULT_IDLE_INTERVAL = 5;

function initAnimations() {
  const grid = document.getElementById("anim-grid")!;
  const moodSeg = document.getElementById("anim-mood")!;
  let mood = "working";
  let img: HTMLImageElement | null = null;
  let clips: Rect[][] = [];
  let hoverTimer: number | null = null;

  // Container for idle-only controls (mode + interval); injected below the grid.
  const idleWrap = document.createElement("div");
  idleWrap.className = "idle-playlist-wrap";
  grid.parentElement!.appendChild(idleWrap);

  const boundClip = (m: string) => {
    const v = parseInt(localStorage.getItem(`ap_bind_${m}`) ?? "", 10);
    return Number.isFinite(v) && v >= 0 ? Math.min(v, Math.max(0, clips.length - 1)) : Math.min(MOOD_DEFAULT_ROW[m] ?? 0, Math.max(0, clips.length - 1));
  };

  const readIdleClips = (): number[] => {
    try {
      const v = JSON.parse(localStorage.getItem(IDLE_CLIPS_KEY) || "[]");
      if (Array.isArray(v) && v.length) return v.filter((x) => Number.isFinite(x) && x >= 0).map((x) => Number(x));
    } catch {}
    return clips.length ? [boundClip("idle")] : [];
  };
  const saveIdleClips = (vals: number[]) => {
    const clean = vals.filter((x) => Number.isFinite(x) && x >= 0).map((x) => Number(x));
    localStorage.setItem(IDLE_CLIPS_KEY, JSON.stringify(clean));
    emit("bubble-changed", null);
  };
  const readIdleMode = () => localStorage.getItem(IDLE_MODE_KEY) || "random";
  const readIdleInterval = () => {
    const n = Number.parseFloat(localStorage.getItem(IDLE_INTERVAL_KEY) ?? "");
    return Number.isFinite(n) && n >= 1 ? n : DEFAULT_IDLE_INTERVAL;
  };

  const drawFrame = (cv: HTMLCanvasElement, clip: Rect[], frame: number) => {
    const ctx = cv.getContext("2d");
    if (!ctx || !img || !clip.length) return;
    const r = clip[frame % clip.length];
    const maxW = Math.max(...clip.map((x) => x.w));
    const sc = Math.min(cv.width / maxW, cv.height / r.h);
    const dw = r.w * sc, dh = r.h * sc;
    ctx.imageSmoothingEnabled = false;
    ctx.clearRect(0, 0, cv.width, cv.height);
    ctx.drawImage(img, r.x, r.y, r.w, r.h, (cv.width - dw) / 2, cv.height - dh, dw, dh);
  };

  const paint = () => {
    grid.innerHTML = "";
    if (!clips.length) { idleWrap.style.display = "none"; return; }

    const isIdle = mood === "idle";
    const idleSelected = new Set(readIdleClips());
    const currentBinding = boundClip(mood);

    clips.forEach((clip, i) => {
      const cell = document.createElement("button");
      const selected = isIdle ? idleSelected.has(i) : i === currentBinding;
      cell.className = "anim-cell" + (selected ? " sel" : "");
      const cv = document.createElement("canvas");
      cv.width = 54; cv.height = 44;
      drawFrame(cv, clip, 0);
      const label = document.createElement("span");
      label.className = "cap";
      label.textContent = `${t("Clip")} ${i + 1}`;
      cell.appendChild(cv);
      cell.appendChild(label);
      cell.onclick = () => {
        if (isIdle) {
          // Multi-select playlist; never leave it empty.
          if (idleSelected.has(i) && idleSelected.size <= 1) return;
          if (idleSelected.has(i)) idleSelected.delete(i);
          else idleSelected.add(i);
          saveIdleClips(Array.from(idleSelected).sort((a, b) => a - b));
        } else {
          localStorage.setItem(`ap_bind_${mood}`, String(i));
        }
        emit("bubble-changed", null);
        paint();
      };
      // Hover = animate this clip (mac hover preview).
      cell.onmouseenter = () => {
        let f = 0;
        if (hoverTimer) clearInterval(hoverTimer);
        hoverTimer = window.setInterval(() => drawFrame(cv, clip, ++f), 125);
      };
      cell.onmouseleave = () => {
        if (hoverTimer) clearInterval(hoverTimer);
        hoverTimer = null;
        drawFrame(cv, clip, 0);
      };
      grid.appendChild(cell);
    });
    paintIdleControls();
  };

  const paintIdleControls = () => {
    idleWrap.innerHTML = "";
    idleWrap.style.display = mood === "idle" && clips.length ? "block" : "none";
    if (mood !== "idle" || !clips.length) return;

    const title = document.createElement("div");
    title.className = "idle-title";
    title.textContent = t("Idle animations");
    idleWrap.appendChild(title);

    const note = document.createElement("div");
    note.className = "cap";
    note.style.cssText = "margin: 0 0 8px; color: rgba(255,255,255,0.55);";
    note.textContent = t("Pick clips to cycle while idle.");
    idleWrap.appendChild(note);

    const toolbar = document.createElement("div");
    toolbar.className = "idle-toolbar";

    const allBtn = document.createElement("button");
    allBtn.className = "link";
    allBtn.textContent = t("Select all");
    allBtn.onclick = () => { saveIdleClips(clips.map((_, i) => i)); paint(); };

    const clearBtn = document.createElement("button");
    clearBtn.className = "link";
    clearBtn.textContent = t("Clear");
    clearBtn.onclick = () => { saveIdleClips([boundClip("idle")]); paint(); };

    toolbar.appendChild(allBtn);
    toolbar.appendChild(clearBtn);
    idleWrap.appendChild(toolbar);

    const modeRow = document.createElement("div");
    modeRow.className = "idle-mode-row";
    const modeLabel = document.createElement("span");
    modeLabel.className = "cap";
    modeLabel.textContent = t("Mode");
    modeRow.appendChild(modeLabel);

    const modeSeg = document.createElement("span");
    modeSeg.className = "seg";
    for (const [v, label] of [["random", t("Random")], ["sequential", t("Sequential")]] as const) {
      const b = document.createElement("button");
      b.textContent = label;
      b.classList.toggle("sel", readIdleMode() === v);
      b.onclick = () => {
        localStorage.setItem(IDLE_MODE_KEY, v);
        paintIdleControls();
      };
      modeSeg.appendChild(b);
    }
    modeRow.appendChild(modeSeg);
    idleWrap.appendChild(modeRow);

    const intRow = document.createElement("div");
    intRow.className = "idle-interval-row";
    const intLabel = document.createElement("span");
    intLabel.className = "cap";
    intLabel.textContent = t("Interval");
    intRow.appendChild(intLabel);

    const intInput = document.createElement("input");
    intInput.type = "number";
    intInput.min = "1";
    intInput.step = "1";
    intInput.value = String(readIdleInterval());
    intInput.onchange = () => {
      const n = Number.parseFloat(intInput.value);
      localStorage.setItem(IDLE_INTERVAL_KEY, String(Number.isFinite(n) && n >= 1 ? n : DEFAULT_IDLE_INTERVAL));
      emit("bubble-changed", null);
    };
    intRow.appendChild(intInput);

    const intUnit = document.createElement("span");
    intUnit.className = "cap";
    intUnit.textContent = t("seconds");
    intRow.appendChild(intUnit);
    idleWrap.appendChild(intRow);
  };

  moodSeg.querySelectorAll<HTMLButtonElement>("button").forEach((b) => {
    b.onclick = () => {
      mood = b.dataset.v!;
      moodSeg.querySelectorAll("button").forEach((x) => x.classList.toggle("sel", x === b));
      paint();
    };
  });

  const loadSheet = () => {
    const lib = getLibrary();
    const sel = lib.find((x) => x.slug === savedSlug()) ?? lib[0];
    const url = localStorage.getItem("ap_pet_custom") || localStorage.getItem("ap_pet_url") || sel?.url;
    if (!url) { setTimeout(loadSheet, 3000); return; } // library may seed late
    const im = new Image();
    im.crossOrigin = "anonymous";
    im.onload = () => { img = im; clips = slice(im); paint(); };
    im.onerror = () => { img = null; clips = []; grid.innerHTML = ""; };
    im.src = url.startsWith("data:") ? url : url + (url.includes("?") ? "&" : "?") + "cors=1";
  };
  loadSheet();
  listen("set-pet", () => setTimeout(loadSheet, 50));
}

// ----------------------------------------------------------------- sounds ----
let settingsAudioCtx: AudioContext | null = null;
function playSound(ev: "done" | "waiting") {
  const data = localStorage.getItem(`ap_sound_${ev}_data`);
  if (data) {
    try { void new Audio(data).play(); return; } catch {}
  }
  try {
    settingsAudioCtx = settingsAudioCtx || new AudioContext();
    const o = settingsAudioCtx.createOscillator();
    const g = settingsAudioCtx.createGain();
    o.type = "sine";
    o.frequency.value = ev === "done" ? 880 : 560;
    g.gain.value = 0.05;
    o.connect(g);
    g.connect(settingsAudioCtx.destination);
    o.start();
    o.stop(settingsAudioCtx.currentTime + 0.13);
  } catch {}
}

function initSounds() {
  const filePick = document.createElement("input");
  filePick.type = "file";
  filePick.accept = "audio/*";
  filePick.style.display = "none";
  document.body.appendChild(filePick);

  const syncNames = () => {
    for (const ev of ["done", "waiting"] as const) {
      const name = localStorage.getItem(`ap_sound_${ev}_name`);
      (document.getElementById(`sound-${ev}-name`) as HTMLElement).textContent = name || t("Default");
      (document.getElementById(`t-df-${ev}`) as HTMLElement).style.display = name ? "" : "none";
    }
  };
  syncNames();

  document.querySelectorAll<HTMLButtonElement>(".sound-btns .mini").forEach((b) => {
    const ev = b.dataset.ev as "done" | "waiting";
    b.onclick = () => {
      switch (b.dataset.act) {
        case "play": playSound(ev); break;
        case "reset":
          localStorage.removeItem(`ap_sound_${ev}_data`);
          localStorage.removeItem(`ap_sound_${ev}_name`);
          syncNames();
          break;
        case "upload":
          filePick.onchange = () => {
            const f = filePick.files?.[0];
            if (!f) return;
            if (f.size > 2_000_000) { alert(t("Sound file too large (max 2 MB)")); return; }
            const reader = new FileReader();
            reader.onload = () => {
              localStorage.setItem(`ap_sound_${ev}_data`, String(reader.result));
              localStorage.setItem(`ap_sound_${ev}_name`, f.name);
              syncNames();
              playSound(ev); // preview, like macOS
            };
            reader.readAsDataURL(f);
            filePick.value = "";
          };
          filePick.click();
          break;
      }
    };
  });
}

// --------------------------------------------------------- notifications ----
function initNotify() {
  const box = document.getElementById("notify") as HTMLInputElement;
  box.checked = localStorage.getItem("ap_notify") !== "0";
  box.addEventListener("change", () => localStorage.setItem("ap_notify", box.checked ? "1" : "0"));
  // Per-event sound toggles (mac SoundSettings); legacy ap_sound seeds both.
  const legacyOff = localStorage.getItem("ap_sound") === "0";
  for (const ev of ["done", "waiting"] as const) {
    const el = document.getElementById(`sound-${ev}`) as HTMLInputElement;
    const key = `ap_sound_${ev}`;
    el.checked = (localStorage.getItem(key) ?? (legacyOff ? "0" : "1")) !== "0";
    el.addEventListener("change", () => localStorage.setItem(key, el.checked ? "1" : "0"));
  }
  (document.getElementById("codex-help-close") as HTMLButtonElement).onclick = () => {
    (document.getElementById("codex-help") as HTMLElement).hidden = true;
  };
}

// --------------------------------------------------------------- startup ----
async function initAutostart() {
  const box = document.getElementById("autostart") as HTMLInputElement;
  try { box.checked = await isEnabled(); } catch {}
  box.addEventListener("change", async () => {
    try { box.checked ? await enable() : await disable(); } catch (e) { alert(String(e)); }
  });
}

// --------------------------------------------------------------- motion ----
function initReduceMotion() {
  const box = document.getElementById("reduce-motion") as HTMLInputElement;
  const apply = () => {
    const on = box.checked;
    localStorage.setItem("ap_reduce_motion", on ? "1" : "0");
    document.body.classList.toggle("reduce-motion", on);
  };
  box.checked = localStorage.getItem("ap_reduce_motion") === "1";
  box.addEventListener("change", apply);
  apply();
}

// ----------------------------------------------------------------- icons ----
/// Fill every `<span class="ui-ic" data-icon="name">` with the matching SVG.
function initIcons() {
  document.querySelectorAll<HTMLElement>(".ui-ic[data-icon]").forEach((el) => {
    const name = el.dataset.icon;
    if (!name) return;
    const svg = uiIcon(name);
    if (svg) el.innerHTML = svg;
  });
}

// ----------------------------------------------------------------- i18n ----
function applyStatic() {
  document.documentElement.lang = getLang();
  const set = (id: string, key: string) => { const el = document.getElementById(id); if (el) el.textContent = t(key); };
  // tabs
  set("tab-general", "General");
  set("tab-pet", "Pet");
  set("tab-bubble", "Bubble");
  set("tab-care", "Care");
  set("tab-advanced", "Advanced");
  // page titles / subtitles
  set("t-pet-title", "Your companion");
  set("t-pet-subtitle", "Choose, dress up, and animate your desktop pet.");
  set("t-bubble-title", "Bubble");
  set("t-bubble-subtitle", "Appearance, style, and quick messages.");
  set("t-care-title", "Care");
  set("t-care-subtitle", "Feed, level up, and check in on your companion.");
  set("t-general-title", "General");
  set("t-general-subtitle", "Language, launch, notifications, and app info.");
  set("t-advanced-title", "Advanced");
  set("t-advanced-subtitle", "Integrations, multi-agent bubble, and history.");
  // general
  set("t-lang", "Language");
  set("t-lang2", "Language");
  set("t-startup", "Launch");
  set("t-autostart", "Launch at login");
  set("t-autostart-sub", "DesktopPet starts automatically when you sign in.");
  set("t-notif", "Notifications");
  set("t-notify", "Notifications on");
  set("t-notify-sub", "Alerts when something needs your attention.");
  set("t-motion", "Motion");
  set("t-reduce-motion", "Reduce motion");
  set("t-reduce-motion-sub", "Disable idle animations and visual effects to lower GPU usage.");
  set("t-sounds", "Sounds");
  set("t-sound-done", "When a task finishes");
  set("t-sound-waiting", "When your pet needs you");
  set("t-up-done", "Upload…");
  set("t-up-waiting", "Upload…");
  set("t-df-done", "Default");
  set("t-df-waiting", "Default");
  set("t-app", "About");
  set("t-agents", "Agent integrations");
  set("t-agents-foot", "Install a hook so DesktopPet can mirror your coding agents in the bubble.");
  set("t-version", "Version");
  set("quit-btn", "Quit DesktopPet");
  // pet
  set("t-pet-sub", "Pick the companion that floats on your desktop.");
  set("t-show-main", "Show main pet");
  set("t-show-main-sub", "The pet that tracks your agents and earns XP. Uncheck to hide it and use only extra decoration pets.");
  set("t-choose", "Choose pet");
  set("t-lib-empty", "No pets yet. Tap Browse to add one.");
  set("t-browse", "Browse pets…");
  set("t-create", "Create pet…");
  set("t-bw-title", "Browse pets");
  set("browse-done", "Done");
  set("t-bw-all", "All");
  set("t-bw-char", "Characters");
  set("t-bw-crea", "Creatures");
  set("t-bw-obj", "Objects");
  set("t-cr-title", "Create pet");
  set("create-cancel", "Cancel");
  set("t-cr-name", "Name");
  set("t-cr-desc", "Description");
  set("t-cr-sheet", "Spritesheet");
  set("t-cr-hint", "Use the same 8×9 transparent spritesheet format as downloaded pets.");
  set("cr-create", "Create");
  set("cr-choose", "Choose image…");
  set("t-size", "Size on screen");
  set("t-extra", "Extra pets on desktop");
  set("t-extra-sub", "Pure decoration pets that just float and roam. They don't track tasks or earn XP.");
  set("t-extra-pick", "Tap a pet to spawn it on desktop");
  set("t-extra-running", "On desktop");
  set("t-extra-closeall", "Close all");
  set("t-extra-no", "No pets in library yet. Use Browse or Create first.");
  set("t-extra-cap", "Desktop limit reached. Close one to spawn more.");
  set("t-anims", "Animations");
  set("t-anim-hint", "Hover a clip to preview it.");
  set("am-idle", "Idle");
  set("am-working", "Working");
  set("am-waiting", "Waiting");
  set("am-done", "Done");
  set("am-celebrate", "Celebrate");
  // care
  set("t-care-head", "Your companion");
  set("t-care-help", "Feeding earns XP; your pet levels up through five stages. Optional agent integrations can feed it tokens and finished sessions automatically.");
  set("t-care-ach", "Achievements");
  set("t-care-today", "Today");
  set("t-care-streak", "Streak");
  set("t-care-lifetime", "Lifetime");
  set("t-care-sessions", "Sessions");
  set("care-streak-sub", "days fed");
  set("care-lifetime-sub", "tokens eaten");
  set("care-sessions-sub", "completed");
  set("t-care-cost", "Est. cost (Claude)");
  set("t-care-burn", "Burn, last 7 days");
  // bubble
  set("t-appearance", "Appearance");
  set("t-theme", "Theme");
  set("t-opacity", "Opacity");
  set("t-fontsize", "Text size");
  set("o-dark", "Dark");
  set("o-light", "Light");
  set("o-theme-system", "System");
  set("t-idle", "Show idle message");
  set("t-idle-sub", "The pet's chatter while nothing is happening.");
  set("t-reactive-head", "Reactive comments");
  set("t-reactive", "React to activity");
  set("t-reactive-sub", "The pet reacts to token usage, streaks, hunger, and busy sessions.");
  set("t-split", "Project pets");
  set("t-split-label", "Split pets by project");
  set("t-split-sub", "Give a project its own pet window; the rest stay on the main pet.");
  set("t-display", "Display");
  set("t-rows", "Rows");
  set("o-bm-list", "All rows");
  set("o-bm-carousel", "Carousel");
  set("o-bm-compact", "Compact");
  set("t-grouping", "Sessions");
  set("o-bg-kind", "Grouped by agent");
  set("o-bg-all", "All sessions");
  set("t-maxrows", "Max rows");
  set("t-filter", "Include states");
  set("o-bf-all", "All states");
  set("o-bf-done", "Done and above");
  set("o-bf-ww", "Working & Waiting");
  set("o-bf-w", "Working only");
  set("t-visible", "Visible agents");
  set("t-rowcontent", "Row content");
  set("t-presets", "Presets");
  set("t-preview-cap", "Preview");
  set("t-vocab-foot", "Whimsical phrases shown while something is happening, e.g. \"Brewing…\" or \"Compiling…\".");
  set("t-msg-foot", "Per-agent overrides win over \"All agents\". A custom line replaces the live/theme text and the real pet honours it.");
  set("t-pr-original", "Original");
  set("t-pr-standard", "Standard");
  set("t-pr-detailed", "Detailed");
  set("t-agenticons", "Agent icons");
  set("t-sortkind", "Sort by agent kind");
  set("t-ic-brand", "Brand logos");
  set("t-ic-sym", "Symbols");
  set("icon-reset", "Reset to default");
  set("icon-done", "Done");
  set("t-style", "Style");
  set("t-separator", "Separator");
  set("o-sep-space", "space");
  set("t-dotstyle", "State dot");
  set("o-dot-plain", "Plain dot");
  set("o-dot-claude", "Claude style");
  set("t-ball", "Floating ball");
  set("t-ball-on", "Show floating ball");
  set("t-ball-on-sub", "A draggable ball on your desktop. Left-click for a bubble, right-click for settings. Snaps to screen edges.");
  set("t-click", "Left-click pet");
  set("t-click-action", "Action");
  set("t-click-sub", "What happens when you left-click a pet without dragging. Uses a random line from your quick bubbles below.");
  set("o-lc-none", "Off");
  set("o-lc-self", "This pet");
  set("o-lc-all", "All pets");
  set("t-quick", "Quick bubbles");
  set("t-quick-sub", "One message per line. Left-click a pet or send from the floating ball to show one at random.");
  set("t-quick-help", "Shift-click a preset on the floating ball to delete it.");
  set("t-activity", "Activity messages");
  set("t-phrases", "Vocabulary");
  set("t-messages", "Bubble messages");
  set("t-msg-src", "Messages");
  set("o-ms-system", "System");
  set("o-ms-custom", "Custom");
  set("msg-reset", "Reset to defaults");
  set("t-msg-help", "One message per line; a random one is shown.");
  set("t-msg-agent", "Agent");
  // codex help
  set("t-cdx-title", "How to connect Codex");
  set("t-cdx-1", "Install the hook here (it also enables hooks in Codex's config.toml).");
  set("t-cdx-2", "Open Codex CLI and run /hooks.");
  set("t-cdx-3", "Press t to Trust the DesktopPet hook.");
  set("t-cdx-4", "Quit and reopen Codex (both the CLI and the desktop app).");
  const allOpt = document.querySelector<HTMLOptionElement>('#msg-agent option[value="all"]');
  if (allOpt) allOpt.textContent = t("All agents");
  document.querySelectorAll<HTMLElement>(".msg-label").forEach((el) => {
    if (el.dataset.label) el.textContent = t(el.dataset.label);
  });
  // bottom bar + demo panel
  set("t-lp", "Live preview");
  set("t-preview-sub", "Preview your pet and bubble settings with live samples.");
  set("t-dp-title", "Live preview");
  set("t-dp-quick", "Quick scenarios");
  set("t-dp-active", "Active webhooks");
  set("t-dp-add", "Add webhook");
  set("t-dp-hint", "Add agents here, then change each webhook's state or delete it in the list on the left.");
  set("dp-spawn", "Spawn 3 working");
  set("dp-finish", "Finish all");
  set("dp-clear", "Clear all");
  set("dp-empty", "No webhooks yet. Add one from the right →");
  set("t-bubmode", "Multi-agent bubble");
  set("t-multi", "Enable multi-agent bubble");
  set("t-multi-sub", "Structured rows with icons, state dots, and activity messages.");
  set("t-history", "Session history");
  set("t-fontsize", "Font size");
  search.placeholder = t("Search your pets");
  (document.getElementById("bw-search") as HTMLInputElement).placeholder = t("Search pets");
}

// ------------------------------------------------- version / quit / links ----
function initMisc() {
  getVersion().then((v) => {
    const a = document.getElementById("app-version");
    if (a) a.textContent = v;
  }).catch(() => {});
  (document.getElementById("quit-btn") as HTMLButtonElement).onclick = () => { exit(0); };
  document.querySelectorAll<HTMLElement>("[data-url]").forEach((el) => {
    el.addEventListener("click", () => invoke("open_url", { url: el.dataset.url }).catch(() => {}));
  });
}

function initLang() {
  const sel = document.getElementById("lang") as HTMLSelectElement;
  sel.value = getLang();
  applyStatic();
  // Tell the tray (Rust) + the pet window about the initial language too.
  invoke("set_lang", { code: getLang() }).catch(() => {});
  sel.addEventListener("change", async () => {
    setLang(sel.value as Lang);
    applyStatic();
    renderAgents();
    showCurrent();
    invoke("set_lang", { code: getLang() }).catch(() => {});
    await emit("lang-changed", getLang());
  });
}

function esc(s: string): string {
  return s.replace(/[&<>]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" }[c] || c));
}

// Paint the filled-left part of every slider (drives the --fill CSS variable)
// and the numeric value label next to it.
function initSliders() {
  document.querySelectorAll<HTMLInputElement>('input[type="range"]').forEach((r) => {
    const val = document.getElementById(`${r.id}-val`);
    const paint = () => {
      const min = Number(r.min) || 0;
      const max = Number(r.max) || 100;
      const pct = ((Number(r.value) - min) / (max - min)) * 100;
      r.style.setProperty("--fill", `${pct}%`);
      if (val) val.textContent = r.value + (r.id === "opacity" ? "%" : "");
    };
    r.addEventListener("input", paint);
    paint();
  });
}

// -------------------------------------------------------- floating ball ----
// Toggles whether the floating ball is visible inside the single stage window.
// The state lives in a Rust-side file (read at launch so the ball can spawn
// before Settings opens), so we go through commands instead of localStorage.
function initFloatingBall() {
  const box = document.getElementById("ball-on") as HTMLInputElement | null;
  if (!box) return;
  invoke<boolean>("get_stage_ball_visible")
    .then((v) => { box.checked = v; })
    .catch(() => { box.checked = true; });
  box.addEventListener("change", () => {
    invoke("set_stage_ball_visible", { visible: box.checked }).catch(() => {});
  });
}

// -------------------------------------------------------- quick bubbles ----
// The quick-bubble preset pool: one message per line, shared by the floating
// ball (send menu) and left-click-on-pet (random line). Stored in localStorage
// as a JSON array; the textarea shows raw text for easy editing.
const QUICK_KEY = "ap_quick_bubbles";
const QUICK_DEFAULTS = [
  "Hello!",
  "Coding…",
  "Need a break?",
  "What's up?",
  "Let's ship something.",
];
function readQuickList(): string[] {
  try {
    const v = JSON.parse(localStorage.getItem(QUICK_KEY) || "[]");
    return Array.isArray(v) ? v.filter((x: unknown) => typeof x === "string") : [];
  } catch { return []; }
}
function writeQuickList(list: string[]) {
  localStorage.setItem(QUICK_KEY, JSON.stringify(list));
  emit("bubble-changed", null); // floating ball listens and refreshes its presets
}
function initQuickBubbles() {
  const ta = document.getElementById("quick-bubbles") as HTMLTextAreaElement | null;
  const reset = document.getElementById("quick-reset") as HTMLButtonElement | null;
  if (!ta) return;
  const current = readQuickList();
  ta.value = (current.length ? current : QUICK_DEFAULTS).join("\n");
  if (!current.length) writeQuickList(QUICK_DEFAULTS);
  ta.addEventListener("change", () => {
    const lines = ta.value.split("\n").map((s) => s.trim()).filter(Boolean);
    writeQuickList(lines);
  });
  if (reset) reset.onclick = () => {
    ta.value = QUICK_DEFAULTS.join("\n");
    writeQuickList(QUICK_DEFAULTS);
  };
}

initTabs();
initLang();
initIcons();
loadAgents();
initPet();
initMainPetVisibility();
initPetControls();
initBubble();
initBubbleDisplay();
initAgentIcons();
initAnimations();
initSounds();
initNotify();
initAutostart();
initReduceMotion();
initSliders();
initSegs();
initMisc();
initExtraPets();
initFloatingBall();
initQuickBubbles();
initDemo();
