# Community Pet Gallery — setup (not deployed yet)

Phase 1: web upload + gallery at `/pet`, backed by Cloudflare Pages Functions,
D1 (metadata) and R2 (files), on the existing `desktoppet-landing` Pages project.
Public + auto-publish, with validation, per-IP rate limit, a Report button that
auto-hides at a threshold, an admin delete endpoint, and a Telegram ping on each
upload.

## One-time provisioning (run when ready to ship)

```bash
export PATH="/Users/datnt/.n/n/versions/node/22.22.3/bin:$PATH"
export CLOUDFLARE_ACCOUNT_ID=4dfa59a6cf1ecb9cb737c205fb06e3ce

# 1. R2 bucket for pet files
npx wrangler r2 bucket create desktoppet-pets

# 2. D1 database, then paste its id into landing/wrangler.toml (database_id)
npx wrangler d1 create desktoppet-pets
npx wrangler d1 execute desktoppet-pets --remote --file=landing/schema.sql

# 3. Secrets (Pages project)
npx wrangler pages secret put ADMIN_KEY          --project-name=desktoppet-landing
npx wrangler pages secret put TELEGRAM_BOT_TOKEN --project-name=desktoppet-landing
npx wrangler pages secret put TELEGRAM_CHAT_ID   --project-name=desktoppet-landing
```

For Telegram: create a bot via @BotFather → `TELEGRAM_BOT_TOKEN`; send it a message
and read `chat.id` from `https://api.telegram.org/bot<token>/getUpdates` → `TELEGRAM_CHAT_ID`.

## Deploy

```bash
export PATH="/Users/datnt/.n/n/versions/node/22.22.3/bin:$PATH"
export CLOUDFLARE_ACCOUNT_ID=4dfa59a6cf1ecb9cb737c205fb06e3ce
npx wrangler pages deploy landing --project-name=desktoppet-landing --branch=main --commit-dirty=true
```

## Local test (no prod)

```bash
export PATH="/Users/datnt/.n/n/versions/node/22.22.3/bin:$PATH"
npx wrangler d1 execute desktoppet-pets --local --file=landing/schema.sql
npx wrangler pages dev landing   # serves on http://localhost:8788, local D1/R2
```

## Endpoints

- `GET  /api/pets` — manifest `{pets:[{slug,displayName,kind,submittedBy,spritesheetUrl,petJsonUrl}]}` (used by web + app).
- `POST /api/pets` — multipart upload (name, author?, kind?, file=PNG).
- `GET  /api/r2/<key>` — serves a pet file from R2.
- `POST /api/pets/<slug>/report` — flag; auto-hides at `REPORT_HIDE_THRESHOLD`.
- `DELETE /api/admin/<slug>` — `Authorization: Bearer <ADMIN_KEY>` to take a pet down.

## Phase 2 (later)

Point the app's "Browse pets" at `https://agentpet.thenightwatcher.online/api/pets`
as a second source (reuses `RemotePet` + the existing download flow), then ship an
app release.
