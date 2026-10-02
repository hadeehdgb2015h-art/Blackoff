# Technical architecture

Status: decided in phase 0. Changes to anything here need a note in the decision log at the end.

## 1. Repository layout

```
client/            Godot 4.7 project (GDScript)
  scenes/          one folder per screen/feature (boot, menu, game, hud …)
  scripts/core/    autoloads: SharedData, Platform (later: Net, Settings, Profile)
  scripts/<system>/ gameplay systems, one folder each with a short README
  web/shell.html   custom HTML shell (Telegram bridge, loader, rotate overlay)
  tests/           headless GDScript tests (run_tests.gd)
  shared/          GENERATED copy of /shared (gitignored, tools/sync_shared.sh)
server/            Node 22 + TypeScript, ESM
  src/config/      env parsing (zod), all settings from environment
  src/shared/      shared JSON loader + schemas + cross-file checks
  src/net/         WebSocket transport + binary codec (phase 2)
  src/sim/         zone simulation (phase 2)
  test/            vitest
shared/            JSON source of truth for both sides (see shared/README.md)
tools/             setup_godot.sh, sync_shared.sh, export_web.sh, smoke_web.cjs
deploy/            .env.example, nginx/pm2 snippets (phase 4)
assets/incoming/   owner uploads waiting for licence review
docs/              this file, status, TODO, asset licences, docs/systems/*.md
```

## 2. Engine and client

| Decision | Choice | Why |
|---|---|---|
| Engine | Godot 4.7.2 stable (pinned in `tools/godot_version.env`) | latest stable at phase 0 |
| Renderer | Compatibility (WebGL 2) | the only renderer available on the Web |
| Web export | single-threaded (`variant/thread_support=false`), no GDExtension | runs without COOP/COEP headers, which Telegram's in-app browsers and shared hosts do not reliably send |
| Download size | engine wasm 38 MB raw, about 10 MB gzip; pck must stay under 12 MB compressed | target is under 25 MB initial download, so the server **must** serve gzip or brotli |
| Orientation | landscape (`window/handheld/orientation`), CSS rotate overlay in portrait, Telegram `requestFullscreen` + `lockOrientation` (Bot API 8.0+), browser Fullscreen API as fallback | |
| Language | GDScript, typed | |

Client structure rules:
- **Autoloads stay thin.** `SharedData` loads JSON; `Platform` is the only place that talks to JavaScript or Telegram. Later: `Net` (socket + codec), `Settings` (quality and sensitivity, saved in `user://`), `Session` (identity and profile from the server).
- **Data-driven.** Weapon, zombie and wave stats are never hard-coded; scenes take a definition id and read `SharedData`.
- **Presentation only in online mode.** In online play the client renders server state: interpolated remote entities, a predicted local player, and cosmetic effects. Damage, ammo, currency, kills, waves and position are decided by the server. The phase 1 offline mode runs the same gameplay rules locally so we can tune the feel before networking exists. The rules are written so they can be mirrored on the server from the same JSON.
- **Quality tiers** (phase 6): low, medium and high change resolution scale, shadows, fog, light count and draw distance. The first launch suggests a tier from a short frame-time probe; GPU names are usually masked by browsers (seen as `WebKit WebGL` on the owner's phone).

## 3. Server

- Node 22, TypeScript (strict), `ws` for WebSocket, `zod` for validation, `vitest` for tests, `pg` for Postgres (phase 4).
- One process hosts many **zones**. A zone holds up to `zone.maxPlayers` players (4, configurable up to `maxPlayersHardCap` 8) and at most `maxAliveZombies` (24) live zombies.
- Fixed tick of 20 Hz per zone, driven by one shared scheduler with drift correction. Snapshots go out at 15 Hz.
- **Simulation space**: a flat 2D plane (x, y) per floor, plus an integer floor index. World height is `floor * sim.floorHeight`. Stairs and ramps are portals between floors defined in the map data.
- **Map data**: Godot map scenes are exported by `client/tools/maps/export_map.gd` to `shared/maps/<mapId>.json`: axis-aligned wall boxes, walkable floor rectangles, spawns, zombie entries, buy/ammo points and the safe area (see `docs/systems/maps.md`). The server builds its navigation from this file, so both sides share one geometry.
- **Pathing**: a 0.5 m grid over walkable cells, with walls inflated by `maps.navAgentRadius`. A* runs on it with collinear compression, and zombies skip ahead along the path when the next corner is in clear line. They chase directly when the target is within 10 m and in clear line. Re-planning happens at most every 0.8 s or when the target drifts 1.5 m, plus separation steering. The client uses `AStarGrid2D`; the server runs the same grid A*.
- **Hits**: hitscan from the player's eye along the server-known aim (yaw and pitch from the input), checked against each target's vertical body capsule and a head sphere (radius and heights from `zombies.json` and `constants.player`). Damage multiplies by `headMultiplier` on a head hit. Light lag compensation rewinds targets to the client's interpolation time, capped at 200 ms.
- **Authority**: the client sends only intents (`input`: move vector, aim, buttons; `buy`: item id). The server owns damage, health, ammo, currency, kills, waves, position and fire rate. Inputs are rate-limited (`net.maxInputsPerSecond`) and every field is range-checked.
- **Anti-cheat** (phase 6): logs impossible speed, fire rate beyond `fireRateRpm` plus tolerance, ammo use with an empty magazine, and buys without funds. These are logged with player id and counters, and nobody is banned automatically (`anticheat.logOnly`).

## 4. Network protocol

- Binary WebSocket frames, little-endian, one message per frame: `u8 messageId` then the fields in the order declared in `shared/protocol.json`.
- Positions are quantized `i16` at 1/64 m (±512 m range). Yaw is `u16`, pitch is `i16`, health is `u8` as a percentage.
- Codecs are generated or interpreted from `protocol.json` on both sides (TypeScript and GDScript). A round-trip test in CI encodes every message on one side and decodes it on the other.
- **Snapshots**: delta against the last snapshot the client acknowledged (`ackSeq`), carrying only changed entities and a removed-ids list. A full snapshot is sent on join and resume.
- **Interest management**: entities beyond `net.interestRadius` or on non-adjacent floors are dropped from a client's snapshots. The player's own state always goes in `selfState`.
- **Client sync**: remote entities render about 100 ms behind (`clientInterpDelayMs`) with interpolation. The local player is predicted from its own inputs and reconciled against the server position for the matching `ackSeq`.
- **Reconnect**: `welcome` carries a `resumeToken`. Within `reconnectGraceSec` the player gets the same slot and state back.
- The protocol version is checked in `hello`. A mismatch returns `error.badVersion` and the client asks the user to reload.

## 5. Identity and data

- The client sends `Telegram.WebApp.initData` unchanged in `hello`. The server validates it with HMAC-SHA256: secret = HMAC_SHA256(key "WebAppData", bot token), then compares the hash over the sorted data-check-string and checks `auth_date` age. The client never decides identity.
- Outside Telegram (browser testing), identity is refused unless `ALLOW_DEV_AUTH=1`, which is blocked in production.
- Postgres tables (phase 4): `players` (account_id PK `tg:<id>`, name, games, kills, headshots, best_wave, play_seconds, created_at, last_seen) and `matches` (id, map, started_at, ended_at, wave, players, reason). Migrations are SQL in code (`server/src/db/pgStore.ts`), applied once each at server start under an advisory lock.
- Profile writes happen when a player leaves a zone (leave, reconnect grace expired, zone closed), never every tick. Without `DATABASE_URL` profiles live in memory.

## 6. Deployment (phase 4)

- Pull-based: CI publishes a tested release to the GitHub release `edge`; a pm2 app on the server (`blackoff-updater`) installs new versions, restarts **only** `blackoff` and rolls back on a failed health check. No SSH keys or server secrets live in GitHub.
- nginx: our own site file for our own subdomain (static client pre-gzipped, `application/wasm`, WebSocket proxy to `127.0.0.1:$PORT`). `nginx -t` runs before every reload; a rejected file is removed again.
- Domain, port, database URL and bot token live in `/opt/blackoff/.env` on the server. Nothing is hard-coded. Details: `docs/systems/deploy.md`.

## 7. Extensibility hooks (later expansions, not built now)

| Expansion | Where it plugs in |
|---|---|
| More weapons, melee | new entries in `weapons.json`; `fireMode` gains `melee`; hit resolver is pluggable by mode |
| Brute, spitter and boss zombies | `zombies.json` gains a `behavior` key mapped to server AI behaviour modules; projectile entity kind in `protocol.enums.entityKind` |
| Loot, power-ups | new entity kind plus `event` kinds; zone `pickups` system |
| Private rooms, invites | zone gets `visibility` and `code`; `quickPlay` becomes one of several join messages; Telegram `startapp` param carries the code |
| Admin panel | separate HTTP routes behind an admin token, reading the same DB |
| Extra maps | additional `shared/maps/*.json` plus client scenes; zones carry `mapId` |
| Achievements, cosmetics, Stars payments | DB tables + bot webhook; server-side purchase verification only |
| Multiple servers | zones are self-contained and the process is stateless apart from live zones, so a lobby or router can assign zone ids to servers later |

## 8. Performance budgets

- 60 FPS on strong phones, 30 FPS minimum. At most about 150 draw calls and about 150k visible triangles. Lighting is baked into lightmaps or vertex colours, with at most 4 dynamic lights visible. Shadows: one blob or decal per character, no real-time shadow maps on low.
- Server: one 20 Hz tick for a full zone (4 players, 24 zombies) should take under 2 ms on one core.

## Decision log

| Date | Decision |
|---|---|
| 2026-10-02 | Godot 4.7.2, Compatibility renderer, single-threaded Web export. |
| 2026-10-02 | Shared JSON copied into the client at build time instead of a symlink, which is not portable and is fragile in the Godot importer. |
| 2026-10-02 | zod validates the shared data and env on the server; the server refuses to start on invalid data. |
| 2026-10-02 | First-person camera: genre standard, and the aim ray equals the camera ray, so server hit checks match exactly. Teammates are visible as characters. |
| 2026-10-02 | Sim/view split: `client/scripts/sim` holds the rules (mirrored by the server), views only read state and events. Online mode swaps the world source, not the views. |
| 2026-10-02 | Walls are axis-aligned boxes (exporter enforces this). Navigation is a 0.5 m grid (`AStarGrid2D` on the client, an equivalent A* on the server) built from the exported map. |
| 2026-10-02 | Input bit 32 `firePressed` (latched edge) added so semi-auto taps shorter than a tick are never lost. |
| 2026-10-02 | Placeholder art, textures and sounds are generated in-repo (original, CC0). Real assets plug in via `client/data/visuals.json`. |
| 2026-10-02 | The claude.ai artifact host cannot be used for previews: its per-file limit is 15 MB and the engine wasm is 38 MB, so we did not work around it. Preview hosting is the owner's choice (see status). |
| 2026-10-02 | Phase 2 protocol additions (still version 1, nothing deployed yet): `entityState.sub`, `selfState` with every weapon slot, `event.flags`, the `shot` and `roster` messages, new event kinds, and `indexTables` / `eventFields` documenting the compact ids. |
| 2026-10-02 | Codecs interpret `protocol.json` at runtime on both sides instead of generating code; `shared/tests/golden.json` (generated by the server) keeps them identical. |
| 2026-10-02 | Server RNG is a seeded sfc32. The offline client sim keeps Godot's RNG, so rolls differ but the rules are identical (golden tests). |
| 2026-10-02 | `zone.quickPlayJoinableUntilWave = 0` means "no wave limit". Snapshots are full (players always, zombies within the interest radius); delta compression comes in phase 3. One live connection per account: a newer login takes over the slot. |
| 2026-10-02 | Phase 3: the server applies one buffered input per tick (max 4 queued) instead of the latest one, so client prediction (one movement step per input) replays exactly. Momentary buttons from dropped inputs are kept. |
| 2026-10-02 | Online mode subclasses SimWorld (`NetWorld`) instead of introducing an interface, so every view, the HUD and the test bot run unchanged online. |
| 2026-10-02 | Remote players hold the first-person weapon model hung at eye height; the soldier's arms are solved onto it with a two-bone IK at build time (no runtime IK on phones). |
| 2026-10-02 | Phase 4: deploy is pull-based (GitHub release `edge` + updater app under pm2) instead of push over SSH: no server credentials in GitHub, and the owner runs exactly one command. The server ships as one esbuild bundle (Node 20 target), so the host needs no `npm install`. |
| 2026-10-02 | Phase 13: infection mode as a second game mode of the same zone/sim (`GameMode`), server-only rules (`InfectionSystem`), matched by mode, no AI zombies; infected players reuse the zombie presentation; kills count but earn no TON. Protocol v7. |
| 2026-10-02 | Phase 12: voice chat. Audio is captured, gated and encoded in the page (`client/web/voice.js`, IMA ADPCM 16 kHz, 40 ms frames) and relayed by the server as opaque `bytes16` frames (protocol v6) to the other members of the zone; the server never decodes audio, the mic is always off at start, the speaker choice is saved. |
| 2026-10-02 | Phase 4: default address `blackoff.<ip>.sslip.io` so the owner needs no DNS change; their own subdomain is an installer option. Protocol v2 adds profile stats to `welcome` and a `profile` message after each match. |
