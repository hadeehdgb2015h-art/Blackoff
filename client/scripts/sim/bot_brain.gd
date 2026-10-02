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
	var target: SimZombie = null
	var best := INF
	for z in w.zombies.values():
		var d: float = p.pos.distance_squared_to(z.pos)
		if d >= best:
			continue
		var chest := Vector3(z.pos.x, float(z.def.headCenterHeight) - 0.35, z.pos.y)
		var to := chest - eye
		if w.map.raycast(eye, to.normalized(), to.length()) < to.length() - 0.05:
			continue
		best = d
		target = z
	var wp := p.weapon()
	if target:
		var aim := Vector3(target.pos.x, float(target.def.headCenterHeight) - 0.3, target.pos.y)
		var to := aim - eye
		var err := deg_to_rad(aim_error_deg)
		it.yaw = SimMath.yaw_to(p.pos, target.pos) + rng.randf_range(-err, err)
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
	if wp.mag == 0 and wp.reserve > 0 and not p.is_reloading():
		it.buttons |= PlayerIntent.RELOAD
	if wp.mag == 0 and wp.reserve == 0 and p.weapons.size() > 1:
		it.buttons |= PlayerIntent.SWITCH
	return it
