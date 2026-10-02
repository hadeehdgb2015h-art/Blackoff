class_name BotBrain
extends RefCounted
## Simple scripted player used by automated tests, the browser smoke test
## (?bot=1) and, later, the server load-test bots. It only produces
## PlayerIntents, exactly like a human, so it exercises the real rules.

var pid: int
var rng := RandomNumberGenerator.new()
var aim_error_deg: float = 2.0
var _seq: int = 0
var _fire_toggle: bool = false
var _path: PackedVector2Array = []   ## infected bot: grid path to the nearest soldier
var _path_i: int = 0                  ## next waypoint (only ever advances between repaths)
var _repath_t: float = 0.0


func _init(player_id: int, seed: int = 1) -> void:
	pid = player_id
	rng.seed = seed


func think(w: SimWorld) -> PlayerIntent:
	var p: SimPlayer = w.players[pid]
	var it := PlayerIntent.new()
	_seq = (_seq + 1) % 65536
	it.seq = _seq
	it.yaw = p.yaw
	it.pitch = p.pitch
	if not p.is_alive():
		return it
	var eye := Vector3(p.pos.x, float(w.constants.player.eyeHeight), p.pos.y)
	# Infection, playing infected: run straight at the nearest soldier and claw.
	if p.team == 1:
		var prey: SimPlayer = null
		var pd := INF
		for o in w.players.values():
			if o == p or o.team != 0 or not o.is_alive():
				continue
			var d: float = p.pos.distance_squared_to(o.pos)
			if d < pd:
				pd = d
				prey = o
		if prey:
			# follow the nav grid (walls), straight at them when close
			if w.time >= _repath_t:
				_path = w.nav.find_path(p.pos, prey.pos)
				_path_i = 0
				_repath_t = w.time + 0.5
			var goal := prey.pos
			if sqrt(pd) > 3.0 and not _path.is_empty():
				while _path_i < _path.size() - 1 and p.pos.distance_to(_path[_path_i]) < 0.6:
					_path_i += 1  # reached this waypoint: aim at the next, never back
				goal = _path[_path_i]
			it.yaw = SimMath.yaw_to(p.pos, goal)
			it.move = Vector2(0, 1)
			if sqrt(pd) < 1.6:
				it.yaw = SimMath.yaw_to(p.pos, prey.pos)
				_fire_toggle = not _fire_toggle
				if _fire_toggle:
					it.buttons |= PlayerIntent.FIRE_PRESSED
		return it
	# Targets: AI zombies, plus infected players in infection mode.
	var target_pos := Vector2.ZERO
	var target_head := 0.0
	var found := false
	var best := INF
	var candidates: Array = []
	for z in w.zombies.values():
		candidates.append([z.pos, float(z.def.headCenterHeight)])
	for o in w.players.values():
		if o != p and o.team == 1 and o.is_alive():
			candidates.append([o.pos, float(w.constants.player.headCenterHeight)])
	for c in candidates:
		var cpos: Vector2 = c[0]
		var d: float = p.pos.distance_squared_to(cpos)
		if d >= best:
			continue
		var chest := Vector3(cpos.x, float(c[1]) - 0.35, cpos.y)
		var to := chest - eye
		if w.map.raycast(eye, to.normalized(), to.length()) < to.length() - 0.05:
			continue
		best = d
		target_pos = cpos
		target_head = float(c[1])
		found = true
	var wp := p.weapon()
	if found and wp:
		var aim := Vector3(target_pos.x, target_head - 0.3, target_pos.y)
		var to := aim - eye
		var err := deg_to_rad(aim_error_deg)
		it.yaw = SimMath.yaw_to(p.pos, target_pos) + rng.randf_range(-err, err)
		it.pitch = atan2(to.y, Vector2(to.x, to.z).length()) + rng.randf_range(-err, err)
		if wp.mag > 0:
			if wp.is_auto():
				it.buttons |= PlayerIntent.FIRE_HELD
			else:
				_fire_toggle = not _fire_toggle
				if _fire_toggle:
					it.buttons |= PlayerIntent.FIRE_PRESSED
		if sqrt(best) < 3.5:
			it.move = Vector2(0, -1)  # back off
	# A downed teammate in reach and no zombie close: revive them.
	if w.player_sys.revive_candidate(p) != null and (not found or sqrt(best) > 5.0):
		it.buttons = PlayerIntent.REVIVE
		it.move = Vector2.ZERO
		return it
	if wp == null:
		return it
	if wp.mag == 0 and wp.reserve > 0 and not p.is_reloading():
		it.buttons |= PlayerIntent.RELOAD
	if wp.mag == 0 and wp.reserve == 0 and p.weapons.size() > 1:
		it.buttons |= PlayerIntent.SWITCH
	return it
