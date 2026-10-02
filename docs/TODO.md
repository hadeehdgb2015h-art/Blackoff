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
## Phase 6: performance tiers + anti-cheat logging (folded into phases 9 and 11)

## Owner expansion list (received after phase 5), scheduled as phases 7–13
## Phase 7: client caching ✅ done
- [x] Content-hashed engine and pack files, immutable headers, service worker; revisit downloads nothing, update downloads only the changed file (CI-tested)
## Phase 8: zombies classic ✅ done
- [x] Power-up drops from zombies (insta-kill, double points, max ammo, nuke, fire sale), timed, zone-wide
- [x] Perk machines (Ironhide Brew, Quickhand Soda, Longstride Tonic, Switchblade Fizz) on the map; lost when downed
- [x] New weapons: BR-80 Mauler (LMG), LR-50 Longshot (sniper), Arc Lance (rare, splash), Gale Cannon (rare, cone blast)
- [x] Green beacon beam over the supply cache
## Phase 9: UI and audio ✅ done
- [x] Main menu: backdrop, PLAY ONLINE, solo, settings / controls / how to play, profile card, coming-next line
- [x] Controls layout editor: drag, resize, second FIRE button, opacity, reset/save (saved per device)
- [x] Audio: Music/SFX/UI buses with settings, room reverb, occlusion, music loops with crossfades, footsteps, heartbeat, hit tick, headshot chime, UI clicks
## Phase 10: map ×2 + 5 players per zone ✅ done
- [x] The old grounds: graveyard cloister, crypt, chapel, catacomb; 3 more zombie gates; SMG and shotgun wall-buys; stone texture; 4 new props
- [x] `zone.maxPlayers` 5, a fifth spawn
## Phase 11: TON points, weekly hunt, anti-cheat ✅ done
- [x] TON points per kill (`TON_MICRO_PER_KILL`, server-side), in profile and weekly scores (Postgres + memory)
- [x] Weekly leaderboard in the menu, standing in the profile card, HUD pops; `/admin/leaderboard` and `/admin/suspects`
- [x] Anti-cheat flags (hit rate, head-shot rate, kills per minute) logged and counted; no automatic bans
## Phase 12: voice chat (done)
- [x] Microphone capture in the page (`client/web/voice.js`): echo cancellation, noise suppression, auto gain, 16 kHz mono, voice gate, IMA ADPCM frames (40 ms, 324 bytes)
- [x] Server relay per zone (`voice` / `voiceListen`, protocol v6, `VOICE_CHAT` env), rate- and size-limited, never decoded
- [x] MIC and SPK buttons on the HUD (movable in CONTROLS), talking marks in the team panel, speaker choice remembered, mic always off at start
- [x] Tests: codec and relay (Node), fake-microphone browser test with a talking bot (CI)
- [ ] Known limit: some Telegram versions give the page no microphone (the MIC button then says so); the speaker still works
## Phase 13: infection mode (real zombies vs real soldiers, up to 10, no bots)

## Open questions for the owner
- Own subdomain or the free sslip.io address (installer default)
