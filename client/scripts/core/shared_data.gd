extends Node
## Autoload exposing the shared JSON data (loaded once at startup).
## The files are copied into res://shared/ by tools/sync_shared.sh before
## every export; the server reads the originals in /shared.

var data: Dictionary = {}
var constants: Dictionary = {}
var protocol: Dictionary = {}
var weapons: Dictionary = {}
var zombies: Dictionary = {}
var waves: Dictionary = {}
var maps: Dictionary = {}
var errors: PackedStringArray = []


func _ready() -> void:
	reload()


func reload() -> void:
	data = SharedLoader.load_all()
	constants = data.constants
	protocol = data.protocol
	weapons = data.weapons
	zombies = data.zombies
	waves = data.waves
	maps = data.maps
	errors = data.errors
	for e in errors:
		push_error("SharedData: " + e)


func is_valid() -> bool:
	return errors.is_empty()


func get_weapon(id: String) -> Dictionary:
	return weapons.get(id, {})


func get_zombie(id: String) -> Dictionary:
	return zombies.get(id, {})
