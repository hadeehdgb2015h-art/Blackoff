class_name SharedLoader
extends RefCounted
## Loads and cross-checks the shared JSON data (see /shared/README.md).
## Pure function, usable from autoloads, tests and tools.

const FILES := ["constants", "protocol", "weapons", "zombies", "waves", "perks"]


## Returns {constants, protocol, weapons, zombies, waves, perks, maps: {id: dict}, errors: PackedStringArray}.
static func load_all(dir: String = "res://shared/") -> Dictionary:
	var errors := PackedStringArray()
	var out := {}
	for file_name in FILES:
		out[file_name] = _read_json(dir + file_name + ".json", errors)
	out["weapons"] = out["weapons"].get("weapons", {})
	out["zombies"] = out["zombies"].get("zombies", {})
	out["perks"] = out["perks"].get("perks", {})
	var maps := {}
	var map_dir := dir + "maps/"
	for f in DirAccess.get_files_at(map_dir):
		if f.ends_with(".json"):
			var m := _read_json(map_dir + f, errors)
			if m.has("id"):
				maps[m["id"]] = m
	out["maps"] = maps
	if errors.is_empty():
		_cross_check(out, errors)
	out["errors"] = errors
	return out


static func _read_json(path: String, errors: PackedStringArray) -> Dictionary:
	if not FileAccess.file_exists(path):
		errors.append("missing " + path + " (run tools/sync_shared.sh)")
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		errors.append("%s: parse error line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return {}
	if typeof(json.data) != TYPE_DICTIONARY:
		errors.append(path + ": root must be an object")
		return {}
	return json.data


static func _cross_check(d: Dictionary, errors: PackedStringArray) -> void:
	var c: Dictionary = d["constants"]
	if not d["weapons"].has(c.player.startWeapon):
		errors.append("player.startWeapon '%s' missing from weapons" % c.player.startWeapon)
	if int(c.net.protocolVersion) != int(d["protocol"].get("protocolVersion", -1)):
		errors.append("protocol version mismatch between constants and protocol")
	if not d["maps"].has(c.maps.default):
		errors.append("default map '%s' missing from shared/maps" % c.maps.default)
	var boss: Dictionary = d["waves"].get("boss", {})
	if boss.is_empty() or not d["zombies"].has(str(boss.get("type", ""))):
		errors.append("waves.boss missing or names an unknown zombie")
	for entry in d["waves"].get("mix", []):
		for zid in entry.get("weights", {}).keys():
			if not d["zombies"].has(zid):
				errors.append("waves.mix references unknown zombie '%s'" % zid)
	for m in d["maps"].values():
		for it in m.get("interactables", []):
			if it.kind == "weapon" and not d["weapons"].has(it.get("item", "")):
				errors.append("map %s: interactable %s references unknown weapon" % [m.id, it.id])
			if it.kind == "perk" and not d["perks"].has(it.get("item", "")):
				errors.append("map %s: interactable %s references unknown perk" % [m.id, it.id])
