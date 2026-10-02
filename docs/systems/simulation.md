# Simulation

`client/scripts/sim/` holds the authoritative rules, in plain RefCounted classes with no rendering. They run locally in solo practice. The phase 2 server re-implements the **same rules** in TypeScript, using the same `shared/*.json` and the same formulas, and the tests pin the contract.

| Script | Role |
|---|---|
| `sim_world.gd` | Zone at a fixed 20 Hz tick: players, zombies, wave director, event list |
| `player_system.gd` | Movement (circle vs walls), regen, fire/reload/switch, interactions (buy weapon, buy ammo) |
| `zombie_system.gd` | Spawning at entries, pathing (direct chase when in clear line, else grid A*), separation, wind-up melee, damage and rewards |
| `wave_director.gd` | Infinite waves from `waves.json` (count, interval, health and speed scaling, archetype mix) |
| `map_data.gd` | Collision and raycasts from the map JSON (bucketed) |
| `nav_grid.gd` | `AStarGrid2D` over walkable cells minus walls inflated by `maps.navAgentRadius` |
| `hit_test.gd` | Ray vs body cylinder plus head sphere |
| `player_intent.gd` | One tick of input. Bits match `protocol.json` `inputButtons` |
| `bot_brain.gd` | Scripted player for tests and load bots |

## Key rules
- Coordinates: sim plane = Godot (x, z). yaw = 0 faces −Z.
- Fire rate: shots are scheduled inside each tick window. A semi-auto weapon needs `FIRE_PRESSED`, a latched edge, so quick taps between ticks are never lost. Idle time never banks extra shots.
- Rewards: `economy.hitReward` per non-lethal hit; on a kill, the zombie's `killReward` plus `headshotKillBonus` for a head kill.
- Waves: count = round((base + perWave·(w−1))^exponent · (1 + perExtraPlayer·(players−1))), capped by `count.max`. At most `zone.maxAliveZombies` alive at once.
- Down → bleed out → dead. When nobody is alive, it is game over (revive arrives in phase 5).
- Views read state and per-tick `events` only. Nothing else writes to the sim except `set_input`.
