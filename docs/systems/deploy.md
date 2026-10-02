# Deployment (phase 4)

The owner's server is shared (many pm2 apps, nginx sites and certificates). The
installer adds only its own pieces and never edits anything else.

## Pieces
| Piece | What |
|---|---|
| `tools/make_release.sh` | packs `server/dist-bundle/server.mjs` (esbuild, Node 20 target, no `node_modules`), `shared/` data, the web build and `deploy/*.sh` into `blackoff.tar.gz` + `.sha256` + `version.txt` |
| CI job `release` | on pushes to the deploy branch: packs a release, **rehearses the real installer** on a clean runner (Node 20, pm2 7.0.1, nginx, Postgres), then publishes the files to the GitHub release `edge` (`version.txt` uploaded last) |
| `deploy/install.sh` | one-time setup on the owner's server (re-runnable, keeps settings) |
| `deploy/update.sh` | the updater, run by pm2 as `blackoff-updater --loop 300` |
| `deploy/uninstall.sh` | removes everything the installer created |
| `deploy/check.sh` | read-only survey of the server (sent by the owner before installing) |

## What the installer creates
- `/opt/blackoff/`: `releases/<version>/`, `current` (symlink), `.env` (mode 600; secrets never printed), `logs/`, `bin/update.sh`, `bin/uninstall.sh`, `acme/` (certificate challenges), `backups/` (the previous `pm2 save` list), `ecosystem.config.cjs`.
- pm2 apps `blackoff` (the game server on `127.0.0.1:PORT`) and `blackoff-updater`. Then `pm2 save`, after backing up the old dump.
- nginx: `/etc/nginx/sites-available/blackoff` + link, only `server_name DOMAIN`. It serves the web build (pre-gzipped, `gzip_static`, `application/wasm`, `no-cache` + revalidation), proxies `/ws` (WebSocket) and `/healthz`, and sets `X-Forwarded-For` to the real client address. Every write runs `nginx -t` first; on failure our file is removed again and nginx is not reloaded.
- One Let's Encrypt certificate via `certbot certonly --webroot` (other sites' configs untouched), renewed by the existing certbot timer, with a deploy hook that reloads nginx.
- Postgres: a new role and database `blackoff` with a random password, only if neither exists already. Without Postgres the server keeps profiles in memory.
- Telegram: the bot token (asked with hidden input, checked with `getMe`) goes only into `.env`. The bot's menu button is set to open the game.

Safety checks before any change: running as root, Node ≥ 20, pm2/nginx/certbot present, `nginx -t` already passing, `/opt/blackoff` and the nginx file either absent or ours (marker line), the domain not used by another site, the domain resolving to this server, and the port free.

## Domain
Default: `blackoff.<ip-with-dashes>.sslip.io`, which resolves to the server without any DNS setup. With `--domain play.example.com` the owner's own subdomain is used (needs a DNS `A` record to the server IP first). Re-running with another `--domain` moves the site.

## Updates
`blackoff-updater` checks `version.txt` of the `edge` release every 5 minutes. A new version is downloaded, checked against its sha256, unpacked into `releases/`, pre-compressed, given `web/config.js` (the server URL for the client), switched in via the `current` symlink and started with `pm2 restart blackoff`. If `/healthz` does not answer within 25 s, the previous version comes back and the bad version is skipped from then on. While players are online the update waits (up to 2 hours). The last 3 releases are kept.

## Client configuration at runtime
`index.html` loads an optional `config.js` (`window.BLACKOFF_CONFIG = { server: "wss://DOMAIN/ws" }`), written by the updater. The client picks the server from `?server=`, then `config.js`, then `res://data/net.json`. GitHub Pages has no `config.js`, so the preview stays offline unless `?server=` is given. Outside Telegram the online button reads "open in Telegram" (the live server accepts Telegram logins only).

## Commands on the server
```bash
curl -fsSL https://raw.githubusercontent.com/hadeehdgb2015h-art/Blackoff/claude/hopeful-cerf-elsmwp/deploy/install.sh | bash
#   ... | bash -s -- --domain play.example.com     (own subdomain)
pm2 logs blackoff                    # server log
bash /opt/blackoff/bin/update.sh --once --force   # update now
bash /opt/blackoff/bin/uninstall.sh  # remove (keeps the database unless --drop-db)
```

## Rehearsed in CI (job `release`)
Install with `--no-tls` as `blackoff.localhost` (Chromium treats `*.localhost` as a secure context, like HTTPS) → `/healthz` through nginx reports the Postgres store → wasm served gzip with the wasm MIME type → `config.js` → a Telegram-signed login plays, leaves and gets its game counted (`server/tools/smokeDeploy.ts`) → restart, and the profile is still there → the web build opened as a Telegram Mini App (mocked `Telegram.WebApp` with signed initData) joins a zone → the updater installs a newer release → uninstall leaves no trace and `nginx -t` still passes.
