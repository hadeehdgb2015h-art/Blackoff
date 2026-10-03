# Development status

Read this first in a new session. Then read `docs/TECHNICAL_ARCHITECTURE.md`, `docs/TODO.md` and `docs/systems/`.

## Current phase

**Phases 5 and 7–13 done** (revive and HUD; client caching; zombies classic; main menu, controls layout editor, audio system; the map doubled with the old grounds and 5 players per zone; TON points with the weekly hunt leaderboard and anti-cheat flags; voice chat with MIC/SPK buttons, relayed by the server; infection mode, players vs players up to 10). The owner's expansion list (13 items, phases 7–13 in `docs/TODO.md`) is complete. **Phase 14** answered the owner's first phone feedback: no sound (runtime audio buses looped the web sample graph; flat audio on the web, `docs/systems/presentation.md`), lag and heat (auto quality from the measured frame rate, 30 FPS option, fewer redraws), and a cheap-looking UI (dark fantasy theme: Cinzel, stone and brass panels, ember buttons, `docs/systems/input-and-hud.md`). Still waiting for the installer run on the owner's server. The owner decides the TON economics: `TON_MICRO_PER_KILL` and `TON_PRIZE_TEXT` in the server `.env`, prizes paid by hand from `/admin/leaderboard`. Phase 6 (performance tiers, anti-cheat logging) is folded into phase 11. **Phase 4 (Telegram, DB, deploy): built and rehearsed in CI; waiting for the owner to run the installer.** The owner's server (from `deploy/check.sh`): Ubuntu 22.04, 2 CPUs, 3.9 GB RAM (1.5 GB free), 3.4 GB disk free, Node 20.20, pm2 7.0.1 with ~25 apps, nginx 1.18 with 8 sites, certbot 1.21, Postgres on 5432, public IP 93.115.22.64, free port 8787. They run one command (`deploy/install.sh`, see `docs/systems/deploy.md`); the default address `blackoff.93-115-22-64.sslip.io` needs no DNS work. Then they create a bot with @BotFather and paste the token when asked.

| Phase | State |
|---|---|
| 0 Foundation | done (owner tested: 60 FPS on their phone) |
| 1 Local client | done (owner tested: 60–70 FPS) |
| 2 Authoritative server | done (`docs/systems/server.md`) |
| 3 Sync | done (`docs/systems/netcode.md`) |
| 4 Telegram, DB, deploy | built (`docs/systems/deploy.md`); owner runs the installer |
| 5 Revive, buy, final HUD | done (`docs/systems/simulation.md`, `input-and-hud.md`) |
| 7 Client caching | done (`docs/systems/deploy.md`) |
| 8 Zombies classic | done (`docs/systems/simulation.md`, `presentation.md`) |
| 9 Menu, controls layout, audio | done (`docs/systems/presentation.md`, `input-and-hud.md`) |
| 10 Map ×2, 5 players | done (`docs/systems/maps.md`) |
| 11 TON hunt, anti-cheat | done (`docs/systems/server.md`) |
| 12 Voice chat | done (`docs/systems/netcode.md`, `input-and-hud.md`) |
| 13 Infection mode | done (`docs/systems/server.md`, `netcode.md`) |
| 14 Phone feedback: sound, performance, look | done (`docs/systems/presentation.md`, `input-and-hud.md`) |
| 15–16 Phone performance, first-shot freeze, Arabic phones | done (`docs/systems/presentation.md`) |
| 17 Real sounds, crackle fix, smaller download | done (`docs/systems/presentation.md`, `docs/ASSET_LICENSES.md`, `tools/engine/`) |
| 18 Real music, phone quality fix, TON display | done (`docs/systems/presentation.md`) |
| 19 Invite friends, challenge, feel | done (`docs/systems/netcode.md`, `presentation.md`, `deploy.md`) |
| 20 Boss wave, bot replies and owner panel, dev powers | done (`docs/systems/server.md`, `presentation.md`) |
| 21 Sky visions beside the moon | done (`docs/systems/presentation.md`) |
| 22 Aim down sights, sniper scope, third-person camera (protocol v10) | done (`docs/systems/presentation.md`, `input-and-hud.md`) |
| 23 Daily reward (7-day streak) and daily missions, paid in TON points (protocol v11) | done (`docs/systems/server.md`, `presentation.md`) |
| 24 Interface in English, Arabic and Russian, chosen in Settings (page reloads), right-to-left panels | done (`docs/systems/presentation.md`) |
| 25 Shareable result card drawn by the server, sent to chats / stories from the game (protocol v12) | done (`docs/systems/server.md`) |
| 26 Levels (XP from the server's record) and 13 ranks with drawn insignia, level-up banner, ranks in the team list and on the card (protocol v13) | done (`docs/systems/server.md`, `presentation.md`) |

## Live preview

**https://hadeehdgb2015h-art.github.io/Blackoff/**: GitHub Pages, redeployed by CI on every push. The cloud session proxy blocks github.io, so the CI `pages` job verifies the live URL itself. Total first download is about 13 MB since phase 17 (stripped engine 24 MB wasm served as 6.2 MB gzip + 7.3 MB pck; it was 22 MB: 9.6 MB engine + 12.4 MB pck).
URL flags: `?autostart=1` (skip menu), `?bot=1` (test bot plays), `?debug=1` (exposes `window.__blackoff`), `?showcase=1|box|soldier`, `?weapon=<id>`, `?at=x,z,yaw[,pitch]` (camera placement), `?view=fpp|tpp`, `?ads=1`, `?lang=ar|ru|en`, `?online=1` / `?server=` (quick play online), `&r=N` (bypass a stale `index.html` on Pages, max 10 min; the game files themselves are content-hashed since phase 7 and never stale).

## What exists

| Area | State |
|---|---|
| Map | `facility_01` (textured, prop-dressed, violet dark-fantasy tint): safe room (5 spawns, ammo, Ironhide machine), 2 corridors, lab (AR-7 wall-buy, Quickhand machine), storage (supply cache with beacon beam, Longstride machine), yard (Switchblade machine), and since phase 10 the old grounds to the south: graveyard cloister, crypt, chapel (shotgun wall-buy), catacomb (SMG wall-buy); 7 zombie entries; 262 batched meshes. Pipeline: generator → scene → `shared/maps/facility_01.json` (`docs/systems/maps.md`). |
| Sim | `client/scripts/sim/`: authoritative rules at 20 Hz (movement, weapons, zombies, waves, economy, downed → game over). `server/src/sim/` mirrors it; `shared/tests/golden.json` pins the contract (`docs/systems/simulation.md`). |
| Presentation | first-person rig, procedural zombie and weapon placeholders, tracers and impacts, generated SFX, map mesh batching, quality tiers (`docs/systems/presentation.md`). |
| Input / UI | multi-touch stick, aim, fire-aim, reload, swap, use, pause; keyboard/mouse; movable/resizable controls with an editor; HUD; pause; settings (look, volumes, quality, layout); game over; main menu with profile card (`docs/systems/input-and-hud.md`). |
| Server | phase 2: authoritative TypeScript sim (port of the client rules), binary codec from `protocol.json`, Telegram initData HMAC, sessions with validation, rate limits and resume, zones with quick play, snapshots with interest radius, `/healthz` stats, load-test bots (`docs/systems/server.md`). |
| Deploy | release bundle + GitHub release `edge`, `deploy/install.sh` (own pm2 apps, own nginx site, own certificate, own DB), self-updater with health-check rollback, uninstall (`docs/systems/deploy.md`). Player profiles in Postgres (games, kills, best wave) shown in the menu. |
| Tests / CI | 39 headless client tests (incl. golden contract), online end-to-end (2 Godot bots + web build vs a real server, plus an infection round between 2 bots), voice end-to-end (Chromium with a fake microphone and a talking Node bot hear each other), bot playthrough, 2-minute headless game run, browser bot and multi-touch runs, 61 server tests (sim incl. revive/respawn, power-ups, perks, energy/wind weapons, infection rounds and claws, codec, auth, WebSocket flow incl. revive, scoreboard, the weekly hunt and infection matching, admin pages, anti-cheat flags, voice codec and relay, perf, profiles and weekly scores incl. real Postgres), deploy rehearsal (installer on a clean runner, Telegram Mini App login through nginx, restart, update, uninstall), golden freshness check, 16-bot load test with a 2 ms tick budget, map sync check, Pages deploy and verification (`docs/systems/testing.md`). |

## Art stage (in progress, owner request)

The owner asked for original "Black Ops-like" art built by us in stages: (1) zombies + supply cache ✅, (2) weapons + first-person hands ✅, (3) facility props, textures, lighting and dark-fantasy atmosphere ✅ (reworked after owner feedback), (4) soldier character. The pipeline is in `docs/systems/art-pipeline.md`. Stage 4 (soldier) is folded into phase 3, where other players first appear on screen.
Also added on request: the supply cache (random weapon box) and two box-only weapons (KS-12 shotgun, VX-9 SMG).

## Owner feedback log
- Stage 3 first pass: quality looked worse, look sensitivity was bad, the aim moved with the move stick, and there was no dark-fantasy feel. Fixed: textures switched from ETC2 to WebP plus MSAA; the browser pointer-to-mouse double input was removed (it caused both the stick-turns-camera bug and the jumpy sensitivity); a new aim curve, smoothing and aim slowdown; a full dark-fantasy atmosphere layer (see `docs/systems/art-pipeline.md`).
- Stage 3, second round: the owner liked it, asked to remove the star from the rune circle (no stars or polygrams anywhere), and sent five dark-fantasy reference images. Added: dark props (skeletons, graves, gothic gates, spikes, braziers, candles, banners, dead trees), a far backdrop (mountains, forest, castle, giant hand holding a castle), a grinning moon behind the castle, and a lightning storm with thunder (see `docs/systems/art-pipeline.md`).
- Third round: the owner measured **60–70 FPS** on their phone, and asked to remove every circle as well. All rune circles and wall glyphs are gone; the rule is no circles, stars, sigils or religious symbols.

- Phase 27, players' report: "the aim is very heavy" and "I can't get out of any menu". Look speed raised (0.16° → 0.22° per px, slow drags 0.6× → 0.85×), aim slowdown softened (0.55× → 0.8×, narrower), the scope slows less. Telegram's back button and the phone's back key now close the open panel (or pause in a game) instead of leaving the Mini App.

## Known limitations

- All characters, weapons and the map use generated art (soldier for other players added in phase 3).
- No baked lighting yet: lights are dynamic without shadows.
- UI text is English only. Arabic needs a bundled font.
- Solo play has nobody to revive you: down → game over.
- In headless Chromium (software GL) the game runs at 2–9 FPS. That is not representative; real phones must be tested by the owner.

## How to build and test

```bash
GODOT_DIR=/opt/godot tools/setup_godot.sh       # pinned editor + web templates (GitHub releases)
tools/build_maps.sh                              # regenerate greybox + export map JSON
tools/export_web.sh                              # sync shared → headless tests → build/web
SMOKE_DPR=0.5 NODE_PATH=$(npm root -g) node tools/smoke_web.cjs build/web /tmp/s.png "?autostart=1&bot=1" 45
SMOKE_TOUCH=1 NODE_PATH=$(npm root -g) node tools/smoke_web.cjs build/web /tmp/t.png "?autostart=1&debug=1" 5
cd server && npm ci && npm run typecheck && npm test
python3 tools/gen_textures.py                    # regenerate placeholder textures
/opt/blender-venv/bin/python tools/sfx/build_sfx.py   # rebuild the sounds from art/sfx_sources (ffmpeg + numpy)
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

## Next steps (phase 4)

1. The owner runs `curl -fsSL https://raw.githubusercontent.com/hadeehdgb2015h-art/Blackoff/claude/hopeful-cerf-elsmwp/deploy/check.sh | bash` on their server (read only) and sends the output, the domain, and a subdomain choice.
2. From that, write `deploy/install.sh`. It must only add:
   - its own directory;
   - its own pm2 app `blackoff`;
   - its own nginx file for the game subdomain (WebSocket proxy to a free port), checked with `nginx -t` before reload;
   - certbot for that subdomain only.
   Nothing else on the server may change.
3. Set `client/data/net.json` → `server` to `wss://<subdomain>/ws`, then Telegram bot setup (Mini App URL = the Pages link or the subdomain), and Postgres profiles.
Local end-to-end test: `cd server && ALLOW_DEV_AUTH=1 npm run dev`, then open the web build with `?server=ws://127.0.0.1:8787/ws`.
