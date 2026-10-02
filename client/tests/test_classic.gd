extends TestCase
## Phase 8 rules: power-up drops, perk machines, energy/wind weapons
## (mirrored by server/test/classic.test.ts).


func _world(seed: int = 5, drop_chance: float = -1.0) -> SimWorld:
	var d: Dictionary = defs().duplicate(true)  # private copy: tests tweak drop chances
	if drop_chance >= 0.0:
		d.constants.powerups.dropChance = drop_chance
	return SimWorld.new(d, "facility_01", seed)


func _zombie_at(w: SimWorld, x: float, y: float, hp: float = 50.0) -> SimZombie:
	var before := w.zombies.keys()
	w.zombie_sys.spawn("walker", 1)
	for z in w.zombies.values():
		if not before.has(z.id):
			z.pos = Vector2(x, y)
			z.hp = hp
			return z
	return null


func _intent(buttons: int, yaw := 0.0, pitch := 0.0) -> PlayerIntent:
	var it := PlayerIntent.new()
	it.buttons = buttons
	it.yaw = yaw
	it.pitch = pitch
	return it


func test_drop_and_pickup() -> void:
	var w := _world(5, 1.0)
	var a: SimPlayer = w.players[w.add_player("A")]
	var b: SimPlayer = w.players[w.add_player("B")]
	b.pos = a.pos + Vector2(3, 0)
	var z := _zombie_at(w, a.pos.x, a.pos.y - 2.0, 1.0)
	w.zombie_sys.apply_damage(z, 10.0, false, a, Vector3.ZERO)
	eq(w.powerups.drops.size(), 1, "a kill dropped a power-up")
	var drop = w.powerups.drops.values()[0]
	var z2 := _zombie_at(w, a.pos.x + 1.0, a.pos.y - 2.0, 1.0)
	w.zombie_sys.apply_damage(z2, 10.0, false, a, Vector3.ZERO)
	eq(w.powerups.drops.size(), 1, "cooldown: no second drop")
	b.pos = drop.pos
	w.step()
	eq(w.powerups.drops.size(), 0, "picked up")
	var taken := false
	for e in w.events:
		if e.type == "powerup_taken" and e.pid == b.id and e.ptype == drop.type:
			taken = true
	check(taken, "powerup_taken event for B")


func test_effects_of_each_powerup() -> void:
	var w := _world()
	var a: SimPlayer = w.players[w.add_player("A")]
	w.powerups._apply("instaKill", a.id)
	var z := _zombie_at(w, 0, 0, 500.0)
	w.zombie_sys.apply_damage(z, 1.0, false, a, Vector3.ZERO)
	check(not w.zombies.has(z.id), "insta-kill: any hit is lethal")
	var cash := a.currency
	w.powerups._apply("doublePoints", a.id)
	w.add_currency(a, 50, "hit")
	eq(a.currency, cash + 100, "double points")
	w.add_currency(a, -30, "purchase")
	eq(a.currency, cash + 70, "spending is not doubled")
	var wp := a.weapon()
	wp.mag = 1
	wp.reserve = 2
	w.powerups._apply("maxAmmo", a.id)
	eq(wp.mag, int(wp.def.magSize), "max ammo fills the magazine")
	eq(wp.reserve, int(wp.def.reserveMax), "max ammo fills the reserve")
	_zombie_at(w, 1, 1)
	_zombie_at(w, 2, 2)
	var before := a.currency
	w.powerups._apply("nuke", a.id)
	eq(w.zombies.size(), 0, "nuke clears the zone")
	eq(a.currency, before + 800, "nuke reward (doubled)")
	eq(a.kills, 1, "nuke kills are not credited")
	w.powerups._apply("fireSale", a.id)
	eq(w.box_sys.price(), 10, "fire sale price")
	for i in 31 * 20:
		w.step()
	eq(w.box_sys.price(), int(defs().constants.supplyBox.price), "fire sale over")
	check(not w.powerups.is_active("instaKill"), "insta-kill over")


func test_perk_machine() -> void:
	var w := _world()
	var a: SimPlayer = w.players[w.add_player("A")]
	for it in w.map.interactables:
		if it.id == "perk_ironhide":
			a.pos = it.pos
	a.currency = 10000
	var opt := w.interact_option(a.id)
	eq(str(opt.get("action", "")), "perk", "machine prompt")
	eq(int(opt.get("cost", 0)), 2500, "machine price")
	w.set_input(a.id, _intent(PlayerIntent.INTERACT))
	w.step()
	eq(a.perks.size(), 1, "one perk bought")
	eq(a.perks[0], "ironhide", "perk bought")
	eq(a.currency, 7500, "paid")
	near(a.max_hp, 160.0, 0.001, "more health")
	near(a.hp, 160.0, 0.001, "healed to the new max")
	check(w.interact_option(a.id).full, "owned: full")
	w.set_input(a.id, _intent(PlayerIntent.INTERACT))
	w.step()
	eq(a.currency, 7500, "not sold twice")
	for extra in ["quickhands", "longstride", "switchblade"]:
		a.perks.append(extra)
	near(w.player_sys.perk_mul(a, "reloadMul"), 0.5, 0.0001, "reload multiplier")
	near(w.player_sys.perk_mul(a, "moveSpeedMul"), 1.12, 0.0001, "speed multiplier")
	near(w.player_sys.perk_mul(a, "switchMul"), 0.4, 0.0001, "swap multiplier")
	var wp := a.weapon()
	wp.mag = 0
	w.set_input(a.id, _intent(PlayerIntent.RELOAD))
	w.step()
	near(a.reload_end - w.time, float(wp.def.reloadSec) * 0.5, 0.001, "faster reload")
	w.damage_player(a, 1000.0, 0)
	check(a.perks.is_empty(), "perks lost when downed")
	near(a.max_hp, 100.0, 0.001, "base health back")


func test_arc_splash_and_gale_cone() -> void:
	var w := _world()
	var a: SimPlayer = w.players[w.add_player("A")]
	a.pos = Vector2(0, -14)
	a.weapons[0] = WeaponState.create("arc", w.defs.weapons.arc)
	var direct := _zombie_at(w, 0, -20, 1000.0)
	var near_z := _zombie_at(w, 1.5, -20.5, 1000.0)
	var far_z := _zombie_at(w, 6, -20, 1000.0)
	w.set_input(a.id, _intent(PlayerIntent.FIRE_HELD | PlayerIntent.FIRE_PRESSED, 0.0, -0.02))
	w.step()
	check(direct.hp < 1000.0, "direct hit")
	near(near_z.hp, 880.0, 0.001, "splash damage next to the hit")
	near(far_z.hp, 1000.0, 0.001, "out of splash range")
	a.weapons[0] = WeaponState.create("gale", w.defs.weapons.gale)
	a.next_fire_time = 0.0
	var front := _zombie_at(w, 0.5, -19, 100.0)
	var side := _zombie_at(w, 5, -16, 100.0)
	var behind := _zombie_at(w, 0, -9, 100.0)
	w.set_input(a.id, _intent(PlayerIntent.FIRE_HELD | PlayerIntent.FIRE_PRESSED))
	w.step()
	check(not w.zombies.has(front.id), "cone kills in front")
	check(not w.zombies.has(near_z.id), "cone kills the second one in front too")
	near(side.hp, 100.0, 0.001, "outside the cone")
	near(behind.hp, 100.0, 0.001, "behind")
