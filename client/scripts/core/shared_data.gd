extends Node
## Loads the repository-level shared JSON (constants, protocol, weapons,
## zombies, waves). The files are copied into res://shared/ by
## tools/sync_shared.sh before every export; the server reads the originals.

const SHARED_DIR := "res://shared/"
const FILES := ["constants", "protocol", "weapons", "zombies", "waves"]

var constants: Dictionary = {}
var protocol: Dictionary = {}
var weapons: Dictionary = {}
var zombies: Dictionary = {}
var waves: Dictionary = {}
var errors: PackedStringArray = []


func _ready() -> void:
	reload()


func reload() -> void:
	errors.clear()
	var data := {}
	for file_name in FILES:
		data[file_name] = _read_json(SHARED_DIR + file_name + ".json")
	constants = data["constants"]
	protocol = data["protocol"]
	weapons = data["weapons"].get("weapons", {})
	zombies = data["zombies"].get("zombies", {})
	waves = data["waves"]
	_cross_check()
	for e in errors:
		push_error("SharedData: " + e)


func is_valid() -> bool:
	return errors.is_empty()


func get_weapon(id: String) -> Dictionary:
	return weapons.get(id, {})


func get_zombie(id: String) -> Dictionary:
	return zombies.get(id, {})


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		errors.append("missing " + path + " (run tools/sync_shared.sh)")
		return {}
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(text) != OK:
		errors.append("%s: parse error line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return {}
	if typeof(json.data) != TYPE_DICTIONARY:
		errors.append(path + ": root must be an object")
		return {}
	return json.data


func _cross_check() -> void:
	if errors.size() > 0:
		return
	var start_weapon: String = constants.get("player", {}).get("startWeapon", "")
	if not weapons.has(start_weapon):
		errors.append("player.startWeapon '%s' missing from weapons" % start_weapon)
	if int(constants.get("net", {}).get("protocolVersion", -1)) != int(protocol.get("protocolVersion", -2)):
		errors.append("protocol version mismatch between constants and protocol")
	for entry in waves.get("mix", []):
		for zid in entry.get("weights", {}).keys():
			if not zombies.has(zid):
				errors.append("waves.mix references unknown zombie '%s'" % zid)
