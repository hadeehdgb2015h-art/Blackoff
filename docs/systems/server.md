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
| `app.ts` | HTTP `/healthz` (uptime, connections, store, zones, players, zombies, tick ms) and the `/ws` endpoint |
| `db/profileStore.ts`, `db/pgStore.ts` | player profiles: memory store, or Postgres with in-code migrations. Each player's match result (kills, headshots, wave, seconds) is written when they leave a zone; the session then gets a `profile` message. `welcome` carries games, kills and best wave |
| `anticheat.ts` | statistical flags at the end of a zone (hit rate, head-shot rate, kills per minute over `constants.anticheat` thresholds); logged with the account, counted as `suspicion` in the profile, never an automatic ban |
| `tools/bundle.mjs` | one-file deploy bundle (`npm run bundle` → `dist-bundle/server.mjs`); see `docs/systems/deploy.md` |

## Weekly hunt (TON points, phase 11)
Every kill in an online zone earns `TON_MICRO_PER_KILL` points (millionths of a TON, default 1000 = 0.001). The zone reports each member's kills, shots and hits when they leave; the hub turns that into TON points and anti-cheat flags and writes the profile plus a `weekly_scores` row (ISO week, Monday 00:00 UTC). `welcome`/`profile` carry `tonMicro`, `weekKills`, `weekRank`, `tonPerKill`; the `leaderboard` request answers with the week's top 10 and the player's standing. The owner reads `/admin/leaderboard?token=ADMIN_TOKEN` (account ids such as `tg:12345`, to pay the prize by hand) and `/admin/suspects?token=…` before paying. Nothing is paid automatically and the client never decides a number.

## Infection mode (phase 13)
`quickPlay {mode}` (0 zombies, 1 infection) picks or creates a zone of that mode (`constants.infection.maxPlayers` 10). `SimWorld` with `GameMode.INFECTION` runs `InfectionSystem` instead of the wave director, zombies, boxes and power-ups: LOBBY until `minPlayers`, a countdown (`lobbySec`, `lobbyFullSec` when full), then rounds (`roundSec`) in zone state WAVE with `ceil(players / playersPerFirstInfected)` infected picked at random; soldiers carry `soldierWeapons`, the infected have claws (`zombieAttackDamage` inside `zombieAttackRange` and `zombieAttackConeDeg`, every `zombieAttackCooldownSec`), `zombieHealth` and `zombieSpeedMul`. A soldier at zero health turns infected where they stand (`infected` event, the attacker gets the kill); an infected player at zero health is DEAD for `zombieRespawnSec` and comes back at the zombie entry farthest from the soldiers (`playerKilled`, `playerRespawned`). The round ends when no soldier is alive (infected win) or on the clock (soldiers win), then INTERMISSION for `resultSec` and the next round, or LOBBY again when fewer than `minPlayers` remain. Late joiners during a round come in infected. Snapshots carry the round in `wave`, soldiers alive in `remaining` and the phase clock in `timer`; player entities on the infected side carry `entityFlags.zombie`, the local player's `selfState.flags` bit 4. Results of infection zones carry `mode` and earn no TON.

## Voice relay (phase 12)
`voice` frames (C2S, `bytes16` payload) are relayed by `Zone.relayVoice` to the other connected members whose `voiceListen` is on, as S2C `voice {entityId, seq, data}`. Checks: in a zone, 1..`constants.voice.maxFrameBytes` bytes, `maxFramesPerSecond` with a burst of two seconds (a flood is thinned, never a strike or a disconnect). `VOICE_CHAT=0` turns the relay off (`welcome.voice = false`). The server never decodes audio.

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
npm test                                          # sim, codec, golden contract, auth, sessions, perf, profiles
TEST_DATABASE_URL=postgres://u:p@127.0.0.1/db npm test   # also the Postgres store (CI does this)
npm run gen:golden                                # after an intended rule change, then fix the client
```

## Telegram bot and owner panel (phase 20)
`src/bot/telegramBot.ts` long-polls Telegram (`getUpdates`; it deletes any webhook at start, so nginx is untouched) when `TELEGRAM_BOT_TOKEN` is set and `BOT_POLLING` is not 0 (never under tests). Players get Arabic replies: /start (welcome, a Play button opening `https://BLACKOFF_DOMAIN/` as a Web App, invite, stats, weekly top, how to play), /stats, /top, /invite, /help; the command menu is set with `setMyCommands`. A rejected token (401/404) makes it stop quietly.

Owners are the Telegram ids in `ADMIN_TELEGRAM_IDS` (the release's `deploy/owner.env` supplies it when `.env` does not: `applyDefaultsFile`). /admin opens a panel of buttons: live zones (mode, wave, players), memory and tick time; player counts; weekly top; anti-cheat suspects; a message to every player (`telegramIds`, 40 ms apart); find, ban (kicks and refuses login) and unban; TON per kill and a x2 event; give or take TON; the prize text; maintenance (no new games except for owners, with a message); the last warnings (`recentProblems`); restart (exit, pm2 starts it again). A button that needs a value asks for it and takes the owner's next message (5 minutes). The switches live in `RuntimeSettings`, stored in the `settings` table (migration 3; memory without Postgres).

## Owner dev powers (phase 20)
`welcome.dev` is true for owners; the game then shows a DEV button in online zombie games (`client/scripts/ui/dev_panel.gd`). It sends `dev {cmd, arg}` (protocol v9); `Session.onDev` strikes anyone else and applies `src/admin/devPowers.ts` to the live zone: god mode (no damage), infinite ammo, +10,000 credits, full heal, skip the wave, kill every zombie, summon the Warden, jump to wave 5, 10 or 25. Tests: `test/dev.test.ts`, `test/bot.test.ts` (a fake Telegram API).

