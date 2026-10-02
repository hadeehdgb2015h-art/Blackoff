# Server (phase 2)

`server/src/`, Node 22 + TypeScript. The server owns damage, health, ammo, currency, kills, waves, position and fire rate. Clients send only intents.

## Layout
| Path | Role |
|---|---|
| `sim/` | TypeScript port of `client/scripts/sim/`, rule for rule: `simWorld`, `playerSystem`, `zombieSystem`, `boxSystem`, `waveDirector`, `mapData`, `navGrid` (A*, same grid as `AStarGrid2D`), `hitTest`, `botBrain`. Adds `removePlayer()`. A seeded `Rng` (sfc32) is used instead of `Math.random()` |
| `net/codec.ts` | binary codec interpreted from `shared/protocol.json` (the client's `scripts/net/codec.gd` reads the same file) |
| `net/telegramAuth.ts` | Telegram `initData` HMAC-SHA256 check and `auth_date` age limit |
| `net/session.ts` | one WebSocket connection: hello → welcome → quickPlay → zoneJoined, then `input` / `buy` / `ping` / `leave` |
| `zone/zone.ts` | one zone: SimWorld + members, input merging, event → message translation, snapshots |
| `zone/zoneManager.ts` | quick-play matchmaking, the fixed-rate tick loop, zone lifecycle, tick stats |
| `app.ts` | HTTP `/healthz` (uptime, connections, zones, players, zombies, tick ms) and the `/ws` endpoint |

## Connection flow
1. `hello {protocolVersion, initData, resumeToken}`. A wrong version gets `error.badVersion` and the socket closes.
   - Identity comes from Telegram `initData`, checked with `TELEGRAM_BOT_TOKEN`.
   - With `ALLOW_DEV_AUTH=1` (refused in production), `initData = "dev:<name>"` or an empty string gives a test identity.
   - A valid `resumeToken` within `net.reconnectGraceSec` restores the same zone slot.
2. `welcome {playerId, displayName, resumeToken, tickRate}`.
3. `quickPlay` puts the player in the fullest joinable zone, or creates a new one. The server answers `zoneJoined {zoneId, mapId, entityId}`, then `roster` to everyone in the zone.
   - A zone is joinable when it is not over and has fewer than `zone.maxPlayers` members.
   - `zone.quickPlayJoinableUntilWave`: 0 means no wave limit, N stops joins after wave N.
4. Every tick (20 Hz) the server applies inputs and steps the zone. It sends:
   - an `event` for each sim event;
   - a `shot` for each shot (all players' tracers);
   - at 15 Hz, a `snapshot` and a `selfState` to each member.
5. One live connection per account. A newer login takes over the slot and closes the older socket (code 4000).

## Inputs
- Inputs arrive at about 20 Hz. The newest one sets move, aim and held buttons.
- Momentary bits (`firePressed`, `reload`, `interact`, `switch`, `revive`) are OR-ed until the next tick applies them once, so a tap is never lost and never repeated.
- `seq` is a wrapping u16; older inputs are ignored. Snapshots echo the last applied seq in `ackSeq`, which client prediction will use in phase 3.
- Validation:
  - move is clamped to length 1;
  - pitch is clamped to ±1.4 rad;
  - buttons are masked to the 6 defined bits;
  - every message is checked by the strict decoder (unknown id, short frame, trailing bytes, bad UTF-8).
- Malformed frames get `error.badMessage`; the socket closes on the fifth strike (code 4001).
- Rate limits are token buckets: `net.maxInputsPerSecond` for inputs, and 10/s with a burst of 20 for everything else. Extra messages are dropped and logged; a sustained flood closes the socket with `rateLimited`.
- `buy {itemId}` only works for the item the player can interact with right now. It goes through the same interact rules as the USE button.

## Snapshots and interest
- Each snapshot carries every player, plus the zombies within `net.interestRadius` of the receiving player, and a `removed` list of entities that left the set or died. These are full snapshots; delta compression against `ackSeq` is phase 3.
- `entityState.sub` holds the zombie type index for zombies and the held weapon index for players.
- `entityState.flags`: 1 moving, 2 attacking, 4 downed, 8 reloading.
- Index tables (sorted weapon ids, sorted zombie ids, box and entry order in the map) are defined in `protocol.json` → `indexTables`. Each event's meaning of a/b/value/flags is in `eventFields`.

## Lifecycle
- On disconnect, the player stays (idle) for `net.reconnectGraceSec`, then is removed.
- Empty zones close after `zone.emptyZoneTtlSec`.
- After game over, a zone lingers for 10 s (`GAME_OVER_LINGER_MS`) and then closes. Its members return to the lobby state and can quick-play again.
- The tick loop is drift-corrected: each tick is scheduled against the ideal timeline. After a stall of more than 5 ticks it skips ahead instead of fast-forwarding.

## Measured (cloud container, one core)
| Test | Result |
|---|---|
| `test/perf.test.ts`: 4 bots + 24 zombies in one zone, snapshots included | average tick well under the 2 ms budget |
| `npm run loadtest -- --local --bots 16 --seconds 30` | 4 zones, 16 players, 44 zombies: average tick 0.34 ms, worst 7 ms (GC); 2.1 KiB/s down per player; 15 snapshots/s |

## Running locally
```bash
cd server && npm ci
ALLOW_DEV_AUTH=1 npm run dev                     # ws://127.0.0.1:8787/ws, /healthz
npm run loadtest -- --bots 8 --seconds 20        # against the running server
npm test                                          # sim, codec, golden contract, auth, sessions, perf
npm run gen:golden                                # after an intended rule change, then fix the client
```
