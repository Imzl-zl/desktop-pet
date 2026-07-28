import { json, slugify, shortId, validateSheet, fileUrl, telegram, clientIp, getUser } from "../_lib.js";

const KINDS = new Set(["character", "creature", "object"]);

// GET /api/pets — manifest used by both the web gallery and the DesktopPet app.
// App-facing fields stay stable; web-only stats (downloads/likes/creator) are extra.
export async function onRequestGet({ env, request }) {
  const origin = new URL(request.url).origin;
  const { results } = await env.DB.prepare(
    `SELECT p.slug, p.name, p.kind, p.author, p.description, p.created_at, p.downloads, p.likes, p.user_id,
            u.name AS creator_name, u.avatar_url AS creator_avatar
       FROM pets p LEFT JOIN users u ON u.id = p.user_id
      WHERE p.status = 'public' ORDER BY p.created_at DESC LIMIT 500`
  ).all();
  const pets = (results || []).map((p) => ({
    slug: p.slug,
    displayName: p.name,
    kind: p.kind,
    description: p.description || "",
    submittedBy: p.creator_name || p.author,
    spritesheetUrl: fileUrl(origin, `pets/${p.slug}/sheet.png`),
    petJsonUrl: fileUrl(origin, `pets/${p.slug}/pet.json`),
    createdAt: p.created_at,
    downloads: p.downloads,
    likes: p.likes,
    creator: p.user_id ? { id: p.user_id, name: p.creator_name, avatar: p.creator_avatar } : null,
  }));
  return json({ pets }, 200, { "cache-control": "public, max-age=30" });
}

// POST /api/pets — upload a pet (multipart: name, kind?, file=PNG). Requires login.
export async function onRequestPost({ env, request }) {
  const now = Date.now();
  const user = await getUser(env, request, now);
  if (!user) return json({ error: "Please sign in to upload a pet." }, 401);

  const ip = clientIp(request);
  const maxPerHour = parseInt(env.UPLOAD_MAX_PER_HOUR || "5", 10);
  const recent = await env.DB.prepare(
    "SELECT COUNT(*) AS n FROM uploads WHERE ip = ? AND created_at > ?"
  ).bind(ip, now - 3600_000).first();
  if ((recent?.n || 0) >= maxPerHour)
    return json({ error: "Too many uploads, try again later." }, 429);

  let form;
  try { form = await request.formData(); } catch { return json({ error: "Invalid form." }, 400); }

  const name = (form.get("name") || "").toString().trim().slice(0, 60);
  const description = (form.get("description") || "").toString().trim().slice(0, 160);
  let kind = (form.get("kind") || "character").toString();
  if (!KINDS.has(kind)) kind = "character";
  const file = form.get("file");
  const author = user.name;

  if (!name) return json({ error: "Name is required." }, 400);
  if (!file || typeof file === "string") return json({ error: "A spritesheet PNG is required." }, 400);

  const buf = await file.arrayBuffer();
  const v = validateSheet(buf);
  if (v.error) return json({ error: v.error }, 400);

  const slug = `${slugify(name)}-${shortId()}`;
  const sheetKey = `pets/${slug}/sheet.png`;
  const jsonKey = `pets/${slug}/pet.json`;
  const petJson = JSON.stringify({
    id: slug,
    displayName: name,
    description: description || `by ${author}`,
    spritesheetPath: "sheet.png",
  });

  await env.PETS.put(sheetKey, buf, { httpMetadata: { contentType: "image/png" } });
  await env.PETS.put(jsonKey, petJson, { httpMetadata: { contentType: "application/json" } });

  await env.DB.prepare(
    `INSERT INTO pets (slug, name, author, kind, description, sheet_key, json_key, width, height, status, reports, user_id, created_at)
     VALUES (?,?,?,?,?,?,?,?,?, 'public', 0, ?, ?)`
  ).bind(slug, name, author, kind, description || null, sheetKey, jsonKey, v.width, v.height, user.id, now).run();
  await env.DB.prepare("INSERT INTO uploads (ip, created_at) VALUES (?, ?)").bind(ip, now).run();

  const origin = new URL(request.url).origin;
  await telegram(env, `🐾 New pet: <b>${name}</b> by ${author} (${kind})\n${origin}/pet/${slug}`);

  return json({ ok: true, slug, name, kind });
}
