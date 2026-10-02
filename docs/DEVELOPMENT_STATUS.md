# Development status

Read this first in a new session. Then read `docs/TECHNICAL_ARCHITECTURE.md` and `docs/TODO.md`.

## Current phase

**Phase 0 (foundation): done, waiting for owner approval.** Do not start phase 1 until the owner approves.

## What exists

| Area | State |
|---|---|
| Godot client | `client/`, Godot 4.7.2, Compatibility renderer. The boot scene (`scenes/boot`) is a smoke test: a lit 3D room with fog, an FPS counter, a diagnostics label (renderer, GPU, web/touch/Telegram flags, shared data check) and a Fullscreen button. |
| Web export | `tools/export_web.sh` runs the headless tests, then exports `build/web/`. wasm is 38 MB raw, 9.7 MB gzip; pck 28 KB. Checked in headless Chromium with `tools/smoke_web.cjs`. |
| HTML shell | `client/web/shell.html`: loader bar, portrait rotate overlay, Telegram bridge `window.BlackoffTG` (ready, expand, disableVerticalSwipes, requestFullscreen, haptics). The Telegram SDK loads asynchronously with a 2.5 s timeout, so the game still starts if telegram.org is unreachable. |
| Shared data | `shared/*.json`: constants, protocol v1 layout, weapons (pistol, rifle), zombies (walker, runner), waves curve. |
| Server | `server/`: env config (zod), shared data loader with cross-checks, HTTP `/healthz`, a WebSocket endpoint `/ws` (binary only, max message size enforced). 7 vitest tests. |
| CI | `.github/workflows/ci.yml`: server typecheck, test and build; client Godot install (cached), tests, export, Chromium smoke test, and the web build uploaded as an Actions artifact. |
| Deploy | not yet (phase 4). `deploy/.env.example` lists every variable. |

## How to build and test (cloud session or CI)

```bash
GODOT_DIR=/opt/godot tools/setup_godot.sh   # downloads the pinned editor + web templates from GitHub releases
tools/export_web.sh                          # sync shared → client tests → build/web
NODE_PATH=$(npm root -g) node tools/smoke_web.cjs build/web /tmp/shot.png   # needs playwright
cd server && npm ci && npm run typecheck && npm test && npm run build
```

## Environment notes (cloud sessions)

- Downloads from GitHub release assets (`github.com/.../releases/download/...`) work. The GitHub web and API pages for repositories outside this one return 403 through the session proxy; use `git ls-remote --tags` to discover versions.
- Chromium for Playwright lives at `/opt/pw-browsers`. The global `playwright` package is under `$(npm root -g)`.
- The claude.ai artifact host rejects the 38 MB wasm (15 MB file limit), so it cannot host previews.

## Preview link: live on GitHub Pages

**https://hadeehdgb2015h-art.github.io/Blackoff/**, redeployed on every push. CI checks it after each deploy: wasm is served gzip, about 10.3 MB total first download. The cloud session proxy blocks github.io, so check it through the CI log.

The repo is public, Pages Source is set to GitHub Actions, and the github-pages environment allows `claude/*`.
Pages is for client previews only. From phase 2 on, the game server runs on the owner's server.

## Needs from owner (open)

- Before phase 2 (game server), set these as GitHub secrets: `DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_SSH_KEY` (private key of a dedicated deploy key), `DEPLOY_PORT` (SSH, optional), plus the domain or subdomain and URL path for the game, and a free local port for the Node process.
- Later (phase 4): Telegram bot token as a server-side secret, and a Postgres database and user.

## Next steps (phase 1, after approval)

See `docs/TODO.md` → Phase 1.
