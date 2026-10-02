class_name SimPlayer
extends RefCounted
## Authoritative player state (local sim now, server later).

enum State { ALIVE, DOWNED, DEAD }

var id: int
var name: String
var pos := Vector2.ZERO
var prev_pos := Vector2.ZERO
var yaw: float = 0.0
var pitch: float = 0.0
var hp: float = 100.0
var max_hp: float = 100.0
var state: State = State.ALIVE
var currency: int = 0
var weapons: Array[WeaponState] = []
var slot: int = 0
var next_fire_time: float = 0.0
var reload_end: float = 0.0     ## 0 = not reloading
var switch_end: float = 0.0
var last_damage_time: float = -999.0
var downed_time: float = 0.0
var buttons_prev: int = 0
var moving: bool = false
var input := PlayerIntent.new()
# stats
var kills: int = 0
var headshots: int = 0
var shots_fired: int = 0


func weapon() -> WeaponState:
	return weapons[slot] if slot < weapons.size() else null


func find_weapon(id_: String) -> int:
	for i in weapons.size():
		if weapons[i].id == id_:
			return i
	return -1


func is_reloading() -> bool:
	return reload_end > 0.0


func is_alive() -> bool:
	return state == State.ALIVE
