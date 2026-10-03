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
## Phase 13: infection mode (done)
- [x] Server rules (`server/src/sim/infectionSystem.ts`): lobby with countdown, rounds, first infected picked at random, claws, bullets on infected players, infection on the spot, respawn at a zombie entry, soldiers win on the clock, infected win when nobody is left; no AI zombies, boxes, perks or power-ups; up to 10 players
- [x] Protocol v7: `quickPlay.mode`, `zoneJoined.mode`, `entityFlags.zombie`, events playerKilled/infected/roundStart/roundEnd; zones matched by mode
- [x] Client: PLAY INFECTION in the menu, infected players shown as zombies with name tags, first-person claws, ATTACK button, round HUD, banners, the test bot plays both sides
- [x] Tests: 8 sim and wire tests, CI runs two bots through a round
- [x] Infection kills count in the match and profile but earn no TON (players, not zombies: nothing to farm)
- [ ] Later ideas: round score table, a last-survivor bonus, an infected-only sprint

## Phase 14: phone feedback (sound, performance, look)
- [x] No sound on phones: runtime audio buses looped the web sample graph into silence; flat audio on the web
- [x] Lag and heat: auto quality (phones start low, climb while the frame rate holds), 30 FPS option, controls redraw on change only, same-tap fullscreen
- [x] Dark fantasy UI: Cinzel, stone/brass panels, ember buttons, vignette and embers, loading curtain; settings, leaderboard, layout editor, HUD headlines restyled
- [ ] Still to hear from the owner: phone model, Telegram or browser, frame rate shown by the FPS counter

## Phase 15: radical phone performance
- [x] Canvas capped at 720 lines on touch screens; 24 m batch chunks; props hidden beyond 42 m; lights culled by distance; far zombies hold their pose on low; sticky auto tier; auto 30 FPS cap; model pre-warm; on-screen counters and `?perf=1`
- [ ] Next if still needed: fewer materials per chunk (texture atlas), simpler zombie meshes for far distance, Telegram WebView-specific findings from the owner's FPS screenshot

## Phase 16: owner's phone report (lag, heat, slow entry, first-shot freeze)
- [x] Sounds registered and shaders drawn once at load (first shot no longer freezes)
- [x] Saved 60 FPS from older builds reset to automatic (30 on phones): heat
- [x] Right-to-left mirroring on Arabic phones fixed (HUD and menu)
- [x] Compressed vertex attributes on merged map meshes; load timings printed (`[load]`)
- [ ] Waiting for the owner's next screenshot (FPS line) on the new build

## Phase 17: real sounds and a 10 MB target (owner: crackle, a sound every 15 s, cheap sounds, annoying steps, 50 MB is too big)
- [x] All sounds cut from real CC0 recordings (`tools/sfx/build_sfx.py`, sources in `docs/ASSET_LICENSES.md`); rain bed as seamless music loop
- [x] Crackle: one player per sound with a voice limit, free-first 3D pool, master limiter in the page
- [x] Thunder every 45-90 s (was 9-20 s); footsteps softer and quieter
- [x] Models decimated (soldier 7k, zombies 3.5k, weapons 3-4.5k triangles), 512 px textures, 256 px material maps, no unused LODs or shadow meshes
- [x] Stripped engine template (no physics, navigation, XR, advanced GUI, unused modules), built and cached by CI
- [ ] Owner listens on the phone and reports which sounds still feel wrong
- [ ] Next size step if needed: brotli on the server (nginx module), or fewer weapon models shipped at start

## Phase 18: owner's second phone report
- [x] Static "old TV" hiss: the rain bed is replaced by three real CC0 music loops
- [x] Black lines and stalls on "high": no MSAA on phones, at most 10 lights
- [x] No "+0.00001 TON" on every kill: TON shown once, at game over, in readable form

## Phase 19: a game people talk about
- [x] Invite friends: t.me/<bot>?startapp link straight into the inviter's game (protocol v8)
- [x] Challenge friends from the game-over screen (result + link)
- [x] Feel: kill streak call-outs, shot shake, kill punch, blood bursts and floor splats
- [ ] Owner: enable the bot's Mini App in @BotFather (needed for invite links)
- [ ] Next: boss wave every 5 waves, daily reward and missions, a result card image for sharing

## Phase 20: boss, bot, owner powers
- [x] Boss wave every 5 waves: THE WARDEN (both sims, health bar, roar, tests)
- [x] The bot answers players (Arabic): Play button, stats, weekly top, invite, how to play
- [x] Owner panel in the bot (/admin): live zones, players, top, suspects, broadcast, find/ban/unban, TON per kill and x2, give TON, prize, maintenance, warnings, restart
- [x] Owner DEV powers in game: god mode, infinite ammo, money, heal, skip wave, kill all, summon the Warden, jump to wave
- [x] Daily reward and missions: phase 23

## Phase 21: sky visions
- [x] Six original visions beside the moon (no copied art), one cheap additive quad, ~97 KB
- [ ] Owner: record a clip of a vision for social media

## Phase 22: aim and third person
- [x] Aim down sights: AIM button / right mouse, per-weapon zoom, sights brought to the eye, red dot, tighter spread and slower walk checked by the server (protocol v10)
- [x] Sniper scope overlay (lens, mil reticle, red dot)
- [x] Third-person camera over the shoulder (default), VIEW button and setting, camera never through walls, shots go to the crosshair, ADS switches to first person
- [ ] Owner: try both views on the phone and say which should be the default

## Phase 23: daily reward and missions
- [x] Daily reward: 7-day streak calendar, one claim per day, resets after a missed day
- [x] Three daily missions (easy, medium, hard) with progress after each online game, paid at once, bonus for all three
- [x] Paid in TON points from the TON per kill in force; stored in Postgres (migration 4); protocol v11
- [ ] Owner: decide whether the amounts suit the prize budget (`shared/constants.json` → `daily`)
- [ ] Next: a result card image for sharing

## Open questions for the owner
- Own subdomain or the free sslip.io address (installer default)
