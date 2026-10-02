# Testing

| Level | Command | What it proves |
|---|---|---|
| Client unit/integration | `godot --headless --path client --script res://tests/run_tests.gd` | shared data, map collision, nav reachability, hit shapes, fire rate, reload, economy, wave formulas, alive cap, every script and scene compiles, bot clears ≥ 2 waves with average tick < 2 ms. Any engine/script error fails the test |
| Headless game | `BLACKOFF_BOT=1 godot --headless --path client res://scenes/game/game.tscn --fixed-fps 60 --quit-after 7200` | the full game scene runs 2 minutes with views, HUD and audio and no script errors |
| Browser (bot) | `SMOKE_DPR=0.5 SMOKE_EXPECT="[game] wave 1 started" node tools/smoke_web.cjs build/web shot.png "?autostart=1&bot=1" 45` | the real web export plays in Chromium |
| Browser (multi-touch) | `SMOKE_TOUCH=1 node tools/smoke_web.cjs build/web touch.png "?autostart=1&debug=1" 5` | real touch events: move stick + aim drag held together, then FIRE |
| Server | `cd server && npm test` | env and shared data schemas; the TypeScript sim (map, nav, hits, fire rate, reload, economy, waves, supply cache, bot clears waves); codec strictness; Telegram initData; full WebSocket flow (login, zone, input → movement, roster, resume, ping, rate limit, bad frames); zone perf budget |
| Golden contract | `npm run gen:golden && git diff --exit-code shared/tests`, plus `client/tests/test_golden.gd` | the server and the client sim agree on codec bytes, wave formulas, hit shapes, movement and raycasts |
| Load test | `cd server && npm run loadtest -- --local --bots 16 --seconds 30 --max-tick-ms 2` | 16 WebSocket bots over 4 zones, average tick under 2 ms |
| Map sync | `tools/build_maps.sh --check` | `shared/maps` matches the committed scene |
| Browser (cache) | `SMOKE_CACHE=1 node tools/smoke_web.cjs build/web "" "" 2` (CI); `SMOKE_CACHE_NEXT=<newer build dir>` | the service worker installs on the first visit; the second visit fetches no big file from the server, or, with a newer build, only the files whose hashed names changed |
| Voice (Node) | `cd server && npx vitest run test/voice.test.ts` | the browser codec (`client/web/voice.js`) under Node: 324-byte frames, > 20 dB SNR on a tone, every frame decodes alone; `bytes16`; relay to listening members only, mute, size and flood limits, `VOICE_CHAT=0` |
| Voice (browser) | server on 8798, `npx tsx tools/voiceBot.ts ws://127.0.0.1:8798/ws Talker 60 --expect-receive`, then `SMOKE_VOICE=1 node tools/smoke_web.cjs build/web voice.png "?autostart=1&voice=1&server=ws://127.0.0.1:8798/ws&name=WebVoice" 12` | Chromium with a fake microphone (a tone WAV) turns the mic on at join, encodes and sends frames, and plays the bot's frames; the bot hears and decodes the browser's frames |
| Layout | `test_layout.gd` | touch layout defaults, clamping, resolution of old/partial saved data, normalised positions across aspect ratios |
| Profiles (Postgres) | `TEST_DATABASE_URL=… npm test` (CI: postgres service) | migrations run once, profiles accumulate, best wave keeps the max, match records |
| Deploy rehearsal | CI job `release` (see `docs/systems/deploy.md`) | the real installer on a clean machine: nginx + pm2 + Postgres, Telegram-signed play through nginx, profile survives a restart, the web build opened as a Telegram Mini App joins online, update, uninstall |

URL flags (web): `?autostart=1` skips the menu, `?bot=1` lets the test bot play, `?debug=1` publishes `window.__blackoff` state. Outside the browser, use the env vars `BLACKOFF_AUTOSTART`, `BLACKOFF_BOT`.
