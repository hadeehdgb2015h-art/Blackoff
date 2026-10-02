# TODO

## Phase 1: local client (feel) ✅ done
- [x] Greybox map facility_01 + map pipeline (scene → shared/maps JSON, CI sync check)
- [x] First-person player, interpolated camera, viewmodel with recoil/reload/switch animation
- [x] Multi-touch controls + keyboard/mouse; settings (sensitivity, invert, quality, FPS, volume)
- [x] Pistol + rifle, walker + runner, infinite waves, credits, wall-buy, ammo point
- [x] HUD, pause, game over; generated placeholder SFX
- [x] Tests: 21 headless, bot playthrough, headless game run, browser bot + multi-touch
- [x] Art stages 1–3 (zombies + supply cache, weapons, environment), generated in-repo
- [x] Art stage 4: soldier character (phase 3)
- [ ] Baked lighting (LightmapGI needs a GPU; try in CI with Xvfb/llvmpipe or in the editor later)
- [ ] Arabic UI localisation (needs an Arabic font, e.g. Noto Sans Arabic OFL, which can be fetched from GitHub)

## Phase 2: authoritative server ✅ done
- [x] Binary codec interpreted from `protocol.json` (TS + GDScript), golden vectors checked on both sides
- [x] Zones, quick play matchmaking, zone lifecycle, drift-corrected 20 Hz loop, reconnect grace + resume token
- [x] Server sim: TypeScript port (movement, grid A*, body/head hitscan, waves, economy, supply cache)
- [x] Telegram initData HMAC validation (dev auth only outside production)
- [x] Validation of every client action, rate limits; load-test bots; perf budget in CI
- [ ] Multiple floors (portals between floors): the map has one floor; add when a map needs stairs
- [ ] Lag compensation (rewind targets to the client's view time, capped 200 ms): phase 3, once clients interpolate

## Phase 3: sync
- [ ] Client `Net` autoload (WebSocket + NetCodec), online mode in the game scene (NetWorld with the SimWorld read API)
- [ ] Interpolation buffer, local prediction + reconciliation against `ackSeq`, delta snapshots
- [ ] Soldier character model for other players (art stage 4)

## Phase 4: Telegram, DB, deploy
- [x] initData HMAC validation (phase 2), Postgres profiles + migrations, stats in the menu
- [x] Release bundle + `edge` release from CI, `deploy/install.sh` / `update.sh` / `uninstall.sh`, rehearsed in CI
- [ ] Owner runs the installer on their server and opens the game from their bot

## Phase 5: revive, buy, final HUD ✅ done
- [x] Revive (hold, tick-exact on both sims, reward, bleed-out pause), respawn at the next wave, downs/revives stats
- [x] Buying: wall weapons + ammo refills, ammo point, supply cache (since phase 1)
- [x] HUD: team list, downed-teammate markers (edge-pinned), revive bar, downed screen, game-over table (server `scoreboard`)
- [x] Bots revive teammates (headless/online tests)
## Phase 6: performance tiers + anti-cheat logging

## Open questions for the owner
- Own subdomain or the free sslip.io address (installer default)
