extends TestCase


func _setup() -> Array:
	var w := SimWorld.new(defs(), "facility_01", 5)
	var pid := w.add_player("t")
	var p: SimPlayer = w.players[pid]
	var b = w.box_sys.boxes.values()[0]
	p.pos = b.pos
	return [w, p, b]


func _press(w: SimWorld, p: SimPlayer, bits: int) -> void:
	var it := PlayerIntent.new()
	it.buttons = bits
	w.set_input(p.id, it)
	w.step()
	w.set_input(p.id, PlayerIntent.new())
	w.step()


func test_box_roll_offer_take() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var p: SimPlayer = s[1]
	var b = s[2]
	var price := int(defs().constants.supplyBox.price)
	p.currency = price - 1
	_press(w, p, PlayerIntent.INTERACT)
	eq(b.state, BoxSystem.State.IDLE, "cannot open without funds")
	p.currency = price + 100
	_press(w, p, PlayerIntent.INTERACT)
	eq(b.state, BoxSystem.State.ROLLING, "box rolling")
	eq(p.currency, 100, "price charged")
	check(defs().weapons[b.result].boxWeight > 0, "result comes from the box pool")
	check(p.find_weapon(b.result) < 0, "result is not already owned")
	_press(w, p, PlayerIntent.INTERACT)
	eq(b.state, BoxSystem.State.ROLLING, "interact while rolling does nothing")
	for i in int(defs().constants.supplyBox.rollSec * 20) + 1:
		w.step()
	eq(b.state, BoxSystem.State.OFFER, "offer after roll")
	var result: String = b.result
	_press(w, p, PlayerIntent.INTERACT)
	eq(b.state, BoxSystem.State.IDLE, "box closed after take")
	eq(p.weapon().id, result, "rolled weapon equipped")


func test_box_offer_expires() -> void:
	var s := _setup()
	var w: SimWorld = s[0]
	var p: SimPlayer = s[1]
	var b = s[2]
	p.currency = 5000
	_press(w, p, PlayerIntent.INTERACT)
	var c: Dictionary = defs().constants.supplyBox
	for i in int((c.rollSec + c.offerSec) * 20) + 2:
		w.step()
	eq(b.state, BoxSystem.State.IDLE, "offer expired")
	eq(p.weapons.size(), 1, "nothing taken")


func test_box_distribution_follows_weights() -> void:
	var w := SimWorld.new(defs(), "facility_01", 9)
	var p: SimPlayer = w.players[w.add_player("t")]
	var counts := {}
	for i in 3000:
		var r := w.box_sys.roll(p)
		counts[r] = counts.get(r, 0) + 1
	check(not counts.has("pistol"), "owned / zero-weight weapons never rolled")
	var total := 0.0
	for id in defs().weapons:
		if p.find_weapon(id) < 0:
			total += float(defs().weapons[id].boxWeight)
	for id in counts:
		var expected := float(defs().weapons[id].boxWeight) / total
		near(counts[id] / 3000.0, expected, 0.05, "share of " + id)


func test_shotgun_pellets_sum_damage() -> void:
	var w := SimWorld.new(defs(), "facility_01", 3)
	var p: SimPlayer = w.players[w.add_player("t")]
	p.weapons[0] = WeaponState.create("shotgun", defs().weapons.shotgun)
	w.zombie_sys.spawn("walker", 50)
	var z: SimZombie = w.zombies.values()[0]
	z.pos = p.pos + Vector2(0, -2.5)
	var hp0 := z.hp
	var it := PlayerIntent.new()
	it.buttons = PlayerIntent.FIRE_PRESSED | PlayerIntent.FIRE_HELD
	it.pitch = atan2(1.2 - 1.6, 2.5)
	w.set_input(p.id, it)
	w.step()
	var hits := 0
	for e in w.events:
		if e.type == "zombie_hit":
			hits += 1
		if e.type == "shot":
			eq(e.ends.size(), int(defs().weapons.shotgun.pellets), "one end point per pellet")
	eq(hits, 1, "one hit event per zombie per trigger pull")
	check(hp0 - z.hp > float(defs().weapons.shotgun.damage) * 3, "several pellets landed at close range")
