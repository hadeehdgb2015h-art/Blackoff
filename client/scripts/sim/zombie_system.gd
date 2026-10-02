class_name ZombieSystem
extends RefCounted
## Zombie spawning, pathing, separation, melee attacks and damage/rewards.

const DIRECT_CHASE_DIST := 10.0
const REPATH_SEC := 0.8
const REPATH_GOAL_DRIFT := 1.5
const TURN_RATE := 8.0  ## rad/s

var w: SimWorld


func _init(world: SimWorld) -> void:
	w = world


func spawn(type: String, wave_n: int) -> bool:
	var entries := w.map.zombie_entries.duplicate()
	entries.shuffle()
	var chosen: Dictionary = {}
	for pass_n in 2:
		for e in entries:
			if _blocked(e.pos, 0.9):
				continue
			if pass_n == 0 and _near_player(e.pos, 8.0):
				continue
			chosen = e
			break
		if not chosen.is_empty():
			break
	if chosen.is_empty():
		return false
	var def: Dictionary = w.defs.zombies[type]
	var z := SimZombie.new()
	z.id = w.alloc_id()
	z.type = type
	z.def = def
	z.pos = chosen.pos + Vector2(w.rng.randf_range(-0.3, 0.3), w.rng.randf_range(-0.3, 0.3))
	z.prev_pos = z.pos
	z.yaw = SimMath.yaw_to(chosen.pos, chosen.inside)
	z.max_hp = WaveDirector.health_for(def, wave_n)
	z.hp = z.max_hp
	z.speed = WaveDirector.speed_for(def, wave_n) * w.rng.randf_range(0.92, 1.08)
	z.next_repath_time = w.time + w.rng.randf_range(0.0, 0.3)
	z.stuck_check_time = w.time + 1.0
	z.stuck_check_pos = z.pos
	w.zombies[z.id] = z
	w.emit({"type": "zombie_spawned", "zid": z.id, "ztype": type, "entry": chosen.id})
	return true


func update_all() -> void:
	var targets := w.alive_players()
	for z in w.zombies.values():
		z.prev_pos = z.pos
		_update(z, targets)
	_separate()


func _update(z: SimZombie, targets: Array) -> void:
	z.moving = false
	var target: SimPlayer = null
	var best := INF
	for p in targets:
		var d: float = z.pos.distance_squared_to(p.pos)
		if d < best:
			best = d
			target = p
	if target == null:
		z.state = SimZombie.State.CHASE
		return
	z.target_id = target.id
	var dist := sqrt(best)
	var reach := float(z.def.attackRange) + float(w.constants.player.radius)
	if z.state == SimZombie.State.WINDUP:
		z.yaw = SimMath.approach_angle(z.yaw, SimMath.yaw_to(z.pos, target.pos), TURN_RATE * w.dt)
		if w.time >= z.windup_end:
			z.state = SimZombie.State.CHASE
			z.attack_ready_time = w.time + float(z.def.attackCooldownSec)
			if dist <= reach + 0.35:
				w.damage_player(target, float(z.def.attackDamage), z.id)
		return
	if dist <= reach and w.time >= z.attack_ready_time and w.map.segment_clear(z.pos, target.pos, 0.05):
		z.state = SimZombie.State.WINDUP
		z.windup_end = w.time + float(z.def.attackWindupSec)
		w.emit({"type": "zombie_attack", "zid": z.id, "pid": target.id})
		return
	if dist <= reach * 0.85:
		z.yaw = SimMath.approach_angle(z.yaw, SimMath.yaw_to(z.pos, target.pos), TURN_RATE * w.dt)
		return
	var goal := _steer_point(z, target.pos, dist)
	var to_goal := goal - z.pos
	if to_goal.length_squared() < 0.0001:
		return
	var step := to_goal.normalized() * minf(z.speed * w.dt, to_goal.length() + 0.2)
	z.pos = w.map.move_circle(z.pos, step, z.radius())
	z.moving = true
	z.yaw = SimMath.approach_angle(z.yaw, SimMath.yaw_to(z.prev_pos, z.prev_pos + step), TURN_RATE * w.dt)
	_check_stuck(z)


## Where to walk this tick: straight at the target when the way is clear,
## otherwise along the grid path, skipping corners already in clear line.
func _steer_point(z: SimZombie, target: Vector2, dist: float) -> Vector2:
	if dist < DIRECT_CHASE_DIST and w.map.segment_clear(z.pos, target, z.radius() * 0.9):
		z.path = PackedVector2Array()
		return target
	if z.path.is_empty() or w.time >= z.next_repath_time or z.path_goal.distance_to(target) > REPATH_GOAL_DRIFT:
		z.path = w.nav.find_path(z.pos, target)
		z.path_index = 0
		z.path_goal = target
		z.next_repath_time = w.time + REPATH_SEC + w.rng.randf_range(0.0, 0.3)
		if z.path.is_empty():
			return target
	while z.path_index < z.path.size() - 1 and z.pos.distance_to(z.path[z.path_index]) < 0.35:
		z.path_index += 1
	# One look-ahead check per tick keeps pathing cheap.
	if z.path_index < z.path.size() - 1 and w.map.segment_clear(z.pos, z.path[z.path_index + 1], z.radius() * 0.9):
		z.path_index += 1
	return z.path[z.path_index]


func _check_stuck(z: SimZombie) -> void:
	if w.time < z.stuck_check_time:
		return
	if z.pos.distance_to(z.stuck_check_pos) < 0.2:
		z.path = PackedVector2Array()  # force a fresh path next tick
	z.stuck_check_pos = z.pos
	z.stuck_check_time = w.time + 1.0


func _separate() -> void:
	var list: Array = w.zombies.values()
	for i in list.size():
		var a: SimZombie = list[i]
		for j in range(i + 1, list.size()):
			var b: SimZombie = list[j]
			var min_d := a.radius() + b.radius()
			var diff: Vector2 = a.pos - b.pos
			var d2 := diff.length_squared()
			if d2 >= min_d * min_d:
				continue
			var d := sqrt(d2)
			var n := diff / d if d > 0.0001 else Vector2(1, 0).rotated(float(a.id))
			var push := (min_d - d) * 0.5
			a.pos = w.map.resolve_circle(a.pos + n * push, a.radius())
			b.pos = w.map.resolve_circle(b.pos - n * push, b.radius())


## Keeps players and zombies from overlapping (zombies push players a little).
func separate_from_players() -> void:
	var pr := float(w.constants.player.radius)
	for p in w.players.values():
		if p.state == SimPlayer.State.DEAD:
			continue
		for z in w.zombies.values():
			var min_d: float = pr + z.radius()
			var diff: Vector2 = p.pos - z.pos
			var d := diff.length()
			if d >= min_d:
				continue
			var n := diff / d if d > 0.0001 else Vector2(0, 1)
			var push := min_d - d
			p.pos = w.map.resolve_circle(p.pos + n * push * 0.3, pr)
			z.pos = w.map.resolve_circle(z.pos - n * push * 0.7, z.radius())


func apply_damage(z: SimZombie, dmg: float, head: bool, by: SimPlayer, point: Vector3) -> void:
	z.hp -= dmg
	if w.powerups.is_active("instaKill"):
		z.hp = 0.0
	w.emit({"type": "zombie_hit", "zid": z.id, "pid": by.id, "damage": dmg, "head": head, "point": point})
	if z.hp > 0.0:
		w.add_currency(by, int(w.constants.economy.hitReward), "hit")
		return
	var reward := int(z.def.killReward) + (int(w.constants.economy.headshotKillBonus) if head else 0)
	by.kills += 1
	if head:
		by.headshots += 1
	w.add_currency(by, reward, "kill")
	w.zombies.erase(z.id)
	w.director.killed += 1
	w.emit({"type": "zombie_killed", "zid": z.id, "pid": by.id, "head": head, "ztype": z.type,
		"pos": z.pos, "yaw": z.yaw})
	w.powerups.on_kill(z.pos)


func _blocked(p: Vector2, r: float) -> bool:
	for z in w.zombies.values():
		if z.pos.distance_to(p) < r:
			return true
	return false


func _near_player(p: Vector2, r: float) -> bool:
	for pl in w.players.values():
		if pl.pos.distance_to(p) < r:
			return true
	return false
