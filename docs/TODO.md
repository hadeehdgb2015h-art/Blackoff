# TODO

## Phase 1: local client (feel)
- [ ] Greybox map per slice spec (safe area, 2 corridors, 2 rooms, yard, 4 zombie entries, weapon buy, ammo point)
- [ ] Map data exporter (Godot tool script → `shared/maps/<id>.json`: walls, floors, nav polygons, spawns, interactables)
- [ ] Player controller (third-person over-shoulder camera, collision)
- [ ] Touch controls: move stick, drag-to-aim, fire, reload, switch, interact, revive; settings for sensitivity and quality
- [ ] Weapons from `weapons.json` (pistol, rifle): fire rate, spread, mag/reserve, reload
- [ ] Zombies from `zombies.json` (walker, runner): local nav, attack, capsule + head hit test
- [ ] Waves from `waves.json`; local currency and buy points
- [ ] HUD: health, ammo, wave, currency
- [ ] Placeholder audio and hit feedback

## Phase 2: authoritative server
- [ ] Binary codec generated from `protocol.json` (TS + GDScript) with round-trip tests
- [ ] Zones, quick play matchmaking, zone lifecycle
- [ ] Server sim: 2D + floor movement, navmesh pathing, capsule/head hitscan, waves, economy
- [ ] Validation of every client action; bot client simulator for load tests

## Phase 3: sync
- [ ] Interpolation buffer, local prediction + reconciliation, delta snapshots, interest management, reconnect with resume token

## Phase 4: Telegram, DB, deploy
- [ ] initData HMAC validation, Postgres profiles + migrations, pm2 + nginx deploy via Actions, manual deploy script

## Phase 5: revive, buy, final HUD
## Phase 6: performance tiers + anti-cheat logging

## Open questions for the owner
- Hosting choice for preview links before phase 4 (see DEVELOPMENT_STATUS.md)
