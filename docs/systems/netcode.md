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
- Server URL: `?server=ws://…` first, then `window.BLACKOFF_CONFIG.server` from the site's optional `config.js` (written by the deploy updater), then `client/data/net.json`. `?name=` sets the dev name. The menu's QUICK PLAY ONLINE button is enabled only when a server is set, and outside Telegram (live server) it reads "open in Telegram".
- Inside Telegram the menu logs in at once and shows the player's stats (`welcome` carries games, kills, best wave; a `profile` message refreshes them after each match). Protocol version 5 (phase 11): `welcome`/`profile` add `tonMicro`, `weekKills`, `weekRank`, `tonPerKill`; new `leaderboard` request and reply. The HUD shows "+0.001 TON" per kill and a running total online only (display; the server owns the totals). Protocol version 4 (phase 8): snapshot entities of kind 2 are power-up drops (`sub` = type index); snapshot adds `instaKill`/`doublePoints`/`fireSale` seconds left; `selfState.perks` is a bitmask over the sorted perk ids; events `powerupDropped` (value = lifetime in 0.1 s), `powerupTaken`, `powerupExpired`; `purchase` flags 3 = perk (b = perk index). Protocol version 3: `selfState` adds `revive` (0–255 progress of the revive you are doing or receiving) and `bleedout` (seconds left while downed); entity flag 16 = being revived and 32 = dead; event `playerRespawned`; message `scoreboard` at game over. While holding REVIVE next to a downed teammate the client predicts no movement or shots, matching the server.

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

## Infection mode (phase 13)
Online only, no client sim mirror: `NetWorld` reads `mode` from `zoneJoined`, the infected flag (64) from player entities and bit 4 of `selfState.flags` for the local player, and the round, soldiers left and phase clock from the snapshot. Prediction moves an infected local player at `zombieSpeedMul` and never predicts shots for them (no weapon); the server's `zombieAttack` event (flag 1 = a player) swings the first-person claws (`FpRig.set_claws`, `on_claw`). Infected players are drawn as zombies (`ZombieView`, walker model) with a name tag; a fallen infected player disappears until `playerRespawned`. `BotBrain` plays both sides (soldiers also target infected players; an infected bot runs at the nearest soldier and claws). `?mode=infection` (or `BLACKOFF_MODE=infection` headless) with `?autostart=1` joins an infection zone.

## Invites (phase 19, protocol v8)
`welcome` carries the player's `inviteCode` (10 characters, an HMAC of the account id keyed from the bot token, so it survives restarts) and the bot's `botUsername` (`TELEGRAM_BOT_USERNAME`, else asked from Telegram's `getMe` at start). The invite link is `https://t.me/<bot>?startapp=sq<code>`; Telegram hands `sq<code>` to the Mini App as `start_param` (`?startapp=` in a plain browser, for tests). The menu sees it once per session and goes straight to online play with `quickPlay.friend` set. The server puts the player in the inviter's zone while the inviter is in a game with room and not over, whatever the wave and in the inviter's mode; otherwise ordinary quick play. `zoneJoined.friend` says how it went (0 no invite, 1 joined `friendName`, 2 could not), shown as a toast. Sharing (`Social`, `BlackoffTG.share`) opens Telegram's chat picker (`t.me/share/url`): INVITE FRIENDS in the menu's profile card and in the pause menu, CHALLENGE FRIENDS on the game-over panel (the wave and kills plus the same link). Tests: `server/test/invite.test.ts`; CI joins a browser to a Node host (`server/tools/inviteHost.ts`) through `?startapp=`.

## Voice chat (phase 12)
`client/web/voice.js` runs in the page: the microphone (`getUserMedia` with echo cancellation, noise suppression and auto gain) feeds an AudioWorklet that resamples to 16 kHz mono and cuts 40 ms frames; a voice gate (`constants.voice.vadThreshold`, hold of `vadHoldFrames`) drops silence; frames are IMA ADPCM (4 bits per sample, 4-byte state header so each frame decodes alone, 324 bytes, about 65 kbit/s while talking, nothing while quiet). `Net._pump_voice` takes the frames through `Platform.voice_take()` and sends `voice {seq, data}`; the server (`Session.onVoice`) checks only size and rate and `Zone.relayVoice` sends `voice {entityId, seq, data}` to every other connected member whose speaker is on (`voiceListen`). Incoming frames go to `BlackoffVoice.play`: decoded and scheduled on one short jitter buffer per speaker (`jitterMs`) through a speaker gain. The server never decodes audio; `VOICE_CHAT=0` switches the relay off and `welcome.voice` tells clients. The mic is off at every start (privacy); the speaker choice is in Settings. `?voice=1` turns the mic on at join for browser tests.

## Pause, retry, menu
- Pausing online keeps stepping with an idle input; the zone keeps running on the server.
- "Play again" after a game over sends `leave` + `quickPlay`. The server also moves a player out of a finished zone on `quickPlay`.
- Back to the menu sends `leave`.

## Tests
| Test | Where |
|---|---|
| Two headless Godot bots play the same zone on a real server (roster 2, wave 1 cleared, no script errors) | CI `client-web` → "Online end-to-end" |
| The web export joins the server from Chromium | same step (`?server=ws://127.0.0.1:8799/ws`) |
| Infection: lobby and countdown, round start with random infected, clock win, infected win, late joiners, claws (turn, cone, walls), bullets kill and respawn, speed; over the wire: matching by mode, flags, no TON | `server/test/infection.test.ts` |
| Infection end to end: two Godot bots join an infection zone, a round starts, one hunts the other | CI `client-web` → "Online end-to-end" |
| Voice: codec quality and independence of frames, `bytes16`, relay to listeners only, mute, size and flood limits, `VOICE_CHAT=0` | `server/test/voice.test.ts` |
| Voice end to end: Chromium with a fake microphone (tone WAV) sends frames and plays what `server/tools/voiceBot.ts` says; the bot hears the browser | CI `client-web` → "Online end-to-end" (`SMOKE_VOICE=1`) |
| Correction stats (`[net] rtt=… corrections=…`) are printed every 10 s | game log |

Not yet: delta-compressed snapshots (full snapshots cost about 2 KiB/s per player today) and lag compensation for hits. Both matter more on real mobile networks; they can be measured once the server is deployed (phase 4).
