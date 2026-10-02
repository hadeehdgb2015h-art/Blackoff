# shared/

Single source of truth read by **both** the Godot client and the Node server.

| File | Content |
|---|---|
| `constants.json` | simulation, zone, player, economy, progression, net and anti-cheat constants |
| `protocol.json`  | binary wire protocol: primitives, quantization, enums, message ids and field layouts |
| `weapons.json`   | weapon definitions (damage, fire rate, magazine, prices) |
| `zombies.json`   | zombie archetypes (health and speed scaling, attack, hit capsules, rewards) |
| `waves.json`     | infinite wave difficulty curve and archetype mix |

Rules
- Units: metres, seconds, radians on the wire. Gameplay JSON uses degrees only where the key ends in `Deg`.
- Every file carries `schemaVersion`. Bump it on breaking shape changes.
- The server validates every file at boot (`server/src/shared/`) and refuses to start on invalid data.
- The client gets a copy via `tools/sync_shared.sh` (run automatically by the export script and CI); never edit `client/shared/` by hand.
- Adding a weapon / zombie = adding an entry here; no code change should be required for pure stat variants.
