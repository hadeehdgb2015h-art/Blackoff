class_name BoxSystem
extends RefCounted
## Supply cache: pay, wait for the roll, then take a random weapon.
## The roll result is decided by the authoritative sim when the box opens;
## clients only learn it from `box_offer` (they animate a cosmetic shuffle).
## Weights: weapons.<id>.boxWeight. Weapons the buyer already owns are excluded.

enum State { IDLE, ROLLING, OFFER }

class Box:
	var id: String
	var pos: Vector2
	var state: State = State.IDLE
	var owner_pid: int = -1
	var result: String = ""
	var phase_end: float = 0.0

var w: SimWorld
var cfg: Dictionary
var boxes := {}  ## id -> Box


func _init(world: SimWorld) -> void:
	w = world
	cfg = w.constants.supplyBox
	for it in w.map.interactables:
		if it.kind == "box":
			var b := Box.new()
			b.id = it.id
			b.pos = it.pos
			boxes[b.id] = b


func update() -> void:
	for b in boxes.values():
		if b.state == State.ROLLING and w.time >= b.phase_end:
			b.state = State.OFFER
			b.phase_end = w.time + float(cfg.offerSec)
			w.emit({"type": "box_offer", "box": b.id, "pid": b.owner_pid, "weapon": b.result, "until": b.phase_end})
		elif b.state == State.OFFER and (w.time >= b.phase_end or not w.players.has(b.owner_pid)):
			_close(b)
			w.emit({"type": "box_expired", "box": b.id})


## Option shown to player p at box b (merged into PlayerSystem.interact_option).
## Current price: the fire-sale price while that power-up is active.
func price() -> int:
	var sale: Dictionary = w.constants.powerups.types.get("fireSale", {})
	if not sale.is_empty() and w.powerups.is_active("fireSale"):
		return int(sale.get("boxPrice", cfg.price))
	return int(cfg.price)


func option(b: Box, p: SimPlayer) -> Dictionary:
	match b.state:
		State.IDLE:
			return {"action": "box", "cost": price(), "label": "Supply Cache", "full": false}
		State.ROLLING:
			if b.owner_pid == p.id:
				return {"action": "wait", "cost": 0, "label": "Rolling...", "full": false, "busy": true}
		State.OFFER:
			if b.owner_pid == p.id:
				return {"action": "take", "item": b.result, "cost": 0, "label": str(w.defs.weapons[b.result].displayName), "full": false}
	return {"action": "wait", "cost": 0, "label": "Supply Cache in use", "full": false, "busy": true}


## Charges the price and starts a roll. Returns false (no charge) if nothing can be rolled.
func open(b: Box, p: SimPlayer) -> bool:
	if b.state != State.IDLE:
		return false
	var result := roll(p)
	if result == "":
		return false
	b.state = State.ROLLING
	b.owner_pid = p.id
	b.result = result
	b.phase_end = w.time + float(cfg.rollSec)
	var cost := price()
	w.add_currency(p, -cost, "supply_box")
	w.emit({"type": "box_opened", "box": b.id, "pid": p.id, "cost": cost, "until": b.phase_end})
	return true


func take(b: Box, p: SimPlayer) -> void:
	if b.state != State.OFFER or b.owner_pid != p.id:
		return
	w.player_sys.give_weapon(p, b.result)
	w.emit({"type": "box_taken", "box": b.id, "pid": p.id, "weapon": b.result})
	_close(b)


## Weighted pick over weapons with boxWeight > 0 that p does not own.
func roll(p: SimPlayer) -> String:
	var pool := {}
	var total := 0.0
	for id in w.defs.weapons:
		var wt := float(w.defs.weapons[id].get("boxWeight", 0))
		if wt > 0.0 and p.find_weapon(id) < 0:
			pool[id] = wt
			total += wt
	if total <= 0.0:
		return ""
	var r := w.rng.randf() * total
	var last := ""
	var ids := pool.keys()
	ids.sort()  # deterministic order across platforms (server mirrors this)
	for id in ids:
		last = id
		r -= pool[id]
		if r <= 0.0:
			return id
	return last


func _close(b: Box) -> void:
	b.state = State.IDLE
	b.owner_pid = -1
	b.result = ""
