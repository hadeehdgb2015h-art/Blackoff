class_name PowerupSystem
extends RefCounted
## Power-up drops (mirrored by server/src/sim/powerupSystem.ts): a killed zombie
## may leave a pickup; any alive player walking over it applies it to the whole
## zone. Timed ones (insta-kill, double points, fire sale) keep an end time;
## the others act at once (max ammo, nuke). Rolls use the world RNG.

class Powerup:
	var id: int
	var type: String
	var pos: Vector2
	var until: float

var w: SimWorld
var cfg: Dictionary
var drops := {}        ## id -> Powerup
var active := {}       ## type -> end time
var types: Array = []  ## sorted type ids (index table)
var _last_drop_time: float = -1e9


func _init(world: SimWorld) -> void:
	w = world
	cfg = w.constants.powerups
	types = cfg.types.keys()
	types.sort()


func is_active(type: String) -> bool:
	return active.has(type) and w.time < float(active[type])


## Whole seconds left of a timed power-up (0 when off).
func seconds_left(type: String) -> int:
	if not active.has(type):
		return 0
	return maxi(0, ceili(float(active[type]) - w.time))


## Called on every zombie kill; may drop a pickup at the death position.
func on_kill(pos: Vector2) -> void:
	if drops.size() >= int(cfg.maxOnGround) or w.time - _last_drop_time < float(cfg.minSecondsBetween):
		return
	if w.rng.randf() >= float(cfg.dropChance):
		return
	var type := _pick()
	if type == "":
		return
	_last_drop_time = w.time
	var d := Powerup.new()
	d.id = w.alloc_id()
	d.type = type
	d.pos = pos
	d.until = w.time + float(cfg.lifetimeSec)
	drops[d.id] = d
	w.emit({"type": "powerup_dropped", "id": d.id, "ptype": type, "pos": pos, "until": d.until})


func _pick() -> String:
	var total := 0.0
	for t in types:
		total += float(cfg.types[t].weight)
	if total <= 0.0:
		return ""
	var r := w.rng.randf() * total
	for t in types:
		r -= float(cfg.types[t].weight)
		if r < 0.0:
			return t
	return types[types.size() - 1]


func update() -> void:
	for d in drops.values().duplicate():
		if w.time >= d.until:
			drops.erase(d.id)
			w.emit({"type": "powerup_expired", "id": d.id})
			continue
		for p in w.players.values():
			if p.state != SimPlayer.State.ALIVE or p.pos.distance_to(d.pos) > float(cfg.pickupRadius):
				continue
			drops.erase(d.id)
			_apply(d.type, p.id)
			break
	for t in active.keys().duplicate():
		if w.time >= float(active[t]):
			active.erase(t)


func _apply(type: String, pid: int) -> void:
	var def: Dictionary = cfg.types[type]
	w.emit({"type": "powerup_taken", "pid": pid, "ptype": type})
	if float(def.durationSec) > 0.0:
		active[type] = w.time + float(def.durationSec)
	if type == "maxAmmo":
		for p in w.players.values():
			for wp in p.weapons:
				wp.mag = int(wp.def.magSize)
				wp.reserve = int(wp.def.reserveMax)
			if p.is_reloading():
				p.reload_end = 0.0
	elif type == "nuke":
		for z in w.zombies.values().duplicate():
			w.zombies.erase(z.id)
			w.director.killed += 1
			w.emit({"type": "zombie_killed", "zid": z.id, "pid": 0, "head": false, "ztype": z.type, "pos": z.pos, "yaw": z.yaw})
		for p in w.players.values():
			if p.is_alive():
				w.add_currency(p, int(def.get("reward", 0)), "nuke")
