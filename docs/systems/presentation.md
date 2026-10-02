# Presentation

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
