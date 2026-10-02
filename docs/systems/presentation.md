# Presentation

`client/scripts/view/` plus `client/scenes/game/game.gd`.

- `game.gd` advances the sim with an accumulator (20 Hz), feeds events to views, HUD and audio, and interpolates every entity between the last two ticks. Aim (yaw/pitch) is applied immediately at render rate, so looking feels instant.
- `fp_rig.gd`: first-person camera and weapon viewmodel (bob, recoil kick, reload and switch animation, muzzle flash; muzzle light on high quality).
- `zombie_view.gd`: interpolated zombie with a procedural placeholder rig (merged meshes, 3 draw calls), walk sway, attack swing, hit flash (material overlay) and death fall.
- `effects.gd`: pooled tracers and impact puffs. `sfx.gd`: pooled 2D and 3D audio.
- `map_batcher.gd`: merges static map meshes by material.

## Art integration points
`client/data/visuals.json` is client-only presentation data.
- `weapons.<id>.model`: path to a `.glb`/`.tscn`; origin at the grip, optional child `Muzzle` (Marker3D).
- `zombies.<id>.model`: path to a scene with an `AnimationPlayer` having `walk`, `attack`, `death`.
- When `model` is empty, the procedural placeholder is used. Placeholders are **not** finished art.
- Sounds: replace the files in `client/assets/sfx/`; names are listed in `sfx.gd`.

## Quality tiers (Settings → Graphics)
| Tier | 3D scale | Lights | Muzzle light | Fog | Far |
|---|---|---|---|---|---|
| low | 0.6 | key lights only | off | off | 55 m |
| medium (default) | 0.8 | all | off | on | 75 m |
| high | 1.0 | all | on | on | 90 m |
