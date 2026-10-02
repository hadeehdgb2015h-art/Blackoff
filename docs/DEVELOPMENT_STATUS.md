# Development status

Read this first in a new session. Then read `docs/TECHNICAL_ARCHITECTURE.md`, `docs/TODO.md` and `docs/systems/`.

## Current phase

**Phase 2 (authoritative server): done.** The owner approved the art and asked to continue with the next step. Phase 3 (client sync) is next. Online play can only be seen on the phone once the server is deployed (phase 4 needs the owner's server details).

| Phase | State |
|---|---|
| 0 Foundation | done (owner tested: 60 FPS on their phone) |
| 1 Local client | done (owner tested: 60–70 FPS) |
| 2 Authoritative server | done (`docs/systems/server.md`) |
| 3 Sync | next |

## Live preview

**https://hadeehdgb2015h-art.github.io/Blackoff/**: GitHub Pages, redeployed by CI on every push. The cloud session proxy blocks github.io, so the CI `pages` job verifies the live URL itself. Total first download is about 18 MB (wasm served gzip + 8 MB pck).
URL flags: `?autostart=1` (skip menu), `?bot=1` (test bot plays), `?debug=1` (exposes `window.__blackoff`), `?showcase=1|box`, `?weapon=<id>`, `?at=x,z,yaw[,pitch]` (camera placement), `&r=N` (bypass the phone cache).

## What exists

| Area | State |
|---|---|
| Map | `facility_01` (art stage 3: textured, prop-dressed, bright with a violet dark-fantasy tint): safe room (spawn, ammo), 2 corridors, lab (AR-7 wall-buy), storage, yard, 4 zombie entries. Pipeline: generator → scene → `shared/maps/facility_01.json` (`docs/systems/maps.md`). |
| Sim | `client/scripts/sim/`: authoritative rules at 20 Hz (movement, weapons, zombies, waves, economy, downed → game over). `server/src/sim/` mirrors it; `shared/tests/golden.json` pins the contract (`docs/systems/simulation.md`). |
| Presentation | first-person rig, procedural zombie and weapon placeholders, tracers and impacts, generated SFX, map mesh batching, quality tiers (`docs/systems/presentation.md`). |
| Input / UI | multi-touch stick, aim, fire-aim, reload, swap, use, pause; keyboard/mouse; HUD; pause; settings; game over; main menu (`docs/systems/input-and-hud.md`). |
| Server | phase 2: authoritative TypeScript sim (port of the client rules), binary codec from `protocol.json`, Telegram initData HMAC, sessions with validation, rate limits and resume, zones with quick play, snapshots with interest radius, `/healthz` stats, load-test bots (`docs/systems/server.md`). |
| Tests / CI | 30 headless client tests (incl. golden contract), bot playthrough, 2-minute headless game run, browser bot and multi-touch runs, 31 server tests (sim, codec, auth, WebSocket flow, perf), golden freshness check, 16-bot load test with a 2 ms tick budget, map sync check, Pages deploy and verification (`docs/systems/testing.md`). |

## Art stage (in progress, owner request)

The owner asked for original "Black Ops-like" art built by us in stages: (1) zombies + supply cache ✅, (2) weapons + first-person hands ✅, (3) facility props, textures, lighting and dark-fantasy atmosphere ✅ (reworked after owner feedback), (4) soldier character. The pipeline is in `docs/systems/art-pipeline.md`. Stage 4 (soldier) is folded into phase 3, where other players first appear on screen.
Also added on request: the supply cache (random weapon box) and two box-only weapons (KS-12 shotgun, VX-9 SMG).

## Owner feedback log
- Stage 3 first pass: quality looked worse, look sensitivity was bad, the aim moved with the move stick, and there was no dark-fantasy feel. Fixed: textures switched from ETC2 to WebP plus MSAA; the browser pointer-to-mouse double input was removed (it caused both the stick-turns-camera bug and the jumpy sensitivity); a new aim curve, smoothing and aim slowdown; a full dark-fantasy atmosphere layer (see `docs/systems/art-pipeline.md`).
- Stage 3, second round: the owner liked it, asked to remove the star from the rune circle (no stars or polygrams anywhere), and sent five dark-fantasy reference images. Added: dark props (skeletons, graves, gothic gates, spikes, braziers, candles, banners, dead trees), a far backdrop (mountains, forest, castle, giant hand holding a castle), a grinning moon behind the castle, and a lightning storm with thunder (see `docs/systems/art-pipeline.md`).
- Third round: the owner measured **60–70 FPS** on their phone, and asked to remove every circle as well. All rune circles and wall glyphs are gone; the rule is no circles, stars, sigils or religious symbols.

## Known limitations

- Zombies, supply cache, weapons and the map (props, surfaces, lighting) use generated art; the soldier character is still missing (art stage 4, only visible in co-op).
- No baked lighting yet: lights are dynamic without shadows.
- UI text is English only. Arabic needs a bundled font.
- Revive is not implemented yet (phase 5); solo play goes down → bleed-out → game over.
- In headless Chromium (software GL) the game runs at 2–9 FPS. That is not representative; real phones must be tested by the owner.

## How to build and test

```bash
GODOT_DIR=/opt/godot tools/setup_godot.sh       # pinned editor + web templates (GitHub releases)
tools/build_maps.sh                              # regenerate greybox + export map JSON
tools/export_web.sh                              # sync shared → headless tests → build/web
SMOKE_DPR=0.5 NODE_PATH=$(npm root -g) node tools/smoke_web.cjs build/web /tmp/s.png "?autostart=1&bot=1" 45
SMOKE_TOUCH=1 NODE_PATH=$(npm root -g) node tools/smoke_web.cjs build/web /tmp/t.png "?autostart=1&debug=1" 5
cd server && npm ci && npm run typecheck && npm test
python3 tools/gen_sfx.py; python3 tools/gen_textures.py   # regenerate placeholder audio/textures
# art: see docs/systems/art-pipeline.md (Blender as a Python module)
```

## Environment notes (cloud sessions)

- Reachable: GitHub (git, release downloads), npm and PyPI. Blocked: github.io, the asset sites (Kenney, Poly Haven, OpenGameArt…), the GitHub API for other repos.
- Chromium lives at `/opt/pw-browsers`, and the global `playwright` package is under `$(npm root -g)`.
- The map generator saves random sub-resource ids, so the `.tscn` diff is noisy on regeneration. Only commit it when the layout changed.

## Needs from owner (open)

- Phase 1 feedback from the phone: control feel, sensitivity, difficulty, FPS.
- CC0 asset uploads to `assets/incoming/` (list given in the phase 1 report).
- Before phase 4 (deploy): server SSH secrets (`DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_SSH_KEY`, optional `DEPLOY_PORT`), the domain or subdomain and path, and a free local port. Telegram bot token (identity check is ready on the server). Postgres connection.

## Next steps (phase 3)

See `docs/TODO.md` → Phase 3. Build the client `Net` autoload (WebSocket + `NetCodec`) and a `NetWorld` that exposes the SimWorld read API from snapshots and events, so the views stay unchanged. Then add interpolation, local prediction with reconciliation against `ackSeq`, and the soldier model. To try it end to end locally, run the server with `ALLOW_DEV_AUTH=1` and use `?server=ws://…` (to be added).
