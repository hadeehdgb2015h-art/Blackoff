# TODO

## Phase 1: local client (feel) ✅ done
- [x] Greybox map facility_01 + map pipeline (scene → shared/maps JSON, CI sync check)
- [x] First-person player, interpolated camera, viewmodel with recoil/reload/switch animation
- [x] Multi-touch controls + keyboard/mouse; settings (sensitivity, invert, quality, FPS, volume)
- [x] Pistol + rifle, walker + runner, infinite waves, credits, wall-buy, ammo point
- [x] HUD, pause, game over; generated placeholder SFX
- [x] Tests: 22 headless, bot playthrough, headless game run, browser bot + multi-touch
- [ ] Art pass: needs CC0 assets from the owner (list in the phase 1 report)
- [ ] Baked lighting (LightmapGI needs a GPU; try in CI with Xvfb/llvmpipe or in the editor later)
- [ ] Arabic UI localisation (needs an Arabic font, e.g. Noto Sans Arabic OFL, which can be fetched from GitHub)

## Phase 2: authoritative server
- [ ] Binary codec generated from `protocol.json` (TS + GDScript) with round-trip tests
- [ ] Zones, quick play matchmaking, zone lifecycle
- [ ] Server sim: 2D + floor movement, navmesh pathing, capsule/head hitscan, waves, economy
- [ ] Validation of every client action; bot client simulator for load tests

## Phase 3: sync
- [ ] Interpolation buffer, local prediction + reconciliation, delta snapshots, interest management, reconnect with resume token

## Phase 4: Telegram, DB, deploy
- [ ] initData HMAC validation, Postgres profiles + migrations, pm2 + nginx deploy via Actions, manual deploy script

## Phase 5: revive, buy, final HUD
## Phase 6: performance tiers + anti-cheat logging

## Open questions for the owner
- Hosting choice for preview links before phase 4 (see DEVELOPMENT_STATUS.md)
