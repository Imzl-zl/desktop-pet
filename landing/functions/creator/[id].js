import { fileUrl, escapeHtml } from "../_lib.js";

// GET /creator/<id> — a creator's profile and their pets.
export async function onRequestGet({ env, request, params }) {
  const origin = new URL(request.url).origin;
  const id = parseInt(params.id, 10);
  const user = Number.isInteger(id)
    ? await env.DB.prepare("SELECT id, name, avatar_url FROM users WHERE id = ?").bind(id).first()
    : null;
  if (!user) return new Response(notFound(), { status: 404, headers: html() });

  const { results } = await env.DB.prepare(
    `SELECT slug, name, kind, downloads, likes FROM pets
      WHERE user_id = ? AND status = 'public' ORDER BY created_at DESC`
  ).bind(id).all();
  const pets = (results || []).map((p) => ({ ...p, sheet: fileUrl(origin, `pets/${p.slug}/sheet.png`) }));
  const totals = pets.reduce((a, p) => ({ d: a.d + p.downloads, l: a.l + p.likes }), { d: 0, l: 0 });

  return new Response(page(user, pets, totals), { headers: html() });
}

const html = () => ({ "content-type": "text/html; charset=utf-8" });

function page(user, pets, totals) {
  const cards = pets.map((p) => `
    <a class="pet cardlink" href="/pet/${escapeHtml(p.slug)}">
      <canvas class="thumb" width="128" height="128" data-sheet="${p.sheet}"></canvas>
      <div class="name">${escapeHtml(p.name)}</div>
      <div class="stats" style="justify-content:center">&#9829; ${p.likes} &middot; &#8681; ${p.downloads}</div>
    </a>`).join("");

  return `<!doctype html><html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(user.name)} — DesktopPet creator</title>
<meta property="og:title" content="${escapeHtml(user.name)} on DesktopPet">
<meta property="og:description" content="${pets.length} pets · ${totals.d} downloads · ${totals.l} likes">
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Orbitron:wght@700;800;900&family=Share+Tech+Mono&family=JetBrains+Mono:wght@400;500;700&display=swap" rel="stylesheet">
<link rel="stylesheet" href="/app.css">
<script src="/app.js" defer></script>
</head><body><div class="wrap">
  <div class="topbar">
    <a class="brand" href="/"><img src="/icon.png" alt="">DesktopPet</a>
    <nav class="nav"><a href="/pet/">Pets</a><a href="/make/">Make</a><a href="/creators/">Creators</a></nav>
    <span class="spacer"></span>
  </div>
  <a class="back" href="/creators/">&larr; Leaderboard</a>
  <div class="prof">
    <img src="${escapeHtml(user.avatar_url || "")}" alt="">
    <div><h1>${escapeHtml(user.name)}</h1>
      <div class="meta">${pets.length} pets &middot; ${totals.d} downloads &middot; ${totals.l} likes</div></div>
  </div>
  ${pets.length ? `<div class="grid">${cards}</div>` : `<div class="empty">No pets yet.</div>`}
</div>
<script>
const TH=16;
function seg(a){const r=[];let s=null;for(let i=0;i<a.length;i++){if(a[i]&&s===null)s=i;else if(!a[i]&&s!==null){r.push([s,i]);s=null;}}if(s!==null)r.push([s,a.length]);return r;}
function firstClip(img){const w=img.naturalWidth,h=img.naturalHeight;const c=document.createElement('canvas');c.width=w;c.height=h;
  c.getContext('2d').drawImage(img,0,0);const px=c.getContext('2d').getImageData(0,0,w,h).data;
  const rowHas=new Array(h).fill(false);for(let y=0;y<h;y++){const rs=y*w*4;for(let x=0;x<w;x++){if(px[rs+x*4+3]>TH){rowHas[y]=true;break;}}}
  const rb=seg(rowHas);if(!rb.length)return null;const[y0,y1]=rb[0];const colHas=new Array(w).fill(false);
  for(let x=0;x<w;x++){for(let y=y0;y<y1;y++){if(px[y*w*4+x*4+3]>TH){colHas[x]=true;break;}}}
  return seg(colHas).map(([x0,x1])=>({x:x0,y:y0,w:x1-x0,h:y1-y0}));}
const cells=[];let tick=0;
document.querySelectorAll('.pet canvas').forEach(cv=>{const img=new Image();img.crossOrigin='anonymous';
  img.onload=()=>{const fr=firstClip(img);if(fr)cells.push({cv,img,fr});};img.src=cv.dataset.sheet;});
setInterval(()=>{tick++;cells.forEach(({cv,img,fr})=>{const x=cv.getContext('2d');x.imageSmoothingEnabled=false;x.clearRect(0,0,cv.width,cv.height);
  const f=fr[tick%fr.length];const s=Math.min(cv.width/f.w,cv.height/f.h)*0.92;const w=f.w*s,h=f.h*s;
  x.drawImage(img,f.x,f.y,f.w,f.h,(cv.width-w)/2,(cv.height-h)/2,w,h);});},150);
</script></body></html>`;
}

function notFound() {
  return `<!doctype html><meta charset="utf-8"><title>Creator not found</title>
<body style="font-family:-apple-system,Arial;background:#16112e;color:#fff;text-align:center;padding:80px">
<h1>Creator not found</h1><p><a href="/creators/" style="color:#a99bff">Back to leaderboard</a></p></body>`;
}
