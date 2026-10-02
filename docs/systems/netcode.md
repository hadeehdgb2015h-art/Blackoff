# Netcode (phase 3: client sync)

The client plays online through the same game scene as offline practice. Only the world source changes:

| Offline | Online |
|---|---|
| `SimWorld` (local rules) | `NetWorld` (`client/scripts/net/net_world.gd`), a `SimWorld` subclass fed by the server |

`NetWorld` keeps SimWorld's read API (`players`, `zombies`, `director`, `zone_state`, `events`, `box_sys`, `interact_option`), so the views, HUD and bot work unchanged.

## Pieces
- `scripts/core/net.gd` (autoload `Net`): `WebSocketPeer` + `NetCodec`.
  - It sends hello with the Telegram initData. Outside Telegram it sends `dev:<name>`, which only dev servers accept.
  - It follows welcome → quickPlay → zoneJoined, pings every 2 s (RTT), and retries with the resume token for `net.reconnectGraceSec`.
  - Messages that arrive during a scene change are buffered.
- `scripts/net/net_world.gd`: replica, prediction, interpolation, and event translation (protocol event kinds → the sim's event dictionaries).
- `scripts/view/remote_player_view.gd`: other players.
  - Model: the operator `soldier.glb` with `idle_<hold>` / `run_<hold>` / `downed`, where the hold is long, smg or pistol depending on the weapon. The run speed follows the measured speed.
  - The held weapon is the first-person model placed per hold class (`visuals.json` → `players.soldier.holds`), and the arms are solved onto it at build time.
  - A name tag shows above the head.
- Server URL: `client/data/net.json` → `server` (set at deploy time). `?server=ws://…` overrides it, and `?name=` sets the dev name. The menu's QUICK PLAY ONLINE button is enabled only when a server is set.

## Local player: prediction and reconciliation
1. Every local tick (20 Hz) the input is quantized exactly like the wire format (move i8/127, yaw u16, pitch i16) and sent with a wrapping `seq`.
2. The same movement rules (`MapData.move_circle`, speed, radius) run immediately, so walking has no latency. Shots are shown at once as well: muzzle flash, sound, recoil and a tracer to the wall or zombie in the aim line. Damage is never predicted.
3. The server buffers inputs and applies exactly one per tick (up to 4 queued; momentary buttons are never lost). Each snapshot carries `ackSeq`, the last input applied.
4. On every snapshot the client takes its server position, drops the inputs up to `ackSeq`, and replays the rest.
   - A difference under 2 m is blended in (35 % per tick); a larger one snaps.
   - Magazine counts are the server's, minus the shots predicted after `ackSeq`.
5. Measured in the CI end-to-end run (2 bots, waves 1–3): **0 corrections** above 5 cm. Prediction matches the server exactly.

## Remote entities: interpolation
- Snapshots (15 Hz) are buffered with their server tick. Remote players and zombies render `INTERP_TICKS` = 2 ticks (100 ms) behind the newest snapshot, interpolated between the two snapshots around that time. The render clock nudges toward its target, so it never drifts.
- A zombie killed by an event stays dead even though older snapshots still list it (a 3 s dead list).
- Other players' shots arrive as `shot` messages and are drawn as tracers from the shooter.

## Pause, retry, menu
- Pausing online keeps stepping with an idle input; the zone keeps running on the server.
- "Play again" after a game over sends `leave` + `quickPlay`. The server also moves a player out of a finished zone on `quickPlay`.
- Back to the menu sends `leave`.

## Tests
| Test | Where |
|---|---|
| Two headless Godot bots play the same zone on a real server (roster 2, wave 1 cleared, no script errors) | CI `client-web` → "Online end-to-end" |
| The web export joins the server from Chromium | same step (`?server=ws://127.0.0.1:8799/ws`) |
| Correction stats (`[net] rtt=… corrections=…`) are printed every 10 s | game log |

Not yet: delta-compressed snapshots (full snapshots cost about 2 KiB/s per player today) and lag compensation for hits. Both matter more on real mobile networks; they can be measured once the server is deployed (phase 4).
