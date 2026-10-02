class_name WeaponState
extends RefCounted
## A weapon instance owned by a player. Stats come from shared/weapons.json.

var id: String
var def: Dictionary
var mag: int
var reserve: int


static func create(weapon_id: String, weapon_def: Dictionary) -> WeaponState:
	var w := WeaponState.new()
	w.id = weapon_id
	w.def = weapon_def
	w.mag = int(weapon_def.magSize)
	w.reserve = int(weapon_def.reserveStart)
	return w


func can_reload() -> bool:
	return mag < int(def.magSize) and reserve > 0


## Moves rounds from reserve into the magazine.
func finish_reload() -> void:
	var need := int(def.magSize) - mag
	var take := mini(need, reserve)
	mag += take
	reserve -= take


func interval() -> float:
	return 60.0 / float(def.fireRateRpm)


func is_auto() -> bool:
	return def.fireMode == "auto"
