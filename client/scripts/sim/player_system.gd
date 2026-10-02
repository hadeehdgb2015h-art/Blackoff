class_name PlayerSystem
extends RefCounted
## Player movement, health regen, weapons (fire/reload/switch),
## interactions (buy weapon, buy ammo) and reviving downed teammates.
## All checks are authoritative.

var w: SimWorld
var c_player: Dictionary
var c_econ: Dictionary


func _init(world: SimWorld) -> void:
	w = world
	c_player = w.constants.player
	c_econ = w.constants.economy


func update(p: SimPlayer) -> void:
	p.prev_pos = p.pos
	var inp := p.input
	var pressed := inp.buttons & ~p.buttons_prev
	p.buttons_prev = inp.buttons
	if not p.is_alive():
		p.moving = false
		p.revive_target = 0
		p.revive_ticks = 0
		return
	p.yaw = SimMath.wrap_angle(inp.yaw)
	p.pitch = clampf(inp.pitch, -1.4, 1.4)
	var reviving := _revive(p, inp)
	if reviving:
		p.moving = false
	else:
		_move(p, inp)
	_regen(p)
	if p.is_reloading() and w.time >= p.reload_end:
		p.weapon().finish_reload()
		p.reload_end = 0.0
		w.emit({"type": "reload_done", "pid": p.id})
	if reviving:
		return  # hands are busy: no switching, reloading, buying or firing
	if pressed & PlayerIntent.SWITCH:
		_switch(p)
	if pressed & PlayerIntent.RELOAD:
		_start_reload(p)
	if pressed & PlayerIntent.INTERACT:
		_interact(p)
	_fire(p, inp, (inp.buttons & PlayerIntent.FIRE_PRESSED) != 0)


## Nearest downed teammate within reviveRange, or null.
func revive_candidate(p: SimPlayer) -> SimPlayer:
	var best: SimPlayer = null
	var best_d := float(c_player.reviveRange)
	for o in w.players.values():
		if o == p or o.state != SimPlayer.State.DOWNED:
			continue
		var d: float = p.pos.distance_to(o.pos)
		if d <= best_d:
			best = o
			best_d = d
	return best


## Ticks a revive needs (counted in ticks so both sims finish on the same tick).
func revive_ticks_needed() -> int:
	return int(round(float(c_player.reviveTimeSec) / w.dt))


## Holding REVIVE next to a downed teammate revives them after reviveTimeSec.
## Returns true while reviving (the reviver stands still and cannot shoot).
func _revive(p: SimPlayer, inp: PlayerIntent) -> bool:
	var t: SimPlayer = revive_candidate(p) if inp.buttons & PlayerIntent.REVIVE else null
	if t == null:
		p.revive_target = 0
		p.revive_ticks = 0
		return false
	if p.revive_target != t.id:
		p.revive_target = t.id
		p.revive_ticks = 0
	p.revive_ticks += 1
	if p.revive_ticks >= revive_ticks_needed():
		t.state = SimPlayer.State.ALIVE
		t.hp = t.max_hp * 0.5
		t.last_damage_time = w.time
		p.revives += 1
		p.revive_target = 0
		p.revive_ticks = 0
		w.add_currency(p, int(c_econ.reviveReward), "revive")
		w.emit({"type": "player_revived", "pid": t.id, "by": p.id})
	return true


func _move(p: SimPlayer, inp: PlayerIntent) -> void:
	var mv := inp.move.limit_length(1.0)
	p.moving = mv.length_squared() > 0.01
	if not p.moving:
		return
	var dir := SimMath.right(p.yaw) * mv.x + SimMath.forward(p.yaw) * mv.y
	var delta := dir * float(c_player.moveSpeed) * w.dt
	p.pos = w.map.move_circle(p.pos, delta, float(c_player.radius))


func _regen(p: SimPlayer) -> void:
	if p.hp < p.max_hp and w.time - p.last_damage_time >= float(c_player.healthRegenDelaySec):
		p.hp = minf(p.max_hp, p.hp + float(c_player.healthRegenPerSec) * w.dt)


func _switch(p: SimPlayer) -> void:
	if p.weapons.size() < 2:
		return
	p.slot = (p.slot + 1) % p.weapons.size()
	p.reload_end = 0.0
	p.switch_end = w.time + float(c_player.weaponSwitchSec)
	w.emit({"type": "weapon_switched", "pid": p.id, "weapon": p.weapon().id})


func _start_reload(p: SimPlayer) -> bool:
	var wp := p.weapon()
	if wp == null or p.is_reloading() or w.time < p.switch_end or not wp.can_reload():
		return false
	p.reload_end = w.time + float(wp.def.reloadSec)
	w.emit({"type": "reload_started", "pid": p.id, "duration": float(wp.def.reloadSec)})
	return true


func _fire(p: SimPlayer, inp: PlayerIntent, pressed: bool) -> void:
	var wp := p.weapon()
	if wp == null:
		return
	var held := inp.has(PlayerIntent.FIRE_HELD) or pressed
	if not held or p.is_reloading() or w.time < p.switch_end:
		return
	if wp.mag <= 0:
		if not _start_reload(p) and pressed:
			w.emit({"type": "dry_fire", "pid": p.id})
		return
	if not wp.is_auto() and not pressed:
		return
	# Shots are scheduled inside this tick's window so fire rate is exact
	# at any tick rate; idle time never banks extra shots.
	var t := maxf(p.next_fire_time, w.time - w.dt)
	var shots := 0
	while t <= w.time and wp.mag > 0 and shots < 3:
		_shoot(p, wp, inp)
		shots += 1
		t += wp.interval()
		if not wp.is_auto():
			break
	if shots > 0:
		p.next_fire_time = t


func _shoot(p: SimPlayer, wp: WeaponState, inp: PlayerIntent) -> void:
	wp.mag -= 1
	p.shots_fired += 1
	var spread := deg_to_rad(float(wp.def.moveSpreadDeg if p.moving else wp.def.spreadDeg))
	var origin := Vector3(p.pos.x, float(c_player.eyeHeight), p.pos.y)
	var rng_max := float(wp.def.range)
	var pellets := maxi(1, int(wp.def.pellets))
	var ends: Array[Vector3] = []
	var hits := {}  ## zid -> {dmg, head, point}
	var any_wall := false
	for i in pellets:
		var ang := w.rng.randf() * spread
		var az := w.rng.randf() * TAU
		var yaw := inp.yaw + cos(az) * ang
		var pitch := clampf(inp.pitch + sin(az) * ang, -1.5, 1.5)
		var dir := SimMath.dir3(yaw, pitch)
		var best_t := w.map.raycast(origin, dir, rng_max)
		var hit_wall := best_t < rng_max
		var target: SimZombie = null
		var head := false
		for z in w.zombies.values():
			if z.pos.distance_squared_to(p.pos) > (rng_max + 1.0) * (rng_max + 1.0):
				continue
			var h := HitTest.ray_character(origin, dir, z.pos, z.radius(), float(z.def.headCenterHeight), float(z.def.headRadius))
			if not h.is_empty() and h.t < best_t:
				best_t = h.t
				target = z
				head = h.head
		var end := origin + dir * best_t
		ends.append(end)
		if target:
			var dmg := float(wp.def.damage) * (float(wp.def.headMultiplier) if head else 1.0)
			if not hits.has(target.id):
				hits[target.id] = {"z": target, "dmg": 0.0, "head": false, "point": end}
			hits[target.id].dmg += dmg
			hits[target.id].head = hits[target.id].head or head
		elif hit_wall:
			any_wall = true
	w.emit({"type": "shot", "pid": p.id, "weapon": wp.id, "from": origin, "to": ends[0], "ends": ends,
		"hit": "zombie" if not hits.is_empty() else ("wall" if any_wall else "none")})
	# One damage application per zombie per trigger pull (pellets are summed).
	for h in hits.values():
		if w.zombies.has(h.z.id):
			w.zombie_sys.apply_damage(h.z, h.dmg, h.head, p, h.point)


## Gives a weapon: refills it if owned, fills a free slot, else replaces the held one.
func give_weapon(p: SimPlayer, id: String) -> void:
	var owned := p.find_weapon(id)
	if owned >= 0:
		var ow: WeaponState = p.weapons[owned]
		ow.mag = int(ow.def.magSize)
		ow.reserve = int(ow.def.reserveMax)
		p.slot = owned
	else:
		var ws := WeaponState.create(id, w.defs.weapons[id])
		if p.weapons.size() < int(c_player.maxWeaponSlots):
			p.weapons.append(ws)
			p.slot = p.weapons.size() - 1
		else:
			p.weapons[p.slot] = ws
	p.reload_end = 0.0
	p.switch_end = w.time + float(c_player.weaponSwitchSec)


## Returns the interaction the player can do now, or {}:
## {id, kind, item, cost, label, available, reason}
func interact_option(p: SimPlayer) -> Dictionary:
	if not p.is_alive():
		return {}
	var downed := revive_candidate(p)
	if downed != null:
		return {"id": "revive", "kind": "revive", "item": "", "action": "revive", "cost": 0,
			"label": "Hold to revive " + downed.name, "full": false, "affordable": true, "target": downed.id}
	var best: Dictionary = {}
	var best_d := INF
	for it in w.map.interactables:
		var d: float = p.pos.distance_to(it.pos)
		if d <= minf(float(it.radius), float(c_player.interactRange) + 0.5) and d < best_d:
			best = it
			best_d = d
	if best.is_empty():
		return {}
	var opt := {"id": best.id, "kind": best.kind, "item": best.item}
	if best.kind == "box":
		opt.merge(w.box_sys.option(w.box_sys.boxes[best.id], p), true)
	elif best.kind == "weapon":
		var def: Dictionary = w.defs.weapons[best.item]
		var owned := p.find_weapon(best.item)
		if owned >= 0:
			opt.merge({"action": "ammo", "cost": int(def.ammoPrice), "label": "Ammo: " + def.displayName,
				"full": p.weapons[owned].reserve >= int(def.reserveMax)}, true)
		else:
			opt.merge({"action": "weapon", "cost": int(def.price), "label": def.displayName, "full": false}, true)
	else:
		var wp := p.weapon()
		opt.merge({"action": "ammo", "item": wp.id, "cost": int(wp.def.ammoPrice), "label": "Ammo: " + wp.def.displayName,
			"full": wp.reserve >= int(wp.def.reserveMax)}, true)
	opt["affordable"] = p.currency >= int(opt.cost) and not opt.get("busy", false)
	return opt


func _interact(p: SimPlayer) -> void:
	var opt := interact_option(p)
	if opt.is_empty() or opt.action == "revive":
		return
	if opt.full:
		w.emit({"type": "purchase_denied", "pid": p.id, "reason": "full"})
		return
	if opt.get("busy", false):
		return
	if not opt.affordable:
		w.emit({"type": "purchase_denied", "pid": p.id, "reason": "funds"})
		return
	var item: String = opt.item
	if opt.action == "box":
		var b = w.box_sys.boxes[opt.id]
		if not w.box_sys.open(b, p):
			w.emit({"type": "purchase_denied", "pid": p.id, "reason": "full"})
		return
	if opt.action == "take":
		w.box_sys.take(w.box_sys.boxes[opt.id], p)
		return
	if opt.action == "weapon":
		give_weapon(p, item)
	else:
		var wp: WeaponState = p.weapons[p.find_weapon(item)]
		wp.reserve = int(wp.def.reserveMax)
	w.add_currency(p, -int(opt.cost), "purchase")
	w.emit({"type": "purchase", "pid": p.id, "action": opt.action, "item": item, "cost": int(opt.cost)})
