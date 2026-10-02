# Development status

Read this first in a new session. Then read `docs/TECHNICAL_ARCHITECTURE.md`, `docs/TODO.md` and `docs/systems/`.

## Current phase

**Phase 1 (local client, feel test): done, waiting for owner feedback and approval.** Do not start phase 2 until the owner approves.

| Phase | State |
|---|---|
| 0 Foundation | done (owner tested: 60 FPS on their phone) |
| 1 Local client | done, waiting for owner test |
| 2 Authoritative server | not started |

## Live preview

**https://hadeehdgb2015h-art.github.io/Blackoff/**: GitHub Pages, redeployed by CI on every push. The cloud session proxy blocks github.io, so the CI `pages` job verifies the live URL itself. Total first download is about 22 MB (wasm served gzip + 12 MB pck).
URL flags: `?autostart=1` (skip menu), `?bot=1` (test bot plays), `?debug=1` (exposes `window.__blackoff`), `?showcase=1|box`, `?weapon=<id>`, `?at=x,z,yaw[,pitch]` (camera placement), `&r=N` (bypass the phone cache).

## What exists

| Area | State |
|---|---|
| Map | `facility_01` (art stage 3: textured, prop-dressed, bright with a violet dark-fantasy tint): safe room (spawn, ammo), 2 corridors, lab (AR-7 wall-buy), storage, yard, 4 zombie entries. Pipeline: generator → scene → `shared/maps/facility_01.json` (`docs/systems/maps.md`). |
| Sim | `client/scripts/sim/`: authoritative rules at 20 Hz (movement, weapons, zombies, waves, economy, downed → game over). Server phase 2 must mirror it (`docs/systems/simulation.md`). |
| Presentation | first-person rig, procedural zombie and weapon placeholders, tracers and impacts, generated SFX, map mesh batching, quality tiers (`docs/systems/presentation.md`). |
| Input / UI | multi-touch stick, aim, fire-aim, reload, swap, use, pause; keyboard/mouse; HUD; pause; settings; game over; main menu (`docs/systems/input-and-hud.md`). |
| Server | phase 0 skeleton plus map schema validation (loads `shared/maps`). |
| Tests / CI | 26 headless client tests, bot playthrough, 2-minute headless game run, browser bot run, browser multi-touch run, server tests, map sync check, Pages deploy and verification (`docs/systems/testing.md`). |

## Art stage (in progress, owner request)

The owner asked for original "Black Ops-like" art built by us in stages: (1) zombies + supply cache ✅, (2) weapons + first-person hands ✅, (3) facility props, textures and lighting ✅, (4) soldier character. The pipeline is in `docs/systems/art-pipeline.md`. Phase 2 (server) waits until the art stages are done, unless the owner says otherwise.
Also added on request: the supply cache (random weapon box) and two box-only weapons (KS-12 shotgun, VX-9 SMG).

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
- Before phase 2/4: server SSH secrets (`DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_SSH_KEY`, optional `DEPLOY_PORT`), the domain or subdomain and path, and a free local port. Later: Telegram bot token and a Postgres database.

## Next steps (phase 2, after approval)

See `docs/TODO.md` → Phase 2. Start with the TypeScript port of `client/scripts/sim`, using `shared/` data, plus cross-language golden tests on fire rate, wave formulas and hit shapes.
