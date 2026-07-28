// OAuth provider config + helpers (GitHub, Google). Used by the auth routes.
export const PROVIDERS = {
  github: {
    authUrl: "https://github.com/login/oauth/authorize",
    tokenUrl: "https://github.com/login/oauth/access_token",
    scope: "read:user",
    id: (env) => env.GITHUB_CLIENT_ID,
    secret: (env) => env.GITHUB_CLIENT_SECRET,
    async profile(token) {
      const r = await fetch("https://api.github.com/user", {
        headers: {
          authorization: `Bearer ${token}`,
          "user-agent": "desktoppet-portal",
          accept: "application/vnd.github+json",
        },
      });
      const u = await r.json();
      return { id: String(u.id), name: u.name || u.login || "GitHub user", avatar: u.avatar_url || null };
    },
  },
  google: {
    authUrl: "https://accounts.google.com/o/oauth2/v2/auth",
    tokenUrl: "https://oauth2.googleapis.com/token",
    scope: "openid profile",
    id: (env) => env.GOOGLE_CLIENT_ID,
    secret: (env) => env.GOOGLE_CLIENT_SECRET,
    async profile(token) {
      const r = await fetch("https://openidconnect.googleapis.com/v1/userinfo", {
        headers: { authorization: `Bearer ${token}` },
      });
      const u = await r.json();
      return { id: String(u.sub), name: u.name || "Google user", avatar: u.picture || null };
    },
  },
};

export const redirectUri = (origin, provider) => `${origin}/api/auth/${provider}/callback`;

/** Exchanges an authorization code for an access token. */
export async function exchangeCode(p, env, code, redirect) {
  const r = await fetch(p.tokenUrl, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded", accept: "application/json" },
    body: new URLSearchParams({
      client_id: p.id(env),
      client_secret: p.secret(env),
      code,
      redirect_uri: redirect,
      grant_type: "authorization_code",
    }),
  });
  const data = await r.json();
  return data.access_token || null;
}
