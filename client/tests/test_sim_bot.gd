extends TestCase
## End-to-end: a bot plays the local sim. Guards against regressions in
## pathing, combat and waves, and measures the cost of a tick.


func test_bot_survives_waves() -> void:
	var w := SimWorld.new(defs(), "facility_01", 1234)
	var pid := w.add_player("bot")
	var bot := BotBrain.new(pid, 99)
	var p: SimPlayer = w.players[pid]
	p.weapons[0] = WeaponState.create("rifle", defs().weapons.rifle)
	p.weapons[0].reserve = 100000
	var cleared := 0
	var worst_ms := 0.0
	var total_ms := 0.0
	var ticks := 20 * 240
	for i in ticks:
		w.set_input(pid, bot.think(w))
		var t0 := Time.get_ticks_usec()
		w.step()
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		total_ms += ms
		worst_ms = maxf(worst_ms, ms)
		for e in w.events:
			if e.type == "wave_cleared":
				cleared += 1
		if w.zone_state == SimWorld.ZoneState.GAME_OVER:
			break
	print("    bot: waves cleared=%d kills=%d hp=%.0f state=%s avg tick=%.3f ms worst=%.2f ms" % [
		cleared, p.kills, p.hp, SimWorld.ZoneState.keys()[w.zone_state], total_ms / ticks, worst_ms])
	check(cleared >= 2, "bot clears at least 2 waves")
	check(p.kills >= 10, "bot kills zombies")
	check(total_ms / ticks < 2.0, "average tick under 2 ms (headless)")
