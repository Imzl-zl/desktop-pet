import type { MiddlewareHandler } from "astro";

// Maintenance mode. Set to false (and remove `output: 'server'` in
// astro.config.mjs) to bring the full site back, then redeploy.
const MAINTENANCE = false;

// Self-contained "coming soon" page. No external/community pet artwork, only
// the original DesktopPet brand mark + CSS clouds, so there are no IP concerns.
const PAGE = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<meta name="robots" content="noindex" />
<title>DesktopPet , back soon</title>
<link rel="icon" href="/favicon.svg" />
<link rel="preconnect" href="https://fonts.googleapis.com" />
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
<link href="https://fonts.googleapis.com/css2?family=Fredoka:wght@500;600;700&family=Plus+Jakarta+Sans:wght@400;500;600&display=swap" rel="stylesheet" />
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  :root { --brand: #2563eb; --ink: #16284a; --muted: #5b6b8c; }
  html, body { height: 100%; }
  body {
    font-family: "Plus Jakarta Sans", ui-sans-serif, system-ui, sans-serif;
    color: var(--ink);
    background: linear-gradient(180deg, #b7d6ff 0%, #d4e7ff 45%, #eaf3ff 100%);
    min-height: 100vh;
    display: grid;
    place-items: center;
    padding: 24px;
    overflow: hidden;
    position: relative;
  }
  /* drifting pixel clouds */
  .cloud {
    position: fixed;
    background: #ffffff;
    border-radius: 999px;
    opacity: .7;
    filter: blur(.3px);
    box-shadow: 0 18px 40px rgba(80, 120, 200, .18);
    animation: drift linear infinite;
  }
  .cloud::before, .cloud::after {
    content: ""; position: absolute; background: #fff; border-radius: 999px;
  }
  .c1 { width: 150px; height: 46px; top: 14%; left: -200px; animation-duration: 46s; }
  .c1::before { width: 80px; height: 80px; top: -34px; left: 26px; }
  .c1::after  { width: 56px; height: 56px; top: -20px; left: 84px; }
  .c2 { width: 110px; height: 36px; top: 62%; left: -180px; animation-duration: 60s; animation-delay: -12s; opacity:.55; }
  .c2::before { width: 60px; height: 60px; top: -26px; left: 20px; }
  .c2::after  { width: 44px; height: 44px; top: -16px; left: 62px; }
  .c3 { width: 130px; height: 40px; top: 80%; left: -220px; animation-duration: 70s; animation-delay: -30s; opacity:.5; }
  .c3::before { width: 70px; height: 70px; top: -30px; left: 22px; }
  .c3::after  { width: 50px; height: 50px; top: -18px; left: 72px; }
  @keyframes drift { from { transform: translateX(0); } to { transform: translateX(112vw); } }

  .card {
    position: relative;
    z-index: 2;
    width: 100%;
    max-width: 540px;
    text-align: center;
    background: rgba(255, 255, 255, .74);
    backdrop-filter: blur(14px);
    -webkit-backdrop-filter: blur(14px);
    border: 1px solid rgba(255, 255, 255, .9);
    border-radius: 28px;
    padding: 44px 36px 36px;
    box-shadow: 0 30px 70px rgba(46, 84, 170, .22);
  }
  .logo {
    width: 76px; height: 76px; border-radius: 22px; margin: 0 auto 18px;
    display: grid; place-items: center;
    background: linear-gradient(150deg, #4f7bff, #7c5cff);
    box-shadow: 0 12px 26px rgba(79, 123, 255, .4);
    animation: float 4s ease-in-out infinite;
  }
  .logo svg { width: 42px; height: 42px; }
  @keyframes float { 0%,100% { transform: translateY(0); } 50% { transform: translateY(-8px); } }
  .wordmark { font-family: "Fredoka", sans-serif; font-weight: 700; font-size: 26px; letter-spacing: -.01em; }
  .wordmark span { color: var(--brand); }
  .badge {
    display: inline-block; margin: 18px 0 14px;
    font-size: 12px; font-weight: 700; letter-spacing: .12em; text-transform: uppercase;
    color: var(--brand); background: rgba(37, 99, 235, .12);
    padding: 6px 14px; border-radius: 999px;
  }
  h1 { font-family: "Fredoka", sans-serif; font-weight: 600; font-size: 34px; line-height: 1.15; color: var(--ink); }
  .lead { margin-top: 14px; font-size: 16px; line-height: 1.6; color: var(--muted); }
  .lead-vi { margin-top: 8px; font-size: 14.5px; line-height: 1.6; color: var(--muted); }
  .actions { margin-top: 26px; display: flex; gap: 12px; justify-content: center; flex-wrap: wrap; }
  .btn {
    display: inline-flex; align-items: center; gap: 8px;
    padding: 11px 20px; border-radius: 999px; font-weight: 600; font-size: 15px;
    text-decoration: none; transition: transform .15s ease, box-shadow .15s ease;
  }
  .btn:hover { transform: translateY(-2px); }
  .btn svg { width: 18px; height: 18px; }
  .btn-primary { background: var(--brand); color: #fff; box-shadow: 0 10px 22px rgba(37, 99, 235, .35); }
  .btn-ghost { background: #fff; color: var(--ink); border: 1px solid #d9e2f2; }
  .foot { margin-top: 26px; font-size: 12.5px; color: #8a97b4; }
  @media (max-width: 480px) { h1 { font-size: 28px; } .card { padding: 34px 22px 28px; } }
</style>
</head>
<body>
  <div class="cloud c1"></div>
  <div class="cloud c2"></div>
  <div class="cloud c3"></div>

  <main class="card">
    <div class="logo">
      <svg viewBox="0 0 24 24" fill="#fff" aria-hidden="true">
        <ellipse cx="12" cy="15.5" rx="5" ry="4.2"/>
        <circle cx="6.5" cy="9.5" r="2.1"/>
        <circle cx="10" cy="6.6" r="2.1"/>
        <circle cx="14" cy="6.6" r="2.1"/>
        <circle cx="17.5" cy="9.5" r="2.1"/>
      </svg>
    </div>
    <div class="wordmark">Agent<span>Pet</span></div>

    <div class="badge">Maintenance</div>
    <h1>We're tidying up the island</h1>
    <p class="lead">The DesktopPet website is taking a short break for maintenance. The desktop app keeps running, and we'll be back online shortly.</p>
    <p class="lead-vi">Website DesktopPet đang bảo trì một chút, bọn mình sẽ quay lại sớm. App trên máy vẫn chạy bình thường. Cảm ơn bạn đã ghé!</p>

    <div class="actions">
      <a class="btn btn-primary" href="https://discord.gg/kzFJKsZav" target="_blank" rel="noopener">
        <svg viewBox="0 0 24 24" fill="currentColor"><path d="M20.317 4.3698a19.7913 19.7913 0 00-4.8851-1.5152.0741.0741 0 00-.0785.0371c-.211.3753-.4447.8648-.6083 1.2495-1.8447-.2762-3.68-.2762-5.4868 0-.1636-.3933-.4058-.8742-.6177-1.2495a.077.077 0 00-.0785-.037 19.7363 19.7363 0 00-4.8852 1.515.0699.0699 0 00-.0321.0277C.5334 9.0458-.319 13.5799.0992 18.0578a.0824.0824 0 00.0312.0561c2.0528 1.5076 4.0413 2.4228 5.9929 3.0294a.0777.0777 0 00.0842-.0276c.4616-.6304.8731-1.2952 1.226-1.9942a.076.076 0 00-.0416-.1057c-.6528-.2476-1.2743-.5495-1.8722-.8923a.077.077 0 01-.0076-.1277c.1258-.0943.2517-.1923.3718-.2914a.0743.0743 0 01.0776-.0105c3.9278 1.7933 8.18 1.7933 12.0614 0a.0739.0739 0 01.0785.0095c.1202.099.246.1981.3728.2924a.077.077 0 01-.0066.1276 12.2986 12.2986 0 01-1.873.8914.0766.0766 0 00-.0407.1067c.3604.698.7719 1.3628 1.225 1.9932a.076.076 0 00.0842.0286c1.961-.6067 3.9495-1.5219 6.0023-3.0294a.077.077 0 00.0313-.0552c.5004-5.177-.8382-9.6739-3.5485-13.6604a.061.061 0 00-.0312-.0286zM8.02 15.3312c-1.1825 0-2.1569-1.0857-2.1569-2.419 0-1.3332.9555-2.4189 2.157-2.4189 1.2108 0 2.1757 1.0952 2.1568 2.419 0 1.3332-.9555 2.4189-2.1569 2.4189zm7.9748 0c-1.1825 0-2.1569-1.0857-2.1569-2.419 0-1.3332.9554-2.4189 2.1569-2.4189 1.2108 0 2.1757 1.0952 2.1568 2.419 0 1.3332-.946 2.4189-2.1568 2.4189Z"/></svg>
        Join our Discord
      </a>
      <a class="btn btn-ghost" href="https://github.com/Imzl-zl/desktop-pet" target="_blank" rel="noopener">
        <svg viewBox="0 0 24 24" fill="currentColor"><path d="M12 .3a12 12 0 0 0-3.8 23.4c.6.1.8-.3.8-.6v-2c-3.3.7-4-1.6-4-1.6-.6-1.4-1.3-1.8-1.3-1.8-1.1-.7.1-.7.1-.7 1.2 0 1.8 1.2 1.8 1.2 1 1.8 2.8 1.3 3.5 1 0-.8.4-1.3.7-1.6-2.7-.3-5.5-1.3-5.5-5.9 0-1.3.5-2.4 1.2-3.2 0-.3-.5-1.5.2-3.2 0 0 1-.3 3.3 1.2a11.5 11.5 0 0 1 6 0C17.3 4.7 18.3 5 18.3 5c.7 1.7.2 2.9.1 3.2.8.8 1.2 1.9 1.2 3.2 0 4.6-2.8 5.6-5.5 5.9.5.4.8 1.1.8 2.2v3.3c0 .3.2.7.8.6A12 12 0 0 0 12 .3z"/></svg>
        GitHub
      </a>
    </div>

    <p class="foot">© 2026 DesktopPet · Made for terminal dwellers</p>
  </main>
</body>
</html>`;

export const onRequest: MiddlewareHandler = async (context, next) => {
  if (!MAINTENANCE) return next();
  const path = context.url.pathname;
  // Keep the API alive (the macOS app uses /api/*) and let static assets
  // (favicon, fonts, /_astro chunks, images) load for the page itself.
  if (path.startsWith("/api/") || path.startsWith("/_") || /\.[a-zA-Z0-9]+$/.test(path)) {
    return next();
  }
  return new Response(PAGE, {
    status: 503,
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "no-store",
      "retry-after": "3600",
    },
  });
};
