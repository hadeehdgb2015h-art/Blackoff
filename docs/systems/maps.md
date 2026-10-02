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

At runtime `MapBatcher` merges all static meshes by material (about 10 draw calls).

## facility_01 (slice map)
Safe room (spawn, ammo point) → two L-shaped corridors (west/east) → lab room (west, AR-7 wall-buy) and storage room (east) → outdoor yard. Four zombie entries: two yard gates, two room windows. Units are metres. North is −Z.
