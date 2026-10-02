# Map pipeline

**Goal:** Godot is the authoring tool. Gameplay geometry is exported to `shared/maps/<id>.json`, which the client sim and the server both read, so collision and navigation always match.

## Flow
1. `client/tools/maps/build_facility_01.gd` (greybox generator) writes `client/scenes/maps/facility_01.tscn`. Retire it once art is placed in the scene; after that, edit the scene in the editor.
2. `client/tools/maps/export_map.gd` reads node groups in the scene and writes the JSON.
3. `tools/build_maps.sh` runs both. CI runs `tools/build_maps.sh --check`, which exports from the committed scene and fails if the JSON is stale.

## Scene conventions (node groups)
| Group | Node | Exported as |
|---|---|---|
| `map_floor` | MeshInstance3D box, top at y=0 | `walkable` rectangles |
| `map_wall` | MeshInstance3D box, axis-aligned | `walls` 3D AABBs. Boxes taller than `player.stepHeight` block movement; every box blocks bullets within its own height |
| `map_visual` | meshes | not exported (ceilings, panels) |
| `map_player_spawn` | Marker3D (rotation.y = yaw) | `playerSpawns` |
| `map_zombie_entry` | Marker3D, meta `entry_id`, `inside` | `zombieEntries` |
| `map_interact` | Marker3D, meta `interact_id`, `kind` (`weapon`/`ammo`), `item`, `radius` | `interactables` |
| `map_safe_area` | Marker3D, meta `min`, `max` | `safeArea` (spawn room; zombies never spawn inside, but they can enter) |
| `map_light` | lights | toggled by the quality settings |

Art props are `Marker3D` nodes in group `map_prop` (`prop` meta = mesh name in `env_props.glb`). Each one that blocks movement also gets a hidden wall AABB, so it is part of the exported collision. At runtime `MapDecor` instances the prop meshes, then `MapBatcher` merges all static meshes by (material, 12 m chunk), which gives about 120 draw calls and keeps each merged mesh under the 8-lights-per-object limit.

## facility_01
Safe room (5 spawns, ammo point, Ironhide machine) → two L-shaped corridors (west/east) → lab room (west, AR-7 wall-buy, Quickhand machine) and storage room (east, supply cache, Longstride machine) → outdoor yard (Switchblade machine). Units are metres. North is −Z.

**The old grounds (phase 10)**, south of the safe room through a new door, double the playable area (bounds now 66 × 73 m):
- **Cloister** (−16..16 × 18..32): a walled graveyard with grave rows, a black obelisk monument, dead trees, braziers, gothic lamps, a gibbet, ground mist and violet spores. Open air (moonlit layer, meta `outdoor`).
- **Crypt** (west, −30..−16): sarcophagi along the walls, candles, a rift over the aisle, veins on the walls. Zombie gate on its west wall.
- **Chapel** (east, 16..30): pews facing an altar stone, braziers, banners, the KS-12 shotgun wall-buy. Zombie gate on its east wall.
- **Catacomb** (−3..3 × 32..43): a candle-lit tunnel to the southern gate, with the VX-9 SMG wall-buy.
Seven zombie entries in all (two yard gates, two room windows, crypt gate, chapel gate, catacomb gate). Stone walls use the `stone_blocks` texture (`art/textures/build_textures.py`); doors in stone walls get a gothic arch. New props (`art/blender/build_dark_props.py`): Sarcophagus, Pew, Obelisk, Gibbet.
