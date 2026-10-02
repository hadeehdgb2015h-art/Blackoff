# Presentation

## Audio (phase 9)
`Audio` autoload (`scripts/core/audio.gd`): buses Music, SFX and UI under Master (volumes from Settings: master, music, sound effects), a reverb on the SFX bus whose room size and wetness follow the local player (indoors when walls surround them, from 8 short raycasts twice a second), looping music with crossfades (`music_menu`, `music_ambient` between waves, `music_tension` during a wave, silence at game over), and UI clicks on every button. `Sfx` plays on the SFX bus; 3D sounds behind a wall (raycast through the sim map) are low-passed and quieter. The local player gets footsteps (4 variants, faster with Longstride), a heartbeat under 30 % health, a hit tick on every hit and a chime on head kills. All sounds and music are synthesised by `tools/gen_sfx.py` (`music_*` loop; `tools/fix_audio_imports.py` sets loop and QOA compression).

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
