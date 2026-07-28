import { fileUrl, escapeHtml } from "../_lib.js";

// GET /pet/<slug> — server-rendered Codex-style pet detail page (with OG tags).
export async function onRequestGet({ env, request, params }) {
  const origin = new URL(request.url).origin;
  const p = await env.DB.prepare(
    `SELECT p.*, u.name AS creator_name, u.avatar_url AS creator_avatar
       FROM pets p LEFT JOIN users u ON u.id = p.user_id
      WHERE p.slug = ? AND p.status = 'public'`
  ).bind(params.slug).first();
  if (!p) return new Response(notFound(), { status: 404, headers: html() });

  const sheet = fileUrl(origin, `pets/${p.slug}/sheet.png`);
  const creator = p.user_id
    ? `<a class="creator" href="/creator/${p.user_id}"><img src="${escapeHtml(p.creator_avatar || "")}" alt="">${escapeHtml(p.creator_name || p.author)}</a>`
    : `<span class="creator">${escapeHtml(p.author)}</span>`;

  return new Response(page({ p, sheet, creator, slug: p.slug }), { headers: html() });
}

const html = () => ({ "content-type": "text/html; charset=utf-8" });

function page({ p, sheet, creator, slug }) {
  const title = `${escapeHtml(p.name)}, an DesktopPet pet`;
  const desc = p.description ? escapeHtml(p.description) : `A ${escapeHtml(p.kind)} pet for DesktopPet.`;
  return `<!doctype html><html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title}</title>
<meta name="description" content="${desc}">
<meta property="og:title" content="${escapeHtml(p.name)} · DesktopPet">
<meta property="og:description" content="A community desktop pet for DesktopPet. ${p.downloads} downloads, ${p.likes} likes.">
<meta property="og:image" content="${sheet}">
<meta name="twitter:card" content="summary_large_image">
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Orbitron:wght@700;800;900&family=Share+Tech+Mono&family=JetBrains+Mono:wght@400;500;700&display=swap" rel="stylesheet">
<link rel="stylesheet" href="/app.css">
<script src="/app.js" defer></script>
</head><body><div class="wrap">
  <div class="topbar">
    <a class="brand" href="/"><img src="/icon.png" alt="">DesktopPet</a>
    <nav class="nav"><a href="/pet/">Pets</a><a href="/make/">Make</a><a href="/creators/">Creators</a></nav>
    <span class="spacer"></span><span class="auth" id="auth"></span>
  </div>
  <a class="back" href="/pet/">&larr; All pets</a>
  <div class="detail">
    <div class="stage"><canvas id="hero" width="250" height="250"></canvas></div>
    <div class="info">
      <h1>${escapeHtml(p.name)}</h1>
      <div>${creator} <span class="kind">${escapeHtml(p.kind)}</span></div>
      <p class="detaildesc">${desc}</p>
      <div class="statgrid">
        <div><b id="dl">${p.downloads}</b><span>downloads</span></div>
        <div><b id="lk">${p.likes}</b><span>likes</span></div>
        <div><b id="an">·</b><span>animations</span></div>
      </div>
      <div class="acts">
        <button class="btn amber" id="download">&#8681; Download PNG</button>
        <button class="btn sec" id="like">&#9829; <span id="likeTxt">Like</span></button>
        <button class="btn sec" id="report">&#9873; Report</button>
        <button class="btn danger" id="delete" hidden>Delete</button>
      </div>
      <p class="hint" style="margin-top:16px">In DesktopPet, open <b>Settings &rsaquo; Pet &rsaquo; Browse pets</b> to install this pet, or download the sheet and import it.</p>
      <div class="clips" id="clips"></div>
    </div>
  </div>
</div>
<script>
(async()=>{let m=null;try{m=(await (await fetch('/api/me')).json()).user;}catch{}
  document.querySelector('#auth').innerHTML=m?'<img class="av" src="'+(m.avatar_url||'')+'" alt=""><span class="uname">'+m.name.replace(/[<>&]/g,'')+'</span>':'<a class="signin" href="/api/auth/github/login">Sign in</a>';})();
const SLUG=${JSON.stringify(slug)}, SHEET=${JSON.stringify(sheet)};
const $=s=>document.querySelector(s);
const TH=16;
function seg(a){const r=[];let s=null;for(let i=0;i<a.length;i++){if(a[i]&&s===null)s=i;else if(!a[i]&&s!==null){r.push([s,i]);s=null;}}if(s!==null)r.push([s,a.length]);return r;}
function slice(img){
  const w=img.naturalWidth,h=img.naturalHeight;const cv=document.createElement('canvas');cv.width=w;cv.height=h;
  cv.getContext('2d').drawImage(img,0,0);const px=cv.getContext('2d').getImageData(0,0,w,h).data;
  const rowHas=new Array(h).fill(false);
  for(let y=0;y<h;y++){const rs=y*w*4;for(let x=0;x<w;x++){if(px[rs+x*4+3]>TH){rowHas[y]=true;break;}}}
  const clips=[];
  for(const[y0,y1]of seg(rowHas)){const colHas=new Array(w).fill(false);
    for(let x=0;x<w;x++){for(let y=y0;y<y1;y++){if(px[y*w*4+x*4+3]>TH){colHas[x]=true;break;}}}
    const row=seg(colHas).map(([x0,x1])=>({x:x0,y:y0,w:x1-x0,h:y1-y0}));if(row.length)clips.push(row);}
  return clips;
}
let tick=0;
function draw(cv,img,frames){const x=cv.getContext('2d');x.imageSmoothingEnabled=false;x.clearRect(0,0,cv.width,cv.height);
  const f=frames[tick%frames.length];const s=Math.min(cv.width/f.w,cv.height/f.h)*0.92;const w=f.w*s,h=f.h*s;
  x.drawImage(img,f.x,f.y,f.w,f.h,(cv.width-w)/2,(cv.height-h)/2,w,h);}
const img=new Image();img.crossOrigin='anonymous';
img.onload=()=>{
  const clips=slice(img);$('#an').textContent=clips.length;
  const hero=$('#hero');const heroFrames=clips[0]||[{x:0,y:0,w:img.naturalWidth,h:img.naturalHeight}];
  const cont=$('#clips');
  const cells=clips.map((fr,i)=>{const fig=document.createElement('figure');const c=document.createElement('canvas');c.width=128;c.height=128;
    const cap=document.createElement('figcaption');cap.textContent='Anim '+(i+1);fig.appendChild(c);fig.appendChild(cap);cont.appendChild(fig);return {c,fr};});
  setInterval(()=>{tick++;draw(hero,img,heroFrames);cells.forEach(({c,fr})=>draw(c,img,fr));},150);
};
img.onerror=()=>{$('#an').textContent='?';};
img.src=SHEET;

let me=null,liked=false;
(async()=>{
  try{me=(await (await fetch('/api/me')).json()).user;}catch{}
  try{const d=await (await fetch('/api/pets/'+SLUG)).json();liked=d.liked;$('#dl').textContent=d.downloads;$('#lk').textContent=d.likes;
    $('#likeTxt').textContent=liked?'Liked':'Like';if(d.isOwner)$('#delete').hidden=false;}catch{}
})();
$('#like').onclick=async()=>{if(!me){location.href='/api/auth/github/login';return;}
  const r=await fetch('/api/pets/'+SLUG+'/like',{method:'POST'});if(!r.ok)return;const d=await r.json();liked=d.liked;$('#lk').textContent=d.likes;$('#likeTxt').textContent=liked?'Liked':'Like';};
$('#download').onclick=async()=>{
  fetch('/api/pets/'+SLUG+'/download',{method:'POST'}).then(()=>{}).catch(()=>{});
  const a=document.createElement('a');a.href=SHEET;a.download=SLUG+'.png';document.body.appendChild(a);a.click();a.remove();
  const n=parseInt($('#dl').textContent||'0',10);$('#dl').textContent=n+1;};
$('#report').onclick=async()=>{if(!confirm('Report this pet as inappropriate?'))return;await fetch('/api/pets/'+SLUG+'/report',{method:'POST'});alert('Thanks, reported.');};
$('#delete').onclick=async()=>{if(!confirm('Delete this pet? This cannot be undone.'))return;const r=await fetch('/api/pets/'+SLUG,{method:'DELETE'});if(r.ok)location.href='/pet/';else alert('Could not delete.');};
</script></body></html>`;
}

function notFound() {
  return `<!doctype html><meta charset="utf-8"><title>Pet not found</title>
<body style="font-family:-apple-system,Arial;background:#16112e;color:#fff;text-align:center;padding:80px">
<h1>Pet not found</h1><p><a href="/pet/" style="color:#a99bff">Back to all pets</a></p></body>`;
}
