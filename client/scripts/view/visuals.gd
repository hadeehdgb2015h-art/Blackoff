class_name Visuals
extends RefCounted
## Loads client-only presentation data (res://data/visuals.json).

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string("res://data/visuals.json")) == OK:
			_data = json.data
		else:
			push_error("visuals.json parse error: " + json.get_error_message())
			_data = {"weapons": {}, "zombies": {}, "players": {"colors": ["#888888"]}}
	return _data


static func weapon(id: String) -> Dictionary:
	return data().weapons.get(id, data().weapons.values()[0])


static func zombie(id: String) -> Dictionary:
	return data().zombies.get(id, data().zombies.values()[0])


static func v3(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


## Instantiates an art model if the integration path is set and exists.
static func try_model(path: String) -> Node3D:
	if path != "" and ResourceLoader.exists(path):
		var res := load(path)
		if res is PackedScene:
			return res.instantiate()
	return null


## A weapon as a world object (supply cache display): the viewmodel scene with
## arms hidden and the camera placement removed, or the procedural mesh.
static func weapon_world_node(id: String) -> Node3D:
	var node := try_model(weapon(id).get("model", ""))
	if node:
		var root := node.find_child("Root", true, false) as Node3D
		if root:
			root.transform = Transform3D.IDENTITY
		for n in ["ArmL", "ArmR"]:
			var arm := node.find_child(n, true, false) as Node3D
			if arm:
				arm.visible = false
		var ap := node.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap:
			ap.stop()
		return node
	var mi := MeshInstance3D.new()
	mi.mesh = FpRig.weapon_mesh(id)
	return mi
