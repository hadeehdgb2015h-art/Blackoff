extends TestCase
## Revive and respawn rules (mirrored by server/test/sim.test.ts).


func _setup() -> Array:
	var w := SimWorld.new(defs(), "facility_01", 7)
	var a: SimPlayer = w.players[w.add_player("A")]
	var b: SimPlayer = w.players[w.add_player("B")]
	b.pos = a.pos + Vector2(1.0, 0.0)
	w.damage_player(b, 500.0, 0)
	return [w, a, b]


func _intent(buttons: int, move := Vector2.ZERO) -> PlayerIntent:
	var it := PlayerIntent.new()
	it.buttons = buttons
	it.move = move
	return it


func _need() -> int:
	return int(round(float(defs().constants.player.reviveTimeSec) * float(defs().constants.sim.tickRate)))


func test_revive_on_exact_tick_with_reward() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var a: SimPlayer = s[1]
	var b: SimPlayer = s[2]
	eq(b.downs, 1, "down counted")
	eq(str(w.interact_option(a.id).get("action", "")), "revive", "revive beats other interactions")
	var cash := a.currency
	var start := a.pos
	w.set_input(a.id, _intent(PlayerIntent.REVIVE | PlayerIntent.FIRE_HELD, Vector2(0, 1)))
	for i in _need() - 1:
		w.step()
	eq(b.state, SimPlayer.State.DOWNED, "not yet revived")
	check(w.reviver_of(b) == a, "A is the reviver")
	check(a.pos == start, "reviver stands still")
	eq(a.shots_fired, 0, "reviver does not shoot")
	w.step()
	eq(b.state, SimPlayer.State.ALIVE, "revived on the exact tick")
	near(b.hp, b.max_hp * 0.5, 0.001, "half health")
	eq(a.revives, 1, "revive counted")
	eq(a.currency, cash + int(defs().constants.economy.reviveReward), "revive reward")


func test_release_restarts_and_bleedout_pauses() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var a: SimPlayer = s[1]
	var b: SimPlayer = s[2]
	w.set_input(a.id, _intent(PlayerIntent.REVIVE))
	for i in 20:
		w.step()
	var left := w.bleedout_left(b)
	for i in 20:
		w.step()
	near(w.bleedout_left(b), left, 0.0001, "bleed-out paused while revived")
	w.set_input(a.id, _intent(0))
	w.step()
	eq(a.revive_ticks, 0, "letting go resets")
	w.set_input(a.id, _intent(PlayerIntent.REVIVE))
	for i in _need() - 1:
		w.step()
	b.pos = a.pos + Vector2(5.0, 0.0)
	w.step()
	eq(b.state, SimPlayer.State.DOWNED, "out of range: no revive")
	eq(a.revive_ticks, 0, "progress lost")


func test_dead_respawn_next_wave_and_game_over() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var a: SimPlayer = s[1]
	var b: SimPlayer = s[2]
	var rate := int(defs().constants.sim.tickRate)
	for i in (int(defs().constants.player.downedBleedoutSec) + 1) * rate:
		w.step()
	eq(b.state, SimPlayer.State.DEAD, "bled out")
	w.zombies.clear()
	w.director.spawned = w.director.to_spawn
	var respawned := false
	for i in 40 * rate:
		w.step()
		w.zombies.clear()
		for e in w.events:
			if e.type == "player_respawned" and e.pid == b.id:
				respawned = true
		if respawned:
			break
	check(respawned, "respawned at the next wave")
	eq(b.state, SimPlayer.State.ALIVE, "alive again")
	near(b.hp, b.max_hp, 0.001, "full health")
	w.damage_player(a, 500.0, 0)
	w.damage_player(b, 500.0, 0)
	w.step()
	eq(w.zone_state, SimWorld.ZoneState.GAME_OVER, "everyone down ends the game")
