// DesktopPet pet mirror: serves the community pet library from our own R2 so the
// app/web are independent of any upstream CDN. Two upstream sources, each tagged
// with `source`:
//   - OpenPets  (openpets.dev catalog)
//   - Petdex    (petdex.dev/api/manifest; assets need a Referer header)
// We mirror every pet's spritesheet + a pet.json into R2 under pets/<slug>/, and
// build the app/web manifest (with source, kind, submittedBy) from a stored
// catalog snapshot.
//
//   GET /manifest                -> manifest, asset URLs pointing at the R2 domain
//   GET /a/<key>                 -> a mirrored asset from R2
//   GET /mirror/run?key=&cursor= -> mirror one batch into R2 (admin, resumable)
//   GET /mirror/status           -> mirror progress

const CATALOG_INDEX = "https://openpets.dev/pets/catalog.v3.json";
const OPENPETS = "https://openpets.dev";
const PETDEX_MANIFEST = "https://petdex.dev/api/manifest";
const PETDEX_REFERER = "https://petdex.dev/"; // hotlink protection on assets.petdex.dev
const UA = "Mozilla/5.0 (DesktopPet pet mirror)";
// R2 bucket's public custom domain. Assets are served from here (CF-cached,
// egress-free, off the Worker request quota) instead of through this Worker.
const R2_PUBLIC = "https://pets.thenightwatcher.online";
const ASSET_MAXAGE = 60 * 60 * 24 * 365; // 1 year
const IMMUTABLE = `public, max-age=${60 * 60 * 24 * 365}, immutable`;
const MIRROR_BATCH = 20;        // pets per /mirror/run
const MIRROR_CONCURRENCY = 6;
const CORS = { "access-control-allow-origin": "*" };

export default {
  async fetch(request, env, ctx) {
    if (request.method !== "GET" && request.method !== "HEAD")
      return new Response("Method not allowed", { status: 405 });
    const url = new URL(request.url);
    const path = url.pathname;

    if (path === "/manifest" || path === "/api/manifest") return manifest(env);
    if (path === "/mirror/status") return mirrorStatus(env);
    if (path === "/mirror/publish") {
      if (env.MIRROR_KEY && url.searchParams.get("key") !== env.MIRROR_KEY)
        return json({ error: "forbidden" }, 403);
      return json(await publishManifest(env));
    }
    if (path === "/mirror/run") {
      if (env.MIRROR_KEY && url.searchParams.get("key") !== env.MIRROR_KEY)
        return json({ error: "forbidden" }, 403);
      return json(await mirrorBatch(url, env));
    }
    if (path.startsWith("/a/")) return asset(decodeURIComponent(path.slice(3)), env, ctx);
    if (path === "/") return new Response("DesktopPet pet mirror.", { status: 200 });
    return new Response("Not found", { status: 404 });
  },
};

// ---- manifest (built from the R2 catalog snapshot, app/web-compatible shape) ----
function manifestPets(catPets) {
  return catPets.map((p) => {
    const out = {
      slug: p.folder,
      displayName: p.displayName || p.folder,
      spritesheetUrl: `${R2_PUBLIC}/pets/${p.folder}/spritesheet.webp`,
      petJsonUrl: `${R2_PUBLIC}/pets/${p.folder}/pet.json`,
      source: p.source,
      kind: p.kind || "",
    };
    // Only include submittedBy when there's a real author. Omitting it (vs "")
    // lets the app fall back to "by community" for unattributed pets.
    if (p.submittedBy) out.submittedBy = p.submittedBy;
    return out;
  });
}

// Rebuild the static manifest.json from the stored catalog (no asset work).
async function publishManifest(env) {
  const snap = await env.CACHE.get("_catalog.json");
  if (!snap) return { ok: false, reason: "no catalog snapshot" };
  const cat = await snap.json();
  const pets = manifestPets(cat.pets || []);
  await env.CACHE.put("manifest.json", JSON.stringify({ pets }),
    { httpMetadata: { contentType: "application/json", cacheControl: "public, max-age=300" } });
  return { ok: true, total: pets.length };
}

async function manifest(env) {
  const snap = await env.CACHE.get("_catalog.json");
  if (!snap) return json({ error: "not mirrored yet", pets: [] }, 200, CORS);
  let cat;
  try { cat = await snap.json(); } catch { return json({ pets: [] }, 200, CORS); }
  return json({ pets: manifestPets(cat.pets || []) }, 200, { "cache-control": "public, max-age=300", ...CORS });
}

// ---- asset serving (R2 only after mirror; sprite falls back to upstream) ----
async function asset(key, env, ctx) {
  if (!key || key.includes("..") || key.startsWith("_")) return new Response("Bad key", { status: 400 });
  const hit = await env.CACHE.get(key);
  if (hit) {
    const h = new Headers(CORS);
    hit.writeHttpMetadata(h);
    h.set("cache-control", `public, max-age=${ASSET_MAXAGE}, immutable`);
    h.set("x-cache", "HIT");
    return new Response(hit.body, { headers: h });
  }
  if (key.endsWith("/pet.json")) return new Response("Not mirrored", { status: 404 });
  let resp;
  try { resp = await fetch(`${OPENPETS}/${key}`); }
  catch { return new Response("upstream error", { status: 502 }); }
  if (!resp || !resp.ok) return new Response("not found", { status: resp ? resp.status : 502 });
  const ct = resp.headers.get("content-type") || "image/webp";
  const buf = await resp.arrayBuffer();
  ctx.waitUntil(env.CACHE.put(key, buf, { httpMetadata: { contentType: ct, cacheControl: IMMUTABLE } }));
  return new Response(buf, {
    headers: { "content-type": ct, "cache-control": `public, max-age=${ASSET_MAXAGE}, immutable`, "x-cache": "MISS", ...CORS },
  });
}

// ---- mirroring ----

// Upstream fetch that adds the Petdex Referer when needed.
function fetchUp(url, source) {
  const headers = { "user-agent": UA };
  if (source === "petdex" || /assets\.petdex\.dev/.test(url)) headers["referer"] = PETDEX_REFERER;
  return fetch(url, { headers });
}

// Build the merged catalog (OpenPets + Petdex), each entry tagged with source.
async function buildCatalog() {
  const pets = [];
  // OpenPets
  try {
    const idx = await (await fetch(CATALOG_INDEX, { headers: { "user-agent": UA } })).json();
    for (const pageUrl of idx.pages || []) {
      const page = await (await fetch(pageUrl, { headers: { "user-agent": UA } })).json();
      for (const p of page.pets || []) {
        const m = /\/pets\/([^/]+)\/spritesheet\./.exec(p.spritesheet || "");
        if (!m) continue;
        pets.push({
          folder: m[1], id: p.id, displayName: p.displayName || p.id, description: p.description || "",
          kind: p.category || "", submittedBy: "", source: "openpets", sprite: p.spritesheet, petjson: null,
        });
      }
    }
  } catch {}
  // Petdex (id + description live in each pet's pet.json, fetched at mirror time)
  try {
    const pd = await (await fetch(PETDEX_MANIFEST, { headers: { "user-agent": UA } })).json();
    for (const p of pd.pets || []) {
      if (!p.slug || !p.spritesheetUrl) continue;
      pets.push({
        folder: p.slug, id: null, displayName: p.displayName || p.slug, description: null,
        kind: p.kind || "", submittedBy: p.submittedBy || "", source: "petdex",
        sprite: p.spritesheetUrl, petjson: p.petJsonUrl || null,
      });
    }
  } catch {}
  return { generatedAt: new Date().toISOString(), total: pets.length, pets };
}

async function mirrorBatch(url, env) {
  const cursor = parseInt(url.searchParams.get("cursor") || "0", 10) || 0;
  const batch = parseInt(url.searchParams.get("batch") || String(MIRROR_BATCH), 10) || MIRROR_BATCH;

  let cat;
  if (cursor === 0) {
    cat = await buildCatalog();
    await env.CACHE.put("_catalog.json", JSON.stringify(cat), { httpMetadata: { contentType: "application/json" } });
  } else {
    const snap = await env.CACHE.get("_catalog.json");
    if (!snap) return { ok: false, reason: "no catalog snapshot; run cursor=0 first" };
    cat = await snap.json();
  }

  const slice = cat.pets.slice(cursor, cursor + batch);
  let mirrored = 0, skipped = 0, failed = 0, i = 0;
  async function run() {
    while (i < slice.length) {
      const p = slice[i++];
      const dir = `pets/${p.folder}`;
      try {
        // Skip pets whose sprite is already in R2 (cheap, resumable re-runs).
        const have = await env.CACHE.head(`${dir}/spritesheet.webp`);
        if (have) { skipped++; continue; }

        // Resolve id + description (Petdex: from upstream pet.json).
        let id = p.id, description = p.description || "";
        if (p.source === "petdex" && p.petjson) {
          try {
            const pj = await fetchUp(p.petjson, p.source);
            if (pj.ok) { const j = await pj.json(); id = j.id || p.folder; description = j.description || ""; }
          } catch {}
        }
        if (!id) id = p.folder;

        await env.CACHE.put(`${dir}/pet.json`, JSON.stringify({
          id, displayName: p.displayName, description, spritesheetPath: "spritesheet.webp",
          category: p.kind, source: p.source, submittedBy: p.submittedBy || "",
        }), { httpMetadata: { contentType: "application/json", cacheControl: IMMUTABLE } });

        const r = await fetchUp(p.sprite, p.source);
        if (!r.ok) { failed++; continue; }
        await env.CACHE.put(`${dir}/spritesheet.webp`, r.body,
          { httpMetadata: { contentType: r.headers.get("content-type") || "image/webp", cacheControl: IMMUTABLE } });
        mirrored++;
      } catch { failed++; }
    }
  }
  await Promise.all(Array.from({ length: MIRROR_CONCURRENCY }, run));

  const next = cursor + batch;
  const done = next >= cat.pets.length;
  if (done) {
    await env.CACHE.put("manifest.json", JSON.stringify({ pets: manifestPets(cat.pets) }),
      { httpMetadata: { contentType: "application/json", cacheControl: "public, max-age=300" } });
  }
  await env.CACHE.put("_mirror.json", JSON.stringify({
    cursor: Math.min(next, cat.pets.length), total: cat.pets.length, done,
    lastMirrored: mirrored, lastSkipped: skipped, lastFailed: failed,
  }), { httpMetadata: { contentType: "application/json" } });
  return { ok: true, cursor: Math.min(next, cat.pets.length), total: cat.pets.length, done, mirrored, skipped, failed };
}

async function mirrorStatus(env) {
  const s = await env.CACHE.get("_mirror.json");
  const doc = s ? await s.json().catch(() => null) : null;
  return json({ progress: doc || { cursor: 0, total: 0, done: false } }, 200, CORS);
}

const json = (data, status = 200, extra = {}) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", ...extra },
  });
