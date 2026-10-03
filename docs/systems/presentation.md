# Presentation

## Phone performance (phase 15)
Measured in Chromium at phone pixel density (`scratchpad/measure.cjs`, `?debug=1` publishes `draw`, `prims`, `objects`, `canvas`): standing at the spawn with no zombie the game issued 285 draw calls and 215 k triangles per frame, and the canvas was the panel's native size (a 2.5–3 megapixel 3D frame). Script time was under 1 ms. WebGL draw calls and fill rate are what a phone pays for, so:
- the shell caps the canvas at 720 lines on touch screens (`BlackoffRotate.layout`), whatever the device pixel ratio;
- `MapBatcher` merges in 24 m chunks (was 12) and puts decoration props in their own meshes with `visibility_range_end` 42 m;
- `game.gd: _cull_lights` keeps only lights near the player on (26 m on low, 40 medium, 80 high; the "extra" group only on medium and up);
- on low, zombies beyond 30 m keep their pose (animation paused) and are only moved;
- auto quality is sticky: phones stay on low by themselves (the player can choose more), a tier that dropped never climbs back in the session; the frame cap is auto (60, then 30 for the session once the phone cannot hold ~50), with 60 and 30 as manual choices;
- the menu pre-loads the zombie, start-weapon and soldier models under the loading curtain;
- `?perf=1` prints a per-section script-time breakdown every 10 s; the FPS label shows the tier.

## First-shot freeze, Arabic phones, saved settings (phase 16)
From the owner's phone (Telegram in Arabic, 51 FPS, 161 draw calls):
- **First shot froze the game:** on the web a sound becomes a browser sample (decoded) the first time it plays, and WebGL compiles a material's shader the first time it is drawn. `Sfx` now registers every sound as a sample while the game loads, and `game.gd: _prewarm_gpu` draws each zombie type (with its hit flash), a teammate, the muzzle flash, tracer, impacts, blast and bolt once in front of the camera behind a short "PREPARING" cover as the match starts.
- **HUD and menu mirrored:** the engine mirrors every Control in right-to-left locales, and a Control positioned before it joins the tree stores its offsets mirrored (it takes its direction from the locale). The interface is English: `Platform` sets the English locale for layout and the root window left-to-right; Arabic player names are still shaped and ordered by the text server. `SMOKE_LOCALE=ar` reproduces the phone in the browser test.
- **Slow to enter, every time:** placing the map's 210 props and merging its meshes took 1.5 s per match in the browser (more on a phone), repeated on every "play again". `MapCache` prepares the map once per session under the menu's curtain at start-up (with the model pre-load) and each match takes a cheap duplicate sharing the merged meshes.
- **Still hot at 51 FPS:** the phone kept a 60 FPS cap saved by an older build. Settings now carry a version; older files are reset to automatic quality and frame cap (a steady 30 on phones).
- Merged map meshes use compressed vertex attributes (less GPU memory traffic). Baking the merged map at build time was measured and rejected: 6 MB more on every update download for ~0.35 s (server CPU) less loading.
- Telegram insets are scaled by the canvas's own height when the page turns the canvas.

## Audio on the web (phase 14)
The web export runs without threads, so the engine plays every sound as a browser sample (an `AudioBufferSourceNode` per playback, gain nodes per bus). Buses added at runtime came out wired in a loop in that graph (bus → previous bus, master → bus), and Web Audio renders a loop without a delay as silence: the owner heard nothing. `Audio.flat` (true on the web) keeps every player on Master and applies the music and effects volumes per player (`Audio.bus_for`, `Audio.sfx_offset_db`); bus effects (reverb, low-pass) do not exist in sample mode anyway. The analyser probe (`scratchpad` during phase 14) confirmed sound reaches the destination. Phones: iPhone mutes Web Audio with the ringer switch; the first tap on the page also unlocks the browser's audio.

## Audio (phase 9)
`Audio` autoload (`scripts/core/audio.gd`): buses Music, SFX and UI under Master (volumes from Settings: master, music, sound effects), a reverb on the SFX bus whose room size and wetness follow the local player (indoors when walls surround them, from 8 short raycasts twice a second), looping music with crossfades (`music_menu`, `music_ambient` between waves, `music_tension` during a wave, silence at game over), and UI clicks on every button. `Sfx` plays on the SFX bus; 3D sounds behind a wall (raycast through the sim map) are low-passed and quieter. The local player gets footsteps (4 variants, faster with Longstride), a heartbeat under 30 % health, a hit tick on every hit and a chime on head kills. All sounds are real CC0 recordings (gunshots, zombie voices, reload, rain, Kenney footsteps, impacts, bells and clicks; sources in `docs/ASSET_LICENSES.md`) cut by `tools/sfx/build_sfx.py`: each file starts on its attack, fades to silence before its last sample and peaks below full scale; the music is three real CC0 tracks (menu, between waves, during a wave) cut by `build_music` into loops whose end matches their start: the loop length is chosen where the next 3 s of music look most like the first 3 s, then refined to the sample and crossfaded. Phase 18 replaced the phase 17 rain bed, which the owner heard as an old TV's static coming and going (rain is broadband noise, and it faded in and out with every wave). `tools/fix_audio_imports.py` keeps effects under 0.8 s as 16-bit PCM and QOA-compresses the rest (music at 22 kHz).

Phase 17 crackle fix: in the browser a voice that is reused is stopped mid-waveform, which clicks, and a shared pool of 8 players made shots, ticks and steps cut each other off. Each 2D sound now has its own player with a small voice limit (`Sfx.VOICES`, 3 for fast guns), 3D sounds take a free player before stealing the oldest, and `client/web/shell.html` puts a fast limiter (DynamicsCompressor, threshold -4 dB) between the engine and the speakers so stacked shots no longer clip. The thunder that rolled every 9-20 s (heard as "a sound every 15 seconds") now comes every 45-90 s, softer; footsteps are a soft concrete step every 0.5 s at -24 dB; zombies groan every 2.5-6 s from four voices.

## Main menu (phase 9)
A screenshot backdrop (`assets/ui/menu_bg.jpg`, an in-game capture) with a left shade, the title, the mode line, a big PLAY ONLINE button (disabled with the reason when no server is set or outside Telegram), SOLO PRACTICE, SETTINGS / CONTROLS / HOW TO PLAY, a "coming next" line, and a profile card (name, best wave, kills, games when logged in; otherwise the Telegram hint). `?screen=layout` opens the controls editor for screenshots.

Phase 8 adds: `PowerupView` (spinning emissive prism, name, light, blinks before vanishing), `PerkMachineView` (procedural vending machine in the perk's colour with name and price), a green beacon beam over the supply cache (`fx_beam.gdshader`, hidden while the cache is in use), coloured energy bolts and a cone blast in `Effects`, four more viewmodels (`vm_lmg`, `vm_sniper`, `vm_arc`, `vm_gale`) and sounds (`lmg_shot`, `sniper_shot`, `arc_shot`, `gale_shot`, `powerup`).

`client/scripts/view/` plus `client/scenes/game/game.gd`.

- `game.gd` advances the sim with an accumulator (20 Hz), feeds events to views, HUD and audio, and interpolates every entity between the last two ticks. Aim (yaw/pitch) is applied immediately at render rate, so looking feels instant.
- `fp_rig.gd`: first-person camera and weapon viewmodel (bob, recoil kick, reload and switch animation, muzzle flash; muzzle light on high quality).
- `zombie_view.gd`: interpolated zombie with a procedural placeholder rig (merged meshes, 3 draw calls), walk sway, attack swing, hit flash (material overlay) and death fall.
- `effects.gd`: pooled tracers and impact puffs. `sfx.gd`: pooled 2D and 3D audio.
- `map_batcher.gd`: merges static map meshes by material.
- `atmosphere.gd`: dark-fantasy effects at the map's `map_fx` markers: corruption veins and hellfire fissures (additive shader sprites; no circles or symbols, owner rule), drifting motes, ground mist, brazier fires and candles with flickering lights, light shafts, the floating rift crystal over the yard breach, the far backdrop (mountains, castle, giant hand, a pine forest MultiMesh), the moon-face billboard, and a lightning storm (emits `thunder`, which the game plays after a delay). The sky is a shader (`shaders/sky_night.gdshader`): moon, stars, clouds and a glowing rift. A violet screen vignette sits under the HUD. Zombie eye glow colour comes from `visuals.json` (`eyes`).

## Art integration points
`client/data/visuals.json` is client-only presentation data.
- `weapons.<id>.model`: path to a `.glb`/`.tscn`; origin at the grip, optional child `Muzzle` (Marker3D).
- `zombies.<id>.model`: path to a scene with an `AnimationPlayer` having `walk`, `attack`, `death`.
- When `model` is empty, the procedural placeholder is used. Placeholders are **not** finished art.
- Sounds: replace the files in `client/assets/sfx/`; names are listed in `sfx.gd`.

## Quality tiers (Settings → Graphics)
| Tier | 3D scale | MSAA | Lights | Muzzle light | Fog / glow | Mist, light shafts | Far |
|---|---|---|---|---|---|---|---|
| low | 0.65 | off | key lights only | off | off | off, motes 40 %, forest 50 % | 520 m |
| medium (default) | 0.85 | 2× | all | off | on | on | 650 m |
| high | 1.0 | 4× | all | on | on | on | 700 m |

Textures ship as lossy WebP (lossless for `fx_*` sprites). ETC2 GPU compression was tried and made the art blocky on phones; the WebP pack is also smaller (≈ 6 MB).

## Feel (phase 19)
Kills chain into call-outs when they come less than 2.6 s apart (`Hud.STREAK_NAMES`: DOUBLE KILL, TRIPLE KILL, QUAD KILL, RAMPAGE, MASSACRE, UNSTOPPABLE, GODLIKE) with a chime and a haptic tap; a lone head kill says HEADSHOT. Call-outs and banners punch in (scale 1.3-1.8 to 1 with a back ease). Every local shot adds camera shake by weapon weight (`recoilKick` x 2.5, capped), a kill widens the view for a moment (1.6 degrees, 3 for a head kill), and every kill bursts blood around the body and leaves a ragged splat on the floor for 9 s (`Effects.gore`, 12 pooled floor quads with a texture drawn once at load; its shader is warmed with the others).

## Boss waves (phase 20)
Every 5th wave (`waves.json` `boss`) adds THE WARDEN (`zombies.json` `boss`: 2400 health + 220 per wave, x(1 + 0.75 per extra player), slow, hits for 55, pays 1500) six seconds after the wave starts; it counts in the wave's zombies. Both sims spawn it the same way (`WaveDirector.bosses_for` / `boss_health_mul`, pinned by tests on both sides). It reuses the walker model at 1.72x with a dark red multiply tint (`visuals.json` `modelScale`, `tint`, `bossName`). Its arrival shakes the screen with a deep roar and thunder and shows "THE WARDEN HAS RISEN"; while it lives a red health bar with its name sits under the wave counter; its death bursts blood and tolls a bell. `?showcase=boss` adds it to the art review.

## Sky visions (phase 21)
Every 20-32 s a vision fades in beside the moon (3.5 s), lingers 10 s with a slow ripple and shimmer, and fades out; the next one comes on the other side (`scripts/view/sky_visions.gd`, `shaders/fx_vision.gdshader`). Six original scenes rendered by `art/blender/build_visions.py` (Cycles): the moon over a sea of hooded statues, a whale swimming through the clouds over waterfalls, a glowing tree on a floating mound, the lantern keeper on the shore, the watcher's eye in a storm and BLACK OFF in the clouds (good for screenshots and clips). Cost: one additive camera-facing quad at the moon's distance (inside the 480 m far plane of the low tier), one 512 px texture loaded when its turn comes and released after (about 10-30 KB each in the pack, 97 KB for all six). `?vision=<name>` shows one at once for screenshots.


## Aim down sights and third person (phase 22)
**ADS** (`scripts/view/fp_rig.gd`, `scripts/ui/scope_overlay.gd`): the AIM button (hold right mouse on desktop) sets intent bit 64. The server and the client sim both honour it (`aiming()`: not while reloading, switching or infected): spread × the weapon's `adsSpreadMul` (sniper 0.02, rifle 0.3, shotgun 0.7) and walk speed × `player.adsMoveMul` (0.55). The view eases in over 0.16 s (smoothstep): field of view from 75° to the weapon's `adsFov` (`client/data/visuals.json`, sniper 18°), bob and shake cut, look speed × (fov/75)^0.7 so far targets stay steady without the scope feeling stuck. The gun is brought to the eye each frame: the barrel is levelled along the camera axis and the muzzle moved under the screen centre, so every model lines up without hand-tuned offsets. Iron sights show a red dot; the sniper (`scope: true`) shows a black scope with a lens rim, a mil reticle and a red centre dot, and hides the gun. Reload or swap drops ADS.

**Frame pacing (phase 30)**: on the web `Engine.max_fps` stays 0 and `BlackoffPace` in `shell.html` wraps `requestAnimationFrame`. It measures the display interval and hands the engine every Nth refresh for the cap (30 FPS: every 2nd at 60 Hz, 3rd at 90 Hz, 4th at 120 Hz). The engine's own cap compared clocks and landed frames at 33 or 50 ms. `Settings.apply_fps_cap()` sets it.

**Third person** (default on; VIEW button reads TPP/FPP, key V, or Settings → Third-person camera): the camera sits over the right shoulder (0.62 right, 0.3 up, 2.6 back of the eye) and the local soldier is drawn with the same model teammates see. The camera never goes through walls: a map ray from the head pulls it in at once and eases back out, with a ceiling clamp indoors. Shots go where the crosshair is: the sim aims from the eye at the point under the crosshair (map ray and zombie hit test), so the server sees an ordinary aim and nothing is trusted; tracers start at the soldier's muzzle. Aiming in third person is GTA-style (phase 28): the camera eases in over the shoulder (0.82 right, 0.12 up, 1.7 back) while the field of view narrows to the weapon's `adsFov`, and the crosshair becomes a red dot; only the scoped sniper switches to the first-person scope. The infected always play in first person.

## Daily reward panel (phase 23)
The menu's profile card has DAILY REWARD · MISSIONS (a pulsing ember dot while today's reward waits); a waiting reward also opens the panel by itself once per session. `DailyPanel` (`scripts/ui/daily_panel.gd`) shows the 7-day calendar (taken days in brass, today pulsing ember, the next one marked), CLAIM DAY n (the server decides and pays; the day flashes, "+x TON" rises, a coin sound plays), the countdown to the new day, and the three missions with progress bars and rewards. Mission payouts after a game show as a toast in the menu, or on the HUD if the player is still in a game. `?screen=daily` with `?server=` and `?name=` opens it for screenshots.

## Languages: English, Arabic, Russian (phase 24)
- **Picking**: Settings → Language (three buttons). The choice is saved (settings file and localStorage, which is written at once) and the page reloads, so every text is built again in the new language. The first start uses the player's Telegram language (else the browser's) when it is Arabic or Russian, else English. `?lang=ar|ru|en` forces one (screenshots); `BLACKOFF_LANG` off the web.
- **Texts**: every visible text goes through `tr("English text")`; data names (weapons, perks, power-ups, zombies) through `I18n.name_of()`. `client/data/i18n/ar.json` and `ru.json` map the English text to the translation. `tools/i18n.py check` (run by `export_web.sh`, so CI fails on it) finds every key in the scripts and the shared data and fails on a missing, empty or unused translation or on different placeholders. `python3 tools/i18n.py missing ar` lists what a new text still needs.
- **Layout**: the translation is registered under the English locale on purpose: a right-to-left locale makes the engine mirror every Control, and Controls placed before they join the tree keep mirrored offsets (the phase 16 bug). The HUD and touch controls stay where they are; panels opt in with `I18n.dir(container)` in Arabic (menu column and profile card, settings, pause, daily reward, weekly hunt, how to play, game over, dev panel), so their rows run right to left and text aligns right. Labels shape and order Arabic on their own (also mixed with numbers and Latin names).
- **Fonts**: Cinzel and the engine sans have no Arabic; Cinzel has no Cyrillic. Fallbacks, subset to the scripts they serve (about 100 KB together): Reem Kufi (Arabic titles and buttons), Forum (Cyrillic titles), Cairo (Arabic body text). `I18n` gives the default theme a body font with these fallbacks, so labels, HUD drawings and 3D signs all have the glyphs; `UiTheme.spaced()` leaves Arabic unspaced (letters join).
- **3D**: the map's wall signs (weapon names, AMMO) are translated when the map loads (`game.gd: _translate_signs`); perk machine and power-up labels use `I18n.name_of`.
- **Settings** scroll (they are taller than a phone screen with the language row).
- Server texts written by the owner (maintenance message, weekly prize) are shown as written.

## Levels and ranks in the game (phase 26)
The profile card shows the rank insignia (`RankBadge`, drawn: chevrons, rockers, bars, diamonds or a crown in the tier's metal, no stars), "Rank · Level n" and an XP bar to the next level. When a recorded game raises the level (`Net.level_up`), the menu shows a banner (insignia popping in, LEVEL UP or NEW RANK, the new rank and level, a sound and a haptic); in a game it is a toast. The team list draws each teammate's insignia and level before the name (from the roster), and the game-over panel estimates the XP of the game (the server's count arrives with the profile). `?screen=profile` with `?server=` and `?name=` logs in for screenshots.
