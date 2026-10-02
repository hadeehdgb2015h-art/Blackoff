extends TestCase


func _world() -> SimWorld:
	return SimWorld.new(defs(), "facility_01", 42)


func test_head_and_body_hits() -> void:
	var o := Vector3(0, 1.6, 0)
	var h := HitTest.ray_character(o, Vector3(0, 0, -1), Vector2(0, -5), 0.35, 1.62, 0.16)
	check(not h.is_empty() and h.head, "level shot hits head")
	var dir := (Vector3(0, 1.0, -5) - o).normalized()
	var b := HitTest.ray_character(o, dir, Vector2(0, -5), 0.35, 1.62, 0.16)
	check(not b.is_empty() and not b.head, "chest shot hits body")
	var miss := HitTest.ray_character(o, Vector3(1, 0, -1).normalized(), Vector2(0, -5), 0.35, 1.62, 0.16)
	check(miss.is_empty(), "wide shot misses")


func test_fire_rate_is_capped() -> void:
	var w := _world()
	var pid := w.add_player("t")
	var p: SimPlayer = w.players[pid]
	p.weapons[0] = WeaponState.create("rifle", defs().weapons.rifle)
	var it := PlayerIntent.new()
	it.buttons = PlayerIntent.FIRE_HELD
	it.pitch = 0.3
	for i in 40:  # two seconds: shots at t = 0.0, 0.1, ... 2.0
		w.set_input(pid, it)
		w.step()
	eq(p.shots_fired, 21, "rifle at 600 rpm: 10 shots per second, no burst catch-up")
	eq(p.weapons[0].mag, 30 - 21, "magazine decremented")


func test_semi_needs_presses() -> void:
	var w := _world()
	var pid := w.add_player("t")
	var p: SimPlayer = w.players[pid]
	var held := PlayerIntent.new()
	held.buttons = PlayerIntent.FIRE_HELD | PlayerIntent.FIRE_PRESSED
	w.set_input(pid, held)
	w.step()
	var hold_only := PlayerIntent.new()
	hold_only.buttons = PlayerIntent.FIRE_HELD
	for i in 10:
		w.set_input(pid, hold_only)
		w.step()
	eq(p.shots_fired, 1, "holding a semi-auto fires once")


func test_reload_moves_reserve() -> void:
	var w := _world()
	var pid := w.add_player("t")
	var p: SimPlayer = w.players[pid]
	var wp := p.weapon()
	wp.mag = 2
	var r := PlayerIntent.new()
	r.buttons = PlayerIntent.RELOAD
	w.set_input(pid, r)
	w.step()
	check(p.is_reloading(), "reload started")
	w.set_input(pid, PlayerIntent.new())
	for i in int(ceil(float(wp.def.reloadSec) * 20)) + 1:
		w.step()
	eq(wp.mag, int(wp.def.magSize), "mag full")
	eq(wp.reserve, int(wp.def.reserveStart) - (int(wp.def.magSize) - 2), "reserve reduced")


func test_kill_rewards_currency() -> void:
	var w := _world()
	var pid := w.add_player("t")
	var p: SimPlayer = w.players[pid]
	var start := p.currency
	check(w.zombie_sys.spawn("walker", 1), "spawned")
	var z: SimZombie = w.zombies.values()[0]
	z.pos = p.pos + Vector2(0, -4)
	z.hp = 1
	var it := PlayerIntent.new()
	it.buttons = PlayerIntent.FIRE_PRESSED | PlayerIntent.FIRE_HELD
	it.pitch = atan2(1.62 - 1.6, 4.0)
	w.set_input(pid, it)
	w.step()
	check(w.zombies.is_empty(), "zombie killed")
	eq(p.kills, 1, "kill counted")
	check(p.currency > start, "currency awarded")


func test_buy_rifle_and_ammo() -> void:
	var w := _world()
	var pid := w.add_player("t")
	var p: SimPlayer = w.players[pid]
	var buy: Dictionary = {}
	for it in w.map.interactables:
		if it.kind == "weapon":
			buy = it
	p.pos = buy.pos
	var press := PlayerIntent.new()
	press.buttons = PlayerIntent.INTERACT
	w.set_input(pid, press)
	w.step()
	eq(p.weapons.size(), 1, "cannot afford rifle with start money")
	p.currency = 5000
	w.set_input(pid, PlayerIntent.new())
	w.step()
	w.set_input(pid, press)
	w.step()
	eq(p.weapons.size(), 2, "rifle bought")
	eq(p.weapon().id, "rifle", "rifle equipped")
	eq(p.currency, 5000 - int(defs().weapons.rifle.price), "price charged")
	p.weapon().reserve = 0
	w.set_input(pid, PlayerIntent.new())
	w.step()
	w.set_input(pid, press)
	w.step()
	eq(p.weapon().reserve, int(defs().weapons.rifle.reserveMax), "ammo refilled at wall-buy")
