extends TestCase


func test_wave_formulas() -> void:
	var c: Dictionary = defs().waves
	eq(WaveDirector.count_for(c, 1, 1), 7, "wave 1 solo count = round(6^1.08)")
	check(WaveDirector.count_for(c, 5, 4) > WaveDirector.count_for(c, 5, 1), "more players, more zombies")
	check(WaveDirector.count_for(c, 10, 1) > WaveDirector.count_for(c, 2, 1), "counts grow")
	check(WaveDirector.count_for(c, 10000, 8) <= int(c.count.max), "count capped")
	near(WaveDirector.spawn_interval_for(c, 1), 2.0, 0.001, "first interval")
	near(WaveDirector.spawn_interval_for(c, 999), float(c.spawnIntervalSec.min), 0.001, "interval floor")
	var walker: Dictionary = defs().zombies.walker
	near(WaveDirector.speed_for(walker, 999), float(walker.maxMoveSpeed), 0.001, "speed capped")
	var mix := WaveDirector.mix_for(c, 1)
	check(mix.has("walker") and not mix.has("runner"), "wave 1 walkers only")


func test_alive_cap_and_progression() -> void:
	var w := SimWorld.new(defs(), "facility_01", 7)
	var pid := w.add_player("t")
	w.players[pid].hp = 1e9  # invulnerable observer
	w.players[pid].max_hp = 1e9
	var max_alive := 0
	var waves_seen := 0
	for i in 20 * 90:
		w.set_input(pid, PlayerIntent.new())
		w.step()
		max_alive = maxi(max_alive, w.zombies.size())
		for e in w.events:
			if e.type == "wave_started":
				waves_seen += 1
	check(max_alive <= int(defs().constants.zone.maxAliveZombies), "alive cap respected")
	eq(waves_seen, 1, "wave 1 never clears without kills")
	check(w.director.spawned == w.director.to_spawn, "all of wave 1 spawned")


func test_boss_every_fifth_wave() -> void:
	var c: Dictionary = defs().waves
	eq(WaveDirector.bosses_for(c, 4), 0, "no boss on wave 4")
	eq(WaveDirector.bosses_for(c, 5), int(c.boss.count), "boss on wave 5")
	var w := SimWorld.new(defs(), "facility_01", 7)
	var pid := w.add_player("t")
	w.players[pid].hp = 1e9
	w.players[pid].max_hp = 1e9
	w.director.wave = 4
	w.director.phase_end = w.time
	w.set_input(pid, PlayerIntent.new())
	w.step()
	eq(w.director.wave, 5, "wave 5 started")
	for i in int(ceil(float(c.boss.delaySec) * 20.0)) + 2:
		w.set_input(pid, PlayerIntent.new())
		w.step()
	var boss: SimZombie = null
	for z in w.zombies.values():
		if z.type == str(c.boss.type):
			boss = z
	check(boss != null, "the Warden came after its delay")
	if boss:
		near(boss.max_hp, WaveDirector.health_for(defs().zombies[str(c.boss.type)], 5), 0.01, "solo boss health")
