# Testing

| Level | Command | What it proves |
|---|---|---|
| Client unit/integration | `godot --headless --path client --script res://tests/run_tests.gd` | shared data, map collision, nav reachability, hit shapes, fire rate, reload, economy, wave formulas, alive cap, every script and scene compiles, bot clears ≥ 2 waves with average tick < 2 ms. Any engine/script error fails the test |
| Headless game | `BLACKOFF_BOT=1 godot --headless --path client res://scenes/game/game.tscn --fixed-fps 60 --quit-after 7200` | the full game scene runs 2 minutes with views, HUD and audio and no script errors |
| Browser (bot) | `SMOKE_DPR=0.5 SMOKE_EXPECT="[game] wave 1 started" node tools/smoke_web.cjs build/web shot.png "?autostart=1&bot=1" 45` | the real web export plays in Chromium |
| Browser (multi-touch) | `SMOKE_TOUCH=1 node tools/smoke_web.cjs build/web touch.png "?autostart=1&debug=1" 5` | real touch events: move stick + aim drag held together, then FIRE |
| Server | `cd server && npm test` | env, shared data and map schemas, health endpoint, websocket rules |
| Map sync | `tools/build_maps.sh --check` | `shared/maps` matches the committed scene |

URL flags (web): `?autostart=1` skips the menu, `?bot=1` lets the test bot play, `?debug=1` publishes `window.__blackoff` state. Outside the browser, use the env vars `BLACKOFF_AUTOSTART`, `BLACKOFF_BOT`.
